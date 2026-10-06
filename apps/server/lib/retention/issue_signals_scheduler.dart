import 'dart:async';
import 'dart:io';

import '../store/scout_store.dart';

/// Periodic issue priority / spike / noise refresh ([ScoutStore.refreshIssueSignals]).
class IssueSignalsScheduler {
  IssueSignalsScheduler({required this.store, this.interval = const Duration(minutes: 5)});

  final ScoutStore store;
  final Duration interval;
  Timer? _timer;
  var _running = false;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => run());
    unawaited(run());
  }

  void stop() => _timer?.cancel();

  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      await store.refreshIssueSignals();
    } catch (e, st) {
      stderr.writeln('issue signals error: $e\n$st');
    } finally {
      _running = false;
    }
  }
}
