import 'dart:async';

import 'package:scout_models/scout_models.dart';

import '../config/server_config.dart';
import '../store/scout_store.dart';
import '../util/dashboard_links.dart';
import '../util/ids.dart';
import '../store/notification_store.dart';
import '../store/platform_store.dart';
import '../notifications/notification_categories.dart';
import '../notifications/notification_dispatcher.dart';
import '../notifications/notification_group.dart';
import '../notifications/notification_router.dart';
import '../notifications/notification_share.dart';

class _PendingDelivery {
  _PendingDelivery({
    required this.projectId,
    required this.eventId,
    required this.issueId,
    required this.job,
    required this.notifications,
    required this.projectName,
  });

  final String projectId;
  final String eventId;
  final String? issueId;
  final NotificationJob job;
  final ProjectNotificationConfig notifications;
  final String projectName;
}

class _NotificationBatch {
  _NotificationBatch({required this.flushAt, required this.items});

  final DateTime flushAt;
  final List<_PendingDelivery> items;
}

class NotificationService {
  NotificationService({
    required this.store,
    required this.platformStore,
    required this.dispatcher,
    required this.config,
    this.scout,
  });

  final NotificationStore store;
  final PlatformStore platformStore;
  final NotificationDispatcher dispatcher;
  final ServerConfig config;
  ScoutStore? scout;

  final _batches = <String, _NotificationBatch>{};
  final _batchTimers = <String, Timer>{};

  Future<void> onEventIngested({
    required String projectId,
    required String eventId,
    required String? issueId,
    required String type,
    required String environment,
    required String? message,
    required Map<String, dynamic> payload,
    required String? fingerprint,
    bool regression = false,
    required ProjectNotificationConfig notifications,
    required PlatformNotificationPolicy platform,
  }) async {
    if (!notifications.enabled) return;
    // Auto-alerts only for release/production builds — never debug/staging/dev.
    if (!isReleaseNotificationEnvironment(environment)) return;

    final projectName = await store.projectName(projectId) ?? projectId;
    final jobs = routeNotifications(
      config: notifications,
      platform: platform,
      projectId: projectId,
      projectName: projectName,
      eventId: eventId,
      type: type,
      environment: environment,
      message: message,
      payload: payload,
      fingerprint: fingerprint,
      issueId: issueId,
      dashboardBaseUrl: '${config.publicUrl}${config.dashboardUrlPath}',
    );
    if (jobs.isEmpty) return;

    for (final job in jobs) {
      // Await so sequential ingest in a batch cannot race past dedup.
      await _deliver(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        job: regression ? job.asRegression() : job,
        notifications: notifications,
        projectName: projectName,
        regression: regression,
      );
    }
  }

  Future<void> _deliver({
    required String projectId,
    required String eventId,
    required String? issueId,
    required NotificationJob job,
    required ProjectNotificationConfig notifications,
    required String projectName,
    bool regression = false,
  }) async {
    // Emergencies (crash, regression, …) always alert and bypass the dedup window.
    final bypassNoise = regression || job.isEmergency;
    final dup = !bypassNoise &&
        await store.recentlyDelivered(
          projectId: projectId,
          dedupKey: job.dedupKey,
          channel: job.channel,
          withinMinutes: notifications.dedupMinutes,
        );
    if (dup) {
      await store.logDelivery(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        dedupKey: job.dedupKey,
        category: job.category,
        channel: job.channel,
        status: 'skipped_dedup',
        urgency: job.urgency,
      );
      return;
    }

    final cap = notifications.maxAlertsPerHour;
    if (cap > 0 && !bypassNoise && await store.sentCountSince(projectId, minutes: 60) >= cap) {
      await store.logDelivery(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        dedupKey: job.dedupKey,
        category: job.category,
        channel: job.channel,
        status: 'rate_limited',
        urgency: job.urgency,
      );
      return;
    }

    final groupMinutes = notifications.groupMinutes;
    // Network noise: always batch at least briefly unless crash emergency.
    final effectiveGroup = (!bypassNoise && job.category.startsWith('network') && groupMinutes == 0)
        ? 2
        : groupMinutes;
    final canBatch = !bypassNoise && job.category != kShareNotifyCategory && effectiveGroup > 0;
    if (canBatch) {
      _enqueueBatch(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId ?? job.issueId,
        job: job,
        notifications: notifications,
        projectName: projectName,
        groupMinutes: effectiveGroup,
      );
      return;
    }

    // Claim the slot before the HTTP send so concurrent requests cannot double-page.
    if (!bypassNoise) {
      await store.logDelivery(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        dedupKey: job.dedupKey,
        category: job.category,
        channel: job.channel,
        status: 'pending',
        urgency: job.urgency,
      );
    }

    await _sendNow(
      projectId: projectId,
      eventId: eventId,
      issueId: issueId,
      job: job,
      notifications: notifications,
      projectName: projectName,
    );
  }

  void _enqueueBatch({
    required String projectId,
    required String eventId,
    required String? issueId,
    required NotificationJob job,
    required ProjectNotificationConfig notifications,
    required String projectName,
    required int groupMinutes,
  }) {
    final groupKey = issueId ?? job.dedupKey;
    final batchKey = '$projectId:${job.channel}:$groupKey';
    final item = _PendingDelivery(
      projectId: projectId,
      eventId: eventId,
      issueId: issueId,
      job: job,
      notifications: notifications,
      projectName: projectName,
    );

    final existing = _batches[batchKey];
    if (existing != null) {
      existing.items.add(item);
      unawaited(store.logDelivery(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        dedupKey: job.dedupKey,
        category: job.category,
        channel: job.channel,
        status: 'batched',
        urgency: job.urgency,
      ));
      return;
    }

    final flushAt = DateTime.now().toUtc().add(Duration(minutes: groupMinutes));
    _batches[batchKey] = _NotificationBatch(flushAt: flushAt, items: [item]);
    _batchTimers[batchKey]?.cancel();
    _batchTimers[batchKey] = Timer(Duration(minutes: groupMinutes), () {
      unawaited(_flushBatch(batchKey));
    });
  }

  Future<void> _flushBatch(String batchKey) async {
    _batchTimers.remove(batchKey)?.cancel();
    final batch = _batches.remove(batchKey);
    if (batch == null || batch.items.isEmpty) return;

    final first = batch.items.first;
    final jobs = <NotificationJob>[];
    for (final item in batch.items) {
      final shareUrl = await _shareEventUrl(item.projectId, item.eventId, item.job.eventUrl);
      jobs.add(item.job.copyWith(eventUrl: shareUrl));
    }

    final outbound = groupedNotificationJob(jobs: jobs, groupMinutes: first.notifications.groupMinutes);
    final dup = await store.recentlyDelivered(
      projectId: first.projectId,
      dedupKey: outbound.dedupKey,
      channel: outbound.channel,
      withinMinutes: first.notifications.dedupMinutes,
    );
    if (dup) {
      for (final item in batch.items) {
        await store.logDelivery(
          projectId: item.projectId,
          eventId: item.eventId,
          issueId: item.issueId,
          dedupKey: item.job.dedupKey,
          category: item.job.category,
          channel: item.job.channel,
          status: 'skipped_dedup',
          urgency: item.job.urgency,
        );
      }
      return;
    }

    final last = batch.items.last;
    final releases = batch.items.map((i) => i.job.release).whereType<String>().toSet();
    var toSend = outbound;
    if (batch.items.length > 1 || releases.length > 1) {
      final extra = StringBuffer();
      if (batch.items.length > 1) {
        extra.writeln('Seen ${batch.items.length}× in this group window.');
      }
      if (releases.length > 1) {
        extra.writeln('Releases: ${releases.join(', ')}');
      }
      toSend = outbound.copyWith(body: '${outbound.body}\n${extra.toString().trim()}');
    }
    try {
      await dispatcher.send(job: toSend, config: first.notifications, projectName: first.projectName);
      await store.logDelivery(
        projectId: first.projectId,
        eventId: last.eventId,
        issueId: last.issueId,
        dedupKey: outbound.dedupKey,
        category: outbound.category,
        channel: outbound.channel,
        status: 'sent',
        urgency: outbound.urgency,
      );
    } catch (e) {
      await store.logDelivery(
        projectId: first.projectId,
        eventId: last.eventId,
        issueId: last.issueId,
        dedupKey: outbound.dedupKey,
        category: outbound.category,
        channel: outbound.channel,
        status: 'failed',
        urgency: outbound.urgency,
        errorMessage: '$e',
      );
    }
  }

  Future<void> _sendNow({
    required String projectId,
    required String eventId,
    required String? issueId,
    required NotificationJob job,
    required ProjectNotificationConfig notifications,
    required String projectName,
  }) async {
    try {
      final shareUrl = await _shareEventUrl(projectId, eventId, job.eventUrl);
      final outbound = job.copyWith(eventUrl: shareUrl);
      await dispatcher.send(job: outbound, config: notifications, projectName: projectName);
      await store.logDelivery(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        dedupKey: job.dedupKey,
        category: job.category,
        channel: job.channel,
        status: 'sent',
        urgency: job.urgency,
      );
    } catch (e) {
      await store.logDelivery(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        dedupKey: job.dedupKey,
        category: job.category,
        channel: job.channel,
        status: 'failed',
        urgency: job.urgency,
        errorMessage: '$e',
      );
    }
  }

  Future<void> onUptimeDown({
    required String projectId,
    required String projectName,
    required String url,
    required String detail,
    required int? latencyMs,
    required ProjectNotificationConfig notifications,
    required PlatformNotificationPolicy platform,
  }) async {
    if (!notifications.enabled || !notifications.healthCheckNotify) return;

    final eventUrl = '${config.publicUrl}${config.dashboardUrlPath}/p/$projectId/health-check';
    final dedupKey = 'uptime-${Uri.encodeComponent(url)}';
    final title = '🚨 Server unreachable — $projectName';
    final body = StringBuffer()
      ..writeln('Project: $projectName')
      ..writeln('URL: $url')
      ..writeln('Detail: $detail');
    if (latencyMs != null) body.writeln('Latency: ${latencyMs}ms');
    body.writeln(
      'Confirmed after retries (${kUptimeConfirmRetry1Minutes}m + ${kUptimeConfirmRetry2Minutes}m) — '
      'Scout light uptime check (every ${kUptimeMonitorIntervalMinutes}m), not the full health script.',
    );

    for (final channel in readyNotificationChannels(config: notifications, platform: platform)) {
      // Soft dedup so a flapping host does not page every tick while still down.
      if (await store.recentlyDelivered(
        projectId: projectId,
        dedupKey: dedupKey,
        channel: channel,
        withinMinutes: kUptimeMonitorIntervalMinutes * 2,
      )) {
        continue;
      }
      final job = NotificationJob(
        channel: channel,
        category: 'uptime',
        dedupKey: dedupKey,
        title: title,
        body: body.toString().trim(),
        eventUrl: eventUrl,
        urgency: 'emergency',
      );
      final eventId = 'uptime-${newId()}';
      try {
        await dispatcher.send(job: job, config: notifications, projectName: projectName);
        await store.logDelivery(
          projectId: projectId,
          eventId: eventId,
          issueId: null,
          dedupKey: dedupKey,
          category: job.category,
          channel: channel,
          status: 'sent',
          urgency: 'emergency',
        );
      } catch (e) {
        await store.logDelivery(
          projectId: projectId,
          eventId: eventId,
          issueId: null,
          dedupKey: dedupKey,
          category: job.category,
          channel: channel,
          status: 'failed',
          urgency: 'emergency',
          errorMessage: '$e',
        );
      }
    }
  }

  Future<void> onHealthCheckFinished({
    required String projectId,
    required String runId,
    required String status,
    required Map<String, dynamic>? report,
    required ProjectNotificationConfig notifications,
    required PlatformNotificationPolicy platform,
  }) async {
    if (!notifications.enabled || !notifications.healthCheckNotify) return;
    if (!healthCheckNeedsAlert(status: status, report: report)) return;

    final projectName = await store.projectName(projectId) ?? projectId;
    final verdict = report?['verdict']?.toString() ?? status;
    final summary = report?['summary']?.toString() ?? 'Health check $status';
    final eventUrl = '${config.publicUrl}${config.dashboardUrlPath}/p/$projectId/health-check';
    final dedupKey = 'health-check-$runId';
    final title = '🚨 [$verdict] Health check — $projectName';
    final body = StringBuffer()
      ..writeln('Project: $projectName')
      ..writeln('Status: $status')
      ..writeln('Verdict: $verdict')
      ..writeln('Summary: $summary')
      ..writeln('Run: $runId');

    for (final channel in readyNotificationChannels(config: notifications, platform: platform)) {
      final job = NotificationJob(
        channel: channel,
        category: 'health_check',
        dedupKey: dedupKey,
        title: title,
        body: body.toString().trim(),
        eventUrl: eventUrl,
        urgency: 'emergency',
      );
      try {
        await dispatcher.send(job: job, config: notifications, projectName: projectName);
        await store.logDelivery(
          projectId: projectId,
          eventId: runId,
          issueId: null,
          dedupKey: dedupKey,
          category: job.category,
          channel: channel,
          status: 'sent',
          urgency: 'emergency',
        );
      } catch (e) {
        await store.logDelivery(
          projectId: projectId,
          eventId: runId,
          issueId: null,
          dedupKey: dedupKey,
          category: job.category,
          channel: channel,
          status: 'failed',
          urgency: 'emergency',
          errorMessage: '$e',
        );
      }
    }
  }

  Future<void> sendTest({
    required String projectId,
    required String channel,
    required ProjectNotificationConfig notifications,
    required PlatformNotificationPolicy platform,
  }) async {
    if (!platform.channelAllowed(channel)) {
      throw ArgumentError('This channel is disabled by the platform administrator');
    }
    final projectName = await store.projectName(projectId) ?? projectId;
    final eventId = 'test-${newId()}';
    final job = NotificationJob(
      channel: channel,
      category: 'error',
      dedupKey: 'test-$eventId',
      title: '[production] Scout test alert',
      body: 'This is a test notification from $projectName.\nEnvironment: production\nIf you received this, the channel is configured correctly.',
      eventUrl: '${config.publicUrl}${config.dashboardUrlPath}/p/$projectId/settings',
      environment: 'production',
    );
    await dispatcher.send(job: job, config: notifications, projectName: projectName);
    await store.logDelivery(
      projectId: projectId,
      eventId: eventId,
      issueId: null,
      dedupKey: job.dedupKey,
      category: job.category,
      channel: job.channel,
      status: 'sent',
    );
  }

  Future<String> _shareEventUrl(String projectId, String eventId, String fallback) async {
    final s = scout;
    if (s == null) return fallback;
    final share = await s.createShareToken(
      projectId: projectId,
      resourceType: 'event',
      resourceId: eventId,
      expiresInDays: 7,
    );
    if (share == null) return fallback;
    return dashboardShareUrl(config, share['token'] as String);
  }

  Future<Map<String, dynamic>> sendShare({
    required String projectId,
    required String resourceType,
    required String resourceId,
    required List<String> channels,
    required ProjectNotificationConfig notifications,
    required PlatformNotificationPolicy platform,
    String? sentByUserId,
  }) async {
    final rid = resourceId;
    if (!{'issue', 'event'}.contains(resourceType)) {
      throw ArgumentError('resourceType must be issue or event');
    }

    final scoutStore = scout;
    if (scoutStore == null) throw StateError('Scout store not configured');

    final ready = readyNotificationChannels(config: notifications, platform: platform).toSet();
    final picked = channels.map((c) => c.trim().toLowerCase()).where(ready.contains).toSet().toList();
    if (picked.isEmpty) throw ArgumentError('No configured notification channels selected');

    final projectName = await store.projectName(projectId) ?? projectId;
    late final String type;
    late final String environment;
    late final String summary;
    late final String body;
    late final String? issueId;
    late final String logEventId;

    if (resourceType == 'issue') {
      final issue = await scoutStore.getIssue(projectId, rid);
      if (issue == null) throw ArgumentError('Issue not found');
      type = issue['type'] as String? ?? 'error';
      environment = 'all';
      summary = issue['title'] as String? ?? 'Issue';
      issueId = rid;
      logEventId = 'share-${newId()}';
      body = shareIssueBody(projectName: projectName, issue: issue);
    } else {
      final event = await scoutStore.getEvent(projectId, rid);
      if (event == null) throw ArgumentError('Event not found');
      type = event['type'] as String? ?? 'error';
      environment = event['environment'] as String? ?? 'unknown';
      final msg = event['message']?.toString().trim();
      summary = (msg != null && msg.isNotEmpty) ? msg : '${type.toUpperCase()} event';
      issueId = event['issueId'] as String?;
      logEventId = rid;
      body = shareEventBody(projectName: projectName, event: event);
    }

    final share = await scoutStore.createShareToken(
      projectId: projectId,
      resourceType: resourceType,
      resourceId: rid,
      createdBy: sentByUserId,
      expiresInDays: 7,
    );
    if (share == null) throw ArgumentError('Resource not found');

    final shareUrl = dashboardShareUrl(config, share['token'] as String);
    final title = shareNotifyTitle(type: type, environment: environment, summary: summary);
    final fullBody = '$body\n\nOpen: $shareUrl';

    final sent = <String>[];
    final failed = <Map<String, String>>[];

    for (final channel in picked) {
      final dedupKey = 'share-manual-${newId()}';
      final job = NotificationJob(
        channel: channel,
        category: kShareNotifyCategory,
        dedupKey: dedupKey,
        title: title,
        body: fullBody,
        eventUrl: shareUrl,
        environment: environment,
        issueId: issueId,
      );
      try {
        await dispatcher.send(job: job, config: notifications, projectName: projectName);
        await store.logDelivery(
          projectId: projectId,
          eventId: logEventId,
          issueId: issueId,
          dedupKey: dedupKey,
          category: kShareNotifyCategory,
          channel: channel,
          status: 'sent',
        );
        sent.add(channel);
      } catch (e) {
        await store.logDelivery(
          projectId: projectId,
          eventId: logEventId,
          issueId: issueId,
          dedupKey: dedupKey,
          category: kShareNotifyCategory,
          channel: channel,
          status: 'failed',
          errorMessage: '$e',
        );
        failed.add({'channel': channel, 'error': '$e'});
      }
    }

    if (sent.isEmpty) {
      throw ArgumentError(failed.first['error'] ?? 'Delivery failed');
    }

    return {'sent': sent, 'failed': failed, 'shareUrl': shareUrl};
  }
}

bool healthCheckNeedsAlert({required String status, required Map<String, dynamic>? report}) {
  if (status == 'timeout' || status == 'failed') return true;
  final verdict = report?['verdict']?.toString().toLowerCase();
  return verdict == 'unhealthy';
}
