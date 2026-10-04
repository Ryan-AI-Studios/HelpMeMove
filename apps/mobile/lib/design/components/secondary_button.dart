import 'package:flutter/material.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_radius.dart';
import 'package:helpmemove/design/components/focus_ring.dart';

/// Surface-filled button with accent text and a 1 dp border.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, this.onPressed});

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
          minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 52)),
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
            return colors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((
            Set<WidgetState> states,
          ) {
            if (states.contains(WidgetState.disabled)) {
              return colors.textMuted;
            }
            if (states.contains(WidgetState.pressed)) {
              return colors.accentPressed;
            }
            return colors.accent;
          }),
          side: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
            final Color color = states.contains(WidgetState.disabled)
                ? colors.textMuted
                : colors.accent;
            return BorderSide(color: color);
          }),
        ),
        child: Text(label),
      ),
    );
  }
}
