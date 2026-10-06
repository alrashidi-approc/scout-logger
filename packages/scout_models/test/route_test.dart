import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  test('normalizeRoute output is pinned (feeds issue fingerprints)', () {
    const fixtures = {
      '': '',
      '/': '/',
      '/users/42/posts/7?x=1': '/users/:id/posts/:id',
      'https://h/v1/a1b2c3d4e5f6a7b8/details': '/v1/:id/details',
      'https://api.co/users/123?a=1#frag': '/users/:id',
      '/users/42/': '/users/:id/',
      'users/42': 'users/:id',
      '/u/550e8400-e29b-41d4-a716-446655440000/x': '/u/:id/x',
      '/u/550E8400-E29B-41D4-A716-446655440000': '/u/:id',
      '/h/ABCDEF0123456789': '/h/:id',
      '/h/abcdef012345678': '/h/abcdef012345678',
      '/v2/123abc/items': '/v2/123abc/items',
      '/a/-1': '/a/-1',
      '?x=1': '',
      '#frag': '',
      'https://h': 'https://h',
      'http://[bad/1?x': 'http://[bad/:id',
    };
    for (final e in fixtures.entries) {
      expect(normalizeRoute(e.key), e.value, reason: e.key);
    }
  });

  test('isDynamicSegment', () {
    expect(isDynamicSegment('42'), isTrue);
    expect(isDynamicSegment('a1b2c3d4e5f6a7b8'), isTrue);
    expect(isDynamicSegment('users'), isFalse);
    expect(isDynamicSegment(''), isFalse);
  });
}
