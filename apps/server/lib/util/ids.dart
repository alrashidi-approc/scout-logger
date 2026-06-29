import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

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

String eventFingerprint(String type, Map<String, dynamic> payload) {
  final network = payload['network'] is Map ? Map<String, dynamic>.from(payload['network'] as Map) : <String, dynamic>{};
  if (type == 'network') {
    // Group by endpoint only: same method + route, ignoring query string,
    // request body and dynamic path ids. A 404 and a 500 on the same route
    // roll into one issue so every occurrence is visible together.
    final method = (network['method']?.toString() ?? 'GET').toUpperCase();
    final url = network['url']?.toString() ?? payload['url']?.toString() ?? payload['path']?.toString() ?? '';
    return sha256.convert(utf8.encode('network|$method|${normalizeRoute(url)}')).toString();
  }
  final category = payload['category']?.toString() ?? '';
  final message = payload['message']?.toString() ?? '';
  final stack = payload['stack']?.toString() ?? payload['stackTrace']?.toString() ?? '';
  final frame = stack.split('\n').where((l) => l.trim().isNotEmpty).firstOrNull ?? '';
  return sha256.convert(utf8.encode('$type|$category|$message|$frame')).toString();
}

/// Collapses a request URL to a stable route: drops scheme/host/query/fragment
/// and replaces dynamic id segments (numeric, UUID, long hex) with `:id`.
String normalizeRoute(String url) {
  if (url.isEmpty) return '';
  var path = Uri.tryParse(url)?.path ?? url.split('?').first.split('#').first;
  if (path.isEmpty) path = url.split('?').first.split('#').first;
  if (path.isEmpty) return '';
  return path.split('/').map((s) => _isDynamicSegment(s) ? ':id' : s).join('/');
}

bool _isDynamicSegment(String s) =>
    RegExp(r'^\d+$').hasMatch(s) ||
    RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(s) ||
    RegExp(r'^[0-9a-fA-F]{16,}$').hasMatch(s);

String eventTitle(String type, Map<String, dynamic> payload) {
  final overview = payload['overview'] is Map ? Map<String, dynamic>.from(payload['overview'] as Map) : <String, dynamic>{};
  final overviewTitle = overview['title']?.toString();
  if (overviewTitle != null && overviewTitle.isNotEmpty) return _clip(overviewTitle);

  final message = payload['message']?.toString();
  if (message != null && message.isNotEmpty) return _clip(message);
  if (type == 'network') {
    final network = payload['network'] is Map ? Map<String, dynamic>.from(payload['network'] as Map) : payload;
    final method = network['method'] ?? 'GET';
    final url = (network['url'] ?? network['path'] ?? '/').toString();
    return '$method ${normalizeRoute(url)}';
  }
  final category = payload['category']?.toString();
  if (category != null && category.isNotEmpty) return '$category · $type';
  return type;
}

String _clip(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

String? releaseFromPayload(Map<String, dynamic> payload) {
  final raw = payload['release'];
  if (raw is Map) return raw['name']?.toString() ?? raw['version']?.toString();
  return raw?.toString();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
