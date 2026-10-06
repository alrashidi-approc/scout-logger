import 'package:shelf/shelf.dart';

import 'http_utils.dart';

/// Fixed-window, in-memory counter per key.
class RateLimiter {
  RateLimiter(this.limit, this.window, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final int limit;
  final Duration window;
  final DateTime Function() _now;
  final _hits = <String, (DateTime, int)>{};

  /// Records a hit; returns seconds to wait when [key] is over [limit], else null.
  int? hit(String key) {
    final now = _now();
    if (_hits.length > 10000) _hits.removeWhere((_, w) => !_active(w, now));
    final w = _hits[key];
    final (start, count) = w != null && _active(w, now) ? w : (now, 0);
    _hits[key] = (start, count + 1);
    return count < limit ? null : _wait(start, now);
  }

  /// Like [hit] but without recording.
  int? check(String key) {
    final now = _now();
    final w = _hits[key];
    return w != null && _active(w, now) && w.$2 >= limit ? _wait(w.$1, now) : null;
  }

  bool _active((DateTime, int) w, DateTime now) => now.difference(w.$1) < window;

  int _wait(DateTime start, DateTime now) => ((window - now.difference(start)).inMilliseconds / 1000).ceil();
}

Response tooManyRequests(int retryAfter) =>
    jsonErr('Too many requests', status: 429).change(headers: {'Retry-After': '$retryAfter'});

/// Requests with a null key (e.g. no socket address, no bearer token) are not limited.
Middleware rateLimit(RateLimiter limiter, String? Function(Request) key) => (Handler inner) => (Request request) {
      final k = key(request);
      final wait = k == null ? null : limiter.hit(k);
      return wait == null ? inner(request) : tooManyRequests(wait);
    };
