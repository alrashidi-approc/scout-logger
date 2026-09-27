import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:scout_models/scout_models.dart';

import '../theme/app_theme.dart';

/// Public read-only uptime outage report (share token).
class SharedUptimeHistoryView extends StatelessWidget {
  const SharedUptimeHistoryView({
    super.key,
    required this.projectName,
    required this.days,
    required this.stats,
    required this.outages,
  });

  final String projectName;
  final int days;
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> outages;

  @override
  Widget build(BuildContext context) {
    final uptimePct = (stats['uptimePercent'] as num?)?.toDouble() ?? 100;
    final outageCount = (stats['outageCount'] as num?)?.toInt() ?? outages.length;
    final downMs = (stats['downMs'] as num?)?.toInt() ?? 0;
    final downLabel = _formatDuration(Duration(milliseconds: downMs));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(projectName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Server uptime · last $days days (Scout light ping)',
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatChip(label: 'Uptime', value: '${uptimePct.toStringAsFixed(1)}%'),
              _StatChip(label: 'Outages', value: '$outageCount'),
              _StatChip(label: 'Unavailable', value: downLabel),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Outages', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          if (outages.isEmpty)
            const Text(
              'No unavailable windows in this period.',
              style: TextStyle(color: AppTheme.muted),
            )
          else
            for (final o in outages) ...[
              _OutageTile(outage: o),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panelElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }
}

class _OutageTile extends StatelessWidget {
  const _OutageTile({required this.outage});
  final Map<String, dynamic> outage;

  @override
  Widget build(BuildContext context) {
    final url = outage['url']?.toString() ?? '';
    final started = DateTime.tryParse(outage['startedAt']?.toString() ?? '');
    final ended = DateTime.tryParse(outage['endedAt']?.toString() ?? '');
    final ongoing = outage['ongoing'] == true || ended == null;
    final durMs = (outage['durationMs'] as num?)?.toInt();
    final detail = outage['lastDetail']?.toString();
    final fmt = DateFormat.MMMd().add_jm();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(url, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text(
            [
              if (started != null) 'From ${fmt.format(started.toLocal())}',
              if (ongoing) 'ongoing' else 'to ${fmt.format(ended.toLocal())}',
              if (durMs != null) _formatDuration(Duration(milliseconds: durMs)),
            ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
          ],
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  if (d.inHours >= 24) {
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    return hours == 0 ? '${days}d' : '${days}d ${hours}h';
  }
  if (d.inHours >= 1) {
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
  }
  if (d.inMinutes >= 1) return '${d.inMinutes}m';
  return '${d.inSeconds}s';
}

/// Dashboard / shared outage list from API maps.
List<Map<String, dynamic>> uptimeOutagesFromJson(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
}

/// Convenience for typed outages when needed.
List<UptimeOutage> parseUptimeOutages(dynamic raw) => [
      for (final m in uptimeOutagesFromJson(raw)) UptimeOutage.fromJson(m),
    ];
