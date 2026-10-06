import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:scout_models/scout_models.dart' show normalizeRoute;

import 'insights.dart';

String newId() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String slugify(String input) {
  final s = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'-+'), '-');
  return s.replaceAll(RegExp(r'^-|-$'), '');
}

String hashIngestKey(String rawKey) => sha256.convert(utf8.encode(rawKey)).toString();

String generateIngestKey() => 'sk_live_${newId()}';

String buildDsn({required String publicUrl, required String projectId, required String rawKey}) {
  final uri = Uri.parse(publicUrl.replaceAll(RegExp(r'/+$'), ''));
  return '${uri.scheme}://$rawKey@${uri.host}:${uri.port}/$projectId';
}

/// Normalized route of a network event (`/api/orders/:id`), '' without a URL.
String networkRoute(Map<String, dynamic> payload) {
  final network = payload['network'] is Map ? payload['network'] as Map : const {};
  return normalizeRoute((network['url'] ?? payload['url'] ?? payload['path'] ?? '').toString());
}

String eventFingerprint(String type, Map<String, dynamic> payload) {
  if (type == 'network') {
    // Group by endpoint only: same method + route, ignoring query string,
    // request body and dynamic path ids. A 404 and a 500 on the same route
    // roll into one issue so every occurrence is visible together.
    final network = payload['network'] is Map ? payload['network'] as Map : const {};
    final method = (network['method']?.toString() ?? 'GET').toUpperCase();
    return sha256.convert(utf8.encode('network|$method|${networkRoute(payload)}')).toString();
  }
  // v2 (errors / crashes): normalized message + top in-app frames. The version is
  // part of the stored value; v1 issues (bare hash) keep their rows and go quiet.
  final category = payload['category']?.toString() ?? '';
  final message = normalizeMessage(payload['message']?.toString() ?? '');
  final frames = stackFrames(stackFromPayload(payload)).take(3).map((f) => f.key).join('|');
  return 'v2:${sha256.convert(utf8.encode('$type|$category|$message|$frames'))}';
}

/// I11 secondary grouping: `context.failure_layer` + `platform_code` + normalized message, only
/// when the app sent either key. Feeds similar issues (I10) — never the fingerprint.
String? issueGroupHint(Map<String, dynamic> payload) {
  final context = payload['context'] is Map ? payload['context'] as Map : const {};
  final layer = context['failure_layer']?.toString().trim() ?? '';
  final code = context['platform_code']?.toString().trim() ?? '';
  if (layer.isEmpty && code.isEmpty) return null;
  return sha256.convert(utf8.encode('$layer|$code|${normalizeMessage(payload['message']?.toString() ?? '')}')).toString();
}

/// The v1 error / crash fingerprint (raw message + first stack line) — finds a v2 issue's predecessor.
String legacyFingerprint(String type, Map<String, dynamic> payload) {
  final frame = (stackFromPayload(payload) ?? '').split('\n').where((l) => l.trim().isNotEmpty).firstOrNull ?? '';
  return sha256.convert(utf8.encode('$type|${payload['category'] ?? ''}|${payload['message'] ?? ''}|$frame')).toString();
}

/// [message] with dynamic parts (URLs, emails, ids, quoted tokens, numbers)
/// replaced by placeholders, so one failure groups regardless of its values.
String normalizeMessage(String message) => message
    .replaceAll(RegExp(r'\b[a-z][a-z0-9+.-]*://\S+', caseSensitive: false), '<url>')
    .replaceAll(RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+'), '<email>')
    .replaceAll(
      RegExp(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', caseSensitive: false),
      '<id>',
    )
    .replaceAll(RegExp(r'\b(0x[0-9a-f]+|(?=[0-9a-f]*\d)[0-9a-f]{8,})\b', caseSensitive: false), '<id>')
    .replaceAll(RegExp(r'''(['"`])[^\s'"`]{1,200}\1'''), '<str>')
    .replaceAll(RegExp(r'(?<![A-Za-z_])\d+(\.\d+)?'), '<num>')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Issue title: diagnosis summary → SDK overview title → `METHOD route · faultLabel`
/// → `culpritFile: normalized message` → message → `category · type`.
String eventTitle(String type, Map<String, dynamic> payload) {
  final summary = _diagnosis(payload)['summary']?.toString().trim() ?? '';
  if (summary.isNotEmpty) return _clip(summary);

  final overview = payload['overview'] is Map ? Map<String, dynamic>.from(payload['overview'] as Map) : <String, dynamic>{};
  final overviewTitle = overview['title']?.toString();
  if (overviewTitle != null && overviewTitle.isNotEmpty) return _clip(overviewTitle);

  if (type == 'network') {
    final network = payload['network'] is Map ? Map<String, dynamic>.from(payload['network'] as Map) : payload;
    final method = network['method'] ?? 'GET';
    final url = (network['url'] ?? network['path'] ?? '/').toString();
    final readable = network['readable'] is Map ? network['readable'] as Map : const {};
    final label = readable['faultLabel']?.toString() ?? '';
    return '$method ${normalizeRoute(url)}${label.isEmpty ? '' : ' · $label'}';
  }
  final message = payload['message']?.toString() ?? '';
  final culprit = stackFrames(stackFromPayload(payload)).firstOrNull?.key;
  final file = culprit == null ? null : RegExp(r'([\w-]+\.dart)').firstMatch(culprit)?.group(1);
  if (message.isNotEmpty) return _clip(file == null ? message : '$file: ${normalizeMessage(message)}');
  final category = payload['category']?.toString();
  if (category != null && category.isNotEmpty) return '$category · $type';
  return type;
}

/// How much to trust [eventTitle]: 0 heuristic, 1–3 diagnosis confidence
/// low / medium (or unset) / high. A stored title is only replaced by an equal or higher rank.
int titleRank(Map<String, dynamic> payload) {
  final diagnosis = _diagnosis(payload);
  if ((diagnosis['summary']?.toString().trim() ?? '').isEmpty) return 0;
  return switch (diagnosis['confidence']?.toString().toLowerCase()) { 'high' => 3, 'low' => 1, _ => 2 };
}

/// Clipped `diagnosis.summary` / `likelyCause`, only when the SDK sent a summary.
({String summary, String? likelyCause})? diagnosisBrief(Map<String, dynamic> payload) {
  final d = _diagnosis(payload);
  final summary = d['summary']?.toString().trim() ?? '';
  final cause = d['likelyCause']?.toString().trim() ?? '';
  return summary.isEmpty ? null : (summary: _clip(summary), likelyCause: cause.isEmpty ? null : _clip(cause));
}

Map _diagnosis(Map<String, dynamic> payload) => payload['diagnosis'] is Map ? payload['diagnosis'] as Map : const {};

String _clip(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

/// `release` wins as sent (name before version — stored in events / releases);
/// otherwise falls back to `release.id`, then non-blank `app.version` / `app.build`.
String? releaseFromPayload(Map<String, dynamic> payload) {
  final raw = payload['release'];
  final direct = raw is Map ? raw['name'] ?? raw['version'] ?? raw['id'] : raw;
  if (direct != null) return direct.toString();
  final app = payload['app'];
  final v = app is Map ? (app['version'] ?? app['build'])?.toString().trim() : null;
  return v != null && v.isNotEmpty ? v : null;
}