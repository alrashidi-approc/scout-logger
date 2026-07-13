import 'notification_router.dart';

/// Build a single outbound job from [count] similar alerts in a group window.
NotificationJob groupedNotificationJob({
  required List<NotificationJob> jobs,
  required int groupMinutes,
}) {
  assert(jobs.isNotEmpty);
  final latest = jobs.last;
  if (jobs.length == 1) return latest;

  final categories = jobs.map((j) => j.category).toSet().toList()..sort();
  final title = '📦 ${latest.title}';
  final body = StringBuffer()
    ..writeln('${jobs.length} similar alerts grouped in the last $groupMinutes min.')
    ..writeln('Categories: ${categories.join(', ')}')
    ..writeln()
    ..write(latest.body);
  return NotificationJob(
    channel: latest.channel,
    category: 'grouped',
    dedupKey: latest.dedupKey,
    title: title,
    body: body.toString().trim(),
    eventUrl: latest.eventUrl,
    environment: latest.environment,
    release: latest.release,
    issueId: latest.issueId,
  );
}
