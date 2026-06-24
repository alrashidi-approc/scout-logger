import 'dart:io';

import 'package:scout_server/app.dart';
import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/db/scout_db.dart';
import 'package:scout_server/store/analytics_store.dart';
import 'package:scout_server/services/key_cipher.dart';
import 'package:scout_server/store/notification_store.dart';
import 'package:scout_server/store/platform_store.dart';
import 'package:scout_server/notifications/notification_dispatcher.dart';
import 'package:scout_server/notifications/notification_service.dart';
import 'package:scout_server/store/scout_store.dart';
import 'package:shelf/shelf_io.dart';

Future<void> main() async {
  try {
    final config = ServerConfig.load();
    final db = ScoutDb(config.dbConfig);
    await runMigrations(db);
    await db.ping();

    final cipher = KeyCipher(config.encryptionKey);
    final platformStore = PlatformStore(db);
    final notificationStore = NotificationStore(db, cipher: cipher);
    final notificationService = NotificationService(
      store: notificationStore,
      platformStore: platformStore,
      dispatcher: NotificationDispatcher(cipher: cipher),
      config: config,
    );
    final store = ScoutStore(db, cipher: cipher, notifications: notificationService);
    final analytics = AnalyticsStore(db);
    final handler = createApp(
      config: config,
      store: store,
      analytics: analytics,
      notifications: notificationService,
      notificationStore: notificationStore,
    );
    stdout.writeln('scout-logger listening on ${config.publicUrl}');
    stdout.writeln('Dashboard: ${config.dashboardPublicUrl}');
    if (config.smtpHost.isEmpty) {
      stdout.writeln('Email: SMTP not configured — new accounts are verified automatically on signup');
    }
    await serve(handler, config.host, config.port);
  } catch (e, st) {
    stderr.writeln('scout-logger failed to start: $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}
