import 'package:flutter/material.dart';

/// Design-system type scale on the platform font.
abstract final class AppTypography {
  static const textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 36,
      height: 44 / 36,
      fontWeight: FontWeight.w700,
    ),
    displayMedium: TextStyle(
      fontSize: 30,
      height: 38 / 30,
      fontWeight: FontWeight.w700,
    ),
    headlineLarge: TextStyle(
      fontSize: 26,
      height: 34 / 26,
      fontWeight: FontWeight.w700,
    ),
    headlineMedium: TextStyle(
      fontSize: 22,
      height: 30 / 22,
      fontWeight: FontWeight.w700,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      height: 28 / 20,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      height: 26 / 18,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      fontSize: 17,
      height: 26 / 17,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: TextStyle(
      fontSize: 15,
      height: 23 / 15,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      height: 20 / 13,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: TextStyle(
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w600,
    ),
  );
}
