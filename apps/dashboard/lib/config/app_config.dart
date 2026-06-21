import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Loaded at startup from the server (`/api/dashboard/config`).
class AppConfig {
  AppConfig._({required this.apiBaseUrl, required this.authRequired, required this.emailVerification});

  static AppConfig? _instance;

  static AppConfig get I {
    final v = _instance;
    if (v == null) throw StateError('Call AppConfig.load() before runApp()');
    return v;
  }

  final String apiBaseUrl;
  final bool authRequired;
  final bool emailVerification;

  static Future<void> load() async {
    final origins = <String>[Uri.base.origin];

    try {
      final raw = await rootBundle.loadString('bootstrap.json');
      final bootstrap = jsonDecode(raw) as Map<String, dynamic>;
      final url = bootstrap['publicUrl'] as String?;
      if (url != null && url.isNotEmpty) origins.insert(0, url.replaceAll(RegExp(r'/+$'), ''));
    } catch (_) {}

    Object? lastError;
    for (final origin in origins.toSet()) {
      try {
        final res = await http.get(Uri.parse('$origin/api/dashboard/config'));
        if (res.statusCode != 200) continue;
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final base = json['apiBaseUrl'] as String? ?? '';
        _instance = AppConfig._(
          apiBaseUrl: base.isNotEmpty ? base.replaceAll(RegExp(r'/+$'), '') : origin,
          authRequired: json['authRequired'] != false,
          emailVerification: json['emailVerification'] == true,
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('Could not load /api/dashboard/config ($lastError)');
  }
}
