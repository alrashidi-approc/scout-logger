import 'package:scout_models/scout_models.dart';

import '../util/insights.dart';
import 'notification_categories.dart';

class NotificationJob {
  NotificationJob({
    required this.channel,
    required this.category,
    required this.dedupKey,
    required this.title,
    required this.body,
    required this.eventUrl,
    this.environment,
    this.release,
    this.issueId,
  });

  final String channel;
  final String category;
  final String dedupKey;
  final String title;
  final String body;
  final String eventUrl;

  /// SDK environment / flavor (e.g. production, staging).
  final String? environment;

  /// App release version when available.
  final String? release;

  /// Issue this alert belongs to (enables Slack action buttons).
  final String? issueId;

  /// A copy flagged as a regression (resolved issue reopened).
  NotificationJob asRegression() => NotificationJob(
        channel: channel,
        category: category,
        dedupKey: dedupKey,
        title: '🔁 Regression: $title',
        body: 'A resolved issue has reoccurred.\n$body',
        eventUrl: eventUrl,
        environment: environment,
        release: release,
        issueId: issueId,
      );
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
  String? issueId,
  required String dashboardBaseUrl,
}) {
  if (!config.enabled) return const [];
  // Hard gate: never route automatic alerts for non-release environments.
  if (!isReleaseNotificationEnvironment(environment)) return const [];

  final categories = notificationCategoriesFor(type: type, payload: payload);
  if (categories.isEmpty) return const [];

  final jobs = <NotificationJob>[];
  final seen = <String>{};
  final dedupBase = issueId ?? fingerprint ?? eventId;
  final release = _releaseFromPayload(payload);
  final title = _alertTitle(type: type, environment: environment, message: message, payload: payload);
  final body = _alertBody(
    projectName: projectName,
    type: type,
    environment: environment,
    release: release,
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
        if (!channelReady(config, channel)) continue;
        final key = '$channel:$dedupBase';
        if (!seen.add(key)) continue;
        jobs.add(NotificationJob(
          channel: channel,
          category: category,
          dedupKey: dedupBase,
          title: title,
          body: body,
          eventUrl: eventUrl,
          environment: environment,
          release: release,
          issueId: issueId,
        ));
      }
    }
  }
  return jobs;
}

List<String> readyNotificationChannels({
  required ProjectNotificationConfig config,
  required PlatformNotificationPolicy platform,
}) =>
    kNotificationChannels.where((c) => platform.channelAllowed(c) && channelReady(config, c)).toList();

bool channelReady(ProjectNotificationConfig config, String channel) => switch (channel) {
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

String _envTag(String environment) => '[${environment.toLowerCase()}]';

String? _releaseFromPayload(Map<String, dynamic> payload) {
  final direct = payload['release'];
  if (direct is String && direct.trim().isNotEmpty) return direct.trim();
  if (direct is Map) {
    final v = direct['version'] ?? direct['name'] ?? direct['id'];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  final app = payload['app'];
  if (app is Map) {
    final v = app['version'] ?? app['build'];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  return null;
}

String _alertTitle({
  required String type,
  required String environment,
  required String? message,
  required Map<String, dynamic> payload,
}) {
  final tag = _envTag(environment);
  String core;
  if (type == 'network') {
    final readable = payload['network'] is Map ? (payload['network'] as Map)['readable'] : null;
    if (readable is Map && readable['title'] != null) {
      core = readable['title'].toString();
    } else {
      core = '${type.toUpperCase()} alert';
    }
  } else {
    final msg = message?.trim();
    if (msg != null && msg.isNotEmpty) {
      core = msg.length > 120 ? '${msg.substring(0, 117)}…' : msg;
    } else {
      core = '${type.toUpperCase()} alert';
    }
  }
  return '$tag $core';
}

String _alertBody({
  required String projectName,
  required String type,
  required String environment,
  required String? release,
  required String? message,
  required Map<String, dynamic> payload,
  required Set<String> categories,
}) {
  final buf = StringBuffer()
    ..writeln('Project: $projectName')
    ..writeln('Environment: $environment')
    ..writeln('Type: $type')
    ..writeln('Categories: ${categories.join(', ')}');
  if (release != null) buf.writeln('Release: $release');
  if (message != null && message.isNotEmpty) buf.writeln('Message: $message');
  final culprit = stackCulpritFromTrace(stackFromPayload(payload));
  if (culprit != null) buf.writeln('Likely source: $culprit');
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
