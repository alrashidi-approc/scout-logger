import 'package:test/test.dart';

import 'package:scout_server/auth/auth_principal.dart';

void main() {
  const user = AuthPrincipal(userId: 'u1');

  test('canViewCredentials allows owner, admin, and global admin', () {
    expect(canViewCredentials(user, 'owner'), isTrue);
    expect(canViewCredentials(user, 'admin'), isTrue);
    expect(canViewCredentials(const AuthPrincipal(globalRole: 'admin'), null), isTrue);
    expect(canViewCredentials(AuthPrincipal.apiKey(), null), isTrue);
  });

  test('canViewCredentials denies other roles and non-members', () {
    for (final role in ['support', 'developer', 'qa', 'project_manager', 'member', 'viewer', null]) {
      expect(canViewCredentials(user, role), isFalse, reason: '$role');
    }
  });
}
