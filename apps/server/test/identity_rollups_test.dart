import 'package:scout_server/util/dates.dart';
import 'package:test/test.dart';

void main() {
  group('preferIdentityRollups', () {
    test('true for multi-day windows', () {
      expect(preferIdentityRollups(TimeWindow.lastDays(7)), isTrue);
      expect(preferIdentityRollups(TimeWindow.lastDays(30)), isTrue);
    });

    test('false for hourly / single-day windows', () {
      final hour = TimeWindow(
        since: DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String(),
      );
      expect(preferIdentityRollups(hour), isFalse);
    });
  });

  group('dateParams', () {
    test('maps since/until to date bounds', () {
      final w = TimeWindow(
        since: '2026-07-01T00:00:00.000Z',
        until: '2026-07-08T00:00:00.000Z',
      );
      expect(dateParams(w), {'fromDate': '2026-07-01', 'untilDate': '2026-07-08'});
    });
  });
}
