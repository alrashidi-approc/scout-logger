import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../widgets/health_check_report_card.dart';

/// Public read-only health check snapshot (share token).
class SharedHealthCheckView extends StatelessWidget {
  const SharedHealthCheckView({
    super.key,
    required this.projectName,
    required this.snapshot,
  });

  final String projectName;
  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    final report = snapshot['report'];
    final run = <String, dynamic>{
      'status': snapshot['status'] ?? 'success',
      if (snapshot['startedAt'] != null) 'startedAt': snapshot['startedAt'],
      if (snapshot['finishedAt'] != null) 'finishedAt': snapshot['finishedAt'],
      if (snapshot['durationMs'] != null) 'durationMs': snapshot['durationMs'],
      if (report is Map) 'report': Map<String, dynamic>.from(report),
    };

    final finishedAt = DateTime.tryParse(snapshot['finishedAt']?.toString() ?? '');
    final finishedLabel = finishedAt != null
        ? DateFormat.yMMMd().add_jm().format(finishedAt.toLocal())
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            projectName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Server health · last check snapshot',
            style: TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
          if (finishedLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              'Checked $finishedLabel',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          HealthCheckReportCard(run: run),
        ],
      ),
    );
  }
}
