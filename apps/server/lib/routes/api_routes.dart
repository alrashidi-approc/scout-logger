import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';
import '../middleware/http_utils.dart';
import '../store/analytics_store.dart';
import '../store/scout_store.dart';

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
    try {
      final overview = await store.projectOverview(id);
      return Response.ok(jsonEncode({'ok': true, 'overview': overview}), headers: {'Content-Type': 'application/json'});
    } catch (_) {
      return jsonErr('Project not found', status: 404);
    }
  });

  router.get('/projects/<id>/issues', (Request request, String id) async {
    final issues = await store.listIssues(id);
    return Response.ok(jsonEncode({'ok': true, 'issues': issues}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/issues/<issueId>', (Request request, String id, String issueId) async {
    final issue = await store.getIssue(id, issueId);
    if (issue == null) return jsonErr('Issue not found', status: 404);
    return Response.ok(jsonEncode({'ok': true, 'issue': issue}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/events', (Request request, String id) async {
    final type = request.url.queryParameters['type'];
    final events = await store.listEvents(id, type: type);
    return Response.ok(jsonEncode({'ok': true, 'events': events}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/events/<eventId>', (Request request, String id, String eventId) async {
    final event = await store.getEvent(id, eventId);
    if (event == null) return jsonErr('Event not found', status: 404);
    return Response.ok(jsonEncode({'ok': true, 'event': event}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/geo', (Request request, String id) async {
    final days = int.tryParse(request.url.queryParameters['days'] ?? '') ?? 7;
    final geo = await store.geoBreakdown(id, days: days);
    return Response.ok(jsonEncode({'ok': true, 'geo': geo}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/analytics/routes', (Request request, String id) async {
    final days = int.tryParse(request.url.queryParameters['days'] ?? '') ?? 30;
    final routes = await analytics.distinctRoutes(id, days: days);
    return Response.ok(jsonEncode({'ok': true, 'routes': routes}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/analytics/funnel', (Request request, String id) async {
    final stepsParam = request.url.queryParameters['steps'] ?? '';
    final steps = stepsParam.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (steps.isEmpty) return jsonErr('steps query required (comma-separated routes)');
    final days = int.tryParse(request.url.queryParameters['days'] ?? '') ?? 30;
    final funnel = await analytics.funnel(id, steps, days: days);
    return Response.ok(jsonEncode({'ok': true, 'funnel': funnel}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/analytics/retention', (Request request, String id) async {
    final weeks = int.tryParse(request.url.queryParameters['weeks'] ?? '') ?? 8;
    final data = await analytics.retention(id, weeks: weeks);
    return Response.ok(jsonEncode({'ok': true, 'retention': data}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/analytics/releases', (Request request, String id) async {
    final days = int.tryParse(request.url.queryParameters['days'] ?? '') ?? 30;
    final releases = await analytics.releaseComparison(id, days: days);
    return Response.ok(jsonEncode({'ok': true, 'releases': releases}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/sessions', (Request request, String id) async {
    final days = int.tryParse(request.url.queryParameters['days'] ?? '') ?? 7;
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 50;
    final sessions = await analytics.listSessions(id, days: days, limit: limit);
    return Response.ok(jsonEncode({'ok': true, 'sessions': sessions}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/sessions/<sessionId>/timeline', (Request request, String id, String sessionId) async {
    final timeline = await analytics.sessionTimeline(id, sessionId);
    if (timeline == null) return jsonErr('Session not found', status: 404);
    return Response.ok(jsonEncode({'ok': true, 'session': timeline}), headers: {'Content-Type': 'application/json'});
  });

  return router.call;
}
