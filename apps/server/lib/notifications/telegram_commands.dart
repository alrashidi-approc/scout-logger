import 'package:scout_models/scout_models.dart';

const telegramCommandHelp = '/health — latest server health check\n'
    '/up — live uptime\n'
    '/stats — last 24 hours\n'
    '/release — issues since the latest release\n'
    '/issues — top open issues\n'
    '/report — admin report as text\n'
    '/pause — silence alerts for 1 hour\n'
    '/help — this list';

const telegramReplyKeyboard = {
  'keyboard': [
    [
      {'text': '/health'},
      {'text': '/up'},
    ],
    [
      {'text': '/stats'},
      {'text': '/release'},
    ],
    [
      {'text': '/issues'},
      {'text': '/report'},
    ],
    [
      {'text': '/pause'},
      {'text': '/help'},
    ],
  ],
  'resize_keyboard': true,
  'is_persistent': true,
};

const _commands = {'health', 'stats', 'issues', 'help', 'up', 'release', 'report', 'pause'};

final _slashCommand = RegExp(r'^/([A-Za-z0-9_]+)(?:@\w+)?(?:\s|$)');

/// `health`, `up`, `stats`, `release`, `issues`, `report`, `pause`, `help`,
/// or `unknown` for any other slash command. Null for normal text and `/start`.
String? telegramCommand(String text) {
  final trimmed = text.trim();
  final slash = _slashCommand.firstMatch(trimmed);
  if (slash != null) {
    final name = slash.group(1)?.toLowerCase() ?? '';
    if (name == 'start') return null;
    return _commands.contains(name) ? name : 'unknown';
  }
  final bare = trimmed.toLowerCase();
  if (_commands.contains(bare)) return bare;
  return null;
}

String telegramMenu(String projectName) => 'Scout · $projectName\n\n$telegramCommandHelp';

String telegramOnlyThese() => 'I only answer these:\n\n$telegramCommandHelp';

String telegramNotConnected() =>
    'This chat is not connected to a Scout project.\nOpen the project in Scout and tap Connect Telegram.';

String telegramHealthText({required String projectName, Map<String, dynamic>? run}) {
  if (run == null) {
    return 'No health check yet for $projectName.\nRun one from the project in Scout.';
  }
  final reportRaw = run['report'];
  final report = reportRaw is Map ? HealthCheckReport.fromJson(Map<String, dynamic>.from(reportRaw)) : null;
  final verdict = report?.verdict ?? run['status']?.toString() ?? 'unknown';
  final stats = report?.stats;
  final counts = stats == null ? '' : '\n${stats.ok} passed, ${stats.fail} failed, ${stats.timeout} timed out';
  final when = _when(run['finishedAt'] ?? run['startedAt']);
  final failed = report?.checks.where((c) => c.status == 'fail' || c.timedOut).take(5).toList() ?? const <HealthCheckItem>[];
  final lines = failed.map((c) {
    final detail = c.detail?.trim();
    final extra = (detail == null || detail.isEmpty) ? '' : ' — ${_clip(detail, 80)}';
    return '• ${c.name} (${c.status})$extra';
  });
  final summary = report?.summary.trim() ?? '';
  return [
    'Server health · $projectName',
    'Verdict: $verdict$counts',
    if (when.isNotEmpty) 'Checked $when',
    if (summary.isNotEmpty) _clip(summary, 240),
    if (lines.isNotEmpty) 'Needs attention:\n${lines.join('\n')}',
  ].join('\n');
}

String telegramStatsText({required String projectName, required Map<String, dynamic> overview}) {
  final release = overview['latestRelease']?.toString().trim();
  return [
    'Last 24 hours · $projectName',
    'Events ${_n(overview['eventsToday'])}',
    'Errors ${_n(overview['errorsToday'])}',
    'Crashes ${_n(overview['crashesToday'])}',
    'Open issues ${_n(overview['openIssues'])} (${_n(overview['highSeverityIssues'])} high)',
    'Users ${_n(overview['uniqueUsersToday'])}',
    if (release != null && release.isNotEmpty) 'Latest release $release',
  ].join('\n');
}

String telegramIssuesText({
  required String projectName,
  required List<Map<String, dynamic>> issues,
  required int regressions,
  required int newIssues,
}) {
  if (issues.isEmpty) {
    return 'No open issues in the last 24 hours for $projectName.\n$newIssues new, $regressions regressions.';
  }
  final lines = issues.take(5).map((issue) {
    final type = issue['type']?.toString() ?? 'issue';
    final title = _clip(issue['title']?.toString() ?? 'Untitled', 80);
    final count = _n(issue['count']);
    return '• $type · $title ($count)';
  });
  return 'Open issues · $projectName\n$newIssues new, $regressions regressions\n\n${lines.join('\n')}';
}

String telegramUptimeText({required String projectName, required UptimeMonitorConfig uptime}) {
  final targets = uptime.validTargets;
  if (!uptime.enabled || targets.isEmpty) {
    return 'Uptime checks are not set up for $projectName.';
  }
  final lines = targets.take(8).map((target) {
    final status = target.lastStatus ?? 'unknown';
    final latency = target.lastLatencyMs == null ? '' : ' ${target.lastLatencyMs}ms';
    final when = _when(target.lastCheckedAt?.toIso8601String());
    final checked = when.isEmpty ? '' : ' · $when';
    return '• $status$latency — ${target.url}$checked';
  });
  return 'Uptime · $projectName\n${lines.join('\n')}';
}

String telegramReleaseText({required String projectName, required Map<String, dynamic> overview}) {
  final release = overview['latestRelease']?.toString().trim();
  if (release == null || release.isEmpty) return 'No release recorded yet for $projectName.';
  return 'Latest release · $projectName\n$release\n${_n(overview['newIssuesSinceLatestRelease'])} new issues since this release';
}

String telegramPausedText(DateTime until) =>
    'Telegram alerts paused until ${_when(until)}.\n/health, /stats, and /report still work.';

String telegramWithLink(String body, String? url) {
  final link = (url == null || url.isEmpty) ? '' : '\n\nOpen: $url';
  final room = 4000 - link.length;
  final clipped = body.length <= room ? body : '${body.substring(0, room.clamp(0, 4000))}…';
  return '$clipped$link';
}

/// Inline buttons on an alert. Resolve and Mute need an issue id.
Map<String, dynamic> telegramAlertKeyboard(String? issueId) {
  final rows = <List<Map<String, String>>>[];
  if (issueId != null && issueId.isNotEmpty) {
    rows.add([
      {'text': 'Resolve', 'callback_data': 'r:$issueId'},
      {'text': 'Mute', 'callback_data': 'm:$issueId'},
    ]);
  }
  rows.add([
    {'text': 'Pause 1 hour', 'callback_data': 'p'},
  ]);
  return {'inline_keyboard': rows};
}

/// `pause`, `resolve`, or `mute`. Null when the button payload is not one of those.
({String kind, String? issueId})? parseTelegramCallback(String data) {
  if (data == 'p') return (kind: 'pause', issueId: null);
  if (data.startsWith('r:') && data.length > 2) return (kind: 'resolve', issueId: data.substring(2));
  if (data.startsWith('m:') && data.length > 2) return (kind: 'mute', issueId: data.substring(2));
  return null;
}

Future<String> telegramCommandReply({
  required String command,
  required String projectId,
  required Future<String?> Function(String projectId) projectName,
  required Future<Map<String, dynamic>> Function(String projectId) overview,
  required Future<Map<String, dynamic>?> Function(String projectId) healthRun,
  required Future<({List<Map<String, dynamic>> issues, int regressions, int newIssues})> Function(String projectId) issues,
}) async {
  final name = (await projectName(projectId))?.trim();
  final label = (name == null || name.isEmpty) ? projectId : name;
  switch (command) {
    case 'health':
      return telegramHealthText(projectName: label, run: await healthRun(projectId));
    case 'stats':
      return telegramStatsText(projectName: label, overview: await overview(projectId));
    case 'release':
      return telegramReleaseText(projectName: label, overview: await overview(projectId));
    case 'issues':
      final data = await issues(projectId);
      return telegramIssuesText(
        projectName: label,
        issues: data.issues,
        regressions: data.regressions,
        newIssues: data.newIssues,
      );
    default:
      return telegramMenu(label);
  }
}

int _n(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

String _clip(String value, int max) => value.length <= max ? value : '${value.substring(0, max)}…';

String _when(Object? raw) {
  final parsed = DateTime.tryParse(raw?.toString() ?? '');
  if (parsed == null) return '';
  final u = parsed.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)} UTC';
}
