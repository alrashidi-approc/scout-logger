import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../widgets/filter_bar.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';
import '../widgets/period_picker.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(7), this.initialQuery});

  final String projectId;
  final PeriodFilter initialPeriod;
  final String? initialQuery;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  late PeriodFilter _period = widget.initialPeriod;
  late String _search = widget.initialQuery ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _syncUrl() {
    final q = <String, String>{..._period.toQuery()};
    if (_search.isNotEmpty) q['q'] = _search;
    context.go(Uri(path: '/p/${widget.projectId}/devices', queryParameters: q).toString());
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
      final devices = await _api.fetchDevices(widget.projectId, period: _period, q: _search.isEmpty ? null : _search);
      if (mounted) setState(() {
        _devices = devices;
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

  void _setPeriod(PeriodFilter p) {
    _period = p;
    _syncUrl();
    _load();
  }

  void _setSearch(String q) {
    _search = q.trim();
    _syncUrl();
    _load();
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  void _openDevice(Map<String, dynamic> d) {
    final id = d['installId'] as String;
    context.push('/p/${widget.projectId}/devices/${Uri.encodeComponent(id)}');
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: pageInsets(context, top: pagePad(context)),
        child: PageHeader(
          title: 'Devices',
          subtitle: _search.isNotEmpty
              ? '${_devices.length} matches for “$_search”'
              : '${_devices.length} installs · linked to logged-in users when accounts sign in',
          period: _period,
          onPeriodTap: _openPeriodPicker,
          actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
        ),
      ),
      Padding(
        padding: pageInsets(context, top: 12),
        child: FilterBar(
          period: _period,
          onPeriodChanged: _setPeriod,
          searchHint: 'Device, install id, user email, name, user id…',
          searchValue: _search,
          onSearch: _setSearch,
        ),
      ),
      Expanded(
        child: AsyncScreenBody(
          loading: _loading,
          refreshing: _refreshing,
          error: _error,
          onRetry: _load,
          placeholderLayout: PlaceholderLayout.list,
          empty: !_loading && _devices.isEmpty
              ? EmptyState(
                  icon: _search.isNotEmpty ? Icons.search_off : Icons.devices_outlined,
                  title: _search.isNotEmpty ? 'No devices match your search' : 'No devices yet',
                  subtitle: _search.isNotEmpty
                      ? 'Try a different name or install id'
                      : 'When the SDK sends installId on events, devices appear here with user counts.',
                )
              : null,
          builder: (context) => RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              key: PageStorageKey('devices-${widget.projectId}'),
              padding: pageInsets(context, top: 12, bottom: pagePad(context)),
              itemCount: _devices.length,
              itemBuilder: (_, i) => _DeviceCard(device: _devices[i], onTap: () => _openDevice(_devices[i])),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onTap});

  final Map<String, dynamic> device;
  final VoidCallback onTap;

  static String _shortId(String id) => id.length > 16 ? '${id.substring(0, 10)}…${id.substring(id.length - 4)}' : id;

  @override
  Widget build(BuildContext context) {
    final name = device['deviceName'] as String?;
    final installId = device['installId'] as String;
    final title = name ?? 'Device ${_shortId(installId)}';
    final last = DateTime.tryParse(device['lastSeenAt'] as String? ?? '');
    final errors = device['errorCount'] as int? ?? 0;
    final events = device['eventCount'] as int? ?? 0;
    final userCount = device['userCount'] as int? ?? 0;
    final guestOnly = device['guestOnly'] == true;
    final contextLine = [
      if (device['platform'] != null) '${device['platform']}',
      if (device['appVersion'] != null) 'v${device['appVersion']}',
      if (device['country'] != null) '${device['country']}',
    ].join(' · ');
    final usersLabel = guestOnly
        ? 'Guest only'
        : userCount == 1
            ? '1 user'
            : '$userCount users';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: errors > 0 ? AppTheme.error.withValues(alpha: 0.35) : AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.smartphone, size: 18, color: AppTheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(_shortId(installId), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontFamily: 'monospace')),
                  if (contextLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(contextLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                  ],
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(children: [
                    if (last != null) TextSpan(text: 'Last ${DateFormat.MMMd().add_jm().format(last.toLocal())} · ', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                    TextSpan(text: '$events events', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                    if (errors > 0) TextSpan(text: ' · $errors errors', style: const TextStyle(fontSize: 11, color: AppTheme.error, fontWeight: FontWeight.w600)),
                    TextSpan(text: ' · $usersLabel', style: TextStyle(fontSize: 11, color: guestOnly ? AppTheme.muted : AppTheme.primary, fontWeight: FontWeight.w600)),
                  ])),
                ]),
              ),
              const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.chevron_right, size: 18, color: AppTheme.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
