@Tags(['db'])
library;

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:scout_server/util/ids.dart';
import 'package:test/test.dart';

import 'test_db.dart';

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);
  const pid = 'similar';

  Future<Result> sql(String q, [Map<String, Object?> params = const {}]) =>
      db.pool.execute(Sql.named(q), parameters: {'pid': pid, ...params});

  IngestEvent error(String message, {String? file, Map<String, dynamic>? context}) => IngestEvent(
        type: 'error',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        payload: {
          'message': message,
          'level': 'error',
          'environment': 'production',
          if (file != null) 'stack': '#0 f (package:app/$file:1:1)',
          if (context != null) 'context': context,
        },
      );

  IngestEvent network(String method, String url) => IngestEvent(
        type: 'network',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        payload: {
          'environment': 'production',
          'network': {'method': method, 'url': url, 'statusCode': 500},
        },
      );

  late Map<String, String> ids;

  setUpAll(() async {
    await sql('INSERT INTO projects (id, name, slug) VALUES (@pid, @pid, @pid)');
    await sql('''
      INSERT INTO issues (id, project_id, fingerprint, type, title, first_seen_at, last_seen_at, event_count)
      VALUES ('v1-boom', @pid, @fp, 'error', 'boom', now() - interval '1 day', now() - interval '1 day', 4)''',
        {'fp': legacyFingerprint('error', error('boom', file: 'cart.dart').payload)});
    const ctx = {'failure_layer': 'app_check', 'platform_code': 'HTTP_503'};
    await store.ingestBatch(projectId: pid, keyId: 'k', enrichment: const {}, events: [
      error('boom', file: 'cart.dart'),
      error('other cart failure', file: 'cart.dart'),
      error('token timeout after 3s', file: 'a.dart', context: ctx),
      error('token timeout after 9s', file: 'b.dart', context: ctx),
      error('unrelated', file: 'home.dart'),
      network('GET', 'https://x.io/api/pay/1'),
      network('POST', 'https://x.io/api/pay/2'),
    ]);
    ids = {for (final r in await sql('SELECT title, id FROM issues WHERE project_id = @pid')) r[0] as String: r[1] as String};
  });

  Future<Map<String, Object?>> similar(String title) async => {
        for (final i in (await store.similarIssues(pid, ids[title]!))!) i['title'] as String: i['similarBecause'],
      };

  test('lineage, culprit file, route and group hint', () async {
    expect(await similar('cart.dart: boom'), {
      'boom': ['predecessor'],
      'cart.dart: other cart failure': ['same_culprit'],
    });
    expect(await similar('boom'), {'cart.dart: boom': ['successor']});
    expect(await similar('a.dart: token timeout after <num>s'), {'b.dart: token timeout after <num>s': ['same_group_hint']});
    expect(await similar('GET /api/pay/:id · Server error'), {'POST /api/pay/:id · Server error': ['same_route']});
    expect(await similar('home.dart: unrelated'), isEmpty);
  });

  test('v1 / v2 marker, lite issue shape, missing issue', () async {
    final lineage = (await store.similarIssues(pid, ids['cart.dart: boom']!))!.first;
    expect(lineage['fingerprintVersion'], 1);
    expect(lineage['id'], 'v1-boom');
    expect(lineage.keys, containsAll(['status', 'eventCount', 'lastSeenAt', 'priority', 'culprit']));
    expect(await store.similarIssues(pid, 'nope'), isNull);
  });
}
