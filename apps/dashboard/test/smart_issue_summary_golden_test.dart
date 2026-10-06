import 'package:flutter_test/flutter_test.dart';
import 'package:scout_dashboard/utils/event_view.dart';
import 'package:scout_dashboard/utils/smart_issue_summary.dart';

EventView _view({
  String message = '',
  Map<String, dynamic>? context,
  Map<String, dynamic>? diagnosis,
  Map<String, dynamic>? network,
  List<String> crumbs = const [],
}) =>
    EventView({
      'id': 'evt_golden',
      'type': 'error',
      'environment': 'production',
      'payload': {
        'message': message,
        'environment': 'production',
        'release': {'name': 'com.acme.app@2.1.0+7', 'bundleId': 'com.acme.app', 'version': '2.1.0'},
        'packageName': 'com.acme.app',
        'screen': {'currentRoute': '/splash'},
        'device': {'platform': 'Android', 'osVersion': '14', 'manufacturer': 'Google', 'model': 'Pixel 8'},
        'context': {...?context},
        if (diagnosis != null) 'diagnosis': diagnosis,
        if (network != null) 'network': network,
        'breadcrumbs': [for (final c in crumbs) {'message': c}],
      },
    });

final _fixtures = <String, EventView>{
  'heuristic device_guard storm': _view(
    message: 'PlatformException(registration_failed, null)',
    context: {'operation': 'device_bootstrap_launch', 'attempt': 'retry', 'outcome': 'failed_final', 'identity_state': 'missing'},
    crumbs: ['GET app-version 200', 'device guard registration_failed', 'App Check token unavailable'],
  ),
  'heuristic app_check with provider': _view(
    message: 'Firebase App Check token unavailable',
    context: {'entrypoint': 'resume', 'app_check_provider': 'play_integrity', 'kDebugMode': 'false', 'step': 'attest'},
  ),
  'heuristic plain message': _view(message: 'Something unexpected broke in checkout flow'),
  'diagnosis with next steps': _view(
    message: 'PlatformException(registration_failed, null)',
    diagnosis: {
      'summary': 'Keystore enrollment failed',
      'likelyCause': 'StrongBox unavailable',
      'stage': 'device_guard_enroll',
      'operation': 'device_bootstrap_cold-start',
      'nextSteps': ['Retry without StrongBox', 'Check OEM keystore', 'Third step dropped'],
    },
    crumbs: ['device guard registration_failed', 'Firebase App Check attestation failed'],
  ),
  'diagnosis fallback next + network call': _view(
    message: 'bootstrap failed',
    context: {'failure_layer': 'bootstrap_api', 'platform_code': 'HTTP_503'},
    diagnosis: {'summary': 'Bootstrap returned 503'},
    network: {'url': 'https://api.acme.com/bootstrap/init?x=1', 'method': 'POST', 'statusCode': 503},
  ),
};

const _golden = {
  'heuristic device_guard storm': '''
## Smart summary

**Where:** /splash · Device Bootstrap Launch
**Failed at:** Device Guard · Registration Failed
**Why:** Device Guard Keystore/identity enrollment failed (Registration Failed) — not Firebase Auth. App version OK (200) — not Kong; App Check also failed in same loop; retry storm — downgrade mid-retry from crashing.
**Next:** Check Device Guard identity (Identity State: Missing) · Keep crashing for Failed Final only; mid-retry → error/warning
**Meta:** com.acme.app@2.1.0+7 · Android 14 · Google Pixel 8 · Production / com.acme.app@2.1.0+7 · Retry storm''',
  'heuristic app_check with provider': '''
## Smart summary

**Where:** /splash · Resume
**Failed at:** App Check · Attest
**Why:** App Check token unavailable (App Check Provider: Play Integrity); on *.dev release builds often Play Integrity, not Firebase down.
**Next:** Confirm App Check provider (App Check Provider: Play Integrity; K Debug Mode is disabled)
**Meta:** com.acme.app@2.1.0+7 · Android 14 · Google Pixel 8 · Production / com.acme.app@2.1.0+7''',
  'heuristic plain message': '''
## Smart summary

**Where:** /splash
**Failed at:** Unknown
**Why:** Something unexpected broke in checkout flow
**Next:** Confirm first hard failure in Timeline
**Meta:** com.acme.app@2.1.0+7 · Android 14 · Google Pixel 8 · Production / com.acme.app@2.1.0+7''',
  'diagnosis with next steps': '''
## Smart summary

**Where:** /splash · Device Bootstrap Cold Start
**Failed at:** Device Guard · Device Guard Enroll · Registration Failed
**Why:** Keystore enrollment failed StrongBox unavailable App Check also failed in same loop
**Next:** Retry without StrongBox · Check OEM keystore
**Meta:** com.acme.app@2.1.0+7 · Android 14 · Google Pixel 8 · Production / com.acme.app@2.1.0+7''',
  'diagnosis fallback next + network call': '''
## Smart summary

**Where:** /splash · POST /bootstrap/init
**Failed at:** Bootstrap API · HTTP 503
**Why:** Bootstrap returned 503
**Next:** Inspect `/bootstrap/*` status + HMAC
**Meta:** com.acme.app@2.1.0+7 · Android 14 · Google Pixel 8 · Production / com.acme.app@2.1.0+7''',
};

void main() {
  for (final MapEntry(:key, :value) in _fixtures.entries) {
    test('brief is stable: $key', () => expect(SmartIssueSummary.fromEvent(value).markdown, _golden[key]));
  }
}
