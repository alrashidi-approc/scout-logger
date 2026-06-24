/// How to treat a failed network call — for alerts, issues, and UX.
///
/// - [critical] — engineering / infra (5xx, missing API, transport)
/// - [user] — invalid input or business rule (400, 422, …)
/// - [auth] — session or permission (401, 403) — usually app-handled
enum NetworkFaultClass { critical, user, auth, success, unknown }

class NetworkFaultInfo {
  const NetworkFaultInfo({
    required this.faultClass,
    required this.kind,
    required this.label,
    required this.actionHint,
    required this.alertWorthy,
    required this.issueWorthy,
    required this.operationalError,
  });

  final NetworkFaultClass faultClass;
  final String kind;
  final String label;
  final String actionHint;
  final bool alertWorthy;
  final bool issueWorthy;
  final bool operationalError;

  Map<String, dynamic> toJson() => {
        'faultClass': faultClass.name,
        'kind': kind,
        'label': label,
        'actionHint': actionHint,
        'alertWorthy': alertWorthy,
        'issueWorthy': issueWorthy,
        'operationalError': operationalError,
      };

  static const editableFaultClasses = [
    NetworkFaultClass.critical,
    NetworkFaultClass.user,
    NetworkFaultClass.auth,
    NetworkFaultClass.success,
  ];

  static NetworkFaultInfo? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final cls = m['faultClass']?.toString();
    return NetworkFaultInfo(
      faultClass: NetworkFaultClass.values.firstWhere(
        (c) => c.name == cls,
        orElse: () => NetworkFaultClass.unknown,
      ),
      kind: m['kind']?.toString() ?? 'unknown',
      label: m['label']?.toString() ?? 'Unknown',
      actionHint: m['actionHint']?.toString() ?? '',
      alertWorthy: m['alertWorthy'] == true,
      issueWorthy: m['issueWorthy'] == true,
      operationalError: m['operationalError'] == true,
    );
  }
}

NetworkFaultClass? parseNetworkFaultClass(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final c in NetworkFaultClass.values) {
    if (c.name == raw.toLowerCase()) return c;
  }
  return null;
}

Map<int, NetworkFaultClass> parseNetworkFaultOverrides(Map<int, String>? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final out = <int, NetworkFaultClass>{};
  for (final e in raw.entries) {
    final cls = parseNetworkFaultClass(e.value);
    if (cls != null && cls != NetworkFaultClass.unknown) out[e.key] = cls;
  }
  return out;
}

/// Preset HTTP codes shown in project settings (defaults apply when not overridden).
const kPresetNetworkFaultCodes = [400, 401, 403, 404, 408, 409, 413, 422, 429, 500, 502, 503, 504];

String defaultNetworkFaultClassName(int statusCode) =>
    classifyNetworkFault({'statusCode': statusCode}).faultClass.name;

NetworkFaultInfo networkFaultInfoForClass(NetworkFaultClass cls, {required int statusCode}) {
  switch (cls) {
    case NetworkFaultClass.critical:
      if (statusCode >= 500) {
        return NetworkFaultInfo(
          faultClass: NetworkFaultClass.critical,
          kind: 'server_error',
          label: 'Server error',
          actionHint: 'Backend failed — check server logs, deployment health, and dependencies.',
          alertWorthy: true,
          issueWorthy: true,
          operationalError: true,
        );
      }
      if (statusCode == 404) {
        return const NetworkFaultInfo(
          faultClass: NetworkFaultClass.critical,
          kind: 'endpoint_missing',
          label: 'API not found',
          actionHint: 'Route or resource missing — fix client URL, API version, or register the endpoint.',
          alertWorthy: true,
          issueWorthy: true,
          operationalError: true,
        );
      }
      if (statusCode == 408 || statusCode == 504) {
        return const NetworkFaultInfo(
          faultClass: NetworkFaultClass.critical,
          kind: 'timeout',
          label: 'Timeout',
          actionHint: 'Upstream or client timed out — check latency, retries, and gateway limits.',
          alertWorthy: true,
          issueWorthy: true,
          operationalError: true,
        );
      }
      if (statusCode == 429) {
        return const NetworkFaultInfo(
          faultClass: NetworkFaultClass.critical,
          kind: 'rate_limited',
          label: 'Rate limited',
          actionHint: 'Too many requests — backoff, cache, or raise API limits.',
          alertWorthy: true,
          issueWorthy: true,
          operationalError: true,
        );
      }
      return NetworkFaultInfo(
        faultClass: NetworkFaultClass.critical,
        kind: 'client_error',
        label: 'Critical ($statusCode)',
        actionHint: 'Treated as an engineering incident — review server and client handling.',
        alertWorthy: true,
        issueWorthy: true,
        operationalError: true,
      );
    case NetworkFaultClass.user:
      return NetworkFaultInfo(
        faultClass: NetworkFaultClass.user,
        kind: statusCode == 422 ? 'validation' : statusCode == 409 ? 'conflict' : 'bad_request',
        label: statusCode == 422
            ? 'Validation error'
            : statusCode == 409
                ? 'Conflict'
                : 'Client error ($statusCode)',
        actionHint: 'User input or request shape — show field errors; not a server incident.',
        alertWorthy: false,
        issueWorthy: false,
        operationalError: false,
      );
    case NetworkFaultClass.auth:
      return NetworkFaultInfo(
        faultClass: NetworkFaultClass.auth,
        kind: statusCode == 403 ? 'forbidden' : 'unauthorized',
        label: statusCode == 403 ? 'Forbidden' : 'Unauthorized',
        actionHint: statusCode == 403
            ? 'User lacks permission — verify roles, scopes, or account state in the app.'
            : 'Usually handled in-app — refresh session, re-login, or fix auth headers.',
        alertWorthy: false,
        issueWorthy: false,
        operationalError: false,
      );
    case NetworkFaultClass.success:
      return const NetworkFaultInfo(
        faultClass: NetworkFaultClass.success,
        kind: 'success',
        label: 'Success',
        actionHint: 'No action required.',
        alertWorthy: false,
        issueWorthy: false,
        operationalError: false,
      );
    case NetworkFaultClass.unknown:
      return NetworkFaultInfo(
        faultClass: NetworkFaultClass.unknown,
        kind: 'client_error',
        label: 'Client error ($statusCode)',
        actionHint: 'Review API contract and client handling for HTTP $statusCode.',
        alertWorthy: false,
        issueWorthy: false,
        operationalError: false,
      );
  }
}

NetworkFaultInfo classifyNetworkFault(
  Map<String, dynamic> network, {
  Map<int, NetworkFaultClass>? faultOverrides,
}) {
  final statusCode = int.tryParse('${network['statusCode'] ?? ''}');
  final hasResponse = network['hasResponse'] == true || statusCode != null;
  final error = network['error']?.toString();
  final errorType = network['errorType']?.toString();

  if (!hasResponse || (statusCode == null && error != null && error.isNotEmpty)) {
    return NetworkFaultInfo(
      faultClass: NetworkFaultClass.critical,
      kind: 'transport',
      label: 'Transport failure',
      actionHint: 'No usable HTTP response — check connectivity, TLS, timeouts, or client config.',
      alertWorthy: true,
      issueWorthy: true,
      operationalError: true,
    );
  }

  if (statusCode == null) {
    return const NetworkFaultInfo(
      faultClass: NetworkFaultClass.unknown,
      kind: 'unknown',
      label: 'Unknown outcome',
      actionHint: 'Inspect request/response payload for status and error fields.',
      alertWorthy: false,
      issueWorthy: false,
      operationalError: false,
    );
  }

  if (statusCode < 400) {
    return const NetworkFaultInfo(
      faultClass: NetworkFaultClass.success,
      kind: 'success',
      label: 'Success',
      actionHint: 'No action required.',
      alertWorthy: false,
      issueWorthy: false,
      operationalError: false,
    );
  }

  final override = faultOverrides?[statusCode];
  if (override != null) return networkFaultInfoForClass(override, statusCode: statusCode);

  if (statusCode >= 500) {
    return NetworkFaultInfo(
      faultClass: NetworkFaultClass.critical,
      kind: 'server_error',
      label: 'Server error',
      actionHint: 'Backend failed — check server logs, deployment health, and dependencies.',
      alertWorthy: true,
      issueWorthy: true,
      operationalError: true,
    );
  }

  if (statusCode == 404) {
    return const NetworkFaultInfo(
      faultClass: NetworkFaultClass.critical,
      kind: 'endpoint_missing',
      label: 'API not found',
      actionHint: 'Route or resource missing — fix client URL, API version, or register the endpoint.',
      alertWorthy: true,
      issueWorthy: true,
      operationalError: true,
    );
  }

  if (statusCode == 401) {
    return const NetworkFaultInfo(
      faultClass: NetworkFaultClass.auth,
      kind: 'unauthorized',
      label: 'Unauthorized',
      actionHint: 'Usually handled in-app — refresh session, re-login, or fix auth headers.',
      alertWorthy: false,
      issueWorthy: false,
      operationalError: false,
    );
  }

  if (statusCode == 403) {
    return const NetworkFaultInfo(
      faultClass: NetworkFaultClass.auth,
      kind: 'forbidden',
      label: 'Forbidden',
      actionHint: 'User lacks permission — verify roles, scopes, or account state in the app.',
      alertWorthy: false,
      issueWorthy: false,
      operationalError: false,
    );
  }

  if (statusCode == 422 || statusCode == 400 || statusCode == 413) {
    return NetworkFaultInfo(
      faultClass: NetworkFaultClass.user,
      kind: statusCode == 422 ? 'validation' : 'bad_request',
      label: statusCode == 422 ? 'Validation error' : 'Bad request',
      actionHint: 'User input or request shape — show field errors; not a server incident.',
      alertWorthy: false,
      issueWorthy: false,
      operationalError: false,
    );
  }

  if (statusCode == 408 || statusCode == 504) {
    return const NetworkFaultInfo(
      faultClass: NetworkFaultClass.critical,
      kind: 'timeout',
      label: 'Timeout',
      actionHint: 'Upstream or client timed out — check latency, retries, and gateway limits.',
      alertWorthy: true,
      issueWorthy: true,
      operationalError: true,
    );
  }

  if (statusCode == 429) {
    return const NetworkFaultInfo(
      faultClass: NetworkFaultClass.critical,
      kind: 'rate_limited',
      label: 'Rate limited',
      actionHint: 'Too many requests — backoff, cache, or raise API limits.',
      alertWorthy: true,
      issueWorthy: true,
      operationalError: true,
    );
  }

  if (statusCode == 409) {
    return const NetworkFaultInfo(
      faultClass: NetworkFaultClass.user,
      kind: 'conflict',
      label: 'Conflict',
      actionHint: 'Business rule conflict — guide the user to resolve state (duplicate, stale data).',
      alertWorthy: false,
      issueWorthy: false,
      operationalError: false,
    );
  }

  return NetworkFaultInfo(
    faultClass: NetworkFaultClass.unknown,
    kind: 'client_error',
    label: 'Client error ($statusCode)',
    actionHint: 'Review API contract and client handling for HTTP $statusCode.',
    alertWorthy: false,
    issueWorthy: false,
    operationalError: false,
  );
}
