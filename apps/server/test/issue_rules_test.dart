import 'package:scout_server/util/issue_rules.dart';
import 'package:test/test.dart';

void main() {
  test('parse validates regexes, caps and shapes', () {
    for (final bad in <Object>[
      {'ignoreMessageRegexes': ['(unclosed']},
      {'ignoreMessageRegexes': ['(a+)+b']},
      {'ignoreMessageRegexes': ['x' * 201]},
      {'ignoreMessageRegexes': List.filled(21, 'a')},
      {'ignoreCulpritPrefixes': ['']},
      {'autoResolveQuietDays': -1},
      {'autoResolveQuietDays': '7'},
      {'ownerRules': [{'prefix': 'package:app/'}]},
      'nope',
    ]) {
      expect(() => IssueRules.parse(bad), throwsFormatException, reason: '$bad');
    }
    final rules = IssueRules.parse({'autoResolveQuietDays': 7}).mergePatch({'ignoreMessageRegexes': [' ^timeout ']});
    expect(rules.toJson(), {
      'autoResolveQuietDays': 7,
      'ignoreMessageRegexes': ['^timeout'],
      'ignoreCulpritPrefixes': [],
      'ownerRules': [],
    });
    expect(IssueRules.fromSettings({'issueRules': {'autoResolveQuietDays': 'x'}}).toJson()['autoResolveQuietDays'], 0);
  });

  test('ignoreReason matches messages case-insensitively and culprit prefixes', () {
    final rules = IssueRules.parse({
      'ignoreMessageRegexes': ['^socketexception'],
      'ignoreCulpritPrefixes': ['package:app/legacy/'],
    });
    expect(rules.ignoreReason(texts: ['SocketException: reset', null]), 'message matches /^socketexception/');
    expect(rules.ignoreReason(texts: ['boom'], culprit: 'package:app/legacy/cart.dart'), 'culprit under package:app/legacy/');
    expect(rules.ignoreReason(texts: ['boom'], culprit: 'package:app/cart.dart'), isNull);
  });

  test('ownerFor picks the longest matching prefix', () {
    final rules = IssueRules.parse({
      'ownerRules': [
        {'prefix': 'package:app/', 'assignee': 'team@x.io'},
        {'prefix': 'package:app/payments/', 'assignee': 'pay@x.io'},
      ],
    });
    expect(rules.ownerFor('package:app/payments/card.dart')?.assignee, 'pay@x.io');
    expect(rules.ownerFor('package:app/home.dart')?.prefix, 'package:app/');
    expect(rules.ownerFor('package:other/x.dart'), isNull);
    expect(rules.ownerFor(null), isNull);
  });
}
