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

Color chartTypeColor(String type) => switch (type.toLowerCase()) {
      'error' || 'crash' => AppTheme.error,
      'network' => AppTheme.warning,
      'session' => AppTheme.info,
      'log' || 'span' => AppTheme.accentPurple,
      _ => AppTheme.primary,
    };
