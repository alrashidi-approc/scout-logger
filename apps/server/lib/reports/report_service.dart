import 'package:scout_models/scout_models.dart';

import '../store/analytics_store.dart';
import '../store/scout_store.dart';
import '../util/dates.dart';
import '../util/ids.dart';

/// Assembles reports from the existing analytics queries — no new heavy SQL.
class ReportService {
  ReportService(this.scout, this.analytics);

  final ScoutStore scout;
  final AnalyticsStore analytics;

  Future<Report> build(ReportType type, String projectId, TimeWindow window) async {
    final project = await scout.fetchProjectById(projectId);
    final name = project?['name'] as String? ?? projectId;
    final from = DateTime.tryParse(window.since ?? '')?.toUtc() ?? DateTime.now().toUtc();
    final to = DateTime.tryParse(window.until ?? '')?.toUtc() ?? DateTime.now().toUtc();

    final sections = switch (type) {
      ReportType.executiveSummary => await _executiveSummary(projectId, window),
      ReportType.release => await _release(projectId, window),
    };

    return Report(
      type: type.id,
      title: type.label,
      projectName: name,
      from: from,
      to: to,
      generatedAt: DateTime.now().toUtc(),
      sections: sections,
    );
  }

  Future<List<ReportSection>> _executiveSummary(String projectId, TimeWindow w) async {
    final stats = await analytics.projectStats(projectId, window: w);
    final digest = await scout.digestData(projectId, hours: (w.approximateDays * 24).clamp(1, 24 * 90), limit: 50);
    final deltas = (stats['deltas'] as Map?) ?? const {};

    final trend = ((stats['dailyTrend'] as List?) ?? const []).cast<Map>();
    final hourly = stats['trendGranularity'] == 'hour';
    final trendChart = ReportChart(
      title: 'Errors & crashes',
      kind: 'line',
      xLabels: trend.map((r) => _tickLabel('${r['date']}', hourly)).toList(),
      series: [
        ReportSeries(name: 'Errors', values: trend.map((r) => _d(r['errors'])).toList()),
        ReportSeries(name: 'Crashes', values: trend.map((r) => _d(r['crashes'])).toList()),
      ],
    );

    final byType = ((stats['byType'] as List?) ?? const []).cast<Map>();
    final typeChart = ReportChart(
      title: 'Events by type',
      kind: 'bar',
      xLabels: byType.map((r) => '${r['type']}').toList(),
      series: [ReportSeries(name: 'Events', values: byType.map((r) => _d(r['count'])).toList())],
    );

    final overview = ReportSection(
      title: 'Overview',
      kpis: [
        ReportKpi(label: 'Events', value: _int(stats['events']), deltaPct: _d(deltas['events'])),
        ReportKpi(label: 'Errors', value: _int(stats['errors']), deltaPct: _d(deltas['errors'])),
        ReportKpi(label: 'Crashes', value: _int(stats['crashes']), deltaPct: _d(deltas['crashes'])),
        ReportKpi(label: 'Crash-free sessions', value: _pct(stats['crashFreeRatePct'])),
        ReportKpi(label: 'Error rate', value: _pct(stats['errorRatePct'])),
        ReportKpi(label: 'Unique users', value: _int(stats['uniqueUsers']), deltaPct: _d(deltas['uniqueUsers'])),
        ReportKpi(label: 'Open issues', value: _int(stats['openIssues'])),
        ReportKpi(label: 'New issues', value: '${digest.newIssues}'),
        ReportKpi(label: 'Regressions', value: '${digest.regressions}'),
      ],
      charts: [trendChart, typeChart],
    );

    final topIssues = ReportSection(
      title: 'Top issues',
      tables: [
        ReportTable(
          title: 'Most active issues',
          columns: const ['Issue', 'Type', 'Events'],
          rows: balancedTopIssues(digest.issues),
        ),
      ],
    );

    return [overview, topIssues];
  }

  Future<List<ReportSection>> _release(String projectId, TimeWindow w) async {
    final releases = await analytics.releaseComparison(projectId, window: w);
    final digest = await scout.digestData(projectId, hours: (w.approximateDays * 24).clamp(1, 24 * 90));

    final top = releases.take(8).toList();
    final crashRateChart = ReportChart(
      title: 'Crash rate by release (%)',
      kind: 'bar',
      xLabels: top.map((r) => '${r['release']}').toList(),
      series: [ReportSeries(name: 'Crash rate', values: top.map((r) => _d(r['crashRatePct'])).toList())],
    );
    final errorsChart = ReportChart(
      title: 'Errors by release',
      kind: 'bar',
      xLabels: top.map((r) => '${r['release']}').toList(),
      series: [ReportSeries(name: 'Errors', values: top.map((r) => _d(r['errors'])).toList())],
    );

    final worst = releases.isEmpty
        ? null
        : releases.reduce((a, b) => _d(a['crashRatePct']) >= _d(b['crashRatePct']) ? a : b);

    final summary = ReportSection(
      title: 'Release health',
      kpis: [
        ReportKpi(label: 'Releases', value: '${releases.length}'),
        ReportKpi(label: 'New issues', value: '${digest.newIssues}'),
        ReportKpi(label: 'Regressions', value: '${digest.regressions}'),
        if (worst != null)
          ReportKpi(label: 'Worst crash rate', value: '${worst['release']} · ${_pct(worst['crashRatePct'])}'),
      ],
      charts: [crashRateChart, errorsChart],
      tables: [
        ReportTable(
          title: 'By release',
          columns: const ['Release', 'Events', 'Errors', 'Crashes', 'Crash %', 'Users', 'Sessions'],
          rows: releases
              .map((r) => [
                    '${r['release']}',
                    _int(r['events']),
                    _int(r['errors']),
                    _int(r['crashes']),
                    _pct(r['crashRatePct']),
                    _int(r['users']),
                    _int(r['sessions']),
                  ])
              .toList(),
        ),
      ],
    );

    return [summary];
  }

  /// Concise text rendering of a report — used for digest/email bodies.
  static String toPlainText(Report r) {
    final buf = StringBuffer()..writeln(r.projectName);
    for (final s in r.sections) {
      buf
        ..writeln('')
        ..writeln(s.title.toUpperCase());
      for (final k in s.kpis) {
        final d = k.deltaPct == null ? '' : ' (${k.deltaPct! >= 0 ? '+' : ''}${k.deltaPct!.toStringAsFixed(0)}%)';
        buf.writeln('• ${k.label}: ${k.value}$d');
      }
      for (final t in s.tables) {
        if (t.rows.isEmpty) continue;
        buf.writeln('${t.title}:');
        for (final row in t.rows.take(10)) {
          buf.writeln('  - ${row.join(' · ')}');
        }
      }
    }
    return buf.toString().trim();
  }

  /// Top issues for the report: same endpoint collapses to one row (status code
  /// ignored) and every present category (crash/error/network) is guaranteed at
  /// least one slot, so a high-volume type can't bury crashes.
  static List<List<String>> balancedTopIssues(List<Map<String, dynamic>> issues, {int limit = 8}) {
    final agg = <String, ({String title, String type, int count})>{};
    for (final i in issues) {
      final type = '${i['type']}';
      final title = displayIssueTitle(type, '${i['title']}');
      final key = '$type|$title';
      final count = (i['count'] as num?)?.toInt() ?? 0;
      agg[key] = (title: title, type: type, count: (agg[key]?.count ?? 0) + count);
    }
    final ranked = agg.entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count));

    final pickedKeys = <String>{};
    final pickedTypes = <String>{};
    // One representative per category first, then fill the rest by volume.
    for (final e in ranked) {
      if (pickedTypes.add(e.value.type)) pickedKeys.add(e.key);
    }
    for (final e in ranked) {
      if (pickedKeys.length >= limit) break;
      pickedKeys.add(e.key);
    }

    return ranked
        .where((e) => pickedKeys.contains(e.key))
        .take(limit)
        .map((e) => [e.value.title, e.value.type, '${e.value.count}'])
        .toList();
  }

  /// Network titles collapse to `METHOD /normalized/route` (dropping the trailing
  /// `(status)`) so the same endpoint isn't repeated per response code.
  static String displayIssueTitle(String type, String title) {
    if (type != 'network') return title;
    final stripped = title.replaceFirst(RegExp(r'\s*\(\d{3}\)\s*$'), '');
    final sp = stripped.indexOf(' ');
    if (sp <= 0) return normalizeRoute(stripped);
    return '${stripped.substring(0, sp)} ${normalizeRoute(stripped.substring(sp + 1))}';
  }

  static double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
  static String _int(dynamic v) => '${v ?? 0}';
  static String _pct(dynamic v) => '${_d(v).toStringAsFixed(1)}%';

  static String _tickLabel(String date, bool hourly) {
    if (hourly) {
      final t = DateTime.tryParse(date);
      return t == null ? date : '${t.hour.toString().padLeft(2, '0')}:00';
    }
    return date.length >= 10 ? date.substring(5, 10) : date;
  }
}
