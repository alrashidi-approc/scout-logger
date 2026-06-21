import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../middleware/auth_middleware.dart';
import '../middleware/http_utils.dart';
import '../store/auth_store.dart';

Handler adminRoutes({required AuthStore auth}) {
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

  return router.call;
}

Handler meRoute({required AuthStore auth}) {
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
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final user = await auth.findUserById(principal.userId!);
    if (user == null) return jsonErr('User not found', status: 404);
    return Response.ok(jsonEncode({'ok': true, 'user': auth.publicUser(user)}), headers: {'Content-Type': 'application/json'});
  };
}
