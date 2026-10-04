import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_colors.dart';

import 'pump_app.dart';

bool _buttonFocused(WidgetTester tester, String label) {
  final SemanticsNode node = tester.getSemantics(
    find.widgetWithText(FilledButton, label),
  );
  return node.flagsCollection.isFocused == Tristate.isTrue;
}

void main() {
  testWidgets('platform dark brightness yields the dark theme', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester);

    final ThemeData theme = Theme.of(tester.element(find.text('HelpMeMove')));
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.surface, AppColors.dark.surface);
    expect(theme.extension<AppColors>()?.surface, AppColors.dark.surface);
  });

  testWidgets('high contrast yields the high-contrast surface', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester);

    final ThemeData theme = Theme.of(tester.element(find.text('HelpMeMove')));
    expect(theme.colorScheme.surface, AppColors.highContrastLight.surface);
    expect(
      theme.extension<AppColors>()?.surface,
      AppColors.highContrastLight.surface,
    );
  });

  testWidgets('disabled animations build the focused flow', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester);

    GoRouter.of(tester.element(find.text('HelpMeMove'))).go('/focus');
    await tester.pumpAndSettle();
    expect(find.text('Focused flow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab order focuses scaffold check before bridge check', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await pumpApp(tester);

      var scaffoldStep = -1;
      var bridgeStep = -1;
      for (var step = 0; step < 8; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (scaffoldStep < 0 && _buttonFocused(tester, 'Scaffold check')) {
          scaffoldStep = step;
        }
        if (bridgeStep < 0 && _buttonFocused(tester, 'Bridge check')) {
          bridgeStep = step;
        }
      }

      expect(scaffoldStep, greaterThanOrEqualTo(0));
      expect(bridgeStep, greaterThan(scaffoldStep));
      expect(_buttonFocused(tester, 'Bridge check'), isTrue);
    } finally {
      handle.dispose();
    }
  });
}
