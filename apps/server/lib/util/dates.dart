/// UTC calendar date string (YYYY-MM-DD) for SQL `date` comparisons.
String utcDateDaysAgo(int days) {
  final now = DateTime.now().toUtc();
  final d = DateTime.utc(now.year, now.month, now.day).subtract(Duration(days: days));
  return d.toIso8601String().substring(0, 10);
}

/// UTC timestamptz string for SQL `@since::timestamptz` filters (avoids make_interval param bugs).
String utcTimestampDaysAgo(int days) =>
    DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

String? sinceTimestamp(int? days) => days == null ? null : utcTimestampDaysAgo(days);
