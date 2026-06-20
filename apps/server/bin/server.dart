import 'dart:io';

import 'package:scout_server/app.dart';
import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/db/scout_db.dart';
import 'package:scout_server/store/analytics_store.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:shelf/shelf_io.dart';

Future<void> main() async {
  try {
    final config = ServerConfig.load();
    final db = ScoutDb(config.dbConfig);
    await runMigrations(db);
    await db.ping();

    final store = ScoutStore(db);
    final analytics = AnalyticsStore(db);
    final handler = createApp(config: config, store: store, analytics: analytics);
    stdout.writeln('scout-logger listening on ${config.publicUrl}');
    stdout.writeln('Dashboard: ${config.dashboardPublicUrl}');
    await serve(handler, config.host, config.port);
  } catch (e, st) {
    stderr.writeln('scout-logger failed to start: $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}
