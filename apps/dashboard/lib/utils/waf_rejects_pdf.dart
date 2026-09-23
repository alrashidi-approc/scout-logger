import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config/brand.dart';

const _primary = PdfColor.fromInt(0xFF2563EB);
const _sidebar = PdfColor.fromInt(0xFF0F172A);
const _muted = PdfColor.fromInt(0xFF64748B);
const _border = PdfColor.fromInt(0xFFE2E8F0);
const _panel = PdfColor.fromInt(0xFFF8FAFC);
const _error = PdfColor.fromInt(0xFFDC2626);

class WafPdfOccurrence {
  const WafPdfOccurrence({
    required this.requestId,
    required this.url,
    required this.occurredAt,
    required this.curl,
    this.statusCode,
    this.scoutUrl,
  });

  final String? requestId;
  final String url;
  final DateTime occurredAt;
  final String curl;
  final String? statusCode;
  final String? scoutUrl;
}

class WafPdfUrlGroup {
  const WafPdfUrlGroup({required this.url, required this.occurrences});

  final String url;
  final List<WafPdfOccurrence> occurrences;

  int get count => occurrences.length;
}

/// Group export rows by full URL (path + query), newest first within each group.
List<WafPdfUrlGroup> groupWafExportEvents(List<Map<String, dynamic>> events) {
  final byUrl = <String, List<WafPdfOccurrence>>{};
  for (final e in events) {
    final url = (e['url']?.toString() ?? '').trim();
    if (url.isEmpty) continue;
    final at = DateTime.tryParse(e['occurredAt']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    final occ = WafPdfOccurrence(
      requestId: e['requestId']?.toString(),
      url: url,
      occurredAt: at,
      curl: e['curl']?.toString() ?? '',
      statusCode: e['statusCode']?.toString(),
      scoutUrl: e['scoutUrl']?.toString(),
    );
    (byUrl[url] ??= []).add(occ);
  }
  final groups = [
    for (final e in byUrl.entries) WafPdfUrlGroup(url: e.key, occurrences: e.value),
  ];
  groups.sort((a, b) {
    final c = b.count.compareTo(a.count);
    if (c != 0) return c;
    return b.occurrences.first.occurredAt.compareTo(a.occurrences.first.occurredAt);
  });
  return groups;
}

Future<Uint8List> buildWafRejectsPdf({
  required String projectName,
  required List<WafPdfUrlGroup> groups,
  required String periodLabel,
  String? environment,
  String? appVersion,
  String? search,
  int? total,
  int? exported,
}) async {
  final doc = pw.Document(title: 'WAF Rejects — $projectName');
  final generated = DateFormat('MMM d, yyyy · HH:mm').format(DateTime.now());
  final filterBits = <String>[
    periodLabel,
    if (environment != null && environment.isNotEmpty) 'env: $environment',
    if (appVersion != null && appVersion.isNotEmpty) 'v$appVersion',
    if (search != null && search.isNotEmpty) 'q: $search',
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      maxPages: 40,
      header: (ctx) => _brandHeader(projectName, generated),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          '${Brand.name}  ·  Page ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ),
      build: (ctx) => [
        pw.SizedBox(height: 8),
        pw.Text('WAF rejects', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _sidebar)),
        pw.SizedBox(height: 4),
        pw.Text(filterBits.join('  ·  '), style: const pw.TextStyle(fontSize: 10, color: _muted)),
        if (total != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            exported != null && exported < total
                ? '$exported of $total rejects in this PDF (export cap)'
                : '$total rejects · ${groups.length} unique URLs',
            style: const pw.TextStyle(fontSize: 9, color: _muted),
          ),
        ],
        pw.SizedBox(height: 12),
        if (groups.isEmpty)
          pw.Text('No WAF rejects matched the current filters.', style: const pw.TextStyle(fontSize: 11, color: _muted))
        else
          for (final g in groups) ...[
            _groupHeader(g),
            pw.SizedBox(height: 4),
            _occurrenceTable(g.occurrences),
            pw.SizedBox(height: 14),
          ],
      ],
    ),
  );
  return doc.save();
}

pw.Widget _brandHeader(String projectName, String generated) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _border, width: 1))),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 28,
          height: 28,
          decoration: pw.BoxDecoration(color: _primary, borderRadius: pw.BorderRadius.circular(6)),
          alignment: pw.Alignment.center,
          child: pw.Text('S', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14)),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(Brand.name, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _sidebar)),
              pw.Text(Brand.slogan, style: const pw.TextStyle(fontSize: 8, color: _muted)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(projectName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _sidebar)),
            pw.Text('Generated $generated', style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _groupHeader(WafPdfUrlGroup g) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: pw.BoxDecoration(
      color: _panel,
      border: pw.Border.all(color: _border),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: pw.BoxDecoration(
            color: _error,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            '×${g.count}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(
            g.url,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _sidebar),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _occurrenceTable(List<WafPdfOccurrence> rows) {
  final fmt = DateFormat('MMM d, yyyy HH:mm:ss');
  pw.Widget cell(String text, {bool header = false, PdfColor? color}) => pw.Padding(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: header ? 8 : 7,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? _sidebar,
          ),
        ),
      );

  return pw.Table(
    border: pw.TableBorder.all(color: _border, width: 0.5),
    columnWidths: {
      0: const pw.FlexColumnWidth(1.2),
      1: const pw.FlexColumnWidth(1.2),
      2: const pw.FlexColumnWidth(1.4),
      3: const pw.FlexColumnWidth(2.8),
      4: const pw.FlexColumnWidth(3.4),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _panel),
        children: [
          cell('Request ID', header: true),
          cell('Date & time', header: true),
          cell('Scout event', header: true),
          cell('API URL', header: true),
          cell('cURL', header: true),
        ],
      ),
      for (final r in rows)
        pw.TableRow(
          children: [
            cell(r.requestId?.isNotEmpty == true ? r.requestId! : '—'),
            cell(fmt.format(r.occurredAt)),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: r.scoutUrl != null && r.scoutUrl!.isNotEmpty
                  ? pw.UrlLink(
                      destination: r.scoutUrl!,
                      child: pw.Text(
                        r.scoutUrl!,
                        style: const pw.TextStyle(fontSize: 6.5, color: _primary),
                      ),
                    )
                  : pw.Text('—', style: const pw.TextStyle(fontSize: 7, color: _sidebar)),
            ),
            cell(r.url),
            cell(r.curl.isEmpty ? '—' : r.curl),
          ],
        ),
    ],
  );
}
