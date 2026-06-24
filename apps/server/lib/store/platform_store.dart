import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:scout_models/scout_models.dart';

import '../db/scout_db.dart';

class PlatformStore {
  PlatformStore(this.db);

  final ScoutDb db;
  static const notificationChannelsKey = 'notification_channels';

  Future<PlatformNotificationPolicy> getNotificationPolicy() async {
    final conn = await db.connect();
    final rows = await conn.execute(
      Sql.named('SELECT value FROM platform_settings WHERE key = @k'),
      parameters: {'k': notificationChannelsKey},
    );
    if (rows.isEmpty) return const PlatformNotificationPolicy();
    final raw = rows.first[0];
    return PlatformNotificationPolicy.fromJson(raw is Map ? Map<String, dynamic>.from(raw) : null);
  }

  Future<PlatformNotificationPolicy> updateNotificationPolicy(PlatformNotificationPolicy policy) async {
    final conn = await db.connect();
    await conn.execute(
      Sql.named('''
        INSERT INTO platform_settings (key, value, updated_at)
        VALUES (@k, @v::jsonb, now())
        ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()
      '''),
      parameters: {'k': notificationChannelsKey, 'v': jsonEncode(policy.toJson())},
    );
    return policy;
  }
}
