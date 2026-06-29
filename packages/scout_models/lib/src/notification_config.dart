/// Alert notification categories — derived from existing event/fault taxonomy.
const kNotificationCategories = {
  'crash',
  'error',
  'network_critical',
  'network_transport',
  'network_user',
  'network_auth',
};

const kNotificationChannels = {'slack', 'whatsapp', 'email'};

const kDefaultNotificationCategories = ['crash', 'error', 'network_critical', 'network_transport'];
const kDefaultNotificationEnvironments = ['production'];
const kDefaultDedupMinutes = 15;
const kDefaultMaxAlertsPerHour = 0; // 0 = unlimited

const kDefaultNotificationChannels = ['slack', 'whatsapp', 'email'];

class PlatformNotificationPolicy {
  const PlatformNotificationPolicy({
    this.slackAllowed = true,
    this.whatsappAllowed = true,
    this.emailAllowed = true,
  });

  final bool slackAllowed;
  final bool whatsappAllowed;
  final bool emailAllowed;

  factory PlatformNotificationPolicy.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const PlatformNotificationPolicy();
    return PlatformNotificationPolicy(
      slackAllowed: json['slack'] != false,
      whatsappAllowed: json['whatsapp'] != false,
      emailAllowed: json['email'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'slack': slackAllowed,
        'whatsapp': whatsappAllowed,
        'email': emailAllowed,
      };

  bool channelAllowed(String channel) => switch (channel) {
        'slack' => slackAllowed,
        'whatsapp' => whatsappAllowed,
        'email' => emailAllowed,
        _ => false,
      };
}

class NotificationRule {
  const NotificationRule({
    required this.id,
    this.enabled = true,
    this.categories = kDefaultNotificationCategories,
    this.channels = kDefaultNotificationChannels,
    this.environments = kDefaultNotificationEnvironments,
  });

  final String id;
  final bool enabled;
  final List<String> categories;
  final List<String> channels;
  final List<String> environments;

  factory NotificationRule.fromJson(Map<String, dynamic> json) => NotificationRule(
        id: json['id']?.toString() ?? 'default',
        enabled: json['enabled'] != false,
        categories: _normList(json['categories'], kNotificationCategories, kDefaultNotificationCategories),
        channels: _normList(json['channels'], kNotificationChannels, kDefaultNotificationChannels),
        environments: _normEnvs(json['environments']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'categories': categories,
        'channels': channels,
        'environments': environments,
      };

  NotificationRule merge(Map<String, dynamic> patch) => NotificationRule(
        id: id,
        enabled: patch.containsKey('enabled') ? patch['enabled'] == true : enabled,
        categories: patch.containsKey('categories')
            ? _normList(patch['categories'], kNotificationCategories, categories)
            : categories,
        channels: patch.containsKey('channels')
            ? _normList(patch['channels'], kNotificationChannels, channels)
            : channels,
        environments: patch.containsKey('environments') ? _normEnvs(patch['environments']) : environments,
      );
}

class SlackChannelConfig {
  const SlackChannelConfig({this.enabled = false, this.webhookUrlEnc});

  final bool enabled;
  final String? webhookUrlEnc;

  factory SlackChannelConfig.fromJson(Map<String, dynamic>? json) => SlackChannelConfig(
        enabled: json?['enabled'] == true,
        webhookUrlEnc: json?['webhookUrlEnc']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (webhookUrlEnc != null) 'webhookUrlEnc': webhookUrlEnc,
      };

  Map<String, dynamic> toClientJson({bool configured = false}) => {
        'enabled': enabled,
        'configured': configured,
      };
}

class WhatsappChannelConfig {
  const WhatsappChannelConfig({this.enabled = false, this.phoneEnc, this.apiKeyEnc});

  final bool enabled;
  final String? phoneEnc;
  final String? apiKeyEnc;

  factory WhatsappChannelConfig.fromJson(Map<String, dynamic>? json) => WhatsappChannelConfig(
        enabled: json?['enabled'] == true,
        phoneEnc: json?['phoneEnc']?.toString(),
        apiKeyEnc: json?['apiKeyEnc']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        if (phoneEnc != null) 'phoneEnc': phoneEnc,
        if (apiKeyEnc != null) 'apiKeyEnc': apiKeyEnc,
      };

  Map<String, dynamic> toClientJson({bool configured = false}) => {
        'enabled': enabled,
        'configured': configured,
      };
}

class EmailChannelConfig {
  const EmailChannelConfig({
    this.enabled = false,
    this.smtpHost = 'smtp.gmail.com',
    this.smtpPort = 587,
    this.smtpUserEnc,
    this.smtpPasswordEnc,
    this.fromEnc,
    this.recipients = const [],
  });

  final bool enabled;
  final String smtpHost;
  final int smtpPort;
  final String? smtpUserEnc;
  final String? smtpPasswordEnc;
  final String? fromEnc;
  final List<String> recipients;

  factory EmailChannelConfig.fromJson(Map<String, dynamic>? json) => EmailChannelConfig(
        enabled: json?['enabled'] == true,
        smtpHost: json?['smtpHost']?.toString() ?? 'smtp.gmail.com',
        smtpPort: int.tryParse('${json?['smtpPort'] ?? ''}') ?? 587,
        smtpUserEnc: json?['smtpUserEnc']?.toString(),
        smtpPasswordEnc: json?['smtpPasswordEnc']?.toString(),
        fromEnc: json?['fromEnc']?.toString(),
        recipients: _normRecipients(json?['recipients']),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        if (smtpUserEnc != null) 'smtpUserEnc': smtpUserEnc,
        if (smtpPasswordEnc != null) 'smtpPasswordEnc': smtpPasswordEnc,
        if (fromEnc != null) 'fromEnc': fromEnc,
        'recipients': recipients,
      };

  Map<String, dynamic> toClientJson({bool configured = false, String? smtpUserHint}) => {
        'enabled': enabled,
        'configured': configured,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        if (smtpUserHint != null) 'smtpUserHint': smtpUserHint,
        'recipients': recipients,
      };
}

/// Spike detection: alert when incident counts cross a threshold in a window.
class ThresholdConfig {
  const ThresholdConfig({
    this.enabled = false,
    this.mode = 'count',
    this.windowMinutes = 15,
    this.errorCount = 0,
    this.crashCount = 0,
    this.sensitivity = 3.0,
    this.channels = kDefaultNotificationChannels,
  });

  final bool enabled;

  /// 'count' = fixed threshold; 'anomaly' = spike vs learned baseline.
  final String mode;
  final int windowMinutes;

  /// count mode: alert when errors in window reach this. anomaly mode: minimum
  /// events before a spike can fire (noise floor). 0 disables the error metric.
  final int errorCount;

  /// Same as [errorCount] but for crashes.
  final int crashCount;

  /// anomaly mode: how many standard deviations above baseline triggers an alert.
  final double sensitivity;
  final List<String> channels;

  bool get isAnomaly => mode == 'anomaly';

  factory ThresholdConfig.fromJson(Map<String, dynamic>? json) => ThresholdConfig(
        enabled: json?['enabled'] == true,
        mode: json?['mode'] == 'anomaly' ? 'anomaly' : 'count',
        windowMinutes: (int.tryParse('${json?['windowMinutes'] ?? ''}') ?? 15).clamp(5, 1440),
        errorCount: (int.tryParse('${json?['errorCount'] ?? ''}') ?? 0).clamp(0, 100000),
        crashCount: (int.tryParse('${json?['crashCount'] ?? ''}') ?? 0).clamp(0, 100000),
        sensitivity: (double.tryParse('${json?['sensitivity'] ?? ''}') ?? 3.0).clamp(1.0, 6.0),
        channels: _normList(json?['channels'] as List?, kNotificationChannels, kDefaultNotificationChannels),
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'mode': mode,
        'windowMinutes': windowMinutes,
        'errorCount': errorCount,
        'crashCount': crashCount,
        'sensitivity': sensitivity,
        'channels': channels,
      };
}

/// Scheduled summary email of top issues + regressions.
class DigestConfig {
  const DigestConfig({this.enabled = false, this.frequency = 'daily', this.hourUtc = 8, this.channel = 'email'});

  final bool enabled;

  /// 'daily' or 'weekly' (weekly fires on Mondays).
  final String frequency;
  final int hourUtc;
  final String channel;

  factory DigestConfig.fromJson(Map<String, dynamic>? json) => DigestConfig(
        enabled: json?['enabled'] == true,
        frequency: json?['frequency'] == 'weekly' ? 'weekly' : 'daily',
        hourUtc: (int.tryParse('${json?['hourUtc'] ?? ''}') ?? 8).clamp(0, 23),
        channel: kNotificationChannels.contains(json?['channel']) ? json!['channel'] as String : 'email',
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'frequency': frequency,
        'hourUtc': hourUtc,
        'channel': channel,
      };
}

class ProjectNotificationConfig {
  const ProjectNotificationConfig({
    this.enabled = false,
    this.dedupMinutes = kDefaultDedupMinutes,
    this.maxAlertsPerHour = kDefaultMaxAlertsPerHour,
    this.rules = const [NotificationRule(id: 'default')],
    this.slack = const SlackChannelConfig(),
    this.whatsapp = const WhatsappChannelConfig(),
    this.email = const EmailChannelConfig(),
    this.threshold = const ThresholdConfig(),
    this.digest = const DigestConfig(),
  });

  final bool enabled;
  final int dedupMinutes;

  /// Max alerts sent per project per rolling hour. 0 disables the cap.
  final int maxAlertsPerHour;
  final List<NotificationRule> rules;
  final SlackChannelConfig slack;
  final WhatsappChannelConfig whatsapp;
  final EmailChannelConfig email;
  final ThresholdConfig threshold;
  final DigestConfig digest;

  factory ProjectNotificationConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const ProjectNotificationConfig();
    final channels = json['channels'] is Map ? Map<String, dynamic>.from(json['channels'] as Map) : <String, dynamic>{};
    final rulesRaw = json['rules'];
    final rules = rulesRaw is List && rulesRaw.isNotEmpty
        ? rulesRaw.whereType<Map>().map((r) => NotificationRule.fromJson(Map<String, dynamic>.from(r))).toList()
        : [const NotificationRule(id: 'default')];
    return ProjectNotificationConfig(
      enabled: json['enabled'] == true,
      dedupMinutes: _clampDedup(json['dedupMinutes']),
      maxAlertsPerHour: _clampRate(json['maxAlertsPerHour']),
      rules: rules,
      slack: SlackChannelConfig.fromJson(channels['slack'] is Map ? Map<String, dynamic>.from(channels['slack'] as Map) : null),
      whatsapp: WhatsappChannelConfig.fromJson(channels['whatsapp'] is Map ? Map<String, dynamic>.from(channels['whatsapp'] as Map) : null),
      email: EmailChannelConfig.fromJson(channels['email'] is Map ? Map<String, dynamic>.from(channels['email'] as Map) : null),
      threshold: ThresholdConfig.fromJson(json['threshold'] is Map ? Map<String, dynamic>.from(json['threshold'] as Map) : null),
      digest: DigestConfig.fromJson(json['digest'] is Map ? Map<String, dynamic>.from(json['digest'] as Map) : null),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'dedupMinutes': dedupMinutes,
        'maxAlertsPerHour': maxAlertsPerHour,
        'rules': rules.map((r) => r.toJson()).toList(),
        'channels': {
          'slack': slack.toJson(),
          'whatsapp': whatsapp.toJson(),
          'email': email.toJson(),
        },
        'threshold': threshold.toJson(),
        'digest': digest.toJson(),
      };

  Map<String, dynamic> toClientJson({
    required PlatformNotificationPolicy platform,
    bool slackConfigured = false,
    bool whatsappConfigured = false,
    bool emailConfigured = false,
    String? emailUserHint,
  }) =>
      {
        'enabled': enabled,
        'dedupMinutes': dedupMinutes,
        'maxAlertsPerHour': maxAlertsPerHour,
        'rules': rules.map((r) => r.toJson()).toList(),
        'platform': platform.toJson(),
        'channels': {
          'slack': slack.toClientJson(configured: slackConfigured),
          'whatsapp': whatsapp.toClientJson(configured: whatsappConfigured),
          'email': email.toClientJson(configured: emailConfigured, smtpUserHint: emailUserHint),
        },
        'threshold': threshold.toJson(),
        'digest': digest.toJson(),
      };
}

List<String> _normList(List<dynamic>? raw, Set<String> allowed, List<String> fallback) {
  if (raw == null || raw.isEmpty) return List<String>.from(fallback);
  final picked = raw.map((e) => e.toString()).where(allowed.contains).toSet().toList();
  return picked.isEmpty ? List<String>.from(fallback) : picked;
}

List<String> _normEnvs(List<dynamic>? raw) {
  if (raw == null || raw.isEmpty) return List<String>.from(kDefaultNotificationEnvironments);
  final picked = raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  return picked.isEmpty ? List<String>.from(kDefaultNotificationEnvironments) : picked;
}

List<String> _normRecipients(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) => e.toString().trim().toLowerCase())
      .where((s) => s.contains('@'))
      .toSet()
      .toList()
    ..sort();
}

int _clampDedup(dynamic raw) {
  final n = raw is int ? raw : int.tryParse('${raw ?? ''}');
  if (n == null) return kDefaultDedupMinutes;
  return n.clamp(1, 1440);
}

int _clampRate(dynamic raw) {
  final n = raw is int ? raw : int.tryParse('${raw ?? ''}');
  if (n == null) return kDefaultMaxAlertsPerHour;
  return n.clamp(0, 1000);
}
