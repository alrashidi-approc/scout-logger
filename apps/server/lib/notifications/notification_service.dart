import 'dart:async';

import 'package:scout_models/scout_models.dart';

import '../config/server_config.dart';
import '../util/ids.dart';
import '../store/notification_store.dart';
import '../store/platform_store.dart';
import '../notifications/notification_dispatcher.dart';
import '../notifications/notification_router.dart';

class NotificationService {
  NotificationService({
    required this.store,
    required this.platformStore,
    required this.dispatcher,
    required this.config,
  });

  final NotificationStore store;
  final PlatformStore platformStore;
  final NotificationDispatcher dispatcher;
  final ServerConfig config;

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

    try {
      await dispatcher.send(job: job, config: notifications, projectName: projectName);
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
      title: 'Scout test alert',
      body: 'This is a test notification from $projectName.\nIf you received this, the channel is configured correctly.',
      eventUrl: '${config.publicUrl}${config.dashboardUrlPath}/p/$projectId/settings',
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
}
