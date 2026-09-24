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
///
/// Slack/email fire only after downtime is confirmed: first fail → wait
/// [confirmRetry1] → retry → wait [confirmRetry2] → retry → alert if still down.
class UptimeMonitorScheduler {
  UptimeMonitorScheduler({
    required this.healthStore,
    required this.notificationStore,
    required this.platformStore,
    required this.notifications,
    required this.config,
    this.interval = const Duration(minutes: kUptimeMonitorIntervalMinutes),
    this.confirmRetry1 = const Duration(minutes: kUptimeConfirmRetry1Minutes),
    this.confirmRetry2 = const Duration(minutes: kUptimeConfirmRetry2Minutes),
  });

  final HealthCheckStore healthStore;
  final NotificationStore notificationStore;
  final PlatformStore platformStore;
  final NotificationService notifications;
  final ServerConfig config;
  final Duration interval;
  final Duration confirmRetry1;
  final Duration confirmRetry2;
  Timer? _timer;

  /// In-flight confirm jobs keyed by `projectId|url`.
  final Set<String> _confirming = {};

  /// Bumped to cancel an in-flight confirm when the host recovers mid-sequence.
  final Map<String, int> _confirmGen = {};

  void start() {
    _timer ??= Timer.periodic(interval, (_) => runChecks());
    unawaited(Future<void>.delayed(const Duration(seconds: 30), runChecks));
  }

  void stop() => _timer?.cancel();

  String _confirmKey(String projectId, String url) => '$projectId|${url.trim()}';

  int _bumpConfirm(String key) => _confirmGen[key] = (_confirmGen[key] ?? 0) + 1;

  Future<void> runChecks() async {
    try {
      for (final e in await healthStore.allEnabledUptime()) {
        await checkProject(projectId: e.id, projectName: e.name, uptime: e.uptime);
      }
    } catch (e) {
      stderr.writeln('uptime monitor error: $e');
    }
  }

  /// Probe every configured URL; persist per-URL results; confirm before emergency alert.
  Future<UptimeMonitorConfig> checkProject({
    required String projectId,
    required String projectName,
    required UptimeMonitorConfig uptime,
  }) async {
    if (!uptime.enabled || !uptime.hasUrl) return uptime;

    final updated = <UptimeTarget>[];
    final toConfirm = <UptimeTarget>[];

    for (final target in uptime.targets) {
      if (!target.isValid) {
        updated.add(target);
        continue;
      }
      final key = _confirmKey(projectId, target.url);
      final probe = await _probe(target.url);
      final reachable = probe['status'] == 'ok';
      final previous = target.lastStatus;
      final inFlight = _confirming.contains(key);

      if (reachable) {
        _bumpConfirm(key);
        _confirming.remove(key);
      }

      final status = uptimeStatusAfterProbe(previousStatus: previous, reachable: reachable);
      final next = _targetFromProbe(target, probe, status: status);
      updated.add(next);

      if (uptimeShouldStartConfirm(
        previousStatus: previous,
        reachable: reachable,
        confirmInFlight: inFlight,
      )) {
        toConfirm.add(next);
      }
    }

    final saved = uptime.copyWith(targets: updated);
    await healthStore.saveUptime(projectId, saved);

    for (final t in toConfirm) {
      unawaited(_confirmDown(
        projectId: projectId,
        projectName: projectName,
        url: t.url,
      ));
    }

    return saved;
  }

  Future<Map<String, dynamic>> _probe(String url) async {
    final uri = Uri.parse(url.trim());
    return probeHost(host: uri.host, sampleUrl: url.trim());
  }

  UptimeTarget _targetFromProbe(
    UptimeTarget target,
    Map<String, dynamic> probe, {
    required String status,
  }) {
    return target.copyWith(
      lastStatus: status,
      lastCheckedAt: DateTime.now().toUtc(),
      lastLatencyMs: (probe['latencyMs'] as num?)?.toInt(),
      lastDetail: probe['detail']?.toString() ?? probe['status']?.toString(),
    );
  }

  Future<void> _persistTargetStatus({
    required String projectId,
    required String url,
    required Map<String, dynamic> probe,
    required String status,
  }) async {
    final current = await healthStore.getUptime(projectId);
    final targets = [
      for (final t in current.targets)
        if (t.url.trim() == url.trim())
          _targetFromProbe(t, probe, status: status)
        else
          t,
    ];
    await healthStore.saveUptime(projectId, current.copyWith(targets: targets));
  }

  Future<void> _confirmDown({
    required String projectId,
    required String projectName,
    required String url,
  }) async {
    final key = _confirmKey(projectId, url);
    if (!_confirming.add(key)) return;
    final gen = _bumpConfirm(key);
    try {
      await Future<void>.delayed(confirmRetry1);
      if (_confirmGen[key] != gen) return;

      var probe = await _probe(url);
      if (_confirmGen[key] != gen) return;
      if (probe['status'] == 'ok') {
        await _persistTargetStatus(projectId: projectId, url: url, probe: probe, status: 'ok');
        return;
      }
      await _persistTargetStatus(
        projectId: projectId,
        url: url,
        probe: probe,
        status: 'confirming',
      );

      await Future<void>.delayed(confirmRetry2);
      if (_confirmGen[key] != gen) return;

      probe = await _probe(url);
      if (_confirmGen[key] != gen) return;
      if (probe['status'] == 'ok') {
        await _persistTargetStatus(projectId: projectId, url: url, probe: probe, status: 'ok');
        return;
      }

      final detail = probe['detail']?.toString() ?? 'unreachable';
      final latencyMs = (probe['latencyMs'] as num?)?.toInt();
      await _persistTargetStatus(projectId: projectId, url: url, probe: probe, status: 'down');

      try {
        final platform = await platformStore.getNotificationPolicy();
        final cfg = await notificationStore.getConfig(projectId);
        await notifications.onUptimeDown(
          projectId: projectId,
          projectName: projectName,
          url: url,
          detail: detail,
          latencyMs: latencyMs,
          notifications: cfg,
          platform: platform,
        );
      } catch (e) {
        stderr.writeln('uptime alert error ($projectId $url): $e');
      }
    } catch (e) {
      stderr.writeln('uptime confirm error ($projectId $url): $e');
    } finally {
      if (_confirmGen[key] == gen) _confirming.remove(key);
    }
  }
}
