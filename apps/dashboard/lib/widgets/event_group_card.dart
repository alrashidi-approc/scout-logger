import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'level_badge.dart';

class EventGroupCard extends StatelessWidget {
  const EventGroupCard({super.key, required this.group, this.onTap});

  final Map<String, dynamic> group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final type = group['type'] as String? ?? 'log';
    final level = (group['level'] as String?)?.toLowerCase();
    final effectiveLevel = level ?? (type == 'log' || type == 'span' || type == 'session' ? 'info' : 'error');
    final title = group['title']?.toString() ?? group['key']?.toString() ?? type;
    final count = (group['count'] as num?)?.toInt() ?? 0;
    final last = DateTime.tryParse(group['lastSeenAt'] as String? ?? '');
    final first = DateTime.tryParse(group['firstSeenAt'] as String? ?? '');
    final lastLabel = last != null ? DateFormat('MMM d · HH:mm').format(last.toLocal()) : '—';
    final firstLabel = first != null ? DateFormat('MMM d').format(first.toLocal()) : null;
    final issueId = group['issueId']?.toString();
    final compact = MediaQuery.sizeOf(context).width < 720;
    final hot = effectiveLevel == 'error' || type == 'crash';

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: hot ? AppTheme.error.withValues(alpha: 0.06) : AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hot ? AppTheme.error.withValues(alpha: 0.45) : AppTheme.border,
          width: hot ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LevelBadge(type: type, level: effectiveLevel),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          '$count event${count == 1 ? '' : 's'}',
                          'last $lastLabel',
                          if (firstLabel != null) 'first $firstLabel',
                          if (issueId != null && issueId.isNotEmpty) 'linked issue',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
