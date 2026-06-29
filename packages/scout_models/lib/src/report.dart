/// Render-agnostic report shapes shared by the server (assembly) and the
/// dashboard (on-screen render + PDF export). Kept deliberately flat so new
/// report types only need to emit different sections.

class ReportKpi {
  const ReportKpi({required this.label, required this.value, this.deltaPct});

  final String label;
  final String value;

  /// Percentage change vs the previous period (drives ▲▼ coloring). Null hides it.
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

  /// `line` or `bar`.
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

class ReportTable {
  const ReportTable({required this.title, required this.columns, required this.rows});

  final String title;
  final List<String> columns;
  final List<List<String>> rows;

  Map<String, dynamic> toJson() => {'title': title, 'columns': columns, 'rows': rows};

  factory ReportTable.fromJson(Map<String, dynamic> j) => ReportTable(
        title: j['title'] as String? ?? '',
        columns: ((j['columns'] as List?) ?? const []).map((e) => '$e').toList(),
        rows: ((j['rows'] as List?) ?? const [])
            .map((r) => ((r as List?) ?? const []).map((e) => '$e').toList())
            .toList(),
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
  });

  final String type;
  final String title;
  final String projectName;
  final DateTime from;
  final DateTime to;
  final DateTime generatedAt;
  final List<ReportSection> sections;

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'projectName': projectName,
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
        'generatedAt': generatedAt.toIso8601String(),
        'sections': sections.map((s) => s.toJson()).toList(),
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
