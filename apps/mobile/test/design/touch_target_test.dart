import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/components/destructive_button.dart';
import 'package:helpmemove/design/components/pain_slider.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/secondary_button.dart';
import 'package:helpmemove/design/components/tertiary_button.dart';

import 'pump_app.dart';

void _expectBox(WidgetTester tester, Finder finder) {
  expect(finder, findsWidgets);
  for (var index = 0; index < finder.evaluate().length; index++) {
    final Size size = tester.getSize(finder.at(index));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  }
}

void main() {
  testWidgets('controls and destinations are at least 48 by 48', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Foundations'));
    await pumpPastNavigation(tester);

    _expectBox(tester, find.byType(PrimaryButton));
    _expectBox(tester, find.byType(SecondaryButton));
    _expectBox(tester, find.byType(TertiaryButton));
    _expectBox(tester, find.byType(DestructiveButton));
    _expectBox(tester, find.byType(PainSlider));
    _expectBox(tester, find.byType(Slider));
    _expectBox(tester, find.byType(NavigationDestination));
    expect(find.byType(NavigationDestination), findsNWidgets(2));
  });
}
