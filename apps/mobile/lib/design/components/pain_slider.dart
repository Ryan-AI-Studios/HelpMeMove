import 'package:flutter/material.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_spacing.dart';

/// Specimen slider from 0 to 10. A null [value] keeps the number in this widget.
class PainSlider extends StatefulWidget {
  const PainSlider({super.key, this.value, this.onChanged});

  final int? value;
  final ValueChanged<int>? onChanged;

  @override
  State<PainSlider> createState() => _PainSliderState();
}

class _PainSliderState extends State<PainSlider> {
  double _value = 0;

  double get _shown {
    final int? external = widget.value;
    if (external == null) {
      return _value;
    }
    final int clamped = external < 0 ? 0 : (external > 10 ? 10 : external);
    return clamped.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = appColorsOf(context);
    final double shown = _shown;
    final int level = shown.round();
    final bool warning = level >= 4;
    final Color background = warning ? colors.warningSoft : colors.accentSoft;
    final Color foreground = warning ? colors.warningText : colors.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ColoredBox(
            key: const Key('pain-value-background'),
            color: background,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space8,
                vertical: AppSpacing.space4,
              ),
              child: Text(
                '$level out of 10',
                style: TextStyle(color: foreground),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space8),
        Semantics(
          label: 'Pain level',
          container: true,
          slider: true,
          value: '$level',
          child: ExcludeSemantics(
            child: Slider(
              value: shown,
              min: 0,
              max: 10,
              divisions: 10,
              onChanged: (double next) {
                final int reported = next.round();
                final ValueChanged<int>? report = widget.onChanged;
                if (report != null) {
                  report(reported);
                }
                if (widget.value == null) {
                  setState(() {
                    _value = next;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}
