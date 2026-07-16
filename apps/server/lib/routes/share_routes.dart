import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../middleware/http_utils.dart';
import '../store/scout_store.dart';
import '../util/dates.dart';

Handler shareRoutes(ScoutStore store) {
  final router = Router();

  router.get('/<token>', (Request request, String token) async {
    try {
      final meta = await store.resolveShareToken(token);
      if (meta == null) return jsonErr('Not found', status: 404);

      final type = meta['resourceType'] as String;
      final pid = meta['projectId'] as String;
      final projectName = await store.projectDisplayName(pid) ?? pid;

      if (type == 'alert') {
        final raw = meta['payload'];
        final payload = raw is Map
            ? Map<String, dynamic>.from(raw)
            : raw is String
                ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
                : <String, dynamic>{};
        final kind = payload['kind'] as String? ?? 'spike';

        if (kind == 'digest') {
          return Response.ok(
            jsonEncode({
              'ok': true,
              'type': 'alert',
              'alertKind': 'digest',
              'projectName': projectName,
              'title': payload['title'],
              'body': payload['body'],
              'expiresAt': meta['expiresAt'],
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final filters = payload['filters'] is Map ? Map<String, dynamic>.from(payload['filters'] as Map) : <String, dynamic>{};
        final hours = (int.tryParse('${filters['hours'] ?? ''}') ?? 1).clamp(1, 72);
        final window = TimeWindow(
          since: DateTime.now().toUtc().subtract(Duration(hours: hours)).toIso8601String(),
        );
        final events = await store.listEvents(
          pid,
          type: filters['type'] as String?,
          level: filters['level'] as String?,
          environment: filters['environment'] as String?,
          window: window,
          limit: 50,
        );
        return Response.ok(
          jsonEncode({
            'ok': true,
            'type': 'alert',
            'alertKind': 'spike',
            'projectName': projectName,
            'title': payload['title'],
            'summary': payload['summary'],
            'metric': payload['metric'],
            'events': events['events'],
            'total': events['total'],
            'expiresAt': meta['expiresAt'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (type == 'report') {
        final raw = meta['payload'];
        final payload = raw is Map
            ? Map<String, dynamic>.from(raw)
            : raw is String
                ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
                : <String, dynamic>{};
        return Response.ok(
          jsonEncode({
            'ok': true,
            'type': 'report',
            'projectName': projectName,
            'report': payload,
            'expiresAt': meta['expiresAt'],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

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
          jsonEncode({'ok': true, 'type': 'event', 'projectName': projectName, 'event': event, 'expiresAt': meta['expiresAt']}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final issue = await store.getIssue(pid, rid);
      if (issue == null) return jsonErr('Not found', status: 404);
      issue.remove('projectId');
      return Response.ok(
        jsonEncode({'ok': true, 'type': 'issue', 'projectName': projectName, 'issue': issue, 'expiresAt': meta['expiresAt']}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  return router.call;
}
