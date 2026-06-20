import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

List<Map<String, dynamic>> jsonListMaps(dynamic value) {
  if (value is! List) return [];
  return [for (final item in value) Map<String, dynamic>.from(item as Map)];
}

Map<String, dynamic> jsonMap(dynamic value) => Map<String, dynamic>.from(value as Map);

class ScoutApi {
  ScoutApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) {
    final base = AppConfig.I.apiBaseUrl;
    if (base.isEmpty) return Uri(path: path);
    return Uri.parse('$base$path');
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (AppConfig.I.apiKey.isNotEmpty) 'X-API-Key': AppConfig.I.apiKey,
      };

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

  Future<Map<String, dynamic>> fetchOverview(String projectId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/overview'), headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['overview']);
  }

  Future<List<Map<String, dynamic>>> fetchIssues(String projectId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/issues'), headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['issues']);
  }

  Future<Map<String, dynamic>> fetchIssue(String projectId, String issueId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/issues/$issueId'), headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['issue']);
  }

  Future<List<Map<String, dynamic>>> fetchEvents(String projectId, {String? type}) async {
    final uri = _uri('/api/projects/$projectId/events').replace(queryParameters: type != null ? {'type': type} : null);
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['events']);
  }

  Future<Map<String, dynamic>> fetchEvent(String projectId, String eventId) async {
    final res = await _client.get(_uri('/api/projects/$projectId/events/$eventId'), headers: _headers);
    _ok(res);
    return jsonMap((jsonDecode(res.body) as Map)['event']);
  }

  Future<List<Map<String, dynamic>>> fetchGeo(String projectId, {int days = 7}) async {
    final uri = _uri('/api/projects/$projectId/geo').replace(queryParameters: {'days': '$days'});
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['geo']);
  }

  Future<List<String>> fetchRoutes(String projectId, {int days = 30}) async {
    final uri = _uri('/api/projects/$projectId/analytics/routes').replace(queryParameters: {'days': '$days'});
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    final routes = (jsonDecode(res.body) as Map)['routes'];
    if (routes is! List) return [];
    return routes.map((r) => r.toString()).toList();
  }

  Future<Map<String, dynamic>> fetchFunnel(String projectId, List<String> steps, {int days = 30}) async {
    final uri = _uri('/api/projects/$projectId/analytics/funnel').replace(queryParameters: {
      'steps': steps.join(','),
      'days': '$days',
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

  Future<List<Map<String, dynamic>>> fetchReleaseComparison(String projectId, {int days = 30}) async {
    final uri = _uri('/api/projects/$projectId/analytics/releases').replace(queryParameters: {'days': '$days'});
    final res = await _client.get(uri, headers: _headers);
    _ok(res);
    return jsonListMaps((jsonDecode(res.body) as Map)['releases']);
  }

  Future<List<Map<String, dynamic>>> fetchSessions(String projectId, {int days = 7, int limit = 50}) async {
    final uri = _uri('/api/projects/$projectId/sessions').replace(queryParameters: {'days': '$days', 'limit': '$limit'});
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
