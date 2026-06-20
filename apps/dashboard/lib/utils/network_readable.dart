Map<String, dynamic> networkReadableFrom(Map<String, dynamic> network) {
  final stored = network['readable'] is Map ? Map<String, dynamic>.from(network['readable'] as Map) : <String, dynamic>{};
  if (stored.isNotEmpty) return stored;

  final method = network['method']?.toString() ?? 'REQUEST';
  final url = network['url']?.toString() ?? network['path']?.toString() ?? '';
  if (url.isEmpty) return {};
  final statusCode = int.tryParse('${network['statusCode'] ?? ''}');
  final hasResponse = network['hasResponse'] == true || statusCode != null;
  final error = network['error']?.toString();
  final errorType = network['errorType']?.toString();
  final durationMs = network['durationMs'];

  final outcome = !hasResponse
      ? 'no_response'
      : statusCode != null && statusCode >= 400
          ? 'http_error'
          : error != null
              ? 'failed'
              : 'success';

  final path = _shortUrl(url);
  final duration = durationMs is num ? _fmtMs(durationMs.toInt()) : null;
  final title = switch (outcome) {
    'success' => '$method $path succeeded (${statusCode ?? 'OK'})',
    'http_error' => '$method $path failed with HTTP $statusCode',
    'no_response' => '$method $path — no response${errorType != null ? ' ($errorType)' : ''}',
    _ => '$method $path failed',
  };

  return {
    'title': title,
    'outcome': outcome,
    'outcomeLabel': _outcomeLabel(outcome),
    'lines': [
      'The app sent a $method request to $url.',
      if (hasResponse)
        'Server responded with HTTP $statusCode.'
      else
        'No response was received${error != null ? ' — $error' : ''}.',
      if (duration != null) 'Completed in $duration.',
    ],
    'request': {
      'method': method,
      'url': url,
      'path': path,
      'summary': '$method $path',
    },
    'response': {
      'hasResponse': hasResponse,
      if (statusCode != null) 'statusCode': statusCode,
      'summary': hasResponse ? _statusLabel(statusCode ?? 0) : (error ?? 'No response'),
      if (error != null) 'error': error,
      if (errorType != null) 'errorType': errorType,
    },
    if (duration != null) 'duration': duration,
  };
}

String _shortUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final path = uri.path.isEmpty ? '/' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}

String _fmtMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  final sec = ms / 1000;
  return sec >= 10 ? '${sec.round()}s' : '${sec.toStringAsFixed(1)}s';
}

String _outcomeLabel(String outcome) => switch (outcome) {
      'success' => 'Success',
      'http_error' => 'HTTP error',
      'no_response' => 'No response',
      _ => 'Failed',
    };

String _statusLabel(int code) {
  if (code >= 500) return 'Server error';
  if (code == 404) return 'Not found';
  if (code == 401) return 'Unauthorized';
  if (code == 403) return 'Forbidden';
  if (code >= 400) return 'Client error';
  return 'OK';
}
