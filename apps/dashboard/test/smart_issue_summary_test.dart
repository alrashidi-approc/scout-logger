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
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch-auth-retry',
      breadcrumbs: [
        _crumb('GET app-version 200'),
        _crumb('device bootstrap'),
        _crumb('device guard registration_failed'),
      ],
    )));

    expect(md, contains('**Failed at:** device_guard'));
    expect(md, contains('Keystore'));
    expect(md, contains('not Firebase Auth'));
    expect(md, contains('registration_failed'));
    expect(md, isNot(contains('### Flow')));
  });

  test('2. App Check only → app_check', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'Firebase App Check token unavailable',
      operation: 'device_bootstrap_launch',
      breadcrumbs: [
        _crumb('device bootstrap'),
        _crumb('Firebase App Check token unavailable'),
      ],
    )));

    expect(md, contains('**Failed at:** app_check'));
    expect(md, contains('App Check'));
    expect(md, isNot(contains('**Failed at:** device_guard')));
  });

  test('3. Mixed → first blocking primary; other in Why', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch-auth-retry',
      breadcrumbs: [
        _crumb('device guard registration_failed', at: '2026-07-29T08:00:01Z'),
        _crumb('App Check token unavailable', at: '2026-07-29T08:00:05Z'),
      ],
    )));

    expect(md, contains('**Failed at:** device_guard'));
    expect(md, contains('App Check also failed'));
  });

  test('4. Retry storm noted in Why/Meta', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch-auth-retry',
      context: {'attempt': 'retry', 'outcome': 'failed_final'},
      breadcrumbs: [
        _crumb('registration_failed', at: '2026-07-29T08:00:01Z'),
        _crumb('registration_failed', at: '2026-07-29T08:00:05Z'),
        _crumb('registration_failed', at: '2026-07-29T08:00:10Z'),
      ],
    )));

    expect(md.toLowerCase(), contains('retry'));
  });

  test('5. app-version 200 → noted as not Kong', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch',
      breadcrumbs: [
        _crumb('GET /app-version → 200 success'),
        _crumb('device guard registration_failed'),
      ],
    )));

    expect(md, contains('app-version OK'));
  });

  test('6. Missing breadcrumbs → still renders brief', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'Something broke',
      breadcrumbs: null,
    )));

    expect(md, contains('## Smart summary'));
    expect(md, contains('**Where:**'));
    expect(md, contains('**Why:**'));
    expect(md, contains('**Meta:**'));
    expect(md, isNot(contains('| App |')));
  });

  test('prefers diagnosis prose over heuristics', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      diagnosis: {
        'summary': 'App Check token fetch failed',
        'likelyCause': 'Debug token not registered',
        'stage': 'app_check',
        'nextSteps': ['Register debug token', 'Disable debug App Check'],
      },
      breadcrumbs: [_crumb('device guard registration_failed')],
    )));

    expect(md, contains('App Check token fetch failed'));
    expect(md, contains('Debug token not registered'));
    expect(md, contains('Register debug token'));
  });

  test('prefers structured failure_layer', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      context: {'failure_layer': 'app_check'},
      breadcrumbs: [_crumb('device guard registration_failed')],
    )));

    expect(md, contains('**Failed at:** app_check'));
  });

  test('issue aggregation includes event count', () {
    final md = SmartIssueSummary.fromIssue(
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
    expect(md, contains('events=`42`'));
    expect(md, contains('retry-storm'));
  });

  test('empty issue events still renders', () {
    final md = SmartIssueSummary.fromIssue({'title': 'empty', 'eventCount': 0}, const []);
    expect(md, contains('## Smart summary'));
    expect(md, contains('**Why:**'));
  });
}
