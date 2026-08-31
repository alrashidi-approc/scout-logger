import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:scout_models/scout_models.dart';

import '../theme/app_theme.dart';
import '../utils/clipboard.dart';

class HealthCheckReportCard extends StatelessWidget {
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

  static int _statusOrder(String s) => switch (s) {
        'fail' => 0,
        'timeout' => 1,
        'ok' => 2,
        'skipped' => 3,
        _ => 4,
      };

  @override
  Widget build(BuildContext context) {
    final report = run['report'] is Map
        ? HealthCheckReport.fromJson(Map<String, dynamic>.from(run['report'] as Map))
        : null;
    final status = run['status'] as String? ?? '';
    final timedOut = status == 'timeout';
    final verdict = report?.verdict;
    final color = report != null ? verdictColor(verdict) : AppTheme.muted;
    final stats = report?.stats;
    final progress = stats != null && stats.total > 0 ? stats.completed / stats.total : 0.0;

    final checks = [...?report?.checks]
      ..sort((a, b) => _statusOrder(a.status).compareTo(_statusOrder(b.status)));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 4,
            color: color,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.monitor_heart_outlined, color: color, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            report?.verdict.toUpperCase() ?? status.toUpperCase(),
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color),
                          ),
                          if (report != null) ...[
                            const SizedBox(height: 4),
                            Text(report.summary, style: const TextStyle(fontSize: 14)),
                          ],
                        ],
                      ),
                    ),
                    if (run['durationMs'] != null)
                      Text('${run['durationMs']} ms', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ],
                ),
                if (stats != null && stats.total > 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppTheme.border,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${stats.completed}/${stats.total} checks',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _StatChip('OK', stats.ok, AppTheme.success),
                      if (stats.fail > 0) _StatChip('Fail', stats.fail, AppTheme.error),
                      if (stats.timeout > 0) _StatChip('Timeout', stats.timeout, AppTheme.warning),
                      if (stats.skipped > 0) _StatChip('Skipped', stats.skipped, AppTheme.muted),
                      if (stats.pending > 0) _StatChip('Pending', stats.pending, AppTheme.info),
                    ],
                  ),
                ],
                if (report != null && (report.timedOutAt != null || report.current != null)) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: (timedOut ? AppTheme.warning : AppTheme.info).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: (timedOut ? AppTheme.warning : AppTheme.info).withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      timedOut
                          ? 'Timed out at: ${report.timedOutAt ?? report.current}'
                          : 'Last running: ${report.current}',
                      style: TextStyle(
                        color: timedOut ? AppTheme.warning : AppTheme.info,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (report == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                timedOut ? 'Script timed out with no progress output' : 'No valid JSON report in stdout',
                style: const TextStyle(color: AppTheme.muted),
              ),
            )
          else if (checks.isEmpty && report.pending.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('No checks recorded', style: TextStyle(color: AppTheme.muted)),
            )
          else ...[
            const Divider(height: 1),
            if (checks.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: checks.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 52),
                itemBuilder: (context, i) => _CheckRow(item: checks[i]),
              ),
            if (report.pending.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Not run (${report.pending.length})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.muted)),
              ),
              ...report.pending.map((id) => _PendingRow(name: id)),
            ],
          ],
          if (_hasLogs(run)) ...[
            const Divider(height: 1),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text('Logs', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                children: [
                  if (run['stderr'] != null && '${run['stderr']}'.trim().isNotEmpty)
                    _LogBlock(label: 'stderr', text: '${run['stderr']}'),
                  if (run['stdout'] != null && '${run['stdout']}'.trim().isNotEmpty)
                    _LogBlock(label: 'stdout', text: '${run['stdout']}'),
                ],
              ),
            ),
          ],
          if (report?.wafLearning != null) ...[
            const Divider(height: 1),
            _WafLearningPanel(wafLearning: report!.wafLearning!),
          ],
          if (run['startedAt'] != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Run at ${run['startedAt']}', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
            ),
        ],
      ),
    );
  }

  bool _hasLogs(Map<String, dynamic> run) {
    final err = '${run['stderr'] ?? ''}'.trim();
    final out = '${run['stdout'] ?? ''}'.trim();
    return err.isNotEmpty || out.isNotEmpty;
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text('$count $label', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.item});

  final HealthCheckItem item;

  @override
  Widget build(BuildContext context) {
    final color = HealthCheckReportCard.statusColor(item.status);
    final subtitle = item.detail ?? item.url;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(HealthCheckReportCard.statusIcon(item.status), color: color, size: 22),
      title: Row(
        children: [
          Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          if (item.latencyMs != null)
            Text('${item.latencyMs} ms', style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
        ],
      ),
      subtitle: subtitle != null && subtitle.isNotEmpty
          ? InkWell(
              onTap: () => copyWithFeedback(context, subtitle, message: 'Copied'),
              child: Text(subtitle, style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
            )
          : null,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(item.status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: const Icon(Icons.radio_button_unchecked, color: AppTheme.muted, size: 20),
      title: Text(name, style: const TextStyle(fontSize: 13, color: AppTheme.muted)),
      trailing: const Text('PENDING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.muted)),
    );
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
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: AppTheme.muted)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(8),
            color: AppTheme.codeBg,
            child: SingleChildScrollView(
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 10, height: 1.35)),
            ),
          ),
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
          Row(
            children: [
              const Icon(Icons.traffic_outlined, size: 20, color: AppTheme.info),
              const SizedBox(width: 8),
              const Text('WAF learning', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$count observed calls · $pathCount OpenAPI paths',
            style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
          if (generatedAt != null)
            Text('Generated $generatedAt', style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              if (openApi != null)
                OutlinedButton.icon(
                  onPressed: () => copyWithFeedback(
                    context,
                    const JsonEncoder.withIndent('  ').convert(openApi),
                    message: 'OpenAPI JSON copied',
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy OpenAPI'),
                ),
              OutlinedButton.icon(
                onPressed: () => copyWithFeedback(
                  context,
                  const JsonEncoder.withIndent('  ').convert(wafLearning),
                  message: 'WAF JSON copied',
                ),
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
