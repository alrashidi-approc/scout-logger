import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../services/screen_cache.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard.dart';
import '../utils/nav.dart';
import '../utils/responsive.dart';
import '../widgets/detail_panel.dart';
import '../widgets/event_card.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';

class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({super.key, required this.projectId, required this.userId});

  final String projectId;
  final String userId;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;

  String get _cacheKey => screenCacheKey(
        'user-detail',
        projectId: widget.projectId,
        extra: {'userId': widget.userId},
      );

  @override
  void initState() {
    super.initState();
    if (!_restore()) _load();
  }

  bool _restore() {
    final cached = ScreenCache.instance.read<Map<String, dynamic>>(_cacheKey);
    if (cached == null) return false;
    _user = cached;
    _hasData = true;
    _loading = false;
    _refreshing = false;
    _error = null;
    return true;
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
      final user = await _api.fetchUser(widget.projectId, widget.userId);
      ScreenCache.instance.write(_cacheKey, user);
      if (mounted) setState(() {
        _user = user;
        _hasData = true;
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

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading && _user == null,
      refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.detail,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    final u = _user!;
    final events = jsonListMaps(u['recentEvents']);
    final first = DateTime.tryParse(u['firstSeenAt'] as String? ?? '');
    final last = DateTime.tryParse(u['lastSeenAt'] as String? ?? '');
    final name = u['displayName'] as String?;
    final email = u['email'] as String?;
    final title = name ?? email ?? widget.userId;
    void copy(String v) => copyWithFeedback(context, v);

    return ListView(
      padding: pageInsets(context, top: 16, bottom: pagePad(context)),
      children: [
        TextButton.icon(onPressed: () => popOrGo(context, '/p/${widget.projectId}/users'), icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Logged-in users')),
        PageHeader(
          title: title,
          subtitle: [
            if (name != null && email != null) email,
            if (name != null || email != null) widget.userId else 'Logged-in user · merged with pre-login activity on same device',
          ].join(' · '),
        ),
        if (u['includesGuestActivity'] == true) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.info.withValues(alpha: 0.25)),
            ),
            child: Text(
              'Includes ${u['guestEventCount'] ?? 0} pre-login events from the same install (guest id merged into this profile).',
              style: const TextStyle(fontSize: 12, color: AppTheme.text, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 16),
        DetailSection(
          title: 'Profile',
          child: Column(children: [
            DetailRow(label: 'User ID', value: widget.userId, mono: true, onCopy: () => copy(widget.userId)),
            if (name != null) DetailRow(label: 'Name', value: name),
            if (email != null) DetailRow(label: 'Email', value: email),
            DetailRow(label: 'Phone', value: '${u['phone'] ?? ''}'),
            DetailRow(label: 'Username', value: '${u['username'] ?? ''}'),
            if (first != null && last != null)
              DetailRow(label: 'Active', value: '${DateFormat.yMMMd().format(first.toLocal())} – ${DateFormat.yMMMd().add_jm().format(last.toLocal())}'),
          ]),
        ),
        const SizedBox(height: 12),
        DetailSection(
          title: 'Last app version',
          child: Column(children: [
            DetailRow(
              label: 'Version',
              value: '${u['lastAppVersionLabel'] ?? u['lastAppVersion'] ?? u['appVersion'] ?? '—'}',
              mono: true,
              onCopy: () {
                final v = '${u['lastAppVersionLabel'] ?? u['lastAppVersion'] ?? u['appVersion'] ?? ''}';
                if (v.isNotEmpty && v != '—') copy(v);
              },
            ),
            DetailRow(label: 'Build', value: '${u['lastBuildNumber'] ?? ''}'),
            DetailRow(
              label: 'Platform',
              value: [
                if (u['platform'] != null) '${u['platform']}',
                if (u['environment'] != null) '${u['environment']}',
              ].join(' · '),
            ),
            if (u['lastAppVersionSeenAt'] != null)
              DetailRow(
                label: 'Last seen on this version',
                value: DateFormat.yMMMd().add_jm().format(
                      DateTime.parse(u['lastAppVersionSeenAt'] as String).toLocal(),
                    ),
              ),
          ]),
        ),
        if (jsonListMaps(u['appVersions']).length > 1) ...[
          const SizedBox(height: 12),
          DetailSection(
            title: 'Version history',
            child: Column(
              children: [
                for (final v in jsonListMaps(u['appVersions']))
                  DetailRow(
                    label: '${v['label'] ?? v['appVersion'] ?? '—'}',
                    value: _versionHistoryLine(v),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        DetailSection(
          title: 'Client context',
          child: Column(children: [
            DetailRow(label: 'Device', value: '${u['deviceName'] ?? ''}'),
            DetailRow(label: 'Country', value: '${u['topCountry'] ?? ''}'),
            DetailRow(label: 'Release', value: '${u['release'] ?? ''}'),
            DetailRow(label: 'Environment', value: '${u['environment'] ?? ''}'),
          ]),
        ),
        const SizedBox(height: 12),
        DetailSection(
          title: 'Technical',
          child: Column(children: [
            DetailRow(label: 'Install ID', value: '${u['installId'] ?? ''}', mono: true, onCopy: u['installId'] != null ? () => copy('${u['installId']}') : null),
            DetailRow(label: 'Locale', value: '${u['locale'] ?? ''}'),
            DetailRow(label: 'Last screen', value: '${u['lastRoute'] ?? ''}'),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _chip('Events', '${u['eventCount']}', Icons.show_chart),
          _chip('Errors', '${u['errorCount']}', Icons.error_outline),
          _chip('Crashes', '${u['crashCount']}', Icons.bolt),
          _chip('Sessions', '${u['sessionCount']}', Icons.play_circle_outline),
          _chip('Devices', '${u['deviceCount'] ?? 1}', Icons.devices),
        ]),
        if (jsonListMaps(u['devices']).isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Devices', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.text)),
          const SizedBox(height: 10),
          ...jsonListMaps(u['devices']).map((d) {
            final firstD = DateTime.tryParse(d['firstSeenAt'] as String? ?? '');
            final lastD = DateTime.tryParse(d['lastSeenAt'] as String? ?? '');
            final installId = d['installId'] as String?;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: installId != null ? () => context.push('/p/${widget.projectId}/devices/${Uri.encodeComponent(installId)}') : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d['deviceName'] as String? ?? 'Device', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('${d['platform'] ?? '—'} · ${d['eventCount']} events', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                          const SizedBox(height: 4),
                          Text(
                            '${d['installId']}',
                            style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontFamily: 'monospace'),
                            maxLines: 1,
                          ),
                          if (firstD != null && lastD != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${DateFormat.MMMd().format(firstD.toLocal())} – ${DateFormat.MMMd().format(lastD.toLocal())}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                              ),
                            ),
                        ]),
                      ),
                      if (installId != null) const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
                    ]),
                  ),
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 20),
        const Text('Recent events', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.text)),
        const SizedBox(height: 10),
        ...events.map((e) => EventCard(event: e, onTap: () => context.push('/p/${widget.projectId}/events/${e['id']}'))),
      ],
    );
  }

  Widget _chip(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
        ]),
      );

  static String _versionHistoryLine(Map<String, dynamic> v) {
    final lastV = DateTime.tryParse(v['lastSeenAt'] as String? ?? '');
    return [
      if (lastV != null) 'last ${DateFormat.MMMd().add_jm().format(lastV.toLocal())}',
      if (v['eventCount'] != null) '${v['eventCount']} events',
      if (v['platform'] != null) '${v['platform']}',
    ].join(' · ');
  }
}
