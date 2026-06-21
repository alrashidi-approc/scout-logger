import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, this.height = 240, this.showUsers = false});

  final List<Map<String, dynamic>> points;
  final double height;
  final bool showUsers;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No trend data yet — send events to populate charts.', style: TextStyle(color: AppTheme.muted))),
      );
    }

    final events = points.map((p) => (p['events'] as num?)?.toDouble() ?? 0).toList();
    final errors = points.map((p) => (p['errors'] as num?)?.toDouble() ?? 0).toList();
    final users = points.map((p) => (p['users'] as num?)?.toDouble() ?? 0).toList();
    final all = [...events, ...errors, if (showUsers) ...users];
    final maxY = all.fold<double>(0, (m, v) => v > m ? v : m);
    final top = maxY <= 0 ? 5.0 : maxY * 1.25;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: top,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border.withValues(alpha: 0.6), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  final d = DateTime.tryParse('${points[i]['date']}');
                  if (d == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(DateFormat.Md().format(d), style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            _line(events, AppTheme.primary, fill: 0.18),
            _line(errors, AppTheme.accentPurple, fill: 0.12),
            if (showUsers) _line(users, AppTheme.success, fill: 0.08, width: 2),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppTheme.panelElevated,
              getTooltipItems: (spots) => spots.map((s) {
                final label = s.bar.color == AppTheme.accentPurple
                    ? 'Errors'
                    : s.bar.color == AppTheme.success
                        ? 'Users'
                        : 'Events';
                return LineTooltipItem('$label: ${s.y.toInt()}', TextStyle(color: s.bar.color, fontWeight: FontWeight.w700));
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  LineChartBarData _line(List<double> values, Color color, {required double fill, double width = 2.5}) {
    return LineChartBarData(
      spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
      isCurved: true,
      color: color,
      barWidth: width,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: fill), color.withValues(alpha: 0.01)])),
    );
  }
}
