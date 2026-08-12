import 'package:flutter_test/flutter_test.dart';
import 'package:scout_dashboard/utils/event_view.dart';
import 'package:scout_dashboard/utils/smart_issue_summary.dart';

Map<String, dynamic> _event({
  required String message,
  String? operation,
  Map<String, dynamic>? context,
  Map<String, dynamic>? diagnosis,
  List<Map<String, dynamic>>? breadcrumbs,
  String route = '/splash',
  String release = 'com.approc.egypt.consulate.dev@1.0.2+60',
}) {
  return {
    'id': 'evt_1',
    'type': 'error',
    'occurredAt': '2026-07-29T08:00:00Z',
    'environment': 'development',
    'payload': {
      'message': message,
      'environment': 'development',
      'release': {
        'name': release,
        'bundleId': 'com.approc.egypt.consulate.dev',
        'version': '1.0.2',
        'buildNumber': '60',
      },
      'packageName': 'com.approc.egypt.consulate.dev',
      'screen': {'currentRoute': route},
      'device': {
        'platform': 'Android',
        'osVersion': '14',
        'manufacturer': 'Samsung',
        'model': 'SM-A525F',
      },
      'context': {
        if (operation != null) 'operation': operation,
        ...?context,
      },
      if (diagnosis != null) 'diagnosis': diagnosis,
      if (breadcrumbs != null) 'breadcrumbs': breadcrumbs,
    },
  };
}

Map<String, dynamic> _crumb(String message, {String? at}) => {
      'message': message,
      'label': message,
      if (at != null) 'timestamp': at,
    };

void main() {
  test('1. registration_failed → device_guard, Keystore not Firebase Auth', () {
    final s = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch-auth-retry',
      breadcrumbs: [
        _crumb('GET app-version 200'),
        _crumb('device bootstrap'),
        _crumb('device guard registration_failed'),
      ],
    )));

    expect(s.failedAt, contains('Device Guard'));
    expect(s.failedAt, contains('Registration Failed'));
    expect(s.why, contains('Keystore'));
    expect(s.why, contains('not Firebase Auth'));
    expect(s.markdown, contains('**Failed at:** Device Guard'));
    expect(s.markdown, isNot(contains('### Flow')));
  });

  test('2. App Check only → app_check', () {
    final s = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'Firebase App Check token unavailable',
      operation: 'device_bootstrap_launch',
      breadcrumbs: [
        _crumb('device bootstrap'),
        _crumb('Firebase App Check token unavailable'),
      ],
    )));

    expect(s.failedAt, contains('App Check'));
    expect(s.why, contains('App Check'));
    expect(s.failedAt, isNot(contains('Device Guard')));
  });

  test('3. Mixed → first blocking primary; other in Why', () {
    final s = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch-auth-retry',
      breadcrumbs: [
        _crumb('device guard registration_failed', at: '2026-07-29T08:00:01Z'),
        _crumb('App Check token unavailable', at: '2026-07-29T08:00:05Z'),
      ],
    )));

    expect(s.failedAt, contains('Device Guard'));
    expect(s.why, contains('App Check also failed'));
  });

  test('4. Retry storm noted in Why/Meta', () {
    final s = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch-auth-retry',
      context: {'attempt': 'retry', 'outcome': 'failed_final'},
      breadcrumbs: [
        _crumb('registration_failed', at: '2026-07-29T08:00:01Z'),
        _crumb('registration_failed', at: '2026-07-29T08:00:05Z'),
        _crumb('registration_failed', at: '2026-07-29T08:00:10Z'),
      ],
    )));

    expect(s.markdown.toLowerCase(), contains('retry'));
    expect(s.meta, contains('Retry storm'));
  });

  test('5. app-version 200 → noted as not Kong', () {
    final s = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch',
      breadcrumbs: [
        _crumb('GET /app-version → 200 success'),
        _crumb('device guard registration_failed'),
      ],
    )));

    expect(s.why, contains('App version OK'));
  });

  test('6. Missing breadcrumbs → still renders brief', () {
    final s = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'Something broke',
      breadcrumbs: null,
    )));

    expect(s.markdown, contains('## Smart summary'));
    expect(s.where, isNotEmpty);
    expect(s.why, isNotEmpty);
    expect(s.meta, isNotEmpty);
    expect(s.markdown, isNot(contains('| App |')));
  });

  test('prefers diagnosis prose over heuristics', () {
    final s = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      diagnosis: {
        'summary': 'App Check token fetch failed',
        'likelyCause': 'Debug token not registered',
        'stage': 'app_check',
        'nextSteps': ['Register debug token', 'Disable debug App Check'],
      },
      breadcrumbs: [_crumb('device guard registration_failed')],
    )));

    expect(s.why, contains('App Check token fetch failed'));
    expect(s.why, contains('Debug token not registered'));
    expect(s.next, contains('Register debug token'));
  });

  test('prefers structured failure_layer', () {
    final s = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      context: {'failure_layer': 'app_check'},
      breadcrumbs: [_crumb('device guard registration_failed')],
    )));

    expect(s.failedAt, contains('App Check'));
  });

  test('issue aggregation includes event count', () {
    final s = SmartIssueSummary.fromIssue(
      {
        'title': 'registration_failed',
        'eventCount': 42,
        'firstSeenAt': '2026-07-01T00:00:00Z',
        'lastSeenAt': '2026-07-29T00:00:00Z',
      },
      [
        _event(
          message: 'PlatformException(registration_failed, null, null, null)',
          operation: 'device_bootstrap_launch-auth-retry',
          breadcrumbs: [
            _crumb('registration_failed'),
            _crumb('registration_failed'),
            _crumb('registration_failed'),
          ],
        ),
      ],
    );
    expect(s.meta.join(' '), contains('events=`42`'));
    expect(s.meta, contains('Retry storm'));
  });

  test('empty issue events still renders', () {
    final s = SmartIssueSummary.fromIssue({'title': 'empty', 'eventCount': 0}, const []);
    expect(s.markdown, contains('## Smart summary'));
    expect(s.why, isNotEmpty);
  });

  test('network tenant_missing explains client header failure', () {
    final s = SmartIssueSummary.fromEvent(EventView({
      'id': 'evt_net',
      'type': 'network',
      'environment': 'staging',
      'payload': {
        'message': 'GET /khadamat-service/api/v1/mobile/faqs?page=1&page_size=10 — no response (unknown)',
        'level': 'error',
        'category': 'network',
        'environment': 'staging',
        'screen': {'currentRoute': '/faqs'},
        'device': {'platform': 'ios', 'osVersion': '26.5.2', 'manufacturer': 'Apple', 'model': 'iPhone'},
        'release': {
          'name': 'com.example.egyptconsulate.dev@1.0.2+85',
          'bundleId': 'com.example.egyptconsulate.dev',
          'version': '1.0.2',
          'buildNumber': '85',
        },
        'packageName': 'com.example.egyptconsulate.dev',
        'network': {
          'url': 'https://mofa-api-gateway-srvice.fedis.app/khadamat-service/api/v1/mobile/faqs?page=1&page_size=10',
          'method': 'GET',
          'error': '[client:tenant_missing] x-tenant-id is not set',
          'errorType': 'unknown',
          'durationMs': 395,
          'hasResponse': false,
          'readable': {
            'title': 'GET /khadamat-service/api/v1/mobile/faqs?page=1&page_size=10 — no response (unknown)',
            'outcome': 'no_response',
            'outcomeLabel': 'No response',
            'actionHint': 'No usable HTTP response — check connectivity, TLS, timeouts, or client config.',
            'request': {
              'method': 'GET',
              'path': '/khadamat-service/api/v1/mobile/faqs?page=1&page_size=10',
              'summary': 'GET /faqs',
            },
            'fault': {
              'kind': 'transport',
              'label': 'Transport failure',
              'actionHint': 'No usable HTTP response — check connectivity, TLS, timeouts, or client config.',
              'faultClass': 'critical',
              'alertWorthy': true,
              'issueWorthy': true,
              'operationalError': true,
            },
          },
        },
      },
    }));

    expect(s.where, contains('/faqs'));
    expect(s.where, contains('GET'));
    expect(s.failedAt, contains('Network'));
    expect(s.failedAt, contains('Tenant Missing'));
    expect(s.why, contains('tenant_missing'));
    expect(s.why, contains('x-tenant-id'));
    expect(s.why.toLowerCase(), isNot(contains('failed at: unknown')));
    expect(s.next.join(' '), contains('x-tenant-id'));
    expect(s.next.join(' '), isNot(contains('Confirm first hard failure')));
  });
}
