import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:scout_models/scout_models.dart';

import '../services/api_client.dart';
import '../services/dashboard_log_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import '../utils/report_pdf.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/panel.dart';
import '../widgets/period_picker.dart';
import '../widgets/stat_card.dart';

const _series = [AppTheme.accentPurple, AppTheme.error, AppTheme.success, AppTheme.warning];

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(30)});

  final String projectId;
  final PeriodFilter initialPeriod;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _api = ScoutApi();
  ReportType _type = ReportType.executiveSummary;
  Report? _report;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  bool _exporting = false;
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
      final report = await _api.fetchReport(widget.projectId, _type.id, period: _period);
      if (mounted) setState(() {
        _report = report;
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
    _load();
  }

  void _selectType(ReportType t) {
    if (t == _type) return;
    setState(() => _type = t);
    _load();
  }

  Future<void> _exportPdf() async {
    final report = _report;
    if (report == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      await Printing.layoutPdf(onLayout: (_) => buildReportPdf(report));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
      refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    final report = _report;
    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        PageHeader(
          title: 'Reports',
          subtitle: 'Shareable summaries · ${_period.comparisonLabel()}',
          period: _period,
          onPeriodTap: _openPeriodPicker,
          actions: [
            FilledButton.icon(
              onPressed: report == null ? null : _exportPdf,
              icon: _exporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Save as PDF'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final t in ReportType.values)
              ChoiceChip(label: Text(t.label), selected: _type == t, onSelected: (_) => _selectType(t)),
          ],
        ),
        const SizedBox(height: 12),
        FilterBar(period: _period, onPeriodChanged: _setPeriod),
        const SizedBox(height: 20),
        if (report != null)
          for (final s in report.sections) ..._section(s),
      ],
    );
  }

  List<Widget> _section(ReportSection s) => [
        Text(s.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (s.kpis.isNotEmpty)
          KpiWrap(
            children: [
              for (final k in s.kpis)
                StatCard(
                  label: k.label,
                  value: k.value,
                  color: AppTheme.accentPurple,
                  delta: k.deltaPct,
                  deltaGoodWhenDown: true,
                ),
            ],
          ),
        for (final c in s.charts)
          if (!c.isEmpty) ...[
            const SizedBox(height: 12),
            DashboardPanel(title: c.title, child: SizedBox(height: 220, child: _chart(c))),
          ],
        for (final t in s.tables)
          if (t.rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            DashboardPanel(title: t.title, child: _table(t)),
          ],
        const SizedBox(height: 24),
      ];

  Widget _chart(ReportChart c) {
    final maxY = c.series.expand((s) => s.values).fold<double>(0, (m, v) => v > m ? v : m);
    final top = maxY <= 0 ? 1.0 : maxY * 1.15;
    final step = (c.xLabels.length / 6).ceil().clamp(1, 999);

    Widget bottom(double value, TitleMeta meta) {
      final i = value.toInt();
      if (i < 0 || i >= c.xLabels.length || i % step != 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(c.xLabels[i], style: const TextStyle(fontSize: 9, color: AppTheme.muted)),
      );
    }

    final titles = FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 26, getTitlesWidget: bottom)),
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34)),
    );

    if (c.kind == 'line') {
      return LineChart(LineChartData(
        minY: 0,
        maxY: top,
        titlesData: titles,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          for (var i = 0; i < c.series.length; i++)
            LineChartBarData(
              isCurved: false,
              barWidth: 2,
              color: _series[i % _series.length],
              dotData: const FlDotData(show: false),
              spots: [for (var x = 0; x < c.series[i].values.length; x++) FlSpot(x.toDouble(), c.series[i].values[x])],
            ),
        ],
      ));
    }

    final values = c.series.first.values;
    return BarChart(BarChartData(
      minY: 0,
      maxY: top,
      titlesData: titles,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      barGroups: [
        for (var x = 0; x < values.length; x++)
          BarChartGroupData(x: x, barRods: [BarChartRodData(toY: values[x], color: _series[0], width: 14, borderRadius: BorderRadius.circular(3))]),
      ],
    ));
  }

  Widget _table(ReportTable t) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 26,
          headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.muted),
          columns: [for (final col in t.columns) DataColumn(label: Text(col))],
          rows: [
            for (final row in t.rows)
              DataRow(cells: [for (final cell in row) DataCell(Text(cell, style: const TextStyle(fontSize: 12)))]),
          ],
        ),
      );
}
