import 'package:flutter/material.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_radius.dart';
import 'package:helpmemove/design/components/focus_ring.dart';

/// Text-only accent button with a 48 by 48 minimum box.
class TertiaryButton extends StatelessWidget {
  const TertiaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = appColorsOf(context);
    return OutsideFocusRing(
      color: colors.accent,
      borderRadius: AppRadius.large,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 48)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 12),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.large)),
            ),
          ),
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
          backgroundColor: const WidgetStatePropertyAll<Color>(
            Color(0x00000000),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
