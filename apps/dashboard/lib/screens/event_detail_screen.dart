import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/event_view.dart';
import '../widgets/event_detail_widgets.dart';
import '../widgets/page_header.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.projectId, required this.eventId});

  final String projectId;
  final String eventId;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _event;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final event = await _api.fetchEvent(widget.projectId, widget.eventId);
      if (mounted) setState(() {
        _event = event;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _copyJson(EventView v) {
    Clipboard.setData(ClipboardData(text: prettyJson(v.event)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event JSON copied')));
  }

  void _copyTicket(EventView v) {
    Clipboard.setData(ClipboardData(text: bugReport(v, widget.projectId)));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bug report copied — paste into your ticket')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _load);

    final v = EventView(_event!);
    final occurred = DateTime.tryParse(v.event['occurredAt'] as String? ?? '');
    final time = occurred != null ? DateFormat('EEEE, MMM d yyyy · HH:mm:ss').format(occurred.toLocal()) : '—';
    final related = jsonListMaps(_event!['relatedEvents']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
        children: [
          Row(children: [
            TextButton.icon(onPressed: () => context.go('/p/${widget.projectId}/events'), icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Events')),
            const Spacer(),
            OutlinedButton.icon(onPressed: () => _copyTicket(v), icon: const Icon(Icons.assignment_outlined, size: 16), label: const Text('Copy ticket')),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: () => _copyJson(v), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy JSON')),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 12),
          PageHeader(title: 'Event details', subtitle: '${v.event['id']} · $time'),
          if (v.sessionId != '—') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go('/p/${widget.projectId}/analytics/sessions/${v.sessionId}'),
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('View full session timeline'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          EventErrorHeader(view: v),
          const SizedBox(height: 12),
          EventFlowDiagram(view: v),
          if (v.issue != null) ...[
            const SizedBox(height: 12),
            _IssueLink(projectId: widget.projectId, issue: v.issue!),
          ],
          const SizedBox(height: 20),
          InfoSection(title: 'What happened', icon: Icons.info_outline, child: SummaryList(lines: v.summaryLines())),
          if (related.isNotEmpty)
            InfoSection(
              title: 'Related events',
              icon: Icons.link,
              subtitle: 'Other events in the same issue group',
              child: Column(
                children: related.map((e) => RelatedEventTile(
                      event: e,
                      onTap: () => context.go('/p/${widget.projectId}/events/${e['id']}'),
                    )).toList(),
              ),
            ),
          if (v.stack.isNotEmpty)
            InfoSection(title: 'Stack trace', icon: Icons.code, subtitle: 'Where the error occurred in code', child: StackTracePanel(stack: v.stack)),
          if (v.issueFields().isNotEmpty)
            InfoSection(title: 'Issue grouping', icon: Icons.fingerprint, subtitle: 'How similar events are grouped', child: FieldGrid(fields: v.issueFields())),
          InfoSection(title: 'Release & application', icon: Icons.rocket_launch_outlined, subtitle: v.environment, child: FieldGrid(fields: v.releaseFields())),
          InfoSection(title: 'Device & connectivity', icon: Icons.phone_android_outlined, child: FieldGrid(fields: v.deviceFields())),
          InfoSection(title: 'User & session', icon: Icons.person_outline, child: FieldGrid(fields: v.userFields())),
          InfoSection(title: 'Screens & trail', icon: Icons.route_outlined, subtitle: v.route, child: FieldGrid(fields: v.screenFields())),
          InfoSection(title: 'Breadcrumbs', icon: Icons.timeline, initiallyExpanded: v.breadcrumbs.isNotEmpty, child: BreadcrumbTrail(items: v.breadcrumbs)),
          InfoSection(
            title: 'Network',
            icon: Icons.lan_outlined,
            subtitle: v.network.isEmpty ? null : v.networkOutcome,
            child: v.network.isEmpty
                ? Text(v.type == 'network' ? v.message : 'No network data captured', style: const TextStyle(color: AppTheme.muted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NetworkReadablePanel(view: v),
                      if (v.networkFields().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('Technical details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.muted)),
                        const SizedBox(height: 8),
                        FieldGrid(fields: v.networkFields()),
                      ],
                    ],
                  ),
          ),
          if (v.network.isNotEmpty)
            InfoSection(title: 'Network payload (raw)', icon: Icons.http, initiallyExpanded: false, child: JsonPanel(data: v.network)),
          InfoSection(
            title: 'Product context',
            icon: Icons.business_outlined,
            subtitle: 'Extra fields attached by your app',
            child: v.customFields().isEmpty ? const Text('No extra context', style: TextStyle(color: AppTheme.muted)) : FieldGrid(fields: v.customFields()),
          ),
          InfoSection(title: 'Server enrichment', icon: Icons.cloud_outlined, initiallyExpanded: false, child: JsonPanel(data: v.enrichment)),
          InfoSection(title: 'Full event', icon: Icons.data_object, initiallyExpanded: false, child: JsonPanel(data: v.event)),
          InfoSection(title: 'Payload only', icon: Icons.inventory_2_outlined, initiallyExpanded: false, child: JsonPanel(data: v.payload)),
        ],
      ),
    );
  }
}

class _IssueLink extends StatelessWidget {
  const _IssueLink({required this.projectId, required this.issue});

  final String projectId;
  final Map<String, dynamic> issue;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/p/$projectId/issues/${issue['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.bug_report_outlined, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Linked issue', style: TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600)),
                Text(issue['title'] as String? ?? 'Issue', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${issue['eventCount']} events · ${issue['status']}', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.muted),
          ]),
        ),
      ),
    );
  }
}
