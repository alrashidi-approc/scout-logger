import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/page_header.dart';

class DashboardLogsScreen extends StatefulWidget {
  const DashboardLogsScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<DashboardLogsScreen> createState() => _DashboardLogsScreenState();
}

class _DashboardLogsScreenState extends State<DashboardLogsScreen> {
  final _api = ScoutApi();
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  String? _level;

  @override
  void initState() {
    super.initState();
    _load();
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
      final logs = await _api.fetchDashboardLogs(widget.projectId, level: _level);
      if (mounted) {
        setState(() {
          _logs = logs;
          _hasData = true;
          _loading = false;

          _refreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;

          _refreshing = false;
        });
      }
    }
  }

  Color _levelColor(String level) => switch (level) {
        'warning' => AppTheme.warning,
        'info' => AppTheme.info,
        _ => AppTheme.error,
      };

  @override
  Widget build(BuildContext context) {
    final pad = pagePad(context);
    final insets = pageInsets(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: insets.copyWith(top: pad),
          child: PageHeader(
            title: 'UI errors',
            subtitle: 'Dashboard API and UI failures — not mobile app events (see Events)',
            actions: [
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Padding(
          padding: insets.copyWith(top: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final lvl in [null, 'error', 'warning', 'info'])
                FilterChip(
                  label: Text(lvl?.toUpperCase() ?? 'ALL'),
                  selected: _level == lvl,
                  onSelected: (_) {
                    setState(() => _level = lvl);
                    _load();
                  },
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncScreenBody(
            loading: _loading,
            refreshing: _refreshing,
            error: _error,
            onRetry: _load,
            placeholderLayout: PlaceholderLayout.list,
            empty: !_loading && _logs.isEmpty
                ? const EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'No dashboard errors',
                    subtitle: 'When API calls or screens fail, entries appear here automatically.',
                  )
                : null,
            builder: (context) => RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: insets.copyWith(top: 12, bottom: pad),
                itemCount: _logs.length,
                itemBuilder: (_, i) {
                  final log = _logs[i];
                  final level = log['level'] as String? ?? 'error';
                  final created = DateTime.tryParse(log['createdAt'] as String? ?? '');
                  final ctx = log['context'] is Map ? Map<String, dynamic>.from(log['context'] as Map) : <String, dynamic>{};
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      leading: Icon(Icons.bug_report_outlined, color: _levelColor(level), size: 20),
                      title: Text(log['message'] as String? ?? '', style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        [
                          if (created != null) DateFormat('MMM d · HH:mm:ss').format(created.toLocal()),
                          if (log['route'] != null) log['route'],
                          if (log['userEmail'] != null) log['userEmail'],
                        ].whereType<String>().join(' · '),
                        style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                      ),
                      children: [
                        if (ctx.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SelectableText(
                              ctx.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
