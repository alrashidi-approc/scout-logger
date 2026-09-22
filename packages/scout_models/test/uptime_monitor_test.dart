import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  test('uptimeShouldAlert only on transition to down', () {
    expect(uptimeShouldAlert(previousStatus: null, newStatus: 'down'), isTrue);
    expect(uptimeShouldAlert(previousStatus: 'ok', newStatus: 'down'), isTrue);
    expect(uptimeShouldAlert(previousStatus: 'down', newStatus: 'down'), isFalse);
    expect(uptimeShouldAlert(previousStatus: 'down', newStatus: 'ok'), isFalse);
    expect(uptimeShouldAlert(previousStatus: null, newStatus: 'ok'), isFalse);
  });

  test('legacy single url still loads', () {
    final cfg = UptimeMonitorConfig.fromJson({
      'enabled': true,
      'url': 'https://api.example.com/health',
      'lastStatus': 'ok',
    });
    expect(cfg.enabled, isTrue);
    expect(cfg.hasUrl, isTrue);
    expect(cfg.targets, hasLength(1));
    expect(cfg.url, 'https://api.example.com/health');
    expect(cfg.targets.first.lastStatus, 'ok');
  });

  test('multiple urls from text', () {
    final cfg = UptimeMonitorConfig.fromUrlsText(
      enabled: true,
      text: 'https://a.example.com/health\nhttps://b.example.com/ok\nnot-a-url',
    );
    expect(cfg.validTargets, hasLength(2));
    expect(cfg.urlsText, contains('a.example.com'));
    expect(cfg.toJson()['targets'], hasLength(2));
  });

  test('fromUrlsText keeps prior probe results for same url', () {
    final prev = [
      const UptimeTarget(url: 'https://a.example.com/health', lastStatus: 'ok', lastLatencyMs: 12),
    ];
    final cfg = UptimeMonitorConfig.fromUrlsText(
      enabled: true,
      text: 'https://a.example.com/health\nhttps://b.example.com/health',
      previous: prev,
    );
    expect(cfg.targets.first.lastStatus, 'ok');
    expect(cfg.targets.first.lastLatencyMs, 12);
    expect(cfg.targets[1].lastStatus, isNull);
  });

  test('round-trip multi target json', () {
    final cfg = UptimeMonitorConfig(
      enabled: true,
      targets: const [
        UptimeTarget(url: 'https://a.example.com/health', lastStatus: 'ok'),
        UptimeTarget(url: 'https://b.example.com/health', lastStatus: 'down'),
      ],
    );
    final again = UptimeMonitorConfig.fromJson(cfg.toJson());
    expect(again.targets, hasLength(2));
    expect(again.targets[1].lastStatus, 'down');
  });
}
