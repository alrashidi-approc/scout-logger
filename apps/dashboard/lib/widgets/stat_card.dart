import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.icon, this.color});

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: accent, size: 20),
              ),
            if (icon != null) const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 13, fontWeight: FontWeight.w500))),
          ]),
          const SizedBox(height: 14),
          Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.text, height: 1)),
        ]),
      ),
    );
  }
}
