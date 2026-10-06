import 'dart:convert';

import 'package:scout_models/scout_models.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:scout_server/routes/ingest_routes.dart';
import 'package:scout_server/services/geo_enricher.dart';
import 'package:scout_server/store/scout_store.dart';

class _FakeStore implements ScoutStore {
  List<IngestEvent>? ingested;

  @override
  Future<Map<String, dynamic>?> findProjectByIngestKey(String rawKey) async => {'projectId': 'p', 'keyId': 'k'};

  @override
  Future<Map<String, dynamic>> ingestBatch({
    required String projectId,
    required String keyId,
    required List<IngestEvent> events,
    required Map<String, dynamic> enrichment,
  }) async {
    ingested = events;
    return {'accepted': events.length, 'configVersion': 1};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Request post(String body) => Request(
        'POST',
        Uri.parse('http://localhost/v1/events/batch'),
        headers: {'authorization': 'Bearer sk_live_test'},
        body: body,
      );

  test('truncates batches over the cap and still succeeds', () async {
    final store = _FakeStore();
    final events = List.generate(maxBatchEvents + 5, (i) => {'type': 'log', 'payload': {'i': i}});
    final res = await ingestRoutes(store, GeoEnricher(enabled: false))(post(jsonEncode({'events': events})));
    expect(res.statusCode, 202);
    expect(store.ingested, hasLength(maxBatchEvents));
    expect(store.ingested!.last.payload['i'], maxBatchEvents - 1);
  });

  test('returns 413 for oversized body', () async {
    final store = _FakeStore();
    final res = await ingestRoutes(store, GeoEnricher(enabled: false))(post('x' * (10 * 1024 * 1024 + 1)));
    expect(res.statusCode, 413);
    expect(store.ingested, isNull);
  });
}
