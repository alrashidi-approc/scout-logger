@Tags(['db'])
library;

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/store/analytics_store.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:scout_server/util/event_filters.dart';
import 'package:test/test.dart';

import 'test_db.dart';

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);
  final analytics = AnalyticsStore(db);
  const pid = 'api';
  const kuwait = 'Asia/Kuwait'; // UTC+3, no DST
  final oct5 = DateTime.utc(2025, 10, 5);
  final oct6 = DateTime.utc(2025, 10, 6);
  final oct11 = DateTime.utc(2025, 10, 11);

  IngestEvent call(String method, String url, int status, String at) => IngestEvent(
        type: 'network',
        timestamp: at,
        payload: {
          'network': {'method': method, 'url': url, 'statusCode': status, 'hasResponse': true},
        },
      );

  setUpAll(() async {
    await (await db.connect()).execute(
      Sql.named('INSERT INTO projects (id, name, slug) VALUES (@id, @id, @id)'),
      parameters: {'id': pid},
    );
    const ssn = 'https://falcon.epa.gov.kw/epa_bridge/api/ssn-details';
    await store.ingestBatch(projectId: pid, keyId: 'k', enrichment: const {}, events: [
      // Kuwait Oct 5 23:59:59 — the second before midnight.
      call('GET', '$ssn?serial=1&ssn=2', 200, '2025-10-05T20:59:59Z'),
      // Kuwait Oct 6 00:00:00 — first second of the day.
      call('get', '$ssn?serial=3&ssn=4', 200, '2025-10-05T21:00:00Z'),
      // Kuwait Oct 6 14:30.
      call('GET', '$ssn/', 500, '2025-10-06T11:30:00Z'),
      // Kuwait Oct 6 23:59:59 — last second of the day.
      call('POST', 'https://h/users/123/orders/3F2504E0-4F89-11D3-9A0C-0305E82C3301', 201, '2025-10-06T20:59:59Z'),
      // Kuwait Oct 7 00:00:00 — next day.
      call('POST', 'https://h/users/456/orders/1', 201, '2025-10-06T21:00:00Z'),
      // Kuwait Oct 10 09:00.
      call('GET', '$ssn?x=1', 200, '2025-10-10T06:00:00Z'),
    ]);
  });

  Future<Map<String, dynamic>> hits(DateTime from, DateTime to, {String tz = kuwait, String? endpoint}) =>
      analytics.apiHits(pid, from: from, to: to, tz: tz, endpoint: endpoint);
  int total(Map<String, dynamic> r) => (r['totals'] as Map)['hits'] as int;

  test('a single day runs local midnight to midnight, to the second', () async {
    final r = await hits(oct6, oct6);
    expect(total(r), 3);
    expect(r['range'], containsPair('since', '2025-10-05T21:00:00.000Z'));
    expect(r['range'], containsPair('until', '2025-10-06T21:00:00.000Z'));
    expect(r['bucket'], 'hour');
    final series = r['series'] as List;
    expect(series.length, 24);
    expect(series.first['date'], '2025-10-06T00:00:00');
    expect(series.first['events'], 1);
    expect(series[14]['events'], 1);
    expect(series.last['events'], 1);
  });

  test('the same calendar day in UTC has different boundaries', () async {
    expect(total(await hits(oct5, oct5)), 1);
    expect(total(await hits(oct5, oct5, tz: 'UTC')), 2);
  });

  test('multi-day range buckets daily and series sums to the total', () async {
    final r = await hits(oct5, oct11);
    expect(r['bucket'], 'day');
    final series = r['series'] as List;
    expect(series.map((p) => p['date']), [for (var d = 5; d <= 11; d++) '2025-10-${d.toString().padLeft(2, '0')}T00:00:00']);
    expect(series.map((p) => p['events']), [1, 3, 1, 0, 0, 1, 0]);
    expect(total(r), 6);
    expect(series.fold<int>(0, (s, p) => s + (p['events'] as int)), 6);
    final endpoints = {for (final e in r['endpoints'] as List) e['key']: e['hits']};
    expect(endpoints, {
      'GET falcon.epa.gov.kw/epa_bridge/api/ssn-details': 4,
      'POST h/users/:id/orders/:id': 2,
    });
  });

  test('endpoint filter accepts a pasted URL, path suffix, or METHOD key', () async {
    Future<int> count(String endpoint) async => total(await hits(oct6, oct6, endpoint: endpoint));
    expect(await count('https://falcon.epa.gov.kw/epa_bridge/api/ssn-details?serial=9'), 2);
    expect(await count('/epa_bridge/api/ssn-details'), 2);
    expect(await count('POST h/users/:id/orders/:id'), 1);
    expect(await count('GET h/users/:id/orders/:id'), 0);
    expect(await count('/api/ssn'), 0);
  });

  test('unknown timezone falls back to UTC', () async {
    final r = await hits(oct6, oct6, tz: 'Not/AZone');
    expect(r['range'], containsPair('tz', 'UTC'));
  });

  test('coverage reports SDK scope and ignored codes', () async {
    final r = await hits(oct6, oct6);
    expect(r['coverage'], containsPair('networkLogScope', 'all'));
    expect(r['coverage'], containsPair('ignoredStatusCodes', isEmpty));
  });

  test('SQL path matches apiEndpointPath', () async {
    const urls = [
      'https://h/a/1/b/?q=1#f',
      'http://h:8080/x/3F2504E0-4F89-11D3-9A0C-0305E82C3301',
      '/rel/42',
      '/',
      ' https://h/v2/users ',
    ];
    final conn = await db.connect();
    for (final url in urls) {
      final rows = await conn.execute(
        Sql.named('''
          SELECT $sqlApiEndpointPath
          FROM (SELECT jsonb_build_object('network', jsonb_build_object('url', @url::text)) AS payload) e
        '''),
        parameters: {'url': url},
      );
      expect(rows.first[0], apiEndpointPath(url), reason: url);
    }
  });
}
