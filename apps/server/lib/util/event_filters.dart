/// SQL fragment — append as `AND $sqlHideSessionHeartbeat` on events queries.
const sqlHideSessionHeartbeat = '''
  NOT (type = 'session' AND COALESCE(payload->>'action', '') = 'heartbeat')
''';

bool isSessionHeartbeat(String type, Map<String, dynamic> payload) =>
    type == 'session' && payload['action']?.toString() == 'heartbeat';

/// True failures only — not info/success network (OK/NET) or HTTP 2xx without error.
String sqlIsErrorEvent({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
(
  ${p}type IN ('error', 'crash')
  OR (
    ${p}type = 'network'
    AND LOWER(COALESCE(NULLIF(${p}payload->>'level', ''), 'error')) NOT IN ('info', 'success')
    AND (
      NULLIF(${p}payload->'network'->>'error', '') IS NOT NULL
      OR NULLIF(${p}payload->'network'->>'statusCode', '') IS NULL
      OR NOT ((${p}payload->'network'->>'statusCode') ~ '^[0-9]+\$' AND (${p}payload->'network'->>'statusCode')::int < 400)
    )
  )
)''';
}

/// Successful outcomes — explicit OK level or healthy network (2xx, no transport error).
String sqlIsSuccessEvent({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
(
  LOWER(COALESCE(NULLIF(${p}payload->>'level', ''), '')) = 'success'
  OR (
    ${p}type = 'network'
    AND LOWER(COALESCE(NULLIF(${p}payload->>'level', ''), '')) IN ('info', 'success')
  )
  OR (
    ${p}type = 'network'
    AND NULLIF(${p}payload->'network'->>'error', '') IS NULL
    AND (${p}payload->'network'->>'statusCode') ~ '^[0-9]+\$'
    AND (${p}payload->'network'->>'statusCode')::int < 400
  )
)''';
}

String sqlDeviceNameExpr({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return "COALESCE(NULLIF(${p}payload->'device'->>'deviceName', ''), NULLIF(${p}payload->'device'->>'deviceModel', ''), NULLIF(${p}payload->'device'->>'model', ''))";
}

String sqlOccurredInWindow({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
(@since::timestamptz IS NULL OR ${p}occurred_at >= @since::timestamptz)
AND (@until::timestamptz IS NULL OR ${p}occurred_at < @until::timestamptz)''';
}

/// Mirrors [sqlIsErrorEvent] for unit tests and ingest-side checks.
bool isErrorEvent(String type, Map<String, dynamic> payload) {
  if (type == 'error' || type == 'crash') return true;
  if (type != 'network') return false;
  final level = (payload['level']?.toString() ?? '').toLowerCase();
  final eff = level.isEmpty ? 'error' : level;
  if (eff == 'info' || eff == 'success') return false;
  final network = payload['network'];
  if (network is! Map) return eff == 'error' || eff == 'warning';
  final err = network['error'];
  if (err != null && err.toString().isNotEmpty) return true;
  final codeStr = network['statusCode']?.toString() ?? '';
  if (codeStr.isEmpty) return true;
  final code = int.tryParse(codeStr);
  if (code == null) return true;
  return code >= 400;
}

/// Mirrors [sqlIsSuccessEvent] for unit tests.
bool isSuccessEvent(String type, Map<String, dynamic> payload) {
  final level = (payload['level']?.toString() ?? '').toLowerCase();
  if (level == 'success') return true;
  if (type != 'network') return false;
  if (level == 'info') return true;
  final network = payload['network'];
  if (network is! Map) return false;
  final err = network['error'];
  if (err != null && err.toString().isNotEmpty) return false;
  final codeStr = network['statusCode']?.toString() ?? '';
  final code = int.tryParse(codeStr);
  if (code == null) return false;
  return code < 400;
}
