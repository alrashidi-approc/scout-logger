import 'package:postgres/postgres.dart';

import 'dates.dart';
import 'event_filters.dart';
import 'user_identity.dart';

String trendGranularity(TimeWindow w) => w.usesHourlyTrend ? 'hour' : 'day';

Future<List<Map<String, dynamic>>> fetchEventTrend(
  Connection conn,
  String projectId,
  TimeWindow w, {
  bool includeUsers = false,
}) async {
  if (w.usesHourlyTrend) return _hourlyTrend(conn, projectId, w, includeUsers: includeUsers);
  if (preferIdentityRollups(w)) {
    return _dailyTrendFromRollups(conn, projectId, w, includeUsers: includeUsers);
  }
  return _dailyTrend(conn, projectId, w, includeUsers: includeUsers);
}

Future<List<Map<String, dynamic>>> _dailyTrendFromRollups(
  Connection conn,
  String projectId,
  TimeWindow w, {
  required bool includeUsers,
}) async {
  final dp = dateParams(w);
  final rows = await conn.execute(
    Sql.named('''
      SELECT date,
             COALESCE(SUM(events_total), 0)::int,
             COALESCE(SUM(errors), 0)::int,
             COALESCE(SUM(crashes), 0)::int
      FROM daily_stats
      WHERE project_id = @pid
        AND (@fromDate::date IS NULL OR date >= @fromDate::date)
        AND (@untilDate::date IS NULL OR date < @untilDate::date)
      GROUP BY date
      ORDER BY date
    '''),
    parameters: {'pid': projectId, ...dp},
  );

  Map<String, int>? usersByDay;
  Map<String, int>? guestsByDay;
  if (includeUsers) {
    final users = await conn.execute(
      Sql.named('''
        SELECT date, COUNT(DISTINCT user_id)::int
        FROM user_daily_stats
        WHERE project_id = @pid
          AND (@fromDate::date IS NULL OR date >= @fromDate::date)
          AND (@untilDate::date IS NULL OR date < @untilDate::date)
        GROUP BY date
      '''),
      parameters: {'pid': projectId, ...dp},
    );
    usersByDay = {
      for (final r in users) (r[0] as DateTime).toIso8601String().substring(0, 10): r[1] as int,
    };
    final guests = await conn.execute(
      Sql.named('''
        SELECT date, COUNT(DISTINCT install_id)::int
        FROM device_daily_stats
        WHERE project_id = @pid
          AND guest_event_count > 0
          AND (@fromDate::date IS NULL OR date >= @fromDate::date)
          AND (@untilDate::date IS NULL OR date < @untilDate::date)
        GROUP BY date
      '''),
      parameters: {'pid': projectId, ...dp},
    );
    guestsByDay = {
      for (final r in guests) (r[0] as DateTime).toIso8601String().substring(0, 10): r[1] as int,
    };
  }

  return rows.map((r) {
    final day = (r[0] as DateTime).toIso8601String().substring(0, 10);
    final events = r[1] as int;
    final errors = r[2] as int;
    return {
      'date': day,
      'events': events,
      'errors': errors,
      'crashes': r[3],
      if (includeUsers) ...{
        'success': (events - errors).clamp(0, events),
        'users': usersByDay?[day] ?? 0,
        'loggedInUsers': usersByDay?[day] ?? 0,
        'guestDevices': guestsByDay?[day] ?? 0,
      },
    };
  }).toList();
}

Future<List<Map<String, dynamic>>> _hourlyTrend(
  Connection conn,
  String projectId,
  TimeWindow w, {
  required bool includeUsers,
}) async {
  final audienceCols = includeUsers
      ? ''', COUNT(*) FILTER (
              WHERE ${sqlIsSuccessEvent()}
            )::int,
            COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()})::int,
            COUNT(DISTINCT install_id) FILTER (WHERE ${guestUserSql()})::int'''
      : '';
  final rows = await conn.execute(
    Sql.named('''
      SELECT date_trunc('hour', occurred_at) AS bucket,
             COUNT(*)::int,
             COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
             COUNT(*) FILTER (WHERE type = 'crash')::int
             $audienceCols
      FROM events
      WHERE project_id = @pid
        AND $sqlHideSessionHeartbeat
        AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
        AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      GROUP BY 1 ORDER BY 1
    '''),
    parameters: {'pid': projectId, ...timeParams(w)},
  );

  final byHour = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final bucket = _hourBucket(r[0] as DateTime);
    byHour[bucket] = {
      'date': bucket,
      'events': r[1],
      'errors': r[2],
      'crashes': r[3],
      if (includeUsers) ..._audienceCols(r, 4),
    };
  }

  final since = DateTime.parse(w.since!).toUtc();
  final until = w.until != null ? DateTime.parse(w.until!).toUtc() : DateTime.now().toUtc();
  var t = DateTime.utc(since.year, since.month, since.day, since.hour);
  final out = <Map<String, dynamic>>[];
  while (t.isBefore(until)) {
    final key = _hourBucket(t);
    out.add(byHour[key] ?? {
      'date': key,
      'events': 0,
      'errors': 0,
      'crashes': 0,
      if (includeUsers) ...const {'success': 0, 'users': 0, 'loggedInUsers': 0, 'guestDevices': 0},
    });
    t = t.add(const Duration(hours: 1));
  }
  return out;
}

String _hourBucket(DateTime d) {
  final u = d.toUtc();
  return DateTime.utc(u.year, u.month, u.day, u.hour).toIso8601String();
}

Future<List<Map<String, dynamic>>> _dailyTrend(
  Connection conn,
  String projectId,
  TimeWindow w, {
  required bool includeUsers,
}) async {
  final rows = await conn.execute(
    Sql.named('''
      SELECT (occurred_at AT TIME ZONE 'UTC')::date AS day,
             COUNT(*)::int,
             COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
             COUNT(*) FILTER (WHERE type = 'crash')::int
             ${includeUsers ? ''', COUNT(*) FILTER (
                    WHERE ${sqlIsSuccessEvent()}
                  )::int,
                  COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()})::int,
                  COUNT(DISTINCT install_id) FILTER (WHERE ${guestUserSql()})::int''' : ''}
      FROM events
      WHERE project_id = @pid
        AND $sqlHideSessionHeartbeat
        AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
        AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      GROUP BY 1 ORDER BY 1
    '''),
    parameters: {'pid': projectId, ...timeParams(w)},
  );

  return rows
      .map((r) => {
            'date': (r[0] as DateTime).toIso8601String().substring(0, 10),
            'events': r[1],
            'errors': r[2],
            'crashes': r[3],
            if (includeUsers) ..._audienceCols(r, 4),
          })
      .toList();
}

Map<String, int> _audienceCols(ResultRow r, int start) => {
      'success': r[start] as int,
      'users': r[start + 1] as int,
      'loggedInUsers': r[start + 1] as int,
      'guestDevices': r[start + 2] as int,
    };
