import 'package:scout_models/scout_models.dart';

import 'event_view.dart';
import 'product_readable.dart';

/// Structured + copyable agent brief for issue/event detail.
class SmartSummary {
  const SmartSummary({
    required this.where,
    required this.failedAt,
    required this.why,
    required this.next,
    required this.meta,
    required this.markdown,
  });

  final String where;
  final String failedAt;
  final String why;
  final List<String> next;
  final List<String> meta;
  final String markdown;
}

/// Short agent brief for issue/event detail. Prefer `payload.diagnosis`, then heuristics.
class SmartIssueSummary {
  SmartIssueSummary._();

  static SmartSummary fromEvent(EventView v) => _toSummary(_briefFromEvent(v));

  static SmartSummary fromIssue(Map<String, dynamic> issue, List<Map<String, dynamic>> events) {
    if (events.isEmpty) {
      final title = str(issue['title']) ?? 'unknown';
      final count = (issue['eventCount'] as num?)?.toInt() ?? 0;
      const where = 'unknown';
      const failedAt = 'unknown';
      final why = 'Issue `$title` has no loaded events to interpret.';
      const next = ['Open a member event and copy its summary.'];
      final meta = ['events=`$count`'];
      return SmartSummary(
        where: where,
        failedAt: failedAt,
        why: why,
        next: next,
        meta: meta,
        markdown: _markdown(where: where, failedAt: failedAt, why: why, next: next, meta: meta),
      );
    }
    final primary = _briefFromEvent(EventView(events.first));
    final storm = primary.storm ||
        events.take(8).any((e) => _briefFromEvent(EventView(e)).storm) ||
        ((issue['eventCount'] as num?)?.toInt() ?? 0) >= 10;
    return _toSummary(primary.copyWith(
      storm: storm,
      issueTitle: str(issue['title']),
      eventCount: (issue['eventCount'] as num?)?.toInt(),
      firstSeen: str(issue['firstSeenAt']),
      lastSeen: str(issue['lastSeenAt']),
    ));
  }

  static SmartSummary _toSummary(_Brief b) {
    final meta = <String>[
      b.app,
      b.platform,
      '${prettyProductScalar(b.env)} / ${b.release}',
      if (b.issueTitle != null) 'issue=`${b.issueTitle}`',
      if (b.eventCount != null) 'events=`${b.eventCount}`',
      if (b.firstSeen != null) 'first=`${b.firstSeen}`',
      if (b.lastSeen != null) 'last=`${b.lastSeen}`',
      if (b.storm) 'Retry storm',
    ];
    return SmartSummary(
      where: b.where,
      failedAt: b.failedAt,
      why: b.why,
      next: b.next,
      meta: meta,
      markdown: _markdown(where: b.where, failedAt: b.failedAt, why: b.why, next: b.next, meta: meta),
    );
  }

  static String _markdown({
    required String where,
    required String failedAt,
    required String why,
    required List<String> next,
    required List<String> meta,
  }) {
    final buf = StringBuffer()
      ..writeln('## Smart summary')
      ..writeln()
      ..writeln('**Where:** $where')
      ..writeln('**Failed at:** $failedAt')
      ..writeln('**Why:** $why');
    if (next.isNotEmpty) buf.writeln('**Next:** ${next.join(' · ')}');
    buf.writeln('**Meta:** ${meta.join(' · ')}');
    return buf.toString().trimRight();
  }

  static _Brief _briefFromEvent(EventView v) {
    if (v.hasDiagnosis) {
      return _diagnosisBrief(v);
    }
    if (v.network.isNotEmpty) {
      return _networkBrief(v);
    }
    return _heuristicBrief(v);
  }

  static _Brief _diagnosisBrief(EventView v) {
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
    final netCall = v.network.isNotEmpty ? _networkCallLabel(v) : null;
    final whereBits = <String>[
      if (v.route != '—') v.route,
      if (operation != null) prettyProductScalar(operation),
      if (entrypoint != null && !(operation?.contains(entrypoint) ?? false))
        prettyProductScalar(entrypoint),
      if (netCall != null) netCall,
    ];
    final failedBits = <String>[
      prettyProductScalar(layer),
      if (stage != null && stage != layer) prettyProductScalar(stage),
      if (platformCode != null) prettyProductScalar(platformCode),
    ];
    return _Brief(
      where: whereBits.isEmpty ? 'unknown' : whereBits.join(' · '),
      failedAt: failedBits.join(' · '),
      why: _diagnosisWhy(v, contributing, storm, appVersionOk),
      next: v.diagnosisNextSteps.isNotEmpty
          ? v.diagnosisNextSteps.take(2).toList()
          : _next(layer, storm, ctx),
      app: _appLabel(v),
      platform: _platformLabel(v),
      env: v.environment == '—' ? 'unknown' : v.environment,
      release: v.release == '—' ? 'unknown' : v.release,
      storm: storm,
      layer: layer,
    );
  }

  static _Brief _networkBrief(EventView v) {
    final readable = v.networkReadable;
    final fault = v.networkFault;
    final error = str(v.network['error'])?.trim();
    final clientCode = _clientErrorCode(error);
    final outcomeLabel = str(readable['outcomeLabel']) ?? str(readable['outcome']);
    final call = _networkCallLabel(v);

    final whereBits = <String>[
      if (v.route != '—') v.route,
      if (call != null) call,
    ];

    final failedBits = <String>[
      'Network',
      if (clientCode != null) prettyProductScalar(clientCode),
      if (fault != null && fault.label.isNotEmpty) fault.label,
      if (clientCode == null && outcomeLabel != null) outcomeLabel,
    ];
    // Dedupe adjacent identical labels
    final failedAt = <String>[];
    for (final b in failedBits) {
      if (failedAt.isEmpty || failedAt.last.toLowerCase() != b.toLowerCase()) failedAt.add(b);
    }

    return _Brief(
      where: whereBits.isEmpty ? 'unknown' : whereBits.join(' · '),
      failedAt: failedAt.join(' · '),
      why: _networkWhy(v, error: error, clientCode: clientCode, fault: fault),
      next: _networkNext(v, clientCode: clientCode, fault: fault),
      app: _appLabel(v),
      platform: _platformLabel(v),
      env: v.environment == '—' ? 'unknown' : v.environment,
      release: v.release == '—' ? 'unknown' : v.release,
      storm: false,
      layer: 'network',
    );
  }

  static _Brief _heuristicBrief(EventView v) {
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

    final why = _heuristicWhy(layer, platformCode, message, contributing, storm, appVersionOk, ctx);
    final next = _next(layer, storm, ctx);

    final whereBits = <String>[
      if (v.route != '—') v.route,
      if (operation != null) prettyProductScalar(operation),
      if (entrypoint != null && !(operation?.contains(entrypoint) ?? false))
        prettyProductScalar(entrypoint),
    ];

    final failedBits = <String>[
      prettyProductScalar(layer),
      if (stage != null && stage != layer) prettyProductScalar(stage),
      if (platformCode != null) prettyProductScalar(platformCode),
    ];

    return _Brief(
      where: whereBits.isEmpty ? 'unknown' : whereBits.join(' · '),
      failedAt: failedBits.join(' · '),
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

  static String? _networkCallLabel(EventView v) {
    final readable = v.networkReadable;
    final req = asMap(readable['request']);
    final method = str(req['method']) ?? str(v.network['method']) ?? 'REQUEST';
    final path = str(req['path']) ??
        () {
          final url = str(v.network['url']) ?? '';
          final uri = Uri.tryParse(url);
          if (uri == null) return url;
          return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
        }();
    if (path == null || path.isEmpty) return null;
    final short = path.length > 64 ? '${path.substring(0, 61)}…' : path;
    return '$method $short';
  }

  static String? _clientErrorCode(String? error) {
    if (error == null || error.isEmpty) return null;
    return RegExp(r'\[client:([^\]]+)\]').firstMatch(error)?.group(1);
  }

  static String _networkWhy(
    EventView v, {
    required String? error,
    required String? clientCode,
    required NetworkFaultInfo? fault,
  }) {
    final parts = <String>[];
    if (clientCode != null) {
      final detail = (error ?? '').replaceFirst(RegExp(r'\[client:[^\]]+\]\s*'), '').trim();
      parts.add(
        'Client blocked the request before HTTP (`$clientCode`)'
        '${detail.isNotEmpty ? ': $detail' : ''}.',
      );
      if (clientCode == 'tenant_missing') {
        parts.add('Not a server outage — missing tenant header on the client.');
      }
    } else if (error != null && error.isNotEmpty) {
      parts.add(error.endsWith('.') ? error : '$error.');
    } else if (v.message.trim().isNotEmpty) {
      parts.add(v.message.trim());
    }
    final hint = fault?.actionHint.trim();
    if (hint != null && hint.isNotEmpty && !(parts.join(' ').contains(hint))) {
      parts.add(hint);
    }
    if (parts.isEmpty) return 'Network request failed with insufficient detail.';
    return parts.join(' ');
  }

  static List<String> _networkNext(
    EventView v, {
    required String? clientCode,
    required NetworkFaultInfo? fault,
  }) {
    final next = <String>[
      if (clientCode == 'tenant_missing') ...[
        'Attach `x-tenant-id` (tenant context) before khadamat API calls',
        'Confirm tenant is set after bootstrap and survives navigation to this screen',
      ] else if (clientCode != null) ...[
        'Fix client precondition `$clientCode` before retrying this endpoint',
        if (fault != null && fault.actionHint.isNotEmpty) fault.actionHint,
      ] else if (fault != null && fault.actionHint.isNotEmpty)
        fault.actionHint
      else
        'Inspect Network panel (request headers, error, cURL)',
    ];
    return next.take(2).toList();
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
      if (appVersionOk) 'App version OK (200)',
      if (contributing.contains('app_check')) 'App Check also failed in same loop',
      if (contributing.contains('device_guard')) 'Device Guard also failed in same loop',
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
    final code = platformCode == null ? null : prettyProductScalar(platformCode);
    final primary = switch (layer) {
      'device_guard' =>
        'Device Guard Keystore/identity enrollment failed'
            '${code != null ? ' ($code)' : ''} — not Firebase Auth.',
      'app_check' =>
        'App Check token unavailable'
            '${_pick(ctx, 'app_check_provider') != null ? ' (${productHumanLine('app_check_provider', _pick(ctx, 'app_check_provider'))})' : ''}'
            '; on *.dev release builds often Play Integrity, not Firebase down.',
      'bootstrap_api' => 'Bootstrap API error.',
      'hang' => 'Hang/timeout during bootstrap.',
      'network' => 'Network failure (not version check).',
      _ => message.trim().isEmpty
          ? 'Insufficient signals to classify.'
          : (message.length > 120 ? '${message.substring(0, 117)}…' : message),
    };
    final extras = <String>[
      if (appVersionOk) 'App version OK (200) — not Kong',
      if (contributing.contains('app_check') && layer != 'app_check')
        'App Check also failed in same loop',
      if (contributing.contains('device_guard') && layer != 'device_guard')
        'Device Guard also failed in same loop',
      if (storm) 'retry storm — downgrade mid-retry from crashing',
    ];
    return extras.isEmpty ? primary : '$primary ${extras.join('; ')}.';
  }

  static List<String> _next(String layer, bool storm, Map<String, dynamic> ctx) {
    String? ctxLine(String key) {
      final v = _pick(ctx, key);
      if (v == null) return null;
      if (v == 'true' || v == 'false') return productHumanLine(key, v == 'true');
      return productHumanLine(key, v);
    }

    final next = <String>[
      switch (layer) {
        'device_guard' => () {
            final bits = [
              if (ctxLine('identity_state') != null) ctxLine('identity_state')!,
              if (ctxLine('has_hw_key') != null) ctxLine('has_hw_key')!,
            ];
            return bits.isEmpty
                ? 'Check Device Guard identity'
                : 'Check Device Guard identity (${bits.join('; ')})';
          }(),
        'app_check' => () {
            final bits = [
              if (ctxLine('app_check_provider') != null) ctxLine('app_check_provider')!,
              if (ctxLine('kDebugMode') != null) ctxLine('kDebugMode')!,
            ];
            return bits.isEmpty
                ? 'Confirm App Check provider'
                : 'Confirm App Check provider (${bits.join('; ')})';
          }(),
        'bootstrap_api' => 'Inspect `/bootstrap/*` status + HMAC',
        'hang' => 'Profile splash for blocking native calls',
        _ => 'Confirm first hard failure in Timeline',
      },
      if (storm) 'Keep crashing for Failed Final only; mid-retry → error/warning',
    ];
    return next;
  }

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
