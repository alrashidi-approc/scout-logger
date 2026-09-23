import 'sdk_config.dart';

/// Dashboard-only knobs for detecting WAF / edge block pages on network events.
///
/// A network response is treated as a WAF reject when its HTTP status is in
/// [statusCodes] and its Content-Type matches one of [contentTypes]
/// (e.g. API expected `application/json` but got `text/html`).
///
/// Optional [environments] / [appVersions] narrow the WAF list (empty = all).
class WafRejectConfig {
  const WafRejectConfig({
    this.visible,
    this.statusCodes,
    this.contentTypes,
    this.environments,
    this.appVersions,
  });

  static const defaultVisible = false;
  static const defaultStatusCodes = [200, 403, 406];
  static const defaultContentTypes = ['text/html'];

  final bool? visible;
  final List<int>? statusCodes;
  final List<String>? contentTypes;
  final List<String>? environments;
  final List<String>? appVersions;

  factory WafRejectConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const WafRejectConfig();
    return WafRejectConfig(
      visible: json['visible'] as bool?,
      statusCodes: normalizeStatusCodes(json['statusCodes'] as List?),
      contentTypes: normalizeContentTypes(json['contentTypes'] as List?),
      environments: normalizeStringList(json['environments'] as List?),
      appVersions: normalizeStringList(json['appVersions'] as List?),
    );
  }

  WafRejectConfig resolved() => WafRejectConfig(
        visible: visible ?? defaultVisible,
        statusCodes: normalizeStatusCodes(
          (statusCodes == null || statusCodes!.isEmpty) ? defaultStatusCodes : statusCodes,
        ),
        contentTypes: normalizeContentTypes(
          (contentTypes == null || contentTypes!.isEmpty) ? defaultContentTypes : contentTypes,
        ),
        environments: normalizeStringList(environments),
        appVersions: normalizeStringList(appVersions),
      );

  WafRejectConfig mergePatch(Map<String, dynamic>? patch) {
    if (patch == null || patch.isEmpty) return this;
    return WafRejectConfig(
      visible: patch.containsKey('visible') ? patch['visible'] == true : visible,
      statusCodes: patch.containsKey('statusCodes')
          ? normalizeStatusCodes(patch['statusCodes'] as List?)
          : statusCodes,
      contentTypes: patch.containsKey('contentTypes')
          ? normalizeContentTypes(patch['contentTypes'] as List?)
          : contentTypes,
      environments: patch.containsKey('environments')
          ? normalizeStringList(patch['environments'] as List?)
          : environments,
      appVersions: patch.containsKey('appVersions')
          ? normalizeStringList(patch['appVersions'] as List?)
          : appVersions,
    );
  }

  Map<String, dynamic> toJson() {
    final r = resolved();
    return {
      'visible': r.visible,
      'statusCodes': r.statusCodes,
      'contentTypes': r.contentTypes,
      'environments': r.environments,
      'appVersions': r.appVersions,
    };
  }
}

List<String> normalizeContentTypes(List<dynamic>? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final out = <String>{};
  for (final item in raw) {
    final s = item.toString().trim().toLowerCase();
    if (s.isEmpty) continue;
    // Strip parameters: "text/html; charset=utf-8" → "text/html"
    final base = s.split(';').first.trim();
    if (base.contains('/')) out.add(base);
  }
  return out.toList()..sort();
}

List<String> normalizeStringList(List<dynamic>? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final out = <String>{};
  for (final item in raw) {
    final s = item.toString().trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out.toList()..sort();
}
