@Tags(['db'])
library;

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:test/test.dart';

import 'test_db.dart';

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);
  const pid = 'signals';

  Future<Result> sql(String q, [Map<String, Object?> params = const {}]) =>
      db.pool.execute(Sql.named(q), parameters: {'pid': pid, ...params});

  IngestEvent error(String message, {String user = 'u1', bool sim = false}) => IngestEvent(
        type: 'error',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        payload: {
          'message': message,
          'level': 'error',
          'environment': 'production',
          'user': {'id': user},
          'device': {'installId': 'd-$user', 'isSimulator': sim},
        },
      );

  Future<void> ingest(List<IngestEvent> events) =>
      store.ingestBatch(projectId: pid, keyId: 'k', events: events, enrichment: const {});

  Future<void> age(String title, Duration by) => sql('''
        WITH i AS (
          UPDATE issues SET first_seen_at = first_seen_at - @by::interval, last_seen_at = last_seen_at - @by::interval
          WHERE project_id = @pid AND title = @t RETURNING id
        ) UPDATE events SET occurred_at = occurred_at - @by::interval WHERE issue_id IN (SELECT id FROM i)''',
      {'t': title, 'by': '${by.inHours} hours'});

  Future<Map<String, List<Object?>>> signals() async => {
        for (final r in await sql('SELECT title, priority, priority_reasons, spike, spike_at, noise_reason FROM issues WHERE project_id = @pid'))
          r[0] as String: r.sublist(1),
      };

  setUpAll(() async {
    await sql('INSERT INTO projects (id, name, slug) VALUES (@pid, @pid, @pid)');
    await sql('''
      INSERT INTO releases (project_id, release, environment, first_seen_at, last_seen_at, event_count, crash_count)
      VALUES (@pid, '2.0.0', 'production', now() - interval '2 days', now(), 0, 0)''');
    await ingest([
      for (var i = 0; i < 12; i++) error('spiky', user: 'u$i'),
      error('lonely'),
      for (var i = 0; i < 3; i++) error('mine'),
      error('sim', user: 'a', sim: true),
      error('sim', user: 'b', sim: true),
      error('auth', user: 'a'),
      error('auth', user: 'b'),
      error('old', user: 'a'),
      error('old', user: 'b'),
    ]);
    await age('lonely', const Duration(days: 2));
    await age('old', const Duration(days: 20));
    await sql('''
      UPDATE events SET payload = payload || '{"network": {"readable": {"faultClass": "auth"}}}'
      WHERE issue_id = (SELECT id FROM issues WHERE project_id = @pid AND title = 'auth')''');
  });

  test('refresh tags spikes, priority reasons and every noise reason', () async {
    expect(await store.refreshIssueSignals(), 6);
    final s = await signals();

    final spiky = s['spiky']!;
    expect(spiky[0], 2 + 2 + 3 + 1);
    expect(spiky[1], ['12 users affected', contains('rising'), 'new in 2.0.0', 'spike: 12 events in the last hour']);
    expect(spiky[2], isTrue);
    expect(spiky[3], isNotNull);
    expect(spiky[4], isNull);

    expect({for (final e in s.entries) e.key: e.value[4]}, {
      'spiky': null,
      'lonely': 'single_occurrence',
      'mine': 'single_user',
      'sim': 'simulator_only',
      'auth': 'auth_class',
      'old': 'stale',
    });
  });

  test('a second refresh changes nothing and keeps spike_at', () async {
    final before = (await signals())['spiky']![3];
    expect(await store.refreshIssueSignals(), 0);
    expect((await signals())['spiky']![3], before);
  });

  test('listIssues returns the signals, hides noise and sorts by priority on request', () async {
    final all = await store.listIssues(pid, lite: true);
    expect(all, hasLength(6));
    final spiky = all.firstWhere((i) => i['title'] == 'spiky');
    expect(spiky['priority'], 8);
    expect(spiky['priorityReasons'], hasLength(4));
    expect(spiky['spike'], isTrue);
    expect(spiky['spikeAt'], isA<String>());
    expect(spiky['noiseReason'], isNull);
    expect(all.firstWhere((i) => i['title'] == 'old')['noiseReason'], 'stale');

    for (final lite in [true, false]) {
      expect((await store.listIssues(pid, lite: lite, hideNoise: true)).map((i) => i['title']), ['spiky']);
      expect((await store.listIssues(pid, lite: lite, byPriority: true)).first['title'], 'spiky');
    }
  });

  test('suspects: dominant (>= 60%) known values over the 8-day window', () async {
    IngestEvent on(String platform, String user) =>
        error('suspect', user: user)..payload['device'] = {'platform': platform, 'installId': 'd-$user'};
    await ingest([on('ios', 'a'), on('ios', 'b'), on('android', 'c')]);
    await store.refreshIssueSignals();
    final issue = (await store.listIssues(pid, lite: true)).firstWhere((i) => i['title'] == 'suspect');
    expect(issue['suspects'], [
      {'dimension': 'environment', 'value': 'production', 'share': 1.0},
      {'dimension': 'platform', 'value': 'ios', 'share': 0.667},
    ]);
    expect((await store.listIssues(pid))[0].containsKey('suspects'), isTrue);
  });

  test('spike clears once the hour calms down', () async {
    await age('spiky', const Duration(hours: 2));
    await store.refreshIssueSignals();
    final spiky = (await signals())['spiky']!;
    expect(spiky[2], isFalse);
    expect(spiky[1], isNot(contains(startsWith('spike'))));
  });
}
