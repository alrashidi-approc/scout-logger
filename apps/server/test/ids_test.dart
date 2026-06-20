import 'package:test/test.dart';

import 'package:scout_server/util/ids.dart';

void main() {
  test('same payload yields stable fingerprint', () {
    final fp1 = eventFingerprint('error', {'message': 'Payment failed', 'stack': 'at foo()'});
    final fp2 = eventFingerprint('error', {'message': 'Payment failed', 'stack': 'at foo()'});
    expect(fp1, fp2);
  });

  test('network title includes status', () {
    final title = eventTitle('network', {'method': 'POST', 'url': '/pay', 'statusCode': 503});
    expect(title, contains('503'));
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
