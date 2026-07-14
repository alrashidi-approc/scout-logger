import 'package:postgres/postgres.dart';

import 'event_filters.dart';
import 'user_identity.dart';

/// Upsert user/device daily rollups after a non-heartbeat event insert.
Future<void> upsertIdentityRollups(
  Connection conn, {
  required String projectId,
  required DateTime occurredAt,
  required String type,
  required Map<String, dynamic> payload,
  String? userId,
  String? installId,
  String? platform,
  String? appVersion,
  String? environment,
  String? release,
  String? country,
}) async {
  final day = occurredAt.toIso8601String().substring(0, 10);
  final err = isErrorEvent(type, payload) ? 1 : 0;
  final crash = type == 'crash' ? 1 : 0;
  final identified = isIdentifiedAppUser(userId: userId, installId: installId);
  final guest = isGuestAppUser(userId: userId, installId: installId);

  final user = payload['user'] is Map ? Map<String, dynamic>.from(payload['user'] as Map) : <String, dynamic>{};
  final device = payload['device'] is Map ? Map<String, dynamic>.from(payload['device'] as Map) : <String, dynamic>{};
  final email = _trim(user['email']);
  final displayName = _trim(user['name']);
  final phone = _trim(user['phone']);
  final username = _trim(user['username']);
  final deviceName = _trim(device['deviceName']) ?? _trim(device['deviceModel']) ?? _trim(device['model']);
  final locale = _trim(_nested(device, 'geo', 'locale')) ?? _trim(device['locale']);
  final route = _trim(_nested(payload, 'screen', 'currentRoute'));

  if (identified && userId != null) {
    await conn.execute(
      Sql.named('''
        INSERT INTO user_stats (
          project_id, user_id, first_seen_at, last_seen_at,
          email, display_name, phone, username,
          platform, app_version, environment, release, country,
          device_name, locale, last_route, install_id
        ) VALUES (
          @pid, @uid, @at, @at,
          @email, @name, @phone, @uname,
          @plat, @aver, @env, @rel, @country,
          @dname, @locale, @route, @iid
        )
        ON CONFLICT (project_id, user_id) DO UPDATE SET
          last_seen_at = GREATEST(user_stats.last_seen_at, EXCLUDED.last_seen_at),
          email = COALESCE(EXCLUDED.email, user_stats.email),
          display_name = COALESCE(EXCLUDED.display_name, user_stats.display_name),
          phone = COALESCE(EXCLUDED.phone, user_stats.phone),
          username = COALESCE(EXCLUDED.username, user_stats.username),
          platform = COALESCE(EXCLUDED.platform, user_stats.platform),
          app_version = COALESCE(EXCLUDED.app_version, user_stats.app_version),
          environment = COALESCE(EXCLUDED.environment, user_stats.environment),
          release = COALESCE(EXCLUDED.release, user_stats.release),
          country = COALESCE(EXCLUDED.country, user_stats.country),
          device_name = COALESCE(EXCLUDED.device_name, user_stats.device_name),
          locale = COALESCE(EXCLUDED.locale, user_stats.locale),
          last_route = COALESCE(EXCLUDED.last_route, user_stats.last_route),
          install_id = COALESCE(EXCLUDED.install_id, user_stats.install_id)
      '''),
      parameters: {
        'pid': projectId,
        'uid': userId,
        'at': occurredAt,
        'email': email,
        'name': displayName,
        'phone': phone,
        'uname': username,
        'plat': platform,
        'aver': appVersion,
        'env': environment,
        'rel': release,
        'country': country,
        'dname': deviceName,
        'locale': locale,
        'route': route,
        'iid': installId,
      },
    );

    await conn.execute(
      Sql.named('''
        INSERT INTO user_daily_stats (project_id, user_id, date, event_count, error_count, crash_count)
        VALUES (@pid, @uid, @day::date, 1, @err, @crash)
        ON CONFLICT (project_id, user_id, date) DO UPDATE SET
          event_count = user_daily_stats.event_count + 1,
          error_count = user_daily_stats.error_count + EXCLUDED.error_count,
          crash_count = user_daily_stats.crash_count + EXCLUDED.crash_count
      '''),
      parameters: {'pid': projectId, 'uid': userId, 'day': day, 'err': err, 'crash': crash},
    );
  }

  if (installId != null && installId.isNotEmpty) {
    await conn.execute(
      Sql.named('''
        INSERT INTO device_stats (
          project_id, install_id, first_seen_at, last_seen_at,
          device_name, platform, app_version, environment, country, locale
        ) VALUES (
          @pid, @iid, @at, @at,
          @dname, @plat, @aver, @env, @country, @locale
        )
        ON CONFLICT (project_id, install_id) DO UPDATE SET
          last_seen_at = GREATEST(device_stats.last_seen_at, EXCLUDED.last_seen_at),
          device_name = COALESCE(EXCLUDED.device_name, device_stats.device_name),
          platform = COALESCE(EXCLUDED.platform, device_stats.platform),
          app_version = COALESCE(EXCLUDED.app_version, device_stats.app_version),
          environment = COALESCE(EXCLUDED.environment, device_stats.environment),
          country = COALESCE(EXCLUDED.country, device_stats.country),
          locale = COALESCE(EXCLUDED.locale, device_stats.locale)
      '''),
      parameters: {
        'pid': projectId,
        'iid': installId,
        'at': occurredAt,
        'dname': deviceName,
        'plat': platform,
        'aver': appVersion,
        'env': environment,
        'country': country,
        'locale': locale,
      },
    );

    await conn.execute(
      Sql.named('''
        INSERT INTO device_daily_stats (project_id, install_id, date, event_count, error_count, crash_count, guest_event_count)
        VALUES (@pid, @iid, @day::date, 1, @err, @crash, @guest)
        ON CONFLICT (project_id, install_id, date) DO UPDATE SET
          event_count = device_daily_stats.event_count + 1,
          error_count = device_daily_stats.error_count + EXCLUDED.error_count,
          crash_count = device_daily_stats.crash_count + EXCLUDED.crash_count,
          guest_event_count = device_daily_stats.guest_event_count + EXCLUDED.guest_event_count
      '''),
      parameters: {
        'pid': projectId,
        'iid': installId,
        'day': day,
        'err': err,
        'crash': crash,
        'guest': guest ? 1 : 0,
      },
    );
  }

  if (identified && userId != null && installId != null && installId.isNotEmpty) {
    await conn.execute(
      Sql.named('''
        INSERT INTO user_device_links (project_id, user_id, install_id, first_seen_at, last_seen_at, event_count)
        VALUES (@pid, @uid, @iid, @at, @at, 1)
        ON CONFLICT (project_id, user_id, install_id) DO UPDATE SET
          last_seen_at = GREATEST(user_device_links.last_seen_at, EXCLUDED.last_seen_at),
          event_count = user_device_links.event_count + 1
      '''),
      parameters: {'pid': projectId, 'uid': userId, 'iid': installId, 'at': occurredAt},
    );
  }
}

String? _trim(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

String? _nested(Map<String, dynamic> m, String a, String b) {
  final nested = m[a];
  if (nested is! Map) return null;
  return nested[b]?.toString();
}
