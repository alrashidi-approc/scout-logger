import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:scout_server/middleware/rate_limit.dart';

void main() {
  var now = DateTime.utc(2026);
  RateLimiter limiter() => RateLimiter(3, const Duration(minutes: 1), now: () => now);

  setUp(() => now = DateTime.utc(2026));

  test('allows up to limit, then returns positive wait', () {
    final l = limiter();
    expect([l.hit('a'), l.hit('a'), l.hit('a')], [null, null, null]);
    expect(l.hit('a'), 60);
    now = now.add(const Duration(seconds: 45));
    expect(l.hit('a'), 15);
    expect(l.hit('b'), isNull);
  });

  test('resets after window', () {
    final l = limiter();
    for (var i = 0; i < 4; i++) {
      l.hit('a');
    }
    now = now.add(const Duration(minutes: 1));
    expect(l.hit('a'), isNull);
  });

  test('check does not record hits', () {
    final l = limiter();
    for (var i = 0; i < 5; i++) {
      expect(l.check('a'), isNull);
    }
    l.hit('a');
    l.hit('a');
    expect(l.check('a'), isNull);
    l.hit('a');
    expect(l.check('a'), 60);
  });

  test('middleware returns 429 with Retry-After', () async {
    final handler = rateLimit(RateLimiter(1, const Duration(minutes: 1), now: () => now), (_) => 'ip')(
      (_) => Response.ok('ok'),
    );
    final req = Request('GET', Uri.parse('http://localhost/'));
    expect((await handler(req)).statusCode, 200);
    final blocked = await handler(req);
    expect(blocked.statusCode, 429);
    expect(blocked.headers['retry-after'], '60');
    expect(await blocked.readAsString(), contains('Too many requests'));
  });
}
