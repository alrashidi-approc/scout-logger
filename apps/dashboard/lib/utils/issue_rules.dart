typedef OwnerRule = ({String prefix, String assignee});

/// Project `settings.issueRules`: auto-resolve, ignore patterns and suggested owners.
/// Limits mirror the server so most mistakes are caught before the PATCH.
class IssueRules {
  const IssueRules({
    this.autoResolveQuietDays = 0,
    this.ignoreMessageRegexes = const [],
    this.ignoreCulpritPrefixes = const [],
    this.ownerRules = const [],
  });

  static const maxPatterns = 20;
  static const maxOwnerRules = 50;
  static const maxLength = 200;

  final int autoResolveQuietDays;
  final List<String> ignoreMessageRegexes;
  final List<String> ignoreCulpritPrefixes;
  final List<OwnerRule> ownerRules;

  factory IssueRules.fromJson(Object? json) {
    if (json is! Map) return const IssueRules();
    List<String> strings(Object? v) => [if (v is List) for (final s in v) if (s is String) s];
    final owners = json['ownerRules'];
    return IssueRules(
      autoResolveQuietDays: (json['autoResolveQuietDays'] as num?)?.toInt() ?? 0,
      ignoreMessageRegexes: strings(json['ignoreMessageRegexes']),
      ignoreCulpritPrefixes: strings(json['ignoreCulpritPrefixes']),
      ownerRules: [
        if (owners is List)
          for (final o in owners)
            if (o is Map && o['prefix'] is String && o['assignee'] is String)
              (prefix: o['prefix'] as String, assignee: o['assignee'] as String),
      ],
    );
  }

  /// Form fields (one regex / prefix per line) → rules, or the first validation error.
  static ({IssueRules? rules, String? error}) parseForm({
    required String quietDays,
    required String regexes,
    required String prefixes,
    required List<OwnerRule> owners,
  }) {
    ({IssueRules? rules, String? error}) fail(String error) => (rules: null, error: error);
    final days = quietDays.trim().isEmpty ? 0 : int.tryParse(quietDays.trim());
    if (days == null || days < 0 || days > 365) return fail('Auto-resolve quiet days must be a whole number 0–365');
    final regexList = lines(regexes);
    final prefixList = lines(prefixes);
    for (final (label, list) in [('message regexes', regexList), ('culprit prefixes', prefixList)]) {
      if (list.length > maxPatterns) return fail('At most $maxPatterns $label');
      if (list.any((s) => s.length > maxLength)) return fail('Ignore $label must be at most $maxLength characters');
    }
    for (final r in regexList) {
      try {
        RegExp(r);
      } on FormatException catch (e) {
        return fail('Invalid regex "$r": ${e.message}');
      }
    }
    if (owners.length > maxOwnerRules) return fail('At most $maxOwnerRules owner rules');
    return (
      rules: IssueRules(
        autoResolveQuietDays: days,
        ignoreMessageRegexes: regexList,
        ignoreCulpritPrefixes: prefixList,
        ownerRules: owners,
      ),
      error: null,
    );
  }

  static List<String> lines(String text) => [
        for (final l in text.split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ];

  Map<String, dynamic> toJson() => {
        'autoResolveQuietDays': autoResolveQuietDays,
        'ignoreMessageRegexes': ignoreMessageRegexes,
        'ignoreCulpritPrefixes': ignoreCulpritPrefixes,
        'ownerRules': [for (final o in ownerRules) {'prefix': o.prefix, 'assignee': o.assignee}],
      };
}
