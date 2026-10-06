@Tags(['db'])
library;

import 'dart:io';

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
}
