/// Manual team share from the dashboard — distinct from automatic spike alerts (📈).
const kShareNotifyCategory = 'share';

/// Emoji prefix for manual shares: 🟢 marks hand-shared (not spike); severity follows type.
String shareNotifyEmoji(String type) => switch (type) {
      'crash' => '🟢 🛑🟡',
      'error' => '🟢 🛑🛑',
      _ => '🟢',
    };

String shareNotifyTitle({
  required String type,
  required String environment,
  required String summary,
}) {
  final tag = '[${environment.toLowerCase()}]';
  final core = summary.trim().isEmpty ? '${type.toUpperCase()} share' : summary.trim();
  final clipped = core.length > 120 ? '${core.substring(0, 117)}…' : core;
  return '${shareNotifyEmoji(type)} $tag $clipped';
}

String shareIssueBody({required String projectName, required Map<String, dynamic> issue}) {
  final buf = StringBuffer()
    ..writeln('Shared from Scout dashboard (manual team alert — not an automatic spike)')
    ..writeln('Project: $projectName')
    ..writeln('Type: ${issue['type']}')
    ..writeln('Issue: ${issue['title']}')
    ..writeln('Events: ${issue['eventCount']} · Logged-in users: ${issue['affectedUsers'] ?? 0}')
    ..writeln('Status: ${issue['status']}');
  if (issue['topCountry'] != null) buf.writeln('Top country: ${issue['topCountry']}');
  return buf.toString().trim();
}

String shareEventBody({required String projectName, required Map<String, dynamic> event}) {
  final buf = StringBuffer()
    ..writeln('Shared from Scout dashboard (manual team alert — not an automatic spike)')
    ..writeln('Project: $projectName')
    ..writeln('Environment: ${event['environment'] ?? 'unknown'}')
    ..writeln('Type: ${event['type']}');
  final msg = event['message']?.toString().trim();
  if (msg != null && msg.isNotEmpty) buf.writeln('Message: $msg');
  if (event['appVersion'] != null) buf.writeln('App version: ${event['appVersion']}');
  if (event['userId'] != null) buf.writeln('User: ${event['userId']}');
  if (event['country'] != null) buf.writeln('Country: ${event['country']}');
  final issue = event['issue'];
  if (issue is Map) buf.writeln('Issue: ${issue['title']}');
  return buf.toString().trim();
}
