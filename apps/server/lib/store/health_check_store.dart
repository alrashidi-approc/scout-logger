import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';

import '../db/scout_db.dart';
import '../util/ids.dart';

const maxHealthCheckScriptBytes = 128 * 1024;

class HealthCheckStore {
  HealthCheckStore(this.db);

  final ScoutDb db;

  Future<Map<String, dynamic>?> getScript(String projectId) async {
    final hc = await _healthCheckSettings(projectId);
    if (hc == null) return null;
    return {
      if (hc['script'] != null) 'script': hc['script'],
      if (hc['updatedAt'] != null) 'updatedAt': hc['updatedAt'],
      if (hc['updatedBy'] != null) 'updatedBy': hc['updatedBy'],
    };
  }

  Future<UptimeMonitorConfig> getUptime(String projectId) async {
    final hc = await _healthCheckSettings(projectId);
    final raw = hc?['uptime'];
    return UptimeMonitorConfig.fromJson(raw is Map ? Map<String, dynamic>.from(raw) : null);
  }

  Future<Map<String, dynamic>?> _healthCheckSettings(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named("SELECT settings->'healthCheck' FROM projects WHERE id = @id"),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) return null;
    final raw = rows.first[0];
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> saveScript({
    required String projectId,
    required String script,
    String? updatedBy,
  }) async {
    if (script.trim().isEmpty) throw ArgumentError('Script cannot be empty');
    if (utf8.encode(script).length > maxHealthCheckScriptBytes) {
      throw ArgumentError('Script exceeds ${maxHealthCheckScriptBytes ~/ 1024} KB limit');
    }

    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT settings FROM projects WHERE id = @id FOR UPDATE'),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) throw ArgumentError('Project not found');

    final current = rows.first[0] is Map ? Map<String, dynamic>.from(rows.first[0] as Map) : <String, dynamic>{};
    final existing = current['healthCheck'] is Map
        ? Map<String, dynamic>.from(current['healthCheck'] as Map)
        : <String, dynamic>{};
    final healthCheck = {
      ...existing,
      'script': script,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if (updatedBy != null) 'updatedBy': updatedBy,
    };
    // jsonb_set only the healthCheck object — never rewrite whole settings.
    await conn.execute(
      Sql.named('''
        UPDATE projects SET settings = jsonb_set(
          COALESCE(settings, '{}'::jsonb),
          '{healthCheck}',
          @hc::jsonb,
          true
        )
        WHERE id = @id
      '''),
      parameters: {'id': projectId, 'hc': jsonEncode(healthCheck)},
    );
    return {
      'script': script,
      'updatedAt': healthCheck['updatedAt'],
      if (updatedBy != null) 'updatedBy': updatedBy,
    };
  }

  Future<UptimeMonitorConfig> saveUptime(String projectId, UptimeMonitorConfig config) async {
    if (config.enabled && !config.hasUrl) {
      throw ArgumentError('Enter at least one valid http(s) URL to enable uptime monitoring');
    }
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT settings FROM projects WHERE id = @id FOR UPDATE'),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) throw ArgumentError('Project not found');

    final current = rows.first[0] is Map ? Map<String, dynamic>.from(rows.first[0] as Map) : <String, dynamic>{};
    final existing = current['healthCheck'] is Map
        ? Map<String, dynamic>.from(current['healthCheck'] as Map)
        : <String, dynamic>{};
    final cleaned = config.copyWith(
      targets: [
        for (final t in config.targets)
          if (t.url.trim().isNotEmpty) t.copyWith(url: t.url.trim()),
      ],
    );
    existing['uptime'] = cleaned.toJson();
    // Patch healthCheck only so Project Settings / notification saves can't race-wipe URLs.
    await conn.execute(
      Sql.named('''
        UPDATE projects SET settings = jsonb_set(
          COALESCE(settings, '{}'::jsonb),
          '{healthCheck}',
          @hc::jsonb,
          true
        )
        WHERE id = @id
      '''),
      parameters: {'id': projectId, 'hc': jsonEncode(existing)},
    );
    return cleaned;
  }

  /// Projects with uptime monitoring enabled and a URL configured.
  Future<List<({String id, String name, UptimeMonitorConfig uptime})>> allEnabledUptime() async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, name, settings->'healthCheck'->'uptime'
        FROM projects
        WHERE settings->'healthCheck'->'uptime'->>'enabled' = 'true'
      '''),
    );
    final out = <({String id, String name, UptimeMonitorConfig uptime})>[];
    for (final r in rows) {
      final uptime = UptimeMonitorConfig.fromJson(
        r[2] is Map ? Map<String, dynamic>.from(r[2] as Map) : null,
      );
      if (!uptime.enabled || !uptime.hasUrl) continue;
      out.add((id: r[0] as String, name: r[1] as String? ?? r[0] as String, uptime: uptime));
    }
    return out;
  }

  Future<String> createRun({required String projectId, String? triggeredBy}) async {
    final id = newId();
    final conn = await db.connect();
    await conn.execute(
      Sql.named('''
        INSERT INTO health_check_runs (id, project_id, status, triggered_by)
        VALUES (@id, @pid, 'running', @by)
      '''),
      parameters: {'id': id, 'pid': projectId, 'by': triggeredBy},
    );
    return id;
  }

  Future<bool> hasRunningRun(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named("SELECT 1 FROM health_check_runs WHERE project_id = @pid AND status = 'running' LIMIT 1"),
      parameters: {'pid': projectId},
    );
    return rows.isNotEmpty;
  }

  Future<void> finishRun({
    required String runId,
    required String status,
    int? exitCode,
    String? stdout,
    String? stderr,
    HealthCheckReport? report,
    Map<String, dynamic>? reportJson,
    required int durationMs,
  }) async {
    final conn = await db.connect();
    await conn.execute(
      Sql.named('''
        UPDATE health_check_runs SET
          status = @status,
          finished_at = now(),
          exit_code = @code,
          stdout = @out,
          stderr = @err,
          report = @report::jsonb,
          duration_ms = @dur
        WHERE id = @id
      '''),
      parameters: {
        'id': runId,
        'status': status,
        'code': exitCode,
        'out': stdout,
        'err': stderr,
        'report': reportJson != null
            ? jsonEncode(reportJson)
            : (report == null ? null : jsonEncode(report.toJson())),
        'dur': durationMs,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listRuns(String projectId, {int limit = 20}) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, project_id, status, started_at, finished_at, exit_code,
               report, triggered_by, duration_ms
        FROM health_check_runs
        WHERE project_id = @pid
        ORDER BY started_at DESC
        LIMIT @lim
      '''),
      parameters: {'pid': projectId, 'lim': limit.clamp(1, 100)},
    );
    return rows.map(_runSummary).toList();
  }

  Future<Map<String, dynamic>?> getRun(String projectId, String runId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, project_id, status, started_at, finished_at, exit_code,
               stdout, stderr, report, triggered_by, duration_ms
        FROM health_check_runs
        WHERE project_id = @pid AND id = @id
      '''),
      parameters: {'pid': projectId, 'id': runId},
    );
    if (rows.isEmpty) return null;
    return _runDetail(rows.first);
  }

  Map<String, dynamic> _runSummary(ResultRow row) {
    final report = row[6];
    return {
      'id': row[0],
      'projectId': row[1],
      'status': row[2],
      'startedAt': (row[3] as DateTime).toUtc().toIso8601String(),
      if (row[4] != null) 'finishedAt': (row[4] as DateTime).toUtc().toIso8601String(),
      if (row[5] != null) 'exitCode': row[5],
      if (report is Map) 'report': Map<String, dynamic>.from(report),
      if (row[7] != null) 'triggeredBy': row[7],
      if (row[8] != null) 'durationMs': row[8],
    };
  }

  Map<String, dynamic> _runDetail(ResultRow row) {
    final report = row[8];
    return {
      'id': row[0],
      'projectId': row[1],
      'status': row[2],
      'startedAt': (row[3] as DateTime).toUtc().toIso8601String(),
      if (row[4] != null) 'finishedAt': (row[4] as DateTime).toUtc().toIso8601String(),
      if (row[5] != null) 'exitCode': row[5],
      if (row[6] != null) 'stdout': row[6],
      if (row[7] != null) 'stderr': row[7],
      if (report is Map) 'report': Map<String, dynamic>.from(report),
      if (row[9] != null) 'triggeredBy': row[9],
      if (row[10] != null) 'durationMs': row[10],
    };
  }
}
