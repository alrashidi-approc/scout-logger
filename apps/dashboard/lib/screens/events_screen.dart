import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_bar.dart';
import '../theme/app_theme.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../widgets/period_picker.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    required this.projectId,
    this.initialType,
    this.initialLevel,
    this.initialCategory,
    this.initialPeriod = const PeriodFilter.days(30),
    this.initialQuery,
    this.initialCountry,
    this.initialEnvironment,
    this.initialAppVersion,
    this.initialDeviceName,
    this.initialOffset = 0,
  });

  final String projectId;
  final String? initialType;
  final String? initialLevel;
  final String? initialCategory;
  final PeriodFilter initialPeriod;
  final String? initialQuery;
  final String? initialCountry;
  final String? initialEnvironment;
  final String? initialAppVersion;
  final String? initialDeviceName;
  final int initialOffset;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  static const _pageSize = 50;

  final _api = ScoutApi();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _events = [];
  List<String> _environments = [];
  List<String> _appVersions = [];
  List<String> _deviceNames = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  int _offset = 0;
  int _total = 0;
  bool _hasMore = false;
  late String? _kindFilter;
  late String? _levelFilter;
  late String? _categoryFilter;
  late PeriodFilter _period;
  late String _search;
  String? _country;
  String? _environment;
  String? _appVersion;
  String? _deviceName;

  static const _levelOptions = [null, 'error', 'info', 'warning', 'success'];
  static const _kindOptions = [null, 'errors', 'error', 'crash', 'network', 'session', 'log', 'span'];
  static const _categoryOptions = [null, 'network', 'system', 'crashing', 'logic', 'ui'];

  @override
  void initState() {
    super.initState();
    _kindFilter = widget.initialType;
    _levelFilter = widget.initialLevel;
    _categoryFilter = widget.initialCategory;
    _period = widget.initialPeriod;
    _search = widget.initialQuery ?? '';
    _country = widget.initialCountry;
    _environment = widget.initialEnvironment;
    _appVersion = widget.initialAppVersion;
    _deviceName = widget.initialDeviceName;
    _offset = widget.initialOffset;
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _syncUrl() {
    final q = <String, String>{};
    if (_kindFilter != null) q['type'] = _kindFilter!;
    if (_levelFilter != null) q['level'] = _levelFilter!;
    if (_categoryFilter != null) q['category'] = _categoryFilter!;
    q.addAll(_period.toQuery());
    if (_search.isNotEmpty) q['q'] = _search;
    if (_country != null) q['country'] = _country!;
    if (_environment != null) q['environment'] = _environment!;
    if (_appVersion != null) q['appVersion'] = _appVersion!;
    if (_deviceName != null) q['device'] = _deviceName!;
    if (_offset > 0) q['offset'] = '$_offset';
    final uri = Uri(path: '/p/${widget.projectId}/events', queryParameters: q.isEmpty ? null : q);
    context.go(uri.toString());
  }

  Future<void> _load({bool resetOffset = false}) async {
    if (resetOffset) _offset = 0;
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
      final page = await _api.fetchEvents(
        widget.projectId,
        type: _kindFilter,
        level: _levelFilter,
        category: _categoryFilter,
        period: _period,
        q: _search.isEmpty ? null : _search,
        country: _country,
        environment: _environment,
        appVersion: _appVersion,
        deviceName: _deviceName,
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _events = jsonListMaps(page['events']);
        _total = page['total'] as int? ?? _events.length;
        _hasMore = page['hasMore'] == true;
        _offset = page['offset'] as int? ?? _offset;
        _hasData = true;
        _loading = false;
        _refreshing = false;
      });
      _loadFacets();
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _loadFacets() async {
    try {
      final facets = await _api.fetchFilterFacets(widget.projectId, period: _period);
      if (!mounted) return;
      setState(() {
        _environments = (facets['environments'] as List?)?.map((e) => e.toString()).toList() ?? [];
        _appVersions = (facets['appVersions'] as List?)?.map((e) => e.toString()).toList() ?? [];
        _deviceNames = (facets['deviceNames'] as List?)?.map((e) => e.toString()).toList() ?? [];
      });
    } catch (_) {}
  }

  void _apply({
    String? kind,
    bool setKind = false,
    String? level,
    bool setLevel = false,
    String? category,
    bool setCategory = false,
    PeriodFilter? period,
    String? search,
    String? country,
    bool clearCountry = false,
    String? environment,
    bool setEnvironment = false,
    bool clearEnvironment = false,
    String? appVersion,
    bool setAppVersion = false,
    bool clearAppVersion = false,
    String? deviceName,
    bool setDeviceName = false,
    bool clearDeviceName = false,
  }) {
    setState(() {
      if (setKind) _kindFilter = kind;
      if (setLevel) _levelFilter = level;
      if (setCategory) _categoryFilter = category;
      if (period != null) _period = period;
      if (search != null) _search = search;
      if (country != null) _country = country;
      if (clearCountry) _country = null;
      if (setEnvironment) _environment = environment;
      if (clearEnvironment) _environment = null;
      if (setAppVersion) _appVersion = appVersion;
      if (clearAppVersion) _appVersion = null;
      if (setDeviceName) _deviceName = deviceName;
      if (clearDeviceName) _deviceName = null;
      _offset = 0;
    });
    _syncUrl();
    _load();
  }

  void _page(int offset) {
    _offset = offset;
    _syncUrl();
    _load();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String _filterSummary() {
    final parts = <String>[_period.label()];
    if (_levelFilter != null) parts.add('level $_levelFilter');
    if (_kindFilter != null) parts.add('kind $_kindFilter');
    if (_categoryFilter != null) parts.add('category $_categoryFilter');
    if (_environment != null) parts.add(_environment!);
    if (_appVersion != null) parts.add('v$_appVersion');
    if (_deviceName != null) parts.add(_deviceName!);
    if (_total == 0) return '${parts.join(' · ')} · 0 events';
    final from = _offset + 1;
    final to = _offset + _events.length;
    return '${parts.join(' · ')} · showing $from–$to of $_total';
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: (p) => _apply(period: p));

  @override
  Widget build(BuildContext context) {
    final pad = pagePad(context);
    final insets = pageInsets(context);
    final page = _total == 0 ? 1 : (_offset ~/ _pageSize) + 1;
    final pages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _load(),
          child: CustomScrollView(
            key: PageStorageKey('events-${widget.projectId}'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: insets.copyWith(top: pad),
                sliver: SliverToBoxAdapter(
                  child: PageHeader(
                    title: 'Events',
                    subtitle: _filterSummary(),
                    period: _period,
                    onPeriodTap: _openPeriodPicker,
                    actions: [IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh))],
                  ),
                ),
              ),
              SliverPadding(
                padding: insets.copyWith(top: 12),
                sliver: SliverToBoxAdapter(
                  child: FilterBar(
                    period: _period,
                    onPeriodChanged: (p) => _apply(period: p),
                    searchHint: 'Message, URL, device, trace ID, user, session…',
                    searchValue: _search,
                    onSearch: (q) => _apply(search: q),
                    levelOptions: _levelOptions,
                    levelSelected: _levelFilter,
                    onLevelSelected: (l) => _apply(level: l, setLevel: true),
                    typeOptions: _kindOptions,
                    typeSelected: _kindFilter,
                    onTypeSelected: (t) => _apply(kind: t, setKind: true),
                    categoryOptions: _categoryOptions,
                    categorySelected: _categoryFilter,
                    onCategorySelected: (c) => _apply(category: c, setCategory: true),
                    environmentOptions: _environments,
                    environmentSelected: _environment,
                    onEnvironmentSelected: (e) => _apply(environment: e, setEnvironment: true, clearEnvironment: e == null),
                    appVersionOptions: _appVersions,
                    appVersionSelected: _appVersion,
                    onAppVersionSelected: (v) => _apply(appVersion: v, setAppVersion: true, clearAppVersion: v == null),
                    deviceNameOptions: _deviceNames,
                    deviceNameSelected: _deviceName,
                    onDeviceNameSelected: (v) => _apply(deviceName: v, setDeviceName: true, clearDeviceName: v == null),
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(hasScrollBody: false, child: LoadingView(layout: PlaceholderLayout.events))
              else if (_error != null && !_hasData)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorPanel(message: formatLoadError(_error!), onRetry: () => _load()),
                )
              else if (_events.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No events',
                    subtitle: 'Try adjusting filters or the time range',
                  ),
                )
              else ...[
                SliverPadding(
                  padding: insets.copyWith(top: 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => EventCard(
                        event: _events[i],
                        onTap: () => context.push('/p/${widget.projectId}/events/${_events[i]['id']}'),
                      ),
                      childCount: _events.length,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: insets.copyWith(top: 8, bottom: pad),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.panel,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Page $page of $pages · $_total total',
                              style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: _offset > 0 && !_loading ? () => _page((_offset - _pageSize).clamp(0, _total)) : null,
                            child: const Text('Previous'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _hasMore && !_loading ? () => _page(_offset + _pageSize) : null,
                            child: const Text('Next'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_refreshing)
          Positioned.fill(
            child: ColoredBox(
              color: AppTheme.bg.withValues(alpha: 0.92),
              child: const ScoutRefreshShimmer(layout: PlaceholderLayout.events),
            ),
          ),
      ],
    );
  }
}
