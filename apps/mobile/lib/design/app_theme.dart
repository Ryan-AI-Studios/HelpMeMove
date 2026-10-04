import 'package:flutter/material.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_typography.dart';

/// Measured themes. Colors come from [AppColors], not a generated scheme.
abstract final class AppTheme {
  static ThemeData light() {
    return _theme(AppColors.light, Brightness.light);
  }

  static ThemeData dark() {
    return _theme(AppColors.dark, Brightness.dark);
  }

  static ThemeData highContrastLight() {
    return _theme(AppColors.highContrastLight, Brightness.light);
  }

  static ThemeData highContrastDark() {
    return _theme(AppColors.highContrastDark, Brightness.dark);
  }

  static ThemeData _theme(AppColors colors, Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      error: colors.critical,
      onError: colors.onCritical,
      surface: colors.surface,
      onSurface: colors.textPrimary,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      dividerColor: colors.divider,
      textTheme: AppTypography.textTheme,
      extensions: <ThemeExtension<dynamic>>[colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: const Color(0x00000000),
      ),
    );
  }
}
