@Tags(['db'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:scout_models/scout_models.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:scout_server/util/dates.dart';
import 'package:test/test.dart';

import 'test_db.dart';

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);

  // Golden captured from the pre-D9 query (5 correlated subqueries per issue) on these fixtures.
  test('listIssues output matches the pre-D9 snapshot across windows, search and facets', () async {
    await (await db.connect()).execute("INSERT INTO projects (id, name, slug) VALUES ('s', 's', 's')");
    final now = DateTime.now().toUtc();
    final events = <IngestEvent>[];
    var i = 0;
    for (final (msg, envs, devices, users, days) in [
      ('alpha boom', ['production', 'staging'], ['Pixel 7', 'iPhone 14', 'Pixel 7'], ['u1', 'u2', ''], [0, 3, 10]),
      ('beta crash', ['production'], ['iPhone 14', 'iPhone 14'], ['u3', 'u3'], [0, 40]),
      ('gamma fail', ['staging'], ['Galaxy S22'], ['u4'], [10]),
      ('delta oops', ['production', 'staging'], ['Pixel 7', 'Galaxy S22', 'Galaxy S22', 'Pixel 7'], ['u1', '', 'u5', 'u6'], [1, 2, 5, 40]),
    ]) {
      for (var k = 0; k < days.length; k++) {
        events.add(IngestEvent(
          type: msg.contains('crash') ? 'crash' : 'error',
          timestamp: now.subtract(Duration(days: days[k], minutes: i++)).toIso8601String(),
          payload: {
            'message': msg,
            'level': k.isEven ? 'error' : 'fatal',
            'environment': envs[k % envs.length],
            'device': {'deviceName': devices[k % devices.length], 'appVersion': k.isEven ? '1.0' : '2.0'},
            'user': {if (users[k % users.length].isNotEmpty) 'id': users[k % users.length]},
          },
        ));
      }
    }
    for (final (code, days) in [(500, 0), (503, 2), (500, 20)]) {
      events.add(IngestEvent(
        type: 'network',
        timestamp: now.subtract(Duration(days: days, minutes: i++)).toIso8601String(),
        payload: {'network': {'statusCode': code, 'url': 'https://x.test/api/pay', 'method': 'POST'}, 'level': 'error'},
      ));
    }
    await store.ingestBatch(projectId: 's', keyId: 'k', events: events, enrichment: const {});

    final until = TimeWindow(
      since: now.subtract(const Duration(days: 12)).toIso8601String(),
      until: now.subtract(const Duration(days: 1)).toIso8601String(),
    );
    final out = <String, Object?>{};
    Future<void> snap(String name, Future<List<Map<String, dynamic>>> f) async => out[name] = [
          for (final r in await f) {...r}..remove('id')..remove('fingerprint')..remove('firstSeenAt')..remove('lastSeenAt'),
        ];
    for (final days in [null, 1, 7, 30]) {
      final d = 'd$days';
      await snap('$d all', store.listIssues('s', days: days));
      await snap('$d crash', store.listIssues('s', days: days, type: 'crash'));
      await snap('$d open', store.listIssues('s', days: days, status: 'open'));
      await snap('$d q-title', store.listIssues('s', days: days, q: 'alp'));
      await snap('$d q-user', store.listIssues('s', days: days, q: 'u5'));
      await snap('$d q-device', store.listIssues('s', days: days, q: 'galaxy'));
      await snap('$d q-url', store.listIssues('s', days: days, q: '/api/pay'));
      await snap('$d env', store.listIssues('s', days: days, environment: 'staging'));
      await snap('$d ver', store.listIssues('s', days: days, appVersion: '2.0'));
      await snap('$d device', store.listIssues('s', days: days, deviceName: 'Pixel 7'));
      await snap('$d env+q', store.listIssues('s', days: days, environment: 'production', q: 'oops'));
      await snap('$d limit', store.listIssues('s', days: days, limit: 2));
    }
    await snap('until all', store.listIssues('s', window: until));
    await snap('until env', store.listIssues('s', window: until, environment: 'production'));
    await snap('until device', store.listIssues('s', window: until, deviceName: 'Galaxy S22'));
    expect(jsonDecode(jsonEncode(out)), jsonDecode(File('test/db/fixtures/list_issues_snapshot.json').readAsStringSync()));

    final full = await store.listIssues('s');
    expect(await store.listIssues('s', lite: true), [
      for (final r in full) {...r}..remove('level')..remove('statusCode')..remove('topDevice'),
    ]);
    for (final r in full) {
      final issue = (await store.getIssue('s', r['id'] as String))!;
      expect(issue.keys, unorderedEquals([
        'id', 'projectId', 'fingerprint', 'type', 'title', 'status', 'firstSeenAt', 'lastSeenAt', //
        'eventCount', 'affectedUsers', 'topCountry', 'priority', 'priorityReasons', 'spike', 'spikeAt', 'noiseReason', 'firstRelease', 'summary', 'likelyCause', 'culprit', 'autoStatusReason', 'autoStatusAt', 'suspects', 'regressedAt', 'suggestedAssignee', 'suggestedOwnerPrefix', 'notes', 'events', 'geoBreakdown', 'deviceBreakdown', 'insights',
      ]));
      expect({...issue}..removeWhere((k, _) => !r.containsKey(k)), {...r}..removeWhere((k, _) => !issue.containsKey(k)));
      expect((issue['insights'] as Map)['severity'], r['severity']);
    }
  });
}
