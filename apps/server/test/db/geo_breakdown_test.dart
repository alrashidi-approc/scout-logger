@Tags(['db'])
library;

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/db/backfills.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:scout_server/util/dates.dart';
import 'package:test/test.dart';

import 'test_db.dart';

/// Day+ windows read daily_stats/user_daily_stats; < 24h windows read raw events.
/// The raw result only depends on which events fall in the window, so the same
/// events ingested "just now" (raw path) are the reference for the rollup path.
Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  var n = 0;

  Future<String> newProject() async {
    final id = 'g${n++}';
    await (await db.connect()).execute(
      Sql.named('INSERT INTO projects (id, name, slug) VALUES (@id, @id, @id)'),
      parameters: {'id': id},
    );
    return id;
  }

  IngestEvent event(DateTime at, String? user, Map<String, dynamic> device) => IngestEvent(
        type: 'error',
        timestamp: at.toIso8601String(),
        payload: {
          'message': 'boom',
          'level': 'error',
          if (user != null) 'user': {'id': user},
          'device': {'installId': 'i-${user ?? 'anon'}', ...device},
        },
      );

  const ip = {'country': 'US'};
  const ipDe = {'country': 'DE'};
  const locale = {'localeCountry': 'DE'};
  const sdkLocale = {'country': 'FR', 'countrySource': 'locale'};

  // (day offset, user, device geo)
  final fixture = [
    (-3, 'alice', ip), (-3, 'alice', ip), (-3, 'bob', locale), (-3, null, ip), (-3, 'erin', const <String, dynamic>{}),
    (-2, 'carol', sdkLocale), (-2, null, ipDe), (-2, 'alice', ip), (-2, 'bob', locale), (-2, 'frank', ipDe),
  ];

  Future<void> ingest(String pid, List<IngestEvent> events) =>
      store.ingestBatch(projectId: pid, keyId: 'k', events: events, enrichment: const {});

  Future<List<Map<String, dynamic>>> whole3Days(String pid) => store.geoBreakdown(
        pid,
        window: TimeWindow(
          since: today.subtract(const Duration(days: 3)).toIso8601String(),
          until: today.toIso8601String(),
        ),
      );

  Future<List<Map<String, dynamic>>> rawReference() async {
    final pid = await newProject();
    var i = 0;
    await ingest(pid, [for (final (_, u, d) in fixture) event(now.subtract(Duration(seconds: ++i)), u, d)]);
    final w = TimeWindow(since: now.subtract(const Duration(hours: 1)).toIso8601String());
    expect(preferIdentityRollups(w), isFalse);
    return store.geoBreakdown(pid, window: w);
  }

  test('whole-day windows: rollups match raw events', () async {
    final pid = await newProject();
    var i = 0;
    await ingest(pid, [
      for (final (day, u, d) in fixture) event(today.add(Duration(days: day, hours: 1, seconds: ++i)), u, d),
    ]);
    final expected = await rawReference();
    expect(expected.map((r) => r['country']), containsAll(['US', 'DE', 'FR']));
    expect(expected.firstWhere((r) => r['country'] == 'DE')['localeEvents'], 2);
    expect(await whole3Days(pid), expected);
  });

  test('backfill recounts geo counters from raw events, once', () async {
    final pid = await newProject();
    var i = 0;
    await ingest(pid, [
      for (final (day, u, d) in fixture) event(today.add(Duration(days: day, hours: 2, seconds: ++i)), u, d),
    ]);
    final expected = await whole3Days(pid);
    final conn = await db.connect();
    await conn.execute(Sql.named('UPDATE daily_stats SET geo_locale = 0, geo_ip = 0, geo_profile = 0 WHERE project_id = @pid'),
        parameters: {'pid': pid});
    expect(await whole3Days(pid), isNot(expected));

    await runBackfills(db);
    expect(await whole3Days(pid), expected);
    expect((await conn.execute("SELECT 1 FROM backfills WHERE name = 'daily_stats_geo_sources'")).length, 1);

    await conn.execute(Sql.named('UPDATE daily_stats SET geo_ip = 0 WHERE project_id = @pid'), parameters: {'pid': pid});
    await runBackfills(db);
    expect(await whole3Days(pid), isNot(expected), reason: 'already recorded, not rerun');
  });

  test('approximation: a user who changed country counts under the latest one only', () async {
    final pid = await newProject();
    await ingest(pid, [
      event(today.subtract(const Duration(days: 3)).add(const Duration(hours: 1)), 'dave', ip),
      event(today.subtract(const Duration(days: 2)).add(const Duration(hours: 1)), 'dave', ipDe),
    ]);
    final users = {for (final r in await whole3Days(pid)) r['country']: r['users']};
    // Raw events would report dave under both US and DE.
    expect(users, {'US': 0, 'DE': 1});
  });
}
