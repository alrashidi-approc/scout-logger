import 'package:test/test.dart';

import 'package:scout_server/util/user_identity.dart';

void main() {
  test('guest when user id matches install id', () {
    const id = 'a1b2c3d4-e5f6-4789-a012-3456789abcde';
    expect(isGuestAppUser(userId: id, installId: id), isTrue);
    expect(isIdentifiedAppUser(userId: id, installId: id), isFalse);
  });

  test('identified when user id differs from install id', () {
    expect(
      isIdentifiedAppUser(userId: 'user-101', installId: 'a1b2c3d4-e5f6-4789-a012-3456789abcde'),
      isTrue,
    );
  });

  test('uuid-shaped id without install id treated as guest', () {
    const id = 'a1b2c3d4-e5f6-4789-a012-3456789abcde';
    expect(isGuestAppUser(userId: id, installId: null), isTrue);
    expect(isIdentifiedAppUser(userId: 'user-101', installId: null), isTrue);
  });

  test('install id from device payload', () {
    final id = installIdFromPayload({
      'device': {'installId': 'install-1', 'anonymousId': 'anon-1'},
      'user': {'id': 'anon-1'},
    });
    expect(id, 'install-1');
  });

  test('install id prefers device then user installId', () {
    expect(
      installIdFromPayload({
        'user': {'id': 'user-123', 'installId': 'device-abc', 'anonymousId': 'device-abc'},
        'device': {'installId': 'device-abc'},
      }),
      'device-abc',
    );
    expect(
      installIdFromPayload({
        'user': {'id': 'user-123', 'installId': 'device-abc'},
        'device': {},
      }),
      'device-abc',
    );
  });

  test('package guest vs logged-in payloads', () {
    expect(
      isGuestAppUser(
        userId: 'device-abc',
        installId: installIdFromPayload({
          'user': {'id': 'device-abc', 'installId': 'device-abc', 'anonymousId': 'device-abc'},
          'device': {'installId': 'device-abc'},
        }),
      ),
      isTrue,
    );
    expect(
      isIdentifiedAppUser(
        userId: 'user-123',
        installId: installIdFromPayload({
          'user': {'id': 'user-123', 'email': 'a@b.com', 'installId': 'device-abc', 'anonymousId': 'device-abc'},
          'device': {'installId': 'device-abc'},
        }),
      ),
      isTrue,
    );
  });

  test('user email from payload', () {
    expect(
      userEmailFromPayload({
        'user': {'id': 'user-123', 'email': 'dev@example.com'},
      }),
      'dev@example.com',
    );
  });
}
