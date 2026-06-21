import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';
import '../middleware/http_utils.dart';
import '../store/analytics_store.dart';
import '../store/scout_store.dart';

int _days(String? raw, int fallback) {
  final p = int.tryParse(raw ?? '');
  if (p == null) return fallback;
  return p.clamp(1, 90);
}

Future<Response> _api(Future<Response> Function() run) async {
  try {
    return await run();
  } catch (e) {
    return jsonErr('$e', status: 500);
  }
}

Handler apiRoutes(ServerConfig config, ScoutStore store, AnalyticsStore analytics) {
  final router = Router();

  router.get('/health', (_) => Response.ok('{"ok":true,"service":"scout-logger"}', headers: {'Content-Type': 'application/json'}));

  router.get('/projects', (_) async {
    final projects = await store.listProjects();
    return Response.ok(jsonEncode({'ok': true, 'projects': projects}), headers: {'Content-Type': 'application/json'});
  });

  router.post('/projects', (Request request) async {
    final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
    final name = body['name']?.toString().trim();
    if (name == null || name.isEmpty) return jsonErr('name is required');
    final project = await store.createProject(name: name, publicUrl: config.publicUrl);
    return Response.ok(jsonEncode({'ok': true, 'project': project}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/overview', (Request request, String id) async {
    return _api(() async {
      try {
        final overview = await store.projectOverview(id, days: _days(request.url.queryParameters['days'], 1));
        return Response.ok(jsonEncode({'ok': true, 'overview': overview}), headers: {'Content-Type': 'application/json'});
      } on ArgumentError {
        return jsonErr('Project not found', status: 404);
      }
    });
  });

  router.get('/projects/<id>/dashboard', (Request request, String id) async {
    return _api(() async {
      final days = _days(request.url.queryParameters['days'], 7);
      try {
        final overview = await store.projectOverview(id, days: days);
        final stats = await analytics.projectStats(id, days: days);
        final insights = await analytics.dashboardInsights(id, days: days);
        return Response.ok(
          jsonEncode({'ok': true, 'dashboard': {...overview, ...stats, ...insights}}),
          headers: {'Content-Type': 'application/json'},
        );
      } on ArgumentError {
        return jsonErr('Project not found', status: 404);
      }
    });
  });

  router.get('/projects/<id>/users', (Request request, String id) async {
    return _api(() async {
      final users = await analytics.listUsers(
        id,
        days: _days(request.url.queryParameters['days'], 30),
        limit: int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100,
      );
      return Response.ok(jsonEncode({'ok': true, 'users': users}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/users/<userId>', (Request request, String id, String userId) async {
    return _api(() async {
      final user = await analytics.getUser(id, userId, days: _days(request.url.queryParameters['days'], 30));
      if (user == null) return jsonErr('User not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'user': user}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/stats', (Request request, String id) async {
    return _api(() async {
      final stats = await analytics.projectStats(id, days: _days(request.url.queryParameters['days'], 7));
      return Response.ok(jsonEncode({'ok': true, 'stats': stats}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/issues', (Request request, String id) async {
    return _api(() async {
      final q = request.url.queryParameters;
      final daysRaw = q['days'];
      final issues = await store.listIssues(
        id,
        type: q['type'],
        status: q['status'],
        q: q['q'],
        days: daysRaw == null || daysRaw.isEmpty ? null : _days(daysRaw, 30),
      );
      return Response.ok(jsonEncode({'ok': true, 'issues': issues}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/issues/<issueId>', (Request request, String id, String issueId) async {
    return _api(() async {
      final issue = await store.getIssue(id, issueId);
      if (issue == null) return jsonErr('Issue not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'issue': issue}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/events', (Request request, String id) async {
    return _api(() async {
      final q = request.url.queryParameters;
      final daysRaw = q['days'];
      final events = await store.listEvents(
        id,
        type: q['type'],
        q: q['q'],
        country: q['country'],
        days: daysRaw == null || daysRaw.isEmpty ? null : _days(daysRaw, 7),
      );
      return Response.ok(jsonEncode({'ok': true, 'events': events}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/events/<eventId>', (Request request, String id, String eventId) async {
    return _api(() async {
      final event = await store.getEvent(id, eventId);
      if (event == null) return jsonErr('Event not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'event': event}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/geo', (Request request, String id) async {
    return _api(() async {
      final geo = await store.geoBreakdown(id, days: _days(request.url.queryParameters['days'], 7));
      return Response.ok(jsonEncode({'ok': true, 'geo': geo}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/analytics/routes', (Request request, String id) async {
    return _api(() async {
      final routes = await analytics.distinctRoutes(id, days: _days(request.url.queryParameters['days'], 30));
      return Response.ok(jsonEncode({'ok': true, 'routes': routes}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/analytics/funnel', (Request request, String id) async {
    return _api(() async {
      final stepsParam = request.url.queryParameters['steps'] ?? '';
      final steps = stepsParam.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (steps.isEmpty) return jsonErr('steps query required (comma-separated routes)');
      final funnel = await analytics.funnel(id, steps, days: _days(request.url.queryParameters['days'], 30));
      return Response.ok(jsonEncode({'ok': true, 'funnel': funnel}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/analytics/retention', (Request request, String id) async {
    return _api(() async {
      final weeks = int.tryParse(request.url.queryParameters['weeks'] ?? '') ?? 8;
      final data = await analytics.retention(id, weeks: weeks);
      return Response.ok(jsonEncode({'ok': true, 'retention': data}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/analytics/releases', (Request request, String id) async {
    return _api(() async {
      final releases = await analytics.releaseComparison(id, days: _days(request.url.queryParameters['days'], 30));
      return Response.ok(jsonEncode({'ok': true, 'releases': releases}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/sessions', (Request request, String id) async {
    return _api(() async {
      final sessions = await analytics.listSessions(
        id,
        days: _days(request.url.queryParameters['days'], 7),
        limit: int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 50,
      );
      return Response.ok(jsonEncode({'ok': true, 'sessions': sessions}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/sessions/<sessionId>/timeline', (Request request, String id, String sessionId) async {
    return _api(() async {
      final timeline = await analytics.sessionTimeline(id, sessionId);
      if (timeline == null) return jsonErr('Session not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'session': timeline}), headers: {'Content-Type': 'application/json'});
    });
  });

  return router.call;
}
