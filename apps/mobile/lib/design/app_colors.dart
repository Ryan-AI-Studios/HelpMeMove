import 'package:flutter/material.dart';

/// Semantic colors for the four measured palettes.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentPressed,
    required this.accentSoft,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.warningSoft,
    required this.warningText,
    required this.critical,
    required this.criticalSoft,
    required this.onCritical,
    required this.info,
    required this.border,
    required this.divider,
  });

  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentPressed;
  final Color accentSoft;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color warningSoft;
  final Color warningText;
  final Color critical;
  final Color criticalSoft;
  final Color onCritical;
  final Color info;
  final Color border;
  final Color divider;

  static const light = AppColors(
    surface: Color(0xFFF7F8F6),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF1ED),
    textPrimary: Color(0xFF18201B),
    textSecondary: Color(0xFF58615A),
    textMuted: Color(0xFF68726A),
    accent: Color(0xFF3C7A62),
    accentPressed: Color(0xFF2F644F),
    accentSoft: Color(0xFFE2F0E8),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D5A),
    warning: Color(0xFFB7791F),
    warningSoft: Color(0xFFFFF4D6),
    warningText: Color(0xFF7A4D12),
    critical: Color(0xFFB64A4A),
    criticalSoft: Color(0xFFFCE7E7),
    onCritical: Color(0xFFFFFFFF),
    info: Color(0xFF4B6F91),
    border: Color(0xFFD9DEDA),
    divider: Color(0xFFE5E9E6),
  );

  static const dark = AppColors(
    surface: Color(0xFF121713),
    surfaceElevated: Color(0xFF1A211C),
    surfaceMuted: Color(0xFF232B25),
    textPrimary: Color(0xFFF4F7F5),
    textSecondary: Color(0xFFBCC6BE),
    textMuted: Color(0xFF8E9A91),
    accent: Color(0xFF65A988),
    accentPressed: Color(0xFF82B99D),
    accentSoft: Color(0xFF203B2F),
    onAccent: Color(0xFF121713),
    success: Color(0xFF65A988),
    warning: Color(0xFFE2B35F),
    warningSoft: Color(0xFF3A2E19),
    warningText: Color(0xFFE2B35F),
    critical: Color(0xFFE07676),
    criticalSoft: Color(0xFF3C2020),
    onCritical: Color(0xFF121713),
    info: Color(0xFF7BA4C8),
    border: Color(0xFF334039),
    divider: Color(0xFF28332D),
  );

  static const highContrastLight = AppColors(
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF1ED),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF58615A),
    textMuted: Color(0xFF3F463F),
    accent: Color(0xFF163E2F),
    accentPressed: Color(0xFF0F3D2E),
    accentSoft: Color(0xFFE2F0E8),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF2E7D5A),
    warning: Color(0xFFB7791F),
    warningSoft: Color(0xFFFFF4D6),
    warningText: Color(0xFF5A380C),
    critical: Color(0xFFB64A4A),
    criticalSoft: Color(0xFFFCE7E7),
    onCritical: Color(0xFFFFFFFF),
    info: Color(0xFF4B6F91),
    border: Color(0xFF000000),
    divider: Color(0xFFE5E9E6),
  );

  static const highContrastDark = AppColors(
    surface: Color(0xFF000000),
    surfaceElevated: Color(0xFF1A211C),
    surfaceMuted: Color(0xFF232B25),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFBCC6BE),
    textMuted: Color(0xFFBCC6BE),
    accent: Color(0xFF8FD0AE),
    accentPressed: Color(0xFF8FD0AE),
    accentSoft: Color(0xFF203B2F),
    onAccent: Color(0xFF000000),
    success: Color(0xFF65A988),
    warning: Color(0xFFE2B35F),
    warningSoft: Color(0xFF000000),
    warningText: Color(0xFFE2B35F),
    critical: Color(0xFFE07676),
    criticalSoft: Color(0xFF3C2020),
    onCritical: Color(0xFF121713),
    info: Color(0xFF7BA4C8),
    border: Color(0xFFFFFFFF),
    divider: Color(0xFF28332D),
  );

  @override
  AppColors copyWith({
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentPressed,
    Color? accentSoft,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? warningSoft,
    Color? warningText,
    Color? critical,
    Color? criticalSoft,
    Color? onCritical,
    Color? info,
    Color? border,
    Color? divider,
  }) {
    return AppColors(
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentPressed: accentPressed ?? this.accentPressed,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      warningText: warningText ?? this.warningText,
      critical: critical ?? this.critical,
      criticalSoft: criticalSoft ?? this.criticalSoft,
      onCritical: onCritical ?? this.onCritical,
      info: info ?? this.info,
      border: border ?? this.border,
      divider: divider ?? this.divider,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      surface: _lerpColor(surface, other.surface, t),
      surfaceElevated: _lerpColor(surfaceElevated, other.surfaceElevated, t),
      surfaceMuted: _lerpColor(surfaceMuted, other.surfaceMuted, t),
      textPrimary: _lerpColor(textPrimary, other.textPrimary, t),
      textSecondary: _lerpColor(textSecondary, other.textSecondary, t),
      textMuted: _lerpColor(textMuted, other.textMuted, t),
      accent: _lerpColor(accent, other.accent, t),
      accentPressed: _lerpColor(accentPressed, other.accentPressed, t),
      accentSoft: _lerpColor(accentSoft, other.accentSoft, t),
      onAccent: _lerpColor(onAccent, other.onAccent, t),
      success: _lerpColor(success, other.success, t),
      warning: _lerpColor(warning, other.warning, t),
      warningSoft: _lerpColor(warningSoft, other.warningSoft, t),
      warningText: _lerpColor(warningText, other.warningText, t),
      critical: _lerpColor(critical, other.critical, t),
      criticalSoft: _lerpColor(criticalSoft, other.criticalSoft, t),
      onCritical: _lerpColor(onCritical, other.onCritical, t),
      info: _lerpColor(info, other.info, t),
      border: _lerpColor(border, other.border, t),
      divider: _lerpColor(divider, other.divider, t),
    );
  }
}

AppColors appColorsOf(BuildContext context) {
  return Theme.of(context).extension<AppColors>() ?? AppColors.light;
}

Color _lerpColor(Color a, Color b, double t) {
  return Color.lerp(a, b, t) ?? a;
}
