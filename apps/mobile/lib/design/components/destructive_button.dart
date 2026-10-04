import 'package:flutter/material.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_radius.dart';
import 'package:helpmemove/design/components/focus_ring.dart';

/// Critical filled button with the same size and focus ring as [PrimaryButton].
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = appColorsOf(context);
    return OutsideFocusRing(
      color: colors.accent,
      borderRadius: AppRadius.large,
      child: FilledButton(
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(120, 52)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 20),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.large)),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return colors.surfaceMuted;
            }
            return colors.critical;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return colors.textMuted;
            }
            return colors.onCritical;
          }),
        ),
        child: Text(label),
      ),
    );
  }
}
