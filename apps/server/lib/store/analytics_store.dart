import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../db/scout_db.dart';
import '../util/dates.dart';
import '../util/event_filters.dart';
import '../util/event_trend.dart';
import '../util/user_identity.dart';

/// Product analytics queries — funnels, retention, releases, session timelines.
class AnalyticsStore {
  AnalyticsStore(this.db);

  final ScoutDb db;

  Future<List<String>> distinctRoutes(String projectId, {int days = 30, TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days);
    final rows = await conn.execute(
      Sql.named('''
        SELECT DISTINCT step->>'route' AS route
        FROM events, jsonb_array_elements(payload->'screenTrail') AS step
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
          AND step->>'route' IS NOT NULL AND step->>'route' != ''
        ORDER BY route
        LIMIT 200
      '''),
      parameters: {'pid': projectId, ...timeParams(w)},
    );
    return rows.map((r) => r[0] as String).toList();
  }

  Future<Map<String, dynamic>> funnel(String projectId, List<String> steps, {int days = 30, TimeWindow? window}) async {
    if (steps.isEmpty) return {'steps': [], 'totalSessions': 0};

    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days);
    final rows = await conn.execute(
      Sql.named('''
        SELECT session_id, payload->'screenTrail' AS trail
        FROM (
          SELECT DISTINCT ON (session_id) session_id, payload
          FROM events
          WHERE project_id = @pid
            AND $sqlHideSessionHeartbeat
            AND session_id IS NOT NULL
            AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
            AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
            AND jsonb_typeof(payload->'screenTrail') = 'array'
            AND jsonb_array_length(payload->'screenTrail') > 0
          ORDER BY session_id, jsonb_array_length(payload->'screenTrail') DESC, occurred_at DESC
        ) t
      '''),
      parameters: {'pid': projectId, ...timeParams(w)},
    );

    final trails = <List<String>>[];
    for (final r in rows) {
      final routes = _routesFromTrail(_jsonField(r[1]));
      if (routes.isNotEmpty) trails.add(routes);
    }

    final total = trails.length;
    final stepCounts = List.generate(steps.length, (i) => 0);
    for (final routes in trails) {
      for (var i = 0; i < steps.length; i++) {
        if (_reachedStep(routes, steps, i)) stepCounts[i]++;
      }
    }

    final base = stepCounts.isEmpty ? 0 : stepCounts.first;
    return {
      'days': w.approximateDays,
      'totalSessions': total,
      'steps': [
        for (var i = 0; i < steps.length; i++)
          {
            'route': steps[i],
            'sessions': stepCounts[i],
            'conversionPct': base == 0 ? 0.0 : (stepCounts[i] / base * 100),
            'dropOffPct': i == 0 || stepCounts[i - 1] == 0
                ? 0.0
                : ((stepCounts[i - 1] - stepCounts[i]) / stepCounts[i - 1] * 100),
          },
      ],
    };
  }

  Future<Map<String, dynamic>> retention(String projectId, {int weeks = 8}) async {
    final conn = await db.connect();
    final since = utcTimestampDaysAgo(weeks * 7);
    final rows = await conn.execute(
      Sql.named('''
        WITH         cohorts AS (
          SELECT user_id, date_trunc('week', first_seen_at AT TIME ZONE 'utc')::date AS cohort_week
          FROM user_first_seen
          WHERE project_id = @pid
            AND first_seen_at >= @since::timestamptz
            AND EXISTS (
              SELECT 1 FROM events e
              WHERE e.project_id = @pid AND e.user_id = user_first_seen.user_id
                AND ${identifiedUserSql(alias: 'e')}
              LIMIT 1
            )
        ),
        activity AS (
          SELECT user_id, date_trunc('week', occurred_at AT TIME ZONE 'utc')::date AS active_week
          FROM events
          WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND ${identifiedUserSql()}
          GROUP BY user_id, active_week
        )
        SELECT
          c.cohort_week,
          ((a.active_week - c.cohort_week) / 7)::int AS period,
          COUNT(DISTINCT c.user_id)::int AS users
        FROM cohorts c
        JOIN activity a ON a.user_id = c.user_id AND a.active_week >= c.cohort_week
        GROUP BY c.cohort_week, period
        ORDER BY c.cohort_week, period
      '''),
      parameters: {'pid': projectId, 'since': since},
    );

    final cohortSizes = <String, int>{};
    final cells = <Map<String, dynamic>>[];
    for (final r in rows) {
      final week = (r[0] as DateTime).toIso8601String().substring(0, 10);
      final period = r[1] as int;
      final users = r[2] as int;
      if (period == 0) cohortSizes[week] = users;
      cells.add({'cohortWeek': week, 'period': period, 'users': users});
    }

    for (final c in cells) {
      final size = cohortSizes[c['cohortWeek'] as String] ?? 0;
      c['retentionPct'] = size == 0 ? 0.0 : (c['users'] as int) / size * 100;
    }

    return {
      'weeks': weeks,
      'cohorts': cohortSizes.entries
          .map((e) => {'cohortWeek': e.key, 'size': e.value})
          .toList()
        ..sort((a, b) => (a['cohortWeek'] as String).compareTo(b['cohortWeek'] as String)),
      'cells': cells,
    };
  }

  Future<List<Map<String, dynamic>>> releaseComparison(String projectId, {int days = 30, TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days);
    final tp = timeParams(w);
    final rows = await conn.execute(
      Sql.named('''
        WITH session_release AS (
          SELECT DISTINCT ON (session_id) session_id, release
          FROM events
          WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND session_id IS NOT NULL AND release IS NOT NULL
          ORDER BY session_id, occurred_at
        ),
        session_stats AS (
          SELECT sr.release, AVG(s.duration_ms)::int AS avg_ms, COUNT(*)::int AS sessions
          FROM app_sessions s
          JOIN session_release sr ON sr.session_id = s.id
          WHERE s.project_id = @pid AND s.ended_at IS NOT NULL
            AND (@since::timestamptz IS NULL OR s.started_at >= @since::timestamptz)
            AND (@until::timestamptz IS NULL OR s.started_at < @until::timestamptz)
          GROUP BY sr.release
        )
        SELECT
          e.release,
          COUNT(*)::int AS events,
          COUNT(*) FILTER (WHERE e.type = 'crash')::int AS crashes,
          COUNT(*) FILTER (WHERE ${sqlIsErrorEvent(alias: 'e')})::int AS errors,
          COUNT(DISTINCT e.user_id) FILTER (WHERE ${identifiedUserSql(alias: 'e')})::int AS users,
          COALESCE(ss.sessions, 0)::int AS sessions,
          COALESCE(ss.avg_ms, 0)::int AS avg_session_ms
        FROM events e
        LEFT JOIN session_stats ss ON ss.release = e.release
        WHERE e.project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND e.release IS NOT NULL
          AND (@since::timestamptz IS NULL OR e.occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR e.occurred_at < @until::timestamptz)
        GROUP BY e.release, ss.sessions, ss.avg_ms
        ORDER BY events DESC
        LIMIT 20
      '''),
      parameters: {'pid': projectId, ...tp},
    );

    return rows.map((r) {
      final events = r[1] as int;
      final crashes = r[2] as int;
      return {
        'release': r[0],
        'events': events,
        'crashes': crashes,
        'errors': r[3],
        'users': r[4],
        'sessions': r[5],
        'avgSessionMs': r[6],
        'crashRatePct': events == 0 ? 0.0 : crashes / events * 100,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listSessions(String projectId, {int days = 7, int limit = 50, TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days);
    final rows = await conn.execute(
      Sql.named('''
        SELECT s.id, s.user_id, s.started_at, s.ended_at, s.duration_ms, s.last_seen_at,
               end_ev.payload->'summary' AS summary,
               end_ev.payload->'reason' AS reason,
               (SELECT release FROM events WHERE project_id = s.project_id AND session_id = s.id AND release IS NOT NULL ORDER BY occurred_at LIMIT 1) AS release,
               (SELECT install_id FROM events WHERE project_id = s.project_id AND session_id = s.id AND install_id IS NOT NULL ORDER BY occurred_at LIMIT 1) AS install_id
        FROM app_sessions s
        LEFT JOIN LATERAL (
          SELECT payload FROM events
          WHERE project_id = s.project_id AND session_id = s.id
            AND type = 'session' AND payload->>'action' = 'end'
          ORDER BY occurred_at DESC LIMIT 1
        ) end_ev ON true
        WHERE s.project_id = @pid
          AND (@since::timestamptz IS NULL OR s.started_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR s.started_at < @until::timestamptz)
        ORDER BY s.started_at DESC
        LIMIT @lim
      '''),
      parameters: {'pid': projectId, 'lim': limit, ...timeParams(w)},
    );

    return rows.map((r) {
      final summary = _jsonField(r[6]);
      final userId = r[1]?.toString();
      final installId = r[9]?.toString();
      return {
        'id': r[0],
        'userId': userId,
        'isGuest': isGuestAppUser(userId: userId, installId: installId),
        'startedAt': (r[2] as DateTime).toUtc().toIso8601String(),
        'endedAt': r[3] != null ? (r[3] as DateTime).toUtc().toIso8601String() : null,
        'lastSeenAt': r[5] != null ? (r[5] as DateTime).toUtc().toIso8601String() : null,
        'durationMs': r[4],
        'release': r[8],
        'reason': _jsonField(r[7])?.toString(),
        'isActive': r[3] == null,
        if (summary is Map) 'summary': Map<String, dynamic>.from(summary),
      };
    }).toList();
  }

  Future<Map<String, dynamic>?> sessionTimeline(String projectId, String sessionId) async {
    final conn = await db.connect();
    final session = await conn.execute(
      Sql.named('''
        SELECT id, user_id, started_at, ended_at, duration_ms, last_seen_at
        FROM app_sessions WHERE project_id = @pid AND id = @sid
      '''),
      parameters: {'pid': projectId, 'sid': sessionId},
    );
    if (session.isEmpty) return null;
    final s = session.first;

    final rows = await conn.execute(
      Sql.named('''
        SELECT payload->'breadcrumbs' AS crumbs, payload->'screenTrail' AS trail, occurred_at
        FROM events
        WHERE project_id = @pid AND session_id = @sid
          AND $sqlHideSessionHeartbeat
        ORDER BY jsonb_array_length(COALESCE(payload->'breadcrumbs', '[]'::jsonb)) DESC, occurred_at DESC
        LIMIT 1
      '''),
      parameters: {'pid': projectId, 'sid': sessionId},
    );

    List<Map<String, dynamic>> timeline = [];
    if (rows.isNotEmpty) {
      timeline = _mergeTrail(_jsonField(rows.first[0]), _jsonField(rows.first[1]));
    }

    return {
      'id': s[0],
      'userId': s[1],
      'startedAt': (s[2] as DateTime).toUtc().toIso8601String(),
      'endedAt': s[3] != null ? (s[3] as DateTime).toUtc().toIso8601String() : null,
      'durationMs': s[4],
      'lastSeenAt': s[5] != null ? (s[5] as DateTime).toUtc().toIso8601String() : null,
      'isActive': s[3] == null,
      'timeline': timeline,
    };
  }

  bool _reachedStep(List<String> routes, List<String> steps, int target) {
    var i = 0;
    for (final r in routes) {
      if (r == steps[i]) {
        if (i == target) return true;
        i++;
      }
    }
    return false;
  }

  List<String> _routesFromTrail(dynamic trail) {
    if (trail is! List) return [];
    return [
      for (final step in trail)
        if (step is Map && step['route'] != null) step['route'].toString(),
    ];
  }

  List<Map<String, dynamic>> _mergeTrail(dynamic crumbs, dynamic trail) {
    final out = <Map<String, dynamic>>[];
    if (crumbs is List) {
      for (final c in crumbs) {
        if (c is Map) out.add(Map<String, dynamic>.from(c));
      }
    }
    if (out.isNotEmpty) return out;

    if (trail is List) {
      for (final step in trail) {
        if (step is! Map) continue;
        final route = step['route']?.toString();
        final nav = step['navigationType'] ?? step['navType'] ?? step['transition'] ?? step['action'];
        out.add({
          if (nav != null) 'navigationType': nav.toString(),
          'type': step['type']?.toString() ?? 'navigation',
          'route': route,
          'label': step['screenName'] ?? route,
          'screenName': step['screenName'] ?? route,
          'at': step['at'],
          if (step['durationMs'] != null) 'durationMs': step['durationMs'],
        });
      }
    }
    return out;
  }

  dynamic _jsonField(dynamic value) {
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  /// Full KPI bundle for the Statistics dashboard page.
  Future<Map<String, dynamic>> projectStats(String projectId, {int days = 7, TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days.clamp(1, 90));
    final period = w.approximateDays;
    final prev = w.previousPeriod();
    final useRollups = preferIdentityRollups(w);

    Future<List<dynamic>> metrics(TimeWindow range) async {
      if (useRollups && preferIdentityRollups(range)) {
        final dp = dateParams(range);
        final daily = await conn.execute(
          Sql.named('''
            SELECT
              COALESCE(SUM(events_total), 0)::int,
              COALESCE(SUM(errors), 0)::int,
              COALESCE(SUM(crashes), 0)::int
            FROM daily_stats
            WHERE project_id = @pid
              AND (@fromDate::date IS NULL OR date >= @fromDate::date)
              AND (@untilDate::date IS NULL OR date < @untilDate::date)
          '''),
          parameters: {'pid': projectId, ...dp},
        );
        final users = await conn.execute(
          Sql.named('''
            SELECT COUNT(DISTINCT user_id)::int
            FROM user_daily_stats
            WHERE project_id = @pid
              AND (@fromDate::date IS NULL OR date >= @fromDate::date)
              AND (@untilDate::date IS NULL OR date < @untilDate::date)
          '''),
          parameters: {'pid': projectId, ...dp},
        );
        final sessions = await conn.execute(
          Sql.named('''
            SELECT COUNT(*)::int FROM app_sessions
            WHERE project_id = @pid
              AND (@since::timestamptz IS NULL OR started_at >= @since::timestamptz)
              AND (@until::timestamptz IS NULL OR started_at < @until::timestamptz)
          '''),
          parameters: {'pid': projectId, ...timeParams(range)},
        );
        final d = daily.first;
        return [d[0], d[1], d[2], 0, 0, 0, 0, users.first[0], sessions.first[0]];
      }

      final rows = await conn.execute(
        Sql.named('''
          SELECT
            COUNT(*)::int,
            COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
            COUNT(*) FILTER (WHERE type = 'crash')::int,
            COUNT(*) FILTER (WHERE type = 'network')::int,
            COUNT(*) FILTER (WHERE type = 'session')::int,
            COUNT(*) FILTER (WHERE type = 'span')::int,
            COUNT(*) FILTER (WHERE type = 'log')::int,
            COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()})::int,
            COUNT(DISTINCT session_id) FILTER (WHERE session_id IS NOT NULL)::int
          FROM events
          WHERE project_id = @pid
            AND $sqlHideSessionHeartbeat
            AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
            AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        '''),
        parameters: {'pid': projectId, ...timeParams(range)},
      );
      return rows.first;
    }

    final cur = await metrics(w);
    final prevM = await metrics(prev);

    final sessions = await conn.execute(
      Sql.named('''
        SELECT
          COUNT(*)::int,
          AVG(duration_ms)::int,
          COUNT(*) FILTER (WHERE ended_at IS NOT NULL)::int
        FROM app_sessions
        WHERE project_id = @pid
          AND (@since::timestamptz IS NULL OR started_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR started_at < @until::timestamptz)
      '''),
      parameters: {'pid': projectId, ...timeParams(w)},
    );
    final sess = sessions.first;

    final openIssues = await conn.execute(
      Sql.named('SELECT COUNT(*)::int FROM issues WHERE project_id = @pid AND status = \'open\''),
      parameters: {'pid': projectId},
    );

    late final List byType;
    late final List byPlatform;
    late final int crashedSessions;
    if (useRollups) {
      crashedSessions = 0; // approximate from crash events below
      byType = const [];
      final platforms = await conn.execute(
        Sql.named('''
          SELECT platform, COUNT(*)::int
          FROM device_stats
          WHERE project_id = @pid AND platform IS NOT NULL
            AND (@since::timestamptz IS NULL OR last_seen_at >= @since::timestamptz)
            AND (@until::timestamptz IS NULL OR last_seen_at < @until::timestamptz)
          GROUP BY platform ORDER BY 2 DESC LIMIT 8
        '''),
        parameters: {'pid': projectId, ...timeParams(w)},
      );
      byPlatform = platforms;
    } else {
      final crashSessions = await conn.execute(
        Sql.named('''
          SELECT COUNT(DISTINCT session_id)::int
          FROM events
          WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND type = 'crash' AND session_id IS NOT NULL
            AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
            AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        '''),
        parameters: {'pid': projectId, ...timeParams(w)},
      );
      crashedSessions = crashSessions.first[0] as int;
      byType = await conn.execute(
        Sql.named('''
          SELECT type, COUNT(*)::int FROM events
          WHERE project_id = @pid
            AND $sqlHideSessionHeartbeat
            AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
            AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
          GROUP BY type ORDER BY COUNT(*) DESC
        '''),
        parameters: {'pid': projectId, ...timeParams(w)},
      );
      byPlatform = await conn.execute(
        Sql.named('''
          SELECT platform, COUNT(*)::int FROM events
          WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND platform IS NOT NULL
            AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
            AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
          GROUP BY platform ORDER BY COUNT(*) DESC LIMIT 8
        '''),
        parameters: {'pid': projectId, ...timeParams(w)},
      );
    }

    final trend = await fetchEventTrend(conn, projectId, w, includeUsers: true);

    int n(dynamic v) => v == null ? 0 : (v is int ? v : (v as num).toInt());
    double delta(num current, num previous) =>
        previous == 0 ? (current == 0 ? 0.0 : 100.0) : ((current - previous) / previous * 100);

    final totalSessions = n(sess[0]);
    final events = n(cur[0]);
    final errors = n(cur[1]);
    final crashes = n(cur[2]);
    // Rollup path: approximate crash-free from crash events vs sessions (not distinct crash sessions).
    final crashed = useRollups ? crashes.clamp(0, totalSessions) : crashedSessions;

    return {
      'days': period,
      'events': n(cur[0]),
      'errors': n(cur[1]),
      'crashes': crashes,
      'networkEvents': n(cur[3]),
      'sessionEvents': n(cur[4]),
      'spans': n(cur[5]),
      'logs': n(cur[6]),
      'uniqueUsers': n(cur[7]),
      'uniqueSessions': n(cur[8]),
      'completedSessions': n(totalSessions),
      'avgSessionDurationMs': sess[1] == null ? null : n(sess[1]),
      'openIssues': n(openIssues.first[0]),
      'crashFreeRatePct': totalSessions == 0 ? 100.0 : ((totalSessions - crashed) / totalSessions * 100),
      'errorRatePct': events == 0 ? 0.0 : (errors / events * 100),
      'deltas': {
        'events': delta(n(cur[0]), n(prevM[0])),
        'errors': delta(n(cur[1]), n(prevM[1])),
        'crashes': delta(n(cur[2]), n(prevM[2])),
        'uniqueUsers': delta(n(cur[7]), n(prevM[7])),
      },
      'byType': byType.map((r) => {'type': r[0], 'count': r[1]}).toList(),
      'byPlatform': byPlatform.map((r) => {'platform': r[0], 'count': r[1]}).toList(),
      'trendGranularity': trendGranularity(w),
      'dailyTrend': trend,
    };
  }

  /// Extended breakdowns for unified dashboard (peak hours, top endpoints/screens, etc.).
  Future<Map<String, dynamic>> dashboardInsights(String projectId, {int days = 7, TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days.clamp(1, 90));
    // Multi-day: avoid full events JSON scans — those are the 20s+ waits on Overview.
    if (preferIdentityRollups(w)) {
      return _dashboardInsightsFromRollups(conn, projectId, w);
    }
    return _dashboardInsightsFromEvents(conn, projectId, w);
  }

  Future<Map<String, dynamic>> _dashboardInsightsFromRollups(
    Connection conn,
    String projectId,
    TimeWindow w,
  ) async {
    final dp = dateParams(w);
    final tp = timeParams(w);
    final usersAffected = await conn.execute(
      Sql.named('''
        SELECT COUNT(DISTINCT user_id)::int
        FROM user_daily_stats
        WHERE project_id = @pid AND error_count > 0
          AND (@fromDate::date IS NULL OR date >= @fromDate::date)
          AND (@untilDate::date IS NULL OR date < @untilDate::date)
      '''),
      parameters: {'pid': projectId, ...dp},
    );
    final byEnv = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF(environment, ''), 'unknown') AS environment, COUNT(*)::int
        FROM user_stats
        WHERE project_id = @pid
          AND (@since::timestamptz IS NULL OR last_seen_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR last_seen_at < @until::timestamptz)
        GROUP BY 1 ORDER BY 2 DESC
      '''),
      parameters: {'pid': projectId, ...tp},
    );
    final byRelease = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF(release, ''), 'unknown') AS release, COUNT(*)::int
        FROM user_stats
        WHERE project_id = @pid AND release IS NOT NULL
          AND (@since::timestamptz IS NULL OR last_seen_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR last_seen_at < @until::timestamptz)
        GROUP BY 1 ORDER BY 2 DESC LIMIT 12
      '''),
      parameters: {'pid': projectId, ...tp},
    );
    final errorDevices = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF(d.device_name, ''), 'unknown') AS device,
               COALESCE(SUM(dd.error_count), 0)::int,
               COUNT(DISTINCT d.install_id)::int
        FROM device_stats d
        INNER JOIN device_daily_stats dd
          ON dd.project_id = d.project_id AND dd.install_id = d.install_id
         AND (@fromDate::date IS NULL OR dd.date >= @fromDate::date)
         AND (@untilDate::date IS NULL OR dd.date < @untilDate::date)
        WHERE d.project_id = @pid AND dd.error_count > 0
        GROUP BY 1 ORDER BY 2 DESC LIMIT 10
      '''),
      parameters: {'pid': projectId, ...dp},
    );
    final n = (dynamic v) => v == null ? 0 : (v is int ? v : (v as num).toInt());
    return {
      'usersAffectedByErrors': n(usersAffected.first[0]),
      'peakHour': null,
      'peakHourEvents': 0,
      'peakErrorHour': null,
      'peakErrorHourCount': 0,
      'hourlyActivity': const <Map<String, dynamic>>[],
      'topFailingEndpoints': const <Map<String, dynamic>>[],
      'topCrashScreens': const <Map<String, dynamic>>[],
      'topErrorDevices': errorDevices.map((r) => {'device': r[0], 'count': r[1], 'installs': r[2]}).toList(),
      'byEnvironment': byEnv.map((r) => {'environment': r[0], 'count': r[1]}).toList(),
      'eventsByRelease': byRelease.map((r) => {'release': r[0], 'count': r[1], 'errors': 0, 'crashes': 0}).toList(),
      'byDeployment': const <Map<String, dynamic>>[],
      'insightsLite': true,
    };
  }

  Future<Map<String, dynamic>> _dashboardInsightsFromEvents(
    Connection conn,
    String projectId,
    TimeWindow w,
  ) async {
    final tp = timeParams(w);
    final p = {'pid': projectId, ...tp};

    final usersAffected = await conn.execute(
      Sql.named('''
        SELECT COUNT(DISTINCT user_id)::int
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND ${identifiedUserSql()}
          AND ${sqlIsErrorEvent()}
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      '''),
      parameters: p,
    );

    final hourly = await conn.execute(
      Sql.named('''
        SELECT EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'UTC')::int AS h,
               COUNT(*)::int,
               COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
               COUNT(*) FILTER (WHERE ${sqlIsSuccessEvent()})::int
        FROM events WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY 1 ORDER BY 1
      '''),
      parameters: p,
    );

    final endpoints = await conn.execute(
      Sql.named('''
        SELECT payload->'network'->>'url' AS endpoint, COUNT(*)::int
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
          AND payload->'network'->>'url' IS NOT NULL
          AND ${sqlIsErrorEvent()}
        GROUP BY endpoint ORDER BY 2 DESC LIMIT 10
      '''),
      parameters: p,
    );

    final screens = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF(payload->'screen'->>'currentRoute', ''), 'unknown') AS screen, COUNT(*)::int
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND type = 'crash'
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY screen ORDER BY 2 DESC LIMIT 10
      '''),
      parameters: p,
    );

    final devices = await conn.execute(
      Sql.named('''
        SELECT ${sqlDeviceNameExpr()} AS device,
               COUNT(*)::int,
               COUNT(DISTINCT install_id) FILTER (WHERE install_id IS NOT NULL)::int
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND ${sqlIsErrorEvent()}
          AND ${sqlDeviceNameExpr()} IS NOT NULL AND ${sqlDeviceNameExpr()} <> ''
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY device ORDER BY 2 DESC LIMIT 10
      '''),
      parameters: p,
    );

    final byEnv = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF(environment, ''), 'unknown') AS environment, COUNT(*)::int
        FROM events WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY environment ORDER BY 2 DESC
      '''),
      parameters: p,
    );

    final byRelease = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF(release, ''), 'unknown') AS release,
               COUNT(*)::int,
               COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
               COUNT(*) FILTER (WHERE type = 'crash')::int
        FROM events WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY release ORDER BY 2 DESC LIMIT 12
      '''),
      parameters: p,
    );

    final byDeploy = await conn.execute(
      Sql.named('''
        SELECT COALESCE(
          NULLIF(payload->'custom'->>'deployment', ''),
          NULLIF(payload->'custom'->>'deploymentTag', ''),
          NULLIF(payload->'custom'->>'deployTag', '')
        ) AS tag, COUNT(*)::int
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
          AND COALESCE(
            NULLIF(payload->'custom'->>'deployment', ''),
            NULLIF(payload->'custom'->>'deploymentTag', ''),
            NULLIF(payload->'custom'->>'deployTag', '')
          ) IS NOT NULL
        GROUP BY tag ORDER BY 2 DESC LIMIT 10
      '''),
      parameters: p,
    );

    int n(dynamic v) => v == null ? 0 : (v is int ? v : (v as num).toInt());

    int? peakHour, peakErrorHour;
    var peakHourEvents = 0, peakErrorHourCount = 0;
    for (final r in hourly) {
      final ev = n(r[1]), err = n(r[2]);
      if (ev > peakHourEvents) (peakHourEvents, peakHour) = (ev, n(r[0]));
      if (err > peakErrorHourCount) (peakErrorHourCount, peakErrorHour) = (err, n(r[0]));
    }

    return {
      'usersAffectedByErrors': n(usersAffected.first[0]),
      'peakHour': peakHour,
      'peakHourEvents': peakHourEvents,
      'peakErrorHour': peakErrorHour,
      'peakErrorHourCount': peakErrorHourCount,
      'hourlyActivity': hourly.map((r) => {'hour': r[0], 'events': r[1], 'errors': r[2], 'success': r[3]}).toList(),
      'topFailingEndpoints': endpoints.map((r) => {'endpoint': r[0], 'count': r[1]}).toList(),
      'topCrashScreens': screens.map((r) => {'screen': r[0], 'count': r[1]}).toList(),
      'topErrorDevices': devices.map((r) => {'device': r[0], 'count': r[1], 'installs': r[2]}).toList(),
      'byEnvironment': byEnv.map((r) => {'environment': r[0], 'count': r[1]}).toList(),
      'eventsByRelease': byRelease.map((r) => {'release': r[0], 'count': r[1], 'errors': r[2], 'crashes': r[3]}).toList(),
      'byDeployment': byDeploy.map((r) => {'tag': r[0], 'count': r[1]}).toList(),
    };
  }

  Future<List<Map<String, dynamic>>> listUsers(
    String projectId, {
    int days = 30,
    int limit = 100,
    TimeWindow? window,
    String? q,
  }) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days.clamp(1, 90));
    final query = q?.trim();
    final qParam = query == null || query.isEmpty ? null : query;

    if (preferIdentityRollups(w)) {
      final rows = await conn.execute(
        Sql.named('''
          SELECT u.user_id,
                 u.first_seen_at,
                 u.last_seen_at,
                 COALESCE(SUM(d.event_count), 0)::int,
                 COALESCE(SUM(d.error_count), 0)::int,
                 COALESCE(SUM(d.crash_count), 0)::int,
                 (SELECT COUNT(*)::int FROM user_device_links l
                  WHERE l.project_id = u.project_id AND l.user_id = u.user_id
                    AND (@since::timestamptz IS NULL OR l.last_seen_at >= @since::timestamptz)
                    AND (@until::timestamptz IS NULL OR l.last_seen_at < @until::timestamptz)),
                 u.email, u.display_name, u.phone, u.username,
                 u.platform, u.app_version, u.environment, u.release, u.country,
                 u.device_name, u.locale, u.last_route, u.install_id
          FROM user_stats u
          INNER JOIN user_daily_stats d
            ON d.project_id = u.project_id AND d.user_id = u.user_id
           AND (@fromDate::date IS NULL OR d.date >= @fromDate::date)
           AND (@untilDate::date IS NULL OR d.date < @untilDate::date)
          WHERE u.project_id = @pid
            AND (
              @q::text IS NULL
              OR u.user_id ILIKE '%' || @q::text || '%'
              OR u.email ILIKE '%' || @q::text || '%'
              OR u.display_name ILIKE '%' || @q::text || '%'
              OR u.phone ILIKE '%' || @q::text || '%'
              OR u.username ILIKE '%' || @q::text || '%'
              OR u.device_name ILIKE '%' || @q::text || '%'
              OR u.country ILIKE '%' || @q::text || '%'
              OR u.install_id ILIKE '%' || @q::text || '%'
              OR EXISTS (
                SELECT 1 FROM user_device_links l
                LEFT JOIN device_stats ds
                  ON ds.project_id = l.project_id AND ds.install_id = l.install_id
                WHERE l.project_id = u.project_id AND l.user_id = u.user_id
                  AND (
                    l.install_id ILIKE '%' || @q::text || '%'
                    OR ds.device_name ILIKE '%' || @q::text || '%'
                    OR ds.platform ILIKE '%' || @q::text || '%'
                  )
              )
            )
          GROUP BY u.project_id, u.user_id, u.first_seen_at, u.last_seen_at,
                   u.email, u.display_name, u.phone, u.username,
                   u.platform, u.app_version, u.environment, u.release, u.country,
                   u.device_name, u.locale, u.last_route, u.install_id
          ORDER BY u.last_seen_at DESC
          LIMIT @lim
        '''),
        parameters: {
          'pid': projectId,
          ...timeParams(w),
          ...dateParams(w),
          'lim': limit,
          'q': qParam,
        },
      );
      return rows
          .map((r) => {
                'userId': r[0],
                'identified': true,
                'firstSeenAt': (r[1] as DateTime).toUtc().toIso8601String(),
                'lastSeenAt': (r[2] as DateTime).toUtc().toIso8601String(),
                'eventCount': r[3],
                'errorCount': r[4],
                'crashCount': r[5],
                'sessionCount': 0,
                'deviceCount': r[6],
                'email': r[7],
                'displayName': r[8],
                'phone': r[9],
                'username': r[10],
                'platform': r[11],
                'appVersion': r[12],
                'environment': r[13],
                'release': r[14],
                'country': r[15],
                'deviceName': r[16],
                'locale': r[17],
                'lastRoute': r[18],
                'installId': r[19],
              })
          .toList();
    }

    final rows = await conn.execute(
      Sql.named('''
        SELECT user_id,
               MIN(occurred_at) AS first_seen,
               MAX(occurred_at) AS last_seen,
               COUNT(*)::int,
               COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
               COUNT(*) FILTER (WHERE type = 'crash')::int,
               COUNT(DISTINCT session_id) FILTER (WHERE session_id IS NOT NULL)::int,
               COUNT(DISTINCT install_id) FILTER (WHERE install_id IS NOT NULL)::int,
               MAX(NULLIF(TRIM(payload->'user'->>'email'), '')) AS email,
               MAX(NULLIF(TRIM(payload->'user'->>'name'), '')) AS display_name,
               MAX(NULLIF(TRIM(payload->'user'->>'phone'), '')) AS phone,
               MAX(NULLIF(TRIM(payload->'user'->>'username'), '')) AS username,
               MAX(platform) AS platform,
               MAX(app_version) AS app_version,
               MAX(environment) AS environment,
               MAX(release) AS release,
               MAX(country) AS country,
               MAX(COALESCE(NULLIF(payload->'device'->>'deviceName', ''),
                            NULLIF(payload->'device'->>'deviceModel', ''),
                            NULLIF(payload->'device'->>'model', ''))) AS device_name,
               MAX(COALESCE(NULLIF(payload->'device'->'geo'->>'locale', ''),
                            NULLIF(payload->'device'->>'locale', ''))) AS locale,
               (SELECT e2.payload->'screen'->>'currentRoute'
                FROM events e2
                WHERE e2.project_id = @pid AND e2.user_id = events.user_id
                  AND e2.payload->'screen'->>'currentRoute' IS NOT NULL
                  AND e2.payload->'screen'->>'currentRoute' <> ''
                ORDER BY e2.occurred_at DESC LIMIT 1) AS last_route,
               (SELECT e2.install_id
                FROM events e2
                WHERE e2.project_id = @pid AND e2.user_id = events.user_id
                  AND e2.install_id IS NOT NULL AND e2.user_id <> e2.install_id
                ORDER BY e2.occurred_at DESC LIMIT 1) AS install_id
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND ${identifiedUserSql()}
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
          AND (
            @q::text IS NULL
            OR user_id ILIKE '%' || @q::text || '%'
            OR install_id ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'user'->>'email'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'user'->>'name'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'user'->>'phone'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'user'->>'username'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'device'->>'deviceName'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'device'->>'deviceModel'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'device'->>'model'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'device'->>'deviceId'), '') ILIKE '%' || @q::text || '%'
            OR country ILIKE '%' || @q::text || '%'
          )
        GROUP BY user_id
        ORDER BY MAX(occurred_at) DESC
        LIMIT @lim
      '''),
      parameters: {
        'pid': projectId,
        ...timeParams(w),
        'lim': limit,
        'q': qParam,
      },
    );
    return rows
        .map((r) => {
              'userId': r[0],
              'identified': true,
              'email': r[8],
              'displayName': r[9],
              'phone': r[10],
              'username': r[11],
              'platform': r[12],
              'appVersion': r[13],
              'environment': r[14],
              'release': r[15],
              'country': r[16],
              'deviceName': r[17],
              'locale': r[18],
              'lastRoute': r[19],
              'installId': r[20],
              'firstSeenAt': (r[1] as DateTime).toUtc().toIso8601String(),
              'lastSeenAt': (r[2] as DateTime).toUtc().toIso8601String(),
              'eventCount': r[3],
              'errorCount': r[4],
              'crashCount': r[5],
              'sessionCount': r[6],
              'deviceCount': r[7],
            })
        .toList();
  }

  Future<Map<String, dynamic>?> getUser(String projectId, String userId, {int days = 30, TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days.clamp(1, 90));
    final tp = timeParams(w);
    final guestSql = guestUserSql();

    final stats = await conn.execute(
      Sql.named('''
        WITH user_installs AS (
          SELECT DISTINCT install_id
          FROM events
          WHERE project_id = @pid AND user_id = @uid AND install_id IS NOT NULL AND user_id <> install_id
        ),
        merged AS (
          SELECT type, occurred_at, country, payload
          FROM events
          WHERE project_id = @pid
            AND $sqlHideSessionHeartbeat
            AND (
              user_id = @uid
              OR (
                install_id IN (SELECT install_id FROM user_installs)
                AND $guestSql
              )
            )
            AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
            AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        )
        SELECT
          COUNT(*)::int,
          COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
          COUNT(*) FILTER (WHERE type = 'crash')::int,
          MIN(occurred_at),
          MAX(occurred_at),
          MAX(country)
        FROM merged
      '''),
      parameters: {'pid': projectId, 'uid': userId, ...tp},
    );
    if (stats.isEmpty || stats.first[0] == 0) return null;

    final guestOnly = await conn.execute(
      Sql.named('''
        WITH user_installs AS (
          SELECT DISTINCT install_id
          FROM events
          WHERE project_id = @pid AND user_id = @uid AND install_id IS NOT NULL AND user_id <> install_id
        )
        SELECT COUNT(*)::int
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND install_id IN (SELECT install_id FROM user_installs)
          AND $guestSql
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      '''),
      parameters: {'pid': projectId, 'uid': userId, ...tp},
    );

    final sessions = await conn.execute(
      Sql.named('''
        SELECT COUNT(*)::int FROM app_sessions
        WHERE project_id = @pid AND user_id = @uid
          AND (@since::timestamptz IS NULL OR started_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR started_at < @until::timestamptz)
      '''),
      parameters: {'pid': projectId, 'uid': userId, ...tp},
    );

    final devices = await conn.execute(
      Sql.named('''
        SELECT install_id,
               MAX(COALESCE(payload->'device'->>'deviceName', payload->'device'->>'deviceModel')) AS device_name,
               MAX(platform) AS platform,
               MIN(occurred_at) AS first_seen,
               MAX(occurred_at) AS last_seen,
               COUNT(*)::int
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND user_id = @uid AND install_id IS NOT NULL AND user_id <> install_id
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY install_id
        ORDER BY MAX(occurred_at) DESC
      '''),
      parameters: {'pid': projectId, 'uid': userId, ...tp},
    );

    final recent = await conn.execute(
      Sql.named('''
        WITH user_installs AS (
          SELECT DISTINCT install_id
          FROM events
          WHERE project_id = @pid AND user_id = @uid AND install_id IS NOT NULL AND user_id <> install_id
        )
        SELECT id, type, occurred_at, message, release, platform, environment, app_version,
               payload->'screen'->>'currentRoute' AS route,
               COALESCE(payload->'device'->>'deviceName', payload->'device'->>'model') AS device_name,
               payload->'network'->>'url' AS network_url,
               payload->'network'->>'statusCode' AS status_code,
               payload->>'category' AS category,
               payload->>'level' AS level,
               user_id,
               install_id
        FROM events
        WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (
            user_id = @uid
            OR (
              install_id IN (SELECT install_id FROM user_installs)
              AND $guestSql
            )
          )
        ORDER BY occurred_at DESC LIMIT 20
      '''),
      parameters: {'pid': projectId, 'uid': userId},
    );

    final profile = await conn.execute(
      Sql.named('''
        SELECT MAX(NULLIF(TRIM(payload->'user'->>'email'), '')),
               MAX(NULLIF(TRIM(payload->'user'->>'name'), '')),
               MAX(NULLIF(TRIM(payload->'user'->>'phone'), '')),
               MAX(NULLIF(TRIM(payload->'user'->>'username'), '')),
               MAX(platform),
               MAX(environment),
               MAX(release),
               MAX(country),
               MAX(COALESCE(NULLIF(payload->'device'->>'deviceName', ''),
                            NULLIF(payload->'device'->>'deviceModel', ''),
                            NULLIF(payload->'device'->>'model', ''))),
               MAX(COALESCE(NULLIF(payload->'device'->'geo'->>'locale', ''),
                            NULLIF(payload->'device'->>'locale', ''))),
               (SELECT e2.payload->'screen'->>'currentRoute'
                FROM events e2
                WHERE e2.project_id = @pid AND e2.user_id = @uid
                  AND e2.payload->'screen'->>'currentRoute' IS NOT NULL
                  AND e2.payload->'screen'->>'currentRoute' <> ''
                ORDER BY e2.occurred_at DESC LIMIT 1),
               (SELECT e2.install_id
                FROM events e2
                WHERE e2.project_id = @pid AND e2.user_id = @uid
                  AND e2.install_id IS NOT NULL AND e2.user_id <> e2.install_id
                ORDER BY e2.occurred_at DESC LIMIT 1)
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND user_id = @uid
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      '''),
      parameters: {'pid': projectId, 'uid': userId, ...tp},
    );

    // Last version by time (not MAX text) — for support "does this user need an update?"
    final lastVersion = await conn.execute(
      Sql.named('''
        SELECT app_version,
               COALESCE(
                 NULLIF(payload->'device'->>'buildNumber', ''),
                 NULLIF(payload->'device'->>'build', ''),
                 NULLIF(payload->'release'->>'buildNumber', '')
               ) AS build_number,
               platform,
               environment,
               release,
               occurred_at
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND user_id = @uid
          AND app_version IS NOT NULL AND TRIM(app_version) <> ''
        ORDER BY occurred_at DESC
        LIMIT 1
      '''),
      parameters: {'pid': projectId, 'uid': userId},
    );

    final versionHistory = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF(TRIM(app_version), ''), 'unknown') AS ver,
               (ARRAY_AGG(
                 COALESCE(
                   NULLIF(payload->'device'->>'buildNumber', ''),
                   NULLIF(payload->'device'->>'build', '')
                 ) ORDER BY occurred_at DESC
               ) FILTER (WHERE
                 NULLIF(payload->'device'->>'buildNumber', '') IS NOT NULL
                 OR NULLIF(payload->'device'->>'build', '') IS NOT NULL
               ))[1] AS build_number,
               MIN(occurred_at) AS first_seen,
               MAX(occurred_at) AS last_seen,
               COUNT(*)::int,
               (ARRAY_AGG(platform ORDER BY occurred_at DESC) FILTER (WHERE platform IS NOT NULL))[1] AS platform
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND user_id = @uid
          AND app_version IS NOT NULL AND TRIM(app_version) <> ''
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY 1
        ORDER BY MAX(occurred_at) DESC
        LIMIT 8
      '''),
      parameters: {'pid': projectId, 'uid': userId, ...tp},
    );

    final s = stats.first;
    final p = profile.first;
    final guestEvents = guestOnly.first[0] as int;
    final lv = lastVersion.isEmpty ? null : lastVersion.first;
    final lastAppVersion = lv?[0]?.toString();
    final lastBuild = lv?[1]?.toString();
    String? lastAppVersionLabel;
    if (lastAppVersion != null && lastAppVersion.isNotEmpty) {
      if (lastAppVersion.contains('+') || lastBuild == null || lastBuild.isEmpty) {
        lastAppVersionLabel = lastAppVersion;
      } else {
        lastAppVersionLabel = '$lastAppVersion+$lastBuild';
      }
    }

    return {
      'userId': userId,
      'identified': true,
      'email': p[0],
      'displayName': p[1],
      'phone': p[2],
      'username': p[3],
      'platform': lv?[2] ?? p[4],
      'appVersion': lastAppVersion,
      'lastAppVersion': lastAppVersion,
      'lastBuildNumber': lastBuild,
      'lastAppVersionLabel': lastAppVersionLabel,
      'lastAppVersionSeenAt': lv?[5] == null ? null : (lv![5] as DateTime).toUtc().toIso8601String(),
      'environment': lv?[3] ?? p[5],
      'release': lv?[4] ?? p[6],
      'topCountry': p[7],
      'deviceName': p[8],
      'locale': p[9],
      'lastRoute': p[10],
      'installId': p[11],
      'includesGuestActivity': guestEvents > 0,
      'guestEventCount': guestEvents,
      'days': w.approximateDays,
      'eventCount': s[0],
      'errorCount': s[1],
      'crashCount': s[2],
      'firstSeenAt': (s[3] as DateTime).toUtc().toIso8601String(),
      'lastSeenAt': (s[4] as DateTime).toUtc().toIso8601String(),
      'sessionCount': sessions.first[0],
      'deviceCount': devices.length,
      'appVersions': versionHistory
          .map((r) {
            final ver = r[0]?.toString() ?? 'unknown';
            final build = r[1]?.toString();
            final label = ver.contains('+') || build == null || build.isEmpty ? ver : '$ver+$build';
            return {
              'appVersion': ver,
              'buildNumber': build,
              'label': label,
              'firstSeenAt': (r[2] as DateTime).toUtc().toIso8601String(),
              'lastSeenAt': (r[3] as DateTime).toUtc().toIso8601String(),
              'eventCount': r[4],
              'platform': r[5],
            };
          })
          .toList(),
      'devices': devices
          .map((r) => {
                'installId': r[0],
                'deviceName': r[1],
                'platform': r[2],
                'firstSeenAt': (r[3] as DateTime).toUtc().toIso8601String(),
                'lastSeenAt': (r[4] as DateTime).toUtc().toIso8601String(),
                'eventCount': r[5],
              })
          .toList(),
      'recentEvents': recent
          .map((r) {
            final uid = r[14]?.toString();
            final iid = r[15]?.toString();
            return {
              'id': r[0],
              'type': r[1],
              'occurredAt': (r[2] as DateTime).toUtc().toIso8601String(),
              'message': r[3],
              'release': r[4],
              'platform': r[5],
              'environment': r[6],
              'appVersion': r[7],
              'route': r[8],
              'deviceName': r[9],
              'networkUrl': r[10],
              'statusCode': r[11]?.toString(),
              'category': r[12],
              'level': r[13],
              'isGuest': isGuestAppUser(userId: uid, installId: iid),
            };
          })
          .toList(),
    };
  }

  Future<List<Map<String, dynamic>>> listDevices(
    String projectId, {
    int days = 30,
    int limit = 100,
    TimeWindow? window,
    String? q,
  }) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days.clamp(1, 90));
    final query = q?.trim();
    final qParam = query == null || query.isEmpty ? null : query;

    if (preferIdentityRollups(w)) {
      final rows = await conn.execute(
        Sql.named('''
          SELECT d.install_id,
                 d.first_seen_at,
                 d.last_seen_at,
                 COALESCE(SUM(dd.event_count), 0)::int,
                 COALESCE(SUM(dd.error_count), 0)::int,
                 COALESCE(SUM(dd.crash_count), 0)::int,
                 COALESCE(SUM(dd.guest_event_count), 0)::int,
                 (SELECT COUNT(DISTINCT l.user_id)::int FROM user_device_links l
                  WHERE l.project_id = d.project_id AND l.install_id = d.install_id
                    AND (@since::timestamptz IS NULL OR l.last_seen_at >= @since::timestamptz)
                    AND (@until::timestamptz IS NULL OR l.last_seen_at < @until::timestamptz)),
                 d.device_name, d.platform, d.app_version, d.environment, d.country
          FROM device_stats d
          INNER JOIN device_daily_stats dd
            ON dd.project_id = d.project_id AND dd.install_id = d.install_id
           AND (@fromDate::date IS NULL OR dd.date >= @fromDate::date)
           AND (@untilDate::date IS NULL OR dd.date < @untilDate::date)
          WHERE d.project_id = @pid
            AND (
              @q::text IS NULL
              OR d.install_id ILIKE '%' || @q::text || '%'
              OR d.device_name ILIKE '%' || @q::text || '%'
              OR d.platform ILIKE '%' || @q::text || '%'
              OR d.country ILIKE '%' || @q::text || '%'
              OR EXISTS (
                SELECT 1 FROM user_device_links l
                LEFT JOIN user_stats us
                  ON us.project_id = l.project_id AND us.user_id = l.user_id
                WHERE l.project_id = d.project_id AND l.install_id = d.install_id
                  AND (
                    l.user_id ILIKE '%' || @q::text || '%'
                    OR us.email ILIKE '%' || @q::text || '%'
                    OR us.display_name ILIKE '%' || @q::text || '%'
                    OR us.phone ILIKE '%' || @q::text || '%'
                    OR us.username ILIKE '%' || @q::text || '%'
                  )
              )
            )
          GROUP BY d.project_id, d.install_id, d.first_seen_at, d.last_seen_at,
                   d.device_name, d.platform, d.app_version, d.environment, d.country
          ORDER BY d.last_seen_at DESC
          LIMIT @lim
        '''),
        parameters: {
          'pid': projectId,
          ...timeParams(w),
          ...dateParams(w),
          'lim': limit,
          'q': qParam,
        },
      );
      return rows
          .map((r) {
            final userCount = r[7] as int;
            final guestEvents = r[6] as int;
            return {
              'installId': r[0],
              'firstSeenAt': (r[1] as DateTime).toUtc().toIso8601String(),
              'lastSeenAt': (r[2] as DateTime).toUtc().toIso8601String(),
              'eventCount': r[3],
              'errorCount': r[4],
              'crashCount': r[5],
              'sessionCount': 0,
              'guestEventCount': guestEvents,
              'userCount': userCount,
              'deviceName': r[8],
              'platform': r[9],
              'appVersion': r[10],
              'environment': r[11],
              'country': r[12],
              'guestOnly': userCount == 0 && guestEvents > 0,
            };
          })
          .toList();
    }

    final rows = await conn.execute(
      Sql.named('''
        SELECT install_id,
               MIN(occurred_at) AS first_seen,
               MAX(occurred_at) AS last_seen,
               COUNT(*)::int,
               COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
               COUNT(*) FILTER (WHERE type = 'crash')::int,
               COUNT(DISTINCT session_id) FILTER (WHERE session_id IS NOT NULL)::int,
               COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()})::int,
               COUNT(*) FILTER (WHERE ${guestUserSql()})::int,
               MAX(COALESCE(NULLIF(payload->'device'->>'deviceName', ''),
                            NULLIF(payload->'device'->>'deviceModel', ''),
                            NULLIF(payload->'device'->>'model', ''))) AS device_name,
               MAX(platform) AS platform,
               MAX(app_version) AS app_version,
               MAX(environment) AS environment,
               MAX(country) AS country
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND install_id IS NOT NULL
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
          AND (
            @q::text IS NULL
            OR install_id ILIKE '%' || @q::text || '%'
            OR user_id ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'device'->>'deviceName'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'device'->>'deviceModel'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'device'->>'model'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'device'->>'deviceId'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'user'->>'email'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'user'->>'name'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'user'->>'phone'), '') ILIKE '%' || @q::text || '%'
            OR NULLIF(TRIM(payload->'user'->>'username'), '') ILIKE '%' || @q::text || '%'
            OR platform ILIKE '%' || @q::text || '%'
            OR country ILIKE '%' || @q::text || '%'
          )
        GROUP BY install_id
        ORDER BY MAX(occurred_at) DESC
        LIMIT @lim
      '''),
      parameters: {
        'pid': projectId,
        ...timeParams(w),
        'lim': limit,
        'q': qParam,
      },
    );
    return rows
        .map((r) => {
              'installId': r[0],
              'firstSeenAt': (r[1] as DateTime).toUtc().toIso8601String(),
              'lastSeenAt': (r[2] as DateTime).toUtc().toIso8601String(),
              'eventCount': r[3],
              'errorCount': r[4],
              'crashCount': r[5],
              'sessionCount': r[6],
              'userCount': r[7],
              'guestEventCount': r[8],
              'deviceName': r[9],
              'platform': r[10],
              'appVersion': r[11],
              'environment': r[12],
              'country': r[13],
              'guestOnly': (r[7] as int) == 0 && (r[8] as int) > 0,
            })
        .toList();
  }

  Future<Map<String, dynamic>?> getDevice(String projectId, String installId, {int days = 30, TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days.clamp(1, 90));
    final tp = timeParams(w);

    final stats = await conn.execute(
      Sql.named('''
        SELECT
          COUNT(*)::int,
          COUNT(*) FILTER (WHERE ${sqlIsErrorEvent()})::int,
          COUNT(*) FILTER (WHERE type = 'crash')::int,
          MIN(occurred_at),
          MAX(occurred_at),
          COUNT(DISTINCT session_id) FILTER (WHERE session_id IS NOT NULL)::int,
          COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()})::int,
          COUNT(*) FILTER (WHERE ${guestUserSql()})::int,
          MAX(COALESCE(NULLIF(payload->'device'->>'deviceName', ''),
                       NULLIF(payload->'device'->>'deviceModel', ''),
                       NULLIF(payload->'device'->>'model', ''))),
          MAX(platform),
          MAX(app_version),
          MAX(environment),
          MAX(release),
          MAX(country),
          MAX(COALESCE(NULLIF(payload->'device'->'geo'->>'locale', ''),
                       NULLIF(payload->'device'->>'locale', '')))
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND install_id = @iid
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      '''),
      parameters: {'pid': projectId, 'iid': installId, ...tp},
    );
    if (stats.isEmpty || stats.first[0] == 0) return null;

    final users = await conn.execute(
      Sql.named('''
        SELECT user_id,
               MAX(NULLIF(TRIM(payload->'user'->>'email'), '')) AS email,
               MAX(NULLIF(TRIM(payload->'user'->>'name'), '')) AS display_name,
               MAX(NULLIF(TRIM(payload->'user'->>'username'), '')) AS username,
               MIN(occurred_at) AS first_seen,
               MAX(occurred_at) AS last_seen,
               COUNT(*)::int
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND install_id = @iid AND ${identifiedUserSql()}
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY user_id
        ORDER BY MAX(occurred_at) DESC
      '''),
      parameters: {'pid': projectId, 'iid': installId, ...tp},
    );

    final recent = await conn.execute(
      Sql.named('''
        SELECT id, type, occurred_at, message, release, platform, environment, app_version,
               payload->'screen'->>'currentRoute' AS route,
               COALESCE(payload->'device'->>'deviceName', payload->'device'->>'model') AS device_name,
               payload->'network'->>'url' AS network_url,
               payload->'network'->>'statusCode' AS status_code,
               payload->>'category' AS category,
               payload->>'level' AS level,
               user_id,
               install_id
        FROM events
        WHERE project_id = @pid AND $sqlHideSessionHeartbeat AND install_id = @iid
        ORDER BY occurred_at DESC LIMIT 20
      '''),
      parameters: {'pid': projectId, 'iid': installId},
    );

    final s = stats.first;
    final userCount = s[6] as int;
    final guestEvents = s[7] as int;
    return {
      'installId': installId,
      'deviceName': s[8],
      'platform': s[9],
      'appVersion': s[10],
      'environment': s[11],
      'release': s[12],
      'topCountry': s[13],
      'locale': s[14],
      'days': w.approximateDays,
      'eventCount': s[0],
      'errorCount': s[1],
      'crashCount': s[2],
      'firstSeenAt': (s[3] as DateTime).toUtc().toIso8601String(),
      'lastSeenAt': (s[4] as DateTime).toUtc().toIso8601String(),
      'sessionCount': s[5],
      'userCount': userCount,
      'guestEventCount': guestEvents,
      'guestOnly': userCount == 0 && guestEvents > 0,
      'users': users
          .map((r) => {
                'userId': r[0],
                'email': r[1],
                'displayName': r[2],
                'username': r[3],
                'firstSeenAt': (r[4] as DateTime).toUtc().toIso8601String(),
                'lastSeenAt': (r[5] as DateTime).toUtc().toIso8601String(),
                'eventCount': r[6],
              })
          .toList(),
      'recentEvents': recent
          .map((r) {
            final uid = r[14]?.toString();
            final iid = r[15]?.toString();
            return {
              'id': r[0],
              'type': r[1],
              'occurredAt': (r[2] as DateTime).toUtc().toIso8601String(),
              'message': r[3],
              'release': r[4],
              'platform': r[5],
              'environment': r[6],
              'appVersion': r[7],
              'route': r[8],
              'deviceName': r[9],
              'networkUrl': r[10],
              'statusCode': r[11]?.toString(),
              'category': r[12],
              'level': r[13],
              'isGuest': isGuestAppUser(userId: uid, installId: iid),
            };
          })
          .toList(),
    };
  }
}
