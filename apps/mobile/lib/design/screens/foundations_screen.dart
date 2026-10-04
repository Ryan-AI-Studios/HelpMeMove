import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/app_card.dart';
import 'package:helpmemove/design/components/destructive_button.dart';
import 'package:helpmemove/design/components/pain_slider.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/secondary_button.dart';
import 'package:helpmemove/design/components/tertiary_button.dart';

class FoundationsScreen extends StatefulWidget {
  const FoundationsScreen({super.key});

  @override
  State<FoundationsScreen> createState() => _FoundationsScreenState();
}

class _FoundationsScreenState extends State<FoundationsScreen> {
  var _removeRequested = false;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = appColorsOf(context);
    final TextTheme text = Theme.of(context).textTheme;
    final List<Widget> scale = [
      Text('Display Large', style: text.displayLarge),
      Text('Display Medium', style: text.displayMedium),
      Text('Headline Large', style: text.headlineLarge),
      Text('Headline Medium', style: text.headlineMedium),
      Text('Title Large', style: text.titleLarge),
      Text('Title Medium', style: text.titleMedium),
      Text('Body Large', style: text.bodyLarge),
      Text('Body Medium', style: text.bodyMedium),
      Text('Body Small', style: text.bodySmall),
      Text('Label Large', style: text.labelLarge),
      Text('Label Medium', style: text.labelMedium),
      Text('Label Small', style: text.labelSmall),
    ];
    final List<(String, Color)> swatches = [
      ('surface', colors.surface),
      ('surfaceElevated', colors.surfaceElevated),
      ('surfaceMuted', colors.surfaceMuted),
      ('textPrimary', colors.textPrimary),
      ('textSecondary', colors.textSecondary),
      ('textMuted', colors.textMuted),
      ('accent', colors.accent),
      ('accentPressed', colors.accentPressed),
      ('accentSoft', colors.accentSoft),
      ('onAccent', colors.onAccent),
      ('success', colors.success),
      ('warning', colors.warning),
      ('warningSoft', colors.warningSoft),
      ('warningText', colors.warningText),
      ('critical', colors.critical),
      ('criticalSoft', colors.criticalSoft),
      ('onCritical', colors.onCritical),
      ('info', colors.info),
      ('border', colors.border),
      ('divider', colors.divider),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Foundations')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PrimaryButton(label: 'Primary', onPressed: _noop),
              const SizedBox(height: AppSpacing.space12),
              const SecondaryButton(label: 'Secondary', onPressed: _noop),
              const SizedBox(height: AppSpacing.space12),
              TertiaryButton(
                label: 'Focused flow',
                onPressed: () => context.go('/focus'),
              ),
              const SizedBox(height: AppSpacing.space12),
              DestructiveButton(
                label: 'Remove sample',
                onPressed: () {
                  setState(() {
                    _removeRequested = true;
                  });
                },
              ),
              if (_removeRequested) ...[
                const SizedBox(height: AppSpacing.space12),
                const Text('Sample remove requested'),
              ],
              const SizedBox(height: AppSpacing.space12),
              const PrimaryButton(label: 'Disabled'),
              const SizedBox(height: AppSpacing.space12),
              const PrimaryButton(label: 'Loading sample', loading: true),
              const SizedBox(height: AppSpacing.space16),
              const PainSlider(),
              const SizedBox(height: AppSpacing.space16),
              const AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sample card'),
                    SizedBox(height: AppSpacing.space8),
                    Text('Specimen'),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space16),
              const Text('Later destinations: Move, Progress, Coach, You.'),
              const SizedBox(height: AppSpacing.space24),
              ...[
                for (final Widget name in scale) ...[
                  name,
                  const SizedBox(height: AppSpacing.space8),
                ],
              ],
              const SizedBox(height: AppSpacing.space16),
              for (final (String name, Color color) in swatches) ...[
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(color: colors.border),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(4),
                        ),
                      ),
                      child: const SizedBox(width: 24, height: 24),
                    ),
                    const SizedBox(width: AppSpacing.space12),
                    Expanded(child: Text(name)),
                  ],
                ),
                const SizedBox(height: AppSpacing.space8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void _noop() {}
