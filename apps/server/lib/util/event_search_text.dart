import 'dart:convert';

/// Per-field cap so one response body cannot crowd out the phone or the request.
const eventSearchBodyLimit = 2000;

/// Whole document cap. The trigram index stores this, not `payload`.
const eventSearchTextLimit = 8000;

/// Text stored on `events.search_text` for advanced search.
///
/// Built at ingest (and by the backfill) so queries never cast `payload` to text.
/// Fields are separated so a query cannot match across two of them.
String eventSearchText(
  Map<String, dynamic> payload, {
  String? message,
  String? userId,
  String? sessionId,
  String? installId,
}) {
  final user = _map(payload['user']);
  final network = _map(payload['network']);
  final request = _map(network['request']);
  final response = _map(network['response']);
  final parts = [
    _clip(message ?? payload['message'], eventSearchBodyLimit),
    _clip(userId ?? user['id'] ?? user['userId'], eventSearchBodyLimit),
    _clip(sessionId ?? user['sessionId'] ?? payload['sessionId'], eventSearchBodyLimit),
    _clip(installId, eventSearchBodyLimit),
    _clip(user['phone'], eventSearchBodyLimit),
    _clip(user['email'], eventSearchBodyLimit),
    _clip(user['username'], eventSearchBodyLimit),
    _clip(user['name'], eventSearchBodyLimit),
    _clip(network['url'] ?? network['path'], eventSearchBodyLimit),
    _clip(network['method'], 32),
    _clip(network['traceId'], eventSearchBodyLimit),
    _clip(request['body'] ?? network['requestBody'] ?? network['body'], eventSearchBodyLimit),
    _clip(response['body'] ?? network['responseBody'], eventSearchBodyLimit),
    _clip(_raw(payload), eventSearchBodyLimit),
  ];
  final doc = parts.join('\u001f');
  if (doc.length <= eventSearchTextLimit) return doc;
  return doc.substring(0, eventSearchTextLimit);
}

Map<String, dynamic> _map(Object? value) => value is Map ? Map<String, dynamic>.from(value) : const {};

String _clip(Object? value, int max) {
  final text = value?.toString() ?? '';
  if (text.length <= max) return text;
  return text.substring(0, max);
}

String _raw(Map<String, dynamic> payload) {
  try {
    return jsonEncode(payload);
  } catch (_) {
    return '';
  }
}
