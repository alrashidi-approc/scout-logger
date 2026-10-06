import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_dashboard/widgets/similar_issues_panel.dart';

const _similar = [
  {
    'id': 'iss_old',
    'type': 'error',
    'title': 'Null check (v1)',
    'status': 'resolved',
    'eventCount': 30,
    'lastSeenAt': '2026-09-01T00:00:00Z',
    'fingerprintVersion': 1,
    'similarBecause': ['predecessor'],
  },
  {
    'id': 'iss_route',
    'type': 'network',
    'title': 'GET /faqs failed',
    'status': 'open',
    'eventCount': 4,
    'lastSeenAt': '2026-10-05T00:00:00Z',
    'fingerprintVersion': 2,
    'similarBecause': ['same_route', 'same_group_hint'],
  },
];

void main() {
  testWidgets('loads only when expanded and renders reasons + previous version', (tester) async {
    var calls = 0;
    Map<String, dynamic>? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SimilarIssuesPanel(
            load: () async {
              calls++;
              return [for (final s in _similar) Map<String, dynamic>.from(s)];
            },
            onOpen: (i) => opened = i,
          ),
        ),
      ),
    ));
    expect(calls, 0);

    await tester.tap(find.text('Similar issues'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('previous version'), findsOneWidget);
    expect(find.text('predecessor'), findsOneWidget);
    expect(find.text('same route'), findsOneWidget);
    expect(find.text('same group hint'), findsOneWidget);
    expect(find.text('Null check (v1)'), findsOneWidget);

    await tester.tap(find.text('GET /faqs failed'));
    expect(opened?['id'], 'iss_route');

    await tester.tap(find.text('Similar issues'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Similar issues'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('empty result shows empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SimilarIssuesPanel(load: () async => [], onOpen: (_) {})),
    ));
    await tester.tap(find.text('Similar issues'));
    await tester.pumpAndSettle();
    expect(find.text('No similar issues'), findsOneWidget);
  });
}
