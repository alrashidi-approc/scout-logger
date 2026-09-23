/// SQL fragment — append as `AND $sqlHideSessionHeartbeat` on events queries.
/// Inline expression so all screens work before/without migration 014 columns.
const sqlHideSessionHeartbeat =
    "NOT (type = 'session' AND COALESCE(payload->>'action', '') = 'heartbeat')";

bool isSessionHeartbeat(String type, Map<String, dynamic> payload) =>
    type == 'session' && payload['action']?.toString() == 'heartbeat';

/// Routine lifecycle noise — hide in Focus view; still visible in All / Grouped.
const sqlIsRoutineEvent = '''
(
  (
    type = 'session'
    AND LOWER(COALESCE(payload->>'action', '')) IN (
      'start', 'end', 'session_start', 'session_end'
    )
  )
  OR (
    type IN ('log', 'session')
    AND (
      LOWER(COALESCE(payload->>'action', '')) IN (
        'session_start', 'session_end',
        'app_background', 'app_foreground', 'app_resumed', 'app_paused',
        'app_backgrounded', 'app_foregrounded'
      )
      OR LOWER(TRIM(COALESCE(message, ''))) IN (
        'session_start', 'session_end', 'session start', 'session end',
        'app backgrounded', 'app foregrounded', 'app resumed', 'app paused'
      )
      OR LOWER(TRIM(COALESCE(message, ''))) ~
        '^(session[ _-]?(start|end)|app (backgrounded|foregrounded|resumed|paused))\$'
    )
  )
)
''';

/// Append as `AND $sqlFocusWorthyEvent` when view=focus.
const sqlFocusWorthyEvent = 'NOT $sqlIsRoutineEvent';

/// Raw events eligible for routine retention (logs, sessions, spans, success network).
/// Keeps errors, crashes, and issue-linked rows for [errorDays].
const sqlRoutineRetentionEvent = '''
(
  issue_id IS NULL
  AND NOT is_error
  AND NOT is_heartbeat
)
''';

/// Raw events eligible for error retention when errorDays > 0.
const sqlErrorRetentionEvent = '(is_error OR issue_id IS NOT NULL)';

/// Stable bucket key for Grouped events view (ephemeral API rollup).
String sqlEventGroupKey({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
CASE
  WHEN ${p}issue_id IS NOT NULL THEN 'issue|' || ${p}issue_id::text
  WHEN ${p}type = 'network' THEN
    'network|' || UPPER(COALESCE(${p}payload->'network'->>'method', 'GET')) || '|' ||
    SPLIT_PART(COALESCE(${p}payload->'network'->>'url', ${p}payload->'network'->>'path', ''), '?', 1)
  ELSE
    ${p}type || '|' || LOWER(LEFT(TRIM(BOTH FROM COALESCE(
      NULLIF(${p}payload->>'action', ''),
      NULLIF(${p}message, ''),
      ${p}type
    )), 160))
END''';
}

/// Mirror of [sqlIsRoutineEvent] for unit tests / clients.
bool isRoutineEvent(String type, Map<String, dynamic> payload, {String? message}) {
  if (isSessionHeartbeat(type, payload)) return true;
  final action = (payload['action']?.toString() ?? '').toLowerCase().trim();
  final msg = (message ?? payload['message']?.toString() ?? '').toLowerCase().trim();
  const sessionActions = {'start', 'end', 'session_start', 'session_end'};
  const lifeActions = {
    'session_start',
    'session_end',
    'app_background',
    'app_foreground',
    'app_resumed',
    'app_paused',
    'app_backgrounded',
    'app_foregrounded',
  };
  const lifeMessages = {
    'session_start',
    'session_end',
    'session start',
    'session end',
    'app backgrounded',
    'app foregrounded',
    'app resumed',
    'app paused',
  };
  if (type == 'session' && sessionActions.contains(action)) return true;
  if (type == 'log' || type == 'session') {
    if (lifeActions.contains(action) || lifeMessages.contains(msg)) return true;
    if (RegExp(r'^(session[ _-]?(start|end)|app (backgrounded|foregrounded|resumed|paused))$')
        .hasMatch(msg)) {
      return true;
    }
  }
  return false;
}

String eventGroupKey({
  required String type,
  String? issueId,
  String? message,
  Map<String, dynamic>? payload,
}) {
  final p = payload ?? const <String, dynamic>{};
  if (issueId != null && issueId.isNotEmpty) return 'issue|$issueId';
  if (type == 'network') {
    final network = p['network'] is Map ? Map<String, dynamic>.from(p['network'] as Map) : p;
    final method = (network['method']?.toString() ?? 'GET').toUpperCase();
    final url = (network['url'] ?? network['path'] ?? '').toString().split('?').first;
    return 'network|$method|$url';
  }
  final action = p['action']?.toString().trim();
  final title = (action != null && action.isNotEmpty)
      ? action
      : (message ?? p['message']?.toString() ?? type);
  final clipped = title.length > 160 ? title.substring(0, 160) : title;
  return '$type|${clipped.toLowerCase()}';
}

/// True failures only — inline expression (works without `is_error` column).
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
    AND COALESCE(NULLIF(${p}payload->'network'->'readable'->>'faultKind', ''), '') <> 'expected'
    AND (
      NULLIF(${p}payload->'network'->>'error', '') IS NOT NULL
      OR NULLIF(${p}payload->'network'->>'statusCode', '') IS NULL
      OR NOT ((${p}payload->'network'->>'statusCode') ~ '^[0-9]{1,9}\$' AND (${p}payload->'network'->>'statusCode')::int < 400)
    )
  )
)''';
}

/// Successful outcomes — inline expression (works without `is_success` column).
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

/// Prefer `1.0.2+46` when SDK sends version and build separately.
String? composeAppVersion({
  String? appVersion,
  String? buildNumber,
  String? releaseVersion,
  String? releaseBuild,
}) {
  final ver = (appVersion ?? releaseVersion)?.trim();
  if (ver == null || ver.isEmpty) return null;
  if (ver.contains('+')) return ver;
  final build = (buildNumber ?? releaseBuild)?.trim();
  if (build == null || build.isEmpty) return ver;
  return '$ver+$build';
}

String? composeAppVersionFromDevice(Map<String, dynamic> device, {Map<String, dynamic>? release}) {
  return composeAppVersion(
    appVersion: device['appVersion']?.toString(),
    buildNumber: device['buildNumber']?.toString() ?? device['build']?.toString(),
    releaseVersion: release?['version']?.toString(),
    releaseBuild: release?['buildNumber']?.toString(),
  );
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
  if (readable is Map && readable['faultKind'] == 'expected') return false;
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

/// Best-effort Content-Type from network payload (headers map or flat fields).
String sqlNetworkContentType({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
LOWER(SPLIT_PART(TRIM(BOTH FROM COALESCE(
  NULLIF(${p}payload->'network'->'response'->'headers'->>'content-type', ''),
  NULLIF(${p}payload->'network'->'response'->'headers'->>'Content-Type', ''),
  NULLIF(${p}payload->'network'->'response'->>'contentType', ''),
  NULLIF(${p}payload->'network'->'response'->>'content-type', ''),
  NULLIF(${p}payload->'network'->>'contentType', ''),
  NULLIF(${p}payload->'network'->>'content-type', ''),
  ''
)), ';', 1))''';
}

String sqlNetworkResponseBody({String alias = ''}) {
  final p = alias.isEmpty ? '' : '$alias.';
  return '''
COALESCE(
  ${p}payload->'network'->'response'->>'body',
  ${p}payload->'network'->>'responseBody',
  ''
)''';
}

String _sqlTextList(List<String> values) =>
    values.map((v) => "'${v.replaceAll("'", "''")}'").join(', ');

/// Network events that look like WAF / edge HTML block pages.
///
/// Tuned for list scans: text status match (no cast/regex), short body peek
/// for the HTML fallback. Content-Type is checked before touching the body.
String sqlIsWafRejectEvent({
  String alias = '',
  required List<int> statusCodes,
  required List<String> contentTypes,
}) {
  if (statusCodes.isEmpty || contentTypes.isEmpty) return 'FALSE';
  final p = alias.isEmpty ? '' : '$alias.';
  final ct = sqlNetworkContentType(alias: alias);
  final body = sqlNetworkResponseBody(alias: alias);
  // Text IN is cheaper than ::int cast + digit regex on every network row.
  final codes = _sqlTextList(statusCodes.map((c) => '$c').toList());
  final types = _sqlTextList(contentTypes.map((e) => e.toLowerCase()).toList());
  return '''
(
  ${p}type = 'network'
  AND (${p}payload->'network'->>'statusCode') IN ($codes)
  AND (
    (
      $ct <> ''
      AND $ct IN ($types)
    )
    OR (
      $ct = ''
      AND LEFT($body, 1024) ~* '(<html|request rejected|cf-ray|attention required|access denied)'
    )
  )
)''';
}

/// Optional multi-value env / version filters from WAF project settings.
/// Empty lists mean “all”.
String sqlWafSettingsFacets({
  String alias = '',
  List<String> environments = const [],
  List<String> appVersions = const [],
}) {
  final parts = <String>[];
  if (environments.isNotEmpty) {
    parts.add('${sqlEnvironmentExpr(alias: alias)} IN (${_sqlTextList(environments)})');
  }
  if (appVersions.isNotEmpty) {
    parts.add('${sqlAppVersionExpr(alias: alias)} IN (${_sqlTextList(appVersions)})');
  }
  if (parts.isEmpty) return '';
  return parts.map((p) => 'AND $p').join('\n          ');
}

bool isWafRejectEvent(
  String type,
  Map<String, dynamic> payload, {
  required List<int> statusCodes,
  required List<String> contentTypes,
}) {
  if (type != 'network' || statusCodes.isEmpty || contentTypes.isEmpty) return false;
  final network = payload['network'];
  if (network is! Map) return false;
  final code = int.tryParse('${network['statusCode'] ?? ''}');
  if (code == null || !statusCodes.contains(code)) return false;

  final response = network['response'] is Map ? Map<String, dynamic>.from(network['response'] as Map) : <String, dynamic>{};
  final headers = response['headers'] is Map ? Map<String, dynamic>.from(response['headers'] as Map) : <String, dynamic>{};
  String? rawCt;
  for (final key in ['content-type', 'Content-Type', 'contentType']) {
    rawCt ??= headers[key]?.toString() ?? response[key]?.toString() ?? network[key]?.toString();
  }
  final ct = (rawCt ?? '').split(';').first.trim().toLowerCase();
  final types = contentTypes.map((e) => e.toLowerCase()).toList();
  if (ct.isNotEmpty) return types.contains(ct);
  final body = '${response['body'] ?? network['responseBody'] ?? ''}';
  final peek = body.length > 1024 ? body.substring(0, 1024) : body;
  return RegExp(r'(<html|request rejected|cf-ray|attention required|access denied)', caseSensitive: false)
      .hasMatch(peek);
}

/// Pull support / ray / request id from WAF HTML body or CF-Ray header.
String? extractWafRequestId(String? html, {String? headerRay}) {
  final body = html ?? '';
  final patterns = <RegExp>[
    RegExp(r'support\s*ID\s*is\s*[:\s]*([A-Za-z0-9_-]+)', caseSensitive: false),
    RegExp(r'request\s*ID\s*[:\s#]*([A-Za-z0-9_-]+)', caseSensitive: false),
    RegExp(r'ray\s*ID\s*[:\s]*([A-Za-z0-9_-]+)', caseSensitive: false),
    RegExp(r'cf-ray["\s:=]+([A-Za-z0-9_-]+)', caseSensitive: false),
    RegExp(r'incident\s*ID\s*[:\s]*([A-Za-z0-9_-]+)', caseSensitive: false),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(body);
    if (m != null) {
      final id = m.group(1)?.trim();
      if (id != null && id.isNotEmpty) return id;
    }
  }
  final ray = headerRay?.trim();
  if (ray != null && ray.isNotEmpty) return ray;
  return null;
}
