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

  late final endpoint = Endpoint(
    host: config.host,
    port: config.port,
    database: config.database,
    username: config.username,
    password: config.password,
  );

  /// Dashboard, API and schedulers. Separate from [ingest] so slow dashboard
  /// queries can't starve event ingest (and vice versa).
  late final pool = _pool(maxConnections: 8, statementTimeout: '30s');
  late final ingest = _pool(maxConnections: 4, statementTimeout: '10s');

  /// Each `execute` checks out a pooled connection; use `pool.runTx` when
  /// statements must share a session.
  Future<Session> connect() async => pool;

  Pool<void> _pool({required int maxConnections, required String statementTimeout}) {
    return Pool.withEndpoints(
      [endpoint],
      settings: PoolSettings(
        maxConnectionCount: maxConnections,
        sslMode: SslMode.disable,
        onOpen: (conn) async {
          await conn.execute("SET statement_timeout = '$statementTimeout'");
          await conn.execute("SET idle_in_transaction_session_timeout = '60s'");
        },
      ),
    );
  }

  Future<void> close() => Future.wait([pool.close(), ingest.close()]);

  Future<void> ping() => pool.execute('SELECT 1');
}

/// Runs on a dedicated connection so long migrations aren't cut by the pools'
/// `statement_timeout`.
Future<void> runMigrations(ScoutDb db) async {
  final dir = _migrationsDirectory();
  if (dir == null) return;
  final conn = await Connection.open(db.endpoint, settings: const ConnectionSettings(sslMode: SslMode.disable));
  try {
    await _migrate(conn, dir);
  } finally {
    await conn.close();
  }
}

Future<void> _migrate(Connection conn, Directory dir) async {
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

    final sql = await file.readAsString();
    // Whole file via the simple protocol (handles `DO $$ … $$`), atomic with its version row.
    await conn.runTx((tx) async {
      await tx.execute(sql, queryMode: QueryMode.simple);
      await tx.execute(
        Sql.named('INSERT INTO schema_migrations (version) VALUES (@v)'),
        parameters: {'v': version},
      );
    });
    stdout.writeln('Applied migration $name');
  }
}

Directory? _migrationsDirectory() {
  for (final path in ['lib/db/migrations', '/app/lib/db/migrations']) {
    final dir = Directory(path);
    if (dir.existsSync()) return dir;
  }
  return null;
}
