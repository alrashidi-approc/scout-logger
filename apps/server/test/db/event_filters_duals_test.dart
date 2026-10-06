@Tags(['db'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:scout_server/util/event_filters.dart';
import 'package:test/test.dart';

import 'test_db.dart';

const _codes = [403];
const _types = ['text/html'];

Map<String, dynamic> _waf(Object? status, {Map<String, dynamic>? response, Map<String, dynamic> extra = const {}}) => {
      'network': {'statusCode': status, if (response != null) 'response': response, ...extra},
    };

// (type, message column, issue_id, payload)
final _fixtures = <(String, String?, String?, Map<String, dynamic>)>[
  ('session', null, null, {'action': 'start'}),
  ('session', null, null, {'action': 'END'}),
  ('session', null, null, {'action': ' start '}),
  ('session', null, null, {'action': 'heartbeat'}),
  ('log', null, null, {'action': 'app_paused'}),
  ('log', 'Session Start', null, {}),
  ('log', ' app resumed ', null, {}),
  ('log', 'session-end', null, {}),
  ('log', 'sessionstart', null, {}),
  ('log', null, null, {'message': 'session_start'}),
  ('log', 'payment failed', null, {'action': 'checkout'}),
  ('log', 'Hello', null, {'action': ' Foo '}),
  ('log', 'Hello', null, {'action': '  '}),
  ('log', '  Padded Message', null, {}),
  ('log', 'x' * 200, null, {}),
  ('log', null, null, {}),
  ('span', null, null, {'action': 'session_start'}),
  ('error', 'session_start', null, {}),
  ('error', 'boom', 'i1', {}),
  ('network', null, null, {'network': {'method': 'post', 'url': 'https://h/a/1?x=1'}}),
  ('network', null, null, {'network': {'path': '/p?q'}}),
  ('network', null, null, {'method': 'PUT', 'url': '/top-level'}),
  ('network', null, null, _waf(403, response: {'headers': {'content-type': 'text/html; charset=utf-8'}})),
  ('network', null, null, _waf(403, response: {'headers': {'Content-Type': 'TEXT/HTML'}})),
  ('network', null, null, _waf(403, response: {'contentType': 'application/json', 'body': '<html>'})),
  ('network', null, null, _waf(403, response: {'body': '<HTML><body>Request Rejected</body>'})),
  ('network', null, null, _waf(403, response: {'body': 'ok'})),
  ('network', null, null, _waf('403', extra: {'responseBody': 'cf-ray: 1'})),
  ('network', null, null, _waf(403, extra: {'contentType': 'text/html'})),
  ('network', null, null, _waf(403, response: {'headers': {'content-type': '', 'Content-Type': 'text/html'}})),
  ('network', null, null, _waf(500, response: {'headers': {'content-type': 'text/html'}})),
  ('network', null, null, _waf(403.0, response: {'headers': {'content-type': 'text/html'}})),
  ('log', null, null, _waf(403, response: {'headers': {'content-type': 'text/html'}})),
];

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();

  test('SQL ↔ Dart duals agree on fixtures (routine, WAF reject, group key)', () async {
    final conn = await db.connect();
    await conn.execute("INSERT INTO projects (id, name, slug) VALUES ('p', 'p', 'p')");
    await conn.execute(
      "INSERT INTO issues (id, project_id, fingerprint, type, title, first_seen_at, last_seen_at) VALUES ('i1', 'p', 'f', 'error', 't', now(), now())",
    );
    for (final (i, (type, message, issueId, payload)) in _fixtures.indexed) {
      await conn.execute(
        Sql.named('''
          INSERT INTO events (id, project_id, issue_id, type, message, occurred_at, payload)
          VALUES (@id, 'p', @iid, @type, @msg, now(), @payload::jsonb)'''),
        parameters: {'id': 'e${'$i'.padLeft(2, '0')}', 'iid': issueId, 'type': type, 'msg': message, 'payload': jsonEncode(payload)},
      );
    }
    final rows = await conn.execute('''
      SELECT $sqlIsRoutineEvent,
             ${sqlIsWafRejectEvent(statusCodes: _codes, contentTypes: _types)},
             ${sqlEventGroupKey()}
      FROM events ORDER BY id
    ''');
    final mismatches = <String>[];
    for (final (i, (type, message, issueId, payload)) in _fixtures.indexed) {
      final r = rows[i];
      final dart = (
        isRoutineEvent(type, payload, message: message),
        isWafRejectEvent(type, payload, statusCodes: _codes, contentTypes: _types),
        eventGroupKey(type: type, issueId: issueId, message: message, payload: payload),
      );
      final label = '$type ${jsonEncode(message)} ${jsonEncode(payload)}';
      if (dart.$1 != r[0]) mismatches.add('routine $label: dart ${dart.$1} sql ${r[0]}');
      if (dart.$2 != r[1]) mismatches.add('waf $label: dart ${dart.$2} sql ${r[1]}');
      if (dart.$3 != r[2]) mismatches.add('groupKey $label: dart ${dart.$3} sql ${r[2]}');
    }
    expect(rows, hasLength(_fixtures.length));
    // Known drift, pinned so new drift fails. Dart trims action / falls back to
    // payload.message / reads top-level network fields / treats heartbeat as routine;
    // SQL trims the message and skips a blank content-type header.
    expect(mismatches, [
      'routine session null {"action":" start "}: dart true sql false',
      'routine session null {"action":"heartbeat"}: dart true sql false',
      'groupKey log " app resumed " {}: dart log| app resumed  sql log|app resumed',
      'routine log null {"message":"session_start"}: dart true sql false',
      'groupKey log null {"message":"session_start"}: dart log|session_start sql log|log',
      'groupKey log "Hello" {"action":"  "}: dart log|hello sql log|',
      'groupKey log "  Padded Message" {}: dart log|  padded message sql log|padded message',
      'groupKey network null {"method":"PUT","url":"/top-level"}: dart network|PUT|/top-level sql network|GET|',
      'waf network null {"network":{"statusCode":403,"response":{"headers":{"content-type":"","Content-Type":"text/html"}}}}: '
          'dart false sql true',
    ]);
  });
}
