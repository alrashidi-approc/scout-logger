import 'package:scout_models/scout_models.dart';

import '../util/ids.dart';
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
    this.urgency = kDefaultAlertUrgency,
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

  /// normal | emergency — drives bypass of soft noise controls.
  final String urgency;

  bool get isEmergency => urgency == 'emergency';

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
        urgency: 'emergency',
      );

  NotificationJob copyWith({
    String? channel,
    String? category,
    String? dedupKey,
    String? title,
    String? body,
    String? eventUrl,
    String? environment,
    String? release,
    String? issueId,
    String? urgency,
  }) =>
      NotificationJob(
        channel: channel ?? this.channel,
        category: category ?? this.category,
        dedupKey: dedupKey ?? this.dedupKey,
        title: title ?? this.title,
        body: body ?? this.body,
        eventUrl: eventUrl ?? this.eventUrl,
        environment: environment ?? this.environment,
        release: release ?? this.release,
        issueId: issueId ?? this.issueId,
        urgency: urgency ?? this.urgency,
      );
}

/// Crash / crash-category alerts are emergencies; others default to normal.
String alertUrgencyFor({required String type, required Iterable<String> categories}) {
  if (type == 'crash' || categories.contains('crash')) return 'emergency';
  return kDefaultAlertUrgency;
}

/// Quiet/Normal drop non-alertWorthy network faults; Urgent and Custom keep selected categories.
bool shouldSkipNonAlertWorthyNetwork(ProjectNotificationConfig config) {
  final p = config.preset;
  return p == 'quiet' || p == 'normal' || p == kDefaultNotificationPreset;
}

bool _networkAlertWorthy(Map<String, dynamic> payload) {
  final network = payload['network'];
  if (network is! Map) return true;
  final n = Map<String, dynamic>.from(network);
  final readable = n['readable'];
  if (readable is Map) {
    if (readable['operationalError'] == false ||
        readable['alertWorthy'] == false ||
        readable['faultKind'] == 'expected') {
      return false;
    }
  }
  final fault = NetworkFaultInfo.fromJson(readable is Map ? readable['fault'] : null) ?? classifyNetworkFault(n);
  return fault.alertWorthy && fault.operationalError && fault.kind != 'expected';
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

  var categories = notificationCategoriesFor(type: type, payload: payload);
  if (categories.isEmpty) return const [];

  if (type == 'network' &&
      shouldSkipNonAlertWorthyNetwork(config) &&
      !_networkAlertWorthy(payload)) {
    return const [];
  }

  final urgency = alertUrgencyFor(type: type, categories: categories);
  final jobs = <NotificationJob>[];
  final seen = <String>{};
  final dedupBase = alertDedupKey(
    type: type,
    issueId: issueId,
    fingerprint: fingerprint,
    eventId: eventId,
    payload: payload,
  );
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
          urgency: urgency,
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

/// Stable key so the same network endpoint (any release / query) shares one alert window.
String alertDedupKey({
  required String type,
  required String? issueId,
  required String? fingerprint,
  required String eventId,
  required Map<String, dynamic> payload,
}) {
  if (type == 'network') {
    final n = _networkMap(payload);
    if (n != null) {
      final method = (n['method']?.toString() ?? 'GET').toUpperCase();
      final rawUrl = n['url']?.toString() ?? n['path']?.toString() ?? '';
      final route = normalizeRoute(rawUrl);
      if (route.isNotEmpty) return 'net|$method|$route';
    }
  }
  return issueId ?? fingerprint ?? eventId;
}

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

/// Path only (no query / secrets), trimmed for alert titles.
String alertPathFromUrl(String? url) {
  if (url == null || url.trim().isEmpty) return '';
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return _trimAlertText(url.trim(), 80);
  final path = uri.path.isEmpty ? '/' : uri.path;
  return _trimAlertText(path, 80);
}

String _trimAlertText(String s, int max) {
  if (s.length <= max) return s;
  return '${s.substring(0, max - 1)}…';
}

String _humanFaultLabel(NetworkFaultInfo fault, {String? errorType, String? message}) {
  final et = (errorType ?? '').toLowerCase();
  if (et.contains('receivetimeout') || et.contains('receive_timeout')) return 'Timeout (no response)';
  if (et.contains('connectiontimeout') || et.contains('connect_timeout')) return 'Connection timeout';
  if (et.contains('sendtimeout') || et.contains('send_timeout')) return 'Send timeout';
  final msg = (message ?? '').toLowerCase();
  if (msg.contains('slow')) return '${fault.label} · slow';
  return fault.label;
}

Map<String, dynamic>? _networkMap(Map<String, dynamic> payload) {
  final network = payload['network'];
  if (network is! Map) return null;
  return Map<String, dynamic>.from(network);
}

String _alertTitle({
  required String type,
  required String environment,
  required String? message,
  required Map<String, dynamic> payload,
}) {
  final tag = _envTag(environment);
  if (type == 'network') {
    final n = _networkMap(payload);
    if (n != null) {
      final method = (n['method']?.toString() ?? 'REQUEST').toUpperCase();
      final rawUrl = n['url']?.toString() ?? n['path']?.toString() ?? '';
      final path = alertPathFromUrl(rawUrl);
      final readable = n['readable'] is Map ? Map<String, dynamic>.from(n['readable'] as Map) : null;
      final fault = NetworkFaultInfo.fromJson(readable?['fault']) ?? classifyNetworkFault(n);
      final response = readable?['response'] is Map ? Map<String, dynamic>.from(readable!['response'] as Map) : null;
      final what = _humanFaultLabel(
        fault,
        errorType: n['errorType']?.toString() ?? response?['errorType']?.toString(),
        message: message,
      );
      final endpoint = path.isEmpty ? '' : ' · $method $path';
      return '$tag $what$endpoint';
    }
  }

  final msg = message?.trim();
  if (msg != null && msg.isNotEmpty) {
    return '$tag ${_trimAlertText(msg, 100)}';
  }
  return '$tag ${type.toUpperCase()} alert';
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
  final buf = StringBuffer()..writeln('$projectName · $environment${release != null ? ' · v$release' : ''}');

  if (type == 'network') {
    final n = _networkMap(payload);
    if (n != null) {
      final method = (n['method']?.toString() ?? '?').toUpperCase();
      final rawUrl = n['url']?.toString() ?? n['path']?.toString() ?? '';
      final uri = Uri.tryParse(rawUrl);
      final host = uri?.host;
      final path = alertPathFromUrl(rawUrl);
      final readable = n['readable'] is Map ? Map<String, dynamic>.from(n['readable'] as Map) : null;
      final fault = NetworkFaultInfo.fromJson(readable?['fault']) ?? classifyNetworkFault(n);
      final errorType = n['errorType']?.toString();
      final statusCode = n['statusCode'];
      final durationMs = n['durationMs'];
      final what = _humanFaultLabel(fault, errorType: errorType, message: message);

      buf.writeln('What: $what');
      if (host != null && host.isNotEmpty) buf.writeln('Host: $host');
      if (path.isNotEmpty) buf.writeln('Request: $method $path');
      if (statusCode != null) buf.writeln('HTTP: $statusCode');
      if (durationMs is num) buf.writeln('Duration: ${_fmtDuration(durationMs.toInt())}');
      if (fault.actionHint.isNotEmpty) buf.writeln(fault.actionHint);
      return buf.toString().trim();
    }
  }

  buf.writeln('Type: $type');
  if (message != null && message.isNotEmpty) buf.writeln(message);
  final culprit = stackCulpritFromTrace(stackFromPayload(payload));
  if (culprit != null) buf.writeln('Likely source: $culprit');
  // Keep categories only for non-network (network already has What/Host/Request).
  if (categories.isNotEmpty) buf.writeln('Categories: ${categories.join(', ')}');
  return buf.toString().trim();
}

String _fmtDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  final sec = ms / 1000;
  return sec >= 10 ? '${sec.round()}s' : '${sec.toStringAsFixed(1)}s';
}
