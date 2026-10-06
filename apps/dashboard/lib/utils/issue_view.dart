import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

String issueLevel(Map<String, dynamic> issue) {
  final level = (issue['level'] as String?)?.toLowerCase();
  if (level == 'error' || level == 'warning' || level == 'success' || level == 'info') return level!;

  final type = issue['type'] as String? ?? 'error';
  if (type == 'crash') return 'error';

  if (type == 'network') {
    final code = int.tryParse('${issue['statusCode'] ?? ''}');
    if (code != null) {
      if (code >= 400) return 'error';
      if (code >= 200 && code < 300) return 'success';
    }
    final title = (issue['title'] as String? ?? '').toLowerCase();
    if (title.contains('succeeded') || title.contains(' ok')) return 'success';
    if (title.contains('slow')) return 'warning';
    if (title.contains('no response') || title.contains('failed') || title.contains('http')) return 'error';
  }

  return type == 'error' ? 'error' : 'info';
}

bool issueErrorFocus(Map<String, dynamic> issue) =>
    issueLevel(issue) == 'error' || issue['type'] == 'crash';

bool issueWarningFocus(Map<String, dynamic> issue) => issueLevel(issue) == 'warning';

Color priorityColor(int priority) => priority >= 6
    ? AppTheme.error
    : priority >= 3
        ? AppTheme.warning
        : AppTheme.muted;

/// Top [max] suspect labels, e.g. `ios · 92%`, `v1.4.0 · 80%`.
List<String> suspectLabels(Map<String, dynamic> issue, {int max = 2}) => [
      for (final s in ((issue['suspects'] as List?) ?? const []).whereType<Map>().take(max))
        '${s['dimension'] == 'app_version' ? 'v' : ''}${s['value']} · ${(((s['share'] as num?) ?? 0) * 100).round()}%',
    ];

DateTime? _issueTime(Map<String, dynamic> issue, String key) => DateTime.tryParse(issue[key] as String? ?? '');

/// Triage inbox buckets; each issue lands in the first that matches (spike → new → regression → waiting),
/// keeping the incoming (priority) order.
({
  List<Map<String, dynamic>> spikes,
  List<Map<String, dynamic>> fresh,
  List<Map<String, dynamic>> regressions,
  List<Map<String, dynamic>> waiting,
}) triageSections(List<Map<String, dynamic>> issues, {required DateTime since}) {
  final spikes = <Map<String, dynamic>>[];
  final fresh = <Map<String, dynamic>>[];
  final regressions = <Map<String, dynamic>>[];
  final waiting = <Map<String, dynamic>>[];
  for (final i in issues) {
    final bucket = i['spike'] == true
        ? spikes
        : !(_issueTime(i, 'firstSeenAt')?.isBefore(since) ?? true)
            ? fresh
            : !(_issueTime(i, 'regressedAt')?.isBefore(since) ?? true)
                ? regressions
                : waiting;
    bucket.add(i);
  }
  return (spikes: spikes, fresh: fresh, regressions: regressions, waiting: waiting);
}

/// First seen, regressed or spiking after [lastVisit].
bool issueSinceVisit(Map<String, dynamic> issue, DateTime? lastVisit) =>
    lastVisit != null &&
    ['firstSeenAt', 'regressedAt', 'spikeAt'].any((k) => _issueTime(issue, k)?.isAfter(lastVisit) ?? false);

Color chartTypeColor(String type) => switch (type.toLowerCase()) {
      'error' || 'crash' => AppTheme.error,
      'network' => AppTheme.warning,
      'session' => AppTheme.info,
      'log' || 'span' => AppTheme.accentPurple,
      _ => AppTheme.primary,
    };
