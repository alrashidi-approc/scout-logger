import 'package:scout_models/scout_models.dart';

import 'notification_categories.dart';

class NotificationJob {
  NotificationJob({
    required this.channel,
    required this.category,
    required this.dedupKey,
    required this.title,
    required this.body,
    required this.eventUrl,
  });

  final String channel;
  final String category;
  final String dedupKey;
  final String title;
  final String body;
  final String eventUrl;
}

List<NotificationJob> routeNotifications({
  required ProjectNotificationConfig config,
  required PlatformNotificationPolicy platform,
  required String projectId,
  required String projectName,
  required String eventId,
  required String type,
  required String environment,
  required String? message,
  required Map<String, dynamic> payload,
  required String? fingerprint,
  required String dashboardBaseUrl,
}) {
  if (!config.enabled) return const [];

  final categories = notificationCategoriesFor(type: type, payload: payload);
  if (categories.isEmpty) return const [];

  final jobs = <NotificationJob>[];
  final seen = <String>{};
  final dedupBase = fingerprint ?? eventId;
  final title = _alertTitle(type: type, message: message, payload: payload);
  final body = _alertBody(
    projectName: projectName,
    type: type,
    environment: environment,
    message: message,
    payload: payload,
    categories: categories,
  );
  final eventUrl = '$dashboardBaseUrl/p/$projectId/events/$eventId';

  for (final rule in config.rules) {
    if (!rule.enabled) continue;
    if (!environmentMatchesRule(environment, rule.environments)) continue;
    final matched = rule.categories.where(categories.contains).toList();
    if (matched.isEmpty) continue;

    for (final category in matched) {
      for (final channel in rule.channels) {
        if (!platform.channelAllowed(channel)) continue;
        if (!_channelReady(config, channel)) continue;
        final key = '$channel:$dedupBase:$category';
        if (!seen.add(key)) continue;
        jobs.add(NotificationJob(
          channel: channel,
          category: category,
          dedupKey: dedupBase,
          title: title,
          body: body,
          eventUrl: eventUrl,
        ));
      }
    }
  }
  return jobs;
}

bool _channelReady(ProjectNotificationConfig config, String channel) => switch (channel) {
      'slack' => config.slack.enabled && (config.slack.webhookUrlEnc?.isNotEmpty ?? false),
      'whatsapp' => config.whatsapp.enabled &&
          (config.whatsapp.phoneEnc?.isNotEmpty ?? false) &&
          (config.whatsapp.apiKeyEnc?.isNotEmpty ?? false),
      'email' => config.email.enabled &&
          (config.email.smtpUserEnc?.isNotEmpty ?? false) &&
          (config.email.smtpPasswordEnc?.isNotEmpty ?? false) &&
          config.email.recipients.isNotEmpty,
      _ => false,
    };

String _alertTitle({required String type, required String? message, required Map<String, dynamic> payload}) {
  if (type == 'network') {
    final readable = payload['network'] is Map ? (payload['network'] as Map)['readable'] : null;
    if (readable is Map && readable['title'] != null) return readable['title'].toString();
  }
  final msg = message?.trim();
  if (msg != null && msg.isNotEmpty) return msg.length > 120 ? '${msg.substring(0, 117)}…' : msg;
  return '${type.toUpperCase()} alert';
}

String _alertBody({
  required String projectName,
  required String type,
  required String environment,
  required String? message,
  required Map<String, dynamic> payload,
  required Set<String> categories,
}) {
  final buf = StringBuffer()
    ..writeln('Project: $projectName')
    ..writeln('Type: $type · $environment')
    ..writeln('Categories: ${categories.join(', ')}');
  if (message != null && message.isNotEmpty) buf.writeln('Message: $message');
  if (type == 'network' && payload['network'] is Map) {
    final n = Map<String, dynamic>.from(payload['network'] as Map);
    final method = n['method']?.toString();
    final url = n['url']?.toString() ?? n['path']?.toString();
    final code = n['statusCode']?.toString();
    if (method != null || url != null) buf.writeln('Request: ${method ?? '?'} ${url ?? ''}'.trim());
    if (code != null) buf.writeln('HTTP: $code');
  }
  return buf.toString().trim();
}
