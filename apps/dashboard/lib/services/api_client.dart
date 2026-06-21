import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
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
    PeriodFilter? period,
  }) async {
    final params = <String, String>{};
    if (type != null) params['type'] = type;
    if (status != null) params['status'] = status;
    if (q != null && q.isNotEmpty) params['q'] = q;
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
    PeriodFilter? period,
  }) async {
    final params = <String, String>{};
    if (type != null) params['type'] = type;
    if (level != null) params['level'] = level;
    if (category != null) params['category'] = category;
    if (q != null && q.isNotEmpty) params['q'] = q;
    if (country != null) params['country'] = country;
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

  void _ok(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw Exception('API ${res.statusCode}: ${res.body}');
  }
}
