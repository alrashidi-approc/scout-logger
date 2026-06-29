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

Future<Uint8List> buildReportPdf(Report report) async {
  final doc = pw.Document(title: '${report.title} — ${report.projectName}');
  final range = '${DateFormat('MMM d, yyyy').format(report.from.toLocal())} '
      '– ${DateFormat('MMM d, yyyy').format(report.to.toLocal())}';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: _muted)),
      ),
      build: (ctx) => [
        pw.Text(report.title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text('${report.projectName}  ·  $range',
            style: const pw.TextStyle(fontSize: 11, color: _muted)),
        pw.Divider(color: _border, height: 24),
        for (final s in report.sections) ..._section(s),
      ],
    ),
  );
  return doc.save();
}

List<pw.Widget> _section(ReportSection s) => [
      pw.Header(level: 1, text: s.title, textStyle: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      if (s.kpis.isNotEmpty) _kpiWrap(s.kpis),
      for (final c in s.charts)
        if (!c.isEmpty) ...[pw.SizedBox(height: 10), _chart(c)],
      for (final t in s.tables)
        if (t.rows.isNotEmpty) ...[pw.SizedBox(height: 12), _table(t)],
      pw.SizedBox(height: 18),
    ];

pw.Widget _kpiWrap(List<ReportKpi> kpis) => pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final k in kpis)
          pw.Container(
            width: 150,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _border),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(k.label, style: const pw.TextStyle(fontSize: 9, color: _muted)),
              pw.SizedBox(height: 4),
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(k.value, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                if (k.deltaPct != null) ...[
                  pw.SizedBox(width: 6),
                  pw.Text(_delta(k.deltaPct!),
                      style: pw.TextStyle(fontSize: 9, color: k.deltaPct! >= 0 ? _palette[1] : _palette[2])),
                ],
              ]),
            ]),
          ),
      ],
    );

pw.Widget _table(ReportTable t) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(t.title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: t.columns,
        data: t.rows,
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF2F2F5)),
        cellAlignment: pw.Alignment.centerLeft,
        cellHeight: 20,
        border: pw.TableBorder.all(color: _border, width: 0.5),
      ),
    ]);

pw.Widget _chart(ReportChart c) {
  final maxY = c.series
      .expand((s) => s.values)
      .fold<double>(0, (m, v) => v > m ? v : m);
  final yMax = maxY <= 0 ? 1.0 : maxY;
  final ticks = [for (var i = 0; i <= 4; i++) (yMax / 4 * i)];
  final step = (c.xLabels.length / 8).ceil().clamp(1, 999);
  final labels = [
    for (var i = 0; i < c.xLabels.length; i++) i % step == 0 ? c.xLabels[i] : '',
  ];

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
    pw.Text(c.title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
    if (c.kind == 'line' && c.series.length > 1) ...[
      pw.SizedBox(height: 4),
      pw.Row(children: [
        for (var i = 0; i < c.series.length; i++) ...[
          pw.Container(width: 8, height: 8, color: _palette[i % _palette.length]),
          pw.SizedBox(width: 4),
          pw.Text(c.series[i].name, style: const pw.TextStyle(fontSize: 9, color: _muted)),
          pw.SizedBox(width: 12),
        ],
      ]),
    ],
    pw.SizedBox(height: 6),
    pw.SizedBox(
      height: 150,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis.fromStrings(labels, marginStart: 26, marginEnd: 12, textStyle: const pw.TextStyle(fontSize: 7)),
          yAxis: pw.FixedAxis(ticks, divisions: true, textStyle: const pw.TextStyle(fontSize: 7)),
        ),
        datasets: datasets,
      ),
    ),
  ]);
}

String _delta(double pct) => '${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(0)}%';
