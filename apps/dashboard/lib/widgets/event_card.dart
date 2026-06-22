import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../utils/issue_view.dart';
import '../utils/user_identity.dart';
import 'detail_panel.dart';
import 'level_badge.dart';

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.onTap});

  final Map<String, dynamic> event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final type = event['type'] as String? ?? 'error';
    final level = (event['level'] as String?)?.toLowerCase();
    final category = event['category'] as String?;
    final effectiveLevel = level ?? (type == 'log' || type == 'span' ? 'info' : 'error');
    final occurred = DateTime.tryParse(event['occurredAt'] as String? ?? '');
    final time = occurred != null ? DateFormat('MMM d, yyyy · HH:mm:ss').format(occurred.toLocal()) : '—';
    final title = event['message']?.toString() ?? type;
    final release = event['release']?.toString() ?? '—';
    final device = event['deviceName']?.toString() ?? event['platform']?.toString() ?? '—';
    final route = event['route']?.toString() ?? '—';
    final url = event['networkUrl']?.toString() ?? '';
    final status = event['statusCode']?.toString() ?? '';
    final env = event['environment']?.toString() ?? '—';
    final guest = event['isGuest'] == true || isGuestEvent(event);
    final errorFocus = effectiveLevel == 'error' || type == 'crash';
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
        color: errorFocus ? AppTheme.error.withValues(alpha: 0.06) : AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: errorFocus ? AppTheme.error.withValues(alpha: 0.55) : AppTheme.border,
          width: errorFocus ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(left: errorFocus ? 4 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                        color: errorFocus ? AppTheme.error.withValues(alpha: 0.1) : AppTheme.panelElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: errorFocus ? AppTheme.error.withValues(alpha: 0.25) : AppTheme.border,
                        ),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          LevelBadge(level: effectiveLevel, type: type, compact: true),
                          LevelBadge(type: type, compact: true, transportOnly: true),
                          if (guest) const GuestBadge(compact: true),
                          if (category != null && category.isNotEmpty) _pill(category.toUpperCase(), AppTheme.muted),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: errorFocus ? AppTheme.error : AppTheme.text,
                            height: 1.3,
                          ),
                        ),
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
                          decoration: BoxDecoration(
                            color: AppTheme.panelElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: FlowStrip(items: flow, embedded: true),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Text('Environment: $env', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                    ),
                  ],
                ),
              ),
              if (errorFocus)
                const Positioned(left: 0, top: 0, bottom: 0, child: SizedBox(width: 4, child: ColoredBox(color: AppTheme.error))),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.panelElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
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
    final level = issueLevel(issue);
    final last = DateTime.tryParse(issue['lastSeenAt'] as String? ?? '');
    final lastLabel = last != null ? DateFormat.yMMMd().add_jm().format(last.toLocal()) : '—';
    final status = issue['status'] as String? ?? 'open';
    final compact = MediaQuery.sizeOf(context).width < 600;
    final resolved = status == 'resolved';
    final errorFocus = !resolved && issueErrorFocus(issue);
    final warningFocus = !resolved && !errorFocus && issueWarningFocus(issue);
    final accent = errorFocus
        ? AppTheme.error
        : warningFocus
            ? AppTheme.warning
            : level == 'success'
                ? AppTheme.success
                : null;

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: errorFocus
            ? AppTheme.error.withValues(alpha: 0.06)
            : warningFocus
                ? AppTheme.warning.withValues(alpha: 0.06)
                : AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: resolved
              ? AppTheme.success.withValues(alpha: 0.35)
              : accent?.withValues(alpha: 0.55) ?? AppTheme.border,
          width: errorFocus ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(errorFocus || warningFocus ? 14 : 0, compact ? 12 : 14, compact ? 12 : 14, compact ? 12 : 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    LevelBadge(level: level, type: type, compact: compact),
                    if (type == 'network') LevelBadge(type: type, compact: compact, transportOnly: true),
                  ],
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      issue['title'] as String? ?? 'Unknown',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 14 : 15,
                        color: errorFocus ? AppTheme.error : AppTheme.text,
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 8),
                    Wrap(spacing: 12, runSpacing: 4, children: [
                      _meta(Icons.repeat, '${issue['eventCount']} events'),
                      _meta(Icons.public, issue['topCountry'] as String? ?? '—'),
                      _meta(Icons.schedule, lastLabel),
                      _meta(Icons.flag_outlined, status, color: resolved ? AppTheme.success : AppTheme.muted),
                    ]),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.muted),
              ]),
            ),
            if (errorFocus)
              const Positioned(left: 0, top: 0, bottom: 0, child: SizedBox(width: 4, child: ColoredBox(color: AppTheme.error)))
            else if (warningFocus)
              const Positioned(left: 0, top: 0, bottom: 0, child: SizedBox(width: 4, child: ColoredBox(color: AppTheme.warning))),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color? color}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? AppTheme.muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 12, color: color ?? AppTheme.muted)),
        ],
      );
}
