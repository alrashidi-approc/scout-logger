/// SQL fragment — append as `AND $sqlHideSessionHeartbeat` on events queries.
/// Inline expression so queries work before migration 014 columns exist.
const sqlHideSessionHeartbeat =
    "NOT (type = 'session' AND COALESCE(payload->>'action', '') = 'heartbeat')";

bool isSessionHeartbeat(String type, Map<String, dynamic> payload) =>
    type == 'session' && payload['action']?.toString() == 'heartbeat';

/// True failures only — inline expression (migration 014 adds `is_error` for indexes).
/// Keep in sync with [isErrorEvent] and 014_event_outcome_columns.sql.
String sqlIsErrorEvent({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
(
  ${p}type IN ('error', 'crash')
  OR (
    ${p}type = 'network'
    AND LOWER(COALESCE(NULLIF(${p}payload->>'level', ''), 'error')) NOT IN ('info', 'success')
    AND COALESCE(NULLIF(${p}payload->'network'->'readable'->>'operationalError', ''), 'true') <> 'false'
    AND (
      NULLIF(${p}payload->'network'->>'error', '') IS NOT NULL
      OR NULLIF(${p}payload->'network'->>'statusCode', '') IS NULL
      OR NOT ((${p}payload->'network'->>'statusCode') ~ '^[0-9]{1,9}\$' AND (${p}payload->'network'->>'statusCode')::int < 400)
    )
  )
)''';
}

/// Successful outcomes — inline expression (migration 014 adds `is_success` for indexes).
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
    AND (${p}payload->'network'->>'statusCode') ~ '^[0-9]{1,9}\$'
    AND (${p}payload->'network'->>'statusCode')::int < 400
  )
)''';
}

String sqlDeviceNameExpr({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return "COALESCE(NULLIF(${p}payload->'device'->>'deviceName', ''), NULLIF(${p}payload->'device'->>'deviceModel', ''), NULLIF(${p}payload->'device'->>'model', ''))";
}

String sqlAppVersionExpr({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return "COALESCE(NULLIF(${p}app_version, ''), NULLIF(${p}payload->'device'->>'appVersion', ''), NULLIF(${p}payload->'device'->>'version', ''))";
}

String sqlEnvironmentExpr({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return "COALESCE(NULLIF(${p}environment, ''), NULLIF(${p}payload->>'environment', ''), NULLIF(${p}payload->'release'->>'environment', ''), 'unknown')";
}

/// Optional env / version / device filters — bind @env, @ver, @device (null = ignore).
/// Each part starts with AND; do not prefix with another AND.
String sqlEventFacetFilters({
  String alias = '',
  bool applyEnvironment = true,
  bool applyAppVersion = true,
  bool applyDevice = true,
}) {
  final parts = <String>[];
  if (applyEnvironment) {
    parts.add('AND (@env::text IS NULL OR ${sqlEnvironmentExpr(alias: alias)} = @env::text)');
  }
  if (applyAppVersion) {
    parts.add('AND (@ver::text IS NULL OR ${sqlAppVersionExpr(alias: alias)} = @ver::text)');
  }
  if (applyDevice) {
    parts.add('AND (@device::text IS NULL OR ${sqlDeviceNameExpr(alias: alias)} = @device::text)');
  }
  return parts.join('\n          ');
}

bool hasEventFacetFilters({String? environment, String? appVersion, String? deviceName}) =>
    environment != null || appVersion != null || deviceName != null;

/// Bind only facet placeholders present in [sqlEventFacetFilters] for this query.
Map<String, dynamic> eventFacetParameters({
  required String projectId,
  required Map<String, dynamic> time,
  String? environment,
  String? appVersion,
  String? deviceName,
  bool applyEnvironment = true,
  bool applyAppVersion = true,
  bool applyDevice = true,
}) {
  return {
    'pid': projectId,
    ...time,
    if (applyEnvironment) 'env': environment,
    if (applyAppVersion) 'ver': appVersion,
    if (applyDevice) 'device': deviceName,
  };
}

/// Events tied to an issue row, optionally scoped to the report period and facets.
String sqlIssueEventScope({
  String alias = 'e',
  String issueIdExpr = 'issues.id',
  bool requireError = true,
  bool applyEnvironment = true,
  bool applyAppVersion = true,
  bool applyDevice = true,
}) {
  final err = requireError ? 'AND ${sqlIsErrorEvent(alias: alias)}' : '';
  return '''
$alias.project_id = @pid AND $alias.issue_id = $issueIdExpr
          $err
          AND ${sqlOccurredInWindow(alias: alias)}
          ${sqlEventFacetFilters(alias: alias, applyEnvironment: applyEnvironment, applyAppVersion: applyAppVersion, applyDevice: applyDevice)}''';
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
