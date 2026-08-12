/// Turns product `custom` / `context` maps into scannable title, chips, and lines.
Map<String, dynamic> productReadableFrom(Map<String, dynamic> fields) {
  if (fields.isEmpty) return const {};

  final lines = <String>[];
  for (final e in fields.entries) {
    if (e.value is Map || e.value is List) continue;
    final line = productHumanLine(e.key, e.value);
    if (line != null) lines.add(line);
  }
  if (lines.isEmpty) return const {};

  const priority = [
    'failure_layer',
    'step',
    'stage',
    'outcome',
    'operation',
    'attempt',
    'entrypoint',
    'platform_code',
  ];

  final chips = <Map<String, String>>[];
  for (final key in priority) {
    if (!fields.containsKey(key)) continue;
    final v = fields[key];
    if (v is Map || v is List || v == null) continue;
    chips.add({'label': humanizeProductKey(key), 'value': prettyProductScalar(v)});
  }

  return {
    'title': _title(fields, lines),
    'chips': chips,
    'lines': lines,
  };
}

String? productHumanLine(String key, dynamic value) {
  if (value == null) return null;
  if (value is Map || value is List) return null;
  final label = humanizeProductKey(key);
  if (value is bool) return '$label is ${value ? 'enabled' : 'disabled'}';
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return null;
    if (t == 'true' || t == 'false') {
      return '$label is ${t == 'true' ? 'enabled' : 'disabled'}';
    }
    return '$label: ${prettyProductScalar(t)}';
  }
  return '$label: ${prettyProductScalar(value)}';
}

String humanizeProductKey(String key) {
  final parts = _splitKey(key);
  if (parts.isEmpty) return key;
  return parts.map(_aliasOrTitle).join(' ');
}

/// Pretty-print a scalar token (`device_guard` → `Device Guard`). Keeps routes/URLs.
String prettyProductScalar(dynamic v) {
  if (v is bool) return v ? 'enabled' : 'disabled';
  final s = v.toString().trim();
  if (s.startsWith('/') || s.contains('://') || s.contains('@')) return s;
  return _prettyScalar(v);
}

String _title(Map<String, dynamic> fields, List<String> lines) {
  String? pick(String k) {
    final v = fields[k];
    if (v == null || v is Map || v is List) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : prettyProductScalar(s);
  }

  final layer = pick('failure_layer');
  final step = pick('step') ?? pick('stage');
  final outcome = pick('outcome');
  final operation = pick('operation');
  final attempt = pick('attempt');

  final bits = <String>[
    if (layer != null) layer,
    if (step != null) 'at $step',
    if (outcome != null) outcome,
    if (attempt != null && outcome == null) 'attempt $attempt',
  ];
  if (bits.isNotEmpty) return bits.join(' · ');
  if (operation != null) return operation;
  return lines.first;
}

String _prettyScalar(dynamic v) {
  if (v is bool) return v ? 'enabled' : 'disabled';
  final s = v.toString().trim();
  if (s.contains(' ')) return s;
  if (s.contains('_') || s.contains('-')) {
    return s.split(RegExp(r'[_\-]+')).where((p) => p.isNotEmpty).map(_aliasOrTitle).join(' ');
  }
  if (RegExp(r'^[a-z][a-z0-9]*$').hasMatch(s)) return _aliasOrTitle(s);
  return s;
}

List<String> _splitKey(String key) {
  final out = <String>[];
  for (final chunk in key.split(RegExp(r'[_\-\s]+'))) {
    if (chunk.isEmpty) continue;
    final buf = StringBuffer();
    for (var i = 0; i < chunk.length; i++) {
      final c = chunk[i];
      final isUpper = c.toUpperCase() == c && c.toLowerCase() != c;
      if (isUpper && buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
      buf.write(c);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
  }
  return out;
}

String _aliasOrTitle(String part) {
  final lower = part.toLowerCase();
  const aliases = {
    'sec': 'Security',
    'hw': 'Hardware',
    'vpn': 'VPN',
    'auth': 'Auth',
    'id': 'ID',
    'url': 'URL',
    'api': 'API',
    'os': 'OS',
    'ip': 'IP',
    'uid': 'User ID',
    'uuid': 'UUID',
    'json': 'JSON',
    'http': 'HTTP',
    'https': 'HTTPS',
    'ssl': 'SSL',
    'tls': 'TLS',
    'db': 'DB',
    'ui': 'UI',
    'ux': 'UX',
  };
  final alias = aliases[lower];
  if (alias != null) return alias;
  if (part.length <= 3 && part.toUpperCase() == part) return part;
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}
