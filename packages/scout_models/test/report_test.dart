import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  test('Report json round-trips with charts and tables', () {
    final report = Report(
      type: ReportType.executiveSummary.id,
      title: 'Executive Summary',
      projectName: 'Acme',
      from: DateTime.utc(2026, 1, 1),
      to: DateTime.utc(2026, 1, 8),
      generatedAt: DateTime.utc(2026, 1, 8, 9),
      sections: const [
        ReportSection(
          title: 'Overview',
          kpis: [ReportKpi(label: 'Errors', value: '12', deltaPct: -20.0)],
          charts: [
            ReportChart(
              title: 'Trend',
              kind: 'line',
              xLabels: ['Mon', 'Tue'],
              series: [ReportSeries(name: 'errors', values: [1, 2])],
            ),
          ],
          tables: [
            ReportTable(title: 'Top issues', columns: ['Issue', 'Count'], rows: [
              ['Crash A', '5']
            ]),
          ],
        ),
      ],
    );

    final back = Report.fromJson(report.toJson());
    expect(back.projectName, 'Acme');
    expect(back.sections.single.kpis.single.deltaPct, -20.0);
    expect(back.sections.single.charts.single.series.single.values, [1, 2]);
    expect(back.sections.single.tables.single.rows.single, ['Crash A', '5']);
    expect(ReportType.fromId('release'), ReportType.release);
  });
}
