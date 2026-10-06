import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/screen_cache.dart';
import '../widgets/event_card.dart';
import '../widgets/route_link.dart';
import '../widgets/filter_bar.dart';
import '../theme/app_theme.dart';
import '../utils/project_list_filters.dart';
import '../widgets/page_header.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../widgets/period_picker.dart';

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({
    super.key,
    required this.projectId,
    this.initialType,
    this.initialStatus,
    this.initialPeriod = const PeriodFilter.days(30),
    this.initialQuery,
    this.initialEnvironment,
    this.initialAppVersion,
    this.initialDeviceName,
    this.initialHideNoise = false,
    this.initialByPriority = false,
    this.initialFirstRelease,
  });

  final String projectId;
  final String? initialType;
  final String? initialStatus;
  final PeriodFilter initialPeriod;
  final String? initialQuery;
  final String? initialEnvironment;
  final String? initialAppVersion;
  final String? initialDeviceName;
  final bool initialHideNoise;
  final bool initialByPriority;
  final String? initialFirstRelease;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> with ProjectListFilters {
  List<Map<String, dynamic>> _issues = [];
  bool _sortBySeverity = false;

  static const _sevRank = {'high': 0, 'medium': 1, 'low': 2};

  List<Map<String, dynamic>> get _displayIssues {
    if (!_sortBySeverity) return _issues;
    final sorted = [..._issues];
    sorted.sort((a, b) =>
        (_sevRank[a['severity']] ?? 3).compareTo(_sevRank[b['severity']] ?? 3));
    return sorted;
  }
  late String? _typeFilter;
  late String? _statusFilter;
  late bool _hideNoise = widget.initialHideNoise;
  late bool _byPriority = widget.initialByPriority;
  late String? _firstRelease = widget.initialFirstRelease;

  @override
  String get projectId => widget.projectId;

  String get _cacheKey => screenCacheKey(
        'issues',
        projectId: widget.projectId,
        period: period,
        extra: {
          'type': _typeFilter,
          'status': _statusFilter,
          'q': search.isEmpty ? null : search,
          'environment': environment,
          'appVersion': appVersion,
          'device': deviceName,
          'noise': _hideNoise ? 'hide' : null,
          'sort': _byPriority ? 'priority' : null,
          'firstRelease': _firstRelease,
        },
      );

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.initialType;
    _statusFilter = widget.initialStatus;
    period = widget.initialPeriod;
    search = widget.initialQuery ?? '';
    environment = widget.initialEnvironment;
    appVersion = widget.initialAppVersion;
    deviceName = widget.initialDeviceName;
    if (!_restore()) _load();
  }

  bool _restore() {
    final cached = ScreenCache.instance.read<Map<String, Object>>(_cacheKey);
    if (cached == null) return false;
    final issues = cached['issues'];
    if (issues is! List) return false;
    _issues = issues.cast<Map<String, dynamic>>();
    restoreFacets(cached);
    return true;
  }

  @override
  void writeCache() => ScreenCache.instance.write(_cacheKey, {'issues': _issues, ...facetCache});

  void _syncUrl() {
    final q = <String, String>{};
    if (_typeFilter != null) q['type'] = _typeFilter!;
    if (_statusFilter != null) q['status'] = _statusFilter!;
    q.addAll(period.toQuery());
    if (search.isNotEmpty) q['q'] = search;
    q.addAll(facetQuery);
    if (_hideNoise) q['noise'] = 'hide';
    if (_byPriority) q['sort'] = 'priority';
    if (_firstRelease case final r?) q['firstRelease'] = r;
    context.go(Uri(path: '/p/${widget.projectId}/issues', queryParameters: q.isEmpty ? null : q).toString());
  }

  Future<void> _load() => loadList(
        () => api.fetchIssues(
          widget.projectId,
          type: _typeFilter,
          status: _statusFilter,
          period: period,
          q: search.isEmpty ? null : search,
          environment: environment,
          appVersion: appVersion,
          deviceName: deviceName,
          hideNoise: _hideNoise,
          byPriority: _byPriority,
          firstRelease: _firstRelease,
        ),
        (issues) => _issues = issues,
      );

  void _apply({
    String? type,
    String? status,
    PeriodFilter? period,
    String? search,
    bool reloadType = false,
    bool reloadStatus = false,
    String? environment,
    bool setEnvironment = false,
    bool clearEnvironment = false,
    String? appVersion,
    bool setAppVersion = false,
    bool clearAppVersion = false,
    String? deviceName,
    bool setDeviceName = false,
    bool clearDeviceName = false,
    bool? hideNoise,
    bool? byPriority,
    String? firstRelease,
  }) {
    setState(() {
      if (hideNoise != null) _hideNoise = hideNoise;
      if (byPriority != null) {
        _byPriority = byPriority;
        if (byPriority) _sortBySeverity = false;
      }
      if (firstRelease != null) _firstRelease = firstRelease.trim().isEmpty ? null : firstRelease.trim();
      if (reloadType) _typeFilter = type;
      if (reloadStatus) _statusFilter = status;
      if (period != null) this.period = period;
      if (search != null) this.search = search;
      if (setEnvironment) this.environment = environment;
      if (clearEnvironment) this.environment = null;
      if (setAppVersion) this.appVersion = appVersion;
      if (clearAppVersion) this.appVersion = null;
      if (setDeviceName) this.deviceName = deviceName;
      if (clearDeviceName) this.deviceName = null;
    });
    _syncUrl();
    if (_restore()) {
      setState(() {});
    } else {
      _load();
    }
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: period, onSelected: (p) => _apply(period: p));

  @override
  Widget build(BuildContext context) {
    final pad = pagePad(context);
    final insets = pageInsets(context);
    final totalEvents = _issues.fold<int>(0, (s, i) => s + (i['eventCount'] as int? ?? 0));

    return Stack(
      children: [
        RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        key: PageStorageKey('issues-${widget.projectId}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: insets.copyWith(top: pad),
            sliver: SliverToBoxAdapter(
              child: PageHeader(
                title: 'Issues',
                subtitle: '${_issues.length} issues · $totalEvents events · ${period.label()}',
                period: period,
                onPeriodTap: _openPeriodPicker,
                actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
              ),
            ),
          ),
          SliverPadding(
            padding: insets.copyWith(top: 12),
            sliver: SliverToBoxAdapter(
              child: FilterBar(
                period: period,
                onPeriodChanged: (p) => _apply(period: p),
                includeHourPresets: true,
                searchHint: 'Title, user id, device id, email…',
                searchValue: search,
                onSearch: (q) => _apply(search: q),
                typeOptions: const [null, 'error', 'crash', 'network'],
                typeSelected: _typeFilter,
                onTypeSelected: (t) => _apply(type: t, reloadType: true),
                environmentOptions: environments,
                environmentSelected: environment,
                onEnvironmentSelected: (e) => _apply(environment: e, setEnvironment: true, clearEnvironment: e == null),
                appVersionOptions: appVersions,
                appVersionSelected: appVersion,
                onAppVersionSelected: (v) => _apply(appVersion: v, setAppVersion: true, clearAppVersion: v == null),
                deviceNameOptions: deviceNames,
                deviceNameSelected: deviceName,
                onDeviceNameSelected: (v) => _apply(deviceName: v, setDeviceName: true, clearDeviceName: v == null),
                extra: [
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(label: const Text('All status'), selected: _statusFilter == null, onSelected: (_) => _apply(status: null, reloadStatus: true)),
                      FilterChip(label: const Text('Open'), selected: _statusFilter == 'open', onSelected: (_) => _apply(status: 'open', reloadStatus: true)),
                      FilterChip(label: const Text('Resolved'), selected: _statusFilter == 'resolved', onSelected: (_) => _apply(status: 'resolved', reloadStatus: true)),
                      FilterChip(label: const Text('Muted'), selected: _statusFilter == 'ignored', onSelected: (_) => _apply(status: 'ignored', reloadStatus: true)),
                      FilterChip(
                        avatar: const Icon(Icons.sort, size: 16),
                        label: const Text('Sort by severity'),
                        selected: _sortBySeverity,
                        onSelected: (v) => setState(() => _sortBySeverity = v),
                      ),
                      FilterChip(
                        avatar: const Icon(Icons.low_priority, size: 16),
                        label: const Text('Sort by priority'),
                        selected: _byPriority && !_sortBySeverity,
                        onSelected: (v) => _apply(byPriority: v),
                      ),
                      FilterChip(
                        avatar: const Icon(Icons.volume_off_outlined, size: 16),
                        label: const Text('Hide noise'),
                        selected: _hideNoise,
                        onSelected: (v) => _apply(hideNoise: v),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextFormField(
                          key: ValueKey(_firstRelease),
                          initialValue: _firstRelease,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'New in release…',
                            prefixIcon: Icon(Icons.new_releases_outlined, size: 16),
                          ),
                          onFieldSubmitted: (v) => _apply(firstRelease: v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (loading)
            const SliverFillRemaining(hasScrollBody: false, child: LoadingView(layout: PlaceholderLayout.issues))
          else if (error != null && !hasData)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorPanel(message: formatLoadError(error!), onRetry: _load),
            )
          else if (_issues.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.check_circle_outline,
                title: 'No issues match filters',
                subtitle: 'When your app sends errors, they appear here grouped by fingerprint.',
              ),
            )
          else
            SliverPadding(
              padding: insets.copyWith(top: 12, bottom: pad),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final issues = _displayIssues;
                    return RouteLink(
                      path: '/p/${widget.projectId}/issues/${issues[i]['id']}',
                      builder: (open) => IssueCard(issue: issues[i], onTap: open ?? () {}),
                    );
                  },
                  childCount: _issues.length,
                ),
              ),
            ),
        ],
      ),
    ),
        if (refreshing)
          Positioned.fill(
            child: ColoredBox(
              color: AppTheme.bg.withValues(alpha: 0.92),
              child: const ScoutRefreshShimmer(layout: PlaceholderLayout.issues),
            ),
          ),
      ],
    );
  }
}
