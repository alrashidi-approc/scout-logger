import 'dart:async';
import 'dart:io';

import 'package:scout_models/scout_models.dart';

import '../config/server_config.dart';
import '../notifications/notification_service.dart';
import '../store/health_check_store.dart';
import '../store/notification_store.dart';
import '../store/platform_store.dart';
import 'network_probe.dart';

/// Light URL reachability checks every [kUptimeMonitorIntervalMinutes] minutes.
class UptimeMonitorScheduler {
  UptimeMonitorScheduler({
    required this.healthStore,
    required this.notificationStore,
    required this.platformStore,
    required this.notifications,
    required this.config,
    this.interval = const Duration(minutes: kUptimeMonitorIntervalMinutes),
  });

  final HealthCheckStore healthStore;
  final NotificationStore notificationStore;
  final PlatformStore platformStore;
  final NotificationService notifications;
  final ServerConfig config;
  final Duration interval;
  Timer? _timer;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => runChecks());
    unawaited(Future<void>.delayed(const Duration(seconds: 30), runChecks));
  }

  void stop() => _timer?.cancel();

  Future<void> runChecks() async {
    try {
      for (final e in await healthStore.allEnabledUptime()) {
        await checkProject(projectId: e.id, projectName: e.name, uptime: e.uptime);
      }
    } catch (e) {
      stderr.writeln('uptime monitor error: $e');
    }
  }

  /// Probe every configured URL; persist per-URL results; emergency on ok→down per URL.
  Future<UptimeMonitorConfig> checkProject({
    required String projectId,
    required String projectName,
    required UptimeMonitorConfig uptime,
  }) async {
    if (!uptime.enabled || !uptime.hasUrl) return uptime;

    final updated = <UptimeTarget>[];
    for (final target in uptime.targets) {
      if (!target.isValid) {
        updated.add(target);
        continue;
      }
      final uri = Uri.parse(target.url.trim());
      final probe = await probeHost(host: uri.host, sampleUrl: target.url.trim());
      final status = probe['status'] == 'ok' ? 'ok' : 'down';
      final previous = target.lastStatus;
      final next = target.copyWith(
        lastStatus: status,
        lastCheckedAt: DateTime.now().toUtc(),
        lastLatencyMs: (probe['latencyMs'] as num?)?.toInt(),
        lastDetail: probe['detail']?.toString() ?? probe['status']?.toString(),
      );
      updated.add(next);

      if (uptimeShouldAlert(previousStatus: previous, newStatus: status)) {
        try {
          final platform = await platformStore.getNotificationPolicy();
          final cfg = await notificationStore.getConfig(projectId);
          await notifications.onUptimeDown(
            projectId: projectId,
            projectName: projectName,
            url: next.url,
            detail: next.lastDetail ?? 'unreachable',
            latencyMs: next.lastLatencyMs,
            notifications: cfg,
            platform: platform,
          );
        } catch (e) {
          stderr.writeln('uptime alert error ($projectId ${next.url}): $e');
        }
      }
    }

    final saved = uptime.copyWith(targets: updated);
    await healthStore.saveUptime(projectId, saved);
    return saved;
  }
}
