import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HourlyChart extends StatelessWidget {
  const HourlyChart({super.key, required this.points, this.errorsOnly = false, this.height = 180});

  final List<Map<String, dynamic>> points;
  final bool errorsOnly;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(height: height, child: const Center(child: Text('No hourly data yet', style: TextStyle(color: AppTheme.muted))));
    }

    final bars = <BarChartGroupData>[];
    var maxY = 0.0;
    for (final p in points) {
      final h = (p['hour'] as num?)?.toInt() ?? 0;
      final v = (errorsOnly ? (p['errors'] as num?) : (p['events'] as num?))?.toDouble() ?? 0;
      if (v > maxY) maxY = v;
      bars.add(BarChartGroupData(
        x: h,
        barRods: [BarChartRodData(toY: v, color: errorsOnly ? AppTheme.error : AppTheme.primary, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))],
      ));
    }

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 5 : maxY * 1.2,
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: AppTheme.border.withValues(alpha: 0.5))),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: AppTheme.muted)))),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) => Text('${v.toInt()}h', style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
              ),
            ),
          ),
          barGroups: bars,
        ),
      ),
    );
  }
}

/// Simple ranked list for endpoints, screens, releases, etc.
class RankList extends StatelessWidget {
  const RankList({super.key, required this.items, required this.labelOf, required this.countOf, this.onTap});

  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) labelOf;
  final int Function(Map<String, dynamic>) countOf;
  final void Function(Map<String, dynamic>)? onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('No data', style: TextStyle(color: AppTheme.muted));
    final max = items.fold<int>(0, (m, i) => countOf(i) > m ? countOf(i) : m);
    return Column(
      children: items.asMap().entries.map((e) {
        final item = e.value;
        final count = countOf(item);
        final label = labelOf(item);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(item),
            borderRadius: BorderRadius.circular(8),
            child: Row(children: [
              SizedBox(width: 22, child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w700))),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.text)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: max == 0 ? 0 : count / max, minHeight: 5, backgroundColor: AppTheme.border, color: AppTheme.primary),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Text('$count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

String formatHour(int? hour) {
  if (hour == null) return '—';
  return '${hour.toString().padLeft(2, '0')}:00 UTC';
}
