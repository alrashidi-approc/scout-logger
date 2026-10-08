import 'dart:convert';

import 'package:scout_models/scout_models.dart';
import 'package:shelf/shelf.dart';

import '../config/server_config.dart';
import '../middleware/http_utils.dart';
import '../notifications/telegram_client.dart';
import '../notifications/telegram_commands.dart';
import '../notifications/telegram_link.dart';
import '../reports/report_service.dart';
import '../store/analytics_store.dart';
import '../store/health_check_store.dart';
import '../store/notification_store.dart';
import '../store/scout_store.dart';
import '../util/dashboard_links.dart';
import '../util/dates.dart';

/// Telegram bot webhook. Verifies `X-Telegram-Bot-Api-Secret-Token`.
/// Accepts a connect `/start` token, the fixed command menu, and alert buttons.
Handler telegramWebhook(
  ServerConfig config,
  NotificationStore? store,
  ScoutStore scout,
  AnalyticsStore analytics,
) {
  final client = TelegramClient(config.telegramBotToken);
  final health = HealthCheckStore(scout.db);
  final reports = ReportService(scout, analytics);
  return (Request request) async {
    if (store == null || config.telegramBotToken.isEmpty || config.telegramWebhookSecret.isEmpty) {
      return Response.notFound('Telegram webhook disabled');
    }

    final got = request.headers['x-telegram-bot-api-secret-token'];
    if (got == null || !constantTimeEquals(config.telegramWebhookSecret, got)) {
      return Response.forbidden('Invalid signature');
    }

    Map<String, dynamic> update;
    try {
      final decoded = jsonDecode(await request.readAsString());
      if (decoded is! Map) return Response.ok('');
      update = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return Response.ok('');
    }

    final callback = update['callback_query'];
    if (callback is Map) {
      await _answerCallback(
        client: client,
        store: store,
        scout: scout,
        query: Map<String, dynamic>.from(callback),
      );
      return Response.ok('');
    }

    String? reply;
    try {
      reply = await handleTelegramUpdate(
        update: update,
        consumeLink: store.consumeTelegramLink,
        bind: (projectId, chatId, chatTitle) => store.bindTelegramChat(projectId, chatId: chatId, chatTitle: chatTitle),
        projectName: store.projectName,
        projectForChat: store.projectIdForTelegramChat,
        runCommand: (projectId, command) => _runCommand(
          command: command,
          projectId: projectId,
          config: config,
          store: store,
          scout: scout,
          health: health,
          reports: reports,
        ),
      );
    } catch (_) {
      reply = 'Could not load that. Try again in a moment.';
    }
    if (reply != null) {
      final message = update['message'];
      final chat = message is Map ? message['chat'] : null;
      final chatId = chat is Map ? chat['id']?.toString() : null;
      if (chatId != null && chatId.isNotEmpty) {
        try {
          await client.sendMessage(chatId: chatId, text: reply, replyMarkup: telegramReplyKeyboard);
        } catch (_) {
          // A failed reply should not make Telegram retry the update.
        }
      }
    }
    return Response.ok('');
  };
}

Future<String> _runCommand({
  required String command,
  required String projectId,
  required ServerConfig config,
  required NotificationStore store,
  required ScoutStore scout,
  required HealthCheckStore health,
  required ReportService reports,
}) async {
  final link = '${dashboardBaseUrl(config)}/p/$projectId';
  if (command == 'pause') {
    final until = await store.pauseTelegramAlerts(projectId);
    return telegramWithLink(telegramPausedText(until), link);
  }
  if (command == 'up') {
    final name = await _label(store, projectId);
    final uptime = await health.getUptime(projectId);
    return telegramWithLink(telegramUptimeText(projectName: name, uptime: uptime), link);
  }
  if (command == 'report') {
    final report = await reports.build(
      ReportType.executiveSummary,
      projectId,
      TimeWindow.lastDays(7),
      audience: ReportAudience.executive,
    );
    return telegramWithLink(ReportService.toPlainText(report), report.snapshotUrl ?? link);
  }
  final body = await telegramCommandReply(
    command: command,
    projectId: projectId,
    projectName: store.projectName,
    overview: (id) => scout.projectOverview(id, days: 1, includeTrend: false),
    healthRun: (id) async {
      final runs = await health.listRuns(id, limit: 1);
      return runs.isEmpty ? null : runs.first;
    },
    issues: (id) => scout.digestData(id, hours: 24, limit: 5),
  );
  return telegramWithLink(body, link);
}

Future<void> _answerCallback({
  required TelegramClient client,
  required NotificationStore store,
  required ScoutStore scout,
  required Map<String, dynamic> query,
}) async {
  final callbackId = query['id']?.toString() ?? '';
  final data = query['data']?.toString() ?? '';
  final message = query['message'];
  final chat = message is Map ? message['chat'] : null;
  final chatId = chat is Map ? chat['id']?.toString() : null;
  if (callbackId.isEmpty || chatId == null || chatId.isEmpty) return;

  String toast;
  try {
    final action = parseTelegramCallback(data);
    final projectId = await store.projectIdForTelegramChat(chatId);
    if (action == null || projectId == null) {
      toast = projectId == null ? 'This chat is not connected.' : 'That button is not available.';
    } else if (action.kind == 'pause') {
      final until = await store.pauseTelegramAlerts(projectId);
      toast = telegramPausedText(until);
    } else {
      final issueId = action.issueId;
      final status = action.kind == 'resolve' ? 'resolved' : 'ignored';
      if (issueId == null || issueId.isEmpty) {
        toast = 'Issue not found.';
      } else {
        final updated = await scout.updateIssueStatus(projectId, issueId, status);
        final title = updated?['title']?.toString().trim();
        toast = updated == null
            ? 'Issue not found in this project.'
            : '${action.kind == 'resolve' ? 'Resolved' : 'Muted'}${title == null || title.isEmpty ? '' : ': $title'}';
      }
    }
  } catch (_) {
    toast = 'Could not do that. Try again in a moment.';
  }

  try {
    await client.answerCallbackQuery(callbackId, text: toast);
  } catch (_) {}
  try {
    await client.sendMessage(chatId: chatId, text: toast, replyMarkup: telegramReplyKeyboard);
  } catch (_) {}
}

Future<String> _label(NotificationStore store, String projectId) async {
  final name = (await store.projectName(projectId))?.trim();
  return (name == null || name.isEmpty) ? projectId : name;
}
