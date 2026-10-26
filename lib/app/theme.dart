import 'package:flutter/material.dart';

/// SolLapChecker brand palette.
class AppColors {
  AppColors._();

  static const navy = Color(0xFF0B1F3A); // window background
  static const navyDeep = Color(0xFF07152A); // title bar / sidebar
  static const navySoft = Color(0xFF112A4D); // raised surfaces
  static const primary = Color(0xFF1E90FF); // electric blue
  static const pass = Color(0xFF22C55E);
  static const fail = Color(0xFFEF4444);
  static const accent = Color(0xFFF59E0B); // gold: warnings, highlights
  static const text = Color(0xFFE6EEFB);
  static const muted = Color(0xFF8EA3C0);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.accent,
    // Chips and tonal buttons use this; without it they inherit the gold accent.
    secondaryContainer: Color(0xFF173A66),
    onSecondaryContainer: AppColors.text,
    error: AppColors.fail,
    surface: AppColors.navy,
    onSurface: AppColors.text,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.navy,
    fontFamily: 'Inter',
    textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: 'Inter',
          bodyColor: AppColors.text,
          displayColor: AppColors.text,
        ),
    dividerColor: Colors.white.withValues(alpha: 0.08),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.navySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
  );
}
