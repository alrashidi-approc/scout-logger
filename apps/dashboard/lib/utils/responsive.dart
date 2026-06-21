import 'package:flutter/material.dart';

/// Layout breakpoints (content area, not full screen).
class Breakpoints {
  static const mobile = 600;
  static const tablet = 900;
  static const desktop = 1200;
  static const shellDrawer = 720;
}

bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < Breakpoints.mobile;

bool useDrawerNav(BuildContext context) => MediaQuery.sizeOf(context).width < Breakpoints.shellDrawer;

bool sideBySide(double maxWidth) => maxWidth >= Breakpoints.tablet;

double pagePad(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < Breakpoints.mobile) return 12;
  if (w < Breakpoints.shellDrawer) return 16;
  return 24;
}

EdgeInsets pageInsets(BuildContext context, {double top = 0, double bottom = 0}) =>
    EdgeInsets.fromLTRB(pagePad(context), top, pagePad(context), bottom);

int kpiColumns(double maxWidth) {
  if (maxWidth >= 1600) return 6;
  if (maxWidth >= Breakpoints.desktop) return 5;
  if (maxWidth >= Breakpoints.tablet) return 4;
  if (maxWidth >= 400) return 2;
  return 1;
}

double kpiCardWidth(double maxWidth, {double gap = 8}) {
  final cols = kpiColumns(maxWidth);
  return (maxWidth - gap * (cols - 1)) / cols;
}

/// Wraps KPI cards — width follows column count, height fits content (no empty grid cells).
class KpiWrap extends StatelessWidget {
  const KpiWrap({super.key, required this.children, this.gap = 8});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      final w = kpiCardWidth(c.maxWidth, gap: gap);
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}

int gridCols(BuildContext context, {int wide = 3, int medium = 2}) {
  final w = MediaQuery.sizeOf(context).width;
  if (w > Breakpoints.desktop) return wide;
  if (w > Breakpoints.mobile) return medium;
  return 1;
}

/// Side-by-side on tablet+, stacked on phone.
Widget responsiveRow({
  required double maxWidth,
  required List<Widget> children,
  double gap = 12,
  List<int>? flex,
}) {
  if (sideBySide(maxWidth)) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(flex: flex != null && i < flex.length ? flex[i] : 1, child: children[i]),
        ],
      ],
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]]],
  );
}

/// Legend chips that wrap on narrow panels.
Widget chartLegend(List<Widget> items) => Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: items);
