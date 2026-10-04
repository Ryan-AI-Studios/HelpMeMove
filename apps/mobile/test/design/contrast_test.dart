import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_colors.dart';

double _linearize(double channel) {
  if (channel <= 0.04045) {
    return channel / 12.92;
  }
  return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) {
  return 0.2126 * _linearize(color.r) +
      0.7152 * _linearize(color.g) +
      0.0722 * _linearize(color.b);
}

double _contrast(Color foreground, Color background) {
  final double lighter = math.max(
    _luminance(foreground),
    _luminance(background),
  );
  final double darker = math.min(
    _luminance(foreground),
    _luminance(background),
  );
  return (lighter + 0.05) / (darker + 0.05);
}

void _expectContrast(Color foreground, Color background, double minimum) {
  expect(_contrast(foreground, background), greaterThanOrEqualTo(minimum));
}

void main() {
  const Color white = Color(0xFFFFFFFF);

  test('dark onAccent and onCritical are not white', () {
    expect(AppColors.dark.onAccent, isNot(white));
    expect(AppColors.dark.onCritical, isNot(white));
    expect(AppColors.dark.onAccent, const Color(0xFF121713));
    expect(AppColors.dark.onCritical, const Color(0xFF121713));
  });

  test('light text pairs are at least 4.5 to 1', () {
    const AppColors colors = AppColors.light;
    _expectContrast(colors.textPrimary, colors.surface, 4.5);
    _expectContrast(colors.textSecondary, colors.surface, 4.5);
    _expectContrast(colors.textMuted, colors.surface, 4.5);
    _expectContrast(colors.onAccent, colors.accent, 4.5);
    _expectContrast(colors.accent, colors.surface, 4.5);
    _expectContrast(colors.warningText, colors.warningSoft, 4.5);
    _expectContrast(colors.onCritical, colors.critical, 4.5);
  });

  test('dark text pairs are at least 4.5 to 1', () {
    const AppColors colors = AppColors.dark;
    _expectContrast(colors.textPrimary, colors.surface, 4.5);
    _expectContrast(colors.textSecondary, colors.surface, 4.5);
    _expectContrast(colors.textMuted, colors.surface, 4.5);
    _expectContrast(colors.onAccent, colors.accent, 4.5);
    _expectContrast(colors.warningText, colors.warningSoft, 4.5);
    _expectContrast(colors.onCritical, colors.critical, 4.5);
  });

  test('high-contrast light pairs are at least 7 to 1', () {
    const AppColors colors = AppColors.highContrastLight;
    _expectContrast(colors.textPrimary, colors.surface, 7);
    _expectContrast(colors.textMuted, const Color(0xFFFFFFFF), 7);
    _expectContrast(colors.onAccent, colors.accent, 7);
    _expectContrast(colors.warningText, const Color(0xFFFFF4D6), 7);
  });

  test('high-contrast dark pairs are at least 7 to 1', () {
    const AppColors colors = AppColors.highContrastDark;
    _expectContrast(colors.textPrimary, const Color(0xFF000000), 7);
    _expectContrast(colors.textMuted, const Color(0xFF000000), 7);
    _expectContrast(colors.onAccent, colors.accent, 7);
    _expectContrast(colors.warningText, const Color(0xFF000000), 7);
  });
}
