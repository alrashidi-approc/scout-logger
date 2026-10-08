import 'package:scout_models/scout_models.dart';
import 'package:scout_server/notifications/telegram_commands.dart';
import 'package:scout_server/notifications/telegram_link.dart';
import 'package:test/test.dart';

void main() {
  Future<void> ignoreBind(String projectId, String chatId, String chatTitle) async {}

  test('only the fixed commands are recognized', () {
    expect(telegramCommand('/health'), 'health');
    expect(telegramCommand('/stats@ScoutBot'), 'stats');
    expect(telegramCommand('issues'), 'issues');
    expect(telegramCommand('/report@ScoutBot'), 'report');
    expect(telegramCommand('/pause'), 'pause');
    expect(telegramCommand('/start abc'), isNull);
    expect(telegramCommand('/mute'), 'unknown');
    expect(telegramCommand('how is production?'), isNull);
  });

  test('health and stats replies stay short', () {
    final health = telegramHealthText(
      projectName: 'Demo',
      run: {
        'status': 'success',
        'finishedAt': '2026-10-08T08:15:00Z',
        'report': {
          'verdict': 'unhealthy',
          'summary': 'API is down',
          'checks': [
            {'name': 'API', 'status': 'fail', 'detail': 'connection refused'},
            {'name': 'Web', 'status': 'ok'},
          ],
          'stats': {'total': 2, 'completed': 2, 'ok': 1, 'fail': 1},
        },
      },
    );
    expect(health, contains('Verdict: unhealthy'));
    expect(health, contains('API (fail)'));
    expect(health, isNot(contains('Web (ok)')));

    final stats = telegramStatsText(
      projectName: 'Demo',
      overview: {
        'eventsToday': 12,
        'errorsToday': 2,
        'crashesToday': 1,
        'openIssues': 4,
        'highSeverityIssues': 1,
        'uniqueUsersToday': 9,
        'latestRelease': '1.4.2',
      },
    );
    expect(stats, contains('Crashes 1'));
    expect(stats, contains('Open issues 4 (1 high)'));
    expect(stats, contains('Latest release 1.4.2'));
  });

  test('uptime, release, pause, and alert buttons stay on the short menu', () {
    final up = telegramUptimeText(
      projectName: 'Demo',
      uptime: UptimeMonitorConfig(
        enabled: true,
        targets: [
          UptimeTarget(url: 'https://api.example.com', lastStatus: 'ok', lastLatencyMs: 40),
        ],
      ),
    );
    expect(up, contains('ok 40ms'));
    expect(up, contains('https://api.example.com'));

    expect(
      telegramReleaseText(projectName: 'Demo', overview: {'latestRelease': '1.4.2', 'newIssuesSinceLatestRelease': 3}),
      contains('3 new issues'),
    );
    expect(parseTelegramCallback('r:issue1')?.kind, 'resolve');
    expect(parseTelegramCallback('m:issue1')?.issueId, 'issue1');
    expect(parseTelegramCallback('p')?.kind, 'pause');
    expect(parseTelegramCallback('nope'), isNull);

    final buttons = telegramAlertKeyboard('issue1');
    final rows = buttons['inline_keyboard'] as List;
    expect(rows.length, 2);
  });

  test('a linked chat can ask for health, and other talk gets the menu', () async {
    final update = {
      'message': {
        'text': '/health',
        'chat': {'id': 7, 'type': 'private'},
      },
    };
    final asked = await handleTelegramUpdate(
      update: update,
      consumeLink: (_) async => null,
      bind: ignoreBind,
      projectName: (_) async => 'Demo',
      projectForChat: (_) async => 'p1',
      runCommand: (projectId, command) async => '$projectId:$command',
    );
    expect(asked, 'p1:health');

    final chatter = await handleTelegramUpdate(
      update: {
        'message': {
          'text': 'can you check the server and explain the crash?',
          'chat': {'id': 7, 'type': 'private'},
        },
      },
      consumeLink: (_) async => null,
      bind: ignoreBind,
      projectName: (_) async => 'Demo',
    );
    expect(chatter, contains('/health'));
    expect(chatter, contains('/stats'));
    expect(chatter, contains('/issues'));

    final group = await handleTelegramUpdate(
      update: {
        'message': {
          'text': 'hello team',
          'chat': {'id': -1, 'type': 'supergroup'},
        },
      },
      consumeLink: (_) async => null,
      bind: ignoreBind,
      projectName: (_) async => 'Demo',
    );
    expect(group, isNull);
  });

  test('an unlinked chat cannot run a command', () async {
    final reply = await handleTelegramUpdate(
      update: {
        'message': {
          'text': '/stats',
          'chat': {'id': 7, 'type': 'private'},
        },
      },
      consumeLink: (_) async => null,
      bind: ignoreBind,
      projectName: (_) async => 'Demo',
      projectForChat: (_) async => null,
      runCommand: (projectId, command) async => 'should not run',
    );
    expect(reply, contains('not connected'));
  });
}
