import 'taxonomy.dart';
import 'network_fault.dart';

/// Remote SDK knobs editable from the dashboard and fetched by mobile clients.
class ProjectSdkConfig {
  const ProjectSdkConfig({
    this.enabledLevels,
    this.enableFlutterHooks,
    this.trackNavigation,
    this.networkCaptureBodies,
    this.networkSlowThresholdMs,
    this.networkIgnoreStatusCodes,
    this.networkLogScope,
    this.networkFaultByStatusCode,
  });

  static const defaultEnabledLevels = ['error', 'info', 'warning', 'success'];
  static const defaultNetworkLogScope = 'all';

  final List<String>? enabledLevels;
  final bool? enableFlutterHooks;
  final bool? trackNavigation;
  final bool? networkCaptureBodies;
  final int? networkSlowThresholdMs;
  final List<int>? networkIgnoreStatusCodes;
  final String? networkLogScope;
  final Map<int, String>? networkFaultByStatusCode;

  factory ProjectSdkConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const ProjectSdkConfig();
    final levels = json['enabledLevels'];
    return ProjectSdkConfig(
      enabledLevels: levels is List ? normalizeEnabledLevels(levels) : null,
      enableFlutterHooks: json['enableFlutterHooks'] as bool?,
      trackNavigation: json['trackNavigation'] as bool?,
      networkCaptureBodies: json['networkCaptureBodies'] as bool?,
      networkSlowThresholdMs: clampSlowThreshold(json['networkSlowThresholdMs']),
      networkIgnoreStatusCodes: normalizeStatusCodes(json['networkIgnoreStatusCodes'] as List?),
      networkLogScope: json.containsKey('networkLogScope')
          ? normalizeNetworkLogScope(json['networkLogScope'])
          : null,
      networkFaultByStatusCode: normalizeNetworkFaultByStatusCode(json['networkFaultByStatusCode']),
    );
  }

  /// Defaults applied — safe to send to SDK clients.
  ProjectSdkConfig resolved() => ProjectSdkConfig(
        enabledLevels: normalizeEnabledLevels(enabledLevels ?? defaultEnabledLevels),
        enableFlutterHooks: enableFlutterHooks ?? true,
        trackNavigation: trackNavigation ?? true,
        networkCaptureBodies: networkCaptureBodies ?? true,
        networkSlowThresholdMs: clampSlowThreshold(networkSlowThresholdMs) ?? 3000,
        networkIgnoreStatusCodes: normalizeStatusCodes(networkIgnoreStatusCodes),
        networkLogScope: normalizeNetworkLogScope(networkLogScope),
        networkFaultByStatusCode: normalizeNetworkFaultByStatusCode(networkFaultByStatusCode),
      );

  ProjectSdkConfig mergePatch(Map<String, dynamic> patch) {
    final sdk = patch['sdk'];
    if (sdk is! Map) return this;
    final m = Map<String, dynamic>.from(sdk);
    return ProjectSdkConfig(
      enabledLevels: m.containsKey('enabledLevels')
          ? normalizeEnabledLevels(m['enabledLevels'] as List?)
          : enabledLevels,
      enableFlutterHooks: m.containsKey('enableFlutterHooks') ? m['enableFlutterHooks'] as bool? : enableFlutterHooks,
      trackNavigation: m.containsKey('trackNavigation') ? m['trackNavigation'] as bool? : trackNavigation,
      networkCaptureBodies:
          m.containsKey('networkCaptureBodies') ? m['networkCaptureBodies'] as bool? : networkCaptureBodies,
      networkSlowThresholdMs: m.containsKey('networkSlowThresholdMs')
          ? clampSlowThreshold(m['networkSlowThresholdMs'])
          : networkSlowThresholdMs,
      networkIgnoreStatusCodes: m.containsKey('networkIgnoreStatusCodes')
          ? normalizeStatusCodes(m['networkIgnoreStatusCodes'] as List?)
          : networkIgnoreStatusCodes,
      networkLogScope: m.containsKey('networkLogScope')
          ? normalizeNetworkLogScope(m['networkLogScope'])
          : networkLogScope,
      networkFaultByStatusCode: m.containsKey('networkFaultByStatusCode')
          ? normalizeNetworkFaultByStatusCode(m['networkFaultByStatusCode'])
          : networkFaultByStatusCode,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabledLevels': normalizeEnabledLevels(enabledLevels ?? defaultEnabledLevels),
        if (enableFlutterHooks != null) 'enableFlutterHooks': enableFlutterHooks,
        if (trackNavigation != null) 'trackNavigation': trackNavigation,
        if (networkCaptureBodies != null) 'networkCaptureBodies': networkCaptureBodies,
        if (networkSlowThresholdMs != null) 'networkSlowThresholdMs': networkSlowThresholdMs,
        'networkIgnoreStatusCodes': normalizeStatusCodes(networkIgnoreStatusCodes),
        'networkLogScope': normalizeNetworkLogScope(networkLogScope),
        if (networkFaultByStatusCode != null && networkFaultByStatusCode!.isNotEmpty)
          'networkFaultByStatusCode': {
            for (final e in normalizeNetworkFaultByStatusCode(networkFaultByStatusCode).entries) '${e.key}': e.value,
          },
      };

  Map<String, dynamic> toClientJson() => resolved().toJson();

  Map<int, NetworkFaultClass> get networkFaultOverrides =>
      parseNetworkFaultOverrides(normalizeNetworkFaultByStatusCode(networkFaultByStatusCode));
}

class ProjectRemoteConfig {
  const ProjectRemoteConfig({
    required this.configVersion,
    required this.updatedAt,
    required this.sdk,
  });

  final int configVersion;
  final String updatedAt;
  final ProjectSdkConfig sdk;

  factory ProjectRemoteConfig.fromSettings(Map<String, dynamic> settings) {
    final sdkJson = settings['sdk'];
    return ProjectRemoteConfig(
      configVersion: settings['configVersion'] as int? ?? 1,
      updatedAt: settings['updatedAt'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      sdk: ProjectSdkConfig.fromJson(sdkJson is Map ? Map<String, dynamic>.from(sdkJson) : null),
    );
  }

  factory ProjectRemoteConfig.defaults() => ProjectRemoteConfig(
        configVersion: 1,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        sdk: const ProjectSdkConfig(),
      );

  Map<String, dynamic> toClientResponse() => {
        'configVersion': configVersion,
        'updatedAt': updatedAt,
        'sdk': sdk.toClientJson(),
      };

  Map<String, dynamic> toSettingsJson() => {
        'configVersion': configVersion,
        'updatedAt': updatedAt,
        'sdk': sdk.toJson(),
      };
}

List<String> normalizeEnabledLevels(List<dynamic>? raw) {
  if (raw == null || raw.isEmpty) return List<String>.from(ProjectSdkConfig.defaultEnabledLevels);
  final picked = raw.map((e) => e.toString().toLowerCase()).where(isKnownEventLevel).toSet();
  if (picked.isEmpty) return List<String>.from(ProjectSdkConfig.defaultEnabledLevels);
  return ['error', 'info', 'warning', 'success'].where(picked.contains).toList();
}

int? clampSlowThreshold(dynamic raw) {
  if (raw == null) return null;
  final n = raw is int ? raw : int.tryParse(raw.toString());
  if (n == null) return null;
  return n.clamp(500, 60000);
}

Map<int, String> normalizeNetworkFaultByStatusCode(dynamic raw) {
  if (raw == null) return const {};
  if (raw is! Map) return const {};
  final out = <int, String>{};
  for (final e in raw.entries) {
    final code = e.key is int ? e.key as int : int.tryParse(e.key.toString());
    if (code == null || code < 100 || code > 599) continue;
    final cls = parseNetworkFaultClass(e.value?.toString());
    if (cls != null && cls != NetworkFaultClass.unknown) out[code] = cls.name;
  }
  return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

List<int> normalizeStatusCodes(List<dynamic>? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final codes = <int>{};
  for (final item in raw) {
    final n = item is int ? item : int.tryParse(item.toString());
    if (n != null && n >= 100 && n <= 599) codes.add(n);
  }
  return codes.toList()..sort();
}

const kNetworkLogScopes = ['all', 'errorsOnly', 'slowOnly'];

/// Wire values: `all`, `errorsOnly`, `slowOnly`.
String normalizeNetworkLogScope(dynamic raw) {
  if (raw == null) return ProjectSdkConfig.defaultNetworkLogScope;
  final s = raw.toString().trim();
  return switch (s) {
    'errors_only' || 'errorsOnly' => 'errorsOnly',
    'slow_only' || 'slowOnly' => 'slowOnly',
    'all' => 'all',
    _ => kNetworkLogScopes.contains(s) ? s : ProjectSdkConfig.defaultNetworkLogScope,
  };
}
