import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  test('legacy config without preset still loads', () {
    final cfg = ProjectNotificationConfig.fromJson({
      'enabled': true,
      'dedupMinutes': 20,
      'rules': [
        {
          'id': 'default',
          'enabled': true,
          'categories': ['crash'],
          'channels': ['slack'],
          'environments': ['production'],
        }
      ],
      'channels': {
        'slack': {'enabled': true, 'webhookUrlEnc': 'x'},
      },
    });
    expect(cfg.enabled, isTrue);
    expect(cfg.preset, kDefaultNotificationPreset);
    expect(cfg.healthCheckNotify, isTrue);
    expect(cfg.dedupMinutes, 20);
  });

  test('quiet preset maps categories and noise controls', () {
    const base = ProjectNotificationConfig(
      enabled: true,
      slack: SlackChannelConfig(enabled: true, webhookUrlEnc: 'enc'),
    );
    final quiet = applyNotificationPreset(base, 'quiet');
    expect(quiet.preset, 'quiet');
    expect(quiet.healthCheckNotify, isTrue);
    expect(quiet.dedupMinutes, 30);
    expect(quiet.groupMinutes, 10);
    expect(quiet.threshold.enabled, isFalse);
    expect(quiet.rules.single.categories, kQuietNotificationCategories);
    expect(quiet.slack.webhookUrlEnc, 'enc');
  });

  test('urgent preset enables spikes and short dedup', () {
    const base = ProjectNotificationConfig(enabled: true);
    final urgent = applyNotificationPreset(base, 'urgent');
    expect(urgent.preset, 'urgent');
    expect(urgent.dedupMinutes, 5);
    expect(urgent.groupMinutes, 0);
    expect(urgent.threshold.enabled, isTrue);
    expect(urgent.threshold.errorCount, 20);
    expect(urgent.threshold.crashCount, 3);
    expect(urgent.rules.single.categories, kUrgentNotificationCategories);
  });

  test('normal preset restores defaults with moderate spikes', () {
    final noisy = applyNotificationPreset(const ProjectNotificationConfig(), 'quiet');
    final normal = applyNotificationPreset(noisy, 'normal');
    expect(normal.preset, 'normal');
    expect(normal.dedupMinutes, kDefaultDedupMinutes);
    expect(normal.groupMinutes, kDefaultGroupMinutes);
    expect(normal.threshold.enabled, isTrue);
    expect(normal.threshold.errorCount, 50);
    expect(normal.threshold.crashCount, 5);
    expect(normal.rules.single.categories, kDefaultNotificationCategories);
  });

  test('preset blurbs are non-empty', () {
    for (final p in ['quiet', 'normal', 'urgent', 'custom']) {
      expect(notificationPresetBlurb(p), isNotEmpty);
    }
  });

  test('round-trip includes preset and healthCheckNotify', () {
    final cfg = applyNotificationPreset(const ProjectNotificationConfig(enabled: true), 'urgent');
    final again = ProjectNotificationConfig.fromJson(cfg.toJson());
    expect(again.preset, 'urgent');
    expect(again.healthCheckNotify, isTrue);
    expect(again.toClientJson(platform: const PlatformNotificationPolicy())['preset'], 'urgent');
  });
}
