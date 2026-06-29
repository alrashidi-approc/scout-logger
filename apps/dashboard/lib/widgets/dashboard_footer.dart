import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'scout_logo.dart';

class DashboardFooter extends StatelessWidget {
  const DashboardFooter({super.key, this.compact = false});

  final bool compact;

  static const _version = '0.1.1';

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24, vertical: compact ? 12 : 14),
      decoration: const BoxDecoration(
        color: AppTheme.panel,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: compact ? _compact(year) : _wide(year),
    );
  }

  Widget _wide(int year) {
    return Row(
      children: [
        const ScoutLogo(compact: true, iconSize: 28),
        const SizedBox(width: 12),
        Text('v$_version', style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600)),
        const SizedBox(width: 16),
        const Text('Mobile observability', style: TextStyle(fontSize: 11, color: AppTheme.muted)),
        const Spacer(),
        Text('© $year Scout Logger', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
      ],
    );
  }

  Widget _compact(int year) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const ScoutLogo(compact: true, iconSize: 24),
        const SizedBox(width: 8),
        Text('v$_version · © $year', style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
      ],
    );
  }
}

/// Slim footer for auth screens (login / signup).
class AuthFooter extends StatelessWidget {
  const AuthFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        '© $year Scout Logger · Mobile observability',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: AppTheme.muted),
      ),
    );
  }
}
