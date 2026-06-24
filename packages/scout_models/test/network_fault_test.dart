import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  group('classifyNetworkFault', () {
    test('500 is critical server error', () {
      final f = classifyNetworkFault({'statusCode': 500});
      expect(f.faultClass, NetworkFaultClass.critical);
      expect(f.kind, 'server_error');
      expect(f.alertWorthy, isTrue);
      expect(f.issueWorthy, isTrue);
    });

    test('404 is critical missing endpoint', () {
      final f = classifyNetworkFault({'statusCode': 404});
      expect(f.faultClass, NetworkFaultClass.critical);
      expect(f.kind, 'endpoint_missing');
    });

    test('401 is auth not critical', () {
      final f = classifyNetworkFault({'statusCode': 401});
      expect(f.faultClass, NetworkFaultClass.auth);
      expect(f.alertWorthy, isFalse);
      expect(f.issueWorthy, isFalse);
    });

    test('422 is user validation', () {
      final f = classifyNetworkFault({'statusCode': 422});
      expect(f.faultClass, NetworkFaultClass.user);
      expect(f.operationalError, isFalse);
    });

    test('200 is success', () {
      final f = classifyNetworkFault({'statusCode': 200});
      expect(f.faultClass, NetworkFaultClass.success);
    });

    test('transport failure is critical', () {
      final f = classifyNetworkFault({'error': 'SocketException'});
      expect(f.faultClass, NetworkFaultClass.critical);
      expect(f.kind, 'transport');
    });

    test('project override can reclassify 404 as user', () {
      final f = classifyNetworkFault(
        {'statusCode': 404},
        faultOverrides: {404: NetworkFaultClass.user},
      );
      expect(f.faultClass, NetworkFaultClass.user);
      expect(f.issueWorthy, isFalse);
    });

    test('project override can treat 401 as success', () {
      final f = classifyNetworkFault(
        {'statusCode': 401},
        faultOverrides: {401: NetworkFaultClass.success},
      );
      expect(f.faultClass, NetworkFaultClass.success);
      expect(f.issueWorthy, isFalse);
    });
  });

  group('networkReadableFrom', () {
    test('includes fault on readable', () {
      final r = networkReadableFrom({
        'method': 'POST',
        'url': '/api/pay',
        'statusCode': 422,
      });
      expect(r['faultClass'], 'user');
      expect(r['faultKind'], 'validation');
      expect(r['actionHint'], isNotEmpty);
    });
  });
}
