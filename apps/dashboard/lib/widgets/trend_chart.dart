import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

const chartErrorColor = AppTheme.error;
const chartSuccessColor = AppTheme.success;

/// Total events vs error-level vs success-level outcomes over time.
class EventOutcomeChart extends StatelessWidget {
  const EventOutcomeChart({super.key, required this.points, this.height = 240, this.hourly = false});

  final List<Map<String, dynamic>> points;
  final double height;
  final bool hourly;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return _empty(height);

    final events = _series(points, 'events');
    final errors = _series(points, 'errors');
    final success = _series(points, 'success');
    final maxY = [...events, ...errors, ...success].fold<double>(0, (m, v) => v > m ? v : m);
    final top = maxY <= 0 ? 5.0 : maxY * 1.25;

    return SizedBox(
      height: height,
      child: LineChart(_lineData(
        points: points,
        hourly: hourly,
        maxY: top,
        series: [
          _Series(events, AppTheme.primary, 'All events', fill: 0.14),
          _Series(errors, chartErrorColor, 'Errors', fill: 0.12),
          _Series(success, chartSuccessColor, 'Success', fill: 0.08, width: 2),
        ],
      )),
    );
  }
}

/// Logged-in users vs anonymous guest devices (install ids).
class UserAudienceChart extends StatelessWidget {
  const UserAudienceChart({super.key, required this.points, this.height = 220, this.hourly = false});

  final List<Map<String, dynamic>> points;
  final double height;
  final bool hourly;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return _empty(height);

    final users = points.map((p) => (p['loggedInUsers'] as num?)?.toDouble() ?? (p['users'] as num?)?.toDouble() ?? 0).toList();
    final guests = _series(points, 'guestDevices');
    final maxY = [...users, ...guests].fold<double>(0, (m, v) => v > m ? v : m);
    final top = maxY <= 0 ? 5.0 : maxY * 1.25;

    return SizedBox(
      height: height,
      child: LineChart(_lineData(
        points: points,
        hourly: hourly,
        maxY: top,
        series: [
          _Series(users, AppTheme.primary, 'Logged-in users', fill: 0.14),
          _Series(guests, AppTheme.muted, 'Guest devices', fill: 0.06, width: 2, dashed: true),
        ],
      )),
    );
  }
}
List<double> _series(List<Map<String, dynamic>> points, String key) =>
    points.map((p) => (p[key] as num?)?.toDouble() ?? 0).toList();

Widget _empty(double height) => SizedBox(
      height: height,
      child: const Center(child: Text('No trend data yet', style: TextStyle(color: AppTheme.muted))),
    );

class _Series {
  const _Series(this.values, this.color, this.label, {this.fill = 0.1, this.width = 2.5, this.dashed = false});
  final List<double> values;
  final Color color;
  final String label;
  final double fill;
  final double width;
  final bool dashed;
}

LineChartData _lineData({
  required List<Map<String, dynamic>> points,
  required bool hourly,
  required double maxY,
  required List<_Series> series,
}) {
  final labelEvery = hourly ? (points.length > 12 ? 4 : 2) : 1;
  final dayFmt = DateFormat.Md();
  final hourFmt = DateFormat('HH:mm');

  return LineChartData(
    minY: 0,
    maxY: maxY,
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
            if (hourly && i % labelEvery != 0 && i != points.length - 1) return const SizedBox.shrink();
            final d = DateTime.tryParse('${points[i]['date']}');
            if (d == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(hourly ? hourFmt.format(d.toUtc()) : dayFmt.format(d), style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
            );
          },
        ),
      ),
    ),
    borderData: FlBorderData(show: false),
    lineBarsData: [
      for (final s in series)
        LineChartBarData(
          spots: [for (var i = 0; i < s.values.length; i++) FlSpot(i.toDouble(), s.values[i])],
          isCurved: true,
          color: s.color,
          barWidth: s.width,
          dashArray: s.dashed ? [6, 4] : null,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: !s.dashed,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [s.color.withValues(alpha: s.fill), s.color.withValues(alpha: 0.01)],
            ),
          ),
        ),
    ],
    lineTouchData: LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => AppTheme.panelElevated,
        getTooltipItems: (spots) {
          final i = spots.first.x.toInt();
          final d = i >= 0 && i < points.length ? DateTime.tryParse('${points[i]['date']}') : null;
          final when = d == null
              ? ''
              : hourly
                  ? '${DateFormat('MMM d, HH:mm').format(d.toUtc())} UTC\n'
                  : '${dayFmt.format(d)}\n';
          return spots.asMap().entries.map((e) {
            final spot = e.value;
            final label = series[e.key].label;
            return LineTooltipItem('$when$label: ${spot.y.toInt()}', TextStyle(color: spot.bar.color, fontWeight: FontWeight.w700));
          }).toList();
        },
      ),
    ),
  );
}
