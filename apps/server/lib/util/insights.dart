// Zero-cost issue heuristics shared by the store (issue detail) and the
// notification router (alert bodies). Pure functions, no DB or external calls.

/// First non-framework frame from a Dart/Flutter stack trace.
String? stackCulpritFromTrace(String? trace) {
  if (trace == null || trace.trim().isEmpty) return null;
  final lines = trace.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (lower.contains('dart:') || lower.contains('package:flutter/') || lower.contains('package:flutter_')) {
      continue;
    }
    if (lower.startsWith('#') || lower.contains('.dart') || lower.contains('package:')) {
      return line.length > 160 ? '${line.substring(0, 157)}…' : line;
    }
  }
  return null;
}

/// Stack trace from a raw event payload (`stack` or `stackTrace`).
String? stackFromPayload(Map<String, dynamic> payload) =>
    payload['stack']?.toString() ?? payload['stackTrace']?.toString();

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
