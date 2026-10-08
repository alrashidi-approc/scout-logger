import 'dart:io';

import 'package:scout_server/app.dart';
import 'package:scout_server/config/server_config.dart';
import 'package:scout_server/db/scout_db.dart';
import 'package:scout_server/store/analytics_store.dart';
import 'package:scout_server/services/key_cipher.dart';
import 'package:scout_server/store/health_check_store.dart';
import 'package:scout_server/store/notification_store.dart';
import 'package:scout_server/store/platform_store.dart';
import 'package:scout_server/notifications/notification_dispatcher.dart';
import 'package:scout_server/notifications/telegram_client.dart';
import 'package:scout_server/notifications/notification_service.dart';
import 'package:scout_server/notifications/monitor_scheduler.dart';
import 'package:scout_server/health_check/uptime_monitor.dart';
import 'package:scout_server/retention/issue_signals_scheduler.dart';
import 'package:scout_server/retention/retention_scheduler.dart';
import 'package:scout_server/reports/report_service.dart';
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
    final dispatcher = NotificationDispatcher(
      cipher: cipher,
      slackInteractive: config.slackSigningSecret.isNotEmpty,
      telegramBotToken: config.telegramBotToken,
    );
    final notificationService = NotificationService(
      store: notificationStore,
      platformStore: platformStore,
      dispatcher: dispatcher,
      config: config,
    );
    final store = ScoutStore(db, cipher: cipher, notifications: notificationService);
    notificationService.scout = store;
    final analytics = AnalyticsStore(db);

    MonitorScheduler(
      scout: store,
      store: notificationStore,
      platformStore: platformStore,
      dispatcher: dispatcher,
      reports: ReportService(store, analytics),
      config: config,
    ).start();
    final healthCheckStore = HealthCheckStore(db);
    UptimeMonitorScheduler(
      healthStore: healthCheckStore,
      notificationStore: notificationStore,
      platformStore: platformStore,
      notifications: notificationService,
      config: config,
    ).start();
    RetentionScheduler(store: store).start();
    IssueSignalsScheduler(store: store).start();
    final handler = createApp(
      config: config,
      store: store,
      analytics: analytics,
      notifications: notificationService,
      notificationStore: notificationStore,
    );
    await _registerTelegramWebhook(config);
    stdout.writeln('scout-logger listening on ${config.publicUrl}');
    stdout.writeln('Dashboard: ${config.dashboardPublicUrl}');
    if (config.smtpUser.isEmpty || config.smtpPassword.isEmpty) {
      stdout.writeln('Email: SMTP not configured — new accounts are verified automatically on signup');
    }
    await serve(handler, config.host, config.port);
  } catch (e, st) {
    stderr.writeln('scout-logger failed to start: $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}

Future<void> _registerTelegramWebhook(ServerConfig config) async {
  if (config.telegramBotToken.isEmpty) return;
  if (!config.publicUrl.startsWith('https://') || config.telegramWebhookSecret.isEmpty) {
    stdout.writeln('Telegram: webhook not registered — set an https PUBLIC_URL and TELEGRAM_WEBHOOK_SECRET');
    return;
  }
    try {
      final client = TelegramClient(config.telegramBotToken);
      await client.setMyCommands();
      await client.setWebhook(
        url: '${config.publicUrl}/telegram/webhook',
        secret: config.telegramWebhookSecret,
      );
      stdout.writeln('Telegram: webhook registered');
    } catch (e) {
      stderr.writeln('Telegram: setWebhook failed: $e');
    }
}
