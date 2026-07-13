import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'auth_service.dart';

/// Cached project membership for router guards.
class ProjectAccessService extends ChangeNotifier {
  ProjectAccessService._();

  static final instance = ProjectAccessService._();

  final _api = ScoutApi();
  final Map<String, String> _roles = {};
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    final auth = AuthService.instance;
    if (!auth.isLoggedIn) {
      _roles.clear();
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final projects = await _api.fetchProjects();
      _roles
        ..clear()
        ..addEntries(projects.map((p) => MapEntry(p['id'] as String, (p['role'] as String?) ?? 'member')));
    } catch (_) {
      _roles.clear();
    }
    _loaded = true;
    notifyListeners();
  }

  void clear() {
    _roles.clear();
    _loaded = false;
    notifyListeners();
  }

  bool canAccess(String projectId) => AuthService.instance.isAdmin || _roles.containsKey(projectId);

  String? role(String projectId) => AuthService.instance.isAdmin ? 'admin' : _roles[projectId];

  bool canManageNotifications(String projectId) {
    final auth = AuthService.instance;
    if (auth.isAdmin || auth.isPlatformOwner) return true;
    final r = _roles[projectId];
    return r == 'owner' || r == 'admin';
  }

  bool canManageMembers(String projectId) {
    final auth = AuthService.instance;
    if (auth.isAdmin || auth.isPlatformOwner) return true;
    final r = _roles[projectId];
    return r == 'owner' || r == 'admin';
  }
}
