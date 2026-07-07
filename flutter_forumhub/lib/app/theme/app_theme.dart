import 'package:flutter/material.dart';

final class AppTheme {
  static const Color paper = Color(0xFFF6F0E2);
  static const Color paperDeep = Color(0xFFE7D9B8);
  static const Color ink = Color(0xFF2D2418);
  static const Color secondaryInk = Color(0xFF5B4D39);
  static const Color accent = Color(0xFF9A5B2A);

  static ThemeData light() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: paper,
    );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: paper,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: secondaryInk,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: secondaryInk,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.72),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
