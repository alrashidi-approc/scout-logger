import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../db/scout_db.dart';
import '../util/dates.dart';
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
          WHERE project_id = @pid AND ${identifiedUserSql()}
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
          WHERE project_id = @pid AND session_id IS NOT NULL AND release IS NOT NULL
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
          COUNT(*) FILTER (WHERE e.type IN ('error', 'network'))::int AS errors,
          COUNT(DISTINCT e.user_id) FILTER (WHERE ${identifiedUserSql(alias: 'e')})::int AS users,
          COALESCE(ss.sessions, 0)::int AS sessions,
          COALESCE(ss.avg_ms, 0)::int AS avg_session_ms
        FROM events e
        LEFT JOIN session_stats ss ON ss.release = e.release
        WHERE e.project_id = @pid
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
        SELECT s.id, s.user_id, s.started_at, s.ended_at, s.duration_ms,
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
      final summary = _jsonField(r[5]);
      final userId = r[1]?.toString();
      final installId = r[8]?.toString();
      return {
        'id': r[0],
        'userId': userId,
        'isGuest': isGuestAppUser(userId: userId, installId: installId),
        'startedAt': (r[2] as DateTime).toUtc().toIso8601String(),
        'endedAt': r[3] != null ? (r[3] as DateTime).toUtc().toIso8601String() : null,
        'durationMs': r[4],
        'release': r[7],
        'reason': _jsonField(r[6])?.toString(),
        if (summary is Map) 'summary': Map<String, dynamic>.from(summary),
      };
    }).toList();
  }

  Future<Map<String, dynamic>?> sessionTimeline(String projectId, String sessionId) async {
    final conn = await db.connect();
    final session = await conn.execute(
      Sql.named('''
        SELECT id, user_id, started_at, ended_at, duration_ms
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
    final since = w.since!;
    final until = w.until;
    final prev = w.previousPeriod();

    Future<List<dynamic>> metrics(String from, {String? before}) async {
      final rows = before == null
          ? await conn.execute(
              Sql.named('''
            SELECT
              COUNT(*)::int,
              COUNT(*) FILTER (WHERE type IN ('error','network'))::int,
              COUNT(*) FILTER (WHERE type = 'crash')::int,
              COUNT(*) FILTER (WHERE type = 'network')::int,
              COUNT(*) FILTER (WHERE type = 'session')::int,
              COUNT(*) FILTER (WHERE type = 'span')::int,
              COUNT(*) FILTER (WHERE type = 'log')::int,
              COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()})::int,
              COUNT(DISTINCT session_id) FILTER (WHERE session_id IS NOT NULL)::int
            FROM events
            WHERE project_id = @pid AND occurred_at >= @from::timestamptz
          '''),
              parameters: {'pid': projectId, 'from': from},
            )
          : await conn.execute(
              Sql.named('''
            SELECT
              COUNT(*)::int,
              COUNT(*) FILTER (WHERE type IN ('error','network'))::int,
              COUNT(*) FILTER (WHERE type = 'crash')::int,
              COUNT(*) FILTER (WHERE type = 'network')::int,
              COUNT(*) FILTER (WHERE type = 'session')::int,
              COUNT(*) FILTER (WHERE type = 'span')::int,
              COUNT(*) FILTER (WHERE type = 'log')::int,
              COUNT(DISTINCT user_id) FILTER (WHERE ${identifiedUserSql()})::int,
              COUNT(DISTINCT session_id) FILTER (WHERE session_id IS NOT NULL)::int
            FROM events
            WHERE project_id = @pid
              AND occurred_at >= @from::timestamptz
              AND occurred_at < @before::timestamptz
          '''),
              parameters: {'pid': projectId, 'from': from, 'before': before},
            );
      return rows.first;
    }

    final cur = until == null ? await metrics(since) : await metrics(since, before: until);
    final prevStart = prev.since!;
    final prevEnd = prev.until ?? since;
    final prevM = await metrics(prevStart, before: prevEnd);

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

    final crashSessions = await conn.execute(
      Sql.named('''
        SELECT COUNT(DISTINCT session_id)::int
        FROM events
        WHERE project_id = @pid AND type = 'crash' AND session_id IS NOT NULL
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      '''),
      parameters: {'pid': projectId, ...timeParams(w)},
    );

    final openIssues = await conn.execute(
      Sql.named('SELECT COUNT(*)::int FROM issues WHERE project_id = @pid AND status = \'open\''),
      parameters: {'pid': projectId},
    );

    final byType = await conn.execute(
      Sql.named('''
        SELECT type, COUNT(*)::int FROM events
        WHERE project_id = @pid
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY type ORDER BY COUNT(*) DESC
      '''),
      parameters: {'pid': projectId, ...timeParams(w)},
    );

    final byPlatform = await conn.execute(
      Sql.named('''
        SELECT platform, COUNT(*)::int FROM events
        WHERE project_id = @pid AND platform IS NOT NULL
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY platform ORDER BY COUNT(*) DESC LIMIT 8
      '''),
      parameters: {'pid': projectId, ...timeParams(w)},
    );

    final trend = await fetchEventTrend(conn, projectId, w, includeUsers: true);

    int n(dynamic v) => v == null ? 0 : (v is int ? v : (v as num).toInt());
    double delta(num current, num previous) =>
        previous == 0 ? (current == 0 ? 0.0 : 100.0) : ((current - previous) / previous * 100);

    final totalSessions = n(sess[0]);
    final crashed = n(crashSessions.first[0]);
    final events = n(cur[0]);
    final errors = n(cur[1]);

    return {
      'days': period,
      'events': n(cur[0]),
      'errors': n(cur[1]),
      'crashes': n(cur[2]),
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
    final tp = timeParams(w);
    final p = {'pid': projectId, ...tp};

    final usersAffected = await conn.execute(
      Sql.named('''
        SELECT COUNT(DISTINCT user_id)::int
        FROM events
        WHERE project_id = @pid AND ${identifiedUserSql()}
          AND type IN ('error', 'network', 'crash')
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      '''),
      parameters: p,
    );

    final peakEvents = await conn.execute(
      Sql.named('''
        SELECT EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'UTC')::int, COUNT(*)::int
        FROM events WHERE project_id = @pid
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY 1 ORDER BY 2 DESC LIMIT 1
      '''),
      parameters: p,
    );

    final peakErrors = await conn.execute(
      Sql.named('''
        SELECT EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'UTC')::int, COUNT(*)::int
        FROM events
        WHERE project_id = @pid AND type IN ('error', 'network', 'crash')
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY 1 ORDER BY 2 DESC LIMIT 1
      '''),
      parameters: p,
    );

    final hourly = await conn.execute(
      Sql.named('''
        SELECT EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'UTC')::int AS h,
               COUNT(*)::int,
               COUNT(*) FILTER (WHERE type IN ('error','network','crash'))::int
        FROM events WHERE project_id = @pid
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
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
          AND payload->'network'->>'url' IS NOT NULL
          AND (
            type IN ('error', 'crash') OR
            type = 'network' OR
            (payload->'network'->>'statusCode') ~ '^[0-9]+\$' AND (payload->'network'->>'statusCode')::int >= 400
          )
        GROUP BY endpoint ORDER BY 2 DESC LIMIT 10
      '''),
      parameters: p,
    );

    final screens = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF(payload->'screen'->>'currentRoute', ''), 'unknown') AS screen, COUNT(*)::int
        FROM events
        WHERE project_id = @pid AND type = 'crash'
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY screen ORDER BY 2 DESC LIMIT 10
      '''),
      parameters: p,
    );

    final byEnv = await conn.execute(
      Sql.named('''
        SELECT COALESCE(NULLIF(environment, ''), 'unknown') AS environment, COUNT(*)::int
        FROM events WHERE project_id = @pid
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
               COUNT(*) FILTER (WHERE type IN ('error','network'))::int,
               COUNT(*) FILTER (WHERE type = 'crash')::int
        FROM events WHERE project_id = @pid
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

    return {
      'usersAffectedByErrors': n(usersAffected.first[0]),
      'peakHour': peakEvents.isEmpty ? null : n(peakEvents.first[0]),
      'peakHourEvents': peakEvents.isEmpty ? 0 : n(peakEvents.first[1]),
      'peakErrorHour': peakErrors.isEmpty ? null : n(peakErrors.first[0]),
      'peakErrorHourCount': peakErrors.isEmpty ? 0 : n(peakErrors.first[1]),
      'hourlyActivity': hourly.map((r) => {'hour': r[0], 'events': r[1], 'errors': r[2]}).toList(),
      'topFailingEndpoints': endpoints.map((r) => {'endpoint': r[0], 'count': r[1]}).toList(),
      'topCrashScreens': screens.map((r) => {'screen': r[0], 'count': r[1]}).toList(),
      'byEnvironment': byEnv.map((r) => {'environment': r[0], 'count': r[1]}).toList(),
      'eventsByRelease': byRelease.map((r) => {'release': r[0], 'count': r[1], 'errors': r[2], 'crashes': r[3]}).toList(),
      'byDeployment': byDeploy.map((r) => {'tag': r[0], 'count': r[1]}).toList(),
    };
  }

  Future<List<Map<String, dynamic>>> listUsers(String projectId, {int days = 30, int limit = 100, TimeWindow? window}) async {
    final conn = await db.connect();
    final w = window ?? TimeWindow.lastDays(days.clamp(1, 90));
    final rows = await conn.execute(
      Sql.named('''
        SELECT user_id,
               MIN(occurred_at) AS first_seen,
               MAX(occurred_at) AS last_seen,
               COUNT(*)::int,
               COUNT(*) FILTER (WHERE type IN ('error','network','crash'))::int,
               COUNT(DISTINCT session_id) FILTER (WHERE session_id IS NOT NULL)::int,
               COUNT(DISTINCT install_id) FILTER (WHERE install_id IS NOT NULL)::int,
               MAX(NULLIF(TRIM(payload->'user'->>'email'), '')) AS email
        FROM events
        WHERE project_id = @pid AND ${identifiedUserSql()}
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
        GROUP BY user_id
        ORDER BY MAX(occurred_at) DESC
        LIMIT @lim
      '''),
      parameters: {'pid': projectId, ...timeParams(w), 'lim': limit},
    );
    return rows
        .map((r) => {
              'userId': r[0],
              'identified': true,
              'email': r[7],
              'firstSeenAt': (r[1] as DateTime).toUtc().toIso8601String(),
              'lastSeenAt': (r[2] as DateTime).toUtc().toIso8601String(),
              'eventCount': r[3],
              'errorCount': r[4],
              'sessionCount': r[5],
              'deviceCount': r[6],
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
          SELECT type, occurred_at, country
          FROM events
          WHERE project_id = @pid
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
          COUNT(*) FILTER (WHERE type IN ('error','network','crash'))::int,
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
        WHERE project_id = @pid AND user_id = @uid AND install_id IS NOT NULL AND user_id <> install_id
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
        SELECT MAX(NULLIF(TRIM(payload->'user'->>'email'), ''))
        FROM events
        WHERE project_id = @pid AND user_id = @uid
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
          AND (@until::timestamptz IS NULL OR occurred_at < @until::timestamptz)
      '''),
      parameters: {'pid': projectId, 'uid': userId, ...tp},
    );

    final s = stats.first;
    final guestEvents = guestOnly.first[0] as int;
    return {
      'userId': userId,
      'identified': true,
      'email': profile.first[0],
      'includesGuestActivity': guestEvents > 0,
      'guestEventCount': guestEvents,
      'days': w.approximateDays,
      'eventCount': s[0],
      'errorCount': s[1],
      'crashCount': s[2],
      'firstSeenAt': (s[3] as DateTime).toUtc().toIso8601String(),
      'lastSeenAt': (s[4] as DateTime).toUtc().toIso8601String(),
      'topCountry': s[5],
      'sessionCount': sessions.first[0],
      'deviceCount': devices.length,
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
}
