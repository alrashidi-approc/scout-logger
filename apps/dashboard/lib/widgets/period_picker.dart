import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/date_range.dart';

/// Bottom sheet: quick ranges, calendar picker, UTC note.
Future<void> showPeriodPicker(
  BuildContext context, {
  required PeriodFilter current,
  required ValueChanged<PeriodFilter> onSelected,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            const Text('Time range', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Dates use UTC · max ${PeriodFilter.maxCustomDays} days', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, factory) in PeriodFilter.quickRanges)
                  ActionChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      onSelected(factory());
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _pickCalendar(context, current: current, onSelected: onSelected);
              },
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text(current.isCustom ? 'Change: ${current.label()}' : 'Pick on calendar…'),
            ),
          ]),
        ),
      );
    },
  );
}

Future<void> _pickCalendar(
  BuildContext context, {
  required PeriodFilter current,
  required ValueChanged<PeriodFilter> onSelected,
}) async {
  final now = DateTime.now();
  final initial = current.isCustom
      ? DateTimeRange(start: current.from!, end: current.to ?? current.from!)
      : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: now,
    initialDateRange: initial,
    helpText: 'Select date range (UTC)',
  );
  if (range == null) return;
  final from = DateTime(range.start.year, range.start.month, range.start.day);
  final to = DateTime(range.end.year, range.end.month, range.end.day);
  final err = PeriodFilter.rangeError(from, to);
  if (err != null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    return;
  }
  onSelected(PeriodFilter.range(from, to));
}

/// Tappable chip showing the active period.
class PeriodChip extends StatelessWidget {
  const PeriodChip({super.key, required this.period, this.onTap});

  final PeriodFilter period;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_today, size: 12, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(period.label(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
          if (onTap != null) ...[const SizedBox(width: 4), Icon(Icons.expand_more, size: 14, color: AppTheme.primary.withValues(alpha: 0.8))],
        ]),
      ),
    );
  }
}
