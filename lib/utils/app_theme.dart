// lib/utils/app_theme.dart
// Dark / light theme definitions — exact color ports from ThemeManager.kt

import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand colors (theme-agnostic) ─────────────────────────────────────────
  static const Color accent    = Color(0xFF25D366); // WhatsApp green
  static const Color danger    = Color(0xFFE53935);
  static const Color warning   = Color(0xFFFF9800);
  static const Color info      = Color(0xFF2196F3);

  // ── Dark theme ────────────────────────────────────────────────────────────
  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0A0E27),
    colorScheme: ColorScheme.dark(
      primary:   accent,
      secondary: const Color(0xFF5C35CC),
      surface:   const Color(0xFF1A1A2E),
      error:     danger,
    ),
    cardColor:  const Color(0xFF16213E),
    dividerColor: const Color(0xFF2D3E5F),
    textTheme: const TextTheme(
      bodyLarge:   TextStyle(color: Color(0xFFFFFFFF)),
      bodyMedium:  TextStyle(color: Color(0xFFCCCCCC)),
      bodySmall:   TextStyle(color: Color(0xFF888888)),
      titleLarge:  TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.w600),
      labelSmall:  TextStyle(color: Color(0xFF888888)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1A2E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2D3E5F)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2D3E5F)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accent, width: 2),
      ),
      hintStyle: const TextStyle(color: Color(0xFF555577)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : Colors.grey),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent.withOpacity(0.4) : Colors.grey.shade800),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1A1A2E),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1A1A2E),
      selectedItemColor: accent,
      unselectedItemColor: Color(0xFF888888),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF16213E),
      selectedColor: accent.withOpacity(0.2),
      labelStyle: const TextStyle(color: Color(0xFFCCCCCC)),
      side: const BorderSide(color: Color(0xFF2D3E5F)),
    ),
    useMaterial3: true,
  );

  // ── Light theme ───────────────────────────────────────────────────────────
  static final ThemeData light = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF5F5F5),
    colorScheme: ColorScheme.light(
      primary:   accent,
      secondary: const Color(0xFF5C35CC),
      surface:   Colors.white,
      error:     danger,
    ),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE0E0E0),
    textTheme: const TextTheme(
      bodyLarge:   TextStyle(color: Color(0xFF000000)),
      bodyMedium:  TextStyle(color: Color(0xFF333333)),
      bodySmall:   TextStyle(color: Color(0xFF666666)),
      titleLarge:  TextStyle(color: Color(0xFF000000), fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: Color(0xFF000000), fontWeight: FontWeight.w600),
      labelSmall:  TextStyle(color: Color(0xFF999999)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accent, width: 2),
      ),
      hintStyle: const TextStyle(color: Color(0xFFAAAAAA)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : Colors.grey.shade400),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent.withOpacity(0.4) : Colors.grey.shade300),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF000000),
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: accent,
      unselectedItemColor: Color(0xFF999999),
    ),
    useMaterial3: true,
  );
}
