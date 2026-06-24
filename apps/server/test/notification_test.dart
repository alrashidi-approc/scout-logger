import 'package:scout_models/scout_models.dart';
import 'package:scout_server/notifications/notification_categories.dart';
import 'package:scout_server/notifications/notification_router.dart';
import 'package:test/test.dart';

void main() {
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
  });
}
