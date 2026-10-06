/// Collapses a request URL to a stable route: drops scheme/host/query/fragment
/// and replaces dynamic id segments (numeric, UUID, long hex) with `:id`.
/// Feeds network issue fingerprints — changing output splits existing issues.
String normalizeRoute(String url) {
  if (url.isEmpty) return '';
  var path = Uri.tryParse(url)?.path ?? url.split('?').first.split('#').first;
  if (path.isEmpty) path = url.split('?').first.split('#').first;
  if (path.isEmpty) return '';
  return path.split('/').map((s) => isDynamicSegment(s) ? ':id' : s).join('/');
}

bool isDynamicSegment(String s) =>
    RegExp(r'^\d+$').hasMatch(s) ||
    RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(s) ||
    RegExp(r'^[0-9a-fA-F]{16,}$').hasMatch(s);
