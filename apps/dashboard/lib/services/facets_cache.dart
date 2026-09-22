import '../utils/date_range.dart';
import 'api_client.dart';

/// Short-lived in-memory cache so Issues/Events/Notifications don't stampede /facets.
abstract final class FacetsCache {
  static final Map<String, _Entry> _entries = {};
  static const _ttl = Duration(seconds: 45);

  static String _key(
    String projectId, {
    PeriodFilter? period,
    String? environment,
    String? appVersion,
    String? deviceName,
  }) {
    final p = period ?? const PeriodFilter.days(30);
    return '$projectId|${p.toQuery()}|${environment ?? ''}|${appVersion ?? ''}|${deviceName ?? ''}';
  }

  static Future<Map<String, dynamic>> get(
    ScoutApi api,
    String projectId, {
    PeriodFilter? period,
    String? environment,
    String? appVersion,
    String? deviceName,
  }) {
    final key = _key(
      projectId,
      period: period,
      environment: environment,
      appVersion: appVersion,
      deviceName: deviceName,
    );
    final now = DateTime.now();
    final hit = _entries[key];
    if (hit != null && now.difference(hit.at) < _ttl) return hit.future;

    final future = api.fetchFilterFacets(
      projectId,
      period: period,
      environment: environment,
      appVersion: appVersion,
      deviceName: deviceName,
    );
    _entries[key] = _Entry(future, now);
    future.then((_) {}, onError: (_) => _entries.remove(key));
    return future;
  }
}

class _Entry {
  _Entry(this.future, this.at);
  final Future<Map<String, dynamic>> future;
  final DateTime at;
}
