import '../utils/date_range.dart';

/// In-memory cache so navigating away and back does not refetch.
/// Refresh icons should call load with [force] / always hit the network and [write].
class ScreenCache {
  ScreenCache._();
  static final instance = ScreenCache._();

  final _store = <String, Object>{};

  T? read<T extends Object>(String key) {
    final v = _store[key];
    return v is T ? v : null;
  }

  void write(String key, Object value) => _store[key] = value;

  void invalidate(String key) => _store.remove(key);

  void invalidatePrefix(String prefix) => _store.removeWhere((k, _) => k.startsWith(prefix));

  void clear() => _store.clear();
}

String screenCacheKey(
  String screen, {
  String? projectId,
  PeriodFilter? period,
  Map<String, String?>? extra,
}) {
  final parts = <String>[screen, if (projectId != null) projectId];
  if (period != null) {
    final q = period.toQuery();
    final keys = q.keys.toList()..sort();
    parts.add(keys.map((k) => '$k=${q[k]}').join('&'));
  }
  if (extra != null && extra.isNotEmpty) {
    final keys = extra.keys.toList()..sort();
    for (final k in keys) {
      final v = extra[k];
      if (v != null && v.isNotEmpty) parts.add('$k=$v');
    }
  }
  return parts.join('|');
}
