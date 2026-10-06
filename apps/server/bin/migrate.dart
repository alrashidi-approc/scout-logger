import 'dart:io';

import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/db/backfills.dart';
import 'package:scout_server/db/scout_db.dart';

Future<void> main(List<String> args) async {
  ScoutDb? db;
  try {
    final config = ServerConfig.load();
    db = ScoutDb(config.dbConfig);
    stdout.writeln('Connecting to ${config.dbConfig.host}:${config.dbConfig.port}/${config.dbConfig.database}...');
    // Deploy runs this right after (re)starting Postgres.
    for (var attempt = 1;; attempt++) {
      try {
        await db.ping();
        break;
      } catch (_) {
        if (attempt == 30) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    // Backfills need the new server's ingest live — deploy runs them after the swap.
    if (args.contains('--backfills')) {
      stdout.writeln('Running backfills...');
      await runBackfills(db);
      stdout.writeln('Done.');
      return;
    }
    stdout.writeln('Running migrations...');
    for (var attempt = 1;; attempt++) {
      try {
        await runMigrations(db, concurrent: true);
        break;
      } on MigrationLockTimeoutException catch (e) {
        if (attempt == 3) rethrow;
        stderr.writeln('$e — retrying in 10s');
        await Future<void>.delayed(const Duration(seconds: 10));
      }
    }
    final conn = await db.connect();
    final rows = await conn.execute('SELECT version, applied_at FROM schema_migrations ORDER BY version');
    stdout.writeln('Applied migrations:');
    for (final r in rows) {
      stdout.writeln('  ${r[0]} — ${(r[1] as DateTime).toUtc().toIso8601String()}');
    }
    stdout.writeln('Done.');
  } catch (e, st) {
    stderr.writeln('Migration failed: $e');
    stderr.writeln(st);
    exitCode = 1;
  } finally {
    await db?.close();
  }
}
