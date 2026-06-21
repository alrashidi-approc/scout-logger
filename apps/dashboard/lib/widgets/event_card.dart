import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'detail_panel.dart';
import 'level_badge.dart';

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.onTap});

  final Map<String, dynamic> event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final type = event['type'] as String? ?? 'error';
    final category = event['category'] as String?;
    final occurred = DateTime.tryParse(event['occurredAt'] as String? ?? '');
    final time = occurred != null ? DateFormat('MMM d, yyyy · HH:mm:ss').format(occurred.toLocal()) : '—';
    final title = event['message']?.toString() ?? type;
    final release = event['release']?.toString() ?? '—';
    final device = event['deviceName']?.toString() ?? event['platform']?.toString() ?? '—';
    final route = event['route']?.toString() ?? '—';
    final url = event['networkUrl']?.toString() ?? '';
    final status = event['statusCode']?.toString() ?? '';
    final env = event['environment']?.toString() ?? '—';
    final isError = type == 'error' || type == 'crash' || type == 'network';
    final accent = type == 'crash' ? AppTheme.error : type == 'network' ? AppTheme.warning : AppTheme.error;
    final compact = MediaQuery.sizeOf(context).width < 720;

    final endpointLabel = url.isEmpty ? null : (status.isNotEmpty ? '$url ($status)' : url);
    final pills = <String>[
      if (release != '—') release,
      if (device != '—') device,
      if (route != '—') route,
      if (endpointLabel != null) endpointLabel,
    ];

    final flow = [
      if (device != '—') FlowItem(Icons.phone_android_outlined, 'Device', device),
      if (release != '—') FlowItem(Icons.verified_outlined, 'Release', release),
      if (route != '—') FlowItem(Icons.route_outlined, 'Screen', route),
      if (url.isNotEmpty) FlowItem(Icons.lan_outlined, 'Network', url),
    ];

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isError ? accent.withValues(alpha: 0.35) : AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(children: [
                Text(time, style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
              ]),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isError ? accent.withValues(alpha: 0.08) : AppTheme.panelElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isError ? accent.withValues(alpha: 0.2) : AppTheme.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  LevelBadge(type: type, level: event['level'] as String?, compact: true),
                  if (category != null && category.isNotEmpty) _pill(category.toUpperCase(), AppTheme.muted),
                ]),
                const SizedBox(height: 10),
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.text, height: 1.3)),
                if (pills.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: pills.map((p) => _pill(p, AppTheme.muted)).toList()),
                ],
              ]),
            ),
            if (flow.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: AppTheme.panelElevated, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
                  child: FlowStrip(items: flow, embedded: true),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Text('Environment: $env', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            ),
          ]),
        ),
      ),
    );
  }

  static Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppTheme.panelElevated, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.border)),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      );
}

class IssueCard extends StatelessWidget {
  const IssueCard({super.key, required this.issue, required this.onTap});

  final Map<String, dynamic> issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = issue['type'] as String? ?? 'error';
    final last = DateTime.tryParse(issue['lastSeenAt'] as String? ?? '');
    final lastLabel = last != null ? DateFormat.yMMMd().add_jm().format(last.toLocal()) : '—';
    final status = issue['status'] as String? ?? 'open';
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LevelBadge(type: type, compact: compact),
            SizedBox(width: compact ? 10 : 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(issue['title'] as String? ?? 'Unknown', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 14 : 15, color: AppTheme.text)),
                SizedBox(height: compact ? 6 : 8),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  _meta(Icons.repeat, '${issue['eventCount']} events'),
                  _meta(Icons.public, issue['topCountry'] as String? ?? '—'),
                  _meta(Icons.schedule, lastLabel),
                  if (status != 'open') _meta(Icons.flag_outlined, status),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.muted),
          ]),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.muted),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
        ],
      );
}
