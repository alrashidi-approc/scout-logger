import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../services/dashboard_log_service.dart';
import '../theme/app_theme.dart';
import '../utils/api_hits_report.dart';
import '../utils/clipboard.dart';
import '../utils/date_range.dart';
import '../utils/download_file.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../utils/time_zone.dart';
import '../widgets/analytics_charts.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/panel.dart';
import '../widgets/period_picker.dart';
import '../widgets/stat_card.dart';
import '../widgets/trend_chart.dart';

/// How many times the app hit each API (query stripped, ids collapsed) over a calendar range,
/// days running midnight to midnight in the browser's time zone.
class ApiHitsScreen extends StatefulWidget {
  const ApiHitsScreen({super.key, required this.projectId, this.initialPeriod, this.initialEndpoint});

  final String projectId;

  /// Calendar range; anything else (or null) falls back to today.
  final PeriodFilter? initialPeriod;
  final String? initialEndpoint;

  @override
  State<ApiHitsScreen> createState() => _ApiHitsScreenState();
}

class _ApiHitsScreenState extends State<ApiHitsScreen> {
  final _api = ScoutApi();
  final _timeZone = localTimeZone();
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  Object? _error;
  late PeriodFilter _period;
  late String _endpoint;

  @override
  void initState() {
    super.initState();
    final p = widget.initialPeriod;
    _period = p != null && p.isCustom ? p : PeriodFilter.today();
    _endpoint = widget.initialEndpoint?.trim() ?? '';
    _load();
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
      final data = await _api.fetchApiHits(widget.projectId, period: _period, timeZone: _timeZone, endpoint: _endpoint);
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Future<void> _exportMarkdown() async {
    String name = widget.projectId;
    try {
      final projects = await _api.fetchProjects();
      name = projects.firstWhere((p) => p['id'] == widget.projectId, orElse: () => const {})['name'] as String? ?? name;
    } catch (_) {}
    final md = buildApiHitsMarkdown(projectName: name, data: _data);
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final q = _period.toQuery();
    final file = 'api-calls-$slug-${q['from']}${q['to'] == q['from'] ? '' : '_${q['to']}'}.md';
    final saved = await downloadTextFile(file, md, mimeType: 'text/markdown');
    if (!mounted) return;
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $file')));
    } else {
      await copyWithFeedback(context, md, message: 'Markdown report copied');
    }
  }

  void _apply({PeriodFilter? period, String? endpoint}) {
    setState(() {
      if (period != null) _period = period;
      if (endpoint != null) _endpoint = endpoint.trim();
    });
    context.go(Uri(
      path: '/p/${widget.projectId}/api-hits',
      queryParameters: _period.mergeQuery({if (_endpoint.isNotEmpty) 'endpoint': _endpoint}),
    ).toString());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final hourly = _data['bucket'] == 'hour';
    final series = jsonListMaps(_data['series']);
    final endpoints = jsonListMaps(_data['endpoints']);
    final totals = _data['totals'] is Map ? Map<String, dynamic>.from(_data['totals'] as Map) : const {};
    final hits = totals['hits'] as int? ?? 0;
    final errors = totals['errors'] as int? ?? 0;
    final peak = series.fold<Map<String, dynamic>?>(
      null,
      (best, p) => (p['events'] as int? ?? 0) > (best?['events'] as int? ?? 0) ? p : best,
    );
    final peakAt = DateTime.tryParse('${peak?['date']}');
    final selected = _data['endpoint'] as String?;
    final zone = (_data['range'] as Map?)?['tz'] as String? ?? _timeZone;
    final warnings = apiHitsCoverageWarnings(_data);
    final fmt = NumberFormat.decimalPattern();

    return AsyncScreenBody(
      loading: _loading,
      refreshing: _refreshing && !_hasData,
      error: _error,
      onRetry: _load,
      placeholderLayout: PlaceholderLayout.dashboard,
      builder: (context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
          children: [
            PageHeader(
              title: 'API hits',
              subtitle: 'Calls per endpoint · query parameters ignored · ids grouped as :id',
              actions: [
                FilledButton.icon(
                  onPressed: _hasData ? _exportMarkdown : null,
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Export Markdown'),
                ),
                TextButton.icon(
                  onPressed: () => context.go('/p/${widget.projectId}/settings'),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Settings'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PeriodChip(
                  period: _period,
                  onTap: () => showPeriodPicker(
                    context,
                    current: _period,
                    localTime: true,
                    onSelected: (p) => _apply(period: p.isCustom ? p : PeriodFilter.today()),
                  ),
                ),
                Text('12 AM – 12 AM · $zone', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
              ],
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Counts may be incomplete', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final w in warnings)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $w', style: const TextStyle(fontSize: 13))),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            SearchField(
              key: ValueKey(_endpoint),
              hint: 'Paste an API URL or path, e.g. https://host/api/ssn-details?serial=…',
              initialValue: _endpoint,
              onSubmitted: (q) => _apply(endpoint: q),
            ),
            if (selected != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InputChip(
                  label: Text('Showing $selected'),
                  onDeleted: () => _apply(endpoint: ''),
                ),
              ),
            ],
            const SizedBox(height: 16),
            KpiWrap(
              children: [
                StatCard(label: 'Total hits', value: fmt.format(hits), icon: Icons.query_stats),
                StatCard(
                  label: hourly ? 'Avg per hour' : 'Avg per day',
                  value: fmt.format(series.isEmpty ? 0 : (hits / series.length).round()),
                  icon: Icons.av_timer,
                ),
                StatCard(
                  label: hourly ? 'Peak hour' : 'Peak day',
                  value: fmt.format(peak?['events'] ?? 0),
                  hint: peakAt == null ? null : DateFormat(hourly ? 'MMM d, HH:mm' : 'MMM d').format(peakAt),
                  icon: Icons.trending_up,
                  color: AppTheme.warning,
                ),
                StatCard(
                  label: 'Error rate',
                  value: hits == 0 ? '0%' : '${(errors / hits * 100).toStringAsFixed(1)}%',
                  hint: '${fmt.format(errors)} failed',
                  icon: Icons.error_outline,
                  color: AppTheme.error,
                ),
              ],
            ),
            const SizedBox(height: 20),
            DashboardPanel(
              title: 'Hits over time',
              subtitle: '${hourly ? 'Hourly' : 'Daily'} · $zone',
              child: EventOutcomeChart(points: series, hourly: hourly, utc: false),
            ),
            if (selected == null && endpoints.isNotEmpty) ...[
              const SizedBox(height: 16),
              DashboardPanel(
                title: 'Top endpoints',
                subtitle: 'Success vs errors; numbers match the ranking below',
                child: _TopEndpointsChart(endpoints: endpoints.take(10).toList()),
              ),
            ],
            const SizedBox(height: 16),
            DashboardPanel(
              title: 'Endpoints',
              subtitle: '${endpoints.length} endpoints · tap one to see only its hits',
              child: hits == 0
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text('No API calls in this range.', style: TextStyle(color: AppTheme.muted)),
                      ),
                    )
                  : RankList(
                      items: endpoints,
                      labelOf: (e) => '${e['key']}',
                      countOf: (e) => e['hits'] as int? ?? 0,
                      onTap: (e) => _apply(endpoint: '${e['key']}'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopEndpointsChart extends StatelessWidget {
  const _TopEndpointsChart({required this.endpoints});

  final List<Map<String, dynamic>> endpoints;

  @override
  Widget build(BuildContext context) {
    final maxY = endpoints.map((e) => e['hits'] as int? ?? 0).fold(0, max);
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 5 : maxY * 1.15,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border.withValues(alpha: 0.5)),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) =>
                    Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) => Text('${v.toInt() + 1}', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < endpoints.length; i++) _bar(i, endpoints[i]),
          ],
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppTheme.panelElevated,
              getTooltipItem: (group, _, __, ___) {
                final e = endpoints[group.x];
                return BarTooltipItem(
                  '${e['key']}\n${e['hits']} hits · ${e['success']} ok · ${e['errors']} errors',
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.text),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  BarChartGroupData _bar(int x, Map<String, dynamic> e) {
    final hits = (e['hits'] as int? ?? 0).toDouble();
    final ok = (e['success'] as int? ?? 0).toDouble();
    final err = (e['errors'] as int? ?? 0).toDouble();
    return BarChartGroupData(x: x, barRods: [
      BarChartRodData(
        toY: hits,
        width: 18,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        rodStackItems: [
          BarChartRodStackItem(0, ok, chartSuccessColor),
          BarChartRodStackItem(ok, ok + err, chartErrorColor),
          BarChartRodStackItem(ok + err, hits, AppTheme.muted.withValues(alpha: 0.5)),
        ],
      ),
    ]);
  }
}
