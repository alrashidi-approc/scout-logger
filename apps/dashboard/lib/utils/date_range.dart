import 'package:intl/intl.dart';

/// Dashboard time filter — preset days, rolling hours, or custom from/to dates.
class PeriodFilter {
  const PeriodFilter._({this.days, this.from, this.to, this.hours});

  const PeriodFilter.days(this.days) : from = null, to = null, hours = null;

  const PeriodFilter.hours(this.hours) : days = null, from = null, to = null;

  const PeriodFilter.range(this.from, this.to) : days = null, hours = null;

  static const maxCustomDays = 90;

  final int? days;
  final DateTime? from;
  final DateTime? to;
  final int? hours;

  bool get isPreset => days != null;
  bool get isHours => hours != null;
  bool get isCustom => from != null;

  int get spanDays {
    if (isPreset) return days!;
    final t = to ?? from!;
    return t.difference(from!).inDays + 1;
  }

  /// Hourly chart for 24h preset, hour window, or a single custom calendar day.
  bool get usesHourlyTrend => isHours || (isPreset ? days == 1 : spanDays == 1);

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
    final hoursStr = q['hours'];
    if (hoursStr != null && hoursStr.isNotEmpty) {
      return PeriodFilter.hours((int.tryParse(hoursStr) ?? 24).clamp(1, 720));
    }
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
    if (q['hours'] != null && q['hours']!.isNotEmpty) return parse(q);
    final fromStr = q['from'];
    if (fromStr != null && fromStr.isNotEmpty) return parse(q);
    final daysStr = q['days'];
    if (daysStr != null && daysStr.isNotEmpty) {
      return PeriodFilter.days(int.tryParse(daysStr) ?? 7);
    }
    return null;
  }

  static Map<String, String>? queryFromUri(Map<String, String> q) {
    if (q.containsKey('hours') && q['hours']!.isNotEmpty) return {'hours': q['hours']!};
    if (q.containsKey('from') && q['from']!.isNotEmpty) {
      return {'from': q['from']!, if (q['to'] != null && q['to']!.isNotEmpty) 'to': q['to']!};
    }
    if (q.containsKey('days') && q['days']!.isNotEmpty) return {'days': q['days']!};
    return null;
  }

  Map<String, String> toQuery() {
    if (isHours) return {'hours': '$hours'};
    if (isPreset) return {'days': '$days'};
    return {'from': _fmt(from!), 'to': _fmt(to ?? from!)};
  }

  Map<String, String> mergeQuery([Map<String, String>? extra]) => {...?extra, ...toQuery()};

  String label() {
    if (isHours) return hours == 1 ? 'last hour' : 'last $hours hours';
    if (isPreset) return days == 1 ? 'today' : 'last $days days';
    final f = from!;
    final t = to ?? f;
    if (_sameDay(f, t)) return DateFormat.yMMMd().format(f);
    return '${DateFormat.MMMd().format(f)} – ${DateFormat.MMMd().format(t)}';
  }

  String comparisonLabel() {
    if (isHours) return 'vs prior $hours hours';
    return isPreset ? 'vs prior $days days' : 'vs prior period';
  }

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
