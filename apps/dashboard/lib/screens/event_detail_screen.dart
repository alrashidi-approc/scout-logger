import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/event_view.dart';
import '../utils/nav.dart';
import '../utils/responsive.dart';
import '../utils/clipboard.dart';
import '../utils/share_link.dart';
import '../widgets/event_detail_widgets.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen(
      {super.key,
      required this.projectId,
      required this.eventId,
      this.shareUrl})
      : shared = false,
        initialEvent = null;

  const EventDetailScreen.viewOnly(
      {super.key, required this.initialEvent, this.shareUrl})
      : shared = true,
        projectId = '',
        eventId = '';

  final String projectId;
  final String eventId;
  final bool shared;
  final Map<String, dynamic>? initialEvent;
  final String? shareUrl;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _event;
  bool _loading = true;
  bool _refreshing = false;
  bool _sharing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialEvent != null) {
      _event = widget.initialEvent;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      beginScreenLoad(
        hasData: _event != null,
        apply: ({required loading, required refreshing, error}) {
          _loading = loading;
          _refreshing = refreshing;
          _error = error;
        },
      );
    });
    try {
      final event = await _api.fetchEvent(widget.projectId, widget.eventId);
      if (mounted) {
        setState(() {
          _event = event;
          _loading = false;

          _refreshing = false;
        });
      }
    } catch (e) {
      DashboardLogService.record(
          projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;

          _refreshing = false;
        });
      }
    }
  }

  void _copyJson(EventView v) => copyWithFeedback(context, prettyJson(v.event),
      message: 'Event JSON copied');

  void _copyTicket(EventView v) => copyWithFeedback(
        context,
        bugReport(v, widget.projectId),
        message: 'Bug report copied — paste into your ticket',
      );

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await copyShareLink(context,
          projectId: widget.projectId,
          type: 'event',
          resourceId: widget.eventId);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading && _event == null,
      refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.detail,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    final v = EventView(_event!);
    final occurred = DateTime.tryParse(v.event['occurredAt'] as String? ?? '');
    final time = occurred != null
        ? DateFormat('EEEE, MMM d yyyy · HH:mm:ss').format(occurred.toLocal())
        : '—';
    final related = jsonListMaps(_event!['relatedEvents']);
    final sessionEvents = jsonListMaps(_event!['sessionEvents']);
    final pid = widget.projectId;
    final shared = widget.shared;
    final countryCode = v.event['country'] as String?;
    final pad = pagePad(context);
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Material(
      color: AppTheme.bg,
      child: ListView(
        padding: pageInsets(context, top: 16).copyWith(bottom: pad + 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!shared)
                TextButton.icon(
                  onPressed: () => popOrGo(context, '/p/$pid/events'),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back'),
                ),
              if (!compact) ...[
                if (!shared)
                  OutlinedButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link, size: 16),
                    label: const Text('Share link'),
                  ),
                OutlinedButton.icon(
                    onPressed: () => _copyTicket(v),
                    icon: const Icon(Icons.assignment_outlined, size: 16),
                    label: const Text('Copy ticket')),
                OutlinedButton.icon(
                    onPressed: () => _copyJson(v),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy JSON')),
              ],
              IconButton(
                  onPressed: shared ? null : _load,
                  icon: const Icon(Icons.refresh)),
              if (compact) ...[
                OutlinedButton(
                    onPressed: () => _copyTicket(v),
                    child: const Icon(Icons.assignment_outlined, size: 16)),
                OutlinedButton(
                    onPressed: () => _copyJson(v),
                    child: const Icon(Icons.copy, size: 16)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          PageHeader(title: 'Event inspector', subtitle: '${v.event['id']}'),
          const SizedBox(height: 12),
          EventErrorHeader(view: v, timeLabel: time),
          const SizedBox(height: 12),
          EventQuickFacts(
            view: v,
            onSessionTap: !shared && v.sessionId != '—'
                ? () => context.push('/p/$pid/sessions/${v.sessionId}')
                : null,
            onUserTap: !shared && v.userId != '—'
                ? () => context.go(
                    '/p/$pid/events?days=30&q=${Uri.encodeComponent(v.userId)}')
                : null,
            onCountryTap: !shared && countryCode != null
                ? () => context.go('/p/$pid/geo')
                : null,
          ),
          const SizedBox(height: 16),
          EventDetailGroup(
            title: 'Overview',
            icon: Icons.dashboard_outlined,
            initiallyExpanded: true,
            children: [
              EventFlowDiagram(view: v),
              if (v.issue != null) ...[
                const SizedBox(height: 12),
                _IssueLink(projectId: pid, issue: v.issue!, shared: shared),
              ],
              InfoSection(
                  title: 'What happened',
                  icon: Icons.info_outline,
                  child: SummaryList(lines: v.summaryLines())),
              if (!shared && related.isNotEmpty)
                InfoSection(
                  title: 'Same issue',
                  icon: Icons.link,
                  subtitle: '${related.length} other occurrences of this error',
                  child: SimpleTimeline(
                    entries: related
                        .map((e) => eventTimelineEntry(
                              e,
                              onTap: () =>
                                  context.push('/p/$pid/events/${e['id']}'),
                            ))
                        .toList(),
                  ),
                ),
            ],
          ),
          EventDetailGroup(
            title: 'Timeline',
            icon: Icons.timeline,
            subtitle: () {
              if (sessionEvents.isNotEmpty) {
                final screens = sessionEvents
                    .map((e) => str(e['route']) ?? '')
                    .where((r) => r.isNotEmpty && r != '—')
                    .toSet()
                    .length;
                return '${sessionEvents.length} events · $screens screens';
              }
              if (v.breadcrumbs.isNotEmpty)
                return '${v.breadcrumbs.length} screens';
              return v.route != '—' ? v.route : null;
            }(),
            children: [
              if (sessionEvents.isNotEmpty) ...[
                SessionTimeline(
                  events: sessionEvents,
                  onEventTap: shared
                      ? null
                      : (e) => context.push('/p/$pid/events/${e['id']}'),
                ),
              ] else if (v.breadcrumbs.isNotEmpty) ...[
                const Text('Screens',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.muted)),
                const SizedBox(height: 8),
                BreadcrumbTrail(items: v.breadcrumbs),
              ] else if (v.route != '—')
                SimpleTimeline(entries: [
                  SimpleTimelineEntry(title: v.route, meta: 'Current screen')
                ]),
            ],
          ),
          EventDetailGroup(
            title: 'Technical',
            icon: Icons.memory_outlined,
            subtitle: 'Stack, device, network',
            initiallyExpanded: true,
            children: [
              if (v.stack.isNotEmpty)
                InfoSection(
                    title: 'Stack trace',
                    icon: Icons.code,
                    subtitle: 'Where the error occurred in code',
                    child: StackTracePanel(stack: v.stack)),
              if (v.issueFields().isNotEmpty)
                InfoSection(
                    title: 'Issue grouping',
                    icon: Icons.fingerprint,
                    child: FieldGrid(fields: v.issueFields())),
              InfoSection(
                  title: 'Release & application',
                  icon: Icons.rocket_launch_outlined,
                  subtitle: v.environment,
                  child: FieldGrid(fields: v.releaseFields())),
              InfoSection(
                  title: 'Device & connectivity',
                  icon: Icons.phone_android_outlined,
                  child: FieldGrid(fields: v.deviceFields())),
              InfoSection(
                  title: 'User & session',
                  icon: Icons.person_outline,
                  child: FieldGrid(fields: v.userFields())),
              InfoSection(
                title: 'Network',
                icon: Icons.lan_outlined,
                subtitle: v.network.isEmpty ? null : v.networkOutcome,
                child: v.network.isEmpty
                    ? Text(
                        v.type == 'network'
                            ? v.message
                            : 'No network data captured',
                        style: const TextStyle(color: AppTheme.muted))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          NetworkReadablePanel(view: v),
                          if (v.networkFields().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('Technical details',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.muted)),
                            const SizedBox(height: 8),
                            FieldGrid(fields: v.networkFields()),
                          ],
                        ],
                      ),
              ),
              InfoSection(
                title: 'Product context',
                icon: Icons.business_outlined,
                child: v.customFields().isEmpty
                    ? const Text('No extra context',
                        style: TextStyle(color: AppTheme.muted))
                    : FieldGrid(fields: v.customFields()),
              ),
            ],
          ),
          EventDetailGroup(
            title: 'Raw data',
            icon: Icons.data_object,
            subtitle: 'JSON payloads',
            children: [
              if (v.network.isNotEmpty)
                InfoSection(
                    title: 'Network payload',
                    icon: Icons.http,
                    child: JsonPanel(data: v.network)),
              InfoSection(
                  title: 'Server enrichment',
                  icon: Icons.cloud_outlined,
                  child: JsonPanel(data: v.enrichment)),
              InfoSection(
                  title: 'Full event',
                  icon: Icons.data_object,
                  child: JsonPanel(data: v.event)),
              InfoSection(
                  title: 'Payload only',
                  icon: Icons.inventory_2_outlined,
                  child: JsonPanel(data: v.payload)),
            ],
          ),
        ],
      ),
    );
  }
}

class _IssueLink extends StatelessWidget {
  const _IssueLink(
      {required this.projectId, required this.issue, this.shared = false});

  final String projectId;
  final Map<String, dynamic> issue;
  final bool shared;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: shared
            ? null
            : () => context.push('/p/$projectId/issues/${issue['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.bug_report_outlined, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shared ? 'Issue group' : 'Linked issue',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.muted,
                          fontWeight: FontWeight.w600)),
                  Text(issue['title'] as String? ?? 'Issue',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (!shared)
                    Text('${issue['eventCount']} events · ${issue['status']}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.muted)),
                  if (shared && issue['status'] != null)
                    Text('${issue['status']}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.muted)),
                ],
              ),
            ),
            if (!shared) const Icon(Icons.chevron_right, color: AppTheme.muted),
          ]),
        ),
      ),
    );
  }
}
