import 'package:intl/intl.dart';

/// Dashboard time filter — preset days or custom from/to (inclusive calendar dates).
class PeriodFilter {
  const PeriodFilter._({this.days, this.from, this.to});

  const PeriodFilter.days(this.days) : from = null, to = null;

  const PeriodFilter.range(this.from, this.to) : days = null;

  static const maxCustomDays = 90;

  final int? days;
  final DateTime? from;
  final DateTime? to;

  bool get isPreset => days != null;
  bool get isCustom => from != null;

  int get spanDays {
    if (isPreset) return days!;
    final t = to ?? from!;
    return t.difference(from!).inDays + 1;
  }

  /// Hourly chart for 24h preset or a single custom calendar day.
  bool get usesHourlyTrend => isPreset ? days == 1 : spanDays == 1;

  static DateTime _todayLocal() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  factory PeriodFilter.today() {
    final t = _todayLocal();
    return PeriodFilter.range(t, t);
  }

  factory PeriodFilter.yesterday() {
    final t = _todayLocal().subtract(const Duration(days: 1));
    return PeriodFilter.range(t, t);
  }

  factory PeriodFilter.thisWeek() {
    final t = _todayLocal();
    final start = t.subtract(Duration(days: t.weekday - 1));
    return PeriodFilter.range(start, t);
  }

  factory PeriodFilter.lastWeek() {
    final t = _todayLocal();
    final thisMon = t.subtract(Duration(days: t.weekday - 1));
    return PeriodFilter.range(thisMon.subtract(const Duration(days: 7)), thisMon.subtract(const Duration(days: 1)));
  }

  factory PeriodFilter.thisMonth() {
    final t = _todayLocal();
    return PeriodFilter.range(DateTime(t.year, t.month, 1), t);
  }

  factory PeriodFilter.lastMonth() {
    final t = _todayLocal();
    final firstThis = DateTime(t.year, t.month, 1);
    final last = firstThis.subtract(const Duration(days: 1));
    return PeriodFilter.range(DateTime(last.year, last.month, 1), last);
  }

  static const quickRanges = [
    ('Today', PeriodFilter.today),
    ('Yesterday', PeriodFilter.yesterday),
    ('This week', PeriodFilter.thisWeek),
    ('Last week', PeriodFilter.lastWeek),
    ('This month', PeriodFilter.thisMonth),
    ('Last month', PeriodFilter.lastMonth),
  ];

  static PeriodFilter parse(Map<String, String> q, {int defaultDays = 7}) {
    final fromStr = q['from'];
    if (fromStr != null && fromStr.isNotEmpty) {
      final from = _parseDate(fromStr);
      if (from == null) return PeriodFilter.days(defaultDays);
      final toStr = q['to'];
      final to = toStr != null && toStr.isNotEmpty ? _parseDate(toStr) : from;
      return PeriodFilter.range(from, to ?? from);
    }
    return PeriodFilter.days(int.tryParse(q['days'] ?? '') ?? defaultDays);
  }

  static PeriodFilter? parseOptional(Map<String, String> q) {
    final fromStr = q['from'];
    if (fromStr != null && fromStr.isNotEmpty) return parse(q);
    final daysStr = q['days'];
    if (daysStr != null && daysStr.isNotEmpty) {
      return PeriodFilter.days(int.tryParse(daysStr) ?? 7);
    }
    return null;
  }

  static Map<String, String>? queryFromUri(Map<String, String> q) {
    if (q.containsKey('from') && q['from']!.isNotEmpty) {
      return {'from': q['from']!, if (q['to'] != null && q['to']!.isNotEmpty) 'to': q['to']!};
    }
    if (q.containsKey('days') && q['days']!.isNotEmpty) return {'days': q['days']!};
    return null;
  }

  Map<String, String> toQuery() {
    if (isPreset) return {'days': '$days'};
    return {'from': _fmt(from!), 'to': _fmt(to ?? from!)};
  }

  Map<String, String> mergeQuery([Map<String, String>? extra]) => {...?extra, ...toQuery()};

  String label() {
    if (isPreset) return days == 1 ? 'today' : 'last $days days';
    final f = from!;
    final t = to ?? f;
    if (_sameDay(f, t)) return DateFormat.yMMMd().format(f);
    return '${DateFormat.MMMd().format(f)} – ${DateFormat.MMMd().format(t)}';
  }

  String comparisonLabel() => isPreset ? 'vs prior $days days' : 'vs prior period';

  static String? rangeError(DateTime from, DateTime to) {
    final days = to.difference(from).inDays + 1;
    if (days > maxCustomDays) return 'Max $maxCustomDays days per range';
    if (days < 1) return 'End must be on or after start';
    return null;
  }

  static DateTime? _parseDate(String raw) {
    try {
      if (raw.length == 10) return DateTime.parse('${raw}T00:00:00');
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  static String _fmt(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

String periodLabel(PeriodFilter p) => p.label();
