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

/// Light automatic reachability check (not the full health script).
const kUptimeMonitorIntervalMinutes = 10;
const kDefaultUptimeMonitorEnabled = false;

bool _isHttpUrl(String raw) {
  final u = raw.trim();
  if (u.isEmpty) return false;
  final uri = Uri.tryParse(u);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

/// One watched server URL + last probe result.
class UptimeTarget {
  const UptimeTarget({
    required this.url,
    this.lastStatus,
    this.lastCheckedAt,
    this.lastLatencyMs,
    this.lastDetail,
  });

  final String url;
  final String? lastStatus;
  final DateTime? lastCheckedAt;
  final int? lastLatencyMs;
  final String? lastDetail;

  bool get isValid => _isHttpUrl(url);

  factory UptimeTarget.fromJson(Map<String, dynamic> json) => UptimeTarget(
        url: json['url']?.toString().trim() ?? '',
        lastStatus: json['lastStatus']?.toString(),
        lastCheckedAt: DateTime.tryParse(json['lastCheckedAt']?.toString() ?? '')?.toUtc(),
        lastLatencyMs: (json['lastLatencyMs'] as num?)?.toInt(),
        lastDetail: json['lastDetail']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (lastStatus != null) 'lastStatus': lastStatus,
        if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt!.toUtc().toIso8601String(),
        if (lastLatencyMs != null) 'lastLatencyMs': lastLatencyMs,
        if (lastDetail != null) 'lastDetail': lastDetail,
      };

  UptimeTarget copyWith({
    String? url,
    String? lastStatus,
    DateTime? lastCheckedAt,
    int? lastLatencyMs,
    String? lastDetail,
  }) =>
      UptimeTarget(
        url: url ?? this.url,
        lastStatus: lastStatus ?? this.lastStatus,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        lastLatencyMs: lastLatencyMs ?? this.lastLatencyMs,
        lastDetail: lastDetail ?? this.lastDetail,
      );
}

class UptimeMonitorConfig {
  const UptimeMonitorConfig({
    this.enabled = kDefaultUptimeMonitorEnabled,
    this.targets = const [],
  });

  final bool enabled;
  final List<UptimeTarget> targets;

  /// Valid http(s) targets only.
  List<UptimeTarget> get validTargets => targets.where((t) => t.isValid).toList();

  bool get hasUrl => validTargets.isNotEmpty;

  /// Convenience for single-URL UIs / legacy callers.
  String get url => validTargets.isEmpty ? '' : validTargets.first.url;

  /// Newline-separated URLs for a simple textarea.
  String get urlsText => targets.map((t) => t.url).where((u) => u.trim().isNotEmpty).join('\n');

  factory UptimeMonitorConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const UptimeMonitorConfig();
    final enabled = json['enabled'] == true;
    final rawTargets = json['targets'];
    if (rawTargets is List && rawTargets.isNotEmpty) {
      final targets = rawTargets
          .whereType<Map>()
          .map((e) => UptimeTarget.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.url.isNotEmpty)
          .toList();
      return UptimeMonitorConfig(enabled: enabled, targets: targets);
    }
    // Legacy single-url shape.
    final legacyUrl = json['url']?.toString().trim() ?? '';
    if (legacyUrl.isEmpty) return UptimeMonitorConfig(enabled: enabled);
    return UptimeMonitorConfig(
      enabled: enabled,
      targets: [
        UptimeTarget(
          url: legacyUrl,
          lastStatus: json['lastStatus']?.toString(),
          lastCheckedAt: DateTime.tryParse(json['lastCheckedAt']?.toString() ?? '')?.toUtc(),
          lastLatencyMs: (json['lastLatencyMs'] as num?)?.toInt(),
          lastDetail: json['lastDetail']?.toString(),
        ),
      ],
    );
  }

  /// Build from enable flag + newline / comma separated URL text (keeps prior results when URL matches).
  factory UptimeMonitorConfig.fromUrlsText({
    required bool enabled,
    required String text,
    List<UptimeTarget> previous = const [],
  }) {
    final prevByUrl = {for (final t in previous) t.url.trim(): t};
    final seen = <String>{};
    final targets = <UptimeTarget>[];
    for (final line in text.split(RegExp(r'[\n,]+'))) {
      final u = line.trim();
      if (u.isEmpty || !seen.add(u)) continue;
      final prev = prevByUrl[u];
      targets.add(prev?.copyWith(url: u) ?? UptimeTarget(url: u));
    }
    return UptimeMonitorConfig(enabled: enabled, targets: targets);
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'targets': targets.map((t) => t.toJson()).toList(),
      };

  UptimeMonitorConfig copyWith({
    bool? enabled,
    List<UptimeTarget>? targets,
  }) =>
      UptimeMonitorConfig(
        enabled: enabled ?? this.enabled,
        targets: targets ?? this.targets,
      );
}

/// True when we should page: first failure, or transition from ok → down.
bool uptimeShouldAlert({required String? previousStatus, required String newStatus}) {
  if (newStatus != 'down') return false;
  return previousStatus != 'down';
}
