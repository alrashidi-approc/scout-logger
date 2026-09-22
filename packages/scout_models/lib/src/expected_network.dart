import 'network_fault.dart';

/// Per-route rules: treat matching HTTP responses as expected business outcomes
/// (not engineering incidents). Example: POST …/empCardImageM → 404 = no image.
class ExpectedNetworkResponse {
  const ExpectedNetworkResponse({
    required this.path,
    this.method = '*',
    this.statusCodes = const [],
    this.note = '',
  });

  /// Route path (query stripped / ids normalized when matching).
  final String path;

  /// HTTP method or `*` for any.
  final String method;

  /// Matching status codes; empty = any status on this route.
  final List<int> statusCodes;

  /// Optional human note shown in readable payload / settings.
  final String note;

  factory ExpectedNetworkResponse.fromJson(Map<String, dynamic> json) {
    final codes = <int>{};
    final raw = json['statusCodes'];
    if (raw is List) {
      for (final item in raw) {
        final n = item is int ? item : int.tryParse(item.toString());
        if (n != null && n >= 100 && n <= 599) codes.add(n);
      }
    }
    var method = (json['method']?.toString() ?? '*').trim().toUpperCase();
    if (method.isEmpty) method = '*';
    return ExpectedNetworkResponse(
      path: json['path']?.toString().trim() ?? '',
      method: method,
      statusCodes: codes.toList()..sort(),
      note: json['note']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'method': method,
        'path': path,
        'statusCodes': statusCodes,
        if (note.isNotEmpty) 'note': note,
      };

  bool get isValid => normalizeExpectedNetworkPath(path).isNotEmpty;
}

List<ExpectedNetworkResponse> normalizeExpectedNetworkResponses(dynamic raw) {
  if (raw is! List || raw.isEmpty) return const [];
  final out = <ExpectedNetworkResponse>[];
  final seen = <String>{};
  for (final item in raw) {
    final ExpectedNetworkResponse rule;
    if (item is ExpectedNetworkResponse) {
      rule = item;
    } else if (item is Map) {
      rule = ExpectedNetworkResponse.fromJson(Map<String, dynamic>.from(item));
    } else {
      continue;
    }
    if (!rule.isValid) continue;
    final key = '${rule.method}|${normalizeExpectedNetworkPath(rule.path)}|${rule.statusCodes.join(',')}';
    if (!seen.add(key)) continue;
    out.add(ExpectedNetworkResponse(
      path: normalizeExpectedNetworkPath(rule.path),
      method: rule.method,
      statusCodes: rule.statusCodes,
      note: rule.note,
    ));
  }
  return out;
}

/// Same idea as server [normalizeRoute]: drop query/host and collapse id segments.
String normalizeExpectedNetworkPath(String url) {
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

ExpectedNetworkResponse? matchExpectedNetworkResponse({
  required List<ExpectedNetworkResponse> rules,
  required String? method,
  required String? url,
  required int? statusCode,
}) {
  if (rules.isEmpty) return null;
  final route = normalizeExpectedNetworkPath(url ?? '');
  if (route.isEmpty) return null;
  final m = (method ?? '*').trim().toUpperCase();
  for (final rule in rules) {
    final rulePath = normalizeExpectedNetworkPath(rule.path);
    if (rulePath.isEmpty || rulePath != route) continue;
    if (rule.method != '*' && rule.method != m) continue;
    if (rule.statusCodes.isNotEmpty) {
      if (statusCode == null || !rule.statusCodes.contains(statusCode)) continue;
    }
    return rule;
  }
  return null;
}

/// Fault forced when an expected-response rule matches.
NetworkFaultInfo expectedNetworkFaultInfo({String note = ''}) {
  final hint = note.trim().isEmpty
      ? 'Configured as an expected API response for this project — not an engineering incident.'
      : note.trim();
  return NetworkFaultInfo(
    faultClass: NetworkFaultClass.user,
    kind: 'expected',
    label: note.trim().isEmpty ? 'Expected response' : 'Expected: ${note.trim()}',
    actionHint: hint,
    alertWorthy: false,
    issueWorthy: false,
    operationalError: false,
  );
}

/// Merge [rule] into [existing] (idempotent by method+path+codes).
List<ExpectedNetworkResponse> upsertExpectedNetworkResponse(
  List<ExpectedNetworkResponse> existing,
  ExpectedNetworkResponse rule,
) {
  if (!rule.isValid) return existing;
  final normalized = ExpectedNetworkResponse(
    path: normalizeExpectedNetworkPath(rule.path),
    method: rule.method.trim().isEmpty ? '*' : rule.method.trim().toUpperCase(),
    statusCodes: List<int>.from(rule.statusCodes)..sort(),
    note: rule.note,
  );
  final key = '${normalized.method}|${normalized.path}|${normalized.statusCodes.join(',')}';
  final out = <ExpectedNetworkResponse>[];
  var replaced = false;
  for (final e in existing) {
    final ek = '${e.method}|${normalizeExpectedNetworkPath(e.path)}|${e.statusCodes.join(',')}';
    if (ek == key) {
      out.add(normalized);
      replaced = true;
    } else {
      out.add(e);
    }
  }
  if (!replaced) out.add(normalized);
  return normalizeExpectedNetworkResponses(out.map((e) => e.toJson()).toList());
}
