import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  test('normalizeContentTypes strips parameters', () {
    expect(normalizeContentTypes(['text/html; charset=utf-8', 'TEXT/HTML', 'bad']), ['text/html']);
  });

  test('WafRejectConfig defaults and merge', () {
    final resolved = const WafRejectConfig().resolved();
    expect(resolved.visible, true);
    expect(resolved.statusCodes, WafRejectConfig.defaultStatusCodes);
    expect(resolved.contentTypes, WafRejectConfig.defaultContentTypes);
    expect(resolved.environments, isEmpty);
    expect(resolved.appVersions, isEmpty);

    final merged = resolved.mergePatch({
      'visible': true,
      'statusCodes': [200],
      'contentTypes': ['text/html; charset=utf-8'],
      'environments': ['production'],
      'appVersions': ['1.0.0'],
    });
    expect(merged.visible, true);
    expect(merged.statusCodes, [200]);
    expect(merged.contentTypes, ['text/html']);
    expect(merged.environments, ['production']);
    expect(merged.appVersions, ['1.0.0']);
  });

  test('WafRejectConfig round trip json', () {
    final json = const WafRejectConfig(
      visible: true,
      statusCodes: [200, 403],
      contentTypes: ['text/html'],
      environments: ['staging'],
      appVersions: ['2.0.0+10'],
    ).toJson();
    final parsed = WafRejectConfig.fromJson(json).resolved();
    expect(parsed.visible, true);
    expect(parsed.statusCodes, [200, 403]);
    expect(parsed.contentTypes, ['text/html']);
    expect(parsed.environments, ['staging']);
    expect(parsed.appVersions, ['2.0.0+10']);
  });
}
