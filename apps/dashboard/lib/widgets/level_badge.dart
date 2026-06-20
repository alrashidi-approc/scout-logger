import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.type, this.level, this.compact = false});

  final String type;
  final String? level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final key = (level ?? type).toLowerCase();
    final (color, label) = switch (key) {
      'crash' || 'crashing' => (AppTheme.error, 'CRASH'),
      'network' => (AppTheme.warning, 'NETWORK'),
      'session' => (AppTheme.info, 'SESSION'),
      'span' || 'log' => (const Color(0xFF7C3AED), key.toUpperCase()),
      'info' => (AppTheme.info, 'INFO'),
      'warning' => (AppTheme.warning, 'WARN'),
      'success' => (AppTheme.success, 'OK'),
      _ => (AppTheme.primary, 'ERROR'),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: compact ? 10 : 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
    );
  }
}
