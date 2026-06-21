import 'package:flutter/material.dart';

/// Brand palette and design tokens shared across the dark/light themes.
class AppColors {
  AppColors._();

  // Brand
  static const brandBlue = Color(0xFF2E7CF6);
  static const brandCyan = Color(0xFF22D3EE);
  static const connected = Color(0xFF22C55E);
  static const connectedDeep = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  // Dark surfaces
  static const darkBg = Color(0xFF0B1020);
  static const darkSurface = Color(0xFF161C2D);
  static const darkSurfaceHi = Color(0xFF1C2438);
  static const darkBorder = Color(0xFF263149);

  // Light surfaces
  static const lightBg = Color(0xFFF6F8FC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE2E8F0);

  /// The signature blue→cyan gradient used on the connect orb and accents.
  static const brandGradient = LinearGradient(
    colors: [brandBlue, brandCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Green gradient for the connected state.
  static const connectedGradient = LinearGradient(
    colors: [connectedDeep, connected],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Convenience accessors for theme-aware colors the widgets reach for often.
extension AppThemeX on BuildContext {
  ColorScheme get scheme => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Muted secondary text/icon color.
  Color get muted => scheme.onSurface.withValues(alpha: 0.55);

  /// Hairline border / divider color.
  Color get hairline =>
      isDark ? AppColors.darkBorder : AppColors.lightBorder;

  /// Card / panel surface color.
  Color get panel => isDark ? AppColors.darkSurface : AppColors.lightSurface;

  /// Slightly elevated surface (selected cards, inset rows).
  Color get panelHi =>
      isDark ? AppColors.darkSurfaceHi : const Color(0xFFF1F5F9);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandBlue,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.brandBlue,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppColors.darkSurfaceHi : const Color(0xFF1E293B),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: AppColors.brandCyan,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      ),
    );
  }
}
