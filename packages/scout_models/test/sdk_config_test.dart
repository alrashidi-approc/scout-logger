import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  test('normalizeEnabledLevels keeps known order', () {
    expect(normalizeEnabledLevels(['success', 'error']), ['error', 'success']);
    expect(normalizeEnabledLevels(['bogus']), ProjectSdkConfig.defaultEnabledLevels);
  });

  test('normalizeStatusCodes filters valid HTTP codes', () {
    expect(normalizeStatusCodes([401, '404', 99, 600, 'bad']), [401, 404]);
    expect(normalizeStatusCodes([]), isEmpty);
  });

  test('ProjectSdkConfig mergePatch updates sdk fields', () {
    const base = ProjectSdkConfig(enabledLevels: ['error', 'info']);
    final merged = base.mergePatch({
      'sdk': {'enabledLevels': ['error', 'warning'], 'trackNavigation': false},
    });
    expect(merged.enabledLevels, ['error', 'warning']);
    expect(merged.trackNavigation, false);
    expect(merged.enableFlutterHooks, isNull);
  });

  test('ProjectRemoteConfig round trip', () {
    final settings = ProjectRemoteConfig(
      configVersion: 2,
      updatedAt: '2026-06-21T00:00:00Z',
      sdk: const ProjectSdkConfig(enabledLevels: ['error'], networkCaptureBodies: false),
    ).toSettingsJson();
    final parsed = ProjectRemoteConfig.fromSettings(settings);
    expect(parsed.configVersion, 2);
    expect(parsed.sdk.resolved().enabledLevels, ['error']);
    expect(parsed.sdk.resolved().networkCaptureBodies, false);
  });
}
