import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../auth/auth_principal.dart';

class JwtService {
  JwtService({required this.secret, this.ttlDays = 7});

  final String secret;
  final int ttlDays;

  String sign(AuthPrincipal user) {
    final jwt = JWT({
      'sub': user.userId,
      'email': user.email,
      'role': user.globalRole,
      'canCreate': user.canCreateProjects,
    });
    return jwt.sign(SecretKey(secret), expiresIn: Duration(days: ttlDays));
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
}
