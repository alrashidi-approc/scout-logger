/// Render-agnostic report shapes shared by the server (assembly) and the
/// dashboard (on-screen render + PDF export).

class ReportKpi {
  const ReportKpi({required this.label, required this.value, this.deltaPct});

  final String label;
  final String value;
  final double? deltaPct;

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        if (deltaPct != null) 'deltaPct': deltaPct,
      };

  factory ReportKpi.fromJson(Map<String, dynamic> j) => ReportKpi(
        label: j['label'] as String? ?? '',
        value: '${j['value'] ?? ''}',
        deltaPct: (j['deltaPct'] as num?)?.toDouble(),
      );
}

class ReportSeries {
  const ReportSeries({required this.name, required this.values});

  final String name;
  final List<double> values;

  Map<String, dynamic> toJson() => {'name': name, 'values': values};

  factory ReportSeries.fromJson(Map<String, dynamic> j) => ReportSeries(
        name: j['name'] as String? ?? '',
        values: ((j['values'] as List?) ?? const []).map((e) => (e as num).toDouble()).toList(),
      );
}

class ReportChart {
  const ReportChart({
    required this.title,
    required this.kind,
    required this.xLabels,
    required this.series,
  });

  final String kind;
  final String title;
  final List<String> xLabels;
  final List<ReportSeries> series;

  bool get isEmpty => series.every((s) => s.values.every((v) => v == 0)) || xLabels.isEmpty;

  Map<String, dynamic> toJson() => {
        'title': title,
        'kind': kind,
        'xLabels': xLabels,
        'series': series.map((s) => s.toJson()).toList(),
      };

  factory ReportChart.fromJson(Map<String, dynamic> j) => ReportChart(
        title: j['title'] as String? ?? '',
        kind: j['kind'] as String? ?? 'bar',
        xLabels: ((j['xLabels'] as List?) ?? const []).map((e) => '$e').toList(),
        series: ((j['series'] as List?) ?? const [])
            .map((e) => ReportSeries.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class ReportTableRow {
  const ReportTableRow({required this.cells, this.linkUrl, this.issueId});

  final List<String> cells;
  final String? linkUrl;
  final String? issueId;

  Map<String, dynamic> toJson() => {
        'cells': cells,
        if (linkUrl != null) 'linkUrl': linkUrl,
        if (issueId != null) 'issueId': issueId,
      };

  factory ReportTableRow.fromJson(dynamic raw) {
    if (raw is Map) {
      final j = Map<String, dynamic>.from(raw);
      return ReportTableRow(
        cells: ((j['cells'] as List?) ?? const []).map((e) => '$e').toList(),
        linkUrl: j['linkUrl'] as String?,
        issueId: j['issueId'] as String?,
      );
    }
    return ReportTableRow(cells: (raw as List).map((e) => '$e').toList());
  }
}

class ReportTable {
  const ReportTable({required this.title, required this.columns, required this.rows});

  final String title;
  final List<String> columns;
  final List<ReportTableRow> rows;

  Map<String, dynamic> toJson() => {
        'title': title,
        'columns': columns,
        'rows': rows.map((r) => r.toJson()).toList(),
      };

  factory ReportTable.fromJson(Map<String, dynamic> j) => ReportTable(
        title: j['title'] as String? ?? '',
        columns: ((j['columns'] as List?) ?? const []).map((e) => '$e').toList(),
        rows: ((j['rows'] as List?) ?? const []).map(ReportTableRow.fromJson).toList(),
      );
}

class ReportHighlight {
  const ReportHighlight({required this.text, this.severity = 'info'});

  final String text;
  final String severity;

  Map<String, dynamic> toJson() => {'text': text, 'severity': severity};

  factory ReportHighlight.fromJson(Map<String, dynamic> j) => ReportHighlight(
        text: j['text'] as String? ?? '',
        severity: j['severity'] as String? ?? 'info',
      );
}

class ReportSection {
  const ReportSection({
    required this.title,
    this.kpis = const [],
    this.charts = const [],
    this.tables = const [],
  });

  final String title;
  final List<ReportKpi> kpis;
  final List<ReportChart> charts;
  final List<ReportTable> tables;

  Map<String, dynamic> toJson() => {
        'title': title,
        'kpis': kpis.map((k) => k.toJson()).toList(),
        'charts': charts.map((c) => c.toJson()).toList(),
        'tables': tables.map((t) => t.toJson()).toList(),
      };

  factory ReportSection.fromJson(Map<String, dynamic> j) => ReportSection(
        title: j['title'] as String? ?? '',
        kpis: ((j['kpis'] as List?) ?? const [])
            .map((e) => ReportKpi.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        charts: ((j['charts'] as List?) ?? const [])
            .map((e) => ReportChart.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        tables: ((j['tables'] as List?) ?? const [])
            .map((e) => ReportTable.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class Report {
  const Report({
    required this.type,
    required this.title,
    required this.projectName,
    required this.from,
    required this.to,
    required this.generatedAt,
    required this.sections,
    this.audience,
    this.audienceLabel,
    this.verdict,
    this.verdictLabel,
    this.highlights = const [],
    this.snapshotUrl,
    this.goNoGo,
  });

  final String type;
  final String title;
  final String projectName;
  final DateTime from;
  final DateTime to;
  final DateTime generatedAt;
  final List<ReportSection> sections;
  final String? audience;
  final String? audienceLabel;
  final String? verdict;
  final String? verdictLabel;
  final List<ReportHighlight> highlights;
  final String? snapshotUrl;
  final String? goNoGo;

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'projectName': projectName,
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
        'sections': sections.map((s) => s.toJson()).toList(),
        if (audience != null) 'audience': audience,
        if (audienceLabel != null) 'audienceLabel': audienceLabel,
        if (verdict != null) 'verdict': verdict,
        if (verdictLabel != null) 'verdictLabel': verdictLabel,
        if (highlights.isNotEmpty) 'highlights': highlights.map((h) => h.toJson()).toList(),
        if (snapshotUrl != null) 'snapshotUrl': snapshotUrl,
        if (goNoGo != null) 'goNoGo': goNoGo,
      };

  factory Report.fromJson(Map<String, dynamic> j) => Report(
        type: j['type'] as String? ?? '',
        title: j['title'] as String? ?? 'Report',
        projectName: j['projectName'] as String? ?? '',
        from: DateTime.tryParse('${j['from']}')?.toUtc() ?? DateTime.now().toUtc(),
        to: DateTime.tryParse('${j['to']}')?.toUtc() ?? DateTime.now().toUtc(),
        generatedAt: DateTime.tryParse('${j['generatedAt']}')?.toUtc() ?? DateTime.now().toUtc(),
        sections: ((j['sections'] as List?) ?? const [])
            .map((e) => ReportSection.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        audience: j['audience'] as String?,
        audienceLabel: j['audienceLabel'] as String?,
        verdict: j['verdict'] as String?,
        verdictLabel: j['verdictLabel'] as String?,
        highlights: ((j['highlights'] as List?) ?? const [])
            .map((e) => ReportHighlight.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        snapshotUrl: j['snapshotUrl'] as String?,
        goNoGo: j['goNoGo'] as String?,
      );
}

enum ReportType {
  executiveSummary('executive-summary', 'Executive Summary'),
  release('release', 'Release Report');

  const ReportType(this.id, this.label);
  final String id;
  final String label;

  static ReportType? fromId(String? id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

enum ReportAudience {
  executive('executive', 'Executive'),
  engineering('engineering', 'Engineering'),
  client('client', 'Client'),
  operations('operations', 'Operations'),
  qaRelease('qa-release', 'QA / Release');

  const ReportAudience(this.id, this.label);
  final String id;
  final String label;

  static ReportAudience? fromId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }

  static ReportAudience fromIdOrDefault(String? id) => fromId(id) ?? ReportAudience.engineering;
}
