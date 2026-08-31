import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scout_models/scout_models.dart';

import '../config/env_file.dart';
import '../config/server_config.dart';
import '../store/health_check_store.dart';
import '../store/scout_store.dart';

const healthCheckTimeout = Duration(seconds: 300);

/// Dart VM for health scripts. Production uses bundled /opt/dart; dev uses `dart run bin/server.dart`.
String resolveDartExecutable() {
  const bundled = '/opt/dart/bin/dart';
  if (File(bundled).existsSync()) return bundled;
  final fromEnv = Platform.environment['SCOUT_DART_BIN'];
  if (fromEnv != null && fromEnv.isNotEmpty && File(fromEnv).existsSync()) return fromEnv;
  final exe = Platform.resolvedExecutable;
  if (exe.endsWith('dart') || exe.contains('/dart-sdk/') || exe.contains('/dart/')) return exe;
  return 'dart';
}

HealthCheckReport? parseHealthCheckReportLine(String line) {
  var raw = line.trim();
  if (raw.isEmpty) return null;
  const prefix = 'SCOUT_REPORT:';
  if (raw.startsWith(prefix)) raw = raw.substring(prefix.length).trim();
  try {
    final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final verdict = decoded['verdict']?.toString();
    final summary = decoded['summary']?.toString();
    if (verdict == null || summary == null) return null;
    return HealthCheckReport.fromJson(decoded);
  } catch (_) {
    return null;
  }
}

/// Full decoded report map (preserves fields not in [HealthCheckReport]).
Map<String, dynamic>? parseHealthCheckReportRaw(String line) {
  var raw = line.trim();
  if (raw.isEmpty) return null;
  const prefix = 'SCOUT_REPORT:';
  if (raw.startsWith(prefix)) raw = raw.substring(prefix.length).trim();
  try {
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  } catch (_) {
    return null;
  }
}

/// Picks the richest report from stdout (most checks, or last valid line).
HealthCheckReport? parseHealthCheckReport(String stdout) {
  HealthCheckReport? best;
  for (final line in stdout.split('\n')) {
    final report = parseHealthCheckReportLine(line);
    if (report == null) continue;
    if (best == null || report.checks.length >= best.checks.length) best = report;
  }
  return best;
}

HealthCheckReport _timeoutReport(HealthCheckReport? partial, {required int limitSec}) {
  if (partial == null) {
    return HealthCheckReport(
      verdict: 'unhealthy',
      summary: 'Script exceeded ${limitSec}s with no progress output',
      checks: const [],
      timedOutAt: 'script',
    );
  }
  final at = partial.current ?? partial.timedOutAt ?? 'unknown';
  return HealthCheckReport(
    verdict: partial.okCount > 0 ? 'degraded' : 'unhealthy',
    summary: 'Timed out at $at — ${partial.checks.length} check(s) completed before ${limitSec}s limit',
    checks: partial.checks,
    stats: partial.stats,
    current: partial.current,
    timedOutAt: at,
    pending: partial.pending,
  );
}

class HealthCheckRunner {
  HealthCheckRunner(this.store, this.scoutStore, this.config);

  final HealthCheckStore store;
  final ScoutStore scoutStore;
  final ServerConfig config;

  Future<void> _publishShareSnapshot(
    String projectId,
    Map<String, dynamic> run,
    String? triggeredBy,
  ) async {
    final report = run['report'];
    if (report == null) return;
    await scoutStore.upsertHealthCheckShareSnapshot(
      projectId: projectId,
      createdBy: triggeredBy,
      snapshot: {
        'runId': run['id'],
        'status': run['status'],
        if (run['startedAt'] != null) 'startedAt': run['startedAt'],
        if (run['finishedAt'] != null) 'finishedAt': run['finishedAt'],
        if (run['durationMs'] != null) 'durationMs': run['durationMs'],
        'report': report is Map ? Map<String, dynamic>.from(report) : report,
      },
    );
  }

  Future<Map<String, dynamic>> run(String projectId, {String? triggeredBy}) async {
    if (await store.hasRunningRun(projectId)) {
      throw StateError('A health check is already running for this project');
    }

    final scriptMeta = await store.getScript(projectId);
    final script = scriptMeta?['script'] as String?;
    if (script == null || script.trim().isEmpty) {
      throw ArgumentError('No health check script saved for this project');
    }

    final runId = await store.createRun(projectId: projectId, triggeredBy: triggeredBy);
    final sw = Stopwatch()..start();
    Directory? tempDir;
    Process? process;

    try {
      tempDir = await Directory.systemTemp.createTemp('scout-health-$projectId-');
      final scriptFile = File('${tempDir.path}/health_check.dart');
      await scriptFile.writeAsString(script);

      final env = EnvFile.load().values;
      process = await Process.start(
        resolveDartExecutable(),
        ['run', scriptFile.path],
        workingDirectory: tempDir.path,
        environment: {
          ...env,
          'SCOUT_PROJECT_ID': projectId,
          'SCOUT_PUBLIC_URL': config.publicUrl,
        },
        runInShell: false,
      );

      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();
      HealthCheckReport? latestReport;
      Map<String, dynamic>? latestReportRaw;

      final stdoutDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdoutBuf.writeln(line);
        final raw = parseHealthCheckReportRaw(line);
        if (raw != null) latestReportRaw = raw;
        final report = parseHealthCheckReportLine(line);
        if (report != null) latestReport = report;
      });

      final stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => stderrBuf.writeln(line));

      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(healthCheckTimeout);
      } on TimeoutException {
        process.kill(ProcessSignal.sigterm);
        try {
          exitCode = await process.exitCode.timeout(const Duration(seconds: 3));
        } catch (_) {
          process.kill(ProcessSignal.sigkill);
          exitCode = -1;
        }
        sw.stop();
        await stdoutDone.cancel();
        await stderrDone.cancel();
        final stdoutStr = stdoutBuf.toString();
        final stderrStr = stderrBuf.toString();
        final partial = latestReport ?? parseHealthCheckReport(stdoutStr);
        final report = _timeoutReport(partial, limitSec: healthCheckTimeout.inSeconds);
        await store.finishRun(
          runId: runId,
          status: 'timeout',
          exitCode: exitCode,
          stdout: stdoutStr.isEmpty ? null : stdoutStr,
          stderr: stderrStr.isEmpty ? 'Script exceeded ${healthCheckTimeout.inSeconds}s timeout' : stderrStr.toString(),
          report: report,
          reportJson: latestReportRaw ?? report.toJson(),
          durationMs: sw.elapsedMilliseconds,
        );
        final timedRun = await store.getRun(projectId, runId);
        if (timedRun != null) {
          await _publishShareSnapshot(projectId, timedRun, triggeredBy);
        }
        return timedRun ?? {'id': runId, 'status': 'timeout', 'report': report.toJson()};
      }

      sw.stop();
      await stdoutDone.cancel();
      await stderrDone.cancel();

      final stdoutStr = stdoutBuf.toString();
      final stderrStr = stderrBuf.toString();
      final report = latestReport ?? parseHealthCheckReport(stdoutStr);
      final status = report != null ? 'success' : 'failed';

      await store.finishRun(
        runId: runId,
        status: status,
        exitCode: exitCode,
        stdout: stdoutStr.isEmpty ? null : stdoutStr,
        stderr: stderrStr.isEmpty ? null : stderrStr.toString(),
        report: report,
        reportJson: latestReportRaw ?? report?.toJson(),
        durationMs: sw.elapsedMilliseconds,
      );

      final finishedRun = await store.getRun(projectId, runId);
      if (finishedRun != null && report != null) {
        await _publishShareSnapshot(projectId, finishedRun, triggeredBy);
      }
      return finishedRun ?? {'id': runId, 'status': status};
    } catch (e) {
      sw.stop();
      process?.kill(ProcessSignal.sigterm);
      await store.finishRun(
        runId: runId,
        status: 'failed',
        stderr: '$e',
        durationMs: sw.elapsedMilliseconds,
      );
      rethrow;
    } finally {
      try {
        await tempDir?.delete(recursive: true);
      } catch (_) {}
    }
  }
}
