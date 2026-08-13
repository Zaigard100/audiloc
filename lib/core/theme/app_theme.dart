import 'package:flutter/material.dart';

/// Dark, cover-forward theme in the spirit of ТЗ's "Яндекс Музыки"
/// reference (bottom mini-player, big artwork, dark surfaces) — built from
/// scratch with an unrelated accent color and no borrowed iconography, per
/// ТЗ п.1 ("без копирования логотипа и брендированных элементов").
class AppTheme {
  AppTheme._();

  static const accent = Color(0xFF7C5CFF);
  static const background = Color(0xFF0E0E12);
  static const surface = Color(0xFF17171D);
  static const surfaceHigh = Color(0xFF1F1F27);
  static const onSurfaceMuted = Color(0xFF9A9AA5);

  static ThemeData dark() {
    final colorScheme = const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      surface: surface,
      onSurface: Colors.white,
      error: Color(0xFFFF6B6B),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.25),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? Colors.white : onSurfaceMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? accent : onSurfaceMuted,
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        color: surfaceHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
        thumbColor: Colors.white,
        overlayColor: accent.withValues(alpha: 0.15),
        trackHeight: 3,
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.08)),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
      listTileTheme: const ListTileThemeData(
        iconColor: onSurfaceMuted,
        textColor: Colors.white,
      ),
    );
  }
}
