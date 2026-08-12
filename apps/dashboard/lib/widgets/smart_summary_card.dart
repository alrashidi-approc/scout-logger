import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/clipboard.dart';
import '../utils/smart_issue_summary.dart';

/// Copy-pasteable smart summary at the top of issue/event detail.
class SmartSummaryCard extends StatelessWidget {
  const SmartSummaryCard({super.key, required this.summary});

  final SmartSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Smart summary',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => copyWithFeedback(
                    context,
                    summary.markdown,
                    message: 'Smart summary copied',
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Short agent brief — Where / Failed at / Why / Next',
              style: TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
            const SizedBox(height: 14),
            _row('Where', summary.where),
            _row('Failed at', summary.failedAt),
            _row('Why', summary.why),
            if (summary.next.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text('Next', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted)),
              const SizedBox(height: 6),
              ...summary.next.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                      Expanded(child: SelectableText(n, style: const TextStyle(fontSize: 13, height: 1.45))),
                    ],
                  ),
                ),
              ),
            ],
            if (summary.meta.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in summary.meta)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Text(m, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.text)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted)),
            const SizedBox(height: 4),
            SelectableText(value, style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
