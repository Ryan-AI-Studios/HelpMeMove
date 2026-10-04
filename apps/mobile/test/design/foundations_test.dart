import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_colors.dart';

import 'pump_app.dart';

void main() {
  testWidgets('foundations shows the card, pain level, warning, and remove', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await pumpApp(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Foundations'));
      await pumpPastNavigation(tester);

      await tester.ensureVisible(find.text('Sample card'));
      expect(find.text('Sample card'), findsOneWidget);
      expect(find.text('Specimen'), findsOneWidget);
      await tester.ensureVisible(find.text('Display Large'));
      expect(find.text('Display Large'), findsOneWidget);
      await tester.ensureVisible(find.text('Label Small'));
      expect(find.text('Label Small'), findsOneWidget);
      await tester.ensureVisible(find.text('warningSoft'));
      expect(find.text('warningSoft'), findsOneWidget);
      expect(find.bySemanticsLabel('Pain level'), findsOneWidget);

      await tester.ensureVisible(find.byType(Slider));
      final ValueChanged<double>? onChanged = tester
          .widget<Slider>(find.byType(Slider))
          .onChanged;
      expect(onChanged, isNotNull);
      onChanged?.call(4);
      await tester.pump();

      final Text value = tester.widget<Text>(find.text('4 out of 10'));
      expect(value.style?.color, AppColors.light.warningText);
      final ColoredBox background = tester.widget<ColoredBox>(
        find.byKey(const Key('pain-value-background')),
      );
      expect(background.color, AppColors.light.warningSoft);

      await tester.ensureVisible(find.text('Remove sample'));
      await tester.tap(find.text('Remove sample'));
      await tester.pump();
      expect(find.text('Sample remove requested'), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });
}
