@Tags(['db'])
library;

import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/db/backfills.dart';
import 'package:scout_server/notifications/notification_service.dart';
import 'package:scout_server/store/platform_store.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:scout_server/util/dates.dart';
import 'package:scout_server/util/ids.dart';
import 'package:test/test.dart';

import 'test_db.dart';

class _FakeNotifications implements NotificationService {
  final sent = <String>[];
  final gate = Completer<void>();

  @override
  PlatformStore get platformStore => _FakePlatformStore();

  @override
  Future<void> onEventIngested({
    required String projectId,
    required String projectName,
    required String eventId,
    required String? issueId,
    String? alertIssueId,
    required String type,
    required String environment,
    required String? message,
    required Map<String, dynamic> payload,
    required String? fingerprint,
    bool regression = false,
    required ProjectNotificationConfig notifications,
    required PlatformNotificationPolicy platform,
  }) async {
    await gate.future;
    if (message == 'bad') throw StateError('send failed');
    sent.add('$projectName:$message${alertIssueId == null ? '' : '@$alertIssueId'}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlatformStore implements PlatformStore {
  @override
  Future<PlatformNotificationPolicy> getNotificationPolicy() async => const PlatformNotificationPolicy();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
    expect(result, {'accepted': 2, 'total': 3, 'rejected': 1, 'configVersion': 1});
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

  test('project eventCount equals the stored non-heartbeat event COUNT, before and after retention', () async {
    final pid = await newProject();
    final now = DateTime.now().toUtc();
    IngestEvent at(String type, Duration ago, Map<String, dynamic> payload) =>
        IngestEvent(type: type, timestamp: now.subtract(ago).toIso8601String(), payload: payload);
    const day = Duration(days: 1);
    const hour = Duration(hours: 1);
    await ingest(pid, [
      at('error', Duration.zero, {'message': 'a'}),
      at('log', day, {'level': 'info', 'message': 'b'}),
      at('session', day * 2, {'action': 'start', 'sessionId': 's'}),
      at('session', day * 2, {'action': 'heartbeat', 'sessionId': 's'}),
      at('log', day * 30 - hour, {'level': 'info', 'message': 'kept routine'}),
      at('log', day * 30 + hour, {'level': 'info', 'message': 'expired routine'}),
      at('network', day * 40, {'network': {'statusCode': 500}}),
      at('error', day * 100, {'message': 'expired error'}),
      at('not_a_type', Duration.zero, {}),
    ]);
    Future<void> expectStoredCount(int expected) async {
      expect(await count('SELECT count(*)::int FROM events WHERE project_id = @pid AND NOT is_heartbeat', pid), expected);
      expect((await store.fetchProjectById(pid))!['eventCount'], expected);
      final listed = await store.listProjects(admin: true);
      expect(listed.firstWhere((p) => p['id'] == pid)['eventCount'], expected);
    }

    await expectStoredCount(7);
    expect(await store.purgeExpiredEvents(pid, retention: const ProjectRetentionConfig()), 2);
    await expectStoredCount(5);
  });

  test('issue correlations and the event detail issue summary', () async {
    final pid = await newProject();
    await ingest(pid, [for (var i = 0; i < 5; i++) error('corr')]);
    await (await db.connect()).execute(
      Sql.named('''
        UPDATE events e SET
          app_version = CASE WHEN r.n <= 4 THEN '1.0' ELSE '2.0' END,
          platform = CASE WHEN r.n <= 2 THEN 'ios' WHEN r.n <= 4 THEN 'android' ELSE 'web' END,
          country = NULL,
          environment = 'production'
        FROM (SELECT id, row_number() OVER (ORDER BY id) AS n FROM events WHERE project_id = @pid) r
        WHERE e.id = r.id
      '''),
      parameters: {'pid': pid},
    );
    final issueId = (await (await db.connect()).execute(
      Sql.named('SELECT id FROM issues WHERE project_id = @pid'),
      parameters: {'pid': pid},
    ))
        .first[0] as String;
    final issue = (await store.getIssue(pid, issueId))!;
    expect((issue['insights'] as Map)['correlations'], [
      {'label': 'App version', 'value': '1.0', 'ratio': 0.8, 'count': 4},
      {'label': 'Environment', 'value': 'production', 'ratio': 1.0, 'count': 5},
    ]);

    final event = (await store.getEvent(pid, (issue['events'] as List).first['id'] as String))!;
    expect(event['issue'], {
      for (final k in ['id', 'title', 'type', 'status', 'eventCount', 'fingerprint', 'firstSeenAt', 'lastSeenAt']) k: issue[k],
    });
  });

  test('a v2 issue replacing a recently active v1 issue does not alert on creation, then dedups as it', () async {
    final pid = await newProject();
    final notifications = _FakeNotifications()..gate.complete();
    final store = ScoutStore(db, notifications: notifications);
    for (final (id, msg, days) in [('v1-boom', 'boom', 1), ('v1-old', 'old', 20)]) {
      await (await db.connect()).execute(
        Sql.named('''
          INSERT INTO issues (id, project_id, fingerprint, type, title, first_seen_at, last_seen_at, event_count)
          VALUES (@id, @pid, @fp, 'error', @msg, now() - make_interval(days => @d), now() - make_interval(days => @d), 3)
        '''),
        parameters: {'id': id, 'pid': pid, 'fp': legacyFingerprint('error', error(msg).payload), 'msg': msg, 'd': days},
      );
    }
    Future<void> send(List<String> messages) async {
      await store.ingestBatch(projectId: pid, keyId: 'k', events: [for (final m in messages) error(m)], enrichment: const {});
      await store.lastNotifications;
    }

    await send(['boom', 'old', 'fresh']);
    expect(notifications.sent, ['$pid:old', '$pid:fresh']);
    await send(['boom']);
    expect(notifications.sent.last, '$pid:boom@v1-boom');
    final links = await (await db.connect()).execute(
      Sql.named("SELECT title, predecessor_id FROM issues WHERE project_id = @pid AND fingerprint LIKE 'v2:%' ORDER BY title"),
      parameters: {'pid': pid},
    );
    expect(links.map((r) => r.toList()), [['boom', 'v1-boom'], ['fresh', null], ['old', null]]);
  });

  test('notifications are sent after the response, in order, errors logged', () async {
    final pid = await newProject();
    final notifications = _FakeNotifications();
    final store = ScoutStore(db, notifications: notifications);
    final result = await store.ingestBatch(
      projectId: pid,
      keyId: 'k',
      events: [error('first'), error('bad'), error('third')],
      enrichment: const {},
    );
    expect(result['accepted'], 3);
    expect(notifications.sent, isEmpty, reason: 'ingest returned before any send finished');
    notifications.gate.complete();
    await store.lastNotifications;
    expect(notifications.sent, ['$pid:first', '$pid:third']);
  });

  test('settings save reclassifies expected network events in the background', () async {
    final pid = await newProject();
    IngestEvent call(String path) => IngestEvent(
          type: 'network',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          payload: {
            'environment': 'production',
            'network': {'method': 'GET', 'url': 'https://api.example.com$path', 'statusCode': 404},
          },
        );
    await ingest(pid, [call('/a'), call('/b')]);
    const open = "SELECT count(*)::int FROM issues WHERE project_id = @pid AND type = 'network' AND status = 'open'";
    expect(await count(open, pid), 2);

    Map<String, dynamic> rule(String path) => {
          'sdk': {
            'expectedNetworkResponses': [
              {'method': 'GET', 'path': path, 'statusCodes': [404]},
            ],
          },
        };
    // Back-to-back saves: the second lands while the first run may be in flight and must not be lost.
    final saved = await store.updateProjectSettings(pid, rule('/a'));
    await store.updateProjectSettings(pid, rule('/b'));
    expect(saved.containsKey('reclassified'), isFalse);
    await store.lastReclassify;
    expect(await count(open, pid), 0);
    expect(await count("SELECT count(*)::int FROM events WHERE project_id = @pid AND type = 'network' AND issue_id IS NULL", pid), 2);
  });

  test('affected_users counts new identified users across batches; backfill fixes stale values', () async {
    final pid = await newProject();
    IngestEvent by(String? user) => IngestEvent(
          type: 'error',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          payload: {
            'message': 'same issue',
            'level': 'error',
            if (user != null) 'user': {'id': user},
            'device': {'installId': 'i-${user ?? 'anon'}'},
          },
        );
    const affected = 'SELECT affected_users FROM issues WHERE project_id = @pid';
    await ingest(pid, [by('alice'), by('bob'), by(null), by('alice')]);
    expect(await count(affected, pid), 2);
    await ingest(pid, [by('alice'), by('carol'), by('carol'), by(null)]);
    expect(await count(affected, pid), 3);
    await ingest(pid, [by('bob')]);
    expect(await count(affected, pid), 3);

    await (await db.connect()).execute(Sql.named('UPDATE issues SET affected_users = 1 WHERE project_id = @pid'),
        parameters: {'pid': pid});
    await runBackfills(db);
    expect(await count(affected, pid), 3);
  });

  test('a diagnosis title replaces a heuristic one and is not downgraded', () async {
    final pid = await newProject();
    IngestEvent ev(Map<String, dynamic> diagnosis, {String message = 'Token 12 failed'}) => IngestEvent(
          type: 'error',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          payload: {'message': message, 'level': 'error', 'diagnosis': diagnosis},
        );
    Future<String> title() async => (await (await db.connect())
            .execute(Sql.named('SELECT title FROM issues WHERE project_id = @pid'), parameters: {'pid': pid}))
        .single[0] as String;

    await ingest(pid, [ev(const {})]);
    expect(await title(), 'Token 12 failed');
    await ingest(pid, [ev({'summary': 'App Check token missing', 'confidence': 'medium'}, message: 'Token 13 failed')]);
    expect(await title(), 'App Check token missing');
    await ingest(pid, [ev(const {}, message: 'Token 14 failed'), ev({'summary': 'Weak guess', 'confidence': 'low'})]);
    expect(await title(), 'App Check token missing');
    await ingest(pid, [ev({'summary': 'Debug token not registered', 'confidence': 'high'})]);
    expect(await title(), 'Debug token not registered');
  });

  test('a heartbeat does not revive a stale session between sweeps', () async {
    final pid = await newProject();
    await ingest(pid, [error('sweeps now')]);
    final pool = await db.connect();
    await pool.execute(
      Sql.named("INSERT INTO app_sessions (id, project_id, started_at, last_seen_at) VALUES ('s1', @pid, now() - interval '20 minutes', now() - interval '10 minutes')"),
      parameters: {'pid': pid},
    );
    await ingest(pid, [
      IngestEvent(type: 'session', timestamp: DateTime.now().toUtc().toIso8601String(), payload: {'action': 'heartbeat', 'sessionId': 's1'}),
    ]);
    const stale = "SELECT count(*)::int FROM app_sessions WHERE project_id = @pid AND last_seen_at < now() - interval '9 minutes'";
    expect(await count('$stale AND ended_at IS NULL', pid), 1, reason: 'sweep throttled, heartbeat ignored');
    await store.closeStaleSessions(projectId: pid);
    expect(await count('$stale AND ended_at = last_seen_at', pid), 1);
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
