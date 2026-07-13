import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'api_client.dart';
import 'project_access_service.dart';

class AuthService extends ChangeNotifier {
  AuthService._();

  static final instance = AuthService._();

  static const _tokenKey = 'scout_auth_token';
  static const _rememberKey = 'scout_auth_remember';

  String? _token;
  Map<String, dynamic>? _user;
  bool _rememberMe = true;
  bool _ready = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get rememberMe => _rememberMe;
  bool get isReady => _ready;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  bool get isAdmin => user?['globalRole'] == 'admin';
  bool get isPlatformOwner => isAdmin || user?['isPlatformOwner'] == true;
  bool get canCreateProjects => isAdmin || user?['canCreateProjects'] == true;
  String get email => user?['email'] as String? ?? '';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _rememberMe = prefs.getBool(_rememberKey) ?? true;
    if (isLoggedIn) {
      final ok = await _restoreSession();
      if (!ok) await logout(silent: true);
    }
    _ready = true;
    notifyListeners();
    if (isLoggedIn) await ProjectAccessService.instance.load();
  }

  Future<bool> _restoreSession() async {
    try {
      await refreshSession();
      return true;
    } on _AuthFailure {
      return false;
    } catch (_) {
      try {
        await refreshMe();
        return true;
      } on _AuthFailure {
        return false;
      } catch (_) {
        return isLoggedIn;
      }
    }
  }

  Future<void> refreshMe() async {
    final res = await http.get(
      _uri('/api/auth/me'),
      headers: _headers(includeAuth: true),
    );
    if (res.statusCode == 401 || res.statusCode == 403) throw _AuthFailure();
    _ensureOk(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    _user = jsonMap(json['user']);
    notifyListeners();
  }

  Future<void> refreshSession() async {
    final res = await http.post(
      _uri('/api/auth/refresh'),
      headers: _headers(includeAuth: true),
      body: jsonEncode({'rememberMe': _rememberMe}),
    );
    if (res.statusCode == 401 || res.statusCode == 403) throw _AuthFailure();
    _ensureOk(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    await _persist(
      json['token'] as String,
      jsonMap(json['user']),
      rememberMe: json['rememberMe'] == true || _rememberMe,
    );
  }

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final res = await http.post(
      _uri('/api/auth/signup'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password, if (displayName != null) 'displayName': displayName}),
    );
    _ensureOk(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final token = json['token'] as String?;
    if (token != null) await _persist(token, jsonMap(json['user']), rememberMe: true);
    return json;
  }

  Future<void> login({
    required String email,
    required String password,
    bool rememberMe = true,
  }) async {
    final res = await http.post(
      _uri('/api/auth/login'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password, 'rememberMe': rememberMe}),
    );
    _ensureOk(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    await _persist(
      json['token'] as String,
      jsonMap(json['user']),
      rememberMe: json['rememberMe'] == true || rememberMe,
    );
  }

  Future<void> verifyEmail(String token) async {
    final res = await http.post(
      _uri('/api/auth/verify-email'),
      headers: _headers(),
      body: jsonEncode({'token': token}),
    );
    _ensureOk(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    await _persist(json['token'] as String, jsonMap(json['user']), rememberMe: true);
  }

  Future<String?> resendVerification(String email) async {
    final res = await http.post(
      _uri('/api/auth/resend-verification'),
      headers: _headers(),
      body: jsonEncode({'email': email}),
    );
    _ensureOk(res);
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['devVerificationUrl'] as String?;
  }

  Future<void> logout({bool silent = false}) async {
    _token = null;
    _user = null;
    ProjectAccessService.instance.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    if (!silent) notifyListeners();
  }

  Future<void> _persist(String token, Map<String, dynamic> user, {required bool rememberMe}) async {
    _token = token;
    _user = user;
    _rememberMe = rememberMe;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setBool(_rememberKey, rememberMe);
    notifyListeners();
    await ProjectAccessService.instance.load();
  }

  Uri _uri(String path) {
    final base = AppConfig.I.apiBaseUrl;
    if (base.isEmpty) return Uri(path: path);
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers({bool includeAuth = false}) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (includeAuth && _token != null) 'Authorization': 'Bearer $_token',
      };

  void _ensureOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    try {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(json['error']?.toString() ?? res.body);
    } catch (_) {
      throw Exception('Request failed (${res.statusCode})');
    }
  }
}

class _AuthFailure implements Exception {}
