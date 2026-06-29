import 'package:scout_server/util/event_filters.dart';
import 'package:test/test.dart';

void main() {
  group('isErrorEvent', () {
    test('crash and error types', () {
      expect(isErrorEvent('crash', {}), isTrue);
      expect(isErrorEvent('error', {'level': 'error'}), isTrue);
    });

    test('network OK — level success + 200', () {
      expect(
        isErrorEvent('network', {
          'level': 'success',
          'network': {'method': 'GET', 'url': '/api', 'statusCode': 200},
        }),
        isFalse,
      );
    });

    test('network NET — 2xx without explicit level', () {
      expect(
        isErrorEvent('network', {
          'network': {'method': 'GET', 'url': '/api', 'statusCode': 200},
        }),
        isFalse,
      );
    });

    test('network failure — 5xx', () {
      expect(
        isErrorEvent('network', {
          'network': {'statusCode': 503},
        }),
        isTrue,
      );
    });

    test('network failure — transport error', () {
      expect(
        isErrorEvent('network', {
          'network': {'error': 'SocketException', 'statusCode': null},
        }),
        isTrue,
      );
    });

    test('network info level is not an error', () {
      expect(isErrorEvent('network', {'level': 'info', 'network': {}}), isFalse);
    });

    test('non-operational fault (401) is excluded even with 4xx status', () {
      expect(
        isErrorEvent('network', {
          'network': {
            'statusCode': 401,
            'readable': {'operationalError': false},
          },
        }),
        isFalse,
      );
    });

    test('operational fault (500) still counts as error', () {
      expect(
        isErrorEvent('network', {
          'network': {
            'statusCode': 500,
            'readable': {'operationalError': true},
          },
        }),
        isTrue,
      );
    });
  });

  group('isSuccessEvent', () {
    test('explicit OK level', () {
      expect(isSuccessEvent('log', {'level': 'success'}), isTrue);
    });

    test('network 200', () {
      expect(
        isSuccessEvent('network', {
          'level': 'success',
          'network': {'statusCode': 200},
        }),
        isTrue,
      );
    });

    test('network 404 is not success', () {
      expect(
        isSuccessEvent('network', {'network': {'statusCode': 404}}),
        isFalse,
      );
    });

    test('error and success are mutually exclusive for typical network OK', () {
      final payload = {
        'level': 'success',
        'network': {'statusCode': 200, 'url': '/health'},
      };
      expect(isErrorEvent('network', payload), isFalse);
      expect(isSuccessEvent('network', payload), isTrue);
    });
  });
}
