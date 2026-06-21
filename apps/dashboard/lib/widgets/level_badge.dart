import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LevelBadge extends StatelessWidget {
  const LevelBadge({
    super.key,
    required this.type,
    this.level,
    this.compact = false,
    this.transportOnly = false,
  });

  final String type;
  final String? level;
  final bool compact;
  /// Show transport kind (error/crash/network/log) instead of severity level.
  final bool transportOnly;

  @override
  Widget build(BuildContext context) {
    if (transportOnly) {
      final (color, label) = _transportStyle(type);
      return _chip(color, label);
    }

    final key = (level ?? type).toLowerCase();
    final (color, label) = switch (key) {
      'crash' || 'crashing' => (AppTheme.error, 'CRASH'),
      'network' => (AppTheme.warning, 'NETWORK'),
      'session' => (AppTheme.info, 'SESSION'),
      'span' => (const Color(0xFF7C3AED), 'SPAN'),
      'log' => (const Color(0xFF7C3AED), 'LOG'),
      'info' => (AppTheme.info, 'INFO'),
      'warning' => (AppTheme.warning, 'WARN'),
      'success' => (AppTheme.success, 'OK'),
      'error' => (AppTheme.error, 'ERROR'),
      _ => (AppTheme.primary, key.toUpperCase()),
    };
    return _chip(color, label);
  }

  (Color, String) _transportStyle(String t) {
    return switch (t.toLowerCase()) {
      'crash' => (AppTheme.error, 'CRASH'),
      'network' => (AppTheme.warning, 'NET'),
      'session' => (AppTheme.info, 'SESS'),
      'log' || 'span' => (const Color(0xFF7C3AED), t.toUpperCase()),
      _ => (AppTheme.muted, t.toUpperCase()),
    };
  }

  Widget _chip(Color color, String label) => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: compact ? 10 : 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      );
}
