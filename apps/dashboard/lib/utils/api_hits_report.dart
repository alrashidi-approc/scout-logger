import 'package:intl/intl.dart';

import '../services/api_client.dart';

/// Share of all calls at which an endpoint is flagged as high volume.
const highVolumeShare = 0.10;

/// Error rate (with at least [minCallsForErrorFlag] calls) at which an endpoint is flagged.
const highErrorRate = 0.05;
const minCallsForErrorFlag = 10;

/// Reasons the counts in an `/api-hits` response may be lower than the real number of calls.
List<String> apiHitsCoverageWarnings(Map<String, dynamic> data) {
  final c = data['coverage'] is Map ? Map<String, dynamic>.from(data['coverage'] as Map) : const <String, dynamic>{};
  final scope = c['networkLogScope'] as String? ?? 'all';
  final ignored = (c['ignoredStatusCodes'] as List?) ?? const [];
  final cutoff = DateTime.tryParse('${c['incompleteBefore']}');
  return [
    if (scope == 'errorsOnly')
      'SDK network log scope is "errors only": successful calls are not sent to Scout, so only failed calls are counted.',
    if (scope == 'slowOnly')
      'SDK network log scope is "slow only": fast calls are not sent to Scout, so only slow calls are counted.',
    if (ignored.isNotEmpty) 'Calls answered with HTTP ${ignored.join(', ')} are ignored by the SDK and not counted.',
    if (cutoff != null)
      'Successful calls older than ${c['retentionDays']} days are deleted by retention; '
          'before ${DateFormat('MMM d, yyyy HH:mm').format(cutoff.toUtc())} UTC only failed calls remain.',
  ];
}

/// Markdown report of an `/api-hits` response, written for the app's developer.
String buildApiHitsMarkdown({
  required String projectName,
  required Map<String, dynamic> data,
  DateTime? generatedAt,
}) {
  final hourly = data['bucket'] == 'hour';
  final range = data['range'] is Map ? Map<String, dynamic>.from(data['range'] as Map) : const <String, dynamic>{};
  final zone = range['tz'] as String? ?? 'UTC';
  final from = DateTime.tryParse('${range['from']}');
  final to = DateTime.tryParse('${range['to']}');
  final warnings = apiHitsCoverageWarnings(data);
  final unit = hourly ? 'hour' : 'day';
  final series = jsonListMaps(data['series']);
  final endpoints = jsonListMaps(data['endpoints']);
  final totals = data['totals'] is Map ? Map<String, dynamic>.from(data['totals'] as Map) : const {};
  final total = totals['hits'] as int? ?? 0;
  final errors = totals['errors'] as int? ?? 0;
  final buckets = series.isEmpty ? 1 : series.length;
  final filter = data['endpoint'] as String?;
  final fmt = NumberFormat.decimalPattern();
  final when = DateFormat(hourly ? 'MMM d, HH:mm' : 'EEE MMM d');

  String pct(int part, int whole) => whole == 0 ? '0%' : '${(part / whole * 100).toStringAsFixed(1)}%';
  String rate(int hits) => (hits / buckets).toStringAsFixed(hits / buckets < 10 ? 1 : 0);
  String code(Object? s) => '`${'$s'.replaceAll('|', r'\|').replaceAll('`', "'")}`';
  // Point dates are local wall-clock times in [zone]; format them as-is.
  DateTime? at(Map<String, dynamic> p) => DateTime.tryParse('${p['date']}');
  final dayFmt = DateFormat('EEE MMM d, yyyy');

  final peak = series.fold<Map<String, dynamic>?>(
    null,
    (best, p) => (p['events'] as int? ?? 0) > (best?['events'] as int? ?? 0) ? p : best,
  );
  final peakAt = peak == null ? null : at(peak);

  final highVolume = [
    for (final e in endpoints)
      if (total > 0 && (e['hits'] as int? ?? 0) / total >= highVolumeShare) e,
  ];
  final failing = [
    for (final e in endpoints)
      if ((e['hits'] as int? ?? 0) >= minCallsForErrorFlag &&
          (e['errors'] as int? ?? 0) / (e['hits'] as int) >= highErrorRate)
        e,
  ];

  final b = StringBuffer()
    ..writeln('# API calls report: $projectName')
    ..writeln()
    ..writeln('- **Period:** ${from == null || to == null ? '—' : from == to ? dayFmt.format(from) : '${dayFmt.format(from)} to ${dayFmt.format(to)}'}'
        ', 12:00 AM to 12:00 AM ($zone)')
    ..writeln('- **Generated:** ${DateFormat('MMM d, yyyy HH:mm').format((generatedAt ?? DateTime.now()).toUtc())} UTC')
    ..writeln('- **Scope:** ${filter == null ? 'all endpoints' : code(filter)}')
    ..writeln('- **Source:** network calls reported by the Scout SDK inside the app')
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---|')
    ..writeln('| Total API calls | ${fmt.format(total)} |')
    ..writeln('| Average per $unit | ${rate(total)} |')
    ..writeln('| Busiest $unit | ${peakAt == null ? '—' : '${fmt.format(peak?['events'] ?? 0)} on ${when.format(peakAt)}'} |')
    ..writeln('| Failed calls | ${fmt.format(errors)} (${pct(errors, total)}) |')
    ..writeln('| Distinct endpoints | ${endpoints.length}${endpoints.length >= 100 ? ' (top 100 listed)' : ''} |')
    ..writeln();

  if (warnings.isNotEmpty) {
    b
      ..writeln('> **Counts may be incomplete**')
      ..writeln('>');
    for (final w in warnings) {
      b.writeln('> - $w');
    }
    b.writeln();
  }

  b
    ..writeln('## Calls per endpoint')
    ..writeln();

  if (endpoints.isEmpty) {
    b.writeln('_No API calls in this period._');
  } else {
    b
      ..writeln('| # | Method | Endpoint | Calls | Per $unit | Share of all calls | Failed | Failure rate |')
      ..writeln('|---:|---|---|---:|---:|---:|---:|---:|');
    for (final (i, e) in endpoints.indexed) {
      final hits = e['hits'] as int? ?? 0;
      final failed = e['errors'] as int? ?? 0;
      b.writeln('| ${i + 1} | ${e['method']} | ${code(e['path'])} | ${fmt.format(hits)} | ${rate(hits)} | '
          '${pct(hits, total)} | ${fmt.format(failed)} | ${pct(failed, hits)} |');
    }
  }

  b
    ..writeln()
    ..writeln('## Calls over time (${hourly ? 'hourly' : 'daily'}, $zone)')
    ..writeln()
    ..writeln('| ${hourly ? 'Hour' : 'Day'} | Calls | Failed |')
    ..writeln('|---|---:|---:|');
  for (final p in series) {
    final t = at(p);
    b.writeln('| ${t == null ? p['date'] : when.format(t)} | ${fmt.format(p['events'] ?? 0)} | ${fmt.format(p['errors'] ?? 0)} |');
  }

  b
    ..writeln()
    ..writeln('## Where to look first')
    ..writeln();
  if (highVolume.isEmpty && failing.isEmpty) {
    b.writeln('No endpoint stands out: none takes ≥ ${(highVolumeShare * 100).round()}% of all calls '
        'or fails ≥ ${(highErrorRate * 100).round()}% of the time.');
  }
  for (final e in highVolume) {
    b.writeln('- ${code(e['key'])}: ${pct(e['hits'] as int, total)} of all calls '
        '(${rate(e['hits'] as int)} per $unit). Check whether it is called more often than the data changes.');
  }
  for (final e in failing) {
    b.writeln('- ${code(e['key'])}: ${pct(e['errors'] as int, e['hits'] as int)} of calls fail. '
        'Failed calls are often retried, which adds traffic.');
  }

  b
    ..writeln()
    ..writeln('## Questions for the app developer')
    ..writeln()
    ..writeln('For each endpoint above:')
    ..writeln()
    ..writeln('- [ ] Is the response cached (memory or disk) and reused, or fetched every time a screen opens?')
    ..writeln('- [ ] Is the same request fired more than once at the same time (widget rebuilds, duplicate listeners)?')
    ..writeln('- [ ] Is there polling or a timer? Can the interval be longer, or replaced by push or refresh-on-demand?')
    ..writeln('- [ ] Can several calls be combined into one request?')
    ..writeln('- [ ] Are failed calls retried? Is there backoff and a retry limit?')
    ..writeln('- [ ] Is user input (search, validation) debounced before calling the API?')
    ..writeln()
    ..writeln('## How these numbers are counted')
    ..writeln()
    ..writeln('- One count per call the app made, as reported by the Scout SDK. Query parameters and request body are ignored.')
    ..writeln('- Each call is placed at the time it happened on the device (calls sent later from offline storage keep their '
        'original time). If the device clock is more than 5 minutes ahead, the time Scout received it is used.')
    ..writeln('- Days run 12:00 AM to 12:00 AM in $zone.')
    ..writeln('- Path segments that are numbers or UUIDs are grouped as `:id` (e.g. `/users/123` → `/users/:id`).')
    ..writeln('- "Failed" means a network error or an HTTP error the project treats as a real failure.')
    ..writeln('- SDK settings checked are the ones saved in Scout; options hard-coded in the app (e.g. ignored status codes) '
        'can also drop calls.');

  return b.toString();
}
