import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../services/screen_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/event_card.dart';
import '../widgets/level_badge.dart';
import '../utils/nav.dart';
import '../utils/responsive.dart';
import '../utils/share_link.dart';
import '../widgets/notify_team_sheet.dart';
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

class _IssueDetailCache {
  const _IssueDetailCache({required this.issue, required this.members});
  final Map<String, dynamic> issue;
  final List<Map<String, dynamic>> members;
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _issue;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  bool _updating = false;
  bool _sharing = false;
  bool _addingNote = false;
  List<Map<String, dynamic>> _members = [];
  final _noteCtrl = TextEditingController();
  Object? _error;

  String? get _cacheKey => widget.shared
      ? null
      : screenCacheKey(
          'issue-detail',
          projectId: widget.projectId,
          extra: {'issueId': widget.issueId},
        );

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialIssue != null) {
      _issue = widget.initialIssue;
      _loading = false;
      _hasData = true;
    } else if (!_restore()) {
      _load();
    }
  }

  bool _restore() {
    final key = _cacheKey;
    if (key == null) return false;
    final cached = ScreenCache.instance.read<_IssueDetailCache>(key);
    if (cached == null) return false;
    _issue = cached.issue;
    _members = cached.members;
    _hasData = true;
    _loading = false;
    _refreshing = false;
    _error = null;
    return true;
  }

  void _writeCache() {
    final key = _cacheKey;
    final issue = _issue;
    if (key == null || issue == null) return;
    ScreenCache.instance.write(key, _IssueDetailCache(issue: issue, members: _members));
  }

  void _invalidateIssueLists() {
    ScreenCache.instance.invalidatePrefix('issues|${widget.projectId}');
    ScreenCache.instance.invalidatePrefix('overview|${widget.projectId}');
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      beginScreenLoad(
        hasData: _hasData,
        apply: ({required loading, required refreshing, error}) {
          _loading = loading;
          _refreshing = refreshing;
          _error = error;
        },
      );
    });
    try {
      final issue = await _api.fetchIssue(widget.projectId, widget.issueId);
      var members = _members;
      if (!widget.shared && members.isEmpty) {
        try {
          members = await _api.fetchAssignableMembers(widget.projectId);
        } catch (_) {}
      }
      if (mounted) setState(() {
        _issue = issue;
        _members = members;
        _hasData = true;
        _loading = false;
        _refreshing = false;
      });
      _writeCache();
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
        _writeCache();
        _invalidateIssueLists();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(switch (status) {
            'resolved' => 'Issue marked resolved',
            'ignored' => 'Issue muted — alerts paused',
            _ => 'Issue reopened',
          })),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _updating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _assign(String? userId) async {
    setState(() => _updating = true);
    try {
      final issue = await _api.assignIssue(widget.projectId, widget.issueId, userId);
      if (mounted) setState(() {
        _issue = issue;
        _updating = false;
      });
      _writeCache();
    } catch (e) {
      if (mounted) {
        setState(() => _updating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _addNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _addingNote = true);
    try {
      final note = await _api.addIssueNote(widget.projectId, widget.issueId, text);
      if (mounted) {
        setState(() {
          (_issue!['notes'] as List).add(note);
          _noteCtrl.clear();
          _addingNote = false;
        });
        _writeCache();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _addingNote = false);
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
    final devices = jsonListMaps(issue['deviceBreakdown']);
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
          if (!shared)
            OutlinedButton.icon(
              onPressed: () => showNotifyTeamSheet(
                context,
                projectId: widget.projectId,
                resourceType: 'issue',
                resourceId: widget.issueId,
              ),
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('Notify team'),
            ),
          if (!shared && status == 'open') ...[
            FilledButton.icon(
              onPressed: _updating ? null : () => _setStatus('resolved'),
              icon: _updating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Resolve'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _updating ? null : () => _setStatus('ignored'),
              icon: const Icon(Icons.notifications_off_outlined, size: 18),
              label: const Text('Mute'),
            ),
          ] else if (!shared && status == 'resolved')
            OutlinedButton.icon(
              onPressed: _updating ? null : () => _setStatus('open'),
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Reopen'),
            )
          else if (!shared && status == 'ignored')
            OutlinedButton.icon(
              onPressed: _updating ? null : () => _setStatus('open'),
              icon: const Icon(Icons.notifications_active_outlined, size: 18),
              label: const Text('Unmute'),
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
        if (issue['insights'] is Map) ...[
          const SizedBox(height: 20),
          _insightsCard(Map<String, dynamic>.from(issue['insights'] as Map)),
        ],
        if (!shared) ...[
          const SizedBox(height: 20),
          _assigneeCard(issue),
          const SizedBox(height: 20),
          _notesCard(issue),
        ],
        if (devices.isNotEmpty) ...[
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Affected devices', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                const Text('Tap a device to see its error events', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: devices.map((d) {
                  final installs = d['installs'] as int? ?? 0;
                  final label = installs > 0 ? '${d['device']} · $installs devices · ${d['count']} ev' : '${d['device']} · ${d['count']} ev';
                  return ActionChip(
                    avatar: const Icon(Icons.phone_android_outlined, size: 16),
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    onPressed: shared
                        ? null
                        : () => context.go(Uri(
                              path: '/p/${widget.projectId}/events',
                              queryParameters: {'device': '${d['device']}', 'type': 'errors'},
                            ).toString()),
                  );
                }).toList()),
              ]),
            ),
          ),
        ],
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

  String _memberLabel(Map<String, dynamic> m) {
    final name = (m['displayName'] as String?)?.trim();
    return name != null && name.isNotEmpty ? '$name (${m['email']})' : '${m['email']}';
  }

  Widget _assigneeCard(Map<String, dynamic> issue) {
    final current = issue['assigneeUserId'] as String?;
    final hasCurrent = current != null && _members.any((m) => m['userId'] == current);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          const Icon(Icons.person_outline, size: 20, color: AppTheme.muted),
          const SizedBox(width: 12),
          const Text('Assignee', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const Spacer(),
          DropdownButton<String?>(
            value: hasCurrent ? current : null,
            hint: const Text('Unassigned'),
            onChanged: _updating ? null : _assign,
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
              for (final m in _members)
                DropdownMenuItem<String?>(value: m['userId'] as String, child: Text(_memberLabel(m))),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _notesCard(Map<String, dynamic> issue) {
    final notes = (issue['notes'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Notes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          if (notes.isEmpty)
            const Text('No notes yet', style: TextStyle(color: AppTheme.muted, fontSize: 13))
          else
            for (final n in notes) ...[
              Text(n['body'] as String? ?? '', style: const TextStyle(fontSize: 14)),
              Text(
                '${n['authorName'] ?? n['authorEmail'] ?? 'Unknown'} · ${_noteTime(n['createdAt'] as String?)}',
                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
              ),
              const Divider(height: 20),
            ],
          Row(children: [
            Expanded(
              child: TextField(
                controller: _noteCtrl,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Add a note…', isDense: true),
                onSubmitted: (_) => _addNote(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _addingNote ? null : _addNote,
              child: _addingNote
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add'),
            ),
          ]),
        ]),
      ),
    );
  }

  String _noteTime(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '' : DateFormat.yMMMd().add_jm().format(d.toLocal());
  }

  Color _sevColor(String s) => switch (s) {
        'high' => AppTheme.error,
        'medium' => AppTheme.warning,
        _ => AppTheme.muted,
      };

  Widget _insightsCard(Map<String, dynamic> insights) {
    final severity = insights['severity'] as String? ?? 'low';
    final reasons = (insights['severityReasons'] as List?)?.cast<String>() ?? const [];
    final culprit = insights['culprit'] as String?;
    final correlations = (insights['correlations'] as List?)?.cast<Map>() ?? const [];
    final color = _sevColor(severity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, size: 18, color: AppTheme.muted),
            const SizedBox(width: 8),
            const Text('Insights', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Text('${severity.toUpperCase()} severity',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(reasons.join(' · '), style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
          ],
          if (culprit != null) ...[
            const SizedBox(height: 14),
            const Text('Likely source', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.muted.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(culprit, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
          if (correlations.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Common factors', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in correlations)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${c['label']}: ${c['value']} · ${((c['ratio'] as num) * 100).round()}%',
                      style: const TextStyle(fontSize: 12)),
                ),
            ]),
          ],
        ]),
      ),
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
