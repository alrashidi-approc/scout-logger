import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/dashboard_log_service.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/period_picker.dart';
import '../widgets/stat_card.dart';
import '../utils/date_range.dart';
import '../utils/issue_view.dart';
import '../utils/responsive.dart';
import '../widgets/panel.dart';
import '../widgets/trend_chart.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(7)});

  final String projectId;
  final PeriodFilter initialPeriod;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _api = ScoutApi();
  Map<String, dynamic>? _data;
  bool _loading = true;
  Object? _error;
  late PeriodFilter _period = widget.initialPeriod;

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
      final data = await _api.fetchStats(widget.projectId, period: _period);
      if (mounted) setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _setPeriod(PeriodFilter p) {
    _period = p;
    context.go(Uri(path: '/p/${widget.projectId}', queryParameters: p.toQuery()).toString());
    _load();
  }

  double _delta(String key) {
    final d = _data?['deltas'];
    if (d is! Map) return 0;
    return (d[key] as num?)?.toDouble() ?? 0;
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
      error: _error,
      onRetry: _load,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final d = _data!;
    final trend = jsonListMaps(d['dailyTrend']);
    final byType = jsonListMaps(d['byType']);
    final byPlatform = jsonListMaps(d['byPlatform']);
    final pid = widget.projectId;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
        children: [
          PageHeader(
            title: 'Statistics',
            subtitle: 'Product KPIs · ${_period.comparisonLabel()}',
            period: _period,
            onPeriodTap: _openPeriodPicker,
            actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
          ),
          const SizedBox(height: 16),
          FilterBar(period: _period, onPeriodChanged: _setPeriod),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth > 900;
            final crashFree = KpiHero(
              title: 'Crash-free sessions',
              value: '${(d['crashFreeRatePct'] as num?)?.toStringAsFixed(1) ?? '100'}%',
              subtitle: '${d['completedSessions']} sessions · ${d['crashes']} crashes',
              color: AppTheme.success,
              icon: Icons.verified_user_outlined,
            );
            final errorRate = KpiHero(
              title: 'Error rate',
              value: '${(d['errorRatePct'] as num?)?.toStringAsFixed(1) ?? '0'}%',
              subtitle: '${d['errors']} errors / ${d['events']} events',
              color: AppTheme.warning,
              icon: Icons.speed,
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: crashFree),
                  const SizedBox(width: 16),
                  Expanded(child: errorRate),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                crashFree,
                const SizedBox(height: 16),
                errorRate,
              ],
            );
          }),
          const SizedBox(height: 16),
          KpiWrap(
            children: [
              StatCard(
                label: 'Total events',
                value: '${d['events']}',
                icon: Icons.show_chart,
                delta: _delta('events'),
                onTap: () => context.go(Uri(path: '/p/$pid/events', queryParameters: _period.toQuery()).toString()),
              ),
              StatCard(
                label: 'Errors',
                value: '${d['errors']}',
                icon: Icons.error_outline,
                color: AppTheme.error,
                delta: _delta('errors'),
                deltaGoodWhenDown: true,
                onTap: () => context.go(Uri(path: '/p/$pid/events', queryParameters: _period.mergeQuery({'level': 'error', 'type': 'errors'})).toString()),
              ),
              StatCard(
                label: 'Crashes',
                value: '${d['crashes']}',
                icon: Icons.bolt,
                color: AppTheme.warning,
                delta: _delta('crashes'),
                deltaGoodWhenDown: true,
                onTap: () => context.go(Uri(path: '/p/$pid/events', queryParameters: _period.mergeQuery({'type': 'crash'})).toString()),
              ),
              StatCard(
                label: 'Logged-in users',
                value: '${d['uniqueUsers']}',
                icon: Icons.people_outline,
                color: AppTheme.success,
                delta: _delta('uniqueUsers'),
                onTap: () => context.go('/p/$pid/analytics?tab=sessions'),
              ),
              StatCard(
                label: 'Sessions',
                value: '${d['completedSessions']}',
                icon: Icons.play_circle_outline,
                color: const Color(0xFF6366F1),
                onTap: () => context.go('/p/$pid/analytics?tab=sessions'),
              ),
              StatCard(
                label: 'Avg session',
                value: _fmtDuration(d['avgSessionDurationMs']),
                icon: Icons.timer_outlined,
                color: const Color(0xFF0EA5E9),
              ),
              StatCard(
                label: 'Network events',
                value: '${d['networkEvents']}',
                icon: Icons.lan_outlined,
                color: AppTheme.info,
                onTap: () => context.go(Uri(path: '/p/$pid/events', queryParameters: _period.mergeQuery({'type': 'network'})).toString()),
              ),
              StatCard(
                label: 'Open issues',
                value: '${d['openIssues']}',
                icon: Icons.bug_report_outlined,
                color: const Color(0xFF7C3AED),
                onTap: () => context.go('/p/$pid/issues'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          DashboardPanel(
            title: 'Activity trend',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _legend(AppTheme.primary, 'Events'),
              const SizedBox(width: 12),
              _legend(AppTheme.error, 'Errors'),
              const SizedBox(width: 12),
              _legend(AppTheme.success, 'Users'),
            ]),
            child: TrendChart(points: trend, showUsers: true),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final side = c.maxWidth > 900;
            final typeCard = DashboardPanel(
              title: 'Events by type',
              child: byType.isEmpty
                  ? const Text('No data', style: TextStyle(color: AppTheme.muted))
                  : SizedBox(height: 220, child: _TypePie(byType)),
            );
            final platformCard = DashboardPanel(
              title: 'By platform',
              child: byPlatform.isEmpty
                  ? const Text('No platform data', style: TextStyle(color: AppTheme.muted))
                  : Column(
                      children: byPlatform.map((p) {
                        final count = p['count'] as int? ?? 0;
                        final total = byPlatform.fold<int>(0, (s, x) => s + (x['count'] as int? ?? 0));
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            SizedBox(width: 80, child: Text('${p['platform']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.text))),
                            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: total == 0 ? 0 : count / total, minHeight: 8, backgroundColor: AppTheme.border, color: AppTheme.primary))),
                            const SizedBox(width: 10),
                            Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.text)),
                          ]),
                        );
                      }).toList(),
                    ),
            );
            if (!side) return Column(children: [typeCard, const SizedBox(height: 16), platformCard]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: typeCard), const SizedBox(width: 16), Expanded(child: platformCard)]);
          }),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
        ],
      );

  String _fmtDuration(dynamic ms) {
    if (ms == null) return '—';
    final totalSec = ((ms is num ? ms.toInt() : int.tryParse('$ms')) ?? 0) ~/ 1000;
    if (totalSec <= 0) return '—';
    if (totalSec < 60) return '${totalSec}s';
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
}

class _TypePie extends StatelessWidget {
  const _TypePie(this.items);
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (s, i) => s + (i['count'] as int? ?? 0));
    if (total == 0) return const Center(child: Text('No data'));

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                for (var i = 0; i < items.length; i++)
                  PieChartSectionData(
                    value: (items[i]['count'] as int? ?? 0).toDouble(),
                    color: chartTypeColor('${items[i]['type']}'),
                    radius: 52,
                    title: '',
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: chartTypeColor('${items[i]['type']}'), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Text('${items[i]['type']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${items[i]['count']}', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
