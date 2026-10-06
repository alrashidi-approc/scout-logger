import 'package:flutter_test/flutter_test.dart';
import 'package:scout_dashboard/utils/issue_rules.dart';

void main() {
  ({IssueRules? rules, String? error}) parse({
    String days = '',
    String regexes = '',
    String prefixes = '',
    List<OwnerRule> owners = const [],
  }) =>
      IssueRules.parseForm(quietDays: days, regexes: regexes, prefixes: prefixes, owners: owners);

  test('form → JSON trims lines and drops blanks', () {
    final r = parse(
      days: ' 14 ',
      regexes: 'timeout\n\n  ^SocketException ',
      prefixes: 'lib/generated/\n',
      owners: [(prefix: 'lib/payments/', assignee: 'pay@acme.com')],
    );
    expect(r.error, isNull);
    expect(r.rules?.toJson(), {
      'autoResolveQuietDays': 14,
      'ignoreMessageRegexes': ['timeout', '^SocketException'],
      'ignoreCulpritPrefixes': ['lib/generated/'],
      'ownerRules': [
        {'prefix': 'lib/payments/', 'assignee': 'pay@acme.com'},
      ],
    });
  });

  test('empty quiet days means off', () => expect(parse().rules?.autoResolveQuietDays, 0));

  test('rejects bad days, too many patterns, long entries, invalid regex, too many owners', () {
    expect(parse(days: '366').error, contains('0–365'));
    expect(parse(days: 'abc').error, contains('0–365'));
    expect(parse(regexes: List.generate(21, (i) => 'p$i').join('\n')).error, 'At most 20 message regexes');
    expect(parse(prefixes: 'x' * 201).error, contains('at most 200 characters'));
    expect(parse(regexes: '(unclosed').error, startsWith('Invalid regex "(unclosed"'));
    final owners = List.generate(51, (i) => (prefix: 'p$i', assignee: 'a'));
    expect(parse(owners: owners).error, 'At most 50 owner rules');
  });

  test('fromJson is lenient and round-trips', () {
    expect(IssueRules.fromJson(null).toJson()['autoResolveQuietDays'], 0);
    final json = {
      'autoResolveQuietDays': 7,
      'ignoreMessageRegexes': ['a', 3],
      'ignoreCulpritPrefixes': <String>[],
      'ownerRules': [
        {'prefix': 'lib/', 'assignee': 'x@y.z'},
        {'prefix': 'bad'},
      ],
    };
    expect(IssueRules.fromJson(json).toJson(), {
      'autoResolveQuietDays': 7,
      'ignoreMessageRegexes': ['a'],
      'ignoreCulpritPrefixes': <String>[],
      'ownerRules': [
        {'prefix': 'lib/', 'assignee': 'x@y.z'},
      ],
    });
  });
}
