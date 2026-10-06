@Tags(['db'])
library;

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:scout_server/util/dates.dart';
import 'package:test/test.dart';

import 'test_db.dart';

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);
  var n = 0;

  Future<String> newProject() async {
    final id = 'p${n++}';
    await (await db.connect()).execute(
      Sql.named('INSERT INTO projects (id, name, slug) VALUES (@id, @id, @id)'),
      parameters: {'id': id},
    );
    return id;
  }

  Future<int> count(String sql, String pid) async =>
      (await (await db.connect()).execute(Sql.named(sql), parameters: {'pid': pid})).first[0] as int;

  IngestEvent error(String message) => IngestEvent(
        type: 'error',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        payload: {'message': message, 'level': 'error', 'environment': 'production'},
      );

  Future<Map<String, dynamic>> ingest(String pid, List<IngestEvent> events) =>
      store.ingestBatch(projectId: pid, keyId: 'k', events: events, enrichment: const {});

  test('concurrent batches with the same fingerprint create one issue', () async {
    final pid = await newProject();
    await Future.wait([for (var i = 0; i < 8; i++) ingest(pid, [error('boom')])]);
    expect(await count('SELECT count(*)::int FROM issues WHERE project_id = @pid', pid), 1);
    expect(await count('SELECT event_count FROM issues WHERE project_id = @pid', pid), 8);
    expect(await count('SELECT count(*)::int FROM events WHERE project_id = @pid', pid), 8);
  });

  test('resolved issue reopens as a regression', () async {
    final pid = await newProject();
    await ingest(pid, [error('again')]);
    await (await db.connect()).execute(Sql.named("UPDATE issues SET status = 'resolved' WHERE project_id = @pid"), parameters: {'pid': pid});
    await ingest(pid, [error('again')]);
    expect(await count("SELECT count(*)::int FROM issues WHERE project_id = @pid AND status = 'open' AND regressed_at IS NOT NULL", pid), 1);
  });

  test('poison event is rejected without failing or duplicating the batch', () async {
    final pid = await newProject();
    final result = await ingest(pid, [error('ok 1'), error('bad \u0000 byte'), error('ok 2')]);
    expect(result, {'accepted': 2, 'total': 3, 'rejected': 1});
    expect(await count('SELECT count(*)::int FROM events WHERE project_id = @pid', pid), 2);
    expect(await count('SELECT sum(event_count)::int FROM issues WHERE project_id = @pid', pid), 2);
    expect(await count('SELECT sum(events_total)::int FROM daily_stats WHERE project_id = @pid', pid), 2);
  });

  test('concurrent same-project batches all commit', () async {
    final pid = await newProject();
    final results = await Future.wait([
      for (var i = 0; i < 6; i++) ingest(pid, i.isEven ? [error('x'), error('y')] : [error('y'), error('x')]),
    ]);
    expect(results.map((r) => r['rejected']), everyElement(0));
    expect(await count('SELECT count(*)::int FROM events WHERE project_id = @pid', pid), 12);
    expect(await count('SELECT sum(event_count)::int FROM issues WHERE project_id = @pid', pid), 12);
  });

  test('batched rollups equal the sum of single-event ingests', () async {
    final base = DateTime.now().toUtc().subtract(const Duration(hours: 2));
    IngestEvent event(String type, int minute, Map<String, dynamic> extra) => IngestEvent(
          type: type,
          timestamp: base.add(Duration(minutes: minute)).toIso8601String(),
          payload: {'level': 'error', 'environment': 'production', 'release': '1.0.$minute', ...extra},
        );
    final alice = {'id': 'alice', 'email': 'a@x.io'};
    final events = [
      event('error', 5, {'message': 'boom', 'user': alice, 'device': {'installId': 'i1', 'platform': 'ios'}}),
      event('crash', 1, {'message': 'crash', 'user': {'id': 'alice', 'name': 'Alice'}, 'device': {'installId': 'i1'}}),
      event('error', 3, {'message': 'boom', 'user': {'id': 'bob'}, 'device': {'installId': 'i2', 'platform': 'android'}}),
      event('log', 4, {'message': 'hello', 'level': 'info', 'device': {'installId': 'i2'}}),
      event('error', 2, {'message': 'boom', 'user': alice, 'device': {'installId': 'i1', 'appVersion': '2.0'}}),
    ];
    final batched = await newProject();
    final single = await newProject();
    await ingest(batched, events);
    for (final e in events) {
      await ingest(single, [e]);
    }

    Future<String> snapshot(String table, String pid) async => (await (await db.connect()).execute(
          Sql.named('''
            SELECT COALESCE(jsonb_agg(j ORDER BY j::text), '[]')::text
            FROM (SELECT to_jsonb(t) - 'id' - 'project_id' - 'created_at' - 'updated_at' AS j FROM $table t WHERE project_id = @pid) s
          '''),
          parameters: {'pid': pid},
        ))
            .first[0] as String;
    for (final table in [
      'issues',
      'daily_stats',
      'releases',
      'user_first_seen',
      'user_stats',
      'user_daily_stats',
      'device_stats',
      'device_daily_stats',
      'user_device_links',
    ]) {
      expect(await snapshot(table, batched), await snapshot(table, single), reason: table);
    }
    expect(await count('SELECT count(*)::int FROM events WHERE project_id = @pid', batched), events.length);
    expect(await count('SELECT sum(event_count)::int FROM issues WHERE project_id = @pid', batched), 4);
  });

  test('project eventCount (daily_stats) equals the non-heartbeat event COUNT, and survives raw-event retention', () async {
    final pid = await newProject();
    final now = DateTime.now().toUtc();
    IngestEvent at(String type, int daysAgo, Map<String, dynamic> payload) => IngestEvent(
          type: type,
          timestamp: now.subtract(Duration(days: daysAgo)).toIso8601String(),
          payload: payload,
        );
    await ingest(pid, [
      at('error', 0, {'message': 'a'}),
      at('log', 1, {'level': 'info', 'message': 'b'}),
      at('session', 2, {'action': 'start', 'sessionId': 's'}),
      at('session', 2, {'action': 'heartbeat', 'sessionId': 's'}),
      at('network', 40, {'network': {'statusCode': 500}}),
      at('not_a_type', 0, {}),
    ]);
    final oldCount = await count('SELECT count(*)::int FROM events WHERE project_id = @pid AND NOT is_heartbeat', pid);
    expect(oldCount, 4);
    expect((await store.fetchProjectById(pid))!['eventCount'], oldCount);

    // Retention deletes raw events but keeps daily_stats: the total stays all-time.
    await (await db.connect()).execute(
      Sql.named("DELETE FROM events WHERE project_id = @pid AND occurred_at < now() - interval '30 days'"),
      parameters: {'pid': pid},
    );
    expect((await store.fetchProjectById(pid))!['eventCount'], 4);
  });

  group('purgeProjectData', () {
    final window = TimeWindow(since: DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String());

    test('returns affected row counts', () async {
      final pid = await newProject();
      await ingest(pid, [error('a'), error('b')]);
      final deleted = await store.purgeProjectData(pid, window: window);
      expect(deleted['deletedEvents'], 2);
      expect(deleted['deletedIssues'], 2);
      expect(await count('SELECT count(*)::int FROM events WHERE project_id = @pid', pid), 0);
    });

    test('rolls back everything when a late statement fails', () async {
      final pid = await newProject();
      await ingest(pid, [error('kept')]);
      final pool = await db.connect();
      await pool.execute(r"CREATE FUNCTION fail_purge() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'boom'; END$$");
      await pool.execute('CREATE TRIGGER fail_purge BEFORE DELETE ON releases FOR EACH STATEMENT EXECUTE FUNCTION fail_purge()');
      addTearDown(() => pool.execute('DROP TRIGGER fail_purge ON releases'));

      await expectLater(store.purgeProjectData(pid, window: window), throwsA(isA<ServerException>()));
      expect(await count('SELECT count(*)::int FROM events WHERE project_id = @pid', pid), 1);
      expect(await count('SELECT count(*)::int FROM issues WHERE project_id = @pid', pid), 1);
      expect(
        (await pool.execute("SELECT count(*)::int FROM pg_stat_activity WHERE datname = current_database() AND state LIKE 'idle in transaction%'")).first[0],
        0,
      );
    });
  });

  group('pools', () {
    test('dashboard and ingest pools set their statement_timeout', () async {
      expect((await db.pool.execute('SHOW statement_timeout')).first[0], '30s');
      expect((await db.ingest.execute('SHOW statement_timeout')).first[0], '10s');
      expect((await db.pool.execute('SHOW idle_in_transaction_session_timeout')).first[0], '1min');
    });

    test('statement_timeout cancels a slow query', () async {
      final slow = db.pool.runTx((tx) async {
        await tx.execute("SET LOCAL statement_timeout = '100ms'");
        await tx.execute('SELECT pg_sleep(2)');
      });
      await expectLater(slow, throwsA(isA<ServerException>().having((e) => e.code, 'code', '57014')));
    });
  });
}
