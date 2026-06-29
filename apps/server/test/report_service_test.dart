import 'package:scout_models/scout_models.dart';
import 'package:scout_server/reports/report_service.dart';
import 'package:test/test.dart';

void main() {
  test('toPlainText renders kpis with deltas and tables', () {
    final report = Report(
      type: ReportType.executiveSummary.id,
      title: 'Executive Summary',
      projectName: 'Acme',
      from: DateTime.utc(2026, 1, 1),
      to: DateTime.utc(2026, 1, 8),
      generatedAt: DateTime.utc(2026, 1, 8),
      sections: const [
        ReportSection(
          title: 'Overview',
          kpis: [
            ReportKpi(label: 'Errors', value: '12', deltaPct: -25.0),
            ReportKpi(label: 'Open issues', value: '3'),
          ],
          tables: [
            ReportTable(title: 'Top issues', columns: ['Issue', 'Events'], rows: [
              ['Crash A', '9']
            ]),
          ],
        ),
      ],
    );

    final text = ReportService.toPlainText(report);
    expect(text, contains('Acme'));
    expect(text, contains('• Errors: 12 (-25%)'));
    expect(text, contains('• Open issues: 3'));
    expect(text, contains('Top issues:'));
    expect(text, contains('Crash A · 9'));
  });

  test('balancedTopIssues collapses same endpoint regardless of status', () {
    final rows = ReportService.balancedTopIssues([
      {'title': 'GET /users/123 (404)', 'type': 'network', 'count': 5},
      {'title': 'GET /users/456 (500)', 'type': 'network', 'count': 7},
    ]);
    expect(rows.length, 1);
    expect(rows.single[0], 'GET /users/:id');
    expect(rows.single[2], '12'); // counts summed
  });

  test('balancedTopIssues guarantees one row per category', () {
    final issues = [
      for (var i = 0; i < 10; i++) {'title': 'err $i', 'type': 'error', 'count': 100 - i},
      {'title': 'rare crash', 'type': 'crash', 'count': 1},
    ];
    final rows = ReportService.balancedTopIssues(issues, limit: 8);
    expect(rows.any((r) => r[1] == 'crash'), isTrue);
    expect(rows.length, 8);
  });
}
