import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../middleware/http_utils.dart';
import '../store/scout_store.dart';

Handler shareRoutes(ScoutStore store) {
  final router = Router();

  router.get('/<token>', (Request request, String token) async {
    try {
      final meta = await store.resolveShareToken(token);
      if (meta == null) return jsonErr('Not found', status: 404);

      final type = meta['resourceType'] as String;
      final pid = meta['projectId'] as String;
      final rid = meta['resourceId'] as String;

      if (type == 'event') {
        final event = await store.getEvent(pid, rid);
        if (event == null) return jsonErr('Not found', status: 404);
        event.remove('relatedEvents');
        final issue = event['issue'];
        if (issue is Map) {
          event['issue'] = {
            'title': issue['title'],
            'type': issue['type'],
            'status': issue['status'],
            'fingerprint': issue['fingerprint'],
          };
        }
        return Response.ok(
          jsonEncode({'ok': true, 'type': 'event', 'event': event, 'expiresAt': meta['expiresAt']}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final issue = await store.getIssue(pid, rid);
      if (issue == null) return jsonErr('Not found', status: 404);
      issue.remove('projectId');
      return Response.ok(
        jsonEncode({'ok': true, 'type': 'issue', 'issue': issue, 'expiresAt': meta['expiresAt']}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  return router.call;
}
