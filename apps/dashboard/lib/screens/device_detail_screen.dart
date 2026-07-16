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

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({super.key, required this.projectId, required this.installId});

  final String projectId;
  final String installId;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _device;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;

  String get _cacheKey => screenCacheKey(
        'device-detail',
        projectId: widget.projectId,
        extra: {'installId': widget.installId},
      );

  @override
  void initState() {
    super.initState();
    if (!_restore()) _load();
  }

  bool _restore() {
    final cached = ScreenCache.instance.read<Map<String, dynamic>>(_cacheKey);
    if (cached == null) return false;
    _device = cached;
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
      final device = await _api.fetchDevice(widget.projectId, widget.installId);
      ScreenCache.instance.write(_cacheKey, device);
      if (mounted) setState(() {
        _device = device;
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
      loading: _loading && _device == null,
      refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.detail,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    final d = _device!;
    final events = jsonListMaps(d['recentEvents']);
    final users = jsonListMaps(d['users']);
    final first = DateTime.tryParse(d['firstSeenAt'] as String? ?? '');
    final last = DateTime.tryParse(d['lastSeenAt'] as String? ?? '');
    final name = d['deviceName'] as String?;
    final title = name ?? 'Device';
    void copy(String v) => copyWithFeedback(context, v);

    return ListView(
      padding: pageInsets(context, top: 16, bottom: pagePad(context)),
      children: [
        TextButton.icon(onPressed: () => popOrGo(context, '/p/${widget.projectId}/devices'), icon: const Icon(Icons.arrow_back, size: 18), label: const Text('Devices')),
        PageHeader(
          title: title,
          subtitle: widget.installId,
        ),
        if (d['guestOnly'] == true) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.muted.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(
              'Guest only — ${d['guestEventCount'] ?? 0} pre-login events, no logged-in accounts on this install yet.',
              style: const TextStyle(fontSize: 12, color: AppTheme.text, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 16),
        DetailSection(
          title: 'Device',
          child: Column(children: [
            DetailRow(label: 'Install ID', value: widget.installId, mono: true, onCopy: () => copy(widget.installId)),
            if (name != null) DetailRow(label: 'Name', value: name),
            if (first != null && last != null)
              DetailRow(label: 'Active', value: '${DateFormat.yMMMd().format(first.toLocal())} – ${DateFormat.yMMMd().add_jm().format(last.toLocal())}'),
          ]),
        ),
        const SizedBox(height: 12),
        DetailSection(
          title: 'Client context',
          child: Column(children: [
            DetailRow(
              label: 'Platform',
              value: [
                if (d['platform'] != null) '${d['platform']}',
                if (d['appVersion'] != null) 'v${d['appVersion']}',
              ].join(' · '),
            ),
            DetailRow(label: 'Country', value: '${d['topCountry'] ?? ''}'),
            DetailRow(label: 'Release', value: '${d['release'] ?? ''}'),
            DetailRow(label: 'Environment', value: '${d['environment'] ?? ''}'),
            DetailRow(label: 'Locale', value: '${d['locale'] ?? ''}'),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _chip('Events', '${d['eventCount']}', Icons.show_chart),
          _chip('Errors', '${d['errorCount']}', Icons.error_outline),
          _chip('Crashes', '${d['crashCount']}', Icons.bolt),
          _chip('Sessions', '${d['sessionCount']}', Icons.play_circle_outline),
          _chip('Users', '${d['userCount'] ?? 0}', Icons.people_outline),
        ]),
        if (users.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Logged-in users', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.text)),
          const SizedBox(height: 10),
          ...users.map((u) {
            final uid = u['userId'] as String;
            final label = u['displayName'] as String? ?? u['email'] as String? ?? u['username'] as String? ?? uid;
            final firstU = DateTime.tryParse(u['firstSeenAt'] as String? ?? '');
            final lastU = DateTime.tryParse(u['lastSeenAt'] as String? ?? '');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.push('/p/${widget.projectId}/users/${Uri.encodeComponent(uid)}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('${u['eventCount']} events', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                          if (firstU != null && lastU != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${DateFormat.MMMd().format(firstU.toLocal())} – ${DateFormat.MMMd().format(lastU.toLocal())}',
                                style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                              ),
                            ),
                        ]),
                      ),
                      const Icon(Icons.chevron_right, size: 18, color: AppTheme.muted),
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
}
