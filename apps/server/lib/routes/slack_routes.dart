import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../config/server_config.dart';
import '../store/scout_store.dart';

/// Handles Slack interactive button callbacks (Resolve / Mute).
/// Requires SLACK_SIGNING_SECRET; requests are verified per Slack's spec.
Handler slackRoutes(ServerConfig config, ScoutStore store) {
  return (Request request) async {
    if (config.slackSigningSecret.isEmpty) return Response.notFound('Slack interactivity disabled');

    final body = await request.readAsString();
    if (!_verify(config.slackSigningSecret, request.headers, body)) {
      return Response.forbidden('Invalid signature');
    }

    // Slack posts application/x-www-form-urlencoded with a `payload` field.
    final form = Uri.splitQueryString(body);
    final raw = form['payload'];
    if (raw == null) return Response.ok('');
    final payload = jsonDecode(raw) as Map<String, dynamic>;
    final actions = payload['actions'];
    if (actions is! List || actions.isEmpty) return Response.ok('');

    final action = Map<String, dynamic>.from(actions.first as Map);
    final issueId = action['value']?.toString();
    final status = switch (action['action_id']) {
      'resolve_issue' => 'resolved',
      'mute_issue' => 'ignored',
      _ => null,
    };
    if (issueId == null || status == null) return Response.ok('');

    final result = await store.updateIssueStatusById(issueId, status);
    final verb = status == 'resolved' ? 'resolved' : 'muted';
    final text = result == null
        ? ':warning: Issue not found.'
        : ':white_check_mark: *${result.title}* $verb by ${payload['user']?['username'] ?? 'Slack user'}.';
    return Response.ok(
      jsonEncode({'replace_original': false, 'response_type': 'in_channel', 'text': text}),
      headers: {'Content-Type': 'application/json'},
    );
  };
}

bool _verify(String secret, Map<String, String> headers, String body) {
  final ts = headers['x-slack-request-timestamp'];
  final sig = headers['x-slack-signature'];
  if (ts == null || sig == null) return false;
  final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - (int.tryParse(ts) ?? 0);
  if (age.abs() > 300) return false; // replay protection: 5 min
  final base = 'v0:$ts:$body';
  final hmac = Hmac(sha256, utf8.encode(secret));
  final expected = 'v0=${hmac.convert(utf8.encode(base))}';
  return _constantTimeEquals(expected, sig);
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
