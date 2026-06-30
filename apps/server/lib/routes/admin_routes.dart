import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config/server_config.dart';
import 'package:scout_models/scout_models.dart';

import '../auth/auth_principal.dart';
import '../middleware/auth_middleware.dart';
import '../middleware/http_utils.dart';
import '../store/auth_store.dart';
import '../store/platform_store.dart';

Handler adminRoutes({
  required AuthStore auth,
  required ServerConfig config,
  required PlatformStore platformStore,
}) {
  final router = Router();

  router.get('/users', (Request request) async {
    final principal = authFrom(request)!;
    if (!principal.isAdmin) return jsonErr('Admin access required', status: 403);
    final users = await auth.listUsers();
    return Response.ok(jsonEncode({'ok': true, 'users': users}), headers: {'Content-Type': 'application/json'});
  });

  router.patch('/users/<id>', (Request request, String id) async {
    final principal = authFrom(request)!;
    if (!principal.isAdmin) return jsonErr('Admin access required', status: 403);
    try {
      final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final role = body['globalRole']?.toString();
      if (role != null && role != 'admin' && role != 'user') return jsonErr('Invalid globalRole');
      final user = await auth.updateUser(
        userId: id,
        globalRole: role,
        canCreateProjects: body.containsKey('canCreateProjects') ? body['canCreateProjects'] == true : null,
        displayName: body['displayName']?.toString(),
      );
      return Response.ok(jsonEncode({'ok': true, 'user': auth.publicUser(user)}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  router.post('/users/<id>/unverify', (Request request, String id) async {
    final principal = authFrom(request)!;
    if (!principal.isAdmin) return jsonErr('Admin access required', status: 403);
    if (principal.userId == id) return jsonErr('You cannot unverify your own account');
    try {
      final user = await auth.setUnverified(id);
      if (user == null) return jsonErr('User not found', status: 404);
      return Response.ok(jsonEncode({'ok': true, 'user': auth.publicUser(user)}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  router.delete('/users/<id>', (Request request, String id) async {
    final principal = authFrom(request)!;
    if (!principal.isAdmin) return jsonErr('Admin access required', status: 403);
    if (principal.userId == id) return jsonErr('You cannot delete your own account');
    try {
      final target = await auth.findUserById(id);
      if (target == null) return jsonErr('User not found', status: 404);
      if (target['globalRole'] == 'admin' && await auth.adminCount() <= 1) {
        return jsonErr('Cannot delete the last admin');
      }
      await auth.deleteUser(id);
      return Response.ok(jsonEncode({'ok': true}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  router.get('/notification-policy', (Request request) async {
    final principal = authFrom(request)!;
    if (!isPlatformOwner(principal, config.platformOwnerEmail)) {
      return jsonErr('Platform owner access required', status: 403);
    }
    final policy = await platformStore.getNotificationPolicy();
    return Response.ok(jsonEncode({'ok': true, 'policy': policy.toJson()}), headers: {'Content-Type': 'application/json'});
  });

  router.patch('/notification-policy', (Request request) async {
    final principal = authFrom(request)!;
    if (!isPlatformOwner(principal, config.platformOwnerEmail)) {
      return jsonErr('Platform owner access required', status: 403);
    }
    try {
      final body = jsonDecode(await readBody(request)) as Map<String, dynamic>;
      final raw = body['policy'] is Map ? Map<String, dynamic>.from(body['policy'] as Map) : body;
      final policy = PlatformNotificationPolicy.fromJson(raw);
      final saved = await platformStore.updateNotificationPolicy(policy);
      return Response.ok(jsonEncode({'ok': true, 'policy': saved.toJson()}), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      return jsonErr('$e', status: 500);
    }
  });

  return router.call;
}

Handler meRoute({required AuthStore auth, required ServerConfig config}) {
  return (Request request) async {
    final principal = authFrom(request)!;
    if (principal.apiKeyBypass) {
      return Response.ok(
        jsonEncode({
          'ok': true,
          'user': {
            'id': 'api-key',
            'email': 'api-key@local',
            'displayName': 'API Key',
            'globalRole': 'admin',
            'canCreateProjects': true,
            'emailVerified': true,
            'isPlatformOwner': true,
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final user = await auth.findUserById(principal.userId!);
    if (user == null) return jsonErr('User not found', status: 404);
    final public = auth.publicUser(user);
    public['isPlatformOwner'] = isPlatformOwner(principal, config.platformOwnerEmail);
    return Response.ok(jsonEncode({'ok': true, 'user': public}), headers: {'Content-Type': 'application/json'});
  };
}
