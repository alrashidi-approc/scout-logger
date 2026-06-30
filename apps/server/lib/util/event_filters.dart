/// SQL fragment — append as `AND $sqlHideSessionHeartbeat` on events queries.
/// Backed by the `is_heartbeat` generated column (see migration 014).
const sqlHideSessionHeartbeat = 'NOT is_heartbeat';

bool isSessionHeartbeat(String type, Map<String, dynamic> payload) =>
    type == 'session' && payload['action']?.toString() == 'heartbeat';

/// True failures only — backed by the `is_error` generated column (migration 014).
/// Classification logic lives in that migration; keep it in sync with [isErrorEvent].
String sqlIsErrorEvent({String alias = ''}) => '${alias.isEmpty ? '' : '$alias.'}is_error';

/// Successful outcomes — backed by the `is_success` generated column (migration 014).
String sqlIsSuccessEvent({String alias = ''}) => '${alias.isEmpty ? '' : '$alias.'}is_success';

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
  final readable = network['readable'];
  if (readable is Map && readable['operationalError'] == false) return false;
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
