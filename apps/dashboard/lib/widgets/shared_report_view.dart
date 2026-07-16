import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:scout_models/scout_models.dart';

import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/panel.dart';
import '../widgets/stat_card.dart';

const _series = [AppTheme.accentPurple, AppTheme.error, AppTheme.success, AppTheme.warning];

class SharedReportView extends StatelessWidget {
  const SharedReportView({super.key, required this.report, this.onIssueTap});

  final Report report;
  final void Function(String issueId)? onIssueTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: pageInsets(context, top: 16, bottom: 24),
      children: [
        if (report.verdictLabel != null) _verdictBanner(report),
        if (report.highlights.isNotEmpty) ...[
          const SizedBox(height: 12),
          _highlights(report.highlights),
        ],
        if (report.goNoGo != null) ...[
          const SizedBox(height: 12),
          _goNoGoChip(report.goNoGo!),
        ],
        const SizedBox(height: 16),
        for (final s in report.sections) ..._section(context, s),
        if (report.snapshotUrl != null) ...[
          const SizedBox(height: 8),
          Text('Full snapshot link included in exported PDF.', style: TextStyle(color: AppTheme.muted.withValues(alpha: 0.9), fontSize: 12)),
        ],
      ],
    );
  }

  Widget _verdictBanner(Report report) {
    final color = switch (report.verdict) {
      'critical' => AppTheme.error,
      'attention' => AppTheme.warning,
      _ => AppTheme.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(switch (report.verdict) {
          'critical' => Icons.error_outline,
          'attention' => Icons.warning_amber_outlined,
          _ => Icons.check_circle_outline,
        }, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(report.verdictLabel!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color))),
      ]),
    );
  }

  Widget _highlights(List<ReportHighlight> items) => DashboardPanel(
        title: 'Highlights',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final h in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('• ', style: TextStyle(color: _severityColor(h.severity))),
                  Expanded(child: Text(h.text, style: const TextStyle(fontSize: 13))),
                ]),
              ),
          ],
        ),
      );

  Widget _goNoGoChip(String value) {
    final (label, color) = switch (value) {
      'go' => ('Go', AppTheme.success),
      'caution' => ('Caution', AppTheme.warning),
      _ => ('No-go', AppTheme.error),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        label: Text('Release signal: $label', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        backgroundColor: color.withValues(alpha: 0.1),
      ),
    );
  }

  List<Widget> _section(BuildContext context, ReportSection s) => [
        const SizedBox(height: 8),
        Text(s.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (s.kpis.isNotEmpty)
          KpiWrap(
            children: [
              for (final k in s.kpis)
                StatCard(label: k.label, value: k.value, color: AppTheme.accentPurple, delta: k.deltaPct, deltaGoodWhenDown: true),
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
            DashboardPanel(title: t.title, child: _table(context, t)),
          ],
        const SizedBox(height: 16),
      ];

  Widget _table(BuildContext context, ReportTable t) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 26,
          headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.muted),
          columns: [for (final col in t.columns) DataColumn(label: Text(col))],
          rows: [
            for (final row in t.rows)
              DataRow(cells: [
                for (var i = 0; i < row.cells.length; i++)
                  DataCell(
                    i == 0 && (row.linkUrl != null || (row.issueId != null && onIssueTap != null))
                        ? InkWell(
                            onTap: () {
                              if (row.linkUrl != null) {
                                // readonly share link — open in new tab on web
                              } else if (row.issueId != null) {
                                onIssueTap!(row.issueId!);
                              }
                            },
                            child: Text(row.cells[i], style: const TextStyle(fontSize: 12, color: AppTheme.accentPurple, decoration: TextDecoration.underline)),
                          )
                        : Text(row.cells[i], style: const TextStyle(fontSize: 12)),
                  ),
              ]),
          ],
        ),
      );

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

  Color _severityColor(String severity) => switch (severity) {
        'critical' => AppTheme.error,
        'warning' => AppTheme.warning,
        _ => AppTheme.muted,
      };
}
