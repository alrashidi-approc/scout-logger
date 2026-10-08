@Tags(['db'])
library;

import 'package:scout_models/scout_models.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:scout_server/util/dates.dart';
import 'package:test/test.dart';

import 'test_db.dart';

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();
  final store = ScoutStore(db);

  test('searchLogs matches raw event JSON', () async {
    await (await db.connect()).execute("INSERT INTO projects (id, name, slug) VALUES ('deep', 'deep', 'deep')");
    final now = DateTime.now().toUtc();
    await store.ingestBatch(projectId: 'deep', keyId: 'k', enrichment: const {}, events: [
      IngestEvent(
        type: 'network',
        timestamp: now.toIso8601String(),
        payload: {
          'message': 'POST /orders',
          'level': 'info',
          'user': {'id': 'user-9', 'phone': '+966511122233'},
          'network': {
            'url': 'https://api.test/orders',
            'method': 'POST',
            'statusCode': 201,
            'request': {'body': '{"sku":"ORD-7781-JSON"}'},
            'response': {'body': '{"ref":"REF-4412-JSON"}'},
          },
        },
      ),
    ]);

    final window = TimeWindow.lastDays(7);
    final request = await store.searchLogs('deep', q: 'ORD-7781-JSON', window: window);
    final response = await store.searchLogs('deep', q: 'REF-4412-JSON', window: window);
    final phone = await store.searchLogs('deep', q: '511122233', window: window);
    final miss = await store.searchLogs('deep', q: 'zzznomatch', window: window);

    expect((request['events'] as List).single['matchSnippet'], contains('ORD-7781-JSON'));
    expect((response['events'] as List).single['matchSnippet'], contains('REF-4412-JSON'));
    expect((phone['events'] as List).single['matchSnippet'], contains('511122233'));
    expect(miss['events'], isEmpty);
  });
}
