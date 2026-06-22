import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/period_picker.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, required this.projectId, this.initialTab, this.initialPeriod = const PeriodFilter.days(30)});

  final String projectId;
  final String? initialTab;
  final PeriodFilter initialPeriod;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with SingleTickerProviderStateMixin {
  final _api = ScoutApi();
  late final TabController _tabs = TabController(length: 4, vsync: this);

  List<String> _routes = [];
  List<String> _funnelSteps = [];
  Map<String, dynamic>? _funnel;
  Map<String, dynamic>? _retention;
  List<Map<String, dynamic>> _releases = [];
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  late PeriodFilter _period = widget.initialPeriod;

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab;
    if (tab == 'sessions') _tabs.index = 3;
    else if (tab == 'releases') _tabs.index = 2;
    else if (tab == 'retention') _tabs.index = 1;
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
      final routes = await _api.fetchRoutes(widget.projectId, period: _period);
      final retention = await _api.fetchRetention(widget.projectId);
      final releases = await _api.fetchReleaseComparison(widget.projectId, period: _period);
      final sessions = await _api.fetchSessions(widget.projectId, period: _period);
      if (mounted) {
        setState(() {
          _routes = routes;
          if (_funnelSteps.isEmpty && routes.length >= 2) _funnelSteps = routes.take(3).toList();
          _retention = retention;
          _releases = releases;
          _sessions = sessions;
          _hasData = true;
          _loading = false;

          _refreshing = false;
        });
        if (_funnelSteps.isNotEmpty) await _runFunnel();
      }
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) setState(() {
        _error = e;
        _loading = false;

        _refreshing = false;
      });
    }
  }

  Future<void> _runFunnel() async {
    if (_funnelSteps.isEmpty) return;
    try {
      final funnel = await _api.fetchFunnel(widget.projectId, _funnelSteps, period: _period);
      if (mounted) setState(() => _funnel = funnel);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _setPeriod(PeriodFilter p) {
    _period = p;
    final tab = GoRouterState.of(context).uri.queryParameters['tab'];
    final q = {...p.toQuery(), if (tab != null && tab.isNotEmpty) 'tab': tab};
    context.go(Uri(path: '/p/${widget.projectId}/analytics', queryParameters: q).toString());
    _load();
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
            refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.analytics,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final insets = pageInsets(context);
    final pad = pagePad(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: insets.copyWith(top: pad),
          child: PageHeader(
            title: 'Analytics',
            subtitle: 'Funnels, retention, releases, and session replays',
            period: _period,
            onPeriodTap: _openPeriodPicker,
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Padding(
          padding: insets.copyWith(top: 8),
          child: FilterBar(period: _period, onPeriodChanged: _setPeriod),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Funnels'),
            Tab(text: 'Retention'),
            Tab(text: 'Releases'),
            Tab(text: 'Sessions'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _FunnelTab(
                routes: _routes,
                steps: _funnelSteps,
                funnel: _funnel,
                onStepsChanged: (s) => setState(() => _funnelSteps = s),
                onRun: _runFunnel,
              ),
              _RetentionTab(data: _retention),
              _ReleasesTab(releases: _releases, period: _period),
              _SessionsTab(projectId: widget.projectId, sessions: _sessions),
            ],
          ),
        ),
      ],
    );
  }
}

class _FunnelTab extends StatelessWidget {
  const _FunnelTab({
    required this.routes,
    required this.steps,
    required this.funnel,
    required this.onStepsChanged,
    required this.onRun,
  });

  final List<String> routes;
  final List<String> steps;
  final Map<String, dynamic>? funnel;
  final ValueChanged<List<String>> onStepsChanged;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final stepData = jsonListMaps(funnel?['steps']);
    final total = funnel?['totalSessions'] as int? ?? 0;

    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Screen funnel', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('Pick routes in order. Counts sessions that visited each step sequentially.', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
              const SizedBox(height: 16),
              if (routes.isEmpty)
                const Text('No screen trails yet — integrate navigation tracking in your app.', style: TextStyle(color: AppTheme.muted))
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in routes)
                      FilterChip(
                        label: Text(r, style: const TextStyle(fontSize: 12)),
                        selected: steps.contains(r),
                        onSelected: (sel) {
                          final next = [...steps];
                          if (sel) {
                            if (!next.contains(r)) next.add(r);
                          } else {
                            next.remove(r);
                          }
                          onStepsChanged(next);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (steps.isNotEmpty)
                  Text('Steps: ${steps.join(' → ')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: steps.isEmpty ? null : onRun, icon: const Icon(Icons.play_arrow), label: const Text('Run funnel')),
              ],
            ]),
          ),
        ),
        if (stepData.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$total sessions analyzed', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                const SizedBox(height: 16),
                ...stepData.asMap().entries.map((e) {
                  final s = e.value;
                  final route = s['route'] as String? ?? '';
                  final count = s['sessions'] as int? ?? 0;
                  final pct = (s['conversionPct'] as num?)?.toDouble() ?? 0;
                  final drop = (s['dropOffPct'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('${e.key + 1}. $route', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('$count sessions · ${pct.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: total == 0 ? 0 : count / total, minHeight: 10, backgroundColor: AppTheme.border, color: AppTheme.primary),
                      ),
                      if (e.key > 0 && drop > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${drop.toStringAsFixed(1)}% drop-off from previous step', style: const TextStyle(fontSize: 11, color: AppTheme.warning)),
                        ),
                    ]),
                  );
                }),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}

class _RetentionTab extends StatelessWidget {
  const _RetentionTab({required this.data});

  final Map<String, dynamic>? data;

  @override
  Widget build(BuildContext context) {
    final cohorts = jsonListMaps(data?['cohorts']);
    final cells = jsonListMaps(data?['cells']);
    if (cohorts.isEmpty) {
      return const EmptyState(icon: Icons.people_outline, title: 'No retention data yet', subtitle: 'Users appear after your app sends events with user IDs.');
    }

    final maxPeriod = cells.fold<int>(0, (m, c) {
      final p = c['period'] as int? ?? 0;
      return p > m ? p : m;
    });

    Color cellColor(double pct) {
      if (pct >= 40) return AppTheme.success.withValues(alpha: 0.15 + pct / 200);
      if (pct >= 15) return AppTheme.primary.withValues(alpha: 0.1 + pct / 300);
      return AppTheme.border.withValues(alpha: 0.5);
    }

    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Weekly retention', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('Rows = signup week. Columns = weeks since first seen.', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(72),
                  border: TableBorder.all(color: AppTheme.border),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: AppTheme.primarySoft),
                      children: [
                        const Padding(padding: EdgeInsets.all(8), child: Text('Cohort', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                        for (var p = 0; p <= maxPeriod; p++)
                          Padding(padding: const EdgeInsets.all(8), child: Text('W+$p', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                      ],
                    ),
                    for (final cohort in cohorts)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(_fmtWeek(cohort['cohortWeek'] as String?), style: const TextStyle(fontSize: 11)),
                          ),
                          for (var p = 0; p <= maxPeriod; p++)
                            Builder(builder: (_) {
                              final cell = cells.cast<Map<String, dynamic>?>().firstWhere(
                                    (c) => c?['cohortWeek'] == cohort['cohortWeek'] && c?['period'] == p,
                                    orElse: () => null,
                                  );
                              final pct = (cell?['retentionPct'] as num?)?.toDouble() ?? 0;
                              return Container(
                                color: cell == null ? null : cellColor(pct),
                                padding: const EdgeInsets.all(8),
                                child: Text(cell == null ? '—' : '${pct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                              );
                            }),
                        ],
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  String _fmtWeek(String? iso) {
    if (iso == null) return '—';
    try {
      return DateFormat.MMMd().format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }
}

class _ReleasesTab extends StatelessWidget {
  const _ReleasesTab({required this.releases, required this.period});

  final List<Map<String, dynamic>> releases;
  final PeriodFilter period;

  @override
  Widget build(BuildContext context) {
    if (releases.isEmpty) {
      return const EmptyState(icon: Icons.new_releases_outlined, title: 'No release data yet', subtitle: 'Release info is auto-collected from your app.');
    }

    final baseline = releases.first;
    final baseCrash = (baseline['crashRatePct'] as num?)?.toDouble() ?? 0;

    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Release comparison (${period.label()})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 16),
              ...releases.map((r) {
                final crash = (r['crashRatePct'] as num?)?.toDouble() ?? 0;
                final delta = crash - baseCrash;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r['release']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(
                          '${r['users']} users · ${r['sessions']} sessions · avg ${_fmtDur(r['avgSessionMs'])}',
                          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                        ),
                        Text('${r['events']} events · ${r['crashes']} crashes · ${r['errors']} errors', style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${crash.toStringAsFixed(2)}% crash', style: TextStyle(fontWeight: FontWeight.w800, color: crash > 1 ? AppTheme.error : AppTheme.success)),
                      if (r != baseline)
                        Text(
                          delta >= 0 ? '+${delta.toStringAsFixed(2)}% vs top' : '${delta.toStringAsFixed(2)}% vs top',
                          style: TextStyle(fontSize: 11, color: delta > 0 ? AppTheme.error : AppTheme.success),
                        ),
                    ]),
                  ]),
                );
              }),
            ]),
          ),
        ),
      ],
    );
  }

  String _fmtDur(dynamic ms) {
    final v = ms is num ? ms.toInt() : int.tryParse('$ms') ?? 0;
    if (v <= 0) return '—';
    final sec = v ~/ 1000;
    if (sec < 60) return '${sec}s';
    return '${sec ~/ 60}m ${sec % 60}s';
  }
}

class _SessionsTab extends StatelessWidget {
  const _SessionsTab({required this.projectId, required this.sessions});

  final String projectId;
  final List<Map<String, dynamic>> sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const EmptyState(icon: Icons.play_circle_outline, title: 'No sessions yet', subtitle: 'Sessions are recorded when users open and close your app.');
    }

    return ListView.separated(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = sessions[i];
        final summary = s['summary'] is Map ? Map<String, dynamic>.from(s['summary'] as Map) : null;
        final started = DateTime.tryParse(s['startedAt'] as String? ?? '');
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/p/$projectId/sessions/${s['id']}'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(started != null ? DateFormat('MMM d · HH:mm').format(started.toLocal()) : '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${s['release'] ?? '—'} · ${_fmtDur(s['durationMs'])}${summary != null ? ' · ${summary['screensVisited'] ?? '?'} screens' : ''}',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                    if (summary != null)
                      Text(
                        '${summary['networkCalls'] ?? 0} network · ${summary['actions'] ?? 0} actions · ${summary['errors'] ?? 0} errors',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ]),
                ),
                Icon(s['endedAt'] == null ? Icons.sensors : Icons.check_circle_outline, color: s['endedAt'] == null ? AppTheme.info : AppTheme.success, size: 20),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppTheme.muted),
              ]),
            ),
          ),
        );
      },
    );
  }

  String _fmtDur(dynamic ms) {
    if (ms == null) return 'open';
    final v = ms is num ? ms.toInt() : int.tryParse('$ms') ?? 0;
    if (v <= 0) return '—';
    final sec = v ~/ 1000;
    if (sec < 60) return '${sec}s';
    return '${sec ~/ 60}m ${sec % 60}s';
  }
}
