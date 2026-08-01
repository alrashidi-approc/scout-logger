import 'event_view.dart';

/// Short agent brief for issue/event detail. Prefer `payload.diagnosis`, then heuristics.
class SmartIssueSummary {
  SmartIssueSummary._();

  static String fromEvent(EventView v) => _render(_briefFromEvent(v));

  static String fromIssue(Map<String, dynamic> issue, List<Map<String, dynamic>> events) {
    if (events.isEmpty) {
      final title = str(issue['title']) ?? 'unknown';
      final count = (issue['eventCount'] as num?)?.toInt() ?? 0;
      return [
        '## Smart summary',
        '',
        '**Where:** unknown',
        '**Failed at:** unknown',
        '**Why:** Issue `$title` has no loaded events to interpret.',
        '**Next:** Open a member event and copy its summary.',
        '**Meta:** events=`$count`',
      ].join('\n');
    }
    final primary = _briefFromEvent(EventView(events.first));
    final storm = primary.storm ||
        events.take(8).any((e) => _briefFromEvent(EventView(e)).storm) ||
        ((issue['eventCount'] as num?)?.toInt() ?? 0) >= 10;
    return _render(primary.copyWith(
      storm: storm,
      issueTitle: str(issue['title']),
      eventCount: (issue['eventCount'] as num?)?.toInt(),
      firstSeen: str(issue['firstSeenAt']),
      lastSeen: str(issue['lastSeenAt']),
    ));
  }

  static _Brief _briefFromEvent(EventView v) {
    final ctx = v.context;
    final crumbs = v.breadcrumbs;
    final message = v.message;
    final operation = _pick(ctx, 'operation') ??
        _pick(v.custom, 'operation') ??
        v.diagnosisOperation ??
        _matchOp(message);
    final stage = v.diagnosisStage ?? _pick(ctx, 'step') ?? _pick(ctx, 'stage');
    final entrypoint = _pick(ctx, 'entrypoint') ?? _entrypoint(operation);
    final platformCode = _pick(ctx, 'platform_code') ?? _platformCode(message);
    final structuredLayer = _pick(ctx, 'failure_layer');
    final attempt = _pick(ctx, 'attempt');
    final outcome = _pick(ctx, 'outcome');

    final layers = _layers(crumbs, message, platformCode, structuredLayer);
    final layer = structuredLayer ??
        (v.diagnosisStage != null ? _layerFromStage(v.diagnosisStage!) : null) ??
        (layers.isEmpty ? 'unknown' : layers.first);
    final contributing = layers.where((l) => l != layer).toSet().toList();
    final storm = _isStorm(crumbs, attempt, outcome) ||
        (attempt == 'retry' && (outcome == 'failed_final' || layers.length >= 2));
    final appVersionOk = _appVersionOk(crumbs);

    // Diagnosis wins for prose when present.
    final why = v.hasDiagnosis
        ? _diagnosisWhy(v, contributing, storm, appVersionOk)
        : _heuristicWhy(layer, platformCode, message, contributing, storm, appVersionOk, ctx);

    final next = v.diagnosisNextSteps.isNotEmpty
        ? v.diagnosisNextSteps.take(2).toList()
        : _next(layer, storm, ctx);

    final whereBits = <String>[
      if (v.route != '—') v.route,
      if (operation != null) operation,
      if (entrypoint != null && !(operation?.contains(entrypoint) ?? false)) entrypoint,
    ];

    return _Brief(
      where: whereBits.isEmpty ? 'unknown' : whereBits.join(' · '),
      failedAt: [
        layer,
        if (stage != null && stage != layer) stage,
        if (platformCode != null) '`$platformCode`',
      ].join(platformCode != null || (stage != null && stage != layer) ? ' · ' : ''),
      why: why,
      next: next,
      app: _appLabel(v),
      platform: _platformLabel(v),
      env: v.environment == '—' ? 'unknown' : v.environment,
      release: v.release == '—' ? 'unknown' : v.release,
      storm: storm,
      layer: layer,
    );
  }

  static String _render(_Brief b) {
    final buf = StringBuffer()
      ..writeln('## Smart summary')
      ..writeln()
      ..writeln('**Where:** ${b.where}')
      ..writeln('**Failed at:** ${b.failedAt}')
      ..writeln('**Why:** ${b.why}');
    if (b.next.isNotEmpty) {
      buf.writeln('**Next:** ${b.next.join(' · ')}');
    }
    final meta = <String>[
      b.app,
      b.platform,
      '${b.env} / ${b.release}',
      if (b.issueTitle != null) 'issue=`${b.issueTitle}`',
      if (b.eventCount != null) 'events=`${b.eventCount}`',
      if (b.firstSeen != null) 'first=`${b.firstSeen}`',
      if (b.lastSeen != null) 'last=`${b.lastSeen}`',
      if (b.storm) 'retry-storm',
    ];
    buf.writeln('**Meta:** ${meta.join(' · ')}');
    return buf.toString().trimRight();
  }

  static String _diagnosisWhy(
    EventView v,
    List<String> contributing,
    bool storm,
    bool appVersionOk,
  ) {
    final parts = <String>[
      v.diagnosisSummary,
      if (v.diagnosisLikelyCause != null && v.diagnosisLikelyCause != v.diagnosisSummary)
        v.diagnosisLikelyCause!,
    ];
    final extras = <String>[
      if (appVersionOk) 'app-version OK (200)',
      if (contributing.contains('app_check')) 'App Check also failed in same loop',
      if (contributing.contains('device_guard')) 'DeviceGuard also failed in same loop',
      if (storm) 'retry storm — not N independent crashes',
    ];
    if (extras.isNotEmpty) parts.add(extras.join('; '));
    return parts.join(' ');
  }

  static String _heuristicWhy(
    String layer,
    String? platformCode,
    String message,
    List<String> contributing,
    bool storm,
    bool appVersionOk,
    Map<String, dynamic> ctx,
  ) {
    final primary = switch (layer) {
      'device_guard' =>
        'DeviceGuard Keystore/identity enrollment failed'
            '${platformCode != null ? ' (`$platformCode`)' : ''} — not Firebase Auth.',
      'app_check' =>
        'App Check token unavailable'
            '${_pick(ctx, 'app_check_provider') != null ? ' (provider=${_pick(ctx, 'app_check_provider')})' : ''}'
            '; on *.dev release builds often Play Integrity, not Firebase down.',
      'bootstrap_api' => 'Bootstrap API error.',
      'hang' => 'Hang/timeout during bootstrap.',
      'network' => 'Network failure (not version check).',
      _ => message.trim().isEmpty
          ? 'Insufficient signals to classify.'
          : (message.length > 120 ? '${message.substring(0, 117)}…' : message),
    };
    final extras = <String>[
      if (appVersionOk) 'app-version OK (200) — not Kong',
      if (contributing.contains('app_check') && layer != 'app_check')
        'App Check also failed in same loop',
      if (contributing.contains('device_guard') && layer != 'device_guard')
        'DeviceGuard also failed in same loop',
      if (storm) 'retry storm — downgrade mid-retry from crashing',
    ];
    return extras.isEmpty ? primary : '$primary ${extras.join('; ')}.';
  }

  static List<String> _next(String layer, bool storm, Map<String, dynamic> ctx) {
    final next = <String>[
      switch (layer) {
        'device_guard' =>
          'Check DeviceGuard identity (`identity_state`=${_pick(ctx, 'identity_state') ?? '?'}, `has_hw_key`=${_pick(ctx, 'has_hw_key') ?? '?'})',
        'app_check' =>
          'Confirm App Check provider (provider=${_pick(ctx, 'app_check_provider') ?? '?'}, kDebugMode=${_pick(ctx, 'kDebugMode') ?? '?'})',
        'bootstrap_api' => 'Inspect `/bootstrap/*` status + HMAC',
        'hang' => 'Profile splash for blocking native calls',
        _ => 'Confirm first hard failure in Timeline',
      },
      if (storm) 'Keep `crashing` for failed_final only; mid-retry → error/warning',
    ];
    return next;
  }

  // ── helpers ──────────────────────────────────────────────────────

  static String? _pick(Map<String, dynamic> m, String key) {
    final v = str(m[key])?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  static String _appLabel(EventView v) {
    final bundle = str(v.payload['packageName']) ??
        str(v.payload['bundleId']) ??
        str(asMap(v.payload['release'])['bundleId']);
    final ver = v.appVersionLabel;
    if (bundle != null && bundle.isNotEmpty && ver != '—') return '$bundle@$ver';
    if (v.release != '—') return v.release;
    if (ver != '—') return ver;
    return 'unknown';
  }

  static String _platformLabel(EventView v) {
    final os = str(v.device['osVersion']) ?? str(v.device['os']) ?? str(v.device['systemVersion']);
    final plat = v.platform == '—' ? null : v.platform;
    final mfr = str(v.device['manufacturer']) ?? str(v.device['brand']);
    final model = str(v.device['model']) ?? str(v.device['name']);
    final left = [if (plat != null) plat, if (os != null && os.isNotEmpty) os].join(' ');
    final right = [if (mfr != null && mfr.isNotEmpty) mfr, if (model != null && model.isNotEmpty) model].join(' ');
    if (left.isEmpty && right.isEmpty) return 'unknown';
    if (right.isEmpty) return left;
    if (left.isEmpty) return right;
    return '$left · $right';
  }

  static String? _entrypoint(String? operation) {
    if (operation == null || !operation.startsWith('device_bootstrap_')) return null;
    return operation.substring('device_bootstrap_'.length);
  }

  static String? _matchOp(String message) =>
      RegExp(r'device_bootstrap_[\w-]+').firstMatch(message)?.group(0);

  static String? _platformCode(String message) {
    final m = RegExp(r'PlatformException\((\w+)').firstMatch(message);
    if (m != null) return m.group(1);
    if (message.toLowerCase().contains('registration_failed')) return 'registration_failed';
    return null;
  }

  static String? _layerFromStage(String stage) {
    final s = stage.toLowerCase();
    if (s.contains('app_check') || s.contains('app-check')) return 'app_check';
    if (s.contains('device_guard') || s.contains('guard')) return 'device_guard';
    if (s.contains('bootstrap')) return 'bootstrap_api';
    if (s.contains('hang')) return 'hang';
    return null;
  }

  static String _crumbText(Map<String, dynamic> c) =>
      (str(c['message']) ?? str(c['label']) ?? str(c['name']) ?? '').toLowerCase();

  static String? _layerFromText(String text) {
    if (text.contains('firebase app check') ||
        text.contains('app check token') ||
        text.contains('app check') ||
        text.contains('attestation')) {
      return 'app_check';
    }
    if (text.contains('device guard') ||
        text.contains('deviceguard') ||
        text.contains('registration_failed') ||
        text.contains('needs_recovery') ||
        text.contains('key_id_failed')) {
      return 'device_guard';
    }
    if (text.contains('apphang') || text.contains('hang') || text.contains('timeout')) return 'hang';
    if (text.contains('/bootstrap/')) return 'bootstrap_api';
    if (RegExp(r'\b(http|https)://|\b(get|post|put|patch|delete)\b').hasMatch(text) &&
        (text.contains('fail') || text.contains('error') || RegExp(r'\b[45]\d\d\b').hasMatch(text))) {
      return 'network';
    }
    return null;
  }

  static bool _appVersionOk(List<Map<String, dynamic>> crumbs) {
    for (final c in crumbs) {
      final t = _crumbText(c);
      if (t.contains('app-version') && (t.contains('200') || t.contains('ok') || t.contains('success'))) {
        return true;
      }
      final status = str(c['statusCode']) ?? str(c['status']);
      final url = str(c['url']) ?? str(c['path']) ?? t;
      if (url.contains('app-version') && status == '200') return true;
    }
    return false;
  }

  static List<String> _layers(
    List<Map<String, dynamic>> crumbs,
    String message,
    String? platformCode,
    String? structuredLayer,
  ) {
    final out = <({String layer, int i})>[];
    var i = 0;
    for (final c in crumbs) {
      final t = _crumbText(c);
      final layer = _layerFromText(t);
      final hard = t.contains('fail') ||
          t.contains('error') ||
          t.contains('unavailable') ||
          t.contains('registration_failed') ||
          t.contains('exception') ||
          t.contains('denied') ||
          t.contains('403');
      if (layer != null && hard) out.add((layer: layer, i: i));
      i++;
    }
    final msg = message.toLowerCase();
    if (platformCode == 'registration_failed' ||
        msg.contains('registration_failed') ||
        msg.contains('needs_recovery') ||
        msg.contains('key_id_failed')) {
      out.add((layer: 'device_guard', i: 1000));
    }
    if (msg.contains('app check') ||
        msg.contains('firebase app check') ||
        msg.contains('attestation failed') ||
        msg.contains('token unavailable')) {
      out.add((layer: 'app_check', i: 1001));
    }
    if (msg.contains('/bootstrap/') && RegExp(r'\b[45]\d\d\b').hasMatch(msg)) {
      out.add((layer: 'bootstrap_api', i: 1002));
    }
    if (msg.contains('apphang') || (msg.contains('hang') && msg.contains('guard'))) {
      out.add((layer: 'hang', i: 1003));
    }
    if (structuredLayer != null) out.insert(0, (layer: structuredLayer, i: -1));

    final seen = <String>{};
    final ordered = <String>[];
    final sorted = [...out]..sort((a, b) => a.i.compareTo(b.i));
    for (final s in sorted) {
      if (seen.add(s.layer)) ordered.add(s.layer);
    }
    return ordered;
  }

  static bool _isStorm(List<Map<String, dynamic>> crumbs, String? attempt, String? outcome) {
    if (attempt == 'retry' || attempt == 'recovery' || outcome == 'failed_final') return true;
    final counts = <String, int>{};
    DateTime? firstAt;
    var repeats = 0;
    for (final c in crumbs) {
      final t = _crumbText(c);
      final hit = t.contains('registration_failed') ||
          t.contains('token unavailable') ||
          t.contains('platformexception');
      if (!hit) continue;
      repeats++;
      final at = DateTime.tryParse(str(c['timestamp']) ?? str(c['at']) ?? '');
      firstAt ??= at;
      if (firstAt != null && at != null && at.difference(firstAt).inSeconds <= 30 && repeats >= 3) {
        return true;
      }
      counts[t] = (counts[t] ?? 0) + 1;
      if (counts[t]! >= 3) return true;
    }
    return false;
  }
}

class _Brief {
  const _Brief({
    required this.where,
    required this.failedAt,
    required this.why,
    required this.next,
    required this.app,
    required this.platform,
    required this.env,
    required this.release,
    required this.storm,
    required this.layer,
    this.issueTitle,
    this.eventCount,
    this.firstSeen,
    this.lastSeen,
  });

  _Brief copyWith({
    bool? storm,
    String? issueTitle,
    int? eventCount,
    String? firstSeen,
    String? lastSeen,
  }) =>
      _Brief(
        where: where,
        failedAt: failedAt,
        why: why,
        next: next,
        app: app,
        platform: platform,
        env: env,
        release: release,
        storm: storm ?? this.storm,
        layer: layer,
        issueTitle: issueTitle ?? this.issueTitle,
        eventCount: eventCount ?? this.eventCount,
        firstSeen: firstSeen ?? this.firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  final String where;
  final String failedAt;
  final String why;
  final List<String> next;
  final String app;
  final String platform;
  final String env;
  final String release;
  final bool storm;
  final String layer;
  final String? issueTitle;
  final int? eventCount;
  final String? firstSeen;
  final String? lastSeen;
}
