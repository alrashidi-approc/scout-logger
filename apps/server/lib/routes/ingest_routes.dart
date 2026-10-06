import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:scout_models/scout_models.dart';

import '../middleware/http_utils.dart';
import '../services/geo_enricher.dart';
import '../store/scout_store.dart';

const maxBatchEvents = 1000;

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
      var events = BatchIngestRequest.fromJson(decoded).events;
      if (events.isEmpty) return jsonErr('Empty batch');
      // The SDK resends all pending events and retries forever on non-2xx, so drop the excess instead of erroring.
      if (events.length > maxBatchEvents) {
        stderr.writeln('ingest: dropped ${events.length - maxBatchEvents} events over batch cap (project ${project['projectId']})');
        events = events.sublist(0, maxBatchEvents);
      }

      final enrichment = {
        'geo': (await geo.lookup(headerMap(request), remoteIp: remoteIp(request))).toJson(),
        'clientIpHash': geo.hashIp(geo.clientIp(headerMap(request), remoteIp: remoteIp(request))),
        'receivedAt': DateTime.now().toUtc().toIso8601String(),
      };

      final result = await store.ingestBatch(
        projectId: project['projectId'] as String,
        keyId: project['keyId'] as String,
        events: events,
        enrichment: enrichment,
      );

      // Events are committed: a 5xx now would make the SDK resend (duplicate) them.
      final configVersion = await store
          .getConfigVersion(project['projectId'] as String)
          .then<int?>((v) => v, onError: (Object _) => null);

      return Response(
        202,
        body: jsonEncode({'ok': true, 'configVersion': configVersion, ...result}),
        headers: {'Content-Type': 'application/json'},
      );
    } on BodyTooLargeException catch (e) {
      return jsonErr('$e', status: 413);
    } on FormatException catch (e) {
      return jsonErr(e.message);
    } catch (e) {
      return jsonErr(e.toString(), status: 500);
    }
  };
}
