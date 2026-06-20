import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../db/scout_db.dart';

/// Product analytics queries — funnels, retention, releases, session timelines.
class AnalyticsStore {
  AnalyticsStore(this.db);

  final ScoutDb db;

  Future<List<String>> distinctRoutes(String projectId, {int days = 30}) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT DISTINCT step->>'route' AS route
        FROM events, jsonb_array_elements(payload->'screenTrail') AS step
        WHERE project_id = @pid
          AND occurred_at >= (now() AT TIME ZONE 'utc') - make_interval(days => @days)
          AND step->>'route' IS NOT NULL AND step->>'route' != ''
        ORDER BY route
        LIMIT 200
      '''),
      parameters: {'pid': projectId, 'days': days},
    );
    return rows.map((r) => r[0] as String).toList();
  }

  Future<Map<String, dynamic>> funnel(String projectId, List<String> steps, {int days = 30}) async {
    if (steps.isEmpty) return {'steps': [], 'totalSessions': 0};

    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT session_id, payload->'screenTrail' AS trail
        FROM (
          SELECT DISTINCT ON (session_id) session_id, payload
          FROM events
          WHERE project_id = @pid
            AND session_id IS NOT NULL
            AND occurred_at >= (now() AT TIME ZONE 'utc') - make_interval(days => @days)
            AND jsonb_typeof(payload->'screenTrail') = 'array'
            AND jsonb_array_length(payload->'screenTrail') > 0
          ORDER BY session_id, jsonb_array_length(payload->'screenTrail') DESC, occurred_at DESC
        ) t
      '''),
      parameters: {'pid': projectId, 'days': days},
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
      'days': days,
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
    final rows = await conn.execute(
      Sql.named('''
        WITH cohorts AS (
          SELECT user_id, date_trunc('week', first_seen_at AT TIME ZONE 'utc')::date AS cohort_week
          FROM user_first_seen
          WHERE project_id = @pid
            AND first_seen_at >= (now() AT TIME ZONE 'utc') - make_interval(weeks => @weeks)
        ),
        activity AS (
          SELECT user_id, date_trunc('week', occurred_at AT TIME ZONE 'utc')::date AS active_week
          FROM events
          WHERE project_id = @pid AND user_id IS NOT NULL
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
      parameters: {'pid': projectId, 'weeks': weeks},
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

  Future<List<Map<String, dynamic>>> releaseComparison(String projectId, {int days = 30}) async {
    final conn = await db.connect();
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
            AND s.started_at >= (now() AT TIME ZONE 'utc') - make_interval(days => @days)
          GROUP BY sr.release
        )
        SELECT
          e.release,
          COUNT(*)::int AS events,
          COUNT(*) FILTER (WHERE e.type = 'crash')::int AS crashes,
          COUNT(*) FILTER (WHERE e.type IN ('error', 'network'))::int AS errors,
          COUNT(DISTINCT e.user_id)::int AS users,
          COALESCE(ss.sessions, 0)::int AS sessions,
          COALESCE(ss.avg_ms, 0)::int AS avg_session_ms
        FROM events e
        LEFT JOIN session_stats ss ON ss.release = e.release
        WHERE e.project_id = @pid
          AND e.release IS NOT NULL
          AND e.occurred_at >= (now() AT TIME ZONE 'utc') - make_interval(days => @days)
        GROUP BY e.release, ss.sessions, ss.avg_ms
        ORDER BY events DESC
        LIMIT 20
      '''),
      parameters: {'pid': projectId, 'days': days},
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

  Future<List<Map<String, dynamic>>> listSessions(String projectId, {int days = 7, int limit = 50}) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT s.id, s.user_id, s.started_at, s.ended_at, s.duration_ms,
               end_ev.payload->'summary' AS summary,
               end_ev.payload->'reason' AS reason,
               (SELECT release FROM events WHERE project_id = s.project_id AND session_id = s.id AND release IS NOT NULL ORDER BY occurred_at LIMIT 1) AS release
        FROM app_sessions s
        LEFT JOIN LATERAL (
          SELECT payload FROM events
          WHERE project_id = s.project_id AND session_id = s.id
            AND type = 'session' AND payload->>'action' = 'end'
          ORDER BY occurred_at DESC LIMIT 1
        ) end_ev ON true
        WHERE s.project_id = @pid
          AND s.started_at >= (now() AT TIME ZONE 'utc') - make_interval(days => @days)
        ORDER BY s.started_at DESC
        LIMIT @lim
      '''),
      parameters: {'pid': projectId, 'days': days, 'lim': limit},
    );

    return rows.map((r) {
      final summary = _jsonField(r[5]);
      return {
        'id': r[0],
        'userId': r[1],
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
        out.add({
          'type': 'navigation',
          'route': route,
          'label': step['screenName'] ?? route,
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
}
