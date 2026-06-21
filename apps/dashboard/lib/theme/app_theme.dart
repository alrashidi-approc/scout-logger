import 'package:flutter/material.dart';

class AppTheme {
  // Dark dashboard palette (Audit Log / Open 360 inspired)
  static const bg = Color(0xFF0B0E14);
  static const sidebar = Color(0xFF070A10);
  static const sidebarHover = Color(0xFF121820);
  static const panel = Color(0xFF161B22);
  static const panelElevated = Color(0xFF1C2330);
  static const border = Color(0xFF252B36);
  static const text = Color(0xFFF1F5F9);
  static const muted = Color(0xFF8892A4);
  static const primary = Color(0xFF2DD4BF);
  static const primarySoft = Color(0x142DD4BF);
  static const accentPurple = Color(0xFF8B5CF6);
  static const accentPink = Color(0xFFEC4899);
  static const error = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);
  static const success = Color(0xFF34D399);
  static const info = Color(0xFF38BDF8);

  // Legacy aliases (widgets reference these)
  static const surface = bg;
  static const card = panel;

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      surface: panel,
      onSurface: text,
      primary: primary,
      onPrimary: bg,
      secondary: accentPurple,
      error: error,
      outline: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      dividerColor: border,
      iconTheme: const IconThemeData(color: muted),
      appBarTheme: const AppBarTheme(
        backgroundColor: panel,
        foregroundColor: text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: border)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: sidebar,
        indicatorColor: primary.withValues(alpha: 0.15),
        selectedIconTheme: const IconThemeData(color: primary),
        unselectedIconTheme: const IconThemeData(color: muted),
        selectedLabelTextStyle: const TextStyle(color: primary, fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: const TextStyle(color: muted, fontSize: 11),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: bg,
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
        fillColor: panelElevated,
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primary, width: 1.5)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panelElevated,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: panelElevated,
        contentTextStyle: const TextStyle(color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: muted,
        indicatorColor: primary,
        dividerColor: border,
      ),
    );
  }

  static ThemeData light() => dark();
}
