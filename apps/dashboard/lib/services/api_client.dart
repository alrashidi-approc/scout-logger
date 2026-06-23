import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'dashboard_log_service.dart';
import '../utils/date_range.dart';
import 'auth_service.dart';

List<Map<String, dynamic>> jsonListMaps(dynamic value) {
  if (value is! List) return [];
  return [for (final item in value) Map<String, dynamic>.from(item as Map)];
}

Map<String, dynamic> jsonMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

double? jsonNum(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value');

int? jsonInt(dynamic value) => value is int ? value : value is num ? value.toInt() : int.tryParse('$value');

String jsonPct(dynamic value, {String fallback = '0'}) {
  final n = jsonNum(value);
  return n == null ? fallback : n.toStringAsFixed(1);
}

class ScoutApi {
  ScoutApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) {
    final base = AppConfig.I.apiBaseUrl;
    if (base.isEmpty) return Uri(path: path);
    return Uri.parse('$base$path');
  }

  Map<String, String> get _headers {
    final auth = AuthService.instance.token;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (auth != null && auth.isNotEmpty) 'Authorization': 'Bearer $auth',
    };
  }

  Future<Map<String, dynamic>> fetchMe() async {
    final res = await _client.get(_uri('/api/auth/me'), headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['user']);
  }

  Future<List<Map<String, dynamic>>> fetchAdminUsers() async {
    final res = await _client.get(_uri('/api/admin/users'), headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['users']);
  }

  Future<Map<String, dynamic>> updateAdminUser(
    String userId, {
    String? globalRole,
    bool? canCreateProjects,
  }) async {
    final body = <String, dynamic>{};
    if (globalRole != null) body['globalRole'] = globalRole;
    if (canCreateProjects != null) body['canCreateProjects'] = canCreateProjects;
    final res = await _client.patch(_uri('/api/admin/users/$userId'), headers: _headers, body: jsonEncode(body));
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['user']);
  }

  Future<Map<String, dynamic>> fetchProjectCredentials(String projectId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/credentials'), headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['credentials']);
  }

  Future<List<Map<String, dynamic>>> fetchProjects() async {
    final res = await _client.get(_uri('/api/projects'), headers: _headers);
    _ok(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return jsonListMaps(json['projects']);
  }

  Future<Map<String, dynamic>> createProject(String name) async {
    final res = await _client.post(
      _uri('/api/projects'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['project']);
  }

  Future<void> deleteProject(String projectId) async {
    final res = await _client.delete(_uri('/api/projects/$projectId'), headers: _headers);
    _ok(res);
  }

  Future<Map<String, dynamic>> purgeProjectData(String projectId, {required PeriodFilter period}) async {
    final uri = _uri('/api/projects/$projectId/data').replace(queryParameters: period.toQuery());
    final res = await _client.delete(uri, headers: _headers);
    _ok(res);
    return jsonMap(jsonDecode(res.body) as Map);
  }

  Future<Map<String, dynamic>> fetchFilterFacets(String projectId, {PeriodFilter? period}) async {
    final uri = _uri('/api/projects/$projectId/facets').replace(queryParameters: (period ?? const PeriodFilter.days(30)).toQuery());
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['facets']);
  }

  Future<Map<String, dynamic>> fetchOverview(String projectId, {PeriodFilter? period}) async {
    final uri = _uri('/api/projects/$projectId/overview').replace(queryParameters: (period ?? const PeriodFilter.days(1)).toQuery());
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['overview']);
  }

  Future<Map<String, dynamic>> fetchDashboard(String projectId, {PeriodFilter? period}) async {
    final uri = _uri('/api/projects/$projectId/dashboard').replace(queryParameters: (period ?? const PeriodFilter.days(7)).toQuery());
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['dashboard']);
  }

  Future<List<Map<String, dynamic>>> fetchUsers(String projectId, {PeriodFilter? period, int limit = 100}) async {
    final uri = _uri('/api/projects/$projectId/users').replace(queryParameters: {...(period ?? const PeriodFilter.days(30)).toQuery(), 'limit': '$limit'});
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['users']);
  }

  Future<Map<String, dynamic>> fetchUser(String projectId, String userId, {PeriodFilter? period}) async {
    final uri = _uri('/api/projects/$projectId/users/$userId').replace(queryParameters: (period ?? const PeriodFilter.days(30)).toQuery());
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['user']);
  }

  Future<Map<String, dynamic>> fetchStats(String projectId, {PeriodFilter? period}) async {
    final uri = _uri('/api/projects/$projectId/stats').replace(queryParameters: (period ?? const PeriodFilter.days(7)).toQuery());
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['stats']);
  }

  Future<List<Map<String, dynamic>>> fetchIssues(
    String projectId, {
    String? type,
    String? status,
    String? q,
    String? environment,
    String? appVersion,
    PeriodFilter? period,
  }) async {
    final params = <String, String>{};
    if (type != null) params['type'] = type;
    if (status != null) params['status'] = status;
    if (q != null && q.isNotEmpty) params['q'] = q;
    if (environment != null) params['environment'] = environment;
    if (appVersion != null) params['appVersion'] = appVersion;
    if (period != null) params.addAll(period.toQuery());
    final uri = _uri('/api/projects/$projectId/issues').replace(queryParameters: params.isEmpty ? null : params);
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['issues']);
  }

  Future<Map<String, dynamic>> fetchIssue(String projectId, String issueId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/issues/$issueId'), headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['issue']);
  }

  Future<List<Map<String, dynamic>>> fetchEvents(
    String projectId, {
    String? type,
    String? level,
    String? category,
    String? q,
    String? country,
    String? environment,
    String? appVersion,
    PeriodFilter? period,
  }) async {
    final params = <String, String>{};
    if (type != null) params['type'] = type;
    if (level != null) params['level'] = level;
    if (category != null) params['category'] = category;
    if (q != null && q.isNotEmpty) params['q'] = q;
    if (country != null) params['country'] = country;
    if (environment != null) params['environment'] = environment;
    if (appVersion != null) params['appVersion'] = appVersion;
    if (period != null) params.addAll(period.toQuery());
    final uri = _uri('/api/projects/$projectId/events').replace(queryParameters: params.isEmpty ? null : params);
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['events']);
  }

  Future<Map<String, dynamic>> updateIssueStatus(
    String projectId,
    String issueId,
    String status,
  ) async {
    final res = await _client.patch(
      _uri('/api/projects/$projectId/issues/$issueId'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['issue']);
  }

  Future<Map<String, dynamic>> fetchEvent(String projectId, String eventId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/events/$eventId'), headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['event']);
  }

  Future<List<Map<String, dynamic>>> fetchGeo(String projectId, {PeriodFilter? period}) async {
    final uri = _uri('/api/projects/$projectId/geo').replace(queryParameters: (period ?? const PeriodFilter.days(7)).toQuery());
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['geo']);
  }

  Future<List<String>> fetchRoutes(String projectId, {PeriodFilter? period}) async {
    final uri = _uri('/api/projects/$projectId/analytics/routes').replace(queryParameters: (period ?? const PeriodFilter.days(30)).toQuery());
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    final routes = (jsonDecode(res.body) as Map)['routes'];
    if (routes is! List) return [];
    return routes.map((r) => r.toString()).toList();
  }

  Future<Map<String, dynamic>> fetchFunnel(String projectId, List<String> steps, {PeriodFilter? period}) async {
    final uri = _uri('/api/projects/$projectId/analytics/funnel').replace(queryParameters: {
      'steps': steps.join(','),
      ...(period ?? const PeriodFilter.days(30)).toQuery(),
    });
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['funnel']);
  }

  Future<Map<String, dynamic>> fetchRetention(String projectId, {int weeks = 8}) async {
    final uri = _uri('/api/projects/$projectId/analytics/retention').replace(queryParameters: {'weeks': '$weeks'});
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['retention']);
  }

  Future<List<Map<String, dynamic>>> fetchReleaseComparison(String projectId, {PeriodFilter? period}) async {
    final uri = _uri('/api/projects/$projectId/analytics/releases').replace(queryParameters: (period ?? const PeriodFilter.days(30)).toQuery());
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['releases']);
  }

  Future<List<Map<String, dynamic>>> fetchSessions(String projectId, {PeriodFilter? period, int limit = 50}) async {
    final uri = _uri('/api/projects/$projectId/sessions').replace(queryParameters: {...(period ?? const PeriodFilter.days(7)).toQuery(), 'limit': '$limit'});
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['sessions']);
  }

  Future<Map<String, dynamic>> fetchSessionTimeline(String projectId, String sessionId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/sessions/$sessionId/timeline'), headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['session']);
  }

  Future<Map<String, dynamic>> fetchProjectSettings(String projectId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/settings'), headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['settings']);
  }

  Future<Map<String, dynamic>> updateProjectSettings(String projectId, Map<String, dynamic> body) async {
    final res = await _client.patch(
      _uri('/api/projects/$projectId/settings'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _ok(res, projectId: projectId);
    return jsonMap((jsonDecode(res.body) as Map)['settings']);
  }

  Future<List<Map<String, dynamic>>> fetchProjectMembers(String projectId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/members'), headers: _headers);
    _ok(res, projectId: projectId);
    return jsonListMaps((jsonDecode(res.body) as Map)['members']);
  }

  Future<Map<String, dynamic>> addProjectMember(
    String projectId, {
    required String email,
    required String password,
    required String role,
  }) async {
    final res = await _client.post(
      _uri('/api/projects/$projectId/members'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password, 'role': role}),
    );
    _ok(res, projectId: projectId);
    return jsonMap((jsonDecode(res.body) as Map)['member']);
  }

  Future<Map<String, dynamic>> updateProjectMemberRole(String projectId, String userId, String role) async {
    final res = await _client.patch(
      _uri('/api/projects/$projectId/members/$userId'),
      headers: _headers,
      body: jsonEncode({'role': role}),
    );
    _ok(res, projectId: projectId);
    return jsonMap((jsonDecode(res.body) as Map)['member']);
  }

  Future<void> removeProjectMember(String projectId, String userId) async {
    final res = await _client.delete(_uri('/api/projects/$projectId/members/$userId'), headers: _headers);
    _ok(res, projectId: projectId);
  }

  Future<List<Map<String, dynamic>>> fetchDashboardLogs(String projectId, {String? level, int limit = 100}) async {
    final params = <String, String>{'limit': '$limit'};
    if (level != null) params['level'] = level;
    final uri = _uri('/api/projects/$projectId/dashboard-logs').replace(queryParameters: params);
    final res = await _client.get(uri, headers: _headers);
    _ok(res, projectId: projectId);
    return jsonListMaps((jsonDecode(res.body) as Map)['logs']);
  }

  static String? _projectFromPath(String path) {
    final m = RegExp(r'/projects/([^/]+)').firstMatch(path);
    return m?.group(1);
  }

  String _formatErr(http.Response res) {
    try {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final err = json['error']?.toString();
      if (err != null && err.isNotEmpty) return 'API ${res.statusCode}: $err';
    } catch (_) {}
    final body = res.body.trim();
    if (body.isEmpty) return 'API ${res.statusCode}';
    return 'API ${res.statusCode}: ${body.length > 200 ? '${body.substring(0, 200)}…' : body}';
  }

  void _ok(http.Response res, {String? projectId}) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    final path = res.request?.url.path ?? '';
    final pid = projectId ?? _projectFromPath(path);
    final err = _formatErr(res);
    if (pid != null && !path.contains('/dashboard-logs')) {
      DashboardLogService.record(
        projectId: pid,
        message: err,
        context: {'path': path, 'status': res.statusCode},
      );
    }
    throw Exception(err);
  }
}
