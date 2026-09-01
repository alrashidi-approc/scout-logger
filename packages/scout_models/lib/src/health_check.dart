class HealthCheckStats {
  const HealthCheckStats({
    required this.total,
    required this.completed,
    required this.ok,
    required this.fail,
    this.skipped = 0,
    this.pending = 0,
    this.timeout = 0,
  });

  final int total;
  final int completed;
  final int ok;
  final int fail;
  final int skipped;
  final int pending;
  final int timeout;

  Map<String, dynamic> toJson() => {
        'total': total,
        'completed': completed,
        'ok': ok,
        'fail': fail,
        if (skipped > 0) 'skipped': skipped,
        if (pending > 0) 'pending': pending,
        if (timeout > 0) 'timeout': timeout,
      };

  factory HealthCheckStats.fromJson(Map<String, dynamic> j) => HealthCheckStats(
        total: (j['total'] as num?)?.toInt() ?? 0,
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        ok: (j['ok'] as num?)?.toInt() ?? 0,
        fail: (j['fail'] as num?)?.toInt() ?? 0,
        skipped: (j['skipped'] as num?)?.toInt() ?? 0,
        pending: (j['pending'] as num?)?.toInt() ?? 0,
        timeout: (j['timeout'] as num?)?.toInt() ?? 0,
      );
}

class HealthCheckItem {
  const HealthCheckItem({
    required this.name,
    required this.status,
    this.url,
    this.latencyMs,
    this.detail,
  });

  final String name;
  final String status;
  final String? url;
  final int? latencyMs;
  final String? detail;

  bool get ok => status == 'ok';
  bool get skipped => status == 'skipped';
  bool get timedOut => status == 'timeout';

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status,
        if (url != null) 'url': url,
        if (latencyMs != null) 'latencyMs': latencyMs,
        if (detail != null) 'detail': detail,
      };

  factory HealthCheckItem.fromJson(Map<String, dynamic> j) => HealthCheckItem(
        name: j['name'] as String? ?? '',
        status: j['status'] as String? ?? 'fail',
        url: j['url'] as String?,
        latencyMs: (j['latencyMs'] as num?)?.toInt(),
        detail: j['detail'] as String?,
      );
}

class HealthCheckReport {
  const HealthCheckReport({
    required this.verdict,
    required this.summary,
    required this.checks,
    this.stats,
    this.current,
    this.timedOutAt,
    this.pending = const [],
    this.wafLearning,
    this.networkProbe,
  });

  final String verdict;
  final String summary;
  final List<HealthCheckItem> checks;
  final HealthCheckStats? stats;
  final String? current;
  final String? timedOutAt;
  final List<String> pending;
  final Map<String, dynamic>? wafLearning;
  final Map<String, dynamic>? networkProbe;

  int get okCount => checks.where((c) => c.ok).length;
  int get failCount => checks.where((c) => c.status == 'fail').length;
  int get timeoutCount => checks.where((c) => c.timedOut).length;

  Map<String, dynamic> toJson() => {
        'verdict': verdict,
        'summary': summary,
        'checks': checks.map((c) => c.toJson()).toList(),
        if (stats != null) 'stats': stats!.toJson(),
        if (current != null) 'current': current,
        if (timedOutAt != null) 'timedOutAt': timedOutAt,
        if (pending.isNotEmpty) 'pending': pending,
        if (wafLearning != null) 'wafLearning': wafLearning,
        if (networkProbe != null) 'networkProbe': networkProbe,
      };

  factory HealthCheckReport.fromJson(Map<String, dynamic> j) => HealthCheckReport(
        verdict: j['verdict'] as String? ?? 'unhealthy',
        summary: j['summary'] as String? ?? '',
        checks: ((j['checks'] as List?) ?? const [])
            .map((e) => HealthCheckItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        stats: j['stats'] is Map ? HealthCheckStats.fromJson(Map<String, dynamic>.from(j['stats'] as Map)) : null,
        current: j['current'] as String?,
        timedOutAt: j['timedOutAt'] as String?,
        pending: ((j['pending'] as List?) ?? const []).map((e) => '$e').toList(),
        wafLearning: j['wafLearning'] is Map
            ? Map<String, dynamic>.from(j['wafLearning'] as Map)
            : null,
        networkProbe: j['networkProbe'] is Map
            ? Map<String, dynamic>.from(j['networkProbe'] as Map)
            : null,
      );
}

class HealthCheckRun {
  const HealthCheckRun({
    required this.id,
    required this.projectId,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.exitCode,
    this.stdout,
    this.stderr,
    this.report,
    this.triggeredBy,
    this.durationMs,
  });

  final String id;
  final String projectId;
  final String status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final String? stdout;
  final String? stderr;
  final HealthCheckReport? report;
  final String? triggeredBy;
  final int? durationMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'status': status,
        'startedAt': startedAt.toUtc().toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toUtc().toIso8601String(),
        if (exitCode != null) 'exitCode': exitCode,
        if (stdout != null) 'stdout': stdout,
        if (stderr != null) 'stderr': stderr,
        if (report != null) 'report': report!.toJson(),
        if (triggeredBy != null) 'triggeredBy': triggeredBy,
        if (durationMs != null) 'durationMs': durationMs,
      };

  factory HealthCheckRun.fromJson(Map<String, dynamic> j) => HealthCheckRun(
        id: j['id'] as String? ?? '',
        projectId: j['projectId'] as String? ?? '',
        status: j['status'] as String? ?? 'failed',
        startedAt: DateTime.tryParse(j['startedAt'] as String? ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        finishedAt: DateTime.tryParse(j['finishedAt'] as String? ?? '')?.toUtc(),
        exitCode: (j['exitCode'] as num?)?.toInt(),
        stdout: j['stdout'] as String?,
        stderr: j['stderr'] as String?,
        report: j['report'] is Map ? HealthCheckReport.fromJson(Map<String, dynamic>.from(j['report'] as Map)) : null,
        triggeredBy: j['triggeredBy'] as String?,
        durationMs: (j['durationMs'] as num?)?.toInt(),
      );
}
