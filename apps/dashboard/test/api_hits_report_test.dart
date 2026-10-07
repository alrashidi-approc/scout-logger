import 'package:flutter_test/flutter_test.dart';
import 'package:scout_dashboard/utils/api_hits_report.dart';

void main() {
  final data = {
    'range': {'from': '2026-10-01', 'to': '2026-10-07', 'tz': 'Asia/Kuwait'},
    'bucket': 'day',
    'coverage': {'networkLogScope': 'all', 'ignoredStatusCodes': <int>[]},
    'totals': {'hits': 1000, 'success': 900, 'errors': 60},
    'endpoints': [
      {'key': 'GET h/api/ssn-details', 'method': 'GET', 'path': 'h/api/ssn-details', 'hits': 900, 'success': 840, 'errors': 10},
      {'key': 'POST h/api/a|b', 'method': 'POST', 'path': 'h/api/a|b', 'hits': 100, 'success': 50, 'errors': 50},
    ],
    'series': [
      for (var d = 1; d <= 7; d++)
        {'date': '2026-10-0${d}T00:00:00', 'events': d == 3 ? 400 : 100, 'success': 0, 'errors': 0},
    ],
  };

  test('header shows the local calendar range and zone', () {
    final md = buildApiHitsMarkdown(projectName: 'EPA', data: data, generatedAt: DateTime.utc(2026, 10, 7, 9));
    expect(md, startsWith('# API calls report: EPA'));
    expect(md, contains('- **Period:** Thu Oct 1, 2026 to Wed Oct 7, 2026, 12:00 AM to 12:00 AM (Asia/Kuwait)'));
    expect(md, contains('## Calls over time (daily, Asia/Kuwait)'));
    expect(md, contains('| Sat Oct 3 | 400 | 0 |'));
  });

  test('summarizes totals, per-day rate and peak', () {
    final md = buildApiHitsMarkdown(projectName: 'EPA', data: data);
    expect(md, contains('| Total API calls | 1,000 |'));
    expect(md, contains('| Average per day | 143 |'));
    expect(md, contains('| Busiest day | 400 on Sat Oct 3 |'));
    expect(md, contains('| Failed calls | 60 (6.0%) |'));
    expect(md, isNot(contains('Counts may be incomplete')));
  });

  test('endpoint table escapes pipes and computes share', () {
    final md = buildApiHitsMarkdown(projectName: 'EPA', data: data);
    expect(md, contains(r'| 2 | POST | `h/api/a\|b` | 100 | 14 | 10.0% | 50 | 50.0% |'));
    expect(md, contains('| 1 | GET | `h/api/ssn-details` | 900 | 129 | 90.0% | 10 | 1.1% |'));
  });

  test('flags high-volume and high-failure endpoints', () {
    final md = buildApiHitsMarkdown(projectName: 'EPA', data: data);
    expect(md, contains('- `GET h/api/ssn-details`: 90.0% of all calls'));
    expect(md, contains(r'- `POST h/api/a\|b`: 50.0% of calls fail'));
  });

  test('single day reads as one date', () {
    final md = buildApiHitsMarkdown(projectName: 'EPA', data: {
      'range': {'from': '2026-10-07', 'to': '2026-10-07', 'tz': 'Asia/Kuwait'},
      'bucket': 'hour',
    });
    expect(md, contains('- **Period:** Wed Oct 7, 2026, 12:00 AM to 12:00 AM (Asia/Kuwait)'));
    expect(md, contains('_No API calls in this period._'));
    expect(md, contains('No endpoint stands out'));
  });

  test('coverage warnings explain missing calls', () {
    final warnings = apiHitsCoverageWarnings({
      'coverage': {
        'networkLogScope': 'errorsOnly',
        'ignoredStatusCodes': [401, 403],
        'retentionDays': 30,
        'incompleteBefore': '2026-09-07T08:00:00Z',
      },
    });
    expect(warnings, hasLength(3));
    expect(warnings[0], contains('errors only'));
    expect(warnings[1], contains('HTTP 401, 403'));
    expect(warnings[2], contains('Sep 7, 2026 08:00 UTC'));
    final md = buildApiHitsMarkdown(projectName: 'EPA', data: {...data, 'coverage': {'networkLogScope': 'slowOnly'}});
    expect(md, contains('> **Counts may be incomplete**'));
    expect(md, contains('slow only'));
  });
}
