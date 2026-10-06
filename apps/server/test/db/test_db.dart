import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:scout_server/config/env_file.dart';
import 'package:scout_server/db/scout_db.dart';
import 'package:test/test.dart';

/// Scratch database on the `./dev db` Postgres (localhost:5433), migrated and
/// dropped after the suite. Returns null when Postgres isn't reachable.
Future<ScoutDb?> openTestDb() async {
  final env = EnvFile.load();
  final host = env['TEST_DB_HOST'] ?? 'localhost';
  final port = int.parse(env['TEST_DB_PORT'] ?? '5433');
  final user = env['POSTGRES_USER'] ?? 'scout';
  final password = env['POSTGRES_PASSWORD'] ?? '';
  final Connection admin;
  try {
    admin = await Connection.open(
      Endpoint(host: host, port: port, database: env['POSTGRES_DB'] ?? 'scout', username: user, password: password),
      settings: const ConnectionSettings(sslMode: SslMode.disable, connectTimeout: Duration(seconds: 2)),
    );
  } catch (_) {
    return null;
  }
  final name = 'scout_test_${Random().nextInt(1 << 32).toRadixString(16)}';
  await admin.execute('CREATE DATABASE $name');
  final db = ScoutDb(DbConfig(host: host, port: port, database: name, username: user, password: password));
  Future<void> drop() async {
    await db.close();
    await admin.execute('DROP DATABASE $name WITH (FORCE)');
    await admin.close();
  }

  try {
    await runMigrations(db);
  } catch (_) {
    await drop();
    rethrow;
  }
  tearDownAll(drop);
  return db;
}

/// Declares a single skipped test so `dart test` reports why DB tests didn't run.
void skipDbTests() => test('db tests', () {}, skip: 'Postgres not reachable (run ./dev db)');
