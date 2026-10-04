import 'package:flutter/material.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/secondary_button.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';

/// Icon plus sentence for one synthetic rule view. Color is not the signal.
class IntakeOutcome extends StatelessWidget {
  const IntakeOutcome({super.key, required this.view, this.onStartOver});

  final SafetyView view;
  final VoidCallback? onStartOver;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = appColorsOf(context);
    final String sentence = outcomeSentence(view.code);
    final String generation = view.permitsOrdinaryGeneration
        ? 'Ordinary exercise generation is allowed by this fixture.'
        : 'Ordinary exercise generation stays off.';
    final String emergency = view.emergencyCode == 'ok'
        ? 'Fixture display: ${view.emergencyDisplay}'
        : 'No emergency number is configured.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Icon(_iconFor(view.code), color: colors.textPrimary, size: 32),
        ),
        const SizedBox(height: AppSpacing.space16),
        Text(sentence),
        const SizedBox(height: AppSpacing.space12),
        Text(generation),
        const SizedBox(height: AppSpacing.space12),
        Text(emergency),
        const SizedBox(height: AppSpacing.space24),
        SecondaryButton(label: 'Start over', onPressed: onStartOver),
      ],
    );
  }
}

String outcomeSentence(String code) {
  switch (code) {
    case 'unmatched':
      return 'The synthetic rule did not match a triage row. Ordinary exercise generation stays off.';
    case 'ineligible':
      return 'The synthetic notice was not acknowledged. Ordinary exercise generation stays off.';
    case 'green':
      return 'The synthetic rule returned green. This is not a clinical clearance.';
    case 'yellow':
      return 'The synthetic rule returned yellow. This is not a clinical restriction.';
    case 'orange':
      return 'The synthetic rule returned orange. Progression stays paused. This is not a referral.';
    case 'red':
      return 'The synthetic rule returned red. Ordinary exercise generation stays off. This is not an emergency instruction.';
    default:
      return 'Something went wrong with the synthetic rule. Ordinary exercise generation stays off.';
  }
}

IconData _iconFor(String code) {
  switch (code) {
    case 'unmatched':
      return Icons.info_outline;
    case 'ineligible':
      return Icons.block;
    case 'green':
      return Icons.check_circle_outline;
    case 'yellow':
      return Icons.flag_outlined;
    case 'orange':
      return Icons.pause_circle_outline;
    case 'red':
      return Icons.stop_circle_outlined;
    default:
      return Icons.error_outline;
  }
}
