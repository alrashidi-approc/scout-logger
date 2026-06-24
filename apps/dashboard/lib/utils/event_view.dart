import 'dart:convert';

import 'package:scout_models/scout_models.dart';

import 'geo_source.dart';
import 'user_identity.dart';

Map<String, dynamic> asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : {};

String? str(dynamic v) => v?.toString();

class EventView {
  EventView(this.event);

  final Map<String, dynamic> event;

  Map<String, dynamic> get payload => asMap(event['payload']);
  Map<String, dynamic> get enrichment => asMap(event['enrichment']);
  Map<String, dynamic> get geo => asMap(enrichment['geo']);
  Map<String, dynamic> get user => asMap(payload['user']);
  Map<String, dynamic> get device => asMap(payload['device']);
  Map<String, dynamic> get deviceGeo {
    final nested = asMap(device['geo']);
    return nested.isEmpty ? device : {...device, ...nested};
  }
  Map<String, dynamic> get screen => asMap(payload['screen']);
  Map<String, dynamic> get network => asMap(payload['network']);
  Map<String, dynamic> get networkReadable => network.isEmpty ? {} : networkReadableFrom(network);
  String get networkOutcome => str(networkReadable['faultLabel']) ?? str(networkReadable['outcomeLabel']) ?? '—';
  NetworkFaultInfo? get networkFault => NetworkFaultInfo.fromJson(networkReadable['fault']);
  Map<String, dynamic> get custom => asMap(payload['custom']);
  Map<String, dynamic>? get issue => event['issue'] is Map ? Map<String, dynamic>.from(event['issue'] as Map) : null;

  String get type => str(event['type']) ?? 'error';
  String get level => str(payload['level']) ?? (type == 'log' ? 'info' : type);
  String get category => str(payload['category']) ?? (type == 'network' ? 'network' : type == 'crash' ? 'crashing' : '');
  String get message {
    if (network.isNotEmpty) {
      final title = str(networkReadable['title']);
      if (title != null) return title;
    }
    return str(payload['message']) ?? str(asMap(payload['overview'])['title']) ?? str(event['message']) ?? type;
  }
  String get stack => str(payload['stack']) ?? str(payload['stackTrace']) ?? str(payload['stacktrace']) ?? '';
  String get release {
    final rel = payload['release'];
    if (rel is Map) return str(rel['name']) ?? str(rel['version']) ?? '—';
    return str(event['release']) ?? str(rel) ?? '—';
  }
  String get environment => str(event['environment']) ?? str(payload['environment']) ?? '—';
  String get platform => str(device['platform']) ?? str(event['platform']) ?? '—';
  String get appVersion => str(device['version']) ?? str(device['appVersion']) ?? str(event['appVersion']) ?? '—';
  String get userId => str(user['id']) ?? str(user['userId']) ?? str(event['userId']) ?? '—';
  String get userEmail => str(user['email']) ?? userEmailFromPayload(payload) ?? '—';
  String get installId => str(event['installId']) ?? installIdFromPayload(payload) ?? '—';
  bool get isGuestUser => isGuestAppUser(userId: userId == '—' ? null : userId, installId: installId == '—' ? null : installId);
  String get sessionId => str(user['sessionId']) ?? str(event['sessionId']) ?? '—';
  String get route => str(screen['currentRoute']) ?? str(payload['route']) ?? str(payload['screen']) ?? '—';
  String get country {
    final name = str(geo['countryName']);
    if (name != null && name != 'Local' && name != 'Unknown') return name;
    final code = str(event['country']) ?? str(geo['country']);
    if (code == null || code == 'LO' || code == '??') return '—';
    return name ?? code;
  }

  String? get connectionCountryCode {
    final code = str(event['country']) ?? str(geo['country']);
    if (code == null || code == 'LO' || code == '??') return null;
    return code.toUpperCase();
  }

  String get localeCountry {
    final code = str(geo['localeCountry']) ?? str(deviceGeo['localeCountry']) ?? str(deviceGeo['countryCode']);
    if (code == null || code.isEmpty) {
      final locale = str(deviceGeo['locale']);
      if (locale != null && locale.contains('-')) {
        final part = locale.split('-').last;
        if (part.length == 2) return part.toUpperCase();
      }
      return '—';
    }
    return code.toUpperCase();
  }

  String get locationLabel => locationFactLabel(
        connectionCode: connectionCountryCode,
        localeCode: localeCountry != '—' ? localeCountry : null,
        city: city,
      );

  String get city => str(event['city']) ?? str(geo['city']) ?? '—';
  String get geoSource => str(geo['source']) ?? 'ip';
  String get method => str(network['method']) ?? str(payload['method']) ?? '';
  String get url => str(network['url']) ?? str(network['path']) ?? str(payload['url']) ?? '';
  String get statusCode => str(network['statusCode']) ?? str(payload['statusCode']) ?? '';

  List<Map<String, dynamic>> get breadcrumbs {
    final raw = payload['breadcrumbs'] ?? payload['screenTrail'] ?? payload['userFlow'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => _normalizeCrumb(Map<String, dynamic>.from(e))).toList();
  }

  static Map<String, dynamic> _normalizeCrumb(Map<String, dynamic> step) {
    final route = str(step['route']);
    final screenName = str(step['screenName']);
    final message = str(step['message']);
    final label = str(step['label']) ?? str(step['name']) ?? screenName ?? message ?? route ?? 'step';
    final at = str(step['timestamp']) ?? str(step['at']) ?? str(step['time']);
    final nav = parseNavTransition(step);
    return {
      ...step,
      'label': label,
      'name': label,
      if (route != null) 'route': route,
      'navigationType': nav.isKnown ? nav.wire : str(step['navigationType']),
      'navigationLabel': nav.label,
      'hasNavigationType': nav.isKnown,
      if (at != null) ...{'timestamp': at, 'at': at},
    };
  }

  bool get breadcrumbsMissingNavType =>
      breadcrumbs.isNotEmpty && breadcrumbs.any((s) => s['hasNavigationType'] != true);

  Map<String, dynamic> get overview => asMap(payload['overview']);
  Map<String, dynamic> get context => asMap(payload['context']);

  List<DetailField> releaseFields() => [
        DetailField('Release', release, mono: true, highlight: true),
        DetailField('Environment', environment, highlight: true),
        DetailField('Platform', platform),
        DetailField('App version', appVersion),
        DetailField('Package / bundle', str(payload['packageName']) ?? str(payload['bundleId']) ?? '—', mono: true),
        DetailField('Event ID', str(event['id']) ?? '—', mono: true),
        DetailField('Occurred', str(event['occurredAt']) ?? '—'),
        DetailField('Received', str(enrichment['receivedAt']) ?? str(event['createdAt']) ?? '—'),
      ];

  List<DetailField> deviceFields() => [
        DetailField('Device name', str(device['deviceName']) ?? '—', highlight: true),
        DetailField('Platform', platform, highlight: true),
        DetailField('OS version', str(device['osVersion']) ?? '—'),
        DetailField('Model', '${str(device['manufacturer']) ?? ''} ${str(device['deviceModel']) ?? ''}'.trim().isEmpty ? '—' : '${str(device['manufacturer']) ?? ''} ${str(device['deviceModel']) ?? ''}'.trim()),
        if (device['isSimulator'] == true) DetailField('Simulator', 'Yes'),
        if (device['ramTotalMb'] != null) DetailField('RAM', '${device['ramFreeMb'] ?? '?'}/${device['ramTotalMb']} MB'),
        if (device['diskFreeMb'] != null) DetailField('Disk free', '${device['diskFreeMb']} MB'),
        DetailField('Dark mode', device['darkMode'] == true ? 'Yes' : 'No'),
        if (deviceGeo['timezone'] != null) DetailField('Timezone', str(deviceGeo['timezone'])!),
        if (deviceGeo['locale'] != null) DetailField('Locale', str(deviceGeo['locale'])!),
        if (deviceGeo['languageCode'] != null) DetailField('Language', str(deviceGeo['languageCode'])!),
        if (deviceGeo['localeCountry'] != null || deviceGeo['countryCode'] != null)
          DetailField('Locale region', str(deviceGeo['localeCountry']) ?? str(deviceGeo['countryCode'])!),
        if (deviceGeo['country'] != null && deviceGeo['countrySource'] != null)
          DetailField('Geo package', '${deviceGeo['country']} (${str(deviceGeo['countrySource'])})'),
        if (device['installId'] != null) DetailField('Install ID', str(device['installId'])!, mono: true),
        if (device['anonymousId'] != null && device['anonymousId'] != device['installId'])
          DetailField('Anonymous ID', str(device['anonymousId'])!, mono: true),
        if (device['launchCount'] != null) DetailField('Launch #', '${device['launchCount']}'),
        if (device['daysSinceInstall'] != null) DetailField('Days since install', '${device['daysSinceInstall']}'),
        DetailField('Device ID', str(device['id']) ?? str(device['deviceId']) ?? '—', mono: true),
        DetailField('App version', appVersion),
        DetailField('Battery', str(device['batteryLevel']) != null ? '${((double.tryParse(device['batteryLevel'].toString()) ?? 0) * 100).round()}%' : '—'),
        DetailField('Online', str(device['isOnline']) ?? str(asMap(device['connectivity'])['isOnline']) ?? '—'),
      ];

  List<DetailField> userFields() => [
        DetailField('User ID', userId, mono: true, highlight: true),
        if (userEmail != '—') DetailField('Email', userEmail, highlight: true),
        if (installId != '—') DetailField('Install ID', installId, mono: true),
        if (isGuestUser) DetailField('Account', 'Guest (device id)', highlight: true),
        DetailField('Session ID', sessionId, mono: true),
        DetailField('Connection country', country),
        if (localeCountry != '—' && localeCountry != connectionCountryCode)
          DetailField('Locale region', localeCountry),
        DetailField('City', city),
        DetailField('IP hash', str(enrichment['clientIpHash']) ?? '—', mono: true),
        ..._extraMap(user, skip: {'id', 'userId', 'sessionId', 'email', 'installId', 'anonymousId'}),
      ];

  Map<String, dynamic> get sessionSummary =>
      payload['summary'] is Map ? Map<String, dynamic>.from(payload['summary'] as Map) : {};

  List<DetailField> screenFields() => [
        DetailField('Current screen', route, highlight: true),
        if (screen['currentScreenMs'] != null) DetailField('Time on screen', '${screen['currentScreenMs']} ms'),
        DetailField('Level', level.toUpperCase(), highlight: true),
        if (category.isNotEmpty) DetailField('Category', category, highlight: true),
        if (type == 'session' && str(payload['durationMs']) != null)
          DetailField('Session duration', _fmtDuration(payload['durationMs']), highlight: true),
        if (type == 'session' && str(payload['action']) != null)
          DetailField('Session action', str(payload['action'])!, highlight: true),
        if (type == 'session' && sessionSummary.isNotEmpty) ...[
          if (sessionSummary['screensVisited'] != null)
            DetailField('Screens visited', '${sessionSummary['screensVisited']}'),
          if (sessionSummary['networkCalls'] != null)
            DetailField('Network calls', '${sessionSummary['networkCalls']}'),
          if (sessionSummary['errors'] != null) DetailField('Errors', '${sessionSummary['errors']}'),
          if (sessionSummary['actions'] != null) DetailField('User actions', '${sessionSummary['actions']}'),
          if (sessionSummary['longestScreen'] != null)
            DetailField('Longest screen', '${sessionSummary['longestScreen']} (${sessionSummary['longestScreenMs']} ms)'),
        ],
        DetailField('Transport type', type),
        DetailField('Message', message),
      ];

  List<String> networkSummaryLines() {
    if (network.isEmpty) return [];
    final lines = networkReadable['lines'];
    if (lines is List) return lines.whereType<String>().toList();
    return summaryLines().where((l) => l.startsWith('Network:')).toList();
  }

  List<DetailField> networkFields() {
    if (method.isEmpty && url.isEmpty && statusCode.isEmpty && type != 'network') return [];
    final hasResponse = network['hasResponse'] == true || statusCode.isNotEmpty;
    final responseText = _networkResponseText();
    return [
      if (method.isNotEmpty) DetailField('Method', method, highlight: true),
      if (url.isNotEmpty) DetailField('URL / path', url, mono: true, highlight: true),
      if (statusCode.isNotEmpty) DetailField('Status code', statusCode, highlight: true),
      if (!hasResponse && type == 'network') DetailField('Response', 'No response received', highlight: true),
      if (network['errorType'] != null) DetailField('Error type', str(network['errorType'])!, highlight: true),
      if (network['error'] != null) DetailField('Error', str(network['error'])!),
      if (responseText != null) DetailField('Network response', responseText, mono: true, block: true),
      if (network['durationMs'] != null) DetailField('Duration', '${network['durationMs']} ms'),
      if (network['slow'] == true)
        DetailField('Slow request', 'Yes (≥ ${network['slowThresholdMs'] ?? '—'} ms)', highlight: true),
      if (network['traceId'] != null) DetailField('Trace ID', str(network['traceId'])!, mono: true),
      if (network['curl'] != null) DetailField('cURL', str(network['curl'])!, mono: true),
    ];
  }

  String? _networkResponseText() {
    final resp = asMap(network['response']);
    if (resp.isEmpty) return null;

    final out = <String, dynamic>{...resp};
    final body = out.remove('body');
    if (body != null) out['body'] = _parseBody(body);

    if (out.isEmpty) return null;
    try {
      return const JsonEncoder.withIndent('  ').convert(out);
    } catch (_) {
      return out.toString();
    }
  }

  static dynamic _parseBody(dynamic body) {
    if (body is! String) return body;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return body;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return body;
    }
  }

  List<DetailField> issueFields() {
    final i = issue;
    if (i == null) return [];
    return [
      DetailField('Issue title', str(i['title']) ?? '—', highlight: true),
      DetailField('Status', str(i['status']) ?? '—'),
      DetailField('Events in group', str(i['eventCount']) ?? '—'),
      DetailField('Fingerprint', str(i['fingerprint']) ?? '—', mono: true),
      DetailField('First seen', str(i['firstSeenAt']) ?? '—'),
      DetailField('Last seen', str(i['lastSeenAt']) ?? '—'),
    ];
  }

  List<DetailField> customFields() {
    const known = {
      'message', 'stack', 'stackTrace', 'stacktrace', 'release', 'environment', 'level', 'category',
      'user', 'device', 'screen', 'network', 'method', 'url', 'statusCode', 'route', 'breadcrumbs',
      'userFlow', 'screenTrail', 'custom', 'context', 'overview', 'session',
    };
    final out = <DetailField>[];
    for (final e in payload.entries) {
      if (known.contains(e.key)) continue;
      out.add(DetailField(e.key, _fmt(e.value), mono: e.value is Map || e.value is List));
    }
    out.addAll(_extraMap(custom));
    return out;
  }

  List<String> summaryLines() => [
        'Level: ${level.toUpperCase()}${category.isNotEmpty ? ' · $category' : ''}',
        if (environment != '—') 'Environment: $environment',
        if (route != '—') 'User was on screen: $route',
        if (breadcrumbs.isNotEmpty) 'Screen trail: ${breadcrumbs.length} steps',
        if (breadcrumbsMissingNavType)
          'Note: navigation type (push/pop/…) not recorded — update scout_logger_plus screenTrail',
        if (platform != '—') 'Platform: $platform · $appVersion',
        if (userId != '—') 'User ID: $userId',
        if (country != '—')
          'Location: $locationLabel (${eventGeoSourceLabel(geoSource)})',
        ...networkSummaryLines(),
        if (issue != null) 'Grouped with ${issue!['eventCount']} similar events',
      ];

  List<DetailField> _extraMap(Map<String, dynamic> map, {Set<String> skip = const {}}) {
    final out = <DetailField>[];
    for (final e in map.entries) {
      if (skip.contains(e.key)) continue;
      out.add(DetailField(e.key, _fmt(e.value), mono: e.value is Map || e.value is List));
    }
    return out;
  }

  static String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is Map || v is List) return const JsonEncoder.withIndent('  ').convert(v);
    return v.toString();
  }

  static String _fmtDuration(dynamic ms) {
    final totalSec = ((ms is num ? ms.toInt() : int.tryParse('$ms')) ?? 0) ~/ 1000;
    if (totalSec < 60) return '${totalSec}s';
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    if (m < 60) return s == 0 ? '${m}m' : '${m}m ${s}s';
    final h = m ~/ 60;
    final rm = m % 60;
    return rm == 0 ? '${h}h' : '${h}h ${rm}m';
  }
}

class DetailField {
  DetailField(this.label, this.value, {this.mono = false, this.highlight = false, this.block = false});
  final String label;
  final String value;
  final bool mono;
  final bool highlight;
  /// Full-width stacked layout (e.g. network response body).
  final bool block;
}

String prettyJson(dynamic v) {
  if (v == null) return '';
  try {
    return const JsonEncoder.withIndent('  ').convert(v);
  } catch (_) {
    return v.toString();
  }
}

String bugReport(EventView v, String projectId) {
  final buf = StringBuffer()
    ..writeln('Scout Logger — Bug Report')
    ..writeln('Project: $projectId')
    ..writeln('Event: ${v.event['id']}')
    ..writeln('Time: ${v.event['occurredAt']}')
    ..writeln()
    ..writeln('## Summary')
    ..writeln(v.message)
    ..writeln()
    ..writeln('## Environment')
    ..writeln('Release: ${v.release}')
    ..writeln('Platform: ${v.platform} ${v.appVersion}')
    ..writeln('User: ${v.userId}')
    ..writeln();
  if (v.stack.isNotEmpty) {
    buf.writeln('## Stack trace');
    buf.writeln(v.stack);
    buf.writeln();
  }
  buf.writeln('## Payload');
  buf.writeln(prettyJson(v.payload));
  return buf.toString();
}
