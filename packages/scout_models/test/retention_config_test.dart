import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  test('ProjectRetentionConfig defaults', () {
    const cfg = ProjectRetentionConfig();
    expect(cfg.enabled, isTrue);
    expect(cfg.routineDays, 30);
    expect(cfg.errorDays, 90);
  });

  test('clampErrorDays allows forever', () {
    expect(clampErrorDays(0), 0);
    expect(clampErrorDays(null), 90);
    expect(clampErrorDays(-1), 90);
  });

  test('ProjectRetentionConfig mergePatch', () {
    const base = ProjectRetentionConfig(routineDays: 30, errorDays: 90);
    final merged = base.mergePatch({'routineDays': 14, 'enabled': false});
    expect(merged.routineDays, 14);
    expect(merged.enabled, isFalse);
    expect(merged.errorDays, 90);
  });

  test('retentionFromSettings reads nested json', () {
    final cfg = retentionFromSettings({
      'retention': {'routineDays': 45, 'errorDays': 0},
    });
    expect(cfg.routineDays, 45);
    expect(cfg.errorDays, 0);
  });
}
