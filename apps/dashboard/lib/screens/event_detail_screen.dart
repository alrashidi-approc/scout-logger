import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/event_view.dart';
import '../utils/nav.dart';
import '../utils/responsive.dart';
import '../widgets/event_detail_widgets.dart';
import '../widgets/page_header.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.projectId, required this.eventId});

  final String projectId;
  final String eventId;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> with SingleTickerProviderStateMixin {
  final _api = ScoutApi();
  Map<String, dynamic>? _event;
  bool _loading = true;
  String? _error;
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

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
      if (mounted) {
        setState(() {
          _event = event;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
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
    final pid = widget.projectId;
    final countryCode = v.event['country'] as String?;
    final pad = pagePad(context);
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: pageInsets(context, top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => popOrGo(context, '/p/$pid/events'),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
                    if (!compact) ...[
                      OutlinedButton.icon(onPressed: () => _copyTicket(v), icon: const Icon(Icons.assignment_outlined, size: 16), label: const Text('Copy ticket')),
                      OutlinedButton.icon(onPressed: () => _copyJson(v), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy JSON')),
                    ],
                    IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                    if (compact) ...[
                      OutlinedButton(onPressed: () => _copyTicket(v), child: const Icon(Icons.assignment_outlined, size: 16)),
                      OutlinedButton(onPressed: () => _copyJson(v), child: const Icon(Icons.copy, size: 16)),
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
                  onSessionTap: v.sessionId != '—' ? () => context.push('/p/$pid/sessions/${v.sessionId}') : null,
                  onUserTap: v.userId != '—' ? () => context.go('/p/$pid/events?days=30&q=${Uri.encodeComponent(v.userId)}') : null,
                  onCountryTap: countryCode != null ? () => context.go('/p/$pid/geo') : null,
                ),
              ],
            ),
          ),
        ),
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.muted,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Timeline'),
              Tab(text: 'Technical'),
              Tab(text: 'Raw data'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(v: v, related: related, projectId: pid, pad: pad, storageKey: 'overview'),
              _TimelineTab(v: v, pad: pad, storageKey: 'timeline'),
              _TechnicalTab(v: v, pad: pad, storageKey: 'technical'),
              _RawTab(v: v, pad: pad, storageKey: 'raw'),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.v, required this.related, required this.projectId, required this.pad, required this.storageKey});
  final EventView v;
  final List<Map<String, dynamic>> related;
  final String projectId;
  final double pad;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    return _tabList(
      storageKey,
      [
        EventFlowDiagram(view: v),
        if (v.issue != null) ...[
          const SizedBox(height: 12),
          _IssueLink(projectId: projectId, issue: v.issue!),
        ],
        const SizedBox(height: 16),
        InfoSection(title: 'What happened', icon: Icons.info_outline, child: SummaryList(lines: v.summaryLines())),
        if (related.isNotEmpty)
          InfoSection(
            title: 'Related events',
            icon: Icons.link,
            subtitle: '${related.length} other events in this issue group',
            child: Column(
              children: related
                  .map((e) => RelatedEventTile(
                        event: e,
                        onTap: () => context.push('/p/$projectId/events/${e['id']}'),
                      ))
                  .toList(),
            ),
          ),
      ],
      pad,
    );
  }
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.v, required this.pad, required this.storageKey});
  final EventView v;
  final double pad;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    return _tabList(
      storageKey,
      [
        InfoSection(
          title: 'User journey',
          icon: Icons.timeline,
          subtitle: 'Breadcrumbs captured before this event',
          initiallyExpanded: true,
          child: v.breadcrumbs.isEmpty
              ? const Text('No breadcrumbs recorded', style: TextStyle(color: AppTheme.muted))
              : BreadcrumbTrail(items: v.breadcrumbs),
        ),
        const SizedBox(height: 12),
        InfoSection(title: 'Screens & trail', icon: Icons.route_outlined, subtitle: v.route, child: FieldGrid(fields: v.screenFields())),
      ],
      pad,
    );
  }
}

class _TechnicalTab extends StatelessWidget {
  const _TechnicalTab({required this.v, required this.pad, required this.storageKey});
  final EventView v;
  final double pad;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    return _tabList(
      storageKey,
      [
        if (v.stack.isNotEmpty)
          InfoSection(title: 'Stack trace', icon: Icons.code, subtitle: 'Where the error occurred in code', child: StackTracePanel(stack: v.stack)),
        if (v.issueFields().isNotEmpty)
          InfoSection(title: 'Issue grouping', icon: Icons.fingerprint, child: FieldGrid(fields: v.issueFields())),
        InfoSection(title: 'Release & application', icon: Icons.rocket_launch_outlined, subtitle: v.environment, child: FieldGrid(fields: v.releaseFields())),
        InfoSection(title: 'Device & connectivity', icon: Icons.phone_android_outlined, child: FieldGrid(fields: v.deviceFields())),
        InfoSection(title: 'User & session', icon: Icons.person_outline, child: FieldGrid(fields: v.userFields())),
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
        InfoSection(
          title: 'Product context',
          icon: Icons.business_outlined,
          child: v.customFields().isEmpty ? const Text('No extra context', style: TextStyle(color: AppTheme.muted)) : FieldGrid(fields: v.customFields()),
        ),
      ],
      pad,
    );
  }
}

class _RawTab extends StatelessWidget {
  const _RawTab({required this.v, required this.pad, required this.storageKey});
  final EventView v;
  final double pad;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    return _tabList(
      storageKey,
      [
        if (v.network.isNotEmpty) InfoSection(title: 'Network payload', icon: Icons.http, child: JsonPanel(data: v.network)),
        InfoSection(title: 'Server enrichment', icon: Icons.cloud_outlined, child: JsonPanel(data: v.enrichment)),
        InfoSection(title: 'Full event', icon: Icons.data_object, child: JsonPanel(data: v.event)),
        InfoSection(title: 'Payload only', icon: Icons.inventory_2_outlined, child: JsonPanel(data: v.payload)),
      ],
      pad,
    );
  }
}

Widget _tabList(String storageKey, List<Widget> children, double pad) {
  return ListView(
    key: PageStorageKey('event-tab-$storageKey'),
    padding: EdgeInsets.fromLTRB(pad, 12, pad, pad + 24),
    children: children,
  );
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
        onTap: () => context.push('/p/$projectId/issues/${issue['id']}'),
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
