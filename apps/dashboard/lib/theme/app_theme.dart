import 'package:flutter/material.dart';

/// Scout dashboard design tokens — light theme (default).
class AppTheme {
  static const bg = Color(0xFFF8FAFC);
  static const sidebar = Color(0xFF0F172A);
  static const sidebarElevated = Color(0xFF1E293B);
  static const sidebarBorder = Color(0xFF334155);
  static const onSidebar = Color(0xFFF1F5F9);
  static const onSidebarMuted = Color(0xFF94A3B8);
  static const sidebarActive = Color(0xFF60A5FA);
  static const sidebarHover = Color(0xFF1E293B);
  static const panel = Color(0xFFFFFFFF);
  static const panelElevated = Color(0xFFF1F5F9);
  static const border = Color(0xFFE2E8F0);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const primary = Color(0xFF2563EB);
  static const primarySoft = Color(0x142563EB);
  static const accentPurple = Color(0xFF7C3AED);
  static const accentPink = Color(0xFFDB2777);
  static const error = Color(0xFFDC2626);
  static const warning = Color(0xFFD97706);
  static const success = Color(0xFF059669);
  static const info = Color(0xFF0284C7);
  static const codeBg = Color(0xFFF1F5F9);
  static const codeHeader = Color(0xFFE2E8F0);

  static const surface = bg;
  static const card = panel;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = isLight
        ? const ColorScheme.light(
            surface: panel,
            onSurface: text,
            primary: primary,
            onPrimary: Colors.white,
            secondary: accentPurple,
            error: error,
            outline: border,
            surfaceContainerHighest: panelElevated,
            surfaceContainerHigh: panelElevated,
            surfaceContainer: panel,
            surfaceContainerLow: bg,
            surfaceContainerLowest: bg,
          )
        : const ColorScheme.dark(
            surface: Color(0xFF161B22),
            onSurface: Color(0xFFF1F5F9),
            primary: Color(0xFF60A5FA),
            onPrimary: Color(0xFF0F172A),
            secondary: accentPurple,
            error: error,
            outline: Color(0xFF252B36),
            surfaceContainerHighest: Color(0xFF161B22),
            surfaceContainerHigh: Color(0xFF161B22),
            surfaceContainer: Color(0xFF161B22),
            surfaceContainerLow: Color(0xFF0B0E14),
            surfaceContainerLowest: Color(0xFF0B0E14),
          );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: scheme,
      dividerColor: border,
      iconTheme: IconThemeData(color: muted),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: text, fontSize: 15),
        bodyMedium: TextStyle(color: text, fontSize: 14),
        bodySmall: TextStyle(color: muted, fontSize: 13),
        titleLarge: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 22),
        titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 16),
        labelLarge: TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: panel,
        foregroundColor: text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.06),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: isLight ? 1 : 0,
        shadowColor: isLight ? Colors.black.withValues(alpha: 0.06) : Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: isLight ? border : border),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: sidebar,
        indicatorColor: primary.withValues(alpha: 0.2),
        selectedIconTheme: const IconThemeData(color: sidebarActive),
        unselectedIconTheme: const IconThemeData(color: onSidebarMuted),
        selectedLabelTextStyle: const TextStyle(color: sidebarActive, fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: const TextStyle(color: onSidebarMuted, fontSize: 11),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: sidebar,
        surfaceTintColor: Colors.transparent,
        scrimColor: Color(0x660F172A),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: primary)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Colors.white : panelElevated,
        hintStyle: TextStyle(color: muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primary, width: 1.5)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panelElevated,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selectedColor: primarySoft,
        checkmarkColor: primary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: muted,
        indicatorColor: primary,
        dividerColor: border,
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      listTileTheme: const ListTileThemeData(iconColor: muted, textColor: text),
    );
  }
}
