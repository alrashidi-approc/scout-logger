import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../services/screen_cache.dart';
import '../widgets/event_card.dart';
import '../widgets/event_group_card.dart';
import '../widgets/route_link.dart';
import '../widgets/filter_bar.dart';
import '../theme/app_theme.dart';
import '../utils/project_list_filters.dart';
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
    this.initialView = 'focus',
    this.initialGroupKey,
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
  final String initialView;
  final String? initialGroupKey;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> with ProjectListFilters {
  static const _pageSize = 50;

  final _scroll = ScrollController();
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _groups = [];
  int _offset = 0;
  int _total = 0;
  bool _hasMore = false;
  late String? _kindFilter;
  late String? _levelFilter;
  late String? _categoryFilter;
  String? _country;
  late String _view;
  String? _groupKey;

  @override
  String get projectId => widget.projectId;

  bool get _isGrouped => _view == 'grouped' && (_groupKey == null || _groupKey!.isEmpty);

  String get _cacheKey => screenCacheKey(
        'events',
        projectId: widget.projectId,
        period: period,
        extra: {
          'type': _kindFilter,
          'level': _levelFilter,
          'category': _categoryFilter,
          'q': search.isEmpty ? null : search,
          'country': _country,
          'environment': environment,
          'appVersion': appVersion,
          'device': deviceName,
          'view': _view,
          'group': _groupKey,
        },
      );

  static const _levelOptions = [null, 'error', 'info', 'warning', 'success'];
  static const _kindOptions = [null, 'errors', 'error', 'crash', 'network', 'session', 'log', 'span'];
  static const _categoryOptions = [null, 'network', 'system', 'crashing', 'logic', 'ui'];

  @override
  void initState() {
    super.initState();
    _kindFilter = widget.initialType;
    _levelFilter = widget.initialLevel;
    _categoryFilter = widget.initialCategory;
    period = widget.initialPeriod;
    search = widget.initialQuery ?? '';
    _country = widget.initialCountry;
    environment = widget.initialEnvironment;
    appVersion = widget.initialAppVersion;
    deviceName = widget.initialDeviceName;
    _offset = widget.initialOffset;
    _view = switch (widget.initialView) {
      'all' || 'grouped' || 'focus' => widget.initialView,
      _ => 'focus',
    };
    _groupKey = widget.initialGroupKey;
    if (!_restore()) _load();
  }

  bool _restore() {
    final cached = ScreenCache.instance.read<Map<String, Object>>(_cacheKey);
    if (cached == null) return false;
    final events = cached['events'];
    if (events is! List) return false;
    _events = events.cast<Map<String, dynamic>>();
    final groups = cached['groups'];
    _groups = groups is List ? groups.cast<Map<String, dynamic>>() : [];
    _offset = cached['offset'] as int? ?? 0;
    _total = cached['total'] as int? ?? (_isGrouped ? _groups.length : _events.length);
    _hasMore = cached['hasMore'] == true;
    restoreFacets(cached);
    return true;
  }

  @override
  void writeCache() {
    ScreenCache.instance.write(_cacheKey, {
      'events': _events,
      'groups': _groups,
      'offset': _offset,
      'total': _total,
      'hasMore': _hasMore,
      ...facetCache,
    });
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
    q.addAll(period.toQuery());
    if (search.isNotEmpty) q['q'] = search;
    if (_country != null) q['country'] = _country!;
    q.addAll(facetQuery);
    if (_view != 'focus' || _groupKey != null) q['view'] = _groupKey != null ? 'all' : _view;
    if (_groupKey != null) q['group'] = _groupKey!;
    if (_offset > 0) q['offset'] = '$_offset';
    final uri = Uri(path: '/p/${widget.projectId}/events', queryParameters: q.isEmpty ? null : q);
    context.go(uri.toString());
  }

  Future<void> _load({bool resetOffset = false}) {
    if (resetOffset) _offset = 0;
    return loadList(
      () => api.fetchEvents(
        widget.projectId,
        type: _kindFilter,
        level: _levelFilter,
        category: _categoryFilter,
        period: period,
        q: search.isEmpty ? null : search,
        country: _country,
        environment: environment,
        appVersion: appVersion,
        deviceName: deviceName,
        limit: _pageSize,
        offset: _offset,
        view: _groupKey != null ? 'all' : _view,
        groupKey: _groupKey,
      ),
      (page) {
        _events = jsonListMaps(page['events']);
        _groups = jsonListMaps(page['groups']);
        _total = page['total'] as int? ?? (_isGrouped ? _groups.length : _events.length);
        _hasMore = page['hasMore'] == true;
        _offset = page['offset'] as int? ?? _offset;
      },
    );
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
    String? view,
    String? groupKey,
    bool clearGroup = false,
  }) {
    setState(() {
      if (setKind) _kindFilter = kind;
      if (setLevel) _levelFilter = level;
      if (setCategory) _categoryFilter = category;
      if (period != null) this.period = period;
      if (search != null) this.search = search;
      if (country != null) _country = country;
      if (clearCountry) _country = null;
      if (setEnvironment) this.environment = environment;
      if (clearEnvironment) this.environment = null;
      if (setAppVersion) this.appVersion = appVersion;
      if (clearAppVersion) this.appVersion = null;
      if (setDeviceName) this.deviceName = deviceName;
      if (clearDeviceName) this.deviceName = null;
      if (view != null) {
        _view = view;
        if (view == 'grouped') _groupKey = null;
      }
      if (groupKey != null) {
        _groupKey = groupKey;
        _view = 'all';
      }
      if (clearGroup) _groupKey = null;
      _offset = 0;
    });
    _syncUrl();
    if (_restore()) {
      setState(() {});
    } else {
      _load();
    }
  }

  void _page(int offset) {
    _offset = offset;
    _syncUrl();
    _load();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String _filterSummary() {
    final parts = <String>[period.label()];
    parts.add(switch (_groupKey != null ? 'members' : _view) {
      'all' => 'all',
      'grouped' => 'grouped',
      'members' => 'group members',
      _ => 'focus',
    });
    if (_levelFilter != null) parts.add('level $_levelFilter');
    if (_kindFilter != null) parts.add('kind $_kindFilter');
    if (_categoryFilter != null) parts.add('category $_categoryFilter');
    if (environment != null) parts.add(environment!);
    if (appVersion != null) parts.add('v$appVersion');
    if (deviceName != null) parts.add(deviceName!);
    final shown = _isGrouped ? _groups.length : _events.length;
    if (_total == 0) return '${parts.join(' · ')} · 0 ${_isGrouped ? 'groups' : 'events'}';
    final from = _offset + 1;
    final to = _offset + shown;
    return '${parts.join(' · ')} · showing $from–$to of $_total';
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: period, onSelected: (p) => _apply(period: p));

  void _openGroup(Map<String, dynamic> group) {
    final key = group['key']?.toString();
    if (key == null || key.isEmpty) return;
    if (key.startsWith('issue|')) {
      final issueId = group['issueId']?.toString() ?? key.substring(6);
      context.push('/p/${widget.projectId}/issues/$issueId');
      return;
    }
    _apply(groupKey: key);
  }

  String _groupBackLabel() {
    final key = _groupKey!;
    final parts = key.split('|');
    final label = parts.length > 1 ? parts.sublist(1).join('|') : key;
    return label.isEmpty ? key : label;
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePad(context);
    final insets = pageInsets(context);
    final page = _total == 0 ? 1 : (_offset ~/ _pageSize) + 1;
    final pages = _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);
    final empty = _isGrouped ? _groups.isEmpty : _events.isEmpty;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _load(resetOffset: true),
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
                    period: period,
                    onPeriodTap: _openPeriodPicker,
                    actions: [IconButton(onPressed: () => _load(resetOffset: true), icon: const Icon(Icons.refresh))],
                  ),
                ),
              ),
              SliverPadding(
                padding: insets.copyWith(top: 12),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'focus',
                            label: Text('Focus'),
                            icon: Icon(Icons.center_focus_strong, size: 16),
                          ),
                          ButtonSegment(
                            value: 'all',
                            label: Text('All'),
                            icon: Icon(Icons.list, size: 16),
                          ),
                          ButtonSegment(
                            value: 'grouped',
                            label: Text('Grouped'),
                            icon: Icon(Icons.layers_outlined, size: 16),
                          ),
                        ],
                        selected: {_groupKey != null ? 'all' : _view},
                        onSelectionChanged: (s) => _apply(view: s.first, clearGroup: true),
                      ),
                      if (_groupKey != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _apply(view: 'grouped', clearGroup: true),
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: Text('Back to groups · ${_groupBackLabel()}'),
                          ),
                        ),
                      ] else if (_view == 'focus') ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Hiding routine session_start / lifecycle noise — switch to All or Grouped to see them',
                          style: TextStyle(fontSize: 12, color: AppTheme.muted),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilterBar(
                        period: period,
                        onPeriodChanged: (p) => _apply(period: p),
                        includeHourPresets: true,
                        searchHint: 'Message, URL, device, trace ID, user, session…',
                        searchValue: search,
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
                        environmentOptions: environments,
                        environmentSelected: environment,
                        onEnvironmentSelected: (e) =>
                            _apply(environment: e, setEnvironment: true, clearEnvironment: e == null),
                        appVersionOptions: appVersions,
                        appVersionSelected: appVersion,
                        onAppVersionSelected: (v) =>
                            _apply(appVersion: v, setAppVersion: true, clearAppVersion: v == null),
                        deviceNameOptions: deviceNames,
                        deviceNameSelected: deviceName,
                        onDeviceNameSelected: (v) =>
                            _apply(deviceName: v, setDeviceName: true, clearDeviceName: v == null),
                      ),
                    ],
                  ),
                ),
              ),
              if (loading)
                const SliverFillRemaining(hasScrollBody: false, child: LoadingView(layout: PlaceholderLayout.events))
              else if (error != null && !hasData)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorPanel(message: formatLoadError(error!), onRetry: () => _load()),
                )
              else if (empty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No events',
                    subtitle: 'Try Focus→All, adjust filters, or widen the time range',
                  ),
                )
              else ...[
                SliverPadding(
                  padding: insets.copyWith(top: 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        if (_isGrouped) {
                          return EventGroupCard(group: _groups[i], onTap: () => _openGroup(_groups[i]));
                        }
                        return RouteLink(
                          path: '/p/${widget.projectId}/events/${_events[i]['id']}',
                          builder: (open) => EventCard(event: _events[i], onTap: open),
                        );
                      },
                      childCount: _isGrouped ? _groups.length : _events.length,
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
                            onPressed:
                                _offset > 0 && !loading ? () => _page((_offset - _pageSize).clamp(0, _total)) : null,
                            child: const Text('Previous'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _hasMore && !loading ? () => _page(_offset + _pageSize) : null,
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
        if (refreshing)
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
