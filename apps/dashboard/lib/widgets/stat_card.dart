import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.onTap,
    this.hint,
    this.delta,
    this.deltaGoodWhenDown = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  final String? hint;
  final double? delta;
  final bool deltaGoodWhenDown;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.primary;

    final card = Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: accent, size: 14),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w500, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (delta != null) _DeltaBadge(value: delta!, goodWhenDown: deltaGoodWhenDown),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: accent, height: 1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      hint!,
                      style: const TextStyle(fontSize: 10, color: AppTheme.muted, height: 1.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), hoverColor: accent.withValues(alpha: 0.06), child: card),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.value, required this.goodWhenDown});
  final double value;
  final bool goodWhenDown;

  @override
  Widget build(BuildContext context) {
    final up = value >= 0;
    final good = goodWhenDown ? !up : up;
    final color = value == 0 ? AppTheme.muted : (good ? AppTheme.success : AppTheme.error);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)),
      child: Text(
        '${up ? '+' : ''}${value.toStringAsFixed(0)}%',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class KpiHero extends StatelessWidget {
  const KpiHero({super.key, required this.title, required this.value, this.subtitle, this.color, this.icon});

  final String title;
  final String value;
  final String? subtitle;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.primary;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.22), AppTheme.panel],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.08), blurRadius: 28)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: AppTheme.muted, fontSize: compact ? 12 : 13, fontWeight: FontWeight.w600)),
              SizedBox(height: compact ? 6 : 8),
              Text(value, style: TextStyle(color: accent, fontSize: compact ? 28 : 34, fontWeight: FontWeight.w900, height: 1)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: const TextStyle(color: AppTheme.muted, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          if (icon != null) Icon(icon, size: compact ? 36 : 44, color: accent.withValues(alpha: 0.35)),
        ],
      ),
    );
  }
}
