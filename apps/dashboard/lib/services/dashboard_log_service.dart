import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'auth_service.dart';
import 'dashboard_scope.dart';

/// Records dashboard UI / API issues server-side per project.
abstract final class DashboardLogService {
  static final _client = http.Client();
  static final _pending = <String>{};

  static void record({
    required String? projectId,
    required String message,
    String level = 'error',
    String? route,
    Map<String, dynamic>? context,
  }) {
    final pid = projectId ?? DashboardScope.projectId;
    if (pid == null || pid.isEmpty) return;
    final text = message.trim();
    if (text.isEmpty) return;

    final key = '$pid|$level|$text';
    if (_pending.contains(key)) return;
    _pending.add(key);
    unawaited(_send(
      pid,
      level: level,
      message: text.length > 2000 ? '${text.substring(0, 2000)}…' : text,
      route: route ?? DashboardScope.route,
      context: context,
    ).whenComplete(() => _pending.remove(key)));

    if (kDebugMode) debugPrint('[scout-dashboard][$level] $text');
  }

  static Future<void> _send(
    String projectId, {
    required String level,
    required String message,
    String? route,
    Map<String, dynamic>? context,
  }) async {
    try {
      final base = AppConfig.I.apiBaseUrl;
      final uri = base.isEmpty
          ? Uri(path: '/api/projects/$projectId/dashboard-logs')
          : Uri.parse('$base/api/projects/$projectId/dashboard-logs');
      final token = AuthService.instance.token;
      await _client.post(
        uri,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'level': level,
          'message': message,
          if (route != null) 'route': route,
          if (context != null && context.isNotEmpty) 'context': context,
        }),
      );
    } catch (_) {}
  }
}
