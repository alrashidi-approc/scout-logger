import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:scout_models/scout_models.dart';

import '../config/server_config.dart';
import '../reports/report_service.dart';
import '../store/notification_store.dart';
import '../store/platform_store.dart';
import '../store/scout_store.dart';
import '../util/dates.dart';
import '../util/ids.dart';
import 'notification_dispatcher.dart';
import 'notification_router.dart';

/// Periodic spike-threshold checks and scheduled digests.
class MonitorScheduler {
  MonitorScheduler({
    required this.scout,
    required this.store,
    required this.platformStore,
    required this.dispatcher,
    required this.reports,
    required this.config,
    this.interval = const Duration(minutes: 5),
  });

  final ScoutStore scout;
  final NotificationStore store;
  final PlatformStore platformStore;
  final NotificationDispatcher dispatcher;
  final ReportService reports;
  final ServerConfig config;
  final Duration interval;
  Timer? _timer;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => runChecks());
  }

  void stop() => _timer?.cancel();

  String get _dashboard => '${config.publicUrl}${config.dashboardUrlPath}';

  Future<void> runChecks() async {
    try {
      final platform = await platformStore.getNotificationPolicy();
      final now = DateTime.now().toUtc();
      for (final e in await store.allEnabledConfigs()) {
        await _checkThresholds(e.id, e.name, e.config, platform);
        await _maybeDigest(e.id, e.name, e.config, platform, now);
      }
    } catch (e) {
      stderr.writeln('monitor scheduler error: $e');
    }
  }

  Future<void> _checkThresholds(
    String projectId,
    String name,
    ProjectNotificationConfig cfg,
    PlatformNotificationPolicy platform,
  ) async {
    final t = cfg.threshold;
    if (!t.enabled || (t.errorCount <= 0 && t.crashCount <= 0)) return;

    final fired = <(String, String)>[]; // (metric, message)
    if (t.isAnomaly) {
      final w = await scout.windowedCounts(projectId, windowMinutes: t.windowMinutes);
      _anomaly('error', w.errors, t, fired);
      _anomaly('crash', w.crashes, t, fired);
    } else {
      final counts = await scout.incidentCounts(projectId, minutes: t.windowMinutes);
      if (t.errorCount > 0 && counts.errors >= t.errorCount) {
        fired.add(('error', '${counts.errors} errors in the last ${t.windowMinutes} min (threshold ${t.errorCount})'));
      }
      if (t.crashCount > 0 && counts.crashes >= t.crashCount) {
        fired.add(('crash', '${counts.crashes} crashes in the last ${t.windowMinutes} min (threshold ${t.crashCount})'));
      }
    }
    if (fired.isEmpty) return;

    for (final (metric, summary) in fired) {
      final job = NotificationJob(
        channel: '',
        category: metric,
        dedupKey: 'threshold-$metric',
        title: '📈 $name: $metric spike',
        body: 'Project: $name\n$summary',
        eventUrl: '$_dashboard/p/$projectId/issues',
      );
      await _fanOut(projectId, name, cfg, platform, t.channels, job, dedupMinutes: t.windowMinutes);
    }
  }

  void _anomaly(String metric, List<int> counts, ThresholdConfig t, List<(String, String)> fired) {
    final floor = metric == 'error' ? t.errorCount : t.crashCount;
    if (floor <= 0 || counts.length < 4) return;
    final current = counts.first;
    if (current < floor) return;

    final history = counts.sublist(1);
    final mean = history.reduce((a, b) => a + b) / history.length;
    final variance = history.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) / history.length;
    final stddev = variance <= 0 ? 0.0 : math.sqrt(variance);
    final limit = stddev == 0 ? mean : mean + t.sensitivity * stddev;

    if (current > limit) {
      final baseline = mean.toStringAsFixed(1);
      fired.add((
        metric,
        '$current ${metric}s in the last ${t.windowMinutes} min — '
            '${t.sensitivity.toStringAsFixed(0)}σ spike above baseline (~$baseline/window).'
      ));
    }
  }

  Future<void> _maybeDigest(
    String projectId,
    String name,
    ProjectNotificationConfig cfg,
    PlatformNotificationPolicy platform,
    DateTime now,
  ) async {
    final d = cfg.digest;
    if (!d.enabled || now.hour != d.hourUtc) return;
    if (d.frequency == 'weekly' && now.weekday != DateTime.monday) return;

    final dedupKey = 'digest-${d.frequency}-${now.toIso8601String().substring(0, 10)}';
    final report = await reports.build(
      ReportType.executiveSummary,
      projectId,
      TimeWindow.lastDays(d.frequency == 'weekly' ? 7 : 1),
    );

    final job = NotificationJob(
      channel: '',
      category: 'error',
      dedupKey: dedupKey,
      title: '🗞 ${d.frequency == 'weekly' ? 'Weekly' : 'Daily'} digest — $name',
      body: ReportService.toPlainText(report),
      eventUrl: '$_dashboard/p/$projectId/reports',
    );
    await _fanOut(projectId, name, cfg, platform, [d.channel], job, dedupMinutes: 60 * 23);
  }

  Future<void> _fanOut(
    String projectId,
    String name,
    ProjectNotificationConfig cfg,
    PlatformNotificationPolicy platform,
    List<String> channels,
    NotificationJob job, {
    required int dedupMinutes,
  }) async {
    for (final channel in channels.toSet()) {
      if (!platform.channelAllowed(channel) || !channelReady(cfg, channel)) continue;
      if (await store.recentlyDelivered(
        projectId: projectId,
        dedupKey: job.dedupKey,
        channel: channel,
        withinMinutes: dedupMinutes,
      )) {
        continue;
      }
      final eventId = '${job.dedupKey}-${newId()}';
      try {
        await dispatcher.send(
          job: NotificationJob(
            channel: channel,
            category: job.category,
            dedupKey: job.dedupKey,
            title: job.title,
            body: job.body,
            eventUrl: job.eventUrl,
          ),
          config: cfg,
          projectName: name,
        );
        await store.logDelivery(
          projectId: projectId,
          eventId: eventId,
          issueId: null,
          dedupKey: job.dedupKey,
          category: job.category,
          channel: channel,
          status: 'sent',
        );
      } catch (e) {
        await store.logDelivery(
          projectId: projectId,
          eventId: eventId,
          issueId: null,
          dedupKey: job.dedupKey,
          category: job.category,
          channel: channel,
          status: 'failed',
          errorMessage: '$e',
        );
      }
    }
  }
}
