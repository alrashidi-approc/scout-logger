import 'package:scout_server/health_check/health_check_runner.dart';
import 'package:scout_models/scout_models.dart';
import 'package:test/test.dart';

void main() {
  group('parseHealthCheckReportLine', () {
    test('parses SCOUT_REPORT prefix', () {
      const line =
          'SCOUT_REPORT:{"verdict":"degraded","summary":"1/2","checks":[{"name":"a","status":"ok"}],"stats":{"total":2,"completed":1,"ok":1,"fail":0,"pending":1},"current":"b"}';
      final report = parseHealthCheckReportLine(line);
      expect(report?.current, 'b');
      expect(report?.checks, hasLength(1));
    });
  });

  group('parseHealthCheckReport', () {
    test('picks richest report from multiple lines', () {
      const stdout = '''
SCOUT_REPORT:{"verdict":"degraded","summary":"1/3","checks":[{"name":"a","status":"ok"}],"stats":{"total":3,"completed":1,"ok":1,"fail":0,"pending":2},"current":"b"}
SCOUT_REPORT:{"verdict":"degraded","summary":"2/3","checks":[{"name":"a","status":"ok"},{"name":"b","status":"timeout"}],"stats":{"total":3,"completed":2,"ok":1,"fail":0,"timeout":1,"pending":1},"current":"c"}
''';
      final report = parseHealthCheckReport(stdout);
      expect(report?.checks, hasLength(2));
      expect(report?.checks.last.status, 'timeout');
    });

    test('returns null for invalid output', () {
      expect(parseHealthCheckReport('not json'), isNull);
      expect(parseHealthCheckReport('{"checks":[]}'), isNull);
    });
  });

  group('HealthCheckReport', () {
    test('round-trips extended JSON', () {
      const original = HealthCheckReport(
        verdict: 'degraded',
        summary: '2/3 ok',
        checks: [
          HealthCheckItem(name: 'a', status: 'ok'),
          HealthCheckItem(name: 'b', status: 'timeout', detail: 'TimeoutException'),
        ],
        stats: HealthCheckStats(total: 3, completed: 2, ok: 1, fail: 0, timeout: 1, pending: 1),
        timedOutAt: 'c',
        pending: ['c'],
      );
      final restored = HealthCheckReport.fromJson(original.toJson());
      expect(restored.timeoutCount, 1);
      expect(restored.pending, ['c']);
    });
  });
}
