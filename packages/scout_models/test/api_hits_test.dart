import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  group('apiEndpointPath', () {
    test('drops scheme, query and fragment', () {
      expect(
        apiEndpointPath('https://falcon.epa.gov.kw/epa_bridge/api/ssn-details?serial=2319037902&ssn=295060100063'),
        'falcon.epa.gov.kw/epa_bridge/api/ssn-details',
      );
      expect(apiEndpointPath('http://h:8080/a#frag'), 'h:8080/a');
    });

    test('collapses numeric and uuid segments, not the host', () {
      expect(apiEndpointPath('https://h/users/123/orders/456'), 'h/users/:id/orders/:id');
      expect(apiEndpointPath('https://h/doc/3F2504E0-4F89-11D3-9A0C-0305E82C3301'), 'h/doc/:id');
      expect(apiEndpointPath('https://h/v2/users'), 'h/v2/users');
      expect(apiEndpointPath('/users/42'), '/users/:id');
    });

    test('trims trailing slashes but keeps root', () {
      expect(apiEndpointPath('https://h/a/'), 'h/a');
      expect(apiEndpointPath('/'), '/');
    });
  });

  test('apiEndpointMethod upper-cases and defaults', () {
    expect(apiEndpointMethod('get'), 'GET');
    expect(apiEndpointMethod(null), 'REQUEST');
    expect(apiEndpointMethod('  '), 'REQUEST');
  });

  group('parseApiEndpointFilter', () {
    test('plain URL has no method', () {
      final f = parseApiEndpointFilter('https://h/api/x?y=1');
      expect(f?.method, isNull);
      expect(f?.path, 'h/api/x');
    });

    test('METHOD prefix is split out', () {
      final f = parseApiEndpointFilter('post https://h/api/x');
      expect(f?.method, 'POST');
      expect(f?.path, 'h/api/x');
    });

    test('empty input is null', () {
      expect(parseApiEndpointFilter('  '), isNull);
      expect(parseApiEndpointFilter(null), isNull);
    });
  });

  group('ApiHitsConfig', () {
    test('defaults to hidden', () {
      expect(ApiHitsConfig.fromJson(null).resolved().visible, isFalse);
      expect(const ApiHitsConfig().toJson(), {'visible': false});
    });

    test('mergePatch sets visible only when present', () {
      const on = ApiHitsConfig(visible: true);
      expect(on.mergePatch({}).visible, isTrue);
      expect(on.mergePatch({'visible': false}).visible, isFalse);
      expect(ApiHitsConfig.fromJson({'visible': true}).toJson(), {'visible': true});
    });
  });
}
