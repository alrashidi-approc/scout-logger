import 'dart:io';

import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/db/scout_db.dart';

Future<void> main() async {
  try {
    final config = ServerConfig.load();
    final db = ScoutDb(config.dbConfig);
    stdout.writeln('Connecting to ${config.dbConfig.host}:${config.dbConfig.port}/${config.dbConfig.database}...');
    await db.ping();
    stdout.writeln('Running migrations...');
    await runMigrations(db);
    final conn = await db.connect();
    final rows = await conn.execute('SELECT version, applied_at FROM schema_migrations ORDER BY version');
    stdout.writeln('Applied migrations:');
    for (final r in rows) {
      stdout.writeln('  ${r[0]} — ${(r[1] as DateTime).toUtc().toIso8601String()}');
    }
    await db.close();
    stdout.writeln('Done.');
  } catch (e, st) {
    stderr.writeln('Migration failed: $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}
