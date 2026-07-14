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

  group('facet filters', () {
    test('hasEventFacetFilters detects active facets', () {
      expect(hasEventFacetFilters(), isFalse);
      expect(hasEventFacetFilters(appVersion: '1.0.0'), isTrue);
      expect(hasEventFacetFilters(environment: 'production'), isTrue);
      expect(hasEventFacetFilters(deviceName: 'iPhone'), isTrue);
    });

    test('sqlEventFacetFilters can omit one dimension for cross-faceting', () {
      expect(sqlEventFacetFilters(applyAppVersion: false), isNot(contains('@ver::text')));
      expect(sqlEventFacetFilters(applyEnvironment: false), isNot(contains('@env::text')));
      expect(sqlEventFacetFilters(), contains('@ver::text'));
    });

    test('sqlIssueEventScope requires error events', () {
      expect(sqlIssueEventScope(), contains('is_error'));
      expect(sqlIssueEventScope(), contains('@ver::text'));
    });

    test('eventFacetParameters omits unused facet binds', () {
      final time = {'since': null, 'until': null};
      expect(
        eventFacetParameters(projectId: 'p', time: time, applyEnvironment: false).keys,
        isNot(contains('env')),
      );
      expect(
        eventFacetParameters(projectId: 'p', time: time, applyAppVersion: false).keys,
        isNot(contains('ver')),
      );
      expect(
        eventFacetParameters(projectId: 'p', time: time, applyDevice: false).keys,
        isNot(contains('device')),
      );
    });

    test('composed listEvents SQL has no double AND', () {
      final sql = '''
        FROM events WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          AND (@country::text IS NULL OR country = @country::text)
          ${sqlEventFacetFilters()}
          AND (@since::timestamptz IS NULL OR occurred_at >= @since::timestamptz)
      ''';
      expect(sql, isNot(matches(RegExp(r'AND\s+AND', caseSensitive: false))));
    });

    test('composed issue scope SQL has no double AND', () {
      final sql = 'SELECT 1 FROM events e WHERE ${sqlIssueEventScope()}';
      expect(sql, isNot(matches(RegExp(r'AND\s+AND', caseSensitive: false))));
    });

    test('composed facet env query SQL has no double AND', () {
      final sql = '''
        FROM events WHERE project_id = @pid
          AND $sqlHideSessionHeartbeat
          ${sqlEventFacetFilters(applyEnvironment: false)}
      ''';
      expect(sql, isNot(matches(RegExp(r'AND\s+AND', caseSensitive: false))));
    });

    test('composeAppVersion joins separate build number', () {
      expect(composeAppVersion(appVersion: '1.0.2', buildNumber: '46'), '1.0.2+46');
      expect(composeAppVersion(appVersion: '1.0.2+46', buildNumber: '99'), '1.0.2+46');
      expect(composeAppVersion(appVersion: '1.0.2'), '1.0.2');
    });
  });
}
