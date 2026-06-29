import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';

import '../db/scout_db.dart';
import '../services/key_cipher.dart';
import '../util/ids.dart';

class NotificationStore {
  NotificationStore(this.db, {KeyCipher? cipher}) : _cipher = cipher;

  final ScoutDb db;
  final KeyCipher? _cipher;

  Future<ProjectNotificationConfig> getConfig(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT settings FROM projects WHERE id = @id'),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) throw ArgumentError('Project not found');
    final settings = rows.first[0];
    final map = settings is Map ? Map<String, dynamic>.from(settings) : <String, dynamic>{};
    return ProjectNotificationConfig.fromJson(
      map['notifications'] is Map ? Map<String, dynamic>.from(map['notifications'] as Map) : null,
    );
  }

  Future<Map<String, dynamic>> getClientConfig(
    String projectId, {
    required PlatformNotificationPolicy platform,
  }) async {
    final config = await getConfig(projectId);
    return config.toClientJson(
      platform: platform,
      slackConfigured: config.slack.webhookUrlEnc?.isNotEmpty ?? false,
      whatsappConfigured: (config.whatsapp.phoneEnc?.isNotEmpty ?? false) && (config.whatsapp.apiKeyEnc?.isNotEmpty ?? false),
      emailConfigured: (config.email.smtpUserEnc?.isNotEmpty ?? false) && (config.email.smtpPasswordEnc?.isNotEmpty ?? false),
      emailUserHint: _hint(_cipher?.decrypt(config.email.smtpUserEnc)),
    );
  }

  Future<ProjectNotificationConfig> updateConfig(String projectId, Map<String, dynamic> patch) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT settings FROM projects WHERE id = @id FOR UPDATE'),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) throw ArgumentError('Project not found');
    final raw = rows.first[0];
    final settings = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final current = ProjectNotificationConfig.fromJson(
      settings['notifications'] is Map ? Map<String, dynamic>.from(settings['notifications'] as Map) : null,
    );
    final next = _merge(current, patch);
    settings['notifications'] = next.toJson();
    await conn.execute(
      Sql.named('UPDATE projects SET settings = @settings::jsonb WHERE id = @id'),
      parameters: {'id': projectId, 'settings': jsonEncode(settings)},
    );
    return next;
  }

  ProjectNotificationConfig _merge(ProjectNotificationConfig current, Map<String, dynamic> patch) {
    var rules = current.rules;
    if (patch['rules'] is List) {
      rules = (patch['rules'] as List)
          .whereType<Map>()
          .map((r) => NotificationRule.fromJson(Map<String, dynamic>.from(r)))
          .toList();
      if (rules.isEmpty) rules = current.rules;
    }

    final channels = patch['channels'] is Map ? Map<String, dynamic>.from(patch['channels'] as Map) : <String, dynamic>{};
    final slackPatch = channels['slack'] is Map ? Map<String, dynamic>.from(channels['slack'] as Map) : null;
    final waPatch = channels['whatsapp'] is Map ? Map<String, dynamic>.from(channels['whatsapp'] as Map) : null;
    final emailPatch = channels['email'] is Map ? Map<String, dynamic>.from(channels['email'] as Map) : null;

    return ProjectNotificationConfig(
      enabled: patch.containsKey('enabled') ? patch['enabled'] == true : current.enabled,
      dedupMinutes: patch.containsKey('dedupMinutes') ? _clampDedup(patch['dedupMinutes']) : current.dedupMinutes,
      maxAlertsPerHour: patch.containsKey('maxAlertsPerHour') ? _clampRate(patch['maxAlertsPerHour']) : current.maxAlertsPerHour,
      rules: rules,
      slack: _mergeSlack(current.slack, slackPatch),
      whatsapp: _mergeWhatsapp(current.whatsapp, waPatch),
      email: _mergeEmail(current.email, emailPatch),
      threshold: patch['threshold'] is Map
          ? ThresholdConfig.fromJson(Map<String, dynamic>.from(patch['threshold'] as Map))
          : current.threshold,
      digest: patch['digest'] is Map
          ? DigestConfig.fromJson(Map<String, dynamic>.from(patch['digest'] as Map))
          : current.digest,
    );
  }

  SlackChannelConfig _mergeSlack(SlackChannelConfig current, Map<String, dynamic>? patch) {
    if (patch == null) return current;
    return SlackChannelConfig(
      enabled: patch.containsKey('enabled') ? patch['enabled'] == true : current.enabled,
      webhookUrlEnc: _encField(patch, 'webhookUrl', current.webhookUrlEnc),
    );
  }

  WhatsappChannelConfig _mergeWhatsapp(WhatsappChannelConfig current, Map<String, dynamic>? patch) {
    if (patch == null) return current;
    return WhatsappChannelConfig(
      enabled: patch.containsKey('enabled') ? patch['enabled'] == true : current.enabled,
      phoneEnc: _encField(patch, 'phone', current.phoneEnc),
      apiKeyEnc: _encField(patch, 'apiKey', current.apiKeyEnc),
    );
  }

  EmailChannelConfig _mergeEmail(EmailChannelConfig current, Map<String, dynamic>? patch) {
    if (patch == null) return current;
    return EmailChannelConfig(
      enabled: patch.containsKey('enabled') ? patch['enabled'] == true : current.enabled,
      smtpHost: patch['smtpHost']?.toString() ?? current.smtpHost,
      smtpPort: patch.containsKey('smtpPort') ? int.tryParse('${patch['smtpPort']}') ?? current.smtpPort : current.smtpPort,
      smtpUserEnc: _encField(patch, 'smtpUser', current.smtpUserEnc),
      smtpPasswordEnc: _encField(patch, 'smtpPassword', current.smtpPasswordEnc),
      fromEnc: _encField(patch, 'from', current.fromEnc),
      recipients: patch.containsKey('recipients') ? _normRecipients(patch['recipients']) : current.recipients,
    );
  }

  String? _encField(Map<String, dynamic> patch, String key, String? current) {
    if (!patch.containsKey(key)) return current;
    final plain = patch[key]?.toString().trim() ?? '';
    if (plain.isEmpty) return current;
    return _cipher?.encrypt(plain) ?? plain;
  }

  String? _hint(String? email) {
    if (email == null || !email.contains('@')) return null;
    final parts = email.split('@');
    final local = parts.first;
    if (local.length <= 2) return '${local[0]}***@${parts[1]}';
    return '${local.substring(0, 2)}***@${parts[1]}';
  }

  List<String> _normRecipients(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString().trim().toLowerCase()).where((s) => s.contains('@')).toSet().toList()..sort();
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

  /// Count alerts actually sent for a project within the last [minutes].
  Future<int> sentCountSince(String projectId, {int minutes = 60}) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT COUNT(*)::int FROM notification_deliveries
        WHERE project_id = @pid
          AND status = 'sent'
          AND created_at >= now() - (@mins::text || ' minutes')::interval
      '''),
      parameters: {'pid': projectId, 'mins': minutes},
    );
    return (rows.first[0] as int?) ?? 0;
  }

  Future<bool> recentlyDelivered({
    required String projectId,
    required String dedupKey,
    required String channel,
    required int withinMinutes,
  }) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT 1 FROM notification_deliveries
        WHERE project_id = @pid
          AND dedup_key = @dk
          AND channel = @ch
          AND status = 'sent'
          AND created_at >= now() - (@mins::text || ' minutes')::interval
        LIMIT 1
      '''),
      parameters: {'pid': projectId, 'dk': dedupKey, 'ch': channel, 'mins': withinMinutes},
    );
    return rows.isNotEmpty;
  }

  Future<void> logDelivery({
    required String projectId,
    required String eventId,
    required String? issueId,
    required String dedupKey,
    required String category,
    required String channel,
    required String status,
    String? errorMessage,
  }) async {
    final conn = await db.connect();
    await conn.execute(
      Sql.named('''
        INSERT INTO notification_deliveries (
          id, project_id, event_id, issue_id, dedup_key, category, channel, status, error_message
        ) VALUES (
          @id, @pid, @eid, @iid, @dk, @cat, @ch, @st, @err
        )
      '''),
      parameters: {
        'id': newId(),
        'pid': projectId,
        'eid': eventId,
        'iid': issueId,
        'dk': dedupKey,
        'cat': category,
        'ch': channel,
        'st': status,
        'err': errorMessage,
      },
    );
  }

  /// Delivery counts grouped by status over the last [hours].
  Future<Map<String, int>> deliverySummary(String projectId, {int hours = 24}) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT status, COUNT(*)::int FROM notification_deliveries
        WHERE project_id = @pid
          AND created_at >= now() - (@hrs::text || ' hours')::interval
        GROUP BY status
      '''),
      parameters: {'pid': projectId, 'hrs': hours},
    );
    return {for (final r in rows) r[0] as String: (r[1] as int?) ?? 0};
  }

  Future<List<Map<String, dynamic>>> listDeliveries(String projectId, {int limit = 50}) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('''
        SELECT id, event_id, issue_id, category, channel, status, error_message, created_at
        FROM notification_deliveries
        WHERE project_id = @pid
        ORDER BY created_at DESC
        LIMIT @lim
      '''),
      parameters: {'pid': projectId, 'lim': limit},
    );
    return rows
        .map((r) => {
              'id': r[0],
              'eventId': r[1],
              'issueId': r[2],
              'category': r[3],
              'channel': r[4],
              'status': r[5],
              'errorMessage': r[6],
              'createdAt': (r[7] as DateTime?)?.toUtc().toIso8601String(),
            })
        .toList();
  }

  /// Deliveries across every project the user can access (admin = all), newest first.
  Future<List<Map<String, dynamic>>> listAllDeliveries({String? userId, bool admin = false, int limit = 100}) async {
    if (!admin && userId == null) return const [];
    final conn = await db.connect();
    final scope = admin
        ? ''
        : 'JOIN project_memberships m ON m.project_id = d.project_id AND m.user_id = @uid';
    final rows = await conn.execute(
      Sql.named('''
        SELECT d.id, d.project_id, p.name, d.event_id, d.issue_id, d.category, d.channel, d.status, d.error_message, d.created_at
        FROM notification_deliveries d
        JOIN projects p ON p.id = d.project_id
        $scope
        ORDER BY d.created_at DESC
        LIMIT @lim
      '''),
      parameters: {'lim': limit, if (!admin) 'uid': userId},
    );
    return rows
        .map((r) => {
              'id': r[0],
              'projectId': r[1],
              'projectName': r[2],
              'eventId': r[3],
              'issueId': r[4],
              'category': r[5],
              'channel': r[6],
              'status': r[7],
              'errorMessage': r[8],
              'createdAt': (r[9] as DateTime?)?.toUtc().toIso8601String(),
            })
        .toList();
  }

  /// Delivery counts by status across the user's projects over the last [hours].
  Future<Map<String, int>> globalDeliverySummary({String? userId, bool admin = false, int hours = 24}) async {
    if (!admin && userId == null) return const {};
    final conn = await db.connect();
    final scope = admin
        ? ''
        : 'JOIN project_memberships m ON m.project_id = d.project_id AND m.user_id = @uid';
    final rows = await conn.execute(
      Sql.named('''
        SELECT d.status, COUNT(*)::int FROM notification_deliveries d
        $scope
        WHERE d.created_at >= now() - (@hrs::text || ' hours')::interval
        GROUP BY d.status
      '''),
      parameters: {'hrs': hours, if (!admin) 'uid': userId},
    );
    return {for (final r in rows) r[0] as String: (r[1] as int?) ?? 0};
  }

  /// All projects that have notifications enabled, with name + parsed config.
  Future<List<({String id, String name, ProjectNotificationConfig config})>> allEnabledConfigs() async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named("SELECT id, name, settings FROM projects WHERE settings->'notifications'->>'enabled' = 'true'"),
    );
    final out = <({String id, String name, ProjectNotificationConfig config})>[];
    for (final r in rows) {
      final settings = r[2] is Map ? Map<String, dynamic>.from(r[2] as Map) : <String, dynamic>{};
      final config = ProjectNotificationConfig.fromJson(
        settings['notifications'] is Map ? Map<String, dynamic>.from(settings['notifications'] as Map) : null,
      );
      out.add((id: r[0] as String, name: r[1] as String? ?? r[0] as String, config: config));
    }
    return out;
  }

  Future<String?> projectName(String projectId) async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT name FROM projects WHERE id = @id'),
      parameters: {'id': projectId},
    );
    if (rows.isEmpty) return null;
    return rows.first[0] as String?;
  }
}
