import 'package:scout_models/scout_models.dart';
import 'package:scout_server/notifications/notification_categories.dart';
import 'package:scout_server/notifications/notification_group.dart';
import 'package:scout_server/notifications/notification_router.dart';
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
  });
}
