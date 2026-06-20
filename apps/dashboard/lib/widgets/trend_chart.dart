import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points});

  final List<Map<String, dynamic>> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('No trend data yet — send events to populate charts.', style: TextStyle(color: AppTheme.muted))),
      );
    }

    final events = points.map((p) => (p['events'] as num?)?.toDouble() ?? 0).toList();
    final errors = points.map((p) => (p['errors'] as num?)?.toDouble() ?? 0).toList();
    final maxY = [...events, ...errors].fold<double>(0, (m, v) => v > m ? v : m);
    final top = maxY <= 0 ? 5.0 : maxY * 1.2;

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: top,
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: AppTheme.border, strokeWidth: 1)),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11, color: AppTheme.muted)))),
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
            _line(events, AppTheme.primary, 'Events'),
            _line(errors, AppTheme.error, 'Errors'),
          ],
          lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(getTooltipItems: (spots) {
            return spots.map((s) {
              final label = s.bar.color == AppTheme.error ? 'Errors' : 'Events';
              return LineTooltipItem('$label: ${s.y.toInt()}', const TextStyle(color: Colors.white, fontWeight: FontWeight.w600));
            }).toList();
          })),
        ),
      ),
    );
  }

  LineChartBarData _line(List<double> values, Color color, String _) {
    return LineChartBarData(
      spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
      isCurved: true,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
    );
  }
}
