import 'dart:async';
import 'dart:io';

import '../store/scout_store.dart';

/// Fills `events.search_text` for rows saved before that column existed.
/// Runs on the live server in small batches so deploy does not wait on it.
class SearchTextBackfill {
  SearchTextBackfill({required this.store, this.interval = const Duration(seconds: 10)});

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
      final n = await store.backfillSearchText();
      if (n < 0) return;
      if (n == 0) {
        await store.markSearchTextBackfillDone();
        _timer?.cancel();
        _timer = null;
        stdout.writeln('search text: backfill complete');
        return;
      }
      stdout.writeln('search text: indexed $n events');
    } catch (e, st) {
      stderr.writeln('search text backfill: $e\n$st');
    } finally {
      _running = false;
    }
  }
}
