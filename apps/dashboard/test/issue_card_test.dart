import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_dashboard/utils/issue_view.dart';
import 'package:scout_dashboard/widgets/event_card.dart';

Future<void> _pump(WidgetTester tester, Map<String, dynamic> issue, {bool sinceLastVisit = false}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(body: IssueCard(issue: issue, onTap: () {}, sinceLastVisit: sinceLastVisit)),
    ));

void main() {
  const base = {
    'id': 'iss_1',
    'type': 'error',
    'title': 'Null check operator',
    'status': 'open',
    'eventCount': 12,
    'lastSeenAt': '2026-10-05T10:00:00Z',
  };

  testWidgets('shows priority, spike, noise and summary', (tester) async {
    await _pump(tester, {
      ...base,
      'priority': 7,
      'priorityReasons': ['crash', 'spike: 40 events in the last hour'],
      'spike': true,
      'noiseReason': 'single_user',
      'summary': 'Keystore enrollment failed',
      'likelyCause': 'StrongBox unavailable',
    }, sinceLastVisit: true);

    expect(find.text('P7'), findsOneWidget);
    expect(find.text('SPIKE'), findsOneWidget);
    expect(find.text('noise · single user'), findsOneWidget);
    expect(find.text('Keystore enrollment failed'), findsOneWidget);
    expect(find.text('StrongBox unavailable'), findsNothing);
    expect(find.text('SINCE LAST VISIT'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.ancestor(of: find.text('P7'), matching: find.byType(Tooltip)));
    expect(tooltip.message, 'crash\nspike: 40 events in the last hour');
  });

  test('suspect labels: max 2, app version prefixed, share as percent', () {
    expect(
      suspectLabels({
        'suspects': [
          {'dimension': 'platform', 'value': 'ios', 'share': 0.923},
          {'dimension': 'app_version', 'value': '1.4.0', 'share': 0.8},
          {'dimension': 'country', 'value': 'EG', 'share': 0.75},
        ],
      }),
      ['ios · 92%', 'v1.4.0 · 80%'],
    );
    expect(suspectLabels({'suspects': null}), isEmpty);
  });

  testWidgets('renders suspect chips', (tester) async {
    await _pump(tester, {
      ...base,
      'suspects': [
        {'dimension': 'environment', 'value': 'production', 'share': 1.0},
      ],
    });
    expect(find.text('production · 100%'), findsOneWidget);
  });

  testWidgets('falls back to likelyCause and hides absent signals', (tester) async {
    await _pump(tester, {...base, 'priority': 0, 'spike': false, 'likelyCause': 'Debug token not registered'});

    expect(find.text('Debug token not registered'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^P\d')), findsNothing);
    expect(find.text('SPIKE'), findsNothing);
    expect(find.textContaining('noise'), findsNothing);
    expect(find.text('SINCE LAST VISIT'), findsNothing);
  });
}
