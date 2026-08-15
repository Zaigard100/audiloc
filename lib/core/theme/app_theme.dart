import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Cover-forward theme in the spirit of ТЗ's "Яндекс Музыки" reference
/// (bottom mini-player, big artwork) — built from scratch with an
/// unrelated accent color and no borrowed iconography, per ТЗ п.1 ("без
/// копирования логотипа и брендированных элементов"). [dark] was the
/// only variant until docs/adr/0028-settings-screen-and-theming.md added
/// [light] and a real switcher for it.
class AppTheme {
  AppTheme._();

  /// Shared across both themes — a brand accent generally shouldn't
  /// flip with light/dark, and keeping it a plain `static const` (rather
  /// than moving it into [AppColors]) means the ~24 call sites that use
  /// it in `const` widget trees didn't need touching for this ADR.
  static const accent = Color(0xFF7C5CFF);
  static const error = Color(0xFFFF6B6B);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      surface: colors.surface,
      onSurface: colors.onSurface,
      error: error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: accent.withValues(alpha: 0.25),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? colors.onSurface : colors.onSurfaceMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? accent : colors.onSurfaceMuted,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceHigh,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: colors.divider,
        thumbColor: colors.onSurface,
        overlayColor: accent.withValues(alpha: 0.15),
        trackHeight: 3,
      ),
      dividerTheme: DividerThemeData(color: colors.divider),
      textTheme: (brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
            bodyColor: colors.onSurface,
            displayColor: colors.onSurface,
          ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.onSurfaceMuted,
        textColor: colors.onSurface,
      ),
      // Material 3's default SnackBar deliberately inverts relative to
      // the surrounding theme (dark text on a light bar in a light
      // theme, and vice versa) — its exact colors come from
      // `ColorScheme.inverseSurface`/`onInverseSurface`/`inversePrimary`,
      // none of which the plain `ColorScheme(...)` constructor above sets
      // explicitly, so they fell back to Material's own defaults instead
      // of this app's palette — the "Продолжить" resume-playback action
      // text ended up unreadable against its own background in dark mode
      // (docs/adr/0029-playback-state-sync.md). Explicit theme instead:
      // themed like the rest of the app (not inverted), so it's readable
      // by construction in both modes.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceHigh,
        contentTextStyle: TextStyle(color: colors.onSurface),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
