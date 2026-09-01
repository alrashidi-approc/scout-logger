import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:scout_models/scout_models.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/clipboard.dart';
import '../widgets/detail_panel.dart';
import '../widgets/stat_card.dart';

enum _CheckFilter { all, issues, ok, skipped }

class HealthCheckReportCard extends StatefulWidget {
  const HealthCheckReportCard({super.key, required this.run});

  final Map<String, dynamic> run;

  static Color verdictColor(String? verdict) => switch (verdict) {
        'healthy' => AppTheme.success,
        'degraded' => AppTheme.warning,
        _ => AppTheme.error,
      };

  static Color statusColor(String status) => switch (status) {
        'ok' => AppTheme.success,
        'skipped' => AppTheme.muted,
        'timeout' => AppTheme.warning,
        _ => AppTheme.error,
      };

  static IconData statusIcon(String status) => switch (status) {
        'ok' => Icons.check_circle_outline,
        'skipped' => Icons.skip_next_outlined,
        'timeout' => Icons.schedule_outlined,
        _ => Icons.error_outline,
      };

  @override
  State<HealthCheckReportCard> createState() => _HealthCheckReportCardState();
}

class _HealthCheckReportCardState extends State<HealthCheckReportCard> {
  _CheckFilter _filter = _CheckFilter.all;
  final _expanded = <String>{};

  HealthCheckReport? get _report => widget.run['report'] is Map
      ? HealthCheckReport.fromJson(Map<String, dynamic>.from(widget.run['report'] as Map))
      : null;

  List<HealthCheckItem> get _sortedChecks {
    final checks = [...?_report?.checks];
    checks.sort((a, b) => _statusOrder(a.status).compareTo(_statusOrder(b.status)));
    return checks;
  }

  List<HealthCheckItem> get _issues => _sortedChecks.where((c) => c.status == 'fail' || c.timedOut).toList();

  List<HealthCheckItem> get _filteredChecks => switch (_filter) {
        _CheckFilter.all => _sortedChecks,
        _CheckFilter.issues => _issues,
        _CheckFilter.ok => _sortedChecks.where((c) => c.ok).toList(),
        _CheckFilter.skipped => _sortedChecks.where((c) => c.skipped).toList(),
      };

  static int _statusOrder(String s) => switch (s) {
        'fail' => 0,
        'timeout' => 1,
        'ok' => 2,
        'skipped' => 3,
        _ => 4,
      };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final runStatus = widget.run['status'] as String? ?? '';
    final timedOut = runStatus == 'timeout';
    final color = report != null ? HealthCheckReportCard.verdictColor(report.verdict) : AppTheme.muted;
    final stats = report?.stats;
    final progress = stats != null && stats.total > 0 ? stats.completed / stats.total : 0.0;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeaderBand(color: color, report: report, run: widget.run, timedOut: timedOut),
          if (stats != null && stats.total > 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: progress.clamp(0, 1), minHeight: 8, backgroundColor: AppTheme.border, color: color),
                  ),
                  const SizedBox(height: 6),
                  Text('${stats.completed} of ${stats.total} checks completed', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 640 ? 5 : (c.maxWidth >= 420 ? 3 : 2);
                  final cards = [
                    StatCard(label: 'Passed', value: '${stats.ok}', icon: Icons.check_circle_outline, color: AppTheme.success),
                    if (stats.fail > 0) StatCard(label: 'Failed', value: '${stats.fail}', icon: Icons.error_outline, color: AppTheme.error),
                    if (stats.timeout > 0) StatCard(label: 'Timeout', value: '${stats.timeout}', icon: Icons.schedule, color: AppTheme.warning),
                    if (stats.skipped > 0) StatCard(label: 'Skipped', value: '${stats.skipped}', icon: Icons.skip_next, color: AppTheme.muted),
                    if (stats.pending > 0) StatCard(label: 'Pending', value: '${stats.pending}', icon: Icons.pending_outlined, color: AppTheme.info),
                  ];
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: cards.map((card) => SizedBox(width: (c.maxWidth - (cols - 1) * 8) / cols, child: card)).toList(),
                  );
                },
              ),
            ),
          ],
          if (report?.networkProbe != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _NetworkProbePanel(probe: report!.networkProbe!),
            ),
          ],
          if (report == null)
            _EmptyReport(timedOut: timedOut, run: widget.run)
          else ...[
            if (_issues.isNotEmpty) _IssuesPanel(issues: _issues, expanded: _expanded, onToggle: _toggle),
            if (report.pending.isNotEmpty) _PendingSection(pending: report.pending),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Text('All checks', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => copyWithFeedback(context, const JsonEncoder.withIndent('  ').convert(report.toJson()), message: 'Report JSON copied'),
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('Copy report'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _FilterChip('All (${_sortedChecks.length})', _filter == _CheckFilter.all, () => setState(() => _filter = _CheckFilter.all)),
                  if (_issues.isNotEmpty)
                    _FilterChip('Issues (${_issues.length})', _filter == _CheckFilter.issues, () => setState(() => _filter = _CheckFilter.issues)),
                  if (stats != null && stats.ok > 0)
                    _FilterChip('OK (${stats.ok})', _filter == _CheckFilter.ok, () => setState(() => _filter = _CheckFilter.ok)),
                  if (stats != null && stats.skipped > 0)
                    _FilterChip('Skipped (${stats.skipped})', _filter == _CheckFilter.skipped, () => setState(() => _filter = _CheckFilter.skipped)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_filteredChecks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No checks in this filter.', style: TextStyle(color: AppTheme.muted)),
              )
            else if (wide)
              _ChecksTable(checks: _filteredChecks, expanded: _expanded, onToggle: _toggle)
            else
              ..._filteredChecks.map((c) => _CheckTile(item: c, expanded: _expanded.contains(c.name), onToggle: () => _toggle(c.name))),
          ],
          if (_hasLogs(widget.run)) ...[
            const Divider(height: 1),
            _LogsSection(run: widget.run),
          ],
          if (report?.wafLearning != null) ...[
            const Divider(height: 1),
            _WafLearningPanel(wafLearning: report!.wafLearning!),
          ],
          _RunFooter(run: widget.run),
        ],
      ),
    );
  }

  void _toggle(String name) => setState(() => _expanded.contains(name) ? _expanded.remove(name) : _expanded.add(name));

  bool _hasLogs(Map<String, dynamic> run) {
    final err = '${run['stderr'] ?? ''}'.trim();
    final out = '${run['stdout'] ?? ''}'.trim();
    return err.isNotEmpty || out.isNotEmpty;
  }
}

class _HeaderBand extends StatelessWidget {
  const _HeaderBand({required this.color, required this.report, required this.run, required this.timedOut});

  final Color color;
  final HealthCheckReport? report;
  final Map<String, dynamic> run;
  final bool timedOut;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final duration = _formatDuration(run['durationMs']);
    final started = _formatTime(run['startedAt']);
    final finished = _formatTime(run['finishedAt']);
    final exitCode = run['exitCode'];
    final runStatus = run['status'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.14), AppTheme.panel],
        ),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.2))),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.monitor_heart_outlined, color: color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          r?.verdict.toUpperCase() ?? runStatus.toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: color, letterSpacing: 0.4),
                        ),
                        _MetaBadge(_runStatusLabel(runStatus), _runStatusColor(runStatus)),
                        if (duration != null) _MetaBadge(duration, AppTheme.muted),
                      ],
                    ),
                    if (r != null) ...[
                      const SizedBox(height: 6),
                      SelectableText(r.summary, style: const TextStyle(fontSize: 14, height: 1.35)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (r != null && (r.timedOutAt != null || r.current != null)) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (timedOut ? AppTheme.warning : AppTheme.info).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: (timedOut ? AppTheme.warning : AppTheme.info).withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(timedOut ? Icons.timer_off_outlined : Icons.play_circle_outline, size: 18, color: timedOut ? AppTheme.warning : AppTheme.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timedOut ? 'Script timed out' : 'Last check running when report was captured',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: timedOut ? AppTheme.warning : AppTheme.info),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          timedOut ? 'Stopped at: ${r.timedOutAt ?? r.current}' : r.current ?? '',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (started != null) _MetaLine(Icons.schedule, 'Started', started),
              if (finished != null) _MetaLine(Icons.flag_outlined, 'Finished', finished),
              if (exitCode != null) _MetaLine(Icons.terminal, 'Exit code', '$exitCode'),
              if (run['triggeredBy'] != null) _MetaLine(Icons.person_outline, 'Triggered by', '${run['triggeredBy']}'),
            ],
          ),
        ],
      ),
    );
  }

  static String? _formatDuration(dynamic ms) {
    if (ms == null) return null;
    final n = (ms as num).toInt();
    if (n >= 60000) return '${(n / 60000).toStringAsFixed(1)} min';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)} s';
    return '$n ms';
  }

  static String? _formatTime(dynamic iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse('$iso');
    if (dt == null) return '$iso';
    return DateFormat('MMM d, yyyy · HH:mm:ss').format(dt.toLocal());
  }

  static String _runStatusLabel(String s) => switch (s) {
        'success' => 'Completed',
        'timeout' => 'Timed out',
        'failed' => 'Failed',
        'running' => 'Running',
        _ => s.isEmpty ? 'Unknown' : s,
      };

  static Color _runStatusColor(String s) => switch (s) {
        'success' => AppTheme.success,
        'timeout' => AppTheme.warning,
        'failed' => AppTheme.error,
        _ => AppTheme.muted,
      };
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.muted),
        const SizedBox(width: 4),
        Text('$label: ', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
        SelectableText(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _IssuesPanel extends StatelessWidget {
  const _IssuesPanel({required this.issues, required this.expanded, required this.onToggle});

  final List<HealthCheckItem> issues;
  final Set<String> expanded;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.report_problem_outlined, color: AppTheme.error, size: 20),
                const SizedBox(width: 8),
                Text('Needs attention (${issues.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.error)),
              ],
            ),
          ),
          ...issues.map((c) => _CheckDetailCard(item: c, expanded: expanded.contains(c.name) || issues.length <= 3, onToggle: () => onToggle(c.name), highlight: true)),
        ],
      ),
    );
  }
}

class _PendingSection extends StatelessWidget {
  const _PendingSection({required this.pending});
  final List<String> pending;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.info.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.info.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_empty, size: 18, color: AppTheme.info),
                const SizedBox(width: 8),
                Text('Not executed (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: pending.map((id) => ActionChip(
                label: Text(id, style: const TextStyle(fontSize: 11)),
                onPressed: () => copyWithFeedback(context, id, message: 'Check id copied'),
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
            const SizedBox(height: 6),
            const Text(
              'These checks did not run — often because the script hit its time limit or stopped early.',
              style: TextStyle(fontSize: 11, color: AppTheme.muted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecksTable extends StatelessWidget {
  const _ChecksTable({required this.checks, required this.expanded, required this.onToggle});

  final List<HealthCheckItem> checks;
  final Set<String> expanded;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(10)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            children: [
              Container(
                color: AppTheme.panelElevated,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: const Row(
                  children: [
                    Expanded(flex: 3, child: Text('Check', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted))),
                    Expanded(child: Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted))),
                    Expanded(child: Text('HTTP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted))),
                    Expanded(child: Text('Latency', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted))),
                    SizedBox(width: 88, child: Text('Actions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted))),
                  ],
                ),
              ),
              ...checks.map((c) => _CheckTableRow(item: c, expanded: expanded.contains(c.name), onToggle: () => onToggle(c.name))),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckTableRow extends StatelessWidget {
  const _CheckTableRow({required this.item, required this.expanded, required this.onToggle});

  final HealthCheckItem item;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final color = HealthCheckReportCard.statusColor(item.status);
    final http = _httpCode(item.detail);
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Icon(HealthCheckReportCard.statusIcon(item.status), size: 16, color: color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: AppTheme.muted),
                    ],
                  ),
                ),
                Expanded(child: Text(item.status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color))),
                Expanded(child: Text(http ?? '—', style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                Expanded(child: Text(item.latencyMs == null ? '—' : '${item.latencyMs} ms', style: const TextStyle(fontSize: 12))),
                SizedBox(width: 88, child: _QuickActions(item: item, compact: true)),
              ],
            ),
          ),
        ),
        if (expanded) _CheckExpandedBody(item: item),
      ],
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.item, required this.expanded, required this.onToggle});

  final HealthCheckItem item;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: _CheckDetailCard(item: item, expanded: expanded, onToggle: onToggle),
    );
  }
}

class _CheckDetailCard extends StatelessWidget {
  const _CheckDetailCard({required this.item, required this.expanded, required this.onToggle, this.highlight = false});

  final HealthCheckItem item;
  final bool expanded;
  final VoidCallback onToggle;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = HealthCheckReportCard.statusColor(item.status);
    return Container(
      margin: EdgeInsets.fromLTRB(highlight ? 8 : 0, 0, highlight ? 8 : 0, highlight ? 8 : 0),
      decoration: BoxDecoration(
        color: highlight ? AppTheme.panel : AppTheme.panelElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(highlight ? 8 : 10),
        border: Border.all(color: highlight ? AppTheme.border : AppTheme.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(highlight ? 8 : 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(HealthCheckReportCard.statusIcon(item.status), color: color, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (!expanded && (item.detail ?? item.url)?.isNotEmpty == true)
                          Text(item.detail ?? item.url!, style: const TextStyle(fontSize: 11, color: AppTheme.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (item.latencyMs != null) Text('${item.latencyMs} ms', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                    child: Text(item.status.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, color: AppTheme.muted),
                ],
              ),
            ),
          ),
          if (expanded) _CheckExpandedBody(item: item),
        ],
      ),
    );
  }
}

class _CheckExpandedBody extends StatelessWidget {
  const _CheckExpandedBody({required this.item});

  final HealthCheckItem item;

  @override
  Widget build(BuildContext context) {
    final http = _httpCode(item.detail);
    final hint = _actionHint(item);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          DetailRow(label: 'Check id', value: item.name, mono: true, onCopy: () => copyWithFeedback(context, item.name)),
          DetailRow(label: 'Status', value: item.status.toUpperCase()),
          if (http != null) DetailRow(label: 'HTTP', value: http, mono: true),
          if (item.latencyMs != null) DetailRow(label: 'Latency', value: '${item.latencyMs} ms'),
          if (item.url?.isNotEmpty == true)
            DetailRow(label: 'URL', value: item.url!, mono: true, onCopy: () => copyWithFeedback(context, item.url!, message: 'URL copied')),
          if (item.detail?.isNotEmpty == true && item.detail != item.url)
            DetailRow(label: 'Detail', value: item.detail!, mono: true, onCopy: () => copyWithFeedback(context, item.detail!, message: 'Detail copied')),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: HealthCheckReportCard.statusColor(item.status).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: HealthCheckReportCard.statusColor(item.status)),
                const SizedBox(width: 8),
                Expanded(child: Text(hint, style: const TextStyle(fontSize: 12, height: 1.4))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _QuickActions(item: item),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.item, this.compact = false});

  final HealthCheckItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final url = item.url?.trim() ?? '';
    final hasUrl = url.isNotEmpty && url.startsWith('http');
    final curl = hasUrl ? _curlGet(url) : null;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasUrl)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy URL',
              icon: const Icon(Icons.link, size: 16),
              onPressed: () => copyWithFeedback(context, url, message: 'URL copied'),
            ),
          if (curl != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy cURL',
              icon: const Icon(Icons.terminal, size: 16),
              onPressed: () => copyWithFeedback(context, curl, message: 'cURL copied'),
            ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (hasUrl) ...[
          OutlinedButton.icon(
            onPressed: () => copyWithFeedback(context, url, message: 'URL copied'),
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Copy URL'),
          ),
          OutlinedButton.icon(
            onPressed: () => _openUrl(context, url),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open'),
          ),
        ],
        if (curl != null)
          OutlinedButton.icon(
            onPressed: () => copyWithFeedback(context, curl, message: 'cURL copied'),
            icon: const Icon(Icons.terminal, size: 16),
            label: const Text('Copy cURL'),
          ),
        OutlinedButton.icon(
          onPressed: () => copyWithFeedback(context, const JsonEncoder.withIndent('  ').convert(item.toJson()), message: 'Check JSON copied'),
          icon: const Icon(Icons.data_object, size: 16),
          label: const Text('Copy check'),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(this.label, this.selected, this.onTap);
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      selectedColor: AppTheme.primarySoft,
      checkmarkColor: AppTheme.primary,
    );
  }
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport({required this.timedOut, required this.run});

  final bool timedOut;
  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(timedOut ? Icons.timer_off_outlined : Icons.info_outline, color: timedOut ? AppTheme.warning : AppTheme.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  timedOut ? 'Script timed out with no SCOUT_REPORT output' : 'No valid SCOUT_REPORT JSON in stdout',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'The server did not receive incremental progress lines. Common causes: script missing stdout.flush(), Dart SDK not available in the container, or script error before first check.',
            style: TextStyle(fontSize: 12, color: AppTheme.muted, height: 1.4),
          ),
          if (run['exitCode'] != null) ...[
            const SizedBox(height: 8),
            Text('Exit code: ${run['exitCode']}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ],
        ],
      ),
    );
  }
}

class _LogsSection extends StatelessWidget {
  const _LogsSection({required this.run});
  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context) {
    final stderr = '${run['stderr'] ?? ''}'.trim();
    final stdout = '${run['stdout'] ?? ''}'.trim();
    final reports = _scoutReportLines(stdout);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: reports.isEmpty && stderr.isNotEmpty,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: const Text('Raw logs', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
          [if (reports.isNotEmpty) '${reports.length} SCOUT_REPORT lines', if (stderr.isNotEmpty) 'stderr', if (stdout.isNotEmpty) 'stdout'].join(' · '),
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          if (reports.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => copyWithFeedback(context, reports.join('\n'), message: 'SCOUT_REPORT lines copied'),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy SCOUT_REPORT lines'),
                ),
              ),
            ),
            ...reports.take(5).map((line) => _LogBlock(label: 'SCOUT_REPORT', text: line)),
            if (reports.length > 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('+ ${reports.length - 5} more lines in full stdout below', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
              ),
          ],
          if (stderr.isNotEmpty) _LogBlock(label: 'stderr', text: stderr),
          if (stdout.isNotEmpty) _LogBlock(label: 'stdout', text: stdout),
        ],
      ),
    );
  }

  static List<String> _scoutReportLines(String stdout) {
    return stdout.split('\n').where((l) => l.trim().startsWith('SCOUT_REPORT:')).map((l) => l.trim()).toList();
  }
}

class _LogBlock extends StatelessWidget {
  const _LogBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppTheme.muted)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => copyWithFeedback(context, text, message: '$label copied'),
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy'),
              ),
            ],
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.codeBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.border)),
            child: SingleChildScrollView(
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkProbePanel extends StatelessWidget {
  const _NetworkProbePanel({required this.probe});

  final Map<String, dynamic> probe;

  @override
  Widget build(BuildContext context) {
    final probes = (probe['probes'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
    final summary = probe['summary'] as String? ?? '';
    final hint = probe['hint'] as String?;
    final scoutHost = probe['scoutHost'] as String?;
    final hasIssue = probes.any((p) => p['status'] != 'ok');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (hasIssue ? AppTheme.warning : AppTheme.info).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (hasIssue ? AppTheme.warning : AppTheme.info).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 20, color: hasIssue ? AppTheme.warning : AppTheme.info),
              const SizedBox(width: 8),
              const Expanded(child: Text('Scout server network probe', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            ],
          ),
          const SizedBox(height: 6),
          Text(summary, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (scoutHost != null) Text('From host: $scoutHost', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint, style: TextStyle(fontSize: 12, color: hasIssue ? AppTheme.warning : AppTheme.muted, height: 1.35)),
          ],
          if (probes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...probes.map((p) {
              final status = p['status'] as String? ?? 'fail';
              final color = HealthCheckReportCard.statusColor(status == 'ok' ? 'ok' : status == 'timeout' ? 'timeout' : 'fail');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(HealthCheckReportCard.statusIcon(status == 'ok' ? 'ok' : status == 'timeout' ? 'timeout' : 'fail'), size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['host'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          if (p['resolvedIps'] != null)
                            Text('DNS: ${p['resolvedIps']}', style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontFamily: 'monospace')),
                          Text(p['detail'] as String? ?? '', style: const TextStyle(fontSize: 11)),
                          if (p['sampleUrl'] != null)
                            SelectableText(p['sampleUrl'] as String, style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
                        ],
                      ),
                    ),
                    if (p['latencyMs'] != null)
                      Text('${p['latencyMs']} ms', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _RunFooter extends StatelessWidget {
  const _RunFooter({required this.run});
  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context) {
    if (run['id'] == null && run['startedAt'] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Wrap(
        spacing: 12,
        children: [
          if (run['id'] != null)
            Text('Run ${run['id']}', style: const TextStyle(color: AppTheme.muted, fontSize: 10, fontFamily: 'monospace')),
          if (run['startedAt'] != null)
            Text('Started ${run['startedAt']}', style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _WafLearningPanel extends StatelessWidget {
  const _WafLearningPanel({required this.wafLearning});

  final Map<String, dynamic> wafLearning;

  @override
  Widget build(BuildContext context) {
    final count = (wafLearning['observationCount'] as num?)?.toInt() ?? 0;
    final openApi = wafLearning['openApi'] as Map<String, dynamic>?;
    final pathCount = (openApi?['paths'] as Map?)?.length ?? 0;
    final generatedAt = wafLearning['generatedAt'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.traffic_outlined, size: 20, color: AppTheme.info),
              SizedBox(width: 8),
              Text('WAF learning', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Text('$count observed calls · $pathCount OpenAPI paths', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
          if (generatedAt != null) Text('Generated $generatedAt', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              if (openApi != null)
                OutlinedButton.icon(
                  onPressed: () => copyWithFeedback(context, const JsonEncoder.withIndent('  ').convert(openApi), message: 'OpenAPI JSON copied'),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy OpenAPI'),
                ),
              OutlinedButton.icon(
                onPressed: () => copyWithFeedback(context, const JsonEncoder.withIndent('  ').convert(wafLearning), message: 'WAF JSON copied'),
                icon: const Icon(Icons.data_object, size: 16),
                label: const Text('Copy WAF JSON'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _httpCode(String? detail) {
  final m = RegExp(r'HTTP\s+(\d{3})').firstMatch(detail ?? '');
  return m?.group(1);
}

String _curlGet(String url) => "curl -sS -w '\\nHTTP %{http_code} · %{time_total}s\\n' -o /dev/null '$url'";

String _actionHint(HealthCheckItem item) {
  final code = _httpCode(item.detail);
  return switch (item.status) {
    'ok' => 'Endpoint responded successfully (${item.detail ?? 'OK'}). No action needed unless latency is unexpectedly high.',
    'timeout' => 'No response within 10 seconds. Test the URL from your machine and from the Scout server network. Check firewall, VPN, or upstream slowness.',
    'skipped' => (item.detail ?? '').startsWith('skipped: depends on')
        ? 'Skipped because a listed prerequisite failed or timed out. Check whether that dependency is really required — citizen auth and e-process auth are separate chains.'
        : 'Skipped by script configuration. Enable in script constants or fix prerequisite checks.',
    'fail' when code == '404' => 'HTTP 404 — URL or resource path may be wrong. Verify base URL, branch name, and route in your API reference.',
    'fail' when code != null && (int.tryParse(code) ?? 0) >= 500 => 'HTTP $code server error — backend issue. Retry manually; check server logs on the API side.',
    'fail' when code != null && (int.tryParse(code) ?? 0) >= 400 => 'HTTP $code client/auth error — verify credentials, headers, or request body in the script.',
    'fail' => 'Request failed (${item.detail ?? 'unknown'}). Copy the URL or cURL below and reproduce in Postman or terminal.',
    _ => 'Review the detail field and test this endpoint manually.',
  };
}

Future<void> _openUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open URL — copy it instead')));
  }
}
