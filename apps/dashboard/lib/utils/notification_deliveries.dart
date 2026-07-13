/// Collapse noisy delivery rows for the dashboard (same project · channel · issue · status).
List<Map<String, dynamic>> groupNotificationDeliveries(List<Map<String, dynamic>> rows) {
  final groups = <String, Map<String, dynamic>>{};
  for (final d in rows) {
    final issueKey = d['issueId']?.toString() ?? d['category']?.toString() ?? '';
    final key = '${d['projectId']}|${d['channel']}|$issueKey|${d['status']}';
    final existing = groups[key];
    if (existing == null) {
      groups[key] = {
        ...d,
        'count': 1,
        'latestAt': d['createdAt'],
      };
      continue;
    }
    existing['count'] = (existing['count'] as int) + 1;
    final at = d['createdAt']?.toString() ?? '';
    final latest = existing['latestAt']?.toString() ?? '';
    if (at.compareTo(latest) > 0) {
      existing['latestAt'] = at;
      if (d['errorMessage'] != null) existing['errorMessage'] = d['errorMessage'];
    }
  }
  final out = groups.values.toList();
  out.sort((a, b) => (b['latestAt']?.toString() ?? '').compareTo(a['latestAt']?.toString() ?? ''));
  return out;
}

String deliveryStatusLabel(String status, {int count = 1}) {
  final base = switch (status) {
    'sent' => 'Sent',
    'failed' => 'Failed',
    'skipped_dedup' => 'Deduped',
    'batched' => 'Grouped (pending)',
    'grouped' => 'Grouped',
    'rate_limited' => 'Rate-limited',
    _ => status,
  };
  return count > 1 ? '$base ×$count' : base;
}
