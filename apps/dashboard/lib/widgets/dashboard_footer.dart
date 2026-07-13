import 'package:flutter/material.dart';

import '../config/brand.dart';
import '../config/build_info.dart';
import '../theme/app_theme.dart';
import 'scout_logo.dart';

class DashboardFooter extends StatelessWidget {
  const DashboardFooter({super.key, this.compact = false});

  final bool compact;

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

  Widget _versionChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Text(
          versionLabel,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary, letterSpacing: 0.2),
        ),
      );

  Widget _wide(int year) {
    return Row(
      children: [
        const ScoutLogo(compact: true, iconSize: 28),
        const SizedBox(width: 12),
        _versionChip(),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            Brand.slogan,
            style: const TextStyle(fontSize: 11, color: AppTheme.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text('© $year ${Brand.name}', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
      ],
    );
  }

  Widget _compact(int year) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const ScoutLogo(compact: true, iconSize: 24),
            const SizedBox(width: 8),
            _versionChip(),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${Brand.slogan} · © $year',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: AppTheme.muted),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
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
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              versionLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '© $year ${Brand.name} · ${Brand.slogan}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}
