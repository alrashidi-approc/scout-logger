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
      unawaited(_deliver(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        job: regression ? job.asRegression() : job,
        notifications: notifications,
        projectName: projectName,
        regression: regression,
      ));
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
    // Regressions always alert and bypass the dedup window.
    final dup = !regression &&
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
      );
      return;
    }

    final cap = notifications.maxAlertsPerHour;
    if (cap > 0 && await store.sentCountSince(projectId, minutes: 60) >= cap) {
      await store.logDelivery(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        dedupKey: job.dedupKey,
        category: job.category,
        channel: job.channel,
        status: 'rate_limited',
      );
      return;
    }

    final groupMinutes = notifications.groupMinutes;
    final canBatch = !regression && job.category != kShareNotifyCategory && groupMinutes > 0;
    if (canBatch) {
      _enqueueBatch(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId ?? job.issueId,
        job: job,
        notifications: notifications,
        projectName: projectName,
        groupMinutes: groupMinutes,
      );
      return;
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
      jobs.add(NotificationJob(
        channel: item.job.channel,
        category: item.job.category,
        dedupKey: item.job.dedupKey,
        title: item.job.title,
        body: item.job.body,
        eventUrl: shareUrl,
        environment: item.job.environment,
        release: item.job.release,
        issueId: item.job.issueId,
      ));
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
        );
      }
      return;
    }

    final last = batch.items.last;
    try {
      await dispatcher.send(job: outbound, config: first.notifications, projectName: first.projectName);
      await store.logDelivery(
        projectId: first.projectId,
        eventId: last.eventId,
        issueId: last.issueId,
        dedupKey: outbound.dedupKey,
        category: outbound.category,
        channel: outbound.channel,
        status: 'sent',
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
      final outbound = NotificationJob(
        channel: job.channel,
        category: job.category,
        dedupKey: job.dedupKey,
        title: job.title,
        body: job.body,
        eventUrl: shareUrl,
        environment: job.environment,
        release: job.release,
        issueId: job.issueId,
      );
      await dispatcher.send(job: outbound, config: notifications, projectName: projectName);
      await store.logDelivery(
        projectId: projectId,
        eventId: eventId,
        issueId: issueId,
        dedupKey: job.dedupKey,
        category: job.category,
        channel: job.channel,
        status: 'sent',
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
        errorMessage: '$e',
      );
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
