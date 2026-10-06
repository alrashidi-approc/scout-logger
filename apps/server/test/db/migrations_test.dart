@Tags(['db'])
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:scout_server/db/scout_db.dart';
import 'package:test/test.dart';

import 'test_db.dart';

Future<void> main() async {
  final db = await openTestDb();
  if (db == null) return skipDbTests();

  test('applies every migration to a fresh database', () async {
    final files = Directory('lib/db/migrations').listSync().where((f) => f.path.endsWith('.sql')).length;
    final rows = await (await db.connect()).execute('SELECT count(*)::int FROM schema_migrations');
    expect(rows.first[0], files);
  });

  group('temp-dir migrations', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('scout_migrations'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Object?> one(String sql) async => (await (await db.connect()).execute(sql)).firstOrNull?[0];
    Future<bool> recorded(int v) async => await one('SELECT 1 FROM schema_migrations WHERE version = $v') != null;

    test('are skipped at boot, then applied, validated and recorded by migrate', () async {
      File('${dir.path}/900_t.sql').writeAsStringSync('CREATE TABLE t900 (x int); INSERT INTO t900 VALUES (1), (2);');
      File('${dir.path}/901_t_x.concurrent.sql').writeAsStringSync('CREATE INDEX CONCURRENTLY IF NOT EXISTS t900_x ON t900 (x);');

      await runMigrations(db, dir: dir);
      expect(await recorded(900), isTrue);
      expect(await recorded(901), isFalse);

      await runMigrations(db, dir: dir, concurrent: true);
      expect(await recorded(901), isTrue);
      expect(await one("SELECT indisvalid FROM pg_index WHERE indexrelid = 't900_x'::regclass"), isTrue);    });

    test('a failed build drops the invalid index and is not recorded', () async {
      File('${dir.path}/910_t.sql').writeAsStringSync('CREATE TABLE t910 (x int); INSERT INTO t910 VALUES (1), (1);');
      File('${dir.path}/911_t_x.concurrent.sql').writeAsStringSync('CREATE UNIQUE INDEX CONCURRENTLY t910_x ON t910 (x);');

      await expectLater(runMigrations(db, dir: dir, concurrent: true), throwsA(isA<ServerException>()));
      expect(await recorded(911), isFalse);
      expect(await one("SELECT to_regclass('t910_x')::text"), isNull);
    });

    test('a migration blocked by a held lock times out and is not recorded', () async {
      File('${dir.path}/920_t.sql').writeAsStringSync('CREATE TABLE t920 (x int);');
      await runMigrations(db, dir: dir);
      File('${dir.path}/921_t_y.sql').writeAsStringSync('ALTER TABLE t920 ADD COLUMN y int;');

      final sw = Stopwatch()..start();
      await db.pool.runTx((tx) async {
        await tx.execute('LOCK TABLE t920 IN ACCESS SHARE MODE');
        await expectLater(
          runMigrations(db, dir: dir),
          throwsA(isA<MigrationLockTimeoutException>().having((e) => e.toString(), 'message', contains('921_t_y.sql'))),
        );
      });
      expect(sw.elapsed, lessThan(const Duration(seconds: 15)));
      expect(await recorded(921), isFalse);
      expect(await one("SELECT 1 FROM information_schema.columns WHERE table_name = 't920' AND column_name = 'y'"), isNull);
    });
  });
}
