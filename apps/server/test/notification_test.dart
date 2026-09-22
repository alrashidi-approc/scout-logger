import 'package:scout_models/scout_models.dart';
import 'package:scout_server/notifications/notification_categories.dart';
import 'package:scout_server/notifications/notification_group.dart';
import 'package:scout_server/notifications/notification_router.dart';
import 'package:scout_server/notifications/notification_service.dart';
import 'package:scout_server/notifications/notification_share.dart';
import 'package:test/test.dart';

void main() {
  test('share notify titles use manual green prefix and severity emojis', () {
    expect(
      shareNotifyTitle(type: 'error', environment: 'production', summary: 'Null check'),
      '🟢 🛑🛑 [production] Null check',
    );
    expect(
      shareNotifyTitle(type: 'crash', environment: 'staging', summary: 'Fatal'),
      '🟢 🛑🟡 [staging] Fatal',
    );
    expect(
      shareNotifyTitle(type: 'network', environment: 'production', summary: 'API down'),
      '🟢 [production] API down',
    );
  });

  test('grouped notification job merges similar alerts', () {
    final jobs = [
      NotificationJob(
        channel: 'slack',
        category: 'network_transport',
        dedupKey: 'fp1',
        title: '[production] DNS failed',
        body: 'Project: App\nType: network',
        eventUrl: 'http://x/share/1',
        environment: 'production',
        issueId: 'i1',
      ),
      NotificationJob(
        channel: 'slack',
        category: 'error',
        dedupKey: 'fp1',
        title: '[production] DNS failed again',
        body: 'Project: App\nType: network',
        eventUrl: 'http://x/share/2',
        environment: 'production',
        issueId: 'i1',
      ),
    ];
    final grouped = groupedNotificationJob(jobs: jobs, groupMinutes: 5);
    expect(grouped.title, startsWith('📦'));
    expect(grouped.body, contains('2 similar alerts'));
    expect(grouped.category, 'grouped');
  });

  test('crash maps to crash category', () {
    expect(notificationCategoriesFor(type: 'crash', payload: {}), {'crash'});
  });

  test('network 500 maps to network_critical', () {
    final cats = notificationCategoriesFor(
      type: 'network',
      payload: {
        'network': {
          'statusCode': 500,
          'readable': networkReadableFrom({'method': 'GET', 'url': '/api', 'statusCode': 500}),
        },
      },
    );
    expect(cats, contains('network_critical'));
  });

  test('default routing matches production crash', () {
    const config = ProjectNotificationConfig(
      enabled: true,
      slack: SlackChannelConfig(enabled: true, webhookUrlEnc: 'enc'),
    );
    final jobs = routeNotifications(
      config: config,
      platform: const PlatformNotificationPolicy(),
      projectId: 'p1',
      projectName: 'Demo',
      eventId: 'e1',
      type: 'crash',
      environment: 'production',
      message: 'Null check',
      payload: {},
      fingerprint: 'fp1',
      dashboardBaseUrl: 'http://localhost/scout/dashboard',
    );
    expect(jobs, isNotEmpty);
    expect(jobs.first.channel, 'slack');
    expect(jobs.first.title, startsWith('[production]'));
    expect(jobs.first.environment, 'production');
    expect(jobs.first.urgency, 'emergency');
  });

  test('quiet preset skips non-alertWorthy network faults', () {
    final config = applyNotificationPreset(
      const ProjectNotificationConfig(
        enabled: true,
        slack: SlackChannelConfig(enabled: true, webhookUrlEnc: 'enc'),
      ),
      'quiet',
    );
    final jobs = routeNotifications(
      config: config,
      platform: const PlatformNotificationPolicy(),
      projectId: 'p1',
      projectName: 'Demo',
      eventId: 'e1',
      type: 'network',
      environment: 'production',
      message: 'Bad request',
      payload: {
        'network': {
          'statusCode': 400,
          'readable': networkReadableFrom({'method': 'POST', 'url': '/api', 'statusCode': 400}),
        },
      },
      fingerprint: 'fp1',
      dashboardBaseUrl: 'http://localhost/scout/dashboard',
    );
    expect(jobs, isEmpty);
  });

  test('urgent preset still routes alertWorthy network_critical', () {
    final config = applyNotificationPreset(
      const ProjectNotificationConfig(
        enabled: true,
        slack: SlackChannelConfig(enabled: true, webhookUrlEnc: 'enc'),
      ),
      'urgent',
    );
    final jobs = routeNotifications(
      config: config,
      platform: const PlatformNotificationPolicy(),
      projectId: 'p1',
      projectName: 'Demo',
      eventId: 'e1',
      type: 'network',
      environment: 'production',
      message: 'Server error',
      payload: {
        'network': {
          'statusCode': 500,
          'readable': networkReadableFrom({'method': 'GET', 'url': '/api', 'statusCode': 500}),
        },
      },
      fingerprint: 'fp1',
      dashboardBaseUrl: 'http://localhost/scout/dashboard',
    );
    expect(jobs, isNotEmpty);
    expect(jobs.first.urgency, 'normal');
  });

  test('network timeout alert is short and drops query secrets', () {
    const config = ProjectNotificationConfig(
      enabled: true,
      slack: SlackChannelConfig(enabled: true, webhookUrlEnc: 'enc'),
    );
    final url =
        'https://mobileserver.epa.gov.kw/EPAMobileAppServices/resources/etransflows?requestNo=10137440&securUser=secret&securPass=secret&loginUser=1838';
    final network = {
      'method': 'GET',
      'url': url,
      'errorType': 'receiveTimeout',
      'durationMs': 30000,
      'readable': networkReadableFrom({
        'method': 'GET',
        'url': url,
        'errorType': 'receiveTimeout',
        'durationMs': 30000,
      }),
    };
    final jobs = routeNotifications(
      config: config,
      platform: const PlatformNotificationPolicy(),
      projectId: 'p1',
      projectName: 'EPA kuwait',
      eventId: 'e1',
      type: 'network',
      environment: 'production',
      message: 'GET $url — no response (receiveTimeout) — slow',
      payload: {'network': network, 'release': '5.0.24'},
      fingerprint: 'fp1',
      dashboardBaseUrl: 'http://localhost/scout/dashboard',
    );
    expect(jobs, isNotEmpty);
    final job = jobs.first;
    expect(job.title, contains('[production]'));
    expect(job.title, contains('Timeout'));
    expect(job.title, contains('GET /EPAMobileAppServices/resources/etransflows'));
    expect(job.title, isNot(contains('securPass')));
    expect(job.title, isNot(contains('requestNo')));
    expect(job.body, contains('EPA kuwait · production · v5.0.24'));
    expect(job.body, contains('Host: mobileserver.epa.gov.kw'));
    expect(job.body, contains('Request: GET /EPAMobileAppServices/resources/etransflows'));
    expect(job.body, isNot(contains('Message:')));
    expect(job.body, isNot(contains('securPass')));
  });

  test('alertPathFromUrl strips query string', () {
    expect(
      alertPathFromUrl('https://api.example.com/v1/items?token=abc'),
      '/v1/items',
    );
  });

  test('network alertDedupKey ignores release and query', () {
    final a = alertDedupKey(
      type: 'network',
      issueId: null,
      fingerprint: 'fp-a',
      eventId: 'e1',
      payload: {
        'network': {
          'method': 'POST',
          'url': 'https://h/EPAMobileAppServices/resources/empCardImageM?x=1',
          'statusCode': 404,
        },
      },
    );
    final b = alertDedupKey(
      type: 'network',
      issueId: null,
      fingerprint: 'fp-b',
      eventId: 'e2',
      payload: {
        'network': {
          'method': 'POST',
          'url': 'https://h/EPAMobileAppServices/resources/empCardImageM',
          'statusCode': 404,
        },
        'release': '4.6.8',
      },
    );
    expect(a, b);
    expect(a, startsWith('net|POST|'));
  });

  test('staging and debug environments never route automatic alerts', () {
    const config = ProjectNotificationConfig(
      enabled: true,
      rules: [
        NotificationRule(id: 'staging', environments: ['staging', 'development', '*']),
      ],
      slack: SlackChannelConfig(enabled: true, webhookUrlEnc: 'enc'),
    );
    for (final env in ['staging', 'development', 'debug', 'profile']) {
      final jobs = routeNotifications(
        config: config,
        platform: const PlatformNotificationPolicy(),
        projectId: 'p1',
        projectName: 'Demo',
        eventId: 'e1',
        type: 'crash',
        environment: env,
        message: 'Null check',
        payload: {},
        fingerprint: 'fp1',
        dashboardBaseUrl: 'http://localhost/scout/dashboard',
      );
      expect(jobs, isEmpty, reason: 'env=$env');
    }
  });

  test('release and prod labels are treated as release mode', () {
    expect(isReleaseNotificationEnvironment('production'), isTrue);
    expect(isReleaseNotificationEnvironment('PROD'), isTrue);
    expect(isReleaseNotificationEnvironment('release'), isTrue);
    expect(isReleaseNotificationEnvironment('staging'), isFalse);
  });

  test('health check alert gate', () {
    expect(healthCheckNeedsAlert(status: 'timeout', report: null), isTrue);
    expect(healthCheckNeedsAlert(status: 'failed', report: null), isTrue);
    expect(healthCheckNeedsAlert(status: 'success', report: {'verdict': 'healthy'}), isFalse);
    expect(healthCheckNeedsAlert(status: 'success', report: {'verdict': 'unhealthy'}), isTrue);
    expect(healthCheckNeedsAlert(status: 'success', report: {'verdict': 'degraded'}), isFalse);
  });
}
