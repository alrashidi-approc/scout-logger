import 'package:flutter_test/flutter_test.dart';
import 'package:scout_dashboard/utils/issue_view.dart';

void main() {
  final since = DateTime.utc(2026, 10, 1);
  const old = '2026-09-01T00:00:00Z';
  const recent = '2026-10-03T00:00:00Z';

  Map<String, dynamic> issue(String id, {bool spike = false, String first = old, String? regressed, String? spikeAt}) => {
        'id': id,
        'spike': spike,
        'firstSeenAt': first,
        if (regressed != null) 'regressedAt': regressed,
        if (spikeAt != null) 'spikeAt': spikeAt,
      };

  test('buckets by spike → new → regression → waiting, keeping order', () {
    final s = triageSections([
      issue('a'),
      issue('b', spike: true, first: recent),
      issue('c', first: recent, regressed: recent),
      issue('d', regressed: recent),
      issue('e', regressed: old),
      issue('f', spike: true),
      issue('g', first: recent),
    ], since: since);

    List<Object?> ids(List<Map<String, dynamic>> l) => l.map((i) => i['id']).toList();
    expect(ids(s.spikes), ['b', 'f']);
    expect(ids(s.fresh), ['c', 'g']);
    expect(ids(s.regressions), ['d']);
    expect(ids(s.waiting), ['a', 'e']);
  });

  test('missing timestamps fall through to waiting', () {
    final s = triageSections([{'id': 'x'}], since: since);
    expect(s.waiting, hasLength(1));
    expect([...s.spikes, ...s.fresh, ...s.regressions], isEmpty);
  });

  test('since last visit uses first seen, regression or spike time', () {
    final visit = DateTime.utc(2026, 10, 2);
    expect(issueSinceVisit(issue('a', first: recent), visit), isTrue);
    expect(issueSinceVisit(issue('b', regressed: recent), visit), isTrue);
    expect(issueSinceVisit(issue('c', spikeAt: recent), visit), isTrue);
    expect(issueSinceVisit(issue('d', regressed: old), visit), isFalse);
    expect(issueSinceVisit(issue('e', first: recent), null), isFalse);
  });
}
