import 'package:flutter_test/flutter_test.dart';
import 'package:scout_dashboard/utils/event_view.dart';
import 'package:scout_dashboard/utils/smart_issue_summary.dart';

Map<String, dynamic> _event({
  required String message,
  String? operation,
  Map<String, dynamic>? context,
  List<Map<String, dynamic>>? breadcrumbs,
  String route = '/splash',
  String release = 'com.approc.egypt.consulate.dev@1.0.2+60',
  Map<String, dynamic>? device,
}) {
  return {
    'id': 'evt_1',
    'type': 'error',
    'occurredAt': '2026-07-29T08:00:00Z',
    'environment': 'development',
    'payload': {
      'message': message,
      'environment': 'development',
      'release': {'name': release, 'bundleId': 'com.approc.egypt.consulate.dev', 'version': '1.0.2', 'buildNumber': '60'},
      'packageName': 'com.approc.egypt.consulate.dev',
      'screen': {'currentRoute': route},
      'device': device ??
          {
            'platform': 'Android',
            'osVersion': '14',
            'manufacturer': 'Samsung',
            'model': 'SM-A525F',
          },
      'context': {
        if (operation != null) 'operation': operation,
        ...?context,
      },
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
  test('1. registration_failed → primary device_guard, Keystore not Firebase Auth', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch-auth-retry',
      breadcrumbs: [
        _crumb('session start'),
        _crumb('splash pipeline'),
        _crumb('GET app-version 200'),
        _crumb('device bootstrap'),
        _crumb('app check step 1'),
        _crumb('device guard step 2'),
        _crumb('PlatformException(registration_failed, null, null, null)'),
      ],
    )));

    expect(md, contains('DeviceGuard'));
    expect(md, contains('Keystore'));
    expect(md, contains('Not Firebase Auth'));
    expect(md, contains('registration_failed'));
    expect(md, isNot(contains('Firebase is down')));
  });

  test('2. App Check token unavailable only → primary app_check', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'Firebase App Check token unavailable',
      operation: 'device_bootstrap_launch',
      breadcrumbs: [
        _crumb('device bootstrap'),
        _crumb('Firebase App Check token unavailable'),
      ],
    )));

    expect(md, contains('App Check'));
    expect(md, contains('Primary: Firebase App Check'));
    expect(md, isNot(contains('Primary: DeviceGuard')));
    expect(md, contains('**Verdict:**'));
  });

  test('3. Mixed App Check + DeviceGuard → primary first blocking; other contributing', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch-auth-retry',
      breadcrumbs: [
        _crumb('device bootstrap'),
        _crumb('app check ok'),
        _crumb('device guard registration_failed', at: '2026-07-29T08:00:01Z'),
        _crumb('PlatformException(registration_failed)', at: '2026-07-29T08:00:02Z'),
        _crumb('App Check token unavailable', at: '2026-07-29T08:00:05Z'),
      ],
    )));

    expect(md, contains('Primary: DeviceGuard'));
    expect(md, contains('Contributing:'));
    expect(md, contains('App Check'));
  });

  test('4. Repeated identical failures → Amplification / retry storm', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch-auth-retry',
      context: {'attempt': 'retry', 'outcome': 'failed_final'},
      breadcrumbs: [
        _crumb('device bootstrap'),
        _crumb('registration_failed', at: '2026-07-29T08:00:01Z'),
        _crumb('registration_failed', at: '2026-07-29T08:00:05Z'),
        _crumb('registration_failed', at: '2026-07-29T08:00:10Z'),
      ],
    )));

    expect(md, contains('### Amplification'));
    expect(md.toLowerCase(), contains('retry storm'));
  });

  test('5. app-version 200 + bootstrap fail → Not this includes version OK', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      operation: 'device_bootstrap_launch',
      breadcrumbs: [
        _crumb('GET /app-version → 200 success'),
        _crumb('device bootstrap'),
        _crumb('device guard registration_failed'),
      ],
    )));

    expect(md, contains('Not Kong/app-version (200)'));
  });

  test('6. Missing breadcrumbs → Verdict + unknown fields; no crash', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'Something broke',
      breadcrumbs: null,
    )));

    expect(md, contains('## Smart summary'));
    expect(md, contains('**Verdict:**'));
    expect(md, contains('| App |'));
    expect(md, contains('### Flow'));
    expect(md, contains('### Root cause'));
    expect(md, contains('### Suggested next'));
  });

  test('prefers structured context.failure_layer over heuristics', () {
    final md = SmartIssueSummary.fromEvent(EventView(_event(
      message: 'PlatformException(registration_failed, null, null, null)',
      context: {
        'failure_layer': 'app_check',
        'app_check_provider': 'play_integrity',
        'kDebugMode': 'false',
        'flavor': 'dev',
      },
      breadcrumbs: [
        _crumb('device guard registration_failed'),
      ],
    )));

    expect(md, contains('Primary:'));
    expect(md, contains('App Check'));
  });

  test('issue aggregation includes event count and amplification', () {
    final events = [
      _event(
        message: 'PlatformException(registration_failed, null, null, null)',
        operation: 'device_bootstrap_launch-auth-retry',
        breadcrumbs: [
          _crumb('registration_failed'),
          _crumb('registration_failed'),
          _crumb('registration_failed'),
        ],
      ),
    ];
    final md = SmartIssueSummary.fromIssue(
      {
        'title': 'registration_failed',
        'eventCount': 42,
        'firstSeenAt': '2026-07-01T00:00:00Z',
        'lastSeenAt': '2026-07-29T00:00:00Z',
      },
      events,
    );
    expect(md, contains('events=`42`'));
    expect(md, contains('### Amplification'));
  });

  test('empty issue events still renders', () {
    final md = SmartIssueSummary.fromIssue(
      {'title': 'empty', 'eventCount': 0},
      const [],
    );
    expect(md, contains('## Smart summary'));
    expect(md, contains('unknown'));
  });
}
