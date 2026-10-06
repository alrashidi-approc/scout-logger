import 'package:postgres/postgres.dart';

/// Collects per-event rollup upserts into one row per (statement, key) and
/// applies them in sorted order, so concurrent batches lock rows in the same
/// order. Merging per parameter: [sum] adds, [max] keeps the latest DateTime,
/// [first] keeps the first event's value, anything else keeps the last non-null.
class RollupBatch {
  final _rows = <String, (String sql, Map<String, Object?> params)>{};

  void add(
    String sql,
    List<Object?> key,
    Map<String, Object?> params, {
    Set<String> sum = const {},
    Set<String> max = const {},
    Set<String> first = const {},
  }) {
    final id = '$sql\u0000${key.join('\u0000')}';
    final merged = _rows[id]?.$2;
    if (merged == null) {
      _rows[id] = (sql, {...params});
      return;
    }
    params.forEach((name, value) {
      if (sum.contains(name)) {
        merged[name] = (merged[name] as int) + (value as int);
      } else if (max.contains(name)) {
        if ((value as DateTime).isAfter(merged[name] as DateTime)) merged[name] = value;
      } else if (!first.contains(name) && value != null) {
        merged[name] = value;
      }
    });
  }

  Future<void> apply(Session conn) async {
    for (final id in _rows.keys.toList()..sort()) {
      final (sql, params) = _rows[id]!;
      await conn.execute(Sql.named(sql), parameters: params);
    }
  }
}
