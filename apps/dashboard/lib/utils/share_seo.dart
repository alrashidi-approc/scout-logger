export 'share_seo_stub.dart' if (dart.library.js_interop) 'share_seo_web.dart';

String shareSeoTitle({required String? type, Map<String, dynamic>? issue, Map<String, dynamic>? event}) {
  if (type == 'issue' && issue != null) {
    return issue['title'] as String? ?? 'Issue';
  }
  if (type == 'event' && event != null) {
    final msg = event['message'] as String?;
    if (msg != null && msg.isNotEmpty) return _truncate(msg, 80);
    final eventType = event['type'] as String? ?? 'event';
    return '${eventType[0].toUpperCase()}${eventType.substring(1)} event';
  }
  return 'Shared item';
}

String shareSeoDescription({required String? type, Map<String, dynamic>? issue, Map<String, dynamic>? event}) {
  if (type == 'issue' && issue != null) {
    final parts = <String>[
      if (issue['type'] != null) '${issue['type']}',
      if (issue['status'] != null) '${issue['status']}',
      if (issue['count'] != null) '${issue['count']} events',
      if (issue['topEnvironment'] != null) '${issue['topEnvironment']}',
    ];
    return 'Scout issue · ${parts.join(' · ')}';
  }
  if (type == 'event' && event != null) {
    final parts = <String>[
      if (event['type'] != null) '${event['type']}',
      if (event['level'] != null) '${event['level']}',
      if (event['environment'] != null) '${event['environment']}',
      if (event['appVersion'] != null) 'v${event['appVersion']}',
    ];
    final msg = event['message'] as String?;
    if (msg != null && msg.isNotEmpty) parts.add(_truncate(msg, 120));
    return 'Scout event · ${parts.join(' · ')}';
  }
  return 'Shared Scout Logger issue or event';
}

String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';
