import 'package:test/test.dart';

import 'package:scout_server/util/ids.dart';

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

  test('normalizeRoute collapses ids but preserves static segments', () {
    expect(normalizeRoute('/users/42/posts/7?x=1'), '/users/:id/posts/:id');
    expect(normalizeRoute('https://h/v1/a1b2c3d4e5f6a7b8/details'), '/v1/:id/details');
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
