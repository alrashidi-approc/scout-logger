import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:scout_models/scout_models.dart';

import '../middleware/http_utils.dart';
import '../services/geo_enricher.dart';
import '../store/scout_store.dart';

Handler ingestRoutes(ScoutStore store, GeoEnricher geo) {
  return (Request request) async {
    if (request.method != 'POST') return jsonErr('Method not allowed', status: 405);

    final token = bearerToken(request);
    if (token == null || token.isEmpty) return jsonErr('Missing Bearer ingest key', status: 401);

    final project = await store.findProjectByIngestKey(token);
    if (project == null) return jsonErr('Invalid ingest key', status: 401);

    try {
      final raw = await readBody(request);
      final decoded = jsonDecode(raw);
      final batch = BatchIngestRequest.fromJson(decoded);
      if (batch.events.isEmpty) return jsonErr('Empty batch');

      final enrichment = {
        'geo': (await geo.lookup(headerMap(request), remoteIp: remoteIp(request))).toJson(),
        'clientIpHash': geo.hashIp(geo.clientIp(headerMap(request), remoteIp: remoteIp(request))),
        'receivedAt': DateTime.now().toUtc().toIso8601String(),
      };

      final result = await store.ingestBatch(
        projectId: project['projectId'] as String,
        keyId: project['keyId'] as String,
        events: batch.events,
        enrichment: enrichment,
      );

      final configVersion = await store.getConfigVersion(project['projectId'] as String);

      return Response(
        202,
        body: jsonEncode({'ok': true, 'configVersion': configVersion, ...result}),
        headers: {'Content-Type': 'application/json'},
      );
    } on FormatException catch (e) {
      return jsonErr(e.message);
    } catch (e) {
      return jsonErr(e.toString(), status: 500);
    }
  };
}
