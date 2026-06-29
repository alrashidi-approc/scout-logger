import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';
import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/db/scout_db.dart';

/// One-shot: compute `network.readable.fault` for historical network events
/// that were ingested before fault enrichment existed. Respects per-project
/// status-code overrides. Safe to re-run — only touches rows missing a fault.
Future<void> main(List<String> args) async {
  const batch = 500;
  try {
    final config = ServerConfig.load();
    final db = ScoutDb(config.dbConfig);
    await db.ping();
    final conn = await db.connect();

    final overridesByProject = await _loadOverrides(conn);
    stdout.writeln('Loaded fault overrides for ${overridesByProject.length} project(s).');

    var total = 0;
    while (true) {
      final rows = await conn.execute(
        Sql.named('''
          SELECT id, project_id, payload FROM events
          WHERE type = 'network'
            AND payload->'network' IS NOT NULL
            AND (payload->'network'->'readable'->'fault') IS NULL
          LIMIT @lim
        '''),
        parameters: {'lim': batch},
      );
      if (rows.isEmpty) break;

      for (final r in rows) {
        final id = r[0] as String;
        final pid = r[1] as String;
        final payload = Map<String, dynamic>.from(r[2] as Map);
        final network = Map<String, dynamic>.from(payload['network'] as Map);
        network['readable'] = networkReadableFrom(network, faultOverrides: overridesByProject[pid]);
        payload['network'] = network;
        await conn.execute(
          Sql.named('UPDATE events SET payload = @p::jsonb WHERE id = @id'),
          parameters: {'p': jsonEncode(payload), 'id': id},
        );
      }
      total += rows.length;
      stdout.writeln('Backfilled $total events...');
    }

    await db.close();
    stdout.writeln('Done — $total network event(s) updated.');
  } catch (e, st) {
    stderr.writeln('Backfill failed: $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}

Future<Map<String, Map<int, NetworkFaultClass>>> _loadOverrides(Connection conn) async {
  final rows = await conn.execute('SELECT id, settings FROM projects');
  final out = <String, Map<int, NetworkFaultClass>>{};
  for (final r in rows) {
    final settings = r[1] is Map ? Map<String, dynamic>.from(r[1] as Map) : <String, dynamic>{};
    final sdkJson = settings['sdk'];
    final sdk = ProjectSdkConfig.fromJson(sdkJson is Map ? Map<String, dynamic>.from(sdkJson) : null);
    final overrides = sdk.networkFaultOverrides;
    if (overrides.isNotEmpty) out[r[0] as String] = overrides;
  }
  return out;
}
