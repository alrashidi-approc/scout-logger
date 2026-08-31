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
    final healthCheck = {
      'script': script,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if (updatedBy != null) 'updatedBy': updatedBy,
    };
    final settings = {...current, 'healthCheck': healthCheck};

    await conn.execute(
      Sql.named('UPDATE projects SET settings = @settings::jsonb WHERE id = @id'),
      parameters: {'id': projectId, 'settings': jsonEncode(settings)},
    );
    return healthCheck;
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
