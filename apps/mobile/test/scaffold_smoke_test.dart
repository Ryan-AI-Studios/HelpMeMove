import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/main.dart';

Future<void> _show(
  WidgetTester tester, {
  required Size size,
  required double textScale,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(const HelpMeMoveApp());
  await tester.pump();
}

void _expectOnScreen(WidgetTester tester, String text, Size size) {
  expect(find.text(text), findsOneWidget);
  final rect = tester.getRect(find.text(text));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(size.width));
  expect(rect.bottom, lessThanOrEqualTo(size.height));
}

void main() {
  testWidgets('compact scaffold check completes', (tester) async {
    const size = Size(390, 844);
    await _show(tester, size: size, textScale: 1);
    _expectOnScreen(tester, 'HelpMeMove', size);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Scaffold check'),
    );
    expect(button.onPressed, isNotNull);
    _expectOnScreen(tester, 'Scaffold check', size);

    await tester.tap(find.text('Scaffold check'));
    await tester.pump();
    _expectOnScreen(tester, 'Scaffold check completed', size);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact text scale 1.3 still completes', (tester) async {
    const size = Size(390, 844);
    await _show(tester, size: size, textScale: 1.3);
    _expectOnScreen(tester, 'HelpMeMove', size);
    _expectOnScreen(tester, 'Scaffold check', size);

    await tester.tap(find.text('Scaffold check'));
    await tester.pump();
    _expectOnScreen(tester, 'Scaffold check completed', size);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded width shows the same scaffold check', (tester) async {
    const size = Size(840, 1200);
    await _show(tester, size: size, textScale: 1);
    _expectOnScreen(tester, 'HelpMeMove', size);
    _expectOnScreen(tester, 'Scaffold check', size);
    expect(tester.takeException(), isNull);
  });
}
