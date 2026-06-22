import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_bar.dart';
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
  });

  final String projectId;
  final String? initialType;
  final String? initialStatus;
  final PeriodFilter initialPeriod;
  final String? initialQuery;
  final String? initialEnvironment;
  final String? initialAppVersion;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _issues = [];
  List<String> _environments = [];
  List<String> _appVersions = [];
  bool _loading = true;
  String? _error;
  late String? _typeFilter;
  late String? _statusFilter;
  late PeriodFilter _period;
  late String _search;
  String? _environment;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.initialType;
    _statusFilter = widget.initialStatus;
    _period = widget.initialPeriod;
    _search = widget.initialQuery ?? '';
    _environment = widget.initialEnvironment;
    _appVersion = widget.initialAppVersion;
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
    context.go(Uri(path: '/p/${widget.projectId}/issues', queryParameters: q.isEmpty ? null : q).toString());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchIssues(
          widget.projectId,
          type: _typeFilter,
          status: _statusFilter,
          period: _period,
          q: _search.isEmpty ? null : _search,
          environment: _environment,
          appVersion: _appVersion,
        ),
        _api.fetchFilterFacets(widget.projectId, period: _period),
      ]);
      if (mounted) {
        final facets = results[1] as Map<String, dynamic>;
        setState(() {
          _issues = results[0] as List<Map<String, dynamic>>;
          _environments = (facets['environments'] as List?)?.map((e) => e.toString()).toList() ?? [];
          _appVersions = (facets['appVersions'] as List?)?.map((e) => e.toString()).toList() ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
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
    });
    _syncUrl();
    _load();
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: (p) => _apply(period: p));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: pageInsets(context, top: pagePad(context)),
          child: PageHeader(
            title: 'Issues',
            subtitle: '${_issues.length} grouped errors and crashes',
            period: _period,
            onPeriodTap: _openPeriodPicker,
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Padding(
          padding: pageInsets(context, top: 12),
          child: FilterBar(
            period: _period,
            onPeriodChanged: (p) => _apply(period: p),
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
            extra: [
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(label: const Text('All status'), selected: _statusFilter == null, onSelected: (_) => _apply(status: null, reloadStatus: true)),
                  FilterChip(label: const Text('Open'), selected: _statusFilter == 'open', onSelected: (_) => _apply(status: 'open', reloadStatus: true)),
                  FilterChip(label: const Text('Resolved'), selected: _statusFilter == 'resolved', onSelected: (_) => _apply(status: 'resolved', reloadStatus: true)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? ErrorPanel(message: _error!, onRetry: _load)
                  : _issues.isEmpty
                      ? const EmptyState(
                          icon: Icons.check_circle_outline,
                          title: 'No issues match filters',
                          subtitle: 'When your app sends errors, they appear here grouped by fingerprint.',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            key: PageStorageKey('issues-${widget.projectId}'),
                            padding: pageInsets(context, top: 12, bottom: pagePad(context)),
                            itemCount: _issues.length,
                            itemBuilder: (_, i) => IssueCard(
                              issue: _issues[i],
                              onTap: () => context.push('/p/${widget.projectId}/issues/${_issues[i]['id']}'),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}
