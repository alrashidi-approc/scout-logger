import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/event_card.dart';
import '../widgets/level_badge.dart';
import '../utils/nav.dart';
import '../utils/responsive.dart';
import '../utils/share_link.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';

class IssueDetailScreen extends StatefulWidget {
  const IssueDetailScreen({super.key, required this.projectId, required this.issueId, this.shareUrl})
      : shared = false,
        initialIssue = null;

  const IssueDetailScreen.viewOnly({super.key, required this.initialIssue, this.shareUrl})
      : shared = true,
        projectId = '',
        issueId = '';

  final String projectId;
  final String issueId;
  final bool shared;
  final Map<String, dynamic>? initialIssue;
  final String? shareUrl;

  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _issue;
  bool _loading = true;
  bool _refreshing = false;
  bool _updating = false;
  bool _sharing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialIssue != null) {
      _issue = widget.initialIssue;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      beginScreenLoad(
        hasData: _issue != null,
        apply: ({required loading, required refreshing, error}) {
          _loading = loading;
          _refreshing = refreshing;
          _error = error;
        },
      );
    });
    try {
      final issue = await _api.fetchIssue(widget.projectId, widget.issueId);
      if (mounted) setState(() {
        _issue = issue;
        _loading = false;

        _refreshing = false;
      });
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) setState(() {
        _error = e;
        _loading = false;

        _refreshing = false;
      });
    }
  }

  Future<void> _setStatus(String status) async {
    setState(() => _updating = true);
    try {
      final issue = await _api.updateIssueStatus(widget.projectId, widget.issueId, status);
      if (mounted) {
        setState(() {
          _issue = issue;
          _updating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status == 'resolved' ? 'Issue marked resolved' : 'Issue reopened')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      await copyShareLink(context, projectId: widget.projectId, type: 'issue', resourceId: widget.issueId);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading && _issue == null,
      refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.detail,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    final issue = _issue!;
    final events = jsonListMaps(issue['events']);
    final geo = jsonListMaps(issue['geoBreakdown']);
    final status = issue['status'] as String? ?? 'open';
    final shared = widget.shared;
    final first = DateTime.tryParse(issue['firstSeenAt'] as String? ?? '');
    final last = DateTime.tryParse(issue['lastSeenAt'] as String? ?? '');

    return ListView(
      padding: pageInsets(context, top: 16, bottom: pagePad(context)),
      children: [
        if (!shared)
          TextButton.icon(
            onPressed: () => popOrGo(context, '/p/${widget.projectId}/issues'),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LevelBadge(type: issue['type'] as String? ?? 'error'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(issue['title'] as String? ?? 'Issue', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                '${issue['eventCount']} events · ${issue['affectedUsers'] ?? 0} logged-in · ${issue['status']}',
                style: const TextStyle(color: AppTheme.muted),
              ),
              if (first != null && last != null)
                Text(
                  'First ${DateFormat.yMMMd().format(first)} · Last ${DateFormat.yMMMd().add_jm().format(last)}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
            ]),
          ),
          IconButton(onPressed: shared ? null : _load, icon: const Icon(Icons.refresh)),
          if (!shared)
            OutlinedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link, size: 18),
              label: const Text('Share link'),
            ),
          if (!shared && status == 'open')
            FilledButton.icon(
              onPressed: _updating ? null : () => _setStatus('resolved'),
              icon: _updating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Resolve'),
            )
          else if (!shared && status == 'resolved')
            OutlinedButton.icon(
              onPressed: _updating ? null : () => _setStatus('open'),
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Reopen'),
            ),
        ]),
        const SizedBox(height: 24),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _statTile('Events', '${issue['eventCount']}', Icons.repeat),
            _statTile('Logged-in', '${issue['affectedUsers'] ?? 0}', Icons.people_outline),
            _statTile('Country', issue['topCountry'] as String? ?? '—', Icons.public),
            _statTile('Status', issue['status'] as String? ?? 'open', Icons.flag_outlined),
          ],
        ),
        if (geo.isNotEmpty) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Affected countries', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: geo.map((g) => Chip(
                      avatar: CircleAvatar(child: Text('${g['country']}', style: const TextStyle(fontSize: 10))),
                      label: Text('${g['count']} events'),
                    )).toList()),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Text('Recent events', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        ...events.map((e) => EventCard(
              event: e,
              onTap: shared ? null : () => context.push('/p/${widget.projectId}/events/${e['id']}'),
            )),
      ],
    );
  }

  Widget _statTile(String label, String value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: AppTheme.muted),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ]),
        ),
      );
}
