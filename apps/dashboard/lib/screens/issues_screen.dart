import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_bar.dart';
import '../utils/responsive.dart';
import '../widgets/page_header.dart';

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({
    super.key,
    required this.projectId,
    this.initialType,
    this.initialStatus,
    this.initialDays,
    this.initialQuery,
  });

  final String projectId;
  final String? initialType;
  final String? initialStatus;
  final int? initialDays;
  final String? initialQuery;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _issues = [];
  bool _loading = true;
  String? _error;
  late String? _typeFilter = widget.initialType;
  late String? _statusFilter = widget.initialStatus;
  late int? _days = widget.initialDays;
  late String _search = widget.initialQuery ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _syncUrl() {
    final q = <String, String>{};
    if (_typeFilter != null) q['type'] = _typeFilter!;
    if (_statusFilter != null) q['status'] = _statusFilter!;
    if (_days != null) q['days'] = '$_days';
    if (_search.isNotEmpty) q['q'] = _search;
    context.go(Uri(path: '/p/${widget.projectId}/issues', queryParameters: q.isEmpty ? null : q).toString());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final issues = await _api.fetchIssues(
        widget.projectId,
        type: _typeFilter,
        status: _statusFilter,
        days: _days,
        q: _search.isEmpty ? null : _search,
      );
      if (mounted) setState(() {
        _issues = issues;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _apply({String? type, String? status, int? days, String? search, bool reloadType = false, bool reloadStatus = false}) {
    setState(() {
      if (reloadType) _typeFilter = type;
      if (reloadStatus) _statusFilter = status;
      if (days != null) _days = days;
      if (search != null) _search = search;
    });
    _syncUrl();
    _load();
  }

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
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Padding(
          padding: pageInsets(context, top: 12),
          child: FilterBar(
            days: _days ?? 30,
            onDaysChanged: (d) => _apply(days: d),
            searchHint: 'Search issue title…',
            searchValue: _search,
            onSearch: (q) => _apply(search: q),
            typeOptions: const [null, 'error', 'crash', 'network'],
            typeSelected: _typeFilter,
            onTypeSelected: (t) => _apply(type: t, reloadType: true),
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
