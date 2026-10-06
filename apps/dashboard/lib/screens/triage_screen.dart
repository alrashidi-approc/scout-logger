import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/dashboard_log_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/issue_view.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/event_card.dart';
import '../widgets/page_header.dart';

/// Open, non-noise issues from the last week by priority, bucketed for triage.
class TriageScreen extends StatefulWidget {
  const TriageScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<TriageScreen> createState() => _TriageScreenState();
}

class _TriageScreenState extends State<TriageScreen> {
  static const _period = PeriodFilter.days(7);

  final _api = ScoutApi();
  List<Map<String, dynamic>> _issues = [];
  DateTime? _lastVisit;
  DateTime _since = DateTime.now();
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _readLastVisit();
    _load();
  }

  Future<void> _readLastVisit() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'triage_last_visit_${widget.projectId}';
    final previous = DateTime.tryParse(prefs.getString(key) ?? '');
    await prefs.setString(key, DateTime.now().toUtc().toIso8601String());
    if (mounted) setState(() => _lastVisit = previous);
  }

  Future<void> _load() async {
    setState(() => beginScreenLoad(
          hasData: _hasData,
          apply: ({required loading, required refreshing, error}) {
            _loading = loading;
            _refreshing = refreshing;
            _error = error;
          },
        ));
    try {
      final since = DateTime.now().subtract(const Duration(days: 7));
      final issues = await _api.fetchIssues(
        widget.projectId,
        status: 'open',
        period: _period,
        hideNoise: true,
        byPriority: true,
      );
      if (!mounted) return;
      setState(() {
        _issues = issues;
        _since = since;
        _hasData = true;
        _loading = false;
        _refreshing = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final lastVisit = _lastVisit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: pageInsets(context, top: pagePad(context)),
          child: PageHeader(
            title: 'Triage inbox',
            subtitle: [
              'Open issues · noise hidden · ${_period.label()}',
              if (lastVisit != null) 'last visit ${DateFormat.yMMMd().add_jm().format(lastVisit.toLocal())}',
            ].join(' · '),
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Expanded(
          child: AsyncScreenBody(
            loading: _loading,
            refreshing: _refreshing,
            error: _error,
            onRetry: _load,
            placeholderLayout: PlaceholderLayout.issues,
            builder: (context) {
              final s = triageSections(_issues, since: _since);
              return RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: pageInsets(context, top: 12, bottom: pagePad(context)),
                  children: [
                    ..._section(Icons.trending_up, 'Spikes', s.spikes, 'No spiking issues'),
                    ..._section(Icons.fiber_new_outlined, 'New', s.fresh, 'Nothing first seen this week'),
                    ..._section(Icons.replay, 'Regressions', s.regressions, 'No regressions this week'),
                    ..._section(Icons.hourglass_empty, 'Waiting', s.waiting, 'Inbox zero'),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _section(IconData icon, String title, List<Map<String, dynamic>> issues, String empty) => [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(children: [
            Icon(icon, size: 18, color: AppTheme.muted),
            const SizedBox(width: 8),
            Text('$title (${issues.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
        ),
        if (issues.isEmpty)
          Text(empty, style: const TextStyle(color: AppTheme.muted, fontSize: 13))
        else
          for (final i in issues)
            IssueCard(
              issue: i,
              sinceLastVisit: issueSinceVisit(i, _lastVisit),
              onTap: () => context.push('/p/${widget.projectId}/issues/${i['id']}'),
            ),
      ];
}
