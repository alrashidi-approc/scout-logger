import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../auth/auth_principal.dart';

class JwtService {
  JwtService({
    required this.secret,
    this.sessionTtlDays = 1,
    this.rememberTtlDays = 30,
  });

  final String secret;
  final int sessionTtlDays;
  final int rememberTtlDays;

  String sign(AuthPrincipal user, {required bool rememberMe}) {
    final ttl = rememberMe ? rememberTtlDays : sessionTtlDays;
    final jwt = JWT({
      'sub': user.userId,
      'email': user.email,
      'role': user.globalRole,
      'canCreate': user.canCreateProjects,
      'remember': rememberMe,
    });
    return jwt.sign(SecretKey(secret), expiresIn: Duration(days: ttl.clamp(1, 365)));
  }

  AuthPrincipal? verify(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(secret));
      final p = jwt.payload;
      if (p is! Map) return null;
      return AuthPrincipal(
        userId: p['sub']?.toString(),
        email: p['email']?.toString(),
        globalRole: p['role']?.toString() ?? 'user',
        canCreateProjects: p['canCreate'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  bool? rememberMeFromToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(secret));
      final p = jwt.payload;
      if (p is! Map) return null;
      return p['remember'] == true;
    } catch (_) {
      return null;
    }
  }
}
