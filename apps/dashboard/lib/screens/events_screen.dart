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

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _events = [];
  List<String> _environments = [];
  List<String> _appVersions = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  late String? _kindFilter;
  late String? _levelFilter;
  late String? _categoryFilter;
  late PeriodFilter _period;
  late String _search;
  String? _country;
  String? _environment;
  String? _appVersion;

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
    _load();
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
    final uri = Uri(path: '/p/${widget.projectId}/events', queryParameters: q.isEmpty ? null : q);
    context.go(uri.toString());
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
      final events = await _api.fetchEvents(
        widget.projectId,
        type: _kindFilter,
        level: _levelFilter,
        category: _categoryFilter,
        period: _period,
        q: _search.isEmpty ? null : _search,
        country: _country,
        environment: _environment,
        appVersion: _appVersion,
      );
      if (!mounted) return;
      setState(() {
        _events = events;
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
    });
    _syncUrl();
    _load();
  }

  String _filterSummary() {
    final parts = <String>[];
    if (_levelFilter != null) parts.add('level $_levelFilter');
    if (_kindFilter != null) parts.add('kind $_kindFilter');
    if (_categoryFilter != null) parts.add('category $_categoryFilter');
    if (_environment != null) parts.add(_environment!);
    if (_appVersion != null) parts.add('v$_appVersion');
    if (parts.isEmpty) return '${_events.length} events';
    return '${_events.length} events · ${parts.join(' · ')}';
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: (p) => _apply(period: p));

  @override
  Widget build(BuildContext context) {
    final pad = pagePad(context);
    final insets = pageInsets(context);

    return Stack(
      children: [
        RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        key: PageStorageKey('events-${widget.projectId}'),
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
                actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
              ),
            ),
          ),
          SliverPadding(
            padding: insets.copyWith(top: 12),
            sliver: SliverToBoxAdapter(
              child: FilterBar(
                period: _period,
                onPeriodChanged: (p) => _apply(period: p),
                searchHint: 'Message, URL, trace ID, user, session…',
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
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(hasScrollBody: false, child: LoadingView(layout: PlaceholderLayout.events))
          else if (_error != null && !_hasData)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorPanel(message: formatLoadError(_error!), onRetry: _load),
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
          else
            SliverPadding(
              padding: insets.copyWith(top: 12, bottom: pad),
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
