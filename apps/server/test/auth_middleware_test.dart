import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:scout_server/auth/auth_principal.dart';
import 'package:scout_server/config/env_file.dart';
import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/db/scout_db.dart';
import 'package:scout_server/middleware/auth_middleware.dart';
import 'package:scout_server/services/jwt_service.dart';
import 'package:scout_server/services/key_cipher.dart';
import 'package:scout_server/store/auth_store.dart';

class _FakeAuthStore extends AuthStore {
  _FakeAuthStore(this.users) : super(ScoutDb(DbConfig.fromUrl('postgres://u:p@localhost/scout')), cipher: KeyCipher('c' * 64));

  final Map<String, Map<String, dynamic>> users;

  @override
  Future<Map<String, dynamic>?> findUserById(String id) async => users[id];
}

void main() {
  final config = ServerConfig.load(
    env: EnvFile({'JWT_SECRET': 'a' * 64, 'ENCRYPTION_KEY': 'b' * 64, 'DATABASE_URL': 'postgres://u:p@localhost/scout'}),
  );
  final jwt = JwtService(secret: config.jwtSecret);
  Map<String, dynamic> user({bool verified = true}) => {
        'id': 'u1',
        'email': 'u1@x.com',
        'globalRole': 'user',
        'canCreateProjects': false,
        'emailVerified': verified,
      };
  final forgedAdmin = jwt.sign(
    const AuthPrincipal(userId: 'u1', email: 'u1@x.com', globalRole: 'admin', canCreateProjects: true),
    rememberMe: false,
  );

  Future<AuthPrincipal?> resolve(Map<String, Map<String, dynamic>> users) => resolveAuth(
        Request('GET', Uri.parse('http://localhost/api/projects'), headers: {'Authorization': 'Bearer $forgedAdmin'}),
        config,
        jwt,
        _FakeAuthStore(users),
      );

  test('role and canCreateProjects come from the DB, not the token', () async {
    final auth = await resolve({'u1': user()});
    expect(auth?.userId, 'u1');
    expect(auth?.isAdmin, isFalse);
    expect(auth?.canCreateProjects, isFalse);
  });

  test('rejects deleted users', () async {
    expect(await resolve({}), isNull);
  });

  test('rejects unverified users', () async {
    expect(await resolve({'u1': user(verified: false)}), isNull);
  });
}
