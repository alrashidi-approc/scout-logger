@Tags(['db'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'test_db.dart';

// The inline JSONB expressions reads used before switching to the generated
// columns (migrations 014 + 023); kept here to prove they are equivalent.
const _inlineHeartbeat = "(type = 'session' AND COALESCE(payload->>'action', '') = 'heartbeat')";
const _inlineError = '''
(
  type IN ('error', 'crash')
  OR (
    type = 'network'
    AND LOWER(COALESCE(NULLIF(payload->>'level', ''), 'error')) NOT IN ('info', 'success')
    AND COALESCE(NULLIF(payload->'network'->'readable'->>'operationalError', ''), 'true') <> 'false'
    AND COALESCE(NULLIF(payload->'network'->'readable'->>'faultKind', ''), '') <> 'expected'
    AND (
      NULLIF(payload->'network'->>'error', '') IS NOT NULL
      OR NULLIF(payload->'network'->>'statusCode', '') IS NULL
      OR NOT ((payload->'network'->>'statusCode') ~ '^[0-9]{1,9}\$' AND (payload->'network'->>'statusCode')::int < 400)
    )
  )
)''';
const _inlineSuccess = '''
(
  LOWER(COALESCE(NULLIF(payload->>'level', ''), '')) = 'success'
  OR (
    type = 'network'
    AND LOWER(COALESCE(NULLIF(payload->>'level', ''), '')) IN ('info', 'success')
  )
  OR (
    type = 'network'
    AND NULLIF(payload->'network'->>'error', '') IS NULL
    AND (payload->'network'->>'statusCode') ~ '^[0-9]{1,9}\$'
    AND (payload->'network'->>'statusCode')::int < 400
  )
)''';

Map<String, dynamic> _net(Object? status, {Object? error, Map<String, dynamic>? readable, String? level}) => {
      if (level != null) 'level': level,
      'network': {
        if (status != null) 'statusCode': status,
        if (error != null) 'error': error,
        if (readable != null) 'readable': readable,
      },
    };

final _fixtures = <(String, Map<String, dynamic>)>[
  ('error', {}),
  ('error', {'level': 'info'}),
  ('crash', {'message': 'boom'}),
  ('log', {'level': 'info'}),
  ('log', {'level': 'success'}),
  ('log', {'level': 'SUCCESS'}),
  ('log', {'level': ''}),
  ('log', {}),
  ('span', {'level': 'warning'}),
  ('session', {'action': 'heartbeat'}),
  ('session', {'action': 'start'}),
  ('session', {'action': ''}),
  ('session', {}),
  ('network', {}),
  ('network', {'level': 'debug'}),
  ('network', {'level': 'info'}),
  ('network', {'level': 'success'}),
  ('network', {'network': null}),
  ('network', _net(null)),
  ('network', _net('')),
  ('network', _net(200)),
  ('network', _net('204')),
  ('network', _net(301)),
  ('network', _net(399)),
  ('network', _net(400)),
  ('network', _net(404)),
  ('network', _net(500)),
  ('network', _net(503, level: 'warning')),
  ('network', _net(500, level: 'info')),
  ('network', _net(200, level: 'error')),
  ('network', _net('abc')),
  ('network', _net('9999999999')),
  ('network', _net(null, error: 'timeout')),
  ('network', _net(200, error: 'socket closed')),
  ('network', _net(500, error: '')),
  ('network', _net(500, readable: {'operationalError': false})),
  ('network', _net(500, readable: {'operationalError': true})),
  ('network', _net(500, readable: {'operationalError': 'false'})),
  ('network', _net(401, readable: {'faultKind': 'expected'})),
  ('network', _net(401, readable: {'faultKind': 'client'})),
  ('network', _net(null, error: 'dns', readable: {'issueWorthy': false})),
  ('network', _net(404, readable: {'issueWorthy': false, 'faultKind': 'expected', 'operationalError': false})),
];

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();

  test('generated is_heartbeat / is_error / is_success match the inline expressions', () async {
    final conn = await db.connect();
    await conn.execute("INSERT INTO projects (id, name, slug) VALUES ('p', 'p', 'p')");
    for (final (i, (type, payload)) in _fixtures.indexed) {
      await conn.execute(
        Sql.named("INSERT INTO events (id, project_id, type, occurred_at, payload) VALUES (@id, 'p', @type, now(), @payload::jsonb)"),
        parameters: {'id': 'e$i', 'type': type, 'payload': jsonEncode(payload)},
      );
    }
    final rows = await conn.execute('''
      SELECT id, type, payload::text,
             is_heartbeat, $_inlineHeartbeat,
             is_error, $_inlineError,
             is_success, $_inlineSuccess
      FROM events ORDER BY id
    ''');
    final mismatches = [
      for (final r in rows)
        if (r[3] != r[4] || r[5] != r[6] || r[7] != r[8])
          '${r[1]} ${r[2]}: heartbeat ${r[3]}/${r[4]} error ${r[5]}/${r[6]} success ${r[7]}/${r[8]}',
    ];
    expect(rows, hasLength(_fixtures.length));
    expect(mismatches, isEmpty);
  });
}
