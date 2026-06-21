import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Light viewport on web — no default grey overscroll / html bleed-through.
class ScoutScrollBehavior extends MaterialScrollBehavior {
  const ScoutScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

extension ScoutTheme on ThemeData {
  ThemeData withScoutDefaults() => copyWith(
        canvasColor: AppTheme.bg,
        scaffoldBackgroundColor: AppTheme.bg,
        colorScheme: colorScheme.copyWith(
          surface: AppTheme.panel,
          surfaceContainerHighest: AppTheme.panel,
          surfaceContainerHigh: AppTheme.panel,
          surfaceContainer: AppTheme.panel,
          surfaceContainerLow: AppTheme.bg,
          surfaceContainerLowest: AppTheme.bg,
        ),
      );
}
