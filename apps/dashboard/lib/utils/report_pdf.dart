import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:scout_models/scout_models.dart';

const _palette = [
  PdfColor.fromInt(0xFF6C5CE7),
  PdfColor.fromInt(0xFFE74C3C),
  PdfColor.fromInt(0xFF00B894),
  PdfColor.fromInt(0xFFF39C12),
];
const _muted = PdfColor.fromInt(0xFF7A7A7A);
const _border = PdfColor.fromInt(0xFFDDDDDD);
const _healthy = PdfColor.fromInt(0xFF00B894);
const _attention = PdfColor.fromInt(0xFFF39C12);
const _critical = PdfColor.fromInt(0xFFE74C3C);

Future<Uint8List> buildReportPdf(Report report) async {
  final doc = pw.Document(title: '${report.title} — ${report.projectName}');
  final range = '${DateFormat('MMM d, yyyy').format(report.from.toLocal())} '
      '– ${DateFormat('MMM d, yyyy').format(report.to.toLocal())}';
  final maxPages = _maxPages(report.audience);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: maxPages,
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: _muted)),
      ),
      build: (ctx) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(report.title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('${report.projectName}  ·  $range', style: const pw.TextStyle(fontSize: 11, color: _muted)),
              if (report.audienceLabel != null)
                pw.Text('Audience: ${report.audienceLabel}', style: const pw.TextStyle(fontSize: 10, color: _muted)),
            ]),
          ),
          if (report.verdictLabel != null) _verdictBadge(report.verdict, report.verdictLabel!),
        ]),
        if (report.goNoGo != null) ...[pw.SizedBox(height: 8), _goNoGo(report.goNoGo!)],
        if (report.highlights.isNotEmpty) ...[pw.SizedBox(height: 10), _highlights(report.highlights)],
        pw.Divider(color: _border, height: 20),
        for (final s in report.sections) ..._section(s, report.audience),
        if (report.snapshotUrl != null) ...[
          pw.SizedBox(height: 8),
          pw.UrlLink(
            destination: report.snapshotUrl!,
            child: pw.Text('View full readonly report online →', style: pw.TextStyle(fontSize: 10, color: _palette[0], decoration: pw.TextDecoration.underline)),
          ),
        ],
      ],
    ),
  );
  return doc.save();
}

int _maxPages(String? audience) => switch (audience) {
      'executive' || 'client' => 1,
      _ => 2,
    };

pw.Widget _verdictBadge(String? verdict, String label) {
  final color = switch (verdict) {
    'critical' => _critical,
    'attention' => _attention,
    _ => _healthy,
  };
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: pw.Border.all(color: color, width: 1.2),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Text(label, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: color)),
  );
}

pw.Widget _goNoGo(String value) {
  final (label, color) = switch (value) {
    'go' => ('Release signal: Go', _healthy),
    'caution' => ('Release signal: Caution', _attention),
    _ => ('Release signal: No-go', _critical),
  };
  return pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color));
}

pw.Widget _highlights(List<ReportHighlight> items) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Highlights', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        for (final h in items)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text('• ${h.text}', style: const pw.TextStyle(fontSize: 10, color: _muted)),
          ),
      ],
    );

List<pw.Widget> _section(ReportSection s, String? audience) => [
      pw.Header(level: 1, text: s.title, textStyle: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      if (s.kpis.isNotEmpty) _kpiWrap(s.kpis),
      for (final c in s.charts)
        if (!c.isEmpty) ...[pw.SizedBox(height: 8), _chart(c)],
      for (final t in s.tables)
        if (t.rows.isNotEmpty) ...[pw.SizedBox(height: 10), _table(t, audience)],
      pw.SizedBox(height: 14),
    ];

pw.Widget _kpiWrap(List<ReportKpi> kpis) => pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in kpis)
          pw.Container(
            width: 140,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _border),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(k.label, style: const pw.TextStyle(fontSize: 8, color: _muted)),
              pw.SizedBox(height: 3),
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(k.value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                if (k.deltaPct != null) ...[
                  pw.SizedBox(width: 4),
                  pw.Text(_delta(k.deltaPct!),
                      style: pw.TextStyle(fontSize: 8, color: k.deltaPct! >= 0 ? _palette[1] : _palette[2])),
                ],
              ]),
            ]),
          ),
      ],
    );

pw.Widget _table(ReportTable t, String? audience) {
  final maxRows = switch (audience) {
    'executive' || 'client' => 5,
    _ => 8,
  };
  final rows = t.rows.take(maxRows).toList();
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Text(t.title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 4),
    pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: {for (var i = 0; i < t.columns.length; i++) i: const pw.FlexColumnWidth()},
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F2F5)),
          children: [
            for (final h in t.columns)
              pw.Padding(
                padding: const pw.EdgeInsets.all(5),
                child: pw.Text(h, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ),
          ],
        ),
        for (final row in rows)
          pw.TableRow(
            children: [
              for (var i = 0; i < row.cells.length; i++)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: i == 0 && row.linkUrl != null
                      ? pw.UrlLink(
                          destination: row.linkUrl!,
                          child: pw.Text(row.cells[i], style: pw.TextStyle(fontSize: 8, color: _palette[0], decoration: pw.TextDecoration.underline)),
                        )
                      : pw.Text(row.cells[i], style: const pw.TextStyle(fontSize: 8)),
                ),
            ],
          ),
      ],
    ),
    if (t.rows.length > maxRows)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text('Showing top $maxRows · open online snapshot for full list', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ),
  ]);
}

pw.Widget _chart(ReportChart c) {
  final maxY = c.series.expand((s) => s.values).fold<double>(0, (m, v) => v > m ? v : m);
  final yMax = maxY <= 0 ? 1.0 : maxY;
  final ticks = [for (var i = 0; i <= 4; i++) (yMax / 4 * i)];
  final step = (c.xLabels.length / 8).ceil().clamp(1, 999);
  final labels = [for (var i = 0; i < c.xLabels.length; i++) i % step == 0 ? c.xLabels[i] : ''];

  final datasets = <pw.Dataset>[];
  if (c.kind == 'line') {
    for (var i = 0; i < c.series.length; i++) {
      final s = c.series[i];
      datasets.add(pw.LineDataSet(
        legend: s.name,
        drawPoints: false,
        isCurved: false,
        lineWidth: 1.5,
        color: _palette[i % _palette.length],
        data: [for (var x = 0; x < s.values.length; x++) pw.PointChartValue(x.toDouble(), s.values[x])],
      ));
    }
  } else {
    final s = c.series.first;
    datasets.add(pw.BarDataSet(
      legend: s.name,
      color: _palette[0],
      width: (260 / (c.xLabels.length * 1.6)).clamp(6, 28),
      data: [for (var x = 0; x < s.values.length; x++) pw.PointChartValue(x.toDouble(), s.values[x])],
    ));
  }

  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Text(c.title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 4),
    pw.SizedBox(
      height: 130,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(labels, marginStart: 22, marginEnd: 10, textStyle: const pw.TextStyle(fontSize: 7)),
          yAxis: pw.FixedAxis(ticks, divisions: true, textStyle: const pw.TextStyle(fontSize: 7)),
        ),
        datasets: datasets,
      ),
    ),
  ]);
}

String _delta(double pct) => '${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(0)}%';
