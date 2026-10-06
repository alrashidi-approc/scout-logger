import 'package:shelf/shelf.dart';

import '../auth/auth_principal.dart';
import '../config/server_config.dart';
import '../services/jwt_service.dart';
import '../store/auth_store.dart';
import 'http_utils.dart';

const authContextKey = 'scout.auth';

AuthPrincipal? authFrom(Request request) => request.context[authContextKey] as AuthPrincipal?;

Future<AuthPrincipal?> resolveAuth(Request request, ServerConfig config, JwtService jwt, AuthStore auth) async {
  final bearer = bearerToken(request);
  if (bearer != null && bearer.isNotEmpty && !bearer.startsWith('sk_live_')) {
    final userId = jwt.verify(bearer)?.userId;
    if (userId != null) {
      final user = await auth.findUserById(userId);
      if (user != null && user['emailVerified'] == true) return auth.toPrincipal(user);
    }
  }
  if (config.dashboardApiKey.isNotEmpty) {
    final key = request.headers['x-api-key'] ?? request.headers['X-API-Key'];
    if (key != null && constantTimeEquals(key, config.dashboardApiKey)) return AuthPrincipal.apiKey();
  }
  return null;
}

Middleware requireAuth(ServerConfig config, JwtService jwt, AuthStore store) {
  return (Handler inner) => (Request request) async {
        final auth = await resolveAuth(request, config, jwt, store);
        if (auth == null) {
          return jsonErr('Unauthorized', status: 401);
        }
        return inner(request.change(context: {...request.context, authContextKey: auth}));
      };
}

Future<Response?> ensureProjectAccess({
  required AuthPrincipal auth,
  required String projectId,
  required Future<String?> Function(String userId, String projectId) membership,
  bool write = false,
}) async {
  if (auth.isAdmin) return null;
  final uid = auth.userId;
  if (uid == null) return jsonErr('Unauthorized', status: 401);
  final role = await membership(uid, projectId);
  if (!canAccessProject(auth, role)) return jsonErr('Project not found', status: 404);
  if (write && !canWriteProject(auth, role)) return jsonErr('Forbidden', status: 403);
  return null;
}

Future<Response?> ensureCredentialsAccess({
  required AuthPrincipal auth,
  required String projectId,
  required Future<String?> Function(String userId, String projectId) membership,
}) async {
  if (auth.isAdmin) return null;
  final uid = auth.userId;
  if (uid == null) return jsonErr('Unauthorized', status: 401);
  final role = await membership(uid, projectId);
  if (!canViewCredentials(auth, role)) return jsonErr('Forbidden', status: 403);
  return null;
}

Future<Response?> ensureProjectDelete({
  required AuthPrincipal auth,
  required String projectId,
  required Future<String?> Function(String userId, String projectId) membership,
}) async {
  if (auth.isAdmin) return null;
  final uid = auth.userId;
  if (uid == null) return jsonErr('Unauthorized', status: 401);
  final role = await membership(uid, projectId);
  if (!canDeleteProject(auth, role)) return jsonErr('Forbidden', status: 403);
  return null;
}

Future<Response?> ensureProjectMembersManage({
  required AuthPrincipal auth,
  required String projectId,
  required Future<String?> Function(String userId, String projectId) membership,
}) async {
  if (auth.isAdmin) return null;
  final uid = auth.userId;
  if (uid == null) return jsonErr('Unauthorized', status: 401);
  final role = await membership(uid, projectId);
  if (!canManageProjectMembers(auth, role)) return jsonErr('Forbidden', status: 403);
  return null;
}

Future<Response?> ensureProjectNotificationsManage({
  required AuthPrincipal auth,
  required String projectId,
  required Future<String?> Function(String userId, String projectId) membership,
}) async {
  if (auth.isAdmin) return null;
  final uid = auth.userId;
  if (uid == null) return jsonErr('Unauthorized', status: 401);
  final role = await membership(uid, projectId);
  if (!canManageProjectNotifications(auth, role)) return jsonErr('Forbidden', status: 403);
  return null;
}
