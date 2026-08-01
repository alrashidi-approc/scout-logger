import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/clipboard.dart';

/// Copy-pasteable smart summary at the top of issue/event detail.
class SmartSummaryCard extends StatelessWidget {
  const SmartSummaryCard({super.key, required this.markdown});

  final String markdown;

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
                    markdown,
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
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
              ),
              child: SelectableText(
                markdown,
                style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
