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
  const pid = 'rules';

  Future<Result> sql(String q, [Map<String, Object?> params = const {}]) =>
      db.pool.execute(Sql.named(q), parameters: {'pid': pid, ...params});

  IngestEvent error(String message, {String? stack}) => IngestEvent(
        type: 'error',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        payload: {'message': message, 'level': 'error', 'environment': 'production', if (stack != null) 'stack': stack},
      );

  Future<Map<String, List<Object?>>> issues() async => {
        for (final r in await sql('SELECT title, status, auto_status_reason, culprit FROM issues WHERE project_id = @pid'))
          r[0] as String: r.sublist(1),
      };

  setUpAll(() async {
    await sql('INSERT INTO projects (id, name, slug) VALUES (@pid, @pid, @pid)');
    await store.ingestBatch(
      projectId: pid,
      keyId: 'k',
      enrichment: const {},
      events: [
        error('quiet one'),
        error('SocketException: reset'),
        error('legacy', stack: '#0 Cart.add (package:app/legacy/cart.dart:3:4)'),
        error('keep', stack: '#0 Home.build (package:app/home.dart:9:1)'),
      ],
    );
    await sql('''
      WITH i AS (
        UPDATE issues SET first_seen_at = now() - interval '10 days', last_seen_at = now() - interval '10 days'
        WHERE project_id = @pid AND title = 'quiet one' RETURNING id
      ) UPDATE events SET occurred_at = now() - interval '10 days' WHERE issue_id IN (SELECT id FROM i)''');
  });

  test('settings PATCH validates and stores issueRules', () async {
    await expectLater(
      store.updateProjectSettings(pid, {'issueRules': {'ignoreMessageRegexes': ['(bad']}}),
      throwsFormatException,
    );
    await expectLater(store.updateProjectSettings(pid, {'issueRules': 'x'}), throwsFormatException);
    final saved = await store.updateProjectSettings(pid, {
      'issueRules': {
        'autoResolveQuietDays': 7,
        'ignoreMessageRegexes': ['^socketexception'],
        'ignoreCulpritPrefixes': ['package:app/legacy/'],
      },
    });
    expect(saved['issueRules'], (await store.getProjectSettings(pid))['issueRules']);
    expect((saved['issueRules'] as Map)['autoResolveQuietDays'], 7);
    await store.updateProjectSettings(pid, {'retention': <String, dynamic>{}});
    expect(((await store.getProjectSettings(pid))['issueRules'] as Map)['ignoreCulpritPrefixes'], ['package:app/legacy/']);
  });

  test('the signals job resolves quiet issues and ignores matches, once', () async {
    await store.refreshIssueSignals();
    expect(await issues(), {
      'quiet one': ['resolved', 'resolved: quiet for 7 days', null],
      'SocketException: reset': ['ignored', 'ignored: message matches /^socketexception/', null],
      'cart.dart: legacy': ['ignored', 'ignored: culprit under package:app/legacy/', 'package:app/legacy/cart.dart'],
      'home.dart: keep': ['open', null, 'package:app/home.dart'],
    });
    final listed = (await store.listIssues(pid, lite: true)).firstWhere((i) => i['title'] == 'quiet one');
    expect(listed['autoStatusReason'], 'resolved: quiet for 7 days');
    expect(listed['autoStatusAt'], isA<String>());

    await sql("UPDATE issues SET status = 'open', resolved_at = NULL WHERE project_id = @pid");
    await store.refreshIssueSignals();
    expect((await issues()).values.map((v) => v[0]), everyElement('open'), reason: 'manual reopen sticks');
  });

  test('issue detail suggests the owner with the longest matching culprit prefix', () async {
    await store.updateProjectSettings(pid, {
      'issueRules': {
        'ownerRules': [
          {'prefix': 'package:app/', 'assignee': 'team@x.io'},
          {'prefix': 'package:app/legacy/', 'assignee': 'legacy@x.io'},
        ],
      },
    });
    Future<Map<String, dynamic>> detail(String title) async {
      final id = (await sql('SELECT id FROM issues WHERE project_id = @pid AND title = @t', {'t': title})).single[0] as String;
      return (await store.getIssue(pid, id))!;
    }

    expect([for (final k in ['suggestedAssignee', 'suggestedOwnerPrefix']) (await detail('cart.dart: legacy'))[k]],
        ['legacy@x.io', 'package:app/legacy/']);
    expect((await detail('home.dart: keep'))['suggestedAssignee'], 'team@x.io');
    expect((await detail('quiet one'))['suggestedAssignee'], isNull);
  });
}
