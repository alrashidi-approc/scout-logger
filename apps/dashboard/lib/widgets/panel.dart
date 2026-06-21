import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/responsive.dart';

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.trailing,
    this.padding,
    this.margin,
  });

  final String? title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.mobile;
    final pad = padding ?? EdgeInsets.all(compact ? 14 : 18);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 6))],
      ),
      child: Padding(
        padding: pad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[
            if (compact && trailing != null)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 14 : 15, color: AppTheme.text)),
                if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppTheme.muted))],
                const SizedBox(height: 8),
                trailing!,
              ])
            else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title!, style: TextStyle(fontWeight: FontWeight.w700, fontSize: compact ? 14 : 15, color: AppTheme.text)),
                    if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppTheme.muted))],
                  ]),
                ),
                if (trailing != null) trailing!,
              ]),
            const SizedBox(height: 12),
          ],
          child,
        ]),
      ),
    );
  }
}
