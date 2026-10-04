import 'package:flutter/material.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_radius.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/focus_ring.dart';

/// Accent filled button. Disabled and loading use muted colors, not a faded accent.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = appColorsOf(context);
    final bool enabled = !loading && onPressed != null;
    final Widget button = FilledButton(
      onPressed: enabled ? onPressed : null,
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
          if (states.contains(WidgetState.pressed)) {
            return colors.accentPressed;
          }
          return colors.accent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.disabled)) {
            return colors.textMuted;
          }
          return colors.onAccent;
        }),
        iconColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.textMuted;
          }
          return colors.onAccent;
        }),
      ),
      child: loading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(width: AppSpacing.space8),
                Text(label),
              ],
            )
          : Text(label),
    );
    final Widget labeled = loading
        ? Semantics(
            label: 'Loading',
            button: true,
            enabled: false,
            container: true,
            excludeSemantics: true,
            child: button,
          )
        : button;
    return OutsideFocusRing(
      color: colors.accent,
      borderRadius: AppRadius.large,
      child: labeled,
    );
  }
}
