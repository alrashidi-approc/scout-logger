import 'dart:async';
import 'dart:io';

import '../store/scout_store.dart';

/// Nightly-style purge of expired raw events. Rollup counters are never deleted.
class RetentionScheduler {
  RetentionScheduler({required this.store, this.interval = const Duration(hours: 6)});

  final ScoutStore store;
  final Duration interval;
  Timer? _timer;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => runRetention());
    unawaited(runRetention());
  }

  void stop() => _timer?.cancel();

  Future<void> runRetention() async {
    try {
      final results = await store.runEventRetentionForAllProjects();
      final deleted = results.values.fold<int>(0, (a, b) => a + b);
      if (deleted > 0) {
        stdout.writeln('retention: deleted $deleted raw events across ${results.length} projects');
      }
    } catch (e, st) {
      stderr.writeln('retention scheduler error: $e\n$st');
    }
  }
}
