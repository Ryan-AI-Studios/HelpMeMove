import 'package:flutter/material.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_radius.dart';
import 'package:helpmemove/design/app_spacing.dart';

/// Elevated surface with a 16 dp radius, 16 dp padding, and a 1 dp border.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = appColorsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.large)),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: child,
      ),
    );
  }
}
