import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/analytics_charts.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/panel.dart';
import '../widgets/stat_card.dart';
import '../widgets/trend_chart.dart';
import '../widgets/world_map.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, required this.projectId, this.initialDays = 7});

  final String projectId;
  final int initialDays;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _recentIssues = [];
  bool _loading = true;
  String? _error;
  late int _days = widget.initialDays;

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
      Map<String, dynamic> data;
      try {
        data = await _api.fetchDashboard(widget.projectId, days: _days);
      } catch (_) {
        final overview = await _api.fetchOverview(widget.projectId, days: _days);
        final stats = await _api.fetchStats(widget.projectId, days: _days);
        data = {...overview, ...stats};
      }
      final issues = await _api.fetchIssues(widget.projectId, days: _days);
      if (mounted) setState(() {
        _d = data;
        _recentIssues = issues.take(5).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _setDays(int d) {
    _days = d;
    context.go('/p/${widget.projectId}?days=$d');
    _load();
  }

  double _delta(String key) {
    final deltas = _d?['deltas'];
    if (deltas is! Map) return 0;
    return jsonNum(deltas[key]) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final pid = widget.projectId;
    final period = periodLabel(_days);
    final title = _d != null ? jsonMap(_d!['project'])['name']?.toString() ?? pid : pid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: pageInsets(context, top: pagePad(context)),
          child: PageHeader(
            title: title,
            subtitle: 'Project dashboard · $period',
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
        ),
        Padding(
          padding: pageInsets(context, top: 12),
          child: FilterBar(days: _days, onDaysChanged: _setDays),
        ),
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
                  ? ErrorPanel(message: _error!, onRetry: _load)
                  : _buildBody(context, _d!, pid),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> d, String pid) {
    final trend = jsonListMaps(d['dailyTrend']);
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
              StatCard(label: 'Events', value: '${d['events'] ?? d['eventsToday']}', icon: Icons.show_chart, delta: _delta('events'), onTap: () => context.go('/p/$pid/events?days=$_days')),
              StatCard(label: 'Errors', value: '${d['errors'] ?? d['errorsToday']}', icon: Icons.error_outline, color: AppTheme.error, delta: _delta('errors'), deltaGoodWhenDown: true, onTap: () => context.go('/p/$pid/events?type=errors&days=$_days')),
              StatCard(label: 'Users w/ errors', value: '${d['usersAffectedByErrors'] ?? 0}', icon: Icons.person_off_outlined, color: AppTheme.accentPink, onTap: () => context.go('/p/$pid/users?days=$_days')),
              StatCard(label: 'Peak hour', value: formatHour(jsonInt(d['peakHour'])), icon: Icons.schedule, color: AppTheme.info, hint: '${d['peakHourEvents'] ?? 0} ev'),
              StatCard(label: 'Peak error hour', value: formatHour(jsonInt(d['peakErrorHour'])), icon: Icons.warning_amber_outlined, color: AppTheme.warning, hint: '${d['peakErrorHourCount'] ?? 0} err'),
              StatCard(label: 'Unique users', value: '${d['uniqueUsers'] ?? d['uniqueUsersToday']}', icon: Icons.people_outline, color: AppTheme.success, delta: _delta('uniqueUsers'), onTap: () => context.go('/p/$pid/users?days=$_days')),
              StatCard(label: 'Sessions', value: '${d['completedSessions'] ?? 0}', icon: Icons.play_circle_outline, color: AppTheme.accentPurple, onTap: () => context.go('/p/$pid/sessions?days=$_days')),
              StatCard(label: 'Crashes', value: '${d['crashes'] ?? d['crashesToday']}', icon: Icons.bolt, color: AppTheme.error, delta: _delta('crashes'), deltaGoodWhenDown: true, onTap: () => context.go('/p/$pid/events?type=crash&days=$_days')),
              StatCard(label: 'Open issues', value: '${d['openIssues']}', icon: Icons.bug_report_outlined, color: AppTheme.accentPurple, onTap: () => context.go('/p/$pid/issues')),
              StatCard(label: 'Live sessions', value: '${d['activeSessions'] ?? 0}', icon: Icons.sensors, color: AppTheme.primary, onTap: () => context.go('/p/$pid/sessions?days=$_days')),
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
                  trailing: chartLegend([
                    _legend(AppTheme.primary, 'Events'),
                    _legend(AppTheme.accentPurple, 'Errors'),
                    _legend(AppTheme.success, 'Users'),
                  ]),
                  child: TrendChart(points: trend, showUsers: true, height: c.maxWidth < Breakpoints.mobile ? 200 : 240),
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
                    child: RankList(items: endpoints, labelOf: (i) => '${i['endpoint']}', countOf: (i) => i['count'] as int? ?? 0, onTap: (i) => context.go('/p/$pid/events?days=$_days&q=${Uri.encodeComponent('${i['endpoint']}')}')),
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
                                          Text('${r['errors']} err', style: const TextStyle(fontSize: 11, color: AppTheme.warning)),
                                          Text('${r['crashes']} crash', style: const TextStyle(fontSize: 11, color: AppTheme.error)),
                                        ]),
                                      ])
                                    : Row(children: [
                                        Expanded(child: Text('${r['release']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.text))),
                                        Text('${r['count']} ev', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                                        const SizedBox(width: 8),
                                        Text('${r['errors']} err', style: const TextStyle(fontSize: 11, color: AppTheme.warning)),
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
                  trailing: TextButton(onPressed: () => context.go('/p/$pid/geo?days=$_days'), child: const Text('Full map')),
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

  static const _colors = [AppTheme.primary, AppTheme.accentPurple, AppTheme.warning, AppTheme.success, AppTheme.info, AppTheme.accentPink];

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
