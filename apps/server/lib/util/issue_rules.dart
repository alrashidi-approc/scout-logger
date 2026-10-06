/// Per-project issue automation, stored as `settings.issueRules` (I9 auto-resolve /
/// ignore, I14 suggested owner). Validated on PATCH; read leniently by the signals job.
class IssueRules {
  IssueRules({
    this.autoResolveQuietDays = 0,
    this.ignoreMessageRegexes = const [],
    this.ignoreCulpritPrefixes = const [],
    this.ownerRules = const [],
  });

  static const maxPatterns = 20;
  static const maxOwnerRules = 50;
  static const maxLength = 200;

  /// Regexes and prefixes only ever see this much text.
  static const _maxInput = 1000;

  /// `(a+)+`-style nested quantifiers — the usual catastrophic backtracking shape.
  static final _nestedQuantifier = RegExp(r'\([^)]*[+*}][^)]*\)\s*[+*{]');

  /// 0 = off.
  final int autoResolveQuietDays;
  final List<String> ignoreMessageRegexes;
  final List<String> ignoreCulpritPrefixes;
  final List<({String prefix, String assignee})> ownerRules;

  late final _regexes = [for (final p in ignoreMessageRegexes) RegExp(p, caseSensitive: false)];

  bool get ignoresAnything => ignoreMessageRegexes.isNotEmpty || ignoreCulpritPrefixes.isNotEmpty;

  /// Stored settings → rules; anything invalid is dropped (it was validated on save).
  factory IssueRules.fromSettings(Map<String, dynamic> settings) {
    try {
      return IssueRules.parse(settings['issueRules']);
    } on FormatException {
      return IssueRules();
    }
  }

  /// Strict parse of a full `issueRules` object; throws [FormatException] with a user-facing message.
  factory IssueRules.parse(Object? json) {
    if (json == null) return IssueRules();
    if (json is! Map) throw const FormatException('issueRules must be an object');
    final days = json['autoResolveQuietDays'] ?? 0;
    if (days is! int || days < 0 || days > 365) {
      throw const FormatException('autoResolveQuietDays must be an integer 0–365');
    }
    List<String> strings(String key, int max) {
      final v = json[key] ?? const [];
      if (v is! List || v.length > max) throw FormatException('$key must be a list of at most $max strings');
      return [
        for (final s in v)
          if (s is! String || s.trim().isEmpty || s.length > maxLength)
            throw FormatException('$key entries must be non-empty strings of at most $maxLength characters')
          else
            s.trim(),
      ];
    }

    final regexes = strings('ignoreMessageRegexes', maxPatterns);
    for (final r in regexes) {
      if (_nestedQuantifier.hasMatch(r)) throw FormatException('Regex "$r" has nested quantifiers');
      try {
        RegExp(r);
      } on FormatException catch (e) {
        throw FormatException('Invalid regex "$r": ${e.message}');
      }
    }
    final owners = json['ownerRules'] ?? const [];
    if (owners is! List || owners.length > maxOwnerRules) {
      throw const FormatException('ownerRules must be a list of at most $maxOwnerRules rules');
    }
    return IssueRules(
      autoResolveQuietDays: days,
      ignoreMessageRegexes: regexes,
      ignoreCulpritPrefixes: strings('ignoreCulpritPrefixes', maxPatterns),
      ownerRules: [
        for (final o in owners)
          if (o is! Map ||
              o['prefix'] is! String ||
              o['assignee'] is! String ||
              [o['prefix'] as String, o['assignee'] as String].any((s) => s.trim().isEmpty || s.length > maxLength))
            throw const FormatException('ownerRules entries need non-empty prefix and assignee (≤ $maxLength characters)')
          else
            (prefix: (o['prefix'] as String).trim(), assignee: (o['assignee'] as String).trim()),
      ],
    );
  }

  /// Keys present in [patch] replace the stored ones.
  IssueRules mergePatch(Map patch) => IssueRules.parse({...toJson(), ...patch});

  Map<String, dynamic> toJson() => {
        'autoResolveQuietDays': autoResolveQuietDays,
        'ignoreMessageRegexes': ignoreMessageRegexes,
        'ignoreCulpritPrefixes': ignoreCulpritPrefixes,
        'ownerRules': [for (final o in ownerRules) {'prefix': o.prefix, 'assignee': o.assignee}],
      };

  /// Why the issue should be ignored (`message matches /re/`, `culprit under prefix`), or null.
  String? ignoreReason({required List<String?> texts, String? culprit}) {
    for (var i = 0; i < _regexes.length; i++) {
      for (final t in texts) {
        if (t != null && _regexes[i].hasMatch(t.length > _maxInput ? t.substring(0, _maxInput) : t)) {
          return 'message matches /${ignoreMessageRegexes[i]}/';
        }
      }
    }
    for (final p in ignoreCulpritPrefixes) {
      if (culprit != null && culprit.startsWith(p)) return 'culprit under $p';
    }
    return null;
  }

  /// Longest-prefix owner rule matching [culprit].
  ({String prefix, String assignee})? ownerFor(String? culprit) {
    if (culprit == null) return null;
    ({String prefix, String assignee})? best;
    for (final o in ownerRules) {
      if (culprit.startsWith(o.prefix) && o.prefix.length > (best?.prefix.length ?? -1)) best = o;
    }
    return best;
  }
}
