import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../utils/event_view.dart';
import '../utils/network_readable.dart';
import 'level_badge.dart';

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.onTap});

  final Map<String, dynamic> event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final type = event['type'] as String? ?? 'error';
    final occurred = DateTime.tryParse(event['occurredAt'] as String? ?? '');
    final time = occurred != null ? DateFormat('MMM d · HH:mm:ss').format(occurred.toLocal()) : '—';
    final payload = event['payload'] is Map ? Map<String, dynamic>.from(event['payload'] as Map) : <String, dynamic>{};
    final network = payload['network'] is Map ? Map<String, dynamic>.from(payload['network'] as Map) : <String, dynamic>{};
    final readable = network.isNotEmpty ? networkReadableFrom(network) : <String, dynamic>{};
    final networkLabel = str(readable['outcomeLabel']);
    final meta = [type, if (networkLabel != null) networkLabel, event['country'] ?? '—', event['release'] ?? '—'].join(' · ');
    final title = str(readable['title']) ?? event['message']?.toString() ?? type;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(time, style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600)),
              const Spacer(),
              LevelBadge(type: type, compact: true),
            ]),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.text),
            ),
            const SizedBox(height: 6),
            Text(meta, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
          ]),
        ),
      ),
    );
  }
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

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LevelBadge(type: type),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(issue['title'] as String? ?? 'Unknown', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
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
