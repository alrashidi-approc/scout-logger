import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/analytics_charts.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/period_picker.dart';
import '../widgets/panel.dart';
import '../widgets/stat_card.dart';
import '../widgets/trend_chart.dart';
import '../widgets/world_map.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(7)});

  final String projectId;
  final PeriodFilter initialPeriod;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _recentIssues = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  late PeriodFilter _period = widget.initialPeriod;

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
      Map<String, dynamic> data;
      try {
        data = await _api.fetchDashboard(widget.projectId, period: _period);
      } catch (_) {
        final overview = await _api.fetchOverview(widget.projectId, period: _period);
        final stats = await _api.fetchStats(widget.projectId, period: _period);
        data = {...overview, ...stats};
      }
      final issues = await _api.fetchIssues(widget.projectId, period: _period);
      if (mounted) setState(() {
        _d = data;
        _recentIssues = issues.take(5).toList();
        _hasData = true;
        _loading = false;

        _refreshing = false;
      });
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) setState(() {
        _error = e;
        _loading = false;

        _refreshing = false;
      });
    }
  }

  void _setPeriod(PeriodFilter p) {
    _period = p;
    context.go(Uri(path: '/p/${widget.projectId}', queryParameters: p.toQuery()).toString());
    _load();
  }

  double _delta(String key) {
    final deltas = _d?['deltas'];
    if (deltas is! Map) return 0;
    return jsonNum(deltas[key]) ?? 0;
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    final pid = widget.projectId;
    final title = _d != null ? jsonMap(_d!['project'])['name']?.toString() ?? pid : pid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: pageInsets(context, top: pagePad(context)),
          child: PageHeader(
            title: title,
            subtitle: 'Project dashboard · ${_period.comparisonLabel()}',
            period: _period,
            onPeriodTap: _openPeriodPicker,
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Padding(
          padding: pageInsets(context, top: 12),
          child: FilterBar(period: _period, onPeriodChanged: _setPeriod),
        ),
        Expanded(
          child: AsyncScreenBody(
            loading: _loading,
            refreshing: _refreshing,
            error: _error,
            onRetry: _load,
            placeholderLayout: PlaceholderLayout.dashboard,
            child: _buildBody(context, _d!, pid),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> d, String pid) {
    final trend = jsonListMaps(d['dailyTrend']);
    final hourlyTrend = d['trendGranularity'] == 'hour' || _period.usesHourlyTrend;
    final hourly = jsonListMaps(d['hourlyActivity']);
    final byPlatform = jsonListMaps(d['byPlatform']);
    final byType = jsonListMaps(d['byType']);
    final countries = jsonListMaps(d['topCountries']);
    final endpoints = jsonListMaps(d['topFailingEndpoints']);
    final screens = jsonListMaps(d['topCrashScreens']);
    final byEnv = jsonListMaps(d['byEnvironment']);
    final byRelease = jsonListMaps(d['eventsByRelease']);
    final byDeploy = jsonListMaps(d['byDeployment']);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: pageInsets(context, top: 12, bottom: pagePad(context)),
        children: [
          KpiWrap(
            children: [
              StatCard(label: 'Crash-free', value: '${jsonPct(d['crashFreeRatePct'], fallback: '100')}%', icon: Icons.verified_user_outlined, color: AppTheme.success, hint: '${d['completedSessions'] ?? 0} sessions'),
              StatCard(label: 'Error rate', value: '${jsonPct(d['errorRatePct'])}%', icon: Icons.speed, color: AppTheme.warning, hint: '${d['errors'] ?? 0} / ${d['events'] ?? 0} ev'),
              StatCard(label: 'Events', value: '${d['events'] ?? d['eventsToday']}', icon: Icons.show_chart, delta: _delta('events'), onTap: () => context.go(Uri(path: '/p/$pid/events', queryParameters: _period.toQuery()).toString())),
              StatCard(label: 'Errors', value: '${d['errors'] ?? d['errorsToday']}', icon: Icons.error_outline, color: AppTheme.error, delta: _delta('errors'), deltaGoodWhenDown: true, onTap: () => context.go(Uri(path: '/p/$pid/events', queryParameters: _period.mergeQuery({'level': 'error', 'type': 'errors'})).toString())),
              StatCard(label: 'Users w/ errors', value: '${d['usersAffectedByErrors'] ?? 0}', icon: Icons.person_off_outlined, color: AppTheme.accentPink, hint: 'Logged-in only', onTap: () => context.go(Uri(path: '/p/$pid/users', queryParameters: _period.toQuery()).toString())),
              StatCard(label: 'Peak hour', value: formatHour(jsonInt(d['peakHour'])), icon: Icons.schedule, color: AppTheme.info, hint: '${d['peakHourEvents'] ?? 0} ev'),
              StatCard(label: 'Peak error hour', value: formatHour(jsonInt(d['peakErrorHour'])), icon: Icons.warning_amber_outlined, color: AppTheme.warning, hint: '${d['peakErrorHourCount'] ?? 0} err'),
              StatCard(label: 'Logged-in users', value: '${d['uniqueUsers'] ?? d['uniqueUsersToday']}', icon: Icons.people_outline, color: AppTheme.success, delta: _delta('uniqueUsers'), hint: 'Excludes guest UUIDs', onTap: () => context.go(Uri(path: '/p/$pid/users', queryParameters: _period.toQuery()).toString())),
              StatCard(label: 'Sessions', value: '${d['completedSessions'] ?? 0}', icon: Icons.play_circle_outline, color: AppTheme.accentPurple, onTap: () => context.go(Uri(path: '/p/$pid/sessions', queryParameters: _period.toQuery()).toString())),
              StatCard(label: 'Crashes', value: '${d['crashes'] ?? d['crashesToday']}', icon: Icons.bolt, color: AppTheme.error, delta: _delta('crashes'), deltaGoodWhenDown: true, onTap: () => context.go(Uri(path: '/p/$pid/events', queryParameters: _period.mergeQuery({'type': 'crash'})).toString())),
              StatCard(label: 'Open issues', value: '${d['openIssues']}', icon: Icons.bug_report_outlined, color: AppTheme.accentPurple, onTap: () => context.go('/p/$pid/issues')),
              StatCard(label: 'Live sessions', value: '${d['activeSessions'] ?? 0}', icon: Icons.sensors, color: AppTheme.primary, onTap: () => context.go(Uri(path: '/p/$pid/sessions', queryParameters: _period.toQuery()).toString())),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            return responsiveRow(
              maxWidth: c.maxWidth,
              flex: const [3, 2],
              children: [
                DashboardPanel(
                  title: 'Events over time',
                  subtitle: hourlyTrend ? 'Hourly (UTC)' : null,
                  trailing: chartLegend([
                    _legend(AppTheme.primary, 'Events'),
                    _legend(AppTheme.error, 'Errors'),
                    _legend(AppTheme.success, 'Logged-in users'),
                  ]),
                  child: TrendChart(points: trend, showUsers: true, hourly: hourlyTrend, height: c.maxWidth < Breakpoints.mobile ? 200 : 240),
                ),
                DashboardPanel(title: 'Peak error times', subtitle: 'Errors by hour (UTC)', child: HourlyChart(points: hourly, errorsOnly: true, height: c.maxWidth < Breakpoints.mobile ? 160 : 180)),
              ],
            );
          }),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) => DashboardPanel(title: 'Activity by hour', subtitle: 'All events (UTC)', child: HourlyChart(points: hourly, height: c.maxWidth < Breakpoints.mobile ? 160 : 180))),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            return responsiveRow(
              maxWidth: c.maxWidth,
              children: [
                Column(children: [
                  DashboardPanel(
                    title: 'Top failing endpoints',
                    child: RankList(items: endpoints, labelOf: (i) => '${i['endpoint']}', countOf: (i) => i['count'] as int? ?? 0, onTap: (i) => context.go(Uri(path: '/p/$pid/events', queryParameters: _period.mergeQuery({'q': '${i['endpoint']}'})).toString())),
                  ),
                  const SizedBox(height: 12),
                  DashboardPanel(
                    title: 'Top crashing screens',
                    child: RankList(items: screens, labelOf: (i) => '${i['screen']}', countOf: (i) => i['count'] as int? ?? 0),
                  ),
                ]),
                Column(children: [
                  DashboardPanel(
                    title: 'Events by platform',
                    child: byPlatform.isEmpty ? const Text('No platform data', style: TextStyle(color: AppTheme.muted)) : _PlatformPie(byPlatform, compact: c.maxWidth < Breakpoints.mobile),
                  ),
                  const SizedBox(height: 12),
                  DashboardPanel(
                    title: 'Events by type',
                    child: RankList(items: byType, labelOf: (i) => '${i['type']}', countOf: (i) => i['count'] as int? ?? 0),
                  ),
                ]),
              ],
            );
          }),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            return responsiveRow(
              maxWidth: c.maxWidth,
              children: [
                DashboardPanel(
                  title: 'Events by release',
                  child: byRelease.isEmpty
                      ? const Text('No release data', style: TextStyle(color: AppTheme.muted))
                      : Column(
                          children: byRelease.map((r) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: c.maxWidth < Breakpoints.mobile
                                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text('${r['release']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.text)),
                                        const SizedBox(height: 4),
                                        Wrap(spacing: 8, children: [
                                          Text('${r['count']} ev', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                                          Text('${r['errors']} err', style: const TextStyle(fontSize: 11, color: AppTheme.error)),
                                          Text('${r['crashes']} crash', style: const TextStyle(fontSize: 11, color: AppTheme.error)),
                                        ]),
                                      ])
                                    : Row(children: [
                                        Expanded(child: Text('${r['release']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.text))),
                                        Text('${r['count']} ev', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                                        const SizedBox(width: 8),
                                        Text('${r['errors']} err', style: const TextStyle(fontSize: 11, color: AppTheme.error)),
                                        const SizedBox(width: 8),
                                        Text('${r['crashes']} crash', style: const TextStyle(fontSize: 11, color: AppTheme.error)),
                                      ]),
                              )).toList(),
                        ),
                ),
                Column(children: [
                  DashboardPanel(
                    title: 'By environment',
                    child: RankList(items: byEnv, labelOf: (i) => '${i['environment']}', countOf: (i) => i['count'] as int? ?? 0),
                  ),
                  const SizedBox(height: 12),
                  DashboardPanel(
                    title: 'By deployment tag',
                    child: byDeploy.isEmpty
                        ? const Text('Set custom.deployment in your app context', style: TextStyle(color: AppTheme.muted, fontSize: 12))
                        : RankList(items: byDeploy, labelOf: (i) => '${i['tag']}', countOf: (i) => i['count'] as int? ?? 0),
                  ),
                ]),
              ],
            );
          }),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            return responsiveRow(
              maxWidth: c.maxWidth,
              flex: const [3, 2],
              children: [
                DashboardPanel(
                  title: 'Recent issues',
                  trailing: TextButton(onPressed: () => context.go('/p/$pid/issues'), child: const Text('View all')),
                  child: _recentIssues.isEmpty
                      ? const Text('No issues yet', style: TextStyle(color: AppTheme.muted))
                      : Column(children: _recentIssues.map((i) => IssueCard(issue: i, onTap: () => context.push('/p/$pid/issues/${i['id']}'))).toList()),
                ),
                DashboardPanel(
                  title: 'Users by country',
                  trailing: TextButton(onPressed: () => context.go(Uri(path: '/p/$pid/geo', queryParameters: _period.toQuery()).toString()), child: const Text('Full map')),
                  child: WorldMapCompact(points: countries),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
        ],
      );
}

class _PlatformPie extends StatelessWidget {
  const _PlatformPie(this.items, {this.compact = false});
  final List<Map<String, dynamic>> items;
  final bool compact;

  static const _colors = [AppTheme.primary, AppTheme.info, AppTheme.warning, AppTheme.success, AppTheme.accentPink, AppTheme.muted];

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (s, i) => s + (i['count'] as int? ?? 0));
    if (total == 0) return const Center(child: Text('No data'));

    final pie = SizedBox(
      height: compact ? 140 : 180,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: compact ? 28 : 32,
          sections: [
            for (var i = 0; i < items.length; i++)
              PieChartSectionData(value: (items[i]['count'] as int? ?? 0).toDouble(), color: _colors[i % _colors.length], radius: compact ? 36 : 44, title: ''),
          ],
        ),
      ),
    );

    final legend = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: _colors[i % _colors.length], borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Expanded(child: Text('${items[i]['platform']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
              Text('${items[i]['count']}', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
            ]),
          ),
      ],
    );

    if (compact) return Column(children: [pie, const SizedBox(height: 8), legend]);
    return Row(children: [Expanded(child: pie), Expanded(child: legend)]);
  }
}
