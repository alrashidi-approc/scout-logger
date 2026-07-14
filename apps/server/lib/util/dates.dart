/// UTC calendar date string (YYYY-MM-DD) for SQL `date` comparisons.
String utcDateDaysAgo(int days) {
  final now = DateTime.now().toUtc();
  final d = DateTime.utc(now.year, now.month, now.day).subtract(Duration(days: days));
  return d.toIso8601String().substring(0, 10);
}

/// UTC timestamptz string for SQL `@since::timestamptz` filters.
String utcTimestampDaysAgo(int days) =>
    DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();

String? sinceTimestamp(int? days) => days == null ? null : utcTimestampDaysAgo(days);

/// Inclusive calendar-date range or rolling `days` window for API queries.
class TimeWindow {
  const TimeWindow({this.since, this.until});

  final String? since;
  final String? until;

  static const all = TimeWindow();

  factory TimeWindow.lastDays(int days) =>
      TimeWindow(since: utcTimestampDaysAgo(days.clamp(1, 365)));

  factory TimeWindow.fromQuery(Map<String, String> q, {int defaultDays = 7, bool optional = false}) {
    final hoursStr = q['hours'];
    if (hoursStr != null && hoursStr.isNotEmpty) {
      final h = (int.tryParse(hoursStr) ?? 24).clamp(1, 720);
      return TimeWindow(
        since: DateTime.now().toUtc().subtract(Duration(hours: h)).toIso8601String(),
      );
    }
    final fromStr = q['from'];
    if (fromStr != null && fromStr.isNotEmpty) {
      final from = _parseDayUtc(fromStr);
      final toStr = q['to'];
      final toDay = (toStr != null && toStr.isNotEmpty) ? _parseDayUtc(toStr) : from;
      return TimeWindow(
        since: from.toIso8601String(),
        until: toDay.add(const Duration(days: 1)).toIso8601String(),
      );
    }
    if (optional && (q['days'] == null || q['days']!.isEmpty)) return all;
    final d = int.tryParse(q['days'] ?? '') ?? defaultDays;
    return TimeWindow.lastDays(d);
  }

  int get approximateDays {
    if (since == null) return 7;
    if (until == null) {
      final s = DateTime.parse(since!).toUtc();
      return DateTime.now().toUtc().difference(s).inDays.clamp(1, 365);
    }
    final s = DateTime.parse(since!).toUtc();
    final u = DateTime.parse(until!).toUtc();
    return u.difference(s).inDays.clamp(1, 365);
  }

  /// Rolling 24h or a single inclusive calendar day (`from`…`to` same day).
  bool get usesHourlyTrend {
    if (since == null) return false;
    final s = DateTime.parse(since!).toUtc();
    final u = until != null ? DateTime.parse(until!).toUtc() : DateTime.now().toUtc();
    final span = u.difference(s);
    if (until == null && span.inHours <= 24) return true;
    if (until != null && span == const Duration(days: 1)) return true;
    return span.inHours <= 24;
  }

  /// Previous period of equal length (for delta comparisons).
  TimeWindow previousPeriod() {
    if (since == null) return TimeWindow.lastDays(7);
    final s = DateTime.parse(since!).toUtc();
    final u = until != null ? DateTime.parse(until!).toUtc() : DateTime.now().toUtc();
    final len = u.difference(s);
    return TimeWindow(since: s.subtract(len).toIso8601String(), until: s.toIso8601String());
  }

  static DateTime _parseDayUtc(String raw) {
    if (raw.length == 10) return DateTime.utc(int.parse(raw.substring(0, 4)), int.parse(raw.substring(5, 7)), int.parse(raw.substring(8, 10)));
    return DateTime.parse(raw).toUtc();
  }
}

Map<String, dynamic> timeParams(TimeWindow w) => {'since': w.since, 'until': w.until};

/// Inclusive `fromDate` / exclusive `untilDate` for `DATE` columns (daily rollups).
Map<String, dynamic> dateParams(TimeWindow w) => {
      'fromDate': w.since?.substring(0, 10),
      'untilDate': trendUntilDate(w),
    };

/// Exclusive upper bound for `daily_stats.date` (until is next-day midnight).
String? trendUntilDate(TimeWindow w) => w.until?.substring(0, 10);

/// Prefer identity/daily rollups unless the window is hourly (sub-day).
bool preferIdentityRollups(TimeWindow w) => !w.usesHourlyTrend;
