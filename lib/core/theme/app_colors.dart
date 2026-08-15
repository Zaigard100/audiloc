import 'package:flutter/material.dart';

/// Semantic colors that actually differ between [AppTheme.light] and
/// [AppTheme.dark] — everything else (accent, error) stays the same
/// across both, so it's a plain `static const` on [AppTheme] rather than
/// living here too. A `ThemeExtension` (not more `static const` fields)
/// specifically so `context.colors.xxx` picks up whichever theme is
/// actually active — the old all-`static const` design (every screen
/// referencing `AppTheme.surface` etc. directly) was silently
/// dark-only: nothing dynamic ever *read* the active theme, so a light
/// `ThemeData` alone wouldn't have changed a single pixel outside of
/// what Material's own defaults cover. See
/// docs/adr/0028-settings-screen-and-theming.md.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.divider,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;

  /// Primary text/icon color at full contrast against [background]/
  /// [surface] — white in dark mode, near-black in light mode. Replaces
  /// what used to be hardcoded `Colors.white` at several call sites that
  /// only ever happened to be correct because the app was dark-only.
  final Color onSurface;

  final Color onSurfaceMuted;
  final Color divider;

  static const dark = AppColors(
    background: Color(0xFF0E0E12),
    surface: Color(0xFF17171D),
    surfaceHigh: Color(0xFF1F1F27),
    onSurface: Colors.white,
    onSurfaceMuted: Color(0xFF9A9AA5),
    divider: Color(0x1FFFFFFF), // Colors.white12
  );

  static const light = AppColors(
    background: Color(0xFFF7F7FA),
    surface: Colors.white,
    surfaceHigh: Color(0xFFEDEDF2),
    onSurface: Color(0xFF17171D),
    onSurfaceMuted: Color(0xFF6C6C77),
    divider: Color(0x1F000000), // Colors.black12
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? divider,
  }) =>
      AppColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        onSurface: onSurface ?? this.onSurface,
        onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
        divider: divider ?? this.divider,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

/// `context.colors` instead of `Theme.of(context).extension<AppColors>()!`.
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
