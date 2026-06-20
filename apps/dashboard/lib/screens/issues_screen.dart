import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../widgets/event_card.dart';
import '../widgets/page_header.dart';

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _issues = [];
  bool _loading = true;
  String? _error;
  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final issues = await _api.fetchIssues(widget.projectId);
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

  List<Map<String, dynamic>> get _filtered {
    if (_typeFilter == null) return _issues;
    return _issues.where((i) => i['type'] == _typeFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _load);

    final filtered = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: PageHeader(
            title: 'Issues',
            subtitle: '${_issues.length} grouped errors and crashes',
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(label: const Text('All'), selected: _typeFilter == null, onSelected: (_) => setState(() => _typeFilter = null)),
              for (final t in ['error', 'crash', 'network'])
                FilterChip(label: Text(t), selected: _typeFilter == t, onSelected: (_) => setState(() => _typeFilter = t)),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'No issues yet',
                  subtitle: 'When your app sends errors, they appear here grouped by fingerprint.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(28),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => IssueCard(
                      issue: filtered[i],
                      onTap: () => context.go('/p/${widget.projectId}/issues/${filtered[i]['id']}'),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
