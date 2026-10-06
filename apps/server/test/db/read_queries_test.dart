@Tags(['db'])
library;

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/store/analytics_store.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:scout_server/util/dates.dart';
import 'package:test/test.dart';

import 'test_db.dart';

/// Smoke-runs dashboard read queries against real Postgres so SQL/column
/// mistakes in shared fragments (event_filters.dart) fail here, not in prod.
Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);
  final analytics = AnalyticsStore(db);
  const pid = 'p';
  final now = DateTime.now().toUtc();

  setUpAll(() async {
    await (await db.connect()).execute("INSERT INTO projects (id, name, slug) VALUES ('p', 'p', 'p')");
    IngestEvent event(String type, int minutesAgo, Map<String, dynamic> payload) => IngestEvent(
          type: type,
          timestamp: now.subtract(Duration(minutes: minutesAgo)).toIso8601String(),
          payload: {
            'environment': 'production',
            'release': '1.0.0',
            'user': {'id': 'alice', 'sessionId': 's1'},
            'device': {'installId': 'i1', 'platform': 'ios'},
            'sessionId': 's1',
            ...payload,
          },
        );
    await store.ingestBatch(projectId: pid, keyId: 'k', enrichment: const {}, events: [
      event('session', 30, {'action': 'start'}),
      event('session', 20, {'action': 'heartbeat'}),
      event('error', 15, {'message': 'boom', 'level': 'error'}),
      event('crash', 10, {'message': 'crash'}),
      event('network', 5, {'network': {'statusCode': 500, 'url': 'https://api.x/a', 'method': 'GET'}}),
      event('network', 4, {'network': {'statusCode': 200, 'url': 'https://api.x/b', 'method': 'GET'}}),
      event('log', 3, {'message': 'hi', 'level': 'info', 'screenTrail': ['/a', '/b']}),
    ]);
  });

  final windows = {
    'hour': TimeWindow(since: now.subtract(const Duration(hours: 1)).toIso8601String()),
    '30d': TimeWindow.lastDays(30),
  };

  for (final MapEntry(key: name, value: w) in windows.entries) {
    test('scout store reads ($name)', () async {
      final issues = await store.listIssues(pid, window: w);
      expect(issues, isNotEmpty);
      await store.listIssues(pid, window: w, lite: true);
      await store.listIssues(pid, window: w, q: 'boom', environment: 'production');
      await store.getIssue(pid, issues.first['id'] as String);
      final events = await store.listEvents(pid, window: w);
      for (final view in ['focus', 'grouped']) {
        await store.listEvents(pid, window: w, view: view);
      }
      await store.listEvents(pid, window: w, type: 'network', q: 'api');
      await store.getEvent(pid, ((events['events'] as List).first as Map)['id'] as String);
      await store.eventFilterFacets(pid, window: w);
      await store.projectOverview(pid, window: w);
      await store.geoBreakdown(pid, window: w);
      await store.sdkHealth(pid, window: w);
      await store.listSessionEvents(pid, 's1');
      await store.incidentCounts(pid, minutes: 60);
    });

    test('analytics reads ($name)', () async {
      await analytics.distinctRoutes(pid, window: w);
      await analytics.funnel(pid, ['/a', '/b'], window: w);
      await analytics.releaseComparison(pid, window: w);
      await analytics.listSessions(pid, window: w);
      await analytics.sessionTimeline(pid, 's1');
      await analytics.projectStats(pid, window: w);
      await analytics.dashboardInsights(pid, window: w);
      await analytics.listUsers(pid, window: w);
      await analytics.getUser(pid, 'alice', window: w);
      await analytics.listDevices(pid, window: w);
      await analytics.getDevice(pid, 'i1', window: w);
    });
  }

  test('project rows and maintenance queries', () async {
    await analytics.retention(pid);
    await store.fetchProjectById(pid);
    await store.listProjects(admin: true);
    await store.reclassifyExpectedNetworkEvents(pid);
    expect((await (await db.connect()).execute(Sql('SELECT 1'))).length, 1);
  });
}
