/// Per-project raw event retention — rollups are kept forever.
class ProjectRetentionConfig {
  const ProjectRetentionConfig({
    this.enabled = true,
    this.routineDays = 30,
    this.errorDays = 90,
  });

  static const minDays = 1;
  static const maxRoutineDays = 365;
  static const maxErrorDays = 730;

  /// Auto-delete routine noise (logs, sessions, spans, success network).
  final bool enabled;

  /// Days to keep non-error, non-issue raw events.
  final int routineDays;

  /// Days to keep errors/crashes/issue-linked raw events. 0 = keep forever.
  final int errorDays;

  factory ProjectRetentionConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const ProjectRetentionConfig();
    return ProjectRetentionConfig(
      enabled: json['enabled'] as bool? ?? true,
      routineDays: clampRetentionDays(json['routineDays'], defaultValue: 30, max: maxRoutineDays),
      errorDays: clampErrorDays(json['errorDays']),
    );
  }

  ProjectRetentionConfig mergePatch(Map<String, dynamic> patch) {
    return ProjectRetentionConfig(
      enabled: patch.containsKey('enabled') ? patch['enabled'] as bool? ?? enabled : enabled,
      routineDays: patch.containsKey('routineDays')
          ? clampRetentionDays(patch['routineDays'], defaultValue: routineDays, max: maxRoutineDays)
          : routineDays,
      errorDays: patch.containsKey('errorDays') ? clampErrorDays(patch['errorDays']) : errorDays,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'routineDays': routineDays,
        'errorDays': errorDays,
      };

  Map<String, dynamic> toClientJson() => toJson();
}

int clampRetentionDays(dynamic raw, {required int defaultValue, required int max}) {
  final n = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  if (n == null || n < ProjectRetentionConfig.minDays) return defaultValue;
  return n.clamp(ProjectRetentionConfig.minDays, max);
}

int clampErrorDays(dynamic raw) {
  if (raw == null) return 90;
  final n = raw is int ? raw : int.tryParse(raw.toString());
  if (n == null || n < 0) return 90;
  if (n == 0) return 0;
  return n.clamp(ProjectRetentionConfig.minDays, ProjectRetentionConfig.maxErrorDays);
}

ProjectRetentionConfig retentionFromSettings(Map<String, dynamic> settings) {
  final raw = settings['retention'];
  return ProjectRetentionConfig.fromJson(raw is Map ? Map<String, dynamic>.from(raw) : null);
}
