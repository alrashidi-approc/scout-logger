import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../middleware/http_utils.dart';
import '../store/scout_store.dart';

Handler clientConfigRoutes(ScoutStore store) {
  return (Request request) async {
    if (request.method != 'GET') return jsonErr('Method not allowed', status: 405);

    final token = bearerToken(request);
    if (token == null || token.isEmpty) return jsonErr('Missing Bearer ingest key', status: 401);

    final project = await store.findProjectByIngestKey(token);
    if (project == null) return jsonErr('Invalid ingest key', status: 401);

    try {
      final config = await store.getClientConfig(project['projectId'] as String);
      return Response.ok(
        jsonEncode({'ok': true, ...config}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  };
}
