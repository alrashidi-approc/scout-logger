import 'package:scout_models/scout_models.dart';

import '../store/analytics_store.dart';
import '../store/notification_store.dart';
import '../store/scout_store.dart';
import '../util/dates.dart';
import '../util/dashboard_links.dart';
import '../config/server_config.dart';
import '../util/ids.dart';

/// Assembles audience-tailored reports from existing analytics queries.
class ReportService {
  ReportService(this.scout, this.analytics, {this.notifications});

  final ScoutStore scout;
  final AnalyticsStore analytics;
  final NotificationStore? notifications;

  Future<Report> build(
    ReportType type,
    String projectId,
    TimeWindow window, {
    ReportAudience audience = ReportAudience.engineering,
  }) async {
    final project = await scout.fetchProjectById(projectId);
    final name = project?['name'] as String? ?? projectId;
    final from = DateTime.tryParse(window.since ?? '')?.toUtc() ?? DateTime.now().toUtc();
    final to = DateTime.tryParse(window.until ?? '')?.toUtc() ?? DateTime.now().toUtc();
    final hours = (window.approximateDays * 24).clamp(1, 24 * 90);

    final stats = await analytics.projectStats(projectId, window: window);
    final digest = await scout.digestData(projectId, hours: hours, limit: 50);
    final releases = type == ReportType.release ? await analytics.releaseComparison(projectId, window: window) : const <Map<String, dynamic>>[];
    final deliverySummary = audience == ReportAudience.operations && notifications != null
        ? await notifications!.deliverySummary(projectId, hours: hours)
        : const <String, int>{};

    final verdict = _verdict(stats, digest);
    final highlights = _highlights(stats, digest, releases, audience, deliverySummary);
    final sections = type == ReportType.release
        ? _releaseSections(stats, digest, releases, audience, deliverySummary)
        : _executiveSections(stats, digest, audience, deliverySummary);

    return Report(
      type: type.id,
      title: '${type.label} · ${audience.label}',
      projectName: name,
      from: from,
      to: to,
      generatedAt: DateTime.now().toUtc(),
      audience: audience.id,
      audienceLabel: audience.label,
      verdict: verdict.$1,
      verdictLabel: verdict.$2,
      highlights: highlights,
      goNoGo: type == ReportType.release ? _goNoGo(stats, digest, releases) : null,
      sections: sections,
    );
  }

  Future<Report> exportForPdf({
    required ReportType type,
    required String projectId,
    required TimeWindow window,
    required ReportAudience audience,
    required ServerConfig config,
    String? createdBy,
    int expiresInDays = 30,
  }) async {
    final report = await build(type, projectId, window, audience: audience);
    final enriched = await _attachShareLinks(
      report: report,
      projectId: projectId,
      createdBy: createdBy,
      expiresInDays: expiresInDays,
      config: config,
    );
    final snapshot = await scout.createReportShareToken(
      projectId: projectId,
      payload: enriched.toJson(),
      createdBy: createdBy,
      expiresInDays: expiresInDays,
    );
    final snapshotUrl = dashboardShareUrl(config, snapshot['token'] as String);
    return Report(
      type: enriched.type,
      title: enriched.title,
      projectName: enriched.projectName,
      from: enriched.from,
      to: enriched.to,
      generatedAt: enriched.generatedAt,
      audience: enriched.audience,
      audienceLabel: enriched.audienceLabel,
      verdict: enriched.verdict,
      verdictLabel: enriched.verdictLabel,
      highlights: enriched.highlights,
      goNoGo: enriched.goNoGo,
      snapshotUrl: snapshotUrl,
      sections: enriched.sections,
    );
  }

  Future<Report> _attachShareLinks({
    required Report report,
    required String projectId,
    String? createdBy,
    required int expiresInDays,
    required ServerConfig config,
  }) async {
    final sections = <ReportSection>[];
    for (final s in report.sections) {
      final tables = <ReportTable>[];
      for (final t in s.tables) {
        final rows = <ReportTableRow>[];
        for (final row in t.rows) {
          var linkUrl = row.linkUrl;
          if (linkUrl == null && row.issueId != null) {
            final share = await scout.createShareToken(
              projectId: projectId,
              resourceType: 'issue',
              resourceId: row.issueId!,
              createdBy: createdBy,
              expiresInDays: expiresInDays,
            );
            if (share != null) linkUrl = dashboardShareUrl(config, share['token'] as String);
          }
          rows.add(ReportTableRow(cells: row.cells, issueId: row.issueId, linkUrl: linkUrl));
        }
        tables.add(ReportTable(title: t.title, columns: t.columns, rows: rows));
      }
      sections.add(ReportSection(title: s.title, kpis: s.kpis, charts: s.charts, tables: tables));
    }
    return Report(
      type: report.type,
      title: report.title,
      projectName: report.projectName,
      from: report.from,
      to: report.to,
      generatedAt: report.generatedAt,
      audience: report.audience,
      audienceLabel: report.audienceLabel,
      verdict: report.verdict,
      verdictLabel: report.verdictLabel,
      highlights: report.highlights,
      goNoGo: report.goNoGo,
      sections: sections,
    );
  }

  List<ReportSection> _executiveSections(
    Map<String, dynamic> stats,
    ({List<Map<String, dynamic>> issues, int regressions, int newIssues}) digest,
    ReportAudience audience,
    Map<String, int> deliverySummary,
  ) {
    final deltas = (stats['deltas'] as Map?) ?? const {};
    final trend = _trendChart(stats);
    final typeChart = _typeChart(stats);
    final issueLimit = _issueLimit(audience);

    final overview = ReportSection(
      title: 'Overview',
      kpis: _pickKpis(audience, stats, deltas, digest),
      charts: _pickCharts(audience, trend, typeChart),
    );

    final sections = <ReportSection>[overview];
    if (_showIssues(audience)) {
      sections.add(ReportSection(
        title: 'Top issues',
        tables: [
          ReportTable(
            title: 'Most active issues',
            columns: const ['Issue', 'Type', 'Version', 'Events'],
            rows: balancedTopIssues(digest.issues, limit: issueLimit),
          ),
        ],
      ));
    }
    if (audience == ReportAudience.operations && deliverySummary.isNotEmpty) {
      sections.add(ReportSection(
        title: 'Alert delivery',
        tables: [
          ReportTable(
            title: 'Notification delivery status',
            columns: const ['Status', 'Count'],
            rows: deliverySummary.entries
                .map((e) => ReportTableRow(cells: [e.key, '${e.value}']))
                .toList(),
          ),
        ],
      ));
    }
    return sections;
  }

  List<ReportSection> _releaseSections(
    Map<String, dynamic> stats,
    ({List<Map<String, dynamic>> issues, int regressions, int newIssues}) digest,
    List<Map<String, dynamic>> releases,
    ReportAudience audience,
    Map<String, int> deliverySummary,
  ) {
    final top = releases.take(8).toList();
    final worst = releases.isEmpty
        ? null
        : releases.reduce((a, b) => _d(a['crashRatePct']) >= _d(b['crashRatePct']) ? a : b);

    final summary = ReportSection(
      title: 'Release health',
      kpis: _pickReleaseKpis(audience, releases, digest, worst),
      charts: audience == ReportAudience.executive || audience == ReportAudience.client
          ? [_crashRateChart(top)]
          : [_crashRateChart(top), _errorsByReleaseChart(top)],
      tables: audience == ReportAudience.executive
          ? const []
          : [
              ReportTable(
                title: 'By release',
                columns: const ['Release', 'Events', 'Errors', 'Crashes', 'Crash %', 'Users', 'Sessions'],
                rows: releases
                    .take(audience == ReportAudience.client ? 5 : 12)
                    .map((r) => ReportTableRow(cells: [
                          '${r['release']}',
                          _int(r['events']),
                          _int(r['errors']),
                          _int(r['crashes']),
                          _pct(r['crashRatePct']),
                          _int(r['users']),
                          _int(r['sessions']),
                        ]))
                    .toList(),
              ),
            ],
    );

    final sections = <ReportSection>[summary];
    if (_showIssues(audience)) {
      sections.add(ReportSection(
        title: audience == ReportAudience.qaRelease ? 'Regressions & top issues' : 'Top issues',
        tables: [
          ReportTable(
            title: audience == ReportAudience.qaRelease ? 'Issues to review' : 'Most active issues',
            columns: const ['Issue', 'Type', 'Version', 'Events'],
            rows: balancedTopIssues(digest.issues, limit: _issueLimit(audience)),
          ),
        ],
      ));
    }
    if (audience == ReportAudience.operations && deliverySummary.isNotEmpty) {
      sections.add(ReportSection(
        title: 'Alert delivery',
        tables: [
          ReportTable(
            title: 'Notification delivery status',
            columns: const ['Status', 'Count'],
            rows: deliverySummary.entries
                .map((e) => ReportTableRow(cells: [e.key, '${e.value}']))
                .toList(),
          ),
        ],
      ));
    }
    return sections;
  }

  (String, String) _verdict(
    Map<String, dynamic> stats,
    ({List<Map<String, dynamic>> issues, int regressions, int newIssues}) digest,
  ) {
    final crashFree = _d(stats['crashFreeRatePct']);
    final errorsDelta = _d((stats['deltas'] as Map?)?['errors']);
    final crashesDelta = _d((stats['deltas'] as Map?)?['crashes']);
    if (crashFree < 95 || crashesDelta > 50) return ('critical', 'Critical');
    if (digest.regressions > 0 || errorsDelta > 20 || crashFree < 99) return ('attention', 'Needs attention');
    return ('healthy', 'Healthy');
  }

  String? _goNoGo(
    Map<String, dynamic> stats,
    ({List<Map<String, dynamic>> issues, int regressions, int newIssues}) digest,
    List<Map<String, dynamic>> releases,
  ) {
    final crashFree = _d(stats['crashFreeRatePct']);
    if (digest.regressions > 0 || crashFree < 98) return 'no-go';
    if (releases.isNotEmpty) {
      final worst = releases.reduce((a, b) => _d(a['crashRatePct']) >= _d(b['crashRatePct']) ? a : b);
      if (_d(worst['crashRatePct']) >= 2) return 'caution';
    }
    return 'go';
  }

  List<ReportHighlight> _highlights(
    Map<String, dynamic> stats,
    ({List<Map<String, dynamic>> issues, int regressions, int newIssues}) digest,
    List<Map<String, dynamic>> releases,
    ReportAudience audience,
    Map<String, int> deliverySummary,
  ) {
    final out = <ReportHighlight>[];
    final crashFree = _d(stats['crashFreeRatePct']);
    final errorsDelta = _d((stats['deltas'] as Map?)?['errors']);

    void add(String text, {String severity = 'info'}) {
      if (out.length >= 5) return;
      out.add(ReportHighlight(text: text, severity: severity));
    }

    switch (audience) {
      case ReportAudience.executive:
        if (digest.regressions > 0) add('$digest.regressions regression${digest.regressions == 1 ? '' : 's'} in production', severity: 'warning');
        if (errorsDelta > 20) add('Errors up ${errorsDelta.toStringAsFixed(0)}% vs previous period', severity: 'warning');
        if (crashFree >= 99) add('${crashFree.toStringAsFixed(1)}% crash-free sessions');
        if (digest.newIssues > 0) add('${digest.newIssues} new issue${digest.newIssues == 1 ? '' : 's'} opened');
      case ReportAudience.engineering:
        if (digest.regressions > 0) add('${digest.regressions} resolved issue${digest.regressions == 1 ? '' : 's'} reopened', severity: 'warning');
        final top = digest.issues.isNotEmpty ? digest.issues.first : null;
        if (top != null) add('Top issue: ${displayIssueTitle('${top['type']}', '${top['title']}')} (${top['count']} events)', severity: 'warning');
        if (errorsDelta.abs() >= 10) add('Errors ${errorsDelta >= 0 ? 'up' : 'down'} ${errorsDelta.abs().toStringAsFixed(0)}%');
        if (digest.newIssues > 0) add('${digest.newIssues} new issues in period');
      case ReportAudience.client:
        add('${crashFree.toStringAsFixed(1)}% crash-free sessions this period');
        if (digest.regressions == 0 && digest.newIssues == 0) {
          add('No new regressions detected');
        } else {
          add('${digest.newIssues} new issue${digest.newIssues == 1 ? '' : 's'} under review');
        }
        add('${_int(stats['uniqueUsers'])} active users in period');
      case ReportAudience.operations:
        if (digest.regressions > 0) add('${digest.regressions} regression${digest.regressions == 1 ? '' : 's'} need triage', severity: 'critical');
        final failed = deliverySummary['failed'] ?? 0;
        if (failed > 0) add('$failed failed alert deliveries', severity: 'warning');
        add('${_int(stats['openIssues'])} open issues');
        if (digest.newIssues > 0) add('${digest.newIssues} new issues in window', severity: 'warning');
      case ReportAudience.qaRelease:
        if (releases.isNotEmpty) {
          final worst = releases.reduce((a, b) => _d(a['crashRatePct']) >= _d(b['crashRatePct']) ? a : b);
          add('Highest crash rate: ${worst['release']} at ${_pct(worst['crashRatePct'])}', severity: _d(worst['crashRatePct']) >= 2 ? 'warning' : 'info');
        }
        if (digest.regressions > 0) add('${digest.regressions} regression${digest.regressions == 1 ? '' : 's'} block release', severity: 'critical');
        add('${digest.newIssues} new issues since last release');
    }
    return out.take(5).toList();
  }

  List<ReportKpi> _pickKpis(
    ReportAudience audience,
    Map<String, dynamic> stats,
    Map deltas,
    ({List<Map<String, dynamic>> issues, int regressions, int newIssues}) digest,
  ) {
    final all = <ReportKpi>[
      ReportKpi(label: 'Events', value: _int(stats['events']), deltaPct: _d(deltas['events'])),
      ReportKpi(label: 'Errors', value: _int(stats['errors']), deltaPct: _d(deltas['errors'])),
      ReportKpi(label: 'Crashes', value: _int(stats['crashes']), deltaPct: _d(deltas['crashes'])),
      ReportKpi(label: 'Crash-free sessions', value: _pct(stats['crashFreeRatePct'])),
      ReportKpi(label: 'Error rate', value: _pct(stats['errorRatePct'])),
      ReportKpi(label: 'Unique users', value: _int(stats['uniqueUsers']), deltaPct: _d(deltas['uniqueUsers'])),
      ReportKpi(label: 'Sessions', value: _int(stats['completedSessions'])),
      ReportKpi(label: 'Open issues', value: _int(stats['openIssues'])),
      ReportKpi(label: 'New issues', value: '${digest.newIssues}'),
      ReportKpi(label: 'Regressions', value: '${digest.regressions}'),
    ];
    final labels = switch (audience) {
      ReportAudience.executive => {'Errors', 'Crashes', 'Crash-free sessions', 'Unique users'},
      ReportAudience.client => {'Crash-free sessions', 'Errors', 'Unique users', 'Sessions'},
      ReportAudience.operations => {'Errors', 'Crashes', 'Open issues', 'Regressions', 'New issues', 'Error rate'},
      ReportAudience.qaRelease => {'Crashes', 'Errors', 'Crash-free sessions', 'Regressions', 'New issues'},
      _ => {'Events', 'Errors', 'Crashes', 'Crash-free sessions', 'Error rate', 'Unique users', 'Open issues', 'New issues', 'Regressions'},
    };
    return all.where((k) => labels.contains(k.label)).toList();
  }

  List<ReportKpi> _pickReleaseKpis(
    ReportAudience audience,
    List<Map<String, dynamic>> releases,
    ({List<Map<String, dynamic>> issues, int regressions, int newIssues}) digest,
    Map<String, dynamic>? worst,
  ) {
    final all = <ReportKpi>[
      ReportKpi(label: 'Releases', value: '${releases.length}'),
      ReportKpi(label: 'New issues', value: '${digest.newIssues}'),
      ReportKpi(label: 'Regressions', value: '${digest.regressions}'),
      if (worst != null) ReportKpi(label: 'Worst crash rate', value: '${worst['release']} · ${_pct(worst['crashRatePct'])}'),
    ];
    if (audience == ReportAudience.executive || audience == ReportAudience.client) {
      return all.take(3).toList();
    }
    return all;
  }

  List<ReportChart> _pickCharts(ReportAudience audience, ReportChart trend, ReportChart typeChart) {
    return switch (audience) {
      ReportAudience.executive || ReportAudience.client || ReportAudience.operations => [trend],
      _ => [trend, if (!typeChart.isEmpty) typeChart],
    };
  }

  bool _showIssues(ReportAudience audience) => audience != ReportAudience.executive || true;

  int _issueLimit(ReportAudience audience) => switch (audience) {
        ReportAudience.executive || ReportAudience.client => 3,
        ReportAudience.operations || ReportAudience.qaRelease => 8,
        _ => 8,
      };

  ReportChart _trendChart(Map<String, dynamic> stats) {
    final trend = ((stats['dailyTrend'] as List?) ?? const []).cast<Map>();
    final hourly = stats['trendGranularity'] == 'hour';
    return ReportChart(
      title: 'Errors & crashes',
      kind: 'line',
      xLabels: trend.map((r) => _tickLabel('${r['date']}', hourly)).toList(),
      series: [
        ReportSeries(name: 'Errors', values: trend.map((r) => _d(r['errors'])).toList()),
        ReportSeries(name: 'Crashes', values: trend.map((r) => _d(r['crashes'])).toList()),
      ],
    );
  }

  ReportChart _typeChart(Map<String, dynamic> stats) {
    final byType = ((stats['byType'] as List?) ?? const []).cast<Map>();
    return ReportChart(
      title: 'Events by type',
      kind: 'bar',
      xLabels: byType.map((r) => '${r['type']}').toList(),
      series: [ReportSeries(name: 'Events', values: byType.map((r) => _d(r['count'])).toList())],
    );
  }

  ReportChart _crashRateChart(List<Map<String, dynamic>> top) => ReportChart(
        title: 'Crash rate by release (%)',
        kind: 'bar',
        xLabels: top.map((r) => '${r['release']}').toList(),
        series: [ReportSeries(name: 'Crash rate', values: top.map((r) => _d(r['crashRatePct'])).toList())],
      );

  ReportChart _errorsByReleaseChart(List<Map<String, dynamic>> top) => ReportChart(
        title: 'Errors by release',
        kind: 'bar',
        xLabels: top.map((r) => '${r['release']}').toList(),
        series: [ReportSeries(name: 'Errors', values: top.map((r) => _d(r['errors'])).toList())],
      );

  /// Concise text rendering of a report — used for digest/email bodies.
  static String toPlainText(Report r) {
    final buf = StringBuffer()..writeln(r.projectName);
    if (r.verdictLabel != null) buf.writeln('Status: ${r.verdictLabel}');
    for (final h in r.highlights) {
      buf.writeln('• ${h.text}');
    }
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
          buf.writeln('  - ${row.cells.join(' · ')}');
        }
      }
    }
    return buf.toString().trim();
  }

  static List<ReportTableRow> balancedTopIssues(List<Map<String, dynamic>> issues, {int limit = 8}) {
    final agg = <String, ({String? id, String title, String type, int count, String version, int bestSingle})>{};
    for (final i in issues) {
      final type = '${i['type']}';
      final title = displayIssueTitle(type, '${i['title']}');
      final key = '$type|$title';
      final count = (i['count'] as num?)?.toInt() ?? 0;
      final rawVer = (i['version'] as String?)?.trim();
      final verLabel = (rawVer == null || rawVer.isEmpty) ? '—' : rawVer;
      final prev = agg[key];
      final bestSingle = prev == null ? count : (count > prev.bestSingle ? count : prev.bestSingle);
      final version = prev == null || count >= prev.bestSingle ? verLabel : prev.version;
      agg[key] = (
        id: prev?.id ?? i['id']?.toString(),
        title: title,
        type: type,
        count: (prev?.count ?? 0) + count,
        version: version,
        bestSingle: bestSingle,
      );
    }
    final ranked = agg.entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count));

    final pickedKeys = <String>{};
    final pickedTypes = <String>{};
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
        .map((e) => ReportTableRow(
              cells: [e.value.title, e.value.type, e.value.version, '${e.value.count}'],
              issueId: e.value.id,
            ))
        .toList();
  }

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
