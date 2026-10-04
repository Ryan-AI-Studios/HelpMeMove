import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/main.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
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

/// Advances a route animation without waiting for the loading specimen's spinner.
Future<void> pumpPastNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
