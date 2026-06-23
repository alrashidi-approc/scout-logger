import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SdkHealthCard extends StatelessWidget {
  const SdkHealthCard({super.key, required this.health, this.onOpenSettings});

  final Map<String, dynamic> health;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (health.isEmpty) return const SizedBox.shrink();

    final hints = health['hints'] is List ? [for (final h in health['hints'] as List) '$h'] : <String>[];
    final byLevel = health['byLevel'] is Map ? Map<String, dynamic>.from(health['byLevel'] as Map) : <String, dynamic>{};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Text('SDK data quality', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            if (onOpenSettings != null)
              TextButton(onPressed: onOpenSettings, child: const Text('Settings')),
          ]),
          const SizedBox(height: 6),
          const Text('How complete mobile events are in the last period.', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Session ID', health['withSessionPct']),
              _metric('Install ID', health['withInstallPct']),
              _metric('Screen trail', health['withScreenTrailPct']),
              _metric('Nav type', health['withNavigationTypePct']),
            ],
          ),
          if (byLevel.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Events by level', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in byLevel.entries)
                  Chip(
                    label: Text('${e.key.toUpperCase()} · ${e.value}'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (hints.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final hint in hints)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.lightbulb_outline, size: 16, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(hint, style: const TextStyle(fontSize: 13, color: AppTheme.muted))),
                ]),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _metric(String label, dynamic pct) {
    final v = pct is num ? pct.toDouble() : double.tryParse('$pct') ?? 0;
    final color = v >= 80 ? AppTheme.success : v >= 50 ? AppTheme.warning : AppTheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600)),
        Text('${v.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}
