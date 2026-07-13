import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../widgets/event_card.dart';
import '../widgets/route_link.dart';
import '../widgets/filter_bar.dart';
import '../theme/app_theme.dart';
import '../utils/screen_load.dart';
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
  });

  final String projectId;
  final String? initialType;
  final String? initialStatus;
  final PeriodFilter initialPeriod;
  final String? initialQuery;
  final String? initialEnvironment;
  final String? initialAppVersion;
  final String? initialDeviceName;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  final _api = ScoutApi();
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
  List<String> _environments = [];
  List<String> _appVersions = [];
  List<String> _deviceNames = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  late String? _typeFilter;
  late String? _statusFilter;
  late PeriodFilter _period;
  late String _search;
  String? _environment;
  String? _appVersion;
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.initialType;
    _statusFilter = widget.initialStatus;
    _period = widget.initialPeriod;
    _search = widget.initialQuery ?? '';
    _environment = widget.initialEnvironment;
    _appVersion = widget.initialAppVersion;
    _deviceName = widget.initialDeviceName;
    _load();
  }

  void _syncUrl() {
    final q = <String, String>{};
    if (_typeFilter != null) q['type'] = _typeFilter!;
    if (_statusFilter != null) q['status'] = _statusFilter!;
    q.addAll(_period.toQuery());
    if (_search.isNotEmpty) q['q'] = _search;
    if (_environment != null) q['environment'] = _environment!;
    if (_appVersion != null) q['appVersion'] = _appVersion!;
    if (_deviceName != null) q['device'] = _deviceName!;
    context.go(Uri(path: '/p/${widget.projectId}/issues', queryParameters: q.isEmpty ? null : q).toString());
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
      final issues = await _api.fetchIssues(
        widget.projectId,
        type: _typeFilter,
        status: _statusFilter,
        period: _period,
        q: _search.isEmpty ? null : _search,
        environment: _environment,
        appVersion: _appVersion,
        deviceName: _deviceName,
      );
      if (!mounted) return;
      setState(() {
        _issues = issues;
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
      final facets = await _api.fetchFilterFacets(
        widget.projectId,
        period: _period,
        environment: _environment,
        appVersion: _appVersion,
        deviceName: _deviceName,
      );
      if (!mounted) return;
      setState(() {
        _environments = (facets['environments'] as List?)?.map((e) => e.toString()).toList() ?? [];
        _appVersions = (facets['appVersions'] as List?)?.map((e) => e.toString()).toList() ?? [];
        _deviceNames = (facets['deviceNames'] as List?)?.map((e) => e.toString()).toList() ?? [];
      });
    } catch (_) {}
  }

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
  }) {
    setState(() {
      if (reloadType) _typeFilter = type;
      if (reloadStatus) _statusFilter = status;
      if (period != null) _period = period;
      if (search != null) _search = search;
      if (setEnvironment) _environment = environment;
      if (clearEnvironment) _environment = null;
      if (setAppVersion) _appVersion = appVersion;
      if (clearAppVersion) _appVersion = null;
      if (setDeviceName) _deviceName = deviceName;
      if (clearDeviceName) _deviceName = null;
    });
    _syncUrl();
    _load();
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: (p) => _apply(period: p));

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
                subtitle: '${_issues.length} issues · $totalEvents events · ${_period.label()}',
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
                includeHourPresets: true,
                searchHint: 'Search issue title…',
                searchValue: _search,
                onSearch: (q) => _apply(search: q),
                typeOptions: const [null, 'error', 'crash', 'network'],
                typeSelected: _typeFilter,
                onTypeSelected: (t) => _apply(type: t, reloadType: true),
                environmentOptions: _environments,
                environmentSelected: _environment,
                onEnvironmentSelected: (e) => _apply(environment: e, setEnvironment: true, clearEnvironment: e == null),
                appVersionOptions: _appVersions,
                appVersionSelected: _appVersion,
                onAppVersionSelected: (v) => _apply(appVersion: v, setAppVersion: true, clearAppVersion: v == null),
                deviceNameOptions: _deviceNames,
                deviceNameSelected: _deviceName,
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
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(hasScrollBody: false, child: LoadingView(layout: PlaceholderLayout.issues))
          else if (_error != null && !_hasData)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorPanel(message: formatLoadError(_error!), onRetry: _load),
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
        if (_refreshing)
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
