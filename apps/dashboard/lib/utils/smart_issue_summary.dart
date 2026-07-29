import 'event_view.dart';

/// Interprets event/issue payloads into a copy-pasteable root-cause writeup.
/// Prefer structured `payload.context` keys over breadcrumb heuristics.
class SmartIssueSummary {
  SmartIssueSummary._();

  static String fromEvent(EventView v) => _render(_analyzeEvent(v));

  static String fromIssue(Map<String, dynamic> issue, List<Map<String, dynamic>> events) {
    if (events.isEmpty) {
      return _render(_Analysis.emptyIssue(issue));
    }
    // Issue events are newest-first from the API.
    final primary = _analyzeEvent(EventView(events.first));
    final analyses = events.take(8).map((e) => _analyzeEvent(EventView(e))).toList();
    return _render(primary.forIssue(issue, analyses));
  }

  static _Analysis _analyzeEvent(EventView v) {
    final ctx = v.context;
    final custom = v.custom;
    final crumbs = v.breadcrumbs;
    final message = v.message;
    final operation = _ctx(ctx, 'operation') ??
        _ctx(custom, 'operation') ??
        v.diagnosisOperation ??
        _opFromMessage(message);
    final entrypoint = _ctx(ctx, 'entrypoint') ?? _entrypointFromOp(operation);
    final structuredLayer = _ctx(ctx, 'failure_layer');
    final platformCode = _ctx(ctx, 'platform_code') ?? _platformCode(message);
    final outcome = _ctx(ctx, 'outcome');
    final attempt = _ctx(ctx, 'attempt');

    final layersInOrder = _failureSignals(crumbs, message, platformCode, structuredLayer);
    final primaryLayer = structuredLayer ?? (layersInOrder.isEmpty ? 'unknown' : layersInOrder.first.layer);
    final contributing = layersInOrder
        .where((s) => s.layer != primaryLayer)
        .map((s) => s.layer)
        .toSet()
        .toList();

    final storm = _isRetryStorm(crumbs, message, attempt, outcome) ||
        (attempt == 'retry' && (outcome == 'failed_final' || layersInOrder.length >= 2));

    final appVersionOk = _hasAppVersionOk(crumbs);
    final screenMs = str(v.screen['currentScreenMs']) ?? str(v.screen['durationMs']);

    return _Analysis(
      verdict: _verdict(
        primaryLayer: primaryLayer,
        message: message,
        entrypoint: entrypoint,
        operation: operation,
        platformCode: platformCode,
        storm: storm,
      ),
      app: _appLabel(v),
      platform: _platformLabel(v),
      screen: _orUnknown(v.route == '—' ? null : v.route),
      screenMs: screenMs,
      operation: _orUnknown(operation),
      env: _orUnknown(v.environment == '—' ? null : v.environment),
      release: _orUnknown(v.release == '—' ? null : v.release),
      issueTitle: v.issue != null ? str(v.issue!['title']) : null,
      eventCount: v.issue != null ? (v.issue!['eventCount'] as num?)?.toInt() : null,
      firstSeen: v.issue != null ? str(v.issue!['firstSeenAt']) : null,
      lastSeen: v.issue != null ? str(v.issue!['lastSeenAt']) : null,
      flow: _flowSteps(
        crumbs: crumbs,
        message: message,
        operation: operation,
        entrypoint: entrypoint,
        primaryLayer: primaryLayer,
        platformCode: platformCode,
        appVersionOk: appVersionOk,
        storm: storm,
      ),
      primaryCause: _primaryCause(primaryLayer, platformCode, message, ctx),
      contributing: [
        for (final layer in contributing) _contributingLine(layer, ctx),
        if (_ctx(ctx, 'app_check_provider') != null && primaryLayer != 'app_check')
          'App Check provider=${_ctx(ctx, 'app_check_provider')} (kDebugMode=${_ctx(ctx, 'kDebugMode') ?? 'unknown'}).',
      ],
      notThis: _notThis(primaryLayer, appVersionOk, message),
      amplification: storm
          ? [
              'Repeated identical bootstrap/App Check/DeviceGuard failures in one session — treat as a retry storm, not N independent crashes.',
              if (outcome != null) 'outcome=`$outcome`.',
            ]
          : const [],
      next: _nextSteps(primaryLayer, storm, ctx),
      failureLayer: primaryLayer,
      isStorm: storm,
    );
  }

  static String _render(_Analysis a) {
    final buf = StringBuffer()
      ..writeln('## Smart summary')
      ..writeln()
      ..writeln('**Verdict:** ${a.verdict}')
      ..writeln()
      ..writeln('| | |')
      ..writeln('|---|---|')
      ..writeln('| App | `${a.app}` |')
      ..writeln('| Platform | ${a.platform} |')
      ..writeln(
          '| Screen | `${a.screen}`${a.screenMs != null ? ' (${a.screenMs} ms)' : ''} |')
      ..writeln('| Operation | `${a.operation}` |')
      ..writeln('| Env | ${a.env} · release=`${a.release}` |');
    if (a.issueTitle != null || a.eventCount != null) {
      final title = a.issueTitle ?? 'unknown';
      final count = a.eventCount?.toString() ?? 'unknown';
      final first = a.firstSeen ?? 'unknown';
      final last = a.lastSeen ?? 'unknown';
      final stormNote = a.isStorm ? ' · retry storm likely' : '';
      buf.writeln('| Issue | `$title` · events=`$count` · first=`$first` · last=`$last`$stormNote |');
    }
    buf
      ..writeln()
      ..writeln('### Flow');
    if (a.flow.isEmpty) {
      buf.writeln('1. Insufficient breadcrumbs — only message/operation available.');
    } else {
      for (var i = 0; i < a.flow.length; i++) {
        buf.writeln('${i + 1}. ${a.flow[i]}');
      }
    }
    buf
      ..writeln()
      ..writeln('### Root cause')
      ..writeln('- Primary: ${a.primaryCause}');
    for (final c in a.contributing) {
      buf.writeln('- Contributing: $c');
    }
    buf
      ..writeln()
      ..writeln('### Not this');
    for (final n in a.notThis) {
      buf.writeln('- $n');
    }
    if (a.amplification.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('### Amplification');
      for (final line in a.amplification) {
        buf.writeln('- $line');
      }
    }
    buf
      ..writeln()
      ..writeln('### Suggested next');
    for (var i = 0; i < a.next.length; i++) {
      buf.writeln('${i + 1}. ${a.next[i]}');
    }
    return buf.toString().trimRight();
  }

  // ── labels / extraction ──────────────────────────────────────────

  static String? _ctx(Map<String, dynamic> ctx, String key) {
    final v = str(ctx[key])?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  static String _orUnknown(String? v) =>
      (v == null || v.isEmpty || v == '—') ? 'unknown' : v;

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
    final left = [
      if (plat != null) plat,
      if (os != null && os.isNotEmpty) os,
    ].join(' ');
    final right = [
      if (mfr != null && mfr.isNotEmpty) mfr,
      if (model != null && model.isNotEmpty) model,
    ].join(' ');
    if (left.isEmpty && right.isEmpty) return 'unknown';
    if (right.isEmpty) return left;
    if (left.isEmpty) return right;
    return '$left · $right';
  }

  static String? _entrypointFromOp(String? operation) {
    if (operation == null) return null;
    const prefix = 'device_bootstrap_';
    if (!operation.startsWith(prefix)) return null;
    return operation.substring(prefix.length);
  }

  static String? _opFromMessage(String message) {
    final m = RegExp(r'device_bootstrap_[\w-]+').firstMatch(message);
    return m?.group(0);
  }

  static String? _platformCode(String message) {
    final m = RegExp(r'PlatformException\((\w+)').firstMatch(message);
    if (m != null) return m.group(1);
    if (message.toLowerCase().contains('registration_failed')) return 'registration_failed';
    return null;
  }

  static String _crumbText(Map<String, dynamic> c) =>
      (str(c['message']) ?? str(c['label']) ?? str(c['name']) ?? '').toLowerCase();

  static String? _layerFromText(String text) {
    if (text.contains('splash pipeline')) return 'splash';
    if (text.contains('device bootstrap') || text.contains('device_bootstrap')) return 'bootstrap';
    if (text.contains('firebase app check') ||
        text.contains('app check token') ||
        text.contains('app check') ||
        text.contains('attestation')) {
      return 'app_check';
    }
    if (text.contains('device security')) return 'device_security';
    if (text.contains('device guard') ||
        text.contains('deviceguard') ||
        text.contains('registration_failed') ||
        text.contains('needs_recovery') ||
        text.contains('key_id_failed')) {
      return 'device_guard';
    }
    if (text.contains('apphang') || text.contains('hang') || text.contains('timeout')) return 'hang';
    if (text.contains('/bootstrap/')) return 'bootstrap_api';
    if (text.contains('session start') || text.contains('session end')) return 'session';
    if (RegExp(r'\b(http|https)://|\b(get|post|put|patch|delete)\b').hasMatch(text) &&
        (text.contains('fail') || text.contains('error') || RegExp(r'\b[45]\d\d\b').hasMatch(text))) {
      return 'network';
    }
    return null;
  }

  static String? _bootstrapStep(String text) {
    if (text.contains('complete ok') || text.contains('tokens saved')) return 'done';
    if (text.contains('step 5') || text.contains('/bootstrap/complete')) return '5_bootstrap_complete';
    if (text.contains('step 4') || text.contains('hmac')) return '4_hmac';
    if (text.contains('step 3') || text.contains('/bootstrap/start')) return '3_bootstrap_start';
    if (text.contains('step 2') || text.contains('device identity') || text.contains('deviceguard')) {
      return '2_device_guard';
    }
    if (text.contains('step 1') || text.contains('app check preflight') || text.contains('app check')) {
      return '1_app_check';
    }
    if (text.contains('retry') || text.contains('recovery')) return 'retry';
    return null;
  }

  static bool _hasAppVersionOk(List<Map<String, dynamic>> crumbs) {
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

  static List<_FailSignal> _failureSignals(
    List<Map<String, dynamic>> crumbs,
    String message,
    String? platformCode,
    String? structuredLayer,
  ) {
    final out = <_FailSignal>[];
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
      if (layer != null && hard && layer != 'splash' && layer != 'session' && layer != 'bootstrap') {
        out.add(_FailSignal(layer: layer, index: i));
      }
      i++;
    }

    final msgLower = message.toLowerCase();
    if (platformCode == 'registration_failed' ||
        msgLower.contains('registration_failed') ||
        msgLower.contains('needs_recovery') ||
        msgLower.contains('key_id_failed')) {
      out.add(_FailSignal(layer: 'device_guard', index: 1000));
    }
    if (msgLower.contains('app check') ||
        msgLower.contains('firebase app check') ||
        msgLower.contains('attestation failed') ||
        msgLower.contains('token unavailable')) {
      out.add(_FailSignal(layer: 'app_check', index: 1001));
    }
    if (msgLower.contains('/bootstrap/') && RegExp(r'\b[45]\d\d\b').hasMatch(msgLower)) {
      out.add(_FailSignal(layer: 'bootstrap_api', index: 1002));
    }
    if (msgLower.contains('apphang') || (msgLower.contains('hang') && msgLower.contains('guard'))) {
      out.add(_FailSignal(layer: 'hang', index: 1003));
    }

    if (structuredLayer != null) {
      out.insert(0, _FailSignal(layer: structuredLayer, index: -1));
    }

    // Keep chronological unique layers (first hard failure wins for primary).
    final seen = <String>{};
    final ordered = <_FailSignal>[];
    final sorted = [...out]..sort((a, b) => a.index.compareTo(b.index));
    for (final s in sorted) {
      if (seen.add(s.layer)) ordered.add(s);
    }
    return ordered;
  }

  static bool _isRetryStorm(
    List<Map<String, dynamic>> crumbs,
    String message,
    String? attempt,
    String? outcome,
  ) {
    if (attempt == 'retry' || attempt == 'recovery') return true;
    if (outcome == 'failed_final') return true;
    final needle = message.trim().isEmpty ? null : message.toLowerCase();
    var repeats = 0;
    DateTime? firstAt;
    for (final c in crumbs) {
      final t = _crumbText(c);
      final hit = (needle != null && needle.isNotEmpty && t.contains(needle.split('(').first.trim())) ||
          t.contains('registration_failed') ||
          t.contains('token unavailable') ||
          t.contains('platformexception');
      if (!hit) continue;
      repeats++;
      final at = DateTime.tryParse(str(c['timestamp']) ?? str(c['at']) ?? '');
      firstAt ??= at;
      if (firstAt != null && at != null && at.difference(firstAt).inSeconds <= 30 && repeats >= 3) {
        return true;
      }
    }
    // Collapsed duplicate labels without timestamps.
    final labels = <String, int>{};
    for (final c in crumbs) {
      final key = _crumbText(c);
      if (key.contains('device bootstrap') ||
          key.contains('app check') ||
          key.contains('device guard') ||
          key.contains('registration_failed')) {
        labels[key] = (labels[key] ?? 0) + 1;
        if (labels[key]! >= 3) return true;
      }
    }
    return false;
  }

  static String _entrypointExplain(String? entrypoint) {
    if (entrypoint == null) return '';
    if (entrypoint.contains('recovery')) return 'cleared local bootstrap cache and retried';
    if (entrypoint.contains('retry')) return 'credentials still missing after safe path';
    if (entrypoint.contains('launch-auth')) return 'after auth check, no user session';
    if (entrypoint == 'splash' || entrypoint == 'launch') return 'splash device bootstrap';
    return entrypoint;
  }

  static List<String> _flowSteps({
    required List<Map<String, dynamic>> crumbs,
    required String message,
    required String? operation,
    required String? entrypoint,
    required String primaryLayer,
    required String? platformCode,
    required bool appVersionOk,
    required bool storm,
  }) {
    final steps = <String>[];
    if (appVersionOk) {
      steps.add('Splash/session path reaches app-version OK (200).');
    }

    // Collapse spam into ×N groups by layer/step.
    final collapsed = <({String key, String label, int n})>[];
    for (final c in crumbs) {
      final t = _crumbText(c);
      if (t.isEmpty) continue;
      final layer = _layerFromText(t);
      final step = _bootstrapStep(t);
      final key = step ?? layer ?? t;
      String label;
      if (step != null) {
        label = 'Bootstrap $step';
      } else if (layer != null) {
        label = switch (layer) {
          'splash' => 'Splash pipeline',
          'bootstrap' => 'Device bootstrap',
          'app_check' => t.contains('unavailable') || t.contains('fail')
              ? 'App Check token unavailable / failed'
              : 'App Check',
          'device_guard' => t.contains('registration_failed') || t.contains('fail')
              ? 'DeviceGuard fails'
              : 'DeviceGuard',
          'device_security' => 'Device security report',
          'session' => t.contains('end') ? 'Session end' : 'Session start',
          'network' => 'Network call',
          'bootstrap_api' => 'Bootstrap API',
          'hang' => 'Hang / timeout',
          _ => layer,
        };
      } else {
        continue; // skip noise crumbs in flow
      }
      if (collapsed.isNotEmpty && collapsed.last.key == key) {
        collapsed[collapsed.length - 1] = (
          key: key,
          label: collapsed.last.label,
          n: collapsed.last.n + 1,
        );
      } else {
        collapsed.add((key: key, label: label, n: 1));
      }
    }

    for (final g in collapsed.take(10)) {
      steps.add(g.n > 1 ? '${g.label} (×${g.n}).' : '${g.label}.');
    }

    if (platformCode == 'registration_failed' || message.toLowerCase().contains('registration_failed')) {
      if (!steps.any((s) => s.toLowerCase().contains('deviceguard fail'))) {
        steps.add('DeviceGuard fails: `registration_failed` (native message often null).');
      }
    }

    if (entrypoint != null) {
      final explain = _entrypointExplain(entrypoint);
      steps.add(
        explain.isEmpty
            ? 'Entrypoint `$entrypoint` via `$operation`.'
            : '`$operation` ($explain).',
      );
    } else if (operation != null) {
      steps.add('Operation `$operation`.');
    }

    if (storm) {
      steps.add('Same failure repeats → reported as crashing (retry storm).');
    } else if (primaryLayer != 'unknown' && steps.isEmpty) {
      steps.add('Failure classified as `$primaryLayer` from message/context.');
    }

    return steps;
  }

  static String _verdict({
    required String primaryLayer,
    required String message,
    required String? entrypoint,
    required String? operation,
    required String? platformCode,
    required bool storm,
  }) {
    final where = entrypoint != null
        ? 'Splash/bootstrap (`$entrypoint`)'
        : (operation != null ? 'Operation `$operation`' : 'Session');
    final stormBit = storm ? ' (retry storm)' : '';
    return switch (primaryLayer) {
      'device_guard' =>
        '$where failed because DeviceGuard could not enroll the hardware identity key'
            '${platformCode != null ? ' (`$platformCode`)' : ''}$stormBit.',
      'app_check' =>
        '$where failed because App Check could not obtain a token'
            '${message.toLowerCase().contains('play') ? ' (Play Integrity likely)' : ''}$stormBit.',
      'bootstrap_api' => '$where failed on the bootstrap API$stormBit.',
      'hang' => '$where hit a hang/timeout$stormBit.',
      'network' => '$where failed on a network call$stormBit.',
      _ => message.trim().isEmpty
          ? 'Failure with insufficient signals to classify the layer$stormBit.'
          : '${message.length > 140 ? '${message.substring(0, 137)}…' : message}$stormBit',
    };
  }

  static String _primaryCause(
    String layer,
    String? platformCode,
    String message,
    Map<String, dynamic> ctx,
  ) {
    final identity = _ctx(ctx, 'identity_state');
    final hw = _ctx(ctx, 'has_hw_key');
    final extra = [
      if (identity != null) 'identity_state=`$identity`',
      if (hw != null) 'has_hw_key=`$hw`',
    ].join(', ');
    return switch (layer) {
      'device_guard' =>
        'DeviceGuard Android Keystore/attestation enrollment failure'
            '${platformCode != null ? ' (`$platformCode`)' : ''}'
            '${extra.isNotEmpty ? ' — $extra' : ''}.',
      'app_check' =>
        'Firebase App Check token unavailable'
            '${_ctx(ctx, 'app_check_provider') != null ? ' (provider=${_ctx(ctx, 'app_check_provider')})' : ''}'
            '${_ctx(ctx, 'flavor') == 'dev' || (str(ctx['kDebugMode']) == 'false') ? '; on *.dev release builds this is often Play Integrity, not “Firebase down”' : ''}.',
      'bootstrap_api' => 'Bootstrap API rejected or errored the request.',
      'hang' => 'UI/app hang guard fired during bootstrap.',
      'network' => 'Network failure outside the version check path.',
      _ => message.trim().isEmpty ? 'unknown' : message,
    };
  }

  static String _contributingLine(String layer, Map<String, dynamic> ctx) => switch (layer) {
        'app_check' =>
          'App Check token unavailable'
              '${_ctx(ctx, 'app_check_provider') != null ? ' (likely ${_ctx(ctx, 'app_check_provider')} on sideloaded/dev release)' : ' (likely Play Integrity on sideloaded/dev release)'}.',
        'device_guard' => 'DeviceGuard enrollment also failed in the same loop.',
        'bootstrap_api' => 'Bootstrap API errors also present.',
        'hang' => 'Hang/timeout also observed.',
        'network' => 'Other network errors also present.',
        _ => '$layer also failed in the same session.',
      };

  static List<String> _notThis(String primaryLayer, bool appVersionOk, String message) {
    final out = <String>[];
    if (appVersionOk) out.add('Not Kong/app-version (200).');
    if (primaryLayer == 'device_guard') {
      out.add('Not Firebase Auth registration — `registration_failed` is DeviceGuard Keystore/identity enrollment.');
      out.add('Not a Dart null-pointer crash (caught PlatformException escalated to Scout).');
    }
    if (primaryLayer == 'app_check') {
      out.add('Not DeviceGuard Keystore enrollment (no registration_failed as primary).');
    }
    if (out.isEmpty) {
      out.add(message.trim().isEmpty
          ? 'Insufficient signals to rule out alternate layers.'
          : 'Do not invent stack frames or HTTP codes beyond what breadcrumbs show.');
    }
    return out;
  }

  static List<String> _nextSteps(String layer, bool storm, Map<String, dynamic> ctx) {
    final next = <String>[];
    switch (layer) {
      case 'device_guard':
        next.add(
          'Inspect DeviceGuard identity snapshot on failing devices'
          ' (`identity_state`=${_ctx(ctx, 'identity_state') ?? '?'}, `has_hw_key`=${_ctx(ctx, 'has_hw_key') ?? '?'}).',
        );
        next.add('Confirm Keystore/attestation support on the device model/OS.');
      case 'app_check':
        next.add(
          'Confirm App Check provider for this flavor'
          ' (provider=${_ctx(ctx, 'app_check_provider') ?? '?'}, kDebugMode=${_ctx(ctx, 'kDebugMode') ?? '?'}).',
        );
        next.add('On `*.dev` release builds, expect Play Integrity — not debug provider.');
      case 'bootstrap_api':
        next.add('Inspect `/bootstrap/*` request/response status and HMAC headers.');
      case 'hang':
        next.add('Profile splash bootstrap for blocking native calls; check AppHangGuard thresholds.');
      default:
        next.add('Open the Timeline breadcrumbs and confirm the first hard failure layer.');
    }
    if (storm) {
      next.add(
        'Downgrade mid-retry bootstrap failures from `crashing` to `error`/`warning`; keep `crashing` for `failed_final` only.',
      );
    } else {
      next.add('Reproduce once with structured context keys (`failure_layer`, `step`, `outcome`) for sharper summaries.');
    }
    return next;
  }
}

class _FailSignal {
  const _FailSignal({required this.layer, required this.index});
  final String layer;
  final int index;
}

class _Analysis {
  const _Analysis({
    required this.verdict,
    required this.app,
    required this.platform,
    required this.screen,
    this.screenMs,
    required this.operation,
    required this.env,
    required this.release,
    this.issueTitle,
    this.eventCount,
    this.firstSeen,
    this.lastSeen,
    required this.flow,
    required this.primaryCause,
    required this.contributing,
    required this.notThis,
    required this.amplification,
    required this.next,
    required this.failureLayer,
    required this.isStorm,
  });

  factory _Analysis.emptyIssue(Map<String, dynamic> issue) => _Analysis(
        verdict: 'Issue `${issue['title'] ?? 'unknown'}` has no loaded events to interpret.',
        app: 'unknown',
        platform: 'unknown',
        screen: 'unknown',
        operation: 'unknown',
        env: 'unknown',
        release: 'unknown',
        issueTitle: str(issue['title']),
        eventCount: (issue['eventCount'] as num?)?.toInt(),
        firstSeen: str(issue['firstSeenAt']),
        lastSeen: str(issue['lastSeenAt']),
        flow: const [],
        primaryCause: 'unknown',
        contributing: const [],
        notThis: const ['No event payloads available.'],
        amplification: const [],
        next: const ['Open a member event and regenerate the summary.'],
        failureLayer: 'unknown',
        isStorm: ((issue['eventCount'] as num?)?.toInt() ?? 0) >= 10,
      );

  _Analysis forIssue(Map<String, dynamic> issue, List<_Analysis> analyses) {
    final layers = analyses.map((a) => a.failureLayer).where((l) => l != 'unknown').toList();
    final storm = isStorm ||
        analyses.any((a) => a.isStorm) ||
        ((issue['eventCount'] as num?)?.toInt() ?? 0) >= 10;
    final contrib = <String>{
      ...contributing,
      for (final a in analyses.skip(1))
        if (a.failureLayer != failureLayer && a.failureLayer != 'unknown')
          SmartIssueSummary._contributingLine(a.failureLayer, const {}),
    };
    return _Analysis(
      verdict: verdict,
      app: app,
      platform: platform,
      screen: screen,
      screenMs: screenMs,
      operation: operation,
      env: env,
      release: release,
      issueTitle: str(issue['title']) ?? issueTitle,
      eventCount: (issue['eventCount'] as num?)?.toInt() ?? eventCount,
      firstSeen: str(issue['firstSeenAt']) ?? firstSeen,
      lastSeen: str(issue['lastSeenAt']) ?? lastSeen,
      flow: flow,
      primaryCause: primaryCause,
      contributing: contrib.toList(),
      notThis: notThis,
      amplification: storm
          ? [
              'Issue spans ${issue['eventCount'] ?? analyses.length} events'
                  '${layers.isNotEmpty ? '; dominant layers: ${layers.toSet().join(', ')}' : ''}.',
              'Clear-session + retry loop may report the same failure many times as `crashing`.',
            ]
          : amplification,
      next: [
        ...next.where((s) => !s.contains('Downgrade mid-retry')),
        if (storm)
          'Downgrade mid-retry bootstrap failures from `crashing` to `error`/`warning`; keep `crashing` for `failed_final` only.',
      ],
      failureLayer: failureLayer,
      isStorm: storm,
    );
  }

  final String verdict;
  final String app;
  final String platform;
  final String screen;
  final String? screenMs;
  final String operation;
  final String env;
  final String release;
  final String? issueTitle;
  final int? eventCount;
  final String? firstSeen;
  final String? lastSeen;
  final List<String> flow;
  final String primaryCause;
  final List<String> contributing;
  final List<String> notThis;
  final List<String> amplification;
  final List<String> next;
  final String failureLayer;
  final bool isStorm;
}
