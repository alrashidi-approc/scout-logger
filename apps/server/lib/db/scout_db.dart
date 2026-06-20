import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:scout_server/config/env_file.dart';

class DbConfig {
  DbConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  factory DbConfig.fromEnv(EnvFile e) {
    final user = e['POSTGRES_USER'] ?? e['DB_USER'];
    final pass = e['POSTGRES_PASSWORD'] ?? e['DB_PASSWORD'];
    final db = e['POSTGRES_DB'] ?? e['DB_NAME'];
    if (user != null && pass != null && db != null) {
      return DbConfig(
        host: e['DB_HOST'] ?? 'localhost',
        port: int.tryParse(e['DB_PORT'] ?? '5432') ?? 5432,
        database: db,
        username: user,
        password: pass,
      );
    }
    final url = e['DATABASE_URL'];
    if (url == null || url.isEmpty) {
      throw StateError('Set POSTGRES_USER/PASSWORD/DB in .env (or DATABASE_URL).');
    }
    return DbConfig.fromUrl(url);
  }

  factory DbConfig.fromUrl(String url) {
    final uri = Uri.parse(url);
    final userInfo = uri.userInfo;
    return DbConfig(
      host: uri.host.isEmpty ? 'localhost' : uri.host,
      port: uri.port == 0 ? 5432 : uri.port,
      database: uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'scout',
      username: userInfo.isNotEmpty ? userInfo.split(':').first : 'scout',
      password: userInfo.contains(':') ? userInfo.split(':').last : '',
    );
  }

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
}

class ScoutDb {
  ScoutDb(this.config);

  final DbConfig config;
  Connection? _conn;

  Future<Connection> connect() async {
    _conn ??= await _open();
    return _conn!;
  }

  Future<Connection> _open() async {
    return Connection.open(
      Endpoint(
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.username,
        password: config.password,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
  }

  Future<void> close() async {
    await _conn?.close();
    _conn = null;
  }

  Future<void> ping() async {
    final conn = await connect();
    await conn.execute('SELECT 1');
  }
}

Future<void> runMigrations(ScoutDb db) async {
  final conn = await db.connect();
  final dir = _migrationsDirectory();
  if (dir == null) return;

  await conn.execute('''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  ''');

  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final match = RegExp(r'^(\d+)').firstMatch(name);
    if (match == null) continue;
    final version = int.parse(match.group(1)!);
    final applied = await conn.execute(
      Sql.named('SELECT 1 FROM schema_migrations WHERE version = @v'),
      parameters: {'v': version},
    );
    if (applied.isNotEmpty) continue;

    await _executeSqlScript(conn, await file.readAsString());
    await conn.execute(
      Sql.named('INSERT INTO schema_migrations (version) VALUES (@v)'),
      parameters: {'v': version},
    );
    stdout.writeln('Applied migration $name');
  }
}

Future<void> _executeSqlScript(Connection conn, String sql) async {
  for (final part in sql.split(';')) {
    final stmt = part.trim();
    if (stmt.isEmpty) continue;
    await conn.execute(stmt);
  }
}

Directory? _migrationsDirectory() {
  for (final path in ['lib/db/migrations', '/app/lib/db/migrations']) {
    final dir = Directory(path);
    if (dir.existsSync()) return dir;
  }
  return null;
}
