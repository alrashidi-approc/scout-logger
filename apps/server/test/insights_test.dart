import 'package:scout_server/util/insights.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 12);
  ({int priority, List<String> reasons, bool spike, String? noise}) signals({
    String type = 'error',
    String status = 'open',
    int users = 0,
    int events = 10,
    Duration age = const Duration(days: 30),
    Duration sinceLast = Duration.zero,
    List<int> hourly = const [],
    int actors = 2,
    bool sim = false,
    bool auth = false,
    ({String name, DateTime since})? release,
  }) =>
      issueSignals(
        type: type,
        status: status,
        affectedUsers: users,
        eventCount: events,
        firstSeenAt: now.subtract(age),
        lastSeenAt: now.subtract(sinceLast),
        hourly: hourly,
        actors: actors,
        simulatorOnly: sim,
        authOnly: auth,
        release: release,
        now: now,
      );

  test('spike: last hour >= max(10, 5 x median hourly of the last 7 days)', () {
    expect(signals(hourly: [10]).spike, isTrue);
    expect(signals(hourly: [9]).spike, isFalse);
    final busy = [30, ...List.filled(168, 6)];
    expect(signals(hourly: busy).spike, isTrue);
    expect(signals(hourly: [29, ...List.filled(168, 6)]).spike, isFalse);
    expect(signals(hourly: [50], status: 'ignored').spike, isFalse);
  });

  test('noise reasons, most explanatory first', () {
    expect(signals(sinceLast: const Duration(days: 15)).noise, 'stale');
    expect(signals(sinceLast: const Duration(days: 15), status: 'resolved').noise, isNull);
    expect(signals(sim: true, auth: true).noise, 'simulator_only');
    expect(signals(auth: true).noise, 'auth_class');
    expect(signals(events: 1, age: const Duration(days: 2)).noise, 'single_occurrence');
    expect(signals(events: 1, age: const Duration(hours: 2)).noise, isNull);
    expect(signals(events: 5, users: 1, actors: 1).noise, 'single_user');
    expect(signals(events: 5, users: 2, actors: 1).noise, isNull);
  });

  test('priority adds users, velocity, crash, new release, spike; noise and status lower it', () {
    final rising = [for (var h = 0; h < 24; h++) 2];
    final p = signals(
      type: 'crash',
      users: 25,
      hourly: [12, ...rising],
      age: const Duration(hours: 3),
      release: (name: '2.1.0', since: now.subtract(const Duration(days: 1))),
    );
    expect(p.reasons, ['25 users affected', contains('rising'), 'crash', 'new in 2.1.0', contains('spike')]);
    expect(p.priority, 2 + 2 + 2 + 2 + 3);
    expect(signals(hourly: [1]).priority, 1);
    expect(signals(hourly: [1], sim: true).priority, 0);
    expect(signals(type: 'crash', status: 'resolved', hourly: [1]).priority, 1);
    expect(signals(type: 'crash', status: 'ignored').priority, 0);
  });
}
