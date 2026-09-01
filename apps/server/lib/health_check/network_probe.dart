import 'dart:async';
import 'dart:io';

const networkProbeTimeout = Duration(seconds: 10);

/// Unique https origins found in a health-check script (config URLs, endpoint strings).
List<String> extractProbeUrls(String script) {
  final found = <String>{};
  final re = RegExp(r'''https?://[^\s'")\]]+''');
  for (final m in re.allMatches(script)) {
    var raw = m.group(0)!;
    while (raw.endsWith(',') || raw.endsWith(';') || raw.endsWith('.')) {
      raw = raw.substring(0, raw.length - 1);
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) continue;
    found.add(raw);
  }
  return found.toList()..sort();
}

/// One sample URL per host (shortest path first for stable probe target).
Map<String, String> hostsToSampleUrl(List<String> urls) {
  final byHost = <String, String>{};
  for (final url in urls) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) continue;
    final host = uri.host.toLowerCase();
    final existing = byHost[host];
    if (existing == null || url.length < existing.length) byHost[host] = url;
  }
  return byHost;
}

Future<Map<String, dynamic>> probeHost({
  required String host,
  required String sampleUrl,
  Duration timeout = networkProbeTimeout,
}) async {
  final sw = Stopwatch()..start();
  String? resolvedIps;
  try {
    final addrs = await InternetAddress.lookup(host).timeout(timeout);
    resolvedIps = addrs.map((a) => a.address).join(', ');
  } catch (e) {
    sw.stop();
    return {
      'host': host,
      'sampleUrl': sampleUrl,
      'status': 'fail',
      'latencyMs': sw.elapsedMilliseconds,
      'detail': 'DNS failed: $e',
      if (resolvedIps != null) 'resolvedIps': resolvedIps,
    };
  }

  try {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    final uri = Uri.parse(sampleUrl);
    final req = await client.headUrl(uri).timeout(timeout);
    final res = await req.close().timeout(timeout);
    sw.stop();
    final code = res.statusCode;
    await res.drain();
    client.close(force: true);
    final ok = code > 0; // any HTTP response = reachable (405 on HEAD is fine)
    return {
      'host': host,
      'sampleUrl': sampleUrl,
      'status': ok ? 'ok' : 'fail',
      'latencyMs': sw.elapsedMilliseconds,
      'detail': 'HTTP $code (HEAD)',
      'resolvedIps': resolvedIps,
    };
  } on TimeoutException {
    sw.stop();
    return {
      'host': host,
      'sampleUrl': sampleUrl,
      'status': 'timeout',
      'latencyMs': sw.elapsedMilliseconds,
      'detail': 'TimeoutException after ${timeout.inSeconds}s (no response from this server)',
      'resolvedIps': resolvedIps,
    };
  } catch (e) {
    // HEAD may be rejected — retry GET with short timeout
    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;
      final req = await client.getUrl(Uri.parse(sampleUrl)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      sw.stop();
      final code = res.statusCode;
      await res.drain();
      client.close(force: true);
      return {
        'host': host,
        'sampleUrl': sampleUrl,
        'status': 'ok',
        'latencyMs': sw.elapsedMilliseconds,
        'detail': 'HTTP $code (GET fallback)',
        'resolvedIps': resolvedIps,
      };
    } catch (e2) {
      sw.stop();
      return {
        'host': host,
        'sampleUrl': sampleUrl,
        'status': 'timeout',
        'latencyMs': sw.elapsedMilliseconds,
        'detail': '$e2',
        'resolvedIps': resolvedIps,
      };
    }
  }
}

/// Probes each unique host referenced in [script] from the Scout server process.
Future<Map<String, dynamic>> runNetworkProbe(String script) async {
  final urls = extractProbeUrls(script);
  final hostMap = hostsToSampleUrl(urls);
  final probes = <Map<String, dynamic>>[];

  for (final entry in hostMap.entries) {
    probes.add(await probeHost(host: entry.key, sampleUrl: entry.value));
  }

  final ok = probes.where((p) => p['status'] == 'ok').length;
  final timeout = probes.where((p) => p['status'] == 'timeout').length;
  final fail = probes.where((p) => p['status'] == 'fail').length;
  final total = probes.length;

  String summary;
  if (total == 0) {
    summary = 'No https URLs found in script to probe';
  } else if (timeout + fail == 0) {
    summary = '$ok/$total hosts reachable from Scout server';
  } else {
    summary = '$ok/$total hosts reachable · $timeout timeout · $fail fail';
  }

  String? scoutHost;
  try {
    scoutHost = Platform.localHostname;
  } catch (_) {}

  return {
    'probedAt': DateTime.now().toUtc().toIso8601String(),
    if (scoutHost != null && scoutHost.isNotEmpty) 'scoutHost': scoutHost,
    'summary': summary,
    'probes': probes,
    'hint': timeout > 0 || fail > 0
        ? 'Timeouts from Scout but OK in the mobile app usually mean geo/IP firewall — this server may not be on an allowed network.'
        : null,
  };
}

Map<String, dynamic> mergeReportWithProbe(
  Map<String, dynamic>? report,
  Map<String, dynamic> probe,
) {
  final base = report != null ? Map<String, dynamic>.from(report) : <String, dynamic>{
    'verdict': 'unhealthy',
    'summary': probe['summary'],
    'checks': <dynamic>[],
  };
  base['networkProbe'] = probe;
  return base;
}
