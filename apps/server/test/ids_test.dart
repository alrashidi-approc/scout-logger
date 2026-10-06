import 'package:test/test.dart';

import 'package:scout_server/util/ids.dart';
import 'package:scout_server/util/insights.dart';

void main() {
  test('same payload yields stable fingerprint', () {
    final fp1 = eventFingerprint('error', {'message': 'Payment failed', 'stack': 'at foo()'});
    final fp2 = eventFingerprint('error', {'message': 'Payment failed', 'stack': 'at foo()'});
    expect(fp1, fp2);
  });

  test('network title is method + normalized route', () {
    final title = eventTitle('network', {'method': 'POST', 'url': '/users/123?token=x', 'statusCode': 503});
    expect(title, 'POST /users/:id');
  });

  test('network groups same endpoint across ids, query and status', () {
    Map<String, dynamic> net(String url, int code) => {
          'network': {'method': 'GET', 'url': url, 'statusCode': code}
        };
    final a = eventFingerprint('network', net('https://api.co/users/123?a=1', 404));
    final b = eventFingerprint('network', net('https://api.co/users/456?a=2', 500));
    expect(a, b);
  });

  test('network keeps distinct endpoints and methods apart', () {
    final get = eventFingerprint('network', {'network': {'method': 'GET', 'url': '/users/1'}});
    final post = eventFingerprint('network', {'network': {'method': 'POST', 'url': '/users/1'}});
    final orders = eventFingerprint('network', {'network': {'method': 'GET', 'url': '/orders/1'}});
    expect(get, isNot(post));
    expect(get, isNot(orders));
  });

  test('network fingerprint is pinned (changing it splits existing issues)', () {
    final fp = eventFingerprint('network', {
      'network': {'method': 'get', 'url': 'https://api.co/v1/users/42/a1b2c3d4e5f6a7b8?x=1'}
    });
    expect(fp, '19a798391f984abcb4cfd7e6bcecca90895330419099119d4401c4ce754fb121');
  });

  group('fingerprint v2 (errors / crashes)', () {
    String crash(String message, {int line = 42, String culprit = 'CheckoutPage._pay', int frameNo = 2}) => '''
#0      _rootRun (dart:async/zone.dart:1399:13)
#1      StatelessElement.build (package:flutter/src/widgets/framework.dart:5$line:27)
#$frameNo      $culprit.<anonymous closure> (package:shop/checkout/checkout_page.dart:$line:7)
#3      ApiClient.post (package:shop/net/api_client.dart:${line + 80}:12)
<asynchronous suspension>
#4      main (package:shop/main.dart:9:3)''';
    Map<String, dynamic> event(String message, String stack) => {'message': message, 'stack': stack};

    test('same crash with different ids, numbers and line numbers groups together', () {
      final a = eventFingerprint('crash', event(
        "Order 1234 for user 3f2b8c1e-1d2a-4b5c-9d8e-0f1a2b3c4d5e failed: 'tok_9AbC' at https://api.shop.io/o/1?x=2 (a@b.io)",
        crash('x', line: 42),
      ));
      final b = eventFingerprint('crash', event(
        "Order 98 for user 0a1b2c3d-0000-4b5c-9d8e-ffffffffffff failed: 'tok_ZZ' at https://api.shop.io/o/77 (z@y.co)",
        crash('x', line: 57, frameNo: 5),
      ));
      expect(a, b);
      expect(a, startsWith('v2:'));
    });

    test('a different in-app culprit splits; framework frames are ignored', () {
      final base = eventFingerprint('error', event('Null check', crash('x')));
      expect(eventFingerprint('error', event('Null check', crash('x', culprit: 'CartPage._add'))), isNot(base));
      final noFramework = crash('x').split('\n').where((l) => !l.contains('package:flutter') && !l.contains('(dart:')).join('\n');
      expect(eventFingerprint('error', event('Null check', noFramework)), base);
    });

    test('no stack falls back to type + category + normalized message', () {
      final a = eventFingerprint('error', {'message': 'Timeout after 30s', 'category': 'sync'});
      expect(eventFingerprint('error', {'message': 'Timeout after 45s', 'category': 'sync'}), a);
      expect(eventFingerprint('error', {'message': 'Timeout after 45s', 'category': 'auth'}), isNot(a));
      expect(eventFingerprint('crash', {'message': 'Timeout after 45s', 'category': 'sync'}), isNot(a));
    });

    test('pinned (changing it splits v2 issues)', () {
      expect(
        eventFingerprint('error', event('Bad state: 3 items', crash('x'))),
        'v2:6b97e45e47847faf01af798f8d49b6270c0204e7b7731f62f26a7f51ecc7220c',
      );
    });

    test('normalizeMessage placeholders', () {
      expect(
        normalizeMessage('GET https://x.io/a?b=1 by me@x.io id 0xFF00 hash deadbeef42 "abc123" "two words" took 1.5s, 3 times'),
        'GET <url> by <email> id <id> hash <id> <str> "two words" took <num>s, <num> times',
      );
    });

    test('stackCulpritFromTrace uses the same parser', () {
      expect(stackCulpritFromTrace(crash('x')), startsWith('#2      CheckoutPage._pay.<anonymous closure>'));
      expect(stackFrames(crash('x')).map((f) => f.key).first, 'CheckoutPage._pay (package:shop/checkout/checkout_page.dart)');
    });
  });

  test('group hint needs failure_layer or platform_code and ignores volatile message parts', () {
    Map<String, dynamic> p(String msg, Map<String, dynamic> ctx) => {'message': msg, 'context': ctx};
    expect(issueGroupHint(p('x', {})), isNull);
    expect(issueGroupHint({'message': 'x'}), isNull);
    final hint = issueGroupHint(p('timeout after 3s', {'failure_layer': 'app_check', 'platform_code': 'HTTP_503'}));
    expect(issueGroupHint(p('timeout after 9s', {'failure_layer': 'app_check', 'platform_code': 'HTTP_503'})), hint);
    expect(issueGroupHint(p('timeout after 3s', {'failure_layer': 'bootstrap_api', 'platform_code': 'HTTP_503'})), isNot(hint));
    expect(issueGroupHint(p('timeout after 3s', {'platform_code': 'HTTP_503'})), isNotNull);
  });

  group('titles', () {
    test('diagnosis summary wins, with a confidence rank', () {
      final p = {
        'message': 'raw 123',
        'diagnosis': {'summary': 'App Check token unavailable', 'confidence': 'high'},
      };
      expect(eventTitle('error', p), 'App Check token unavailable');
      expect(titleRank(p), 3);
      expect(titleRank({'diagnosis': {'summary': 'x'}}), 2);
      expect(titleRank({'message': 'raw'}), 0);
    });

    test('network: METHOD route · faultLabel', () {
      expect(
        eventTitle('network', {
          'message': 'GET /users/7 failed',
          'network': {'method': 'GET', 'url': '/users/7', 'readable': {'faultLabel': 'Not found'}},
        }),
        'GET /users/:id · Not found',
      );
    });

    test('error: culpritFile: normalized message, else clipped message', () {
      const stack = '#0 Foo.bar (package:shop/cart/cart_page.dart:10:2)';
      expect(eventTitle('error', {'message': 'Item 42 missing', 'stack': stack}), 'cart_page.dart: Item <num> missing');
      expect(eventTitle('error', {'message': 'Item 42 missing'}), 'Item 42 missing');
    });
  });

  test('releaseFromPayload keeps release as sent, then falls back to release.id / app.*', () {
    expect(releaseFromPayload({'release': {'name': 'app@1.2', 'version': '1.2'}}), 'app@1.2');
    expect(releaseFromPayload({'release': {'version': '1.2'}}), '1.2');
    expect(releaseFromPayload({'release': ' 1.0 '}), ' 1.0 ');
    expect(releaseFromPayload({'release': 3}), '3');
    expect(releaseFromPayload({'release': {'id': 'r9'}}), 'r9');
    expect(releaseFromPayload({'app': {'version': ' 2.0 ', 'build': '7'}}), '2.0');
    expect(releaseFromPayload({'app': {'build': 7}}), '7');
    expect(releaseFromPayload({'release': {}, 'app': {'version': ' '}}), isNull);
    expect(releaseFromPayload({}), isNull);
  });

  test('buildDsn includes port from publicUrl', () {
    final dsn = buildDsn(
      publicUrl: 'http://46.62.217.25:8081',
      projectId: 'proj_01',
      rawKey: 'sk_live_abc',
    );
    expect(dsn, 'http://sk_live_abc@46.62.217.25:8081/proj_01');
  });
}
