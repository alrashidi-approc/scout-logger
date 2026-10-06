@Tags(['db'])
library;

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/reports/report_service.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:test/test.dart';

import 'test_db.dart';

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);
  var n = 0;

  Future<String> newProject() async {
    final id = 'r${n++}';
    await db.pool.execute(Sql.named('INSERT INTO projects (id, name, slug) VALUES (@id, @id, @id)'), parameters: {'id': id});
    return id;
  }

  IngestEvent error(String message, {String? release, Map<String, dynamic>? diagnosis}) => IngestEvent(
        type: 'error',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        payload: {
          'message': message,
          'level': 'error',
          'environment': 'production',
          if (release != null) 'release': release,
          if (diagnosis != null) 'diagnosis': diagnosis,
        },
      );

  Future<void> ingest(String pid, List<IngestEvent> events) =>
      store.ingestBatch(projectId: pid, keyId: 'k', events: events, enrichment: const {});

  test('first_release, release filter and new-since-latest-release count', () async {
    final pid = await newProject();
    await ingest(pid, [error('old bug', release: '1.0.0')]);
    await db.pool.execute(
      Sql.named("UPDATE issues SET first_seen_at = first_seen_at - interval '3 days' WHERE project_id = @pid"),
      parameters: {'pid': pid},
    );
    await db.pool.execute(
      Sql.named("UPDATE releases SET first_seen_at = first_seen_at - interval '3 days' WHERE project_id = @pid"),
      parameters: {'pid': pid},
    );
    await ingest(pid, [error('new bug', release: '2.0.0'), error('old bug', release: '2.0.0')]);

    final all = await store.listIssues(pid, lite: true);
    expect({for (final i in all) i['title']: i['firstRelease']}, {'old bug': '1.0.0', 'new bug': '2.0.0'});
    for (final lite in [true, false]) {
      expect((await store.listIssues(pid, lite: lite, firstRelease: '2.0.0')).map((i) => i['title']), ['new bug']);
    }

    final overview = await store.projectOverview(pid);
    expect(overview['latestRelease'], '2.0.0');
    expect(overview['newIssuesSinceLatestRelease'], 1);
    expect((await store.projectOverview(await newProject()))['newIssuesSinceLatestRelease'], 0);
  });

  test('summary / likely cause: latest at equal or higher confidence wins', () async {
    final pid = await newProject();
    Future<List<Object?>> brief() async => (await db.pool.execute(
          Sql.named('SELECT summary, likely_cause FROM issues WHERE project_id = @pid'),
          parameters: {'pid': pid},
        ))
            .single;

    await ingest(pid, [error('boom')]);
    expect(await brief(), [null, null]);
    await ingest(pid, [error('boom', diagnosis: {'summary': 'S1', 'likelyCause': 'C1'})]);
    expect(await brief(), ['S1', 'C1']);
    await ingest(pid, [error('boom', diagnosis: {'summary': 'S2', 'likelyCause': 'C2', 'confidence': 'low'})]);
    expect(await brief(), ['S1', 'C1']);
    await ingest(pid, [error('boom', diagnosis: {'summary': 'S3', 'confidence': 'high'}), error('boom')]);
    expect(await brief(), ['S3', null]);
    await ingest(pid, [error('boom', diagnosis: {'summary': 'S4', 'likelyCause': 'C4', 'confidence': 'high'})]);

    final issue = (await store.listIssues(pid, lite: true)).single;
    expect([issue['summary'], issue['likelyCause']], ['S4', 'C4']);

    final digest = await store.digestData(pid, hours: 1);
    expect(digest.issues.single['likelyCause'], 'C4');
    expect(ReportService.balancedTopIssues(digest.issues).single.cells.first, 'S4 — likely cause: C4');
  });
}
