/// Dashboard-only toggle for the API hits page.
class ApiHitsConfig {
  const ApiHitsConfig({this.visible});

  static const defaultVisible = false;

  final bool? visible;

  factory ApiHitsConfig.fromJson(Map<String, dynamic>? json) => ApiHitsConfig(visible: json?['visible'] as bool?);

  ApiHitsConfig resolved() => ApiHitsConfig(visible: visible ?? defaultVisible);

  ApiHitsConfig mergePatch(Map<String, dynamic>? patch) =>
      patch != null && patch.containsKey('visible') ? ApiHitsConfig(visible: patch['visible'] == true) : this;

  Map<String, dynamic> toJson() => {'visible': visible ?? defaultVisible};
}

const _httpMethods = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS', 'REQUEST'};
final _idSegment = RegExp(r'^(\d+|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$');

/// `host/path` for grouping API hits: scheme, query and fragment dropped,
/// numeric / UUID path segments collapsed to `:id`, trailing `/` trimmed.
///
/// Must stay in sync with `sqlApiEndpointPath` on the server.
String apiEndpointPath(String url) {
  final base = url.trim().split(RegExp('[?#]')).first.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
  final segments = base.split('/');
  var path = [
    for (var i = 0; i < segments.length; i++) i > 0 && _idSegment.hasMatch(segments[i]) ? ':id' : segments[i],
  ].join('/');
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

String apiEndpointMethod(String? method) {
  final m = method?.trim().toUpperCase() ?? '';
  return m.isEmpty ? 'REQUEST' : m;
}

/// Parses a pasted URL, path, or `METHOD url` into an endpoint filter.
/// A path starting with `/` matches any host ending in that path.
({String? method, String path})? parseApiEndpointFilter(String? input) {
  var s = input?.trim() ?? '';
  String? method;
  final m = RegExp(r'^(\S+)\s+(\S.*)$').firstMatch(s);
  if (m != null && _httpMethods.contains(m[1]!.toUpperCase())) {
    method = m[1]!.toUpperCase();
    s = m[2]!;
  }
  final path = apiEndpointPath(s);
  return path.isEmpty ? null : (method: method, path: path);
}
