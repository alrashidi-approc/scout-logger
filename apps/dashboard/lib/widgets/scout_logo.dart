import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Scout brand mark — icon + wordmark for sidebar, auth, and footer.
class ScoutLogo extends StatelessWidget {
  const ScoutLogo({
    super.key,
    this.compact = false,
    this.showTagline = false,
    this.iconSize = 40,
    this.onTap,
  });

  final bool compact;
  final bool showTagline;
  final double iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mark = _LogoMark(size: iconSize);
    final wordmark = compact
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Scout', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.text, height: 1.1, letterSpacing: -0.3)),
              if (showTagline)
                const Text('Logger', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.muted, letterSpacing: 0.6))
              else
                const Text('Logger', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.muted, height: 1.2)),
            ],
          );

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        if (wordmark != null) ...[SizedBox(width: iconSize * 0.28), wordmark],
      ],
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: row)),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.accentPurple],
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.35), blurRadius: size * 0.35, offset: Offset(0, size * 0.08))],
      ),
      child: Icon(Icons.radar, color: Colors.white, size: size * 0.52),
    );
  }
}
