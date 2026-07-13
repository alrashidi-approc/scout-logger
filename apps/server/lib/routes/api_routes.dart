import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:scout_models/scout_models.dart';

import '../config/server_config.dart';
import '../middleware/auth_middleware.dart';
import '../middleware/http_utils.dart';
import '../store/analytics_store.dart';
import '../store/auth_store.dart';
import '../store/notification_store.dart';
import '../store/platform_store.dart';
import '../store/scout_store.dart';
import '../notifications/notification_service.dart';
import '../notifications/notification_router.dart';
import '../reports/report_service.dart';
import '../util/dates.dart';
import 'admin_routes.dart';

TimeWindow _window(Map<String, String> q, {int defaultDays = 7}) =>
    TimeWindow.fromQuery(q, defaultDays: defaultDays);

TimeWindow? _optionalWindow(Map<String, String> q) {
  if (q['from'] != null && q['from']!.isNotEmpty) return TimeWindow.fromQuery(q);
  if (q['days'] != null && q['days']!.isNotEmpty) return TimeWindow.fromQuery(q);
  return null;
}

Future<Response> _api(Future<Response> Function() run) async {
  try {
    return await run();
  } catch (e) {
    return jsonErr('$e', status: 500);
  }
}

Future<Response?> _projectGuard(Request request, String projectId, AuthStore auth, {bool write = false}) {
  final principal = authFrom(request)!;
  return ensureProjectAccess(
    auth: principal,
    projectId: projectId,
    membership: auth.membershipRole,
    write: write,
  );
}

Handler apiRoutes(
  ServerConfig config,
  ScoutStore store,
  AnalyticsStore analytics,
  AuthStore authStore, {
  NotificationService? notifications,
  NotificationStore? notificationStore,
}) {
  final router = Router();
  final reportService = ReportService(store, analytics);

  router.get('/health', (_) => Response.ok('{"ok":true,"service":"scout-logger"}', headers: {'Content-Type': 'application/json'}));
  router.get('/auth/me', meRoute(auth: authStore, config: config));
  router.mount('/admin/', adminRoutes(auth: authStore, config: config, platformStore: notifications?.platformStore ?? PlatformStore(store.db)));

  router.get('/projects', (Request request) async {
    final auth = authFrom(request)!;
    final projects = await store.listProjects(userId: auth.userId, admin: auth.isAdmin);
    return Response.ok(jsonEncode({'ok': true, 'projects': projects}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/projects/<id>/access', (Request request, String id) async {
    final auth = authFrom(request)!;
    if (auth.isAdmin) {
      return Response.ok(
        jsonEncode({'ok': true, 'projectId': id, 'role': 'admin', 'access': true}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final uid = auth.userId;
    if (uid == null) return jsonErr('Unauthorized', status: 401);
    final role = await authStore.membershipRole(uid, id);
    if (role == null) return jsonErr('Project not found', status: 404);
    return Response.ok(
      jsonEncode({'ok': true, 'projectId': id, 'role': role, 'access': true}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.post('/projects', (Request request) async {
    final auth = authFrom(request)!;
    if (!auth.canCreateApps) return jsonErr('You do not have permission to create projects', status: 403);
    final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
    final name = body['name']?.toString().trim();
    if (name == null || name.isEmpty) return jsonErr('name is required');
    final project = await store.createProject(name: name, publicUrl: config.publicUrl);
    if (auth.userId != null && !auth.apiKeyBypass) {
      await authStore.addProjectOwner(auth.userId!, project['id'] as String);
    }
    return Response.ok(jsonEncode({'ok': true, 'project': project}), headers: {'Content-Type': 'application/json'});
  });

  router.delete('/projects/<id>', (Request request, String id) async {
    return _api(() async {
      final auth = authFrom(request)!;
      final denied = await ensureProjectDelete(
        auth: auth,
        projectId: id,
        membership: authStore.membershipRole,
      );
      if (denied != null) return denied;
      if (!await store.deleteProject(id)) return jsonErr('Project not found', status: 404);
      return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.delete('/projects/<id>/data', (Request request, String id) async {
    return _api(() async {
      final auth = authFrom(request)!;
      final denied = await ensureProjectDelete(
        auth: auth,
        projectId: id,
        membership: authStore.membershipRole,
      );
      if (denied != null) return denied;
      final q = request.url.queryParameters;
      if ((q['from'] == null || q['from']!.isEmpty) && (q['days'] == null || q['days']!.isEmpty)) {
        return jsonErr('from/to or days query required', status: 400);
      }
      final window = TimeWindow.fromQuery(q, defaultDays: 7);
      if (window.since == null) return jsonErr('Invalid date range', status: 400);
      final deleted = await store.purgeProjectData(id, window: window);
      return Response.ok(
        jsonEncode({'ok': true, 'deleted': deleted}),
        headers: {'Content-Type': 'application/json'},
      );
    });
  });

  router.get('/projects/<id>/facets', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final facets = await store.eventFilterFacets(
        id,
        window: _optionalWindow(request.url.queryParameters) ?? _window(request.url.queryParameters),
        environment: request.url.queryParameters['environment'],
        appVersion: request.url.queryParameters['appVersion'] ?? request.url.queryParameters['app_version'],
        deviceName: request.url.queryParameters['device'] ?? request.url.queryParameters['deviceName'],
      );
      return Response.ok(jsonEncode({'ok': true, 'facets': facets}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/credentials', (Request request, String id) async {
    return _api(() async {
      final auth = authFrom(request)!;
      final denied = await ensureCredentialsAccess(
        auth: auth,
        projectId: id,
        membership: authStore.membershipRole,
      );
      if (denied != null) return denied;
      if (!auth.isAdmin && !await store.projectExists(id)) return jsonErr('Project not found', status: 404);
      if (!auth.isAdmin) {
        final guard = await _projectGuard(request, id, authStore);
        if (guard != null) return guard;
      }
      final creds = await store.getProjectCredentials(id, publicUrl: config.publicUrl);
      if (creds == null) return jsonErr('Project not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'credentials': creds}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/overview', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      try {
        final overview = await store.projectOverview(id, window: _window(request.url.queryParameters, defaultDays: 1));
        return Response.ok(jsonEncode({'ok': true, 'overview': overview}), headers: {'Content-Type': 'application/json'});
      } on ArgumentError {
        return jsonErr('Project not found', status: 404);
      }
    });
  });

  router.get('/projects/<id>/dashboard', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final q = request.url.queryParameters;
      final w = _window(q);
      try {
        final overview = await store.projectOverview(id, window: w, includeTrend: false);
        final stats = await analytics.projectStats(id, window: w);
        final insights = await analytics.dashboardInsights(id, window: w);
        final health = await store.sdkHealth(id, window: w);
        return Response.ok(
          jsonEncode({'ok': true, 'dashboard': {...overview, ...stats, ...insights, 'sdkHealth': health}}),
          headers: {'Content-Type': 'application/json'},
        );
      } on ArgumentError {
        return jsonErr('Project not found', status: 404);
      }
    });
  });

  router.get('/projects/<id>/users', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final users = await analytics.listUsers(
        id,
        window: _window(request.url.queryParameters, defaultDays: 30),
        limit: int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100,
      );
      return Response.ok(jsonEncode({'ok': true, 'users': users}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/users/<userId>', (Request request, String id, String userId) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final user = await analytics.getUser(id, userId, window: _window(request.url.queryParameters, defaultDays: 30));
      if (user == null) return jsonErr('User not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'user': user}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/stats', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final stats = await analytics.projectStats(id, window: _window(request.url.queryParameters));
      return Response.ok(jsonEncode({'ok': true, 'stats': stats}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/reports/<type>', (Request request, String id, String type) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final reportType = ReportType.fromId(type);
      if (reportType == null) return jsonErr('Unknown report type', status: 404);
      final report = await reportService.build(reportType, id, _window(request.url.queryParameters, defaultDays: 30));
      return Response.ok(jsonEncode({'ok': true, 'report': report.toJson()}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/issues', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final q = request.url.queryParameters;
      final issues = await store.listIssues(
        id,
        type: q['type'],
        status: q['status'],
        q: q['q'],
        environment: q['environment'],
        appVersion: q['appVersion'] ?? q['app_version'],
        deviceName: q['device'] ?? q['deviceName'],
        window: _optionalWindow(q) ?? _window(q, defaultDays: 30),
      );
      return Response.ok(jsonEncode({'ok': true, 'issues': issues}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/issues/<issueId>', (Request request, String id, String issueId) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final issue = await store.getIssue(id, issueId);
      if (issue == null) return jsonErr('Issue not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'issue': issue}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.patch('/projects/<id>/issues/<issueId>', (Request request, String id, String issueId) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore, write: true);
      if (guard != null) return guard;
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      Map<String, dynamic>? issue;
      if (json.containsKey('assigneeUserId')) {
        final uid = json['assigneeUserId']?.toString();
        issue = await store.assignIssue(id, issueId, uid != null && uid.isNotEmpty ? uid : null);
      }
      final status = json['status'] as String?;
      if (status != null && status.isNotEmpty) {
        issue = await store.updateIssueStatus(id, issueId, status);
      }
      if (issue == null) return jsonErr('Issue not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'issue': issue}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/issues/<issueId>/notes', (Request request, String id, String issueId) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final notes = await store.listIssueNotes(id, issueId);
      return Response.ok(jsonEncode({'ok': true, 'notes': notes}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.post('/projects/<id>/issues/<issueId>/notes', (Request request, String id, String issueId) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore, write: true);
      if (guard != null) return guard;
      final json = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final text = json['body']?.toString() ?? '';
      if (text.trim().isEmpty) return jsonErr('body is required');
      final note = await store.addIssueNote(id, issueId, authFrom(request)?.userId, text);
      if (note == null) return jsonErr('Issue not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'note': note}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/assignees', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final members = await authStore.listProjectMembers(id);
      return Response.ok(jsonEncode({'ok': true, 'members': members}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/events', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final q = request.url.queryParameters;
      final page = await store.listEvents(
        id,
        limit: int.tryParse(q['limit'] ?? '') ?? 50,
        offset: int.tryParse(q['offset'] ?? '') ?? 0,
        type: q['type'] ?? q['kind'],
        level: q['level'],
        category: q['category'],
        q: q['q'],
        country: q['country'],
        environment: q['environment'],
        appVersion: q['appVersion'] ?? q['app_version'],
        deviceName: q['device'] ?? q['deviceName'],
        window: _optionalWindow(q) ?? _window(q, defaultDays: 30),
      );
      return Response.ok(
        jsonEncode({
          'ok': true,
          'events': page['events'],
          'pagination': {
            'total': page['total'],
            'limit': page['limit'],
            'offset': page['offset'],
            'hasMore': page['hasMore'],
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });
  });

  router.get('/projects/<id>/events/<eventId>', (Request request, String id, String eventId) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final event = await store.getEvent(id, eventId);
      if (event == null) return jsonErr('Event not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'event': event}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.post('/projects/<id>/share', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final type = body['type']?.toString();
      final resourceId = body['resourceId']?.toString();
      if (type == null || type.isEmpty || resourceId == null || resourceId.isEmpty) {
        return jsonErr('type and resourceId required');
      }
      if (!{'event', 'issue'}.contains(type)) return jsonErr('type must be event or issue');
      final rawDays = body['expiresInDays'];
      final expiresInDays = rawDays is num ? rawDays.toInt() : int.tryParse('$rawDays') ?? 30;
      final auth = authFrom(request)!;
      final share = await store.createShareToken(
        projectId: id,
        resourceType: type,
        resourceId: resourceId,
        createdBy: auth.userId,
        expiresInDays: expiresInDays,
      );
      if (share == null) return jsonErr('Resource not found', status: 404);
      final token = share['token'] as String;
      final path = '${config.dashboardUrlPath}/share/$token';
      return Response.ok(
        jsonEncode({
          'ok': true,
          'token': token,
          'url': '${config.publicUrl}$path',
          'path': '/share/$token',
          'expiresAt': share['expiresAt'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });
  });

  router.get('/projects/<id>/geo', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final geo = await store.geoBreakdown(id, window: _window(request.url.queryParameters));
      return Response.ok(jsonEncode({'ok': true, 'geo': geo}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/analytics/routes', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final routes = await analytics.distinctRoutes(id, window: _window(request.url.queryParameters, defaultDays: 30));
      return Response.ok(jsonEncode({'ok': true, 'routes': routes}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/analytics/funnel', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final stepsParam = request.url.queryParameters['steps'] ?? '';
      final steps = stepsParam.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (steps.isEmpty) return jsonErr('steps query required (comma-separated routes)');
      final funnel = await analytics.funnel(id, steps, window: _window(request.url.queryParameters, defaultDays: 30));
      return Response.ok(jsonEncode({'ok': true, 'funnel': funnel}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/analytics/retention', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final weeks = int.tryParse(request.url.queryParameters['weeks'] ?? '') ?? 8;
      final data = await analytics.retention(id, weeks: weeks);
      return Response.ok(jsonEncode({'ok': true, 'retention': data}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/analytics/releases', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final releases = await analytics.releaseComparison(id, window: _window(request.url.queryParameters, defaultDays: 30));
      return Response.ok(jsonEncode({'ok': true, 'releases': releases}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/sessions', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      await store.closeStaleSessions(projectId: id);
      final sessions = await analytics.listSessions(
        id,
        window: _window(request.url.queryParameters),
        limit: int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 50,
      );
      return Response.ok(jsonEncode({'ok': true, 'sessions': sessions}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/sessions/<sessionId>/timeline', (Request request, String id, String sessionId) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      await store.closeStaleSessions(projectId: id);
      final events = await store.listSessionEvents(id, sessionId);
      var timeline = await analytics.sessionTimeline(id, sessionId);
      if (timeline == null && events.isEmpty) return jsonErr('Session not found', status: 404);
      timeline ??= {
        'id': sessionId,
        'userId': null,
        'startedAt': events.first['occurredAt'],
        'endedAt': events.last['occurredAt'],
        'durationMs': null,
        'timeline': <Map<String, dynamic>>[],
      };
      timeline['events'] = events;
      timeline['eventCount'] = events.length;
      return Response.ok(jsonEncode({'ok': true, 'session': timeline}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/sdk-health', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final w = _optionalWindow(request.url.queryParameters) ?? _window(request.url.queryParameters);
      final health = await store.sdkHealth(id, window: w);
      return Response.ok(jsonEncode({'ok': true, 'health': health}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.get('/projects/<id>/settings', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      try {
        final settings = await store.getProjectSettings(id);
        return Response.ok(jsonEncode({'ok': true, 'settings': settings}), headers: {'Content-Type': 'application/json'});
      } on ArgumentError {
        return jsonErr('Project not found', status: 404);
      }
    });
  });

  router.patch('/projects/<id>/settings', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore, write: true);
      if (guard != null) return guard;
      try {
        final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
        final settings = await store.updateProjectSettings(id, body);
        return Response.ok(jsonEncode({'ok': true, 'settings': settings}), headers: {'Content-Type': 'application/json'});
      } on ArgumentError {
        return jsonErr('Project not found', status: 404);
      }
    });
  });

  if (notifications != null && notificationStore != null) {
    router.get('/notifications/deliveries', (Request request) async {
      return _api(() async {
        final auth = authFrom(request)!;
        final limit = (int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100).clamp(1, 200);
        final hours = (int.tryParse(request.url.queryParameters['hours'] ?? '') ?? 24).clamp(1, 720);
        final deliveries = await notificationStore.listAllDeliveries(userId: auth.userId, admin: auth.isAdmin, limit: limit);
        final summary = await notificationStore.globalDeliverySummary(userId: auth.userId, admin: auth.isAdmin, hours: hours);
        return Response.ok(jsonEncode({'ok': true, 'deliveries': deliveries, 'summary': summary}),
            headers: {'Content-Type': 'application/json'});
      });
    });

    router.get('/projects/<id>/notifications', (Request request, String id) async {
      return _api(() async {
        final guard = await _projectGuard(request, id, authStore);
        if (guard != null) return guard;
        final denied = await ensureProjectNotificationsManage(
          auth: authFrom(request)!,
          projectId: id,
          membership: authStore.membershipRole,
        );
        if (denied != null) return denied;
        final configJson = await notificationStore.getClientConfig(
          id,
          platform: await notifications.platformStore.getNotificationPolicy(),
        );
        return Response.ok(jsonEncode({'ok': true, 'notifications': configJson}), headers: {'Content-Type': 'application/json'});
      });
    });

    router.patch('/projects/<id>/notifications', (Request request, String id) async {
      return _api(() async {
        final denied = await ensureProjectNotificationsManage(
          auth: authFrom(request)!,
          projectId: id,
          membership: authStore.membershipRole,
        );
        if (denied != null) return denied;
        try {
          final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
          await notificationStore.updateConfig(id, body);
          final configJson = await notificationStore.getClientConfig(
            id,
            platform: await notifications.platformStore.getNotificationPolicy(),
          );
          return Response.ok(jsonEncode({'ok': true, 'notifications': configJson}), headers: {'Content-Type': 'application/json'});
        } on ArgumentError {
          return jsonErr('Project not found', status: 404);
        }
      });
    });

    router.post('/projects/<id>/notifications/test', (Request request, String id) async {
      return _api(() async {
        final denied = await ensureProjectNotificationsManage(
          auth: authFrom(request)!,
          projectId: id,
          membership: authStore.membershipRole,
        );
        if (denied != null) return denied;
        final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
        final channel = body['channel']?.toString();
        if (channel == null || !kNotificationChannels.contains(channel)) return jsonErr('channel is required');
        final config = await notificationStore.getConfig(id);
        final platform = await notifications.platformStore.getNotificationPolicy();
        try {
          await notifications.sendTest(projectId: id, channel: channel, notifications: config, platform: platform);
        } catch (e) {
          final msg = '$e'.replaceFirst(RegExp(r'^(Exception: )?Failed after \d+ attempts: '), '');
          return jsonErr(msg, status: 400);
        }
        return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type': 'application/json'});
      });
    });

    router.get('/projects/<id>/notifications/channels', (Request request, String id) async {
      return _api(() async {
        final guard = await _projectGuard(request, id, authStore);
        if (guard != null) return guard;
        final config = await notificationStore.getConfig(id);
        final platform = await notifications.platformStore.getNotificationPolicy();
        final channels = readyNotificationChannels(config: config, platform: platform);
        return Response.ok(jsonEncode({'ok': true, 'channels': channels}), headers: {'Content-Type': 'application/json'});
      });
    });

    router.post('/projects/<id>/notifications/share', (Request request, String id) async {
      return _api(() async {
        final guard = await _projectGuard(request, id, authStore);
        if (guard != null) return guard;
        final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
        final resourceType = body['resourceType']?.toString();
        final resourceId = body['resourceId']?.toString();
        final rawChannels = body['channels'];
        if (resourceType == null || !{'issue', 'event'}.contains(resourceType)) {
          return jsonErr('resourceType must be issue or event');
        }
        if (resourceId == null || resourceId.isEmpty) return jsonErr('resourceId is required');
        if (rawChannels is! List || rawChannels.isEmpty) return jsonErr('channels is required');
        final channels = rawChannels.map((e) => e.toString()).toList();
        final config = await notificationStore.getConfig(id);
        final platform = await notifications.platformStore.getNotificationPolicy();
        try {
          final result = await notifications.sendShare(
            projectId: id,
            resourceType: resourceType,
            resourceId: resourceId,
            channels: channels,
            notifications: config,
            platform: platform,
            sentByUserId: authFrom(request)?.userId,
          );
          return Response.ok(jsonEncode({'ok': true, ...result}), headers: {'Content-Type': 'application/json'});
        } on ArgumentError catch (e) {
          final msg = '$e'.replaceFirst('Invalid argument (parameters): ', '').replaceFirst('Invalid argument: ', '');
          return jsonErr(msg, status: 400);
        }
      });
    });

    router.get('/projects/<id>/notifications/deliveries', (Request request, String id) async {
      return _api(() async {
        final denied = await ensureProjectNotificationsManage(
          auth: authFrom(request)!,
          projectId: id,
          membership: authStore.membershipRole,
        );
        if (denied != null) return denied;
        final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 50;
        final hours = int.tryParse(request.url.queryParameters['hours'] ?? '') ?? 24;
        final deliveries = await notificationStore.listDeliveries(id, limit: limit.clamp(1, 200));
        final summary = await notificationStore.deliverySummary(id, hours: hours.clamp(1, 720));
        return Response.ok(jsonEncode({'ok': true, 'deliveries': deliveries, 'summary': summary}),
            headers: {'Content-Type': 'application/json'});
      });
    });
  }

  router.get('/projects/<id>/members', (Request request, String id) async {
    return _api(() async {
      final denied = await ensureProjectMembersManage(
        auth: authFrom(request)!,
        projectId: id,
        membership: authStore.membershipRole,
      );
      if (denied != null) return denied;
      if (!authFrom(request)!.isAdmin && !await store.projectExists(id)) {
        return jsonErr('Project not found', status: 404);
      }
      final members = await authStore.listProjectMembers(id);
      return Response.ok(jsonEncode({'ok': true, 'members': members}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.post('/projects/<id>/members', (Request request, String id) async {
    return _api(() async {
      final denied = await ensureProjectMembersManage(
        auth: authFrom(request)!,
        projectId: id,
        membership: authStore.membershipRole,
      );
      if (denied != null) return denied;
      try {
        final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
        final email = body['email']?.toString();
        final password = body['password']?.toString();
        final role = body['role']?.toString();
        if (email == null || email.trim().isEmpty) return jsonErr('email is required');
        if (role == null || role.isEmpty) return jsonErr('role is required');
        final member = await authStore.addProjectMember(
          projectId: id,
          email: email,
          password: password,
          role: role,
        );
        return Response.ok(jsonEncode({'ok': true, 'member': member}), headers: {'Content-Type': 'application/json'});
      } on ArgumentError catch (e) {
        return jsonErr(e.message ?? '$e', status: 400);
      }
    });
  });

  router.patch('/projects/<id>/members/<userId>', (Request request, String id, String userId) async {
    return _api(() async {
      final denied = await ensureProjectMembersManage(
        auth: authFrom(request)!,
        projectId: id,
        membership: authStore.membershipRole,
      );
      if (denied != null) return denied;
      try {
        final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
        final role = body['role']?.toString();
        if (role == null || role.isEmpty) return jsonErr('role is required');
        final member = await authStore.updateProjectMemberRole(projectId: id, userId: userId, role: role);
        return Response.ok(jsonEncode({'ok': true, 'member': member}), headers: {'Content-Type': 'application/json'});
      } on ArgumentError catch (e) {
        return jsonErr(e.message ?? '$e', status: 400);
      }
    });
  });

  router.delete('/projects/<id>/members/<userId>', (Request request, String id, String userId) async {
    return _api(() async {
      final denied = await ensureProjectMembersManage(
        auth: authFrom(request)!,
        projectId: id,
        membership: authStore.membershipRole,
      );
      if (denied != null) return denied;
      try {
        await authStore.removeProjectMember(projectId: id, userId: userId);
        return Response.ok('{"ok":true}', headers: {'Content-Type': 'application/json'});
      } on ArgumentError catch (e) {
        return jsonErr(e.message ?? '$e', status: 400);
      }
    });
  });

  router.get('/projects/<id>/dashboard-logs', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final q = request.url.queryParameters;
      final logs = await store.listDashboardLogs(
        id,
        level: q['level'],
        limit: int.tryParse(q['limit'] ?? '') ?? 100,
      );
      return Response.ok(jsonEncode({'ok': true, 'logs': logs}), headers: {'Content-Type': 'application/json'});
    });
  });

  router.post('/projects/<id>/dashboard-logs', (Request request, String id) async {
    return _api(() async {
      final guard = await _projectGuard(request, id, authStore);
      if (guard != null) return guard;
      final auth = authFrom(request)!;
      final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final message = body['message']?.toString().trim();
      if (message == null || message.isEmpty) return jsonErr('message is required');
      await store.appendDashboardLog(
        projectId: id,
        userId: auth.userId,
        level: body['level']?.toString() ?? 'error',
        message: message,
        route: body['route']?.toString(),
        context: body['context'] is Map ? Map<String, dynamic>.from(body['context'] as Map) : null,
      );
      return Response.ok('{"ok":true}', headers: {'Content-Type': 'application/json'});
    });
  });

  return router.call;
}
