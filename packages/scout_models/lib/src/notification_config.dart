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

class ProjectNotificationConfig {
  const ProjectNotificationConfig({
    this.enabled = false,
    this.dedupMinutes = kDefaultDedupMinutes,
    this.rules = const [NotificationRule(id: 'default')],
    this.slack = const SlackChannelConfig(),
    this.whatsapp = const WhatsappChannelConfig(),
    this.email = const EmailChannelConfig(),
  });

  final bool enabled;
  final int dedupMinutes;
  final List<NotificationRule> rules;
  final SlackChannelConfig slack;
  final WhatsappChannelConfig whatsapp;
  final EmailChannelConfig email;

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
      rules: rules,
      slack: SlackChannelConfig.fromJson(channels['slack'] is Map ? Map<String, dynamic>.from(channels['slack'] as Map) : null),
      whatsapp: WhatsappChannelConfig.fromJson(channels['whatsapp'] is Map ? Map<String, dynamic>.from(channels['whatsapp'] as Map) : null),
      email: EmailChannelConfig.fromJson(channels['email'] is Map ? Map<String, dynamic>.from(channels['email'] as Map) : null),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'dedupMinutes': dedupMinutes,
        'rules': rules.map((r) => r.toJson()).toList(),
        'channels': {
          'slack': slack.toJson(),
          'whatsapp': whatsapp.toJson(),
          'email': email.toJson(),
        },
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
        'rules': rules.map((r) => r.toJson()).toList(),
        'platform': platform.toJson(),
        'channels': {
          'slack': slack.toClientJson(configured: slackConfigured),
          'whatsapp': whatsapp.toClientJson(configured: whatsappConfigured),
          'email': email.toClientJson(configured: emailConfigured, smtpUserHint: emailUserHint),
        },
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
