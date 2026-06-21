/// Screen trail step — how the user navigated before an event.
///
/// SDK (`scout_logger_plus`) should send each [screenTrail] / [breadcrumbs] item as:
/// ```json
/// {
///   "route": "/checkout",
///   "screenName": "Checkout",
///   "navigationType": "push",
///   "at": "2026-06-20T14:19:50.000Z",
///   "durationMs": 4200
/// }
/// ```
enum NavTransition {
  push,
  pop,
  replace,
  remove,
  go,
  unknown;

  String get label => switch (this) {
        NavTransition.push => 'Push',
        NavTransition.pop => 'Pop',
        NavTransition.replace => 'Replace',
        NavTransition.remove => 'Remove',
        NavTransition.go => 'Go',
        NavTransition.unknown => '—',
      };

  /// Wire value for ingest JSON (`navigationType` field).
  String get wire => switch (this) {
        NavTransition.unknown => '',
        _ => name,
      };

  bool get isKnown => this != NavTransition.unknown;
}

NavTransition parseNavTransition(Map<String, dynamic> step) {
  final raw = step['navigationType'] ??
      step['navType'] ??
      step['transition'] ??
      step['navAction'] ??
      step['action'] ??
      step['type'];
  if (raw == null) return NavTransition.unknown;
  final s = raw.toString().toLowerCase().trim();
  return switch (s) {
    'push' || 'navigate' || 'navigate_to' => NavTransition.push,
    'pop' || 'back' || 'pop_until' => NavTransition.pop,
    'replace' || 'replacestate' || 'replace_all' || 'replace_state' =>
      NavTransition.replace,
    'remove' || 'remove_route' => NavTransition.remove,
    'go' || 'go_named' => NavTransition.go,
    'navigation' => NavTransition.push,
    _ => NavTransition.unknown,
  };
}

/// Normalize a trail step for ingest (use from SDK when recording navigation).
Map<String, dynamic> screenTrailStep({
  required String route,
  required NavTransition navigationType,
  String? screenName,
  DateTime? at,
  int? durationMs,
}) =>
    {
      'route': route,
      'screenName': screenName ?? route,
      if (navigationType.isKnown) 'navigationType': navigationType.wire,
      if (at != null) 'at': at.toUtc().toIso8601String(),
      if (durationMs != null) 'durationMs': durationMs,
    };
