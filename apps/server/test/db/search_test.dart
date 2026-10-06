@Tags(['db'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/db/scout_db.dart';
import 'package:scout_server/store/analytics_store.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:scout_server/util/dates.dart';
import 'package:scout_server/util/event_filters.dart';
import 'package:test/test.dart';

import 'test_db.dart';

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);
  final analytics = AnalyticsStore(db);

  // Golden captured from the pre-trigram per-field ILIKE queries on these fixtures.
  test('search matches the pre-trigram ILIKE results, except the documented differences', () async {
    await (await db.connect()).execute("INSERT INTO projects (id, name, slug) VALUES ('s', 's', 's')");
    final now = DateTime.now().toUtc();
    var i = 0;
    IngestEvent ev(String type, Map<String, dynamic> payload) =>
        IngestEvent(type: type, timestamp: now.subtract(Duration(minutes: ++i)).toIso8601String(), payload: payload);
    await store.ingestBatch(projectId: 's', keyId: 'k', enrichment: const {}, events: [
      ev('error', {
        'message': 'boom at checkout',
        'level': 'error',
        'user': {'id': 'user-42', 'email': 'alice@example.com', 'name': 'Alice Smith'},
        'device': {'deviceName': 'Pixel 7', 'installId': 'inst-7'},
        'stack': 'StackFrame#0 main.dart\n${'x' * 2100} deepframe',
      }),
      ev('log', {'message': 'user tapped pay', 'level': 'info', 'sessionId': 'sess-9', 'user': {'id': 'user-43'}}),
      ev('network', {
        'message': 'POST /api/pay',
        'level': 'error',
        'network': {'url': 'https://x.test/api/pay', 'statusCode': 500, 'method': 'POST', 'traceId': 'trace-abc'},
        'device': {'deviceModel': 'iPhone 14', 'installId': 'inst-8'},
        'user': {'id': 'user-44', 'email': 'bob@example.com'},
      }),
      ev('error', {'message': 'other failure', 'level': 'error', 'stackTrace': 'TraceOnly frame', 'user': {'id': 'user-45', 'name': 'Carol'}}),
    ]);

    final out = <String, Object?>{};
    for (final q in ['boom', 'user-42', 'sess-9', 'inst-7', '/api/pay', 'trace-abc', 'pixel', 'alice@', 'Alice Smith', 'StackFrame', 'deepframe', 'TraceOnly', 'Carol', 'example', 'zzznomatch']) {
      final events = await store.listEvents('s', q: q, window: TimeWindow.lastDays(7));
      final issues = await store.listIssues('s', q: q, window: TimeWindow.lastDays(7));
      final users = await analytics.listUsers('s', q: q, window: TimeWindow.lastDays(7));
      final devices = await analytics.listDevices('s', q: q, window: TimeWindow.lastDays(7));
      out[q] = {
        'events': [for (final e in events['events'] as List) (e as Map)['message']],
        'issues': [for (final e in issues) e['title']],
        'users': [for (final e in users) e['userId']],
        'devices': [for (final e in devices) e['installId']],
      };
    }
    final expected = jsonDecode(File('test/db/fixtures/search_snapshot.json').readAsStringSync()) as Map<String, dynamic>;
    void differs(String q, String list, List<String> now) => (expected[q] as Map)[list] = now;
    // One field set for every event search: events now also match install id, user email/name…
    differs('inst-7', 'events', ['boom at checkout']);
    differs('alice@', 'events', ['boom at checkout']);
    differs('Alice Smith', 'events', ['boom at checkout']);
    differs('Carol', 'events', ['other failure']);
    differs('example', 'events', ['boom at checkout', 'POST /api/pay']);
    // …and issues also match trace id and stackTrace.
    differs('trace-abc', 'issues', ['POST /api/pay · Server error']);
    differs('TraceOnly', 'issues', ['other failure']);
    // Only the first 2000 chars of a stack are searchable.
    differs('deepframe', 'events', []);
    differs('deepframe', 'issues', []);
    expect(jsonDecode(jsonEncode(out)), expected);

    for (final (table, index) in [
      ('events', 'events_search_trgm'),
      ('issues', 'issues_title_trgm'),
      ('user_stats', 'user_stats_search_trgm'),
      ('device_stats', 'device_stats_search_trgm'),
    ]) {
      final text = switch (table) {
        'events' => sqlEventSearchText(),
        'issues' => 'title',
        'user_stats' => sqlUserStatsSearchText(table),
        _ => sqlDeviceStatsSearchText(table),
      };
      final plan = await db.pool.runTx((tx) async {
        await tx.execute('SET LOCAL enable_seqscan = off');
        final rows = await tx.execute(
          Sql.named('EXPLAIN SELECT 1 FROM $table WHERE ${sqlSearchMatch(text)}'),
          parameters: {'q': 'zzznomatch'},
        );
        return rows.map((r) => r[0]).join('\n');
      });
      expect(plan, contains(index), reason: '$table search must use $index');
    }
  });

  test('search queries run under a statement timeout that maps to SearchTimeoutException', () async {
    expect(await db.search('abc', (s) async => (await s.execute('SHOW statement_timeout')).first[0]), '5s');
    await expectLater(
      db.search('abc', (s) async {
        await s.execute("SET LOCAL statement_timeout = '50ms'");
        return s.execute('SELECT pg_sleep(1)');
      }),
      throwsA(isA<SearchTimeoutException>()),
    );
  });
}
