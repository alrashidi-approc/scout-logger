// Zero-cost issue heuristics shared by the store (issue detail) and the
// notification router (alert bodies). Pure functions, no DB or external calls.

/// In-app frames of a Dart/Flutter stack trace (framework `dart:` /
/// `package:flutter*` frames dropped). [key] is stable across builds: no frame
/// number, line/column or anonymous closures — fingerprints hash it, the
/// culprit displays [raw].
List<({String raw, String key})> stackFrames(String? trace) => [
      for (final line in (trace ?? '').split('\n').map((l) => l.trim()))
        if (_isInAppFrame(line.toLowerCase())) (raw: line, key: _frameKey(line)),
    ];

bool _isInAppFrame(String lower) =>
    !lower.contains(_dartSdk) &&
    !lower.contains('package:flutter/') &&
    !lower.contains('package:flutter_') &&
    (lower.startsWith('#') || lower.contains('.dart') || lower.contains('package:'));

/// `dart:async/…` but not the `.dart:12` of an in-app frame's location.
final _dartSdk = RegExp(r'(^|[\s(])dart:');

String _frameKey(String line) => line
    .replaceFirst(RegExp(r'^#\d+\s+'), '')
    .replaceAll(RegExp(r'\.?<anonymous closure>|\.<fn>'), '')
    .replaceAll(RegExp(r'(?<=\.dart)(:\d+)+|(?<=\.dart)\s+\d+:\d+'), '')
    .replaceAll(RegExp(r'\s+'), ' ');

/// First in-app frame of a stack trace, for display.
String? stackCulpritFromTrace(String? trace) {
  final line = stackFrames(trace).firstOrNull?.raw;
  if (line == null) return null;
  return line.length > 160 ? '${line.substring(0, 157)}…' : line;
}

/// File of the top in-app frame (`package:app/src/cart.dart`) — issue rules and similar issues.
String? culpritPath(String? trace) {
  final key = stackFrames(trace).firstOrNull?.key;
  return key == null ? null : RegExp(r'(package:)?[\w.\-/]+\.dart').firstMatch(key)?.group(0);
}

/// Stack trace from a raw event payload (`stack` or `stackTrace`).
String? stackFromPayload(Map<String, dynamic> payload) =>
    payload['stack']?.toString() ?? payload['stackTrace']?.toString();

/// I5: an issue spikes when its last-hour count reaches max(this, [spikeFactor] × median hourly of the last 7 days).
const spikeMinEvents = 10;
const spikeFactor = 5;

/// An open issue unseen this long is `stale` noise.
const staleAfter = Duration(days: 14);

/// Priority (I4), spike (I5) and noise reason (I6) of one issue.
/// [hourly] counts its events per hour back from now ([0] = last hour, up to 192 h);
/// [actors], [simulatorOnly], [authOnly] describe the events in that window.
/// [release] is the project's current release and when it first appeared.
({int priority, List<String> reasons, bool spike, String? noise}) issueSignals({
  required String type,
  required String status,
  required int affectedUsers,
  required int eventCount,
  required DateTime firstSeenAt,
  required DateTime lastSeenAt,
  required List<int> hourly,
  required int actors,
  required bool simulatorOnly,
  required bool authOnly,
  ({String name, DateTime since})? release,
  required DateTime now,
}) {
  int sum(int from, int to) => [for (var h = from; h < to && h < hourly.length; h++) hourly[h]].fold(0, (a, b) => a + b);
  final week = [for (var h = 1; h <= 168; h++) h < hourly.length ? hourly[h] : 0]..sort();
  final median = (week[83] + week[84]) / 2;
  final lastHour = sum(0, 1);
  final spike = status != 'ignored' && lastHour >= (spikeFactor * median).clamp(spikeMinEvents, double.infinity);

  final noise = status == 'open' && now.difference(lastSeenAt) > staleAfter
      ? 'stale'
      : simulatorOnly
          ? 'simulator_only'
          : authOnly
              ? 'auth_class'
              : eventCount == 1 && now.difference(firstSeenAt) > const Duration(hours: 24)
                  ? 'single_occurrence'
                  : eventCount > 1 && affectedUsers <= 1 && actors == 1
                      ? 'single_user'
                      : null;

  if (status == 'ignored') return (priority: 0, reasons: const ['ignored'], spike: false, noise: noise);
  final reasons = <String>[];
  var score = 0;
  void add(int points, String reason) {
    score += points;
    reasons.add(reason);
  }

  if (affectedUsers >= 5) add(affectedUsers >= 100 ? 3 : affectedUsers >= 20 ? 2 : 1, '$affectedUsers users affected');
  final lastDay = sum(0, 24);
  final perHour = lastDay / 24;
  final baseline = sum(24, 192) / 168;
  if (lastDay >= 10 && perHour >= 3 * baseline) {
    add(2, 'rising: ${perHour.toStringAsFixed(1)}/h vs ${baseline.toStringAsFixed(1)}/h last week');
  } else if (lastDay > 0) {
    add(1, 'active in the last 24h');
  }
  if (type == 'crash') add(2, 'crash');
  if (release != null && !firstSeenAt.isBefore(release.since)) add(2, 'new in ${release.name}');
  if (spike) add(3, 'spike: $lastHour events in the last hour');
  if (noise != null) add(-2, 'noise: $noise');
  if (status == 'resolved') {
    score ~/= 2;
    reasons.add('resolved');
  }
  return (priority: score < 0 ? 0 : score, reasons: reasons, spike: spike, noise: noise);
}

/// Severity label + the reasons that drove it, from cheap issue aggregates.
({String severity, List<String> reasons}) computeIssueSeverity({
  required int eventCount,
  required int affectedUsers,
  required int hoursSinceLastSeen,
  required bool isCrash,
}) {
  final reasons = <String>[];
  var score = 0;
  if (eventCount >= 100) {
    score += 2;
    reasons.add('$eventCount events');
  } else if (eventCount >= 20) {
    score += 1;
  }
  if (affectedUsers >= 20) {
    score += 2;
    reasons.add('$affectedUsers users affected');
  } else if (affectedUsers >= 5) {
    score += 1;
  }
  if (hoursSinceLastSeen <= 1) {
    score += 1;
    reasons.add('active in the last hour');
  } else if (hoursSinceLastSeen >= 168) {
    score -= 1;
  }
  if (isCrash) {
    score += 1;
    reasons.add('crash');
  }
  final severity = score >= 4
      ? 'high'
      : score >= 2
          ? 'medium'
          : 'low';
  return (severity: severity, reasons: reasons);
}
