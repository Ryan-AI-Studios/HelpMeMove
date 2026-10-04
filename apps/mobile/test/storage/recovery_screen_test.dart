import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/main.dart';

const String _evidenceDirectory =
    r'C:\dev\HelpMeMove\conductor\0005-EncryptedLocalProfilesAndRecovery\ui-evidence';

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  String initialLocation = '/',
  StorageRecovery? recovery,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    HelpMeMoveApp(initialLocation: initialLocation, recovery: recovery),
  );
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('storage-capture')),
      );
  expect(boundary.size.width, greaterThan(300));
  expect(boundary.size.height, greaterThan(700));
  final ui.Image image = await boundary.toImage(pixelRatio: 1);
  expect(image.width, boundary.size.width.round());
  expect(image.height, boundary.size.height.round());
  final ByteData? data = await tester.runAsync<ByteData?>(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  expect(data, isNotNull);
  final File file = File('$_evidenceDirectory${Platform.pathSeparator}$name');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  testWidgets('storage failure hides the shell and retries home', (
    tester,
  ) async {
    var retries = 0;
    const Size size = Size(390, 844);
    await _pump(
      tester,
      size: size,
      textScale: 1,
      initialLocation: '/storage-failure',
      recovery: StorageRecovery(
        onRetry: () async {
          retries += 1;
          return '/';
        },
        onReset: () async => '/key-loss',
      ),
    );
    expect(find.text('Storage is unavailable'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    await _capture(tester, 'storage-failure-light-390.png');

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(retries, 1);
    expect(find.text('Scaffold check'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('storage failure uses the dark theme', (tester) async {
    const Size size = Size(390, 844);
    await _pump(
      tester,
      size: size,
      textScale: 1,
      brightness: Brightness.dark,
      initialLocation: '/storage-failure',
      recovery: StorageRecovery(
        onRetry: () async => '/storage-failure',
        onReset: () async => '/storage-failure',
      ),
    );
    expect(find.text('Storage is unavailable'), findsOneWidget);
    await _capture(tester, 'storage-failure-dark-390.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('key loss confirms reset and cancel stays put', (tester) async {
    var retries = 0;
    var resets = 0;
    const Size size = Size(390, 844);
    await _pump(
      tester,
      size: size,
      textScale: 1,
      initialLocation: '/key-loss',
      recovery: StorageRecovery(
        onRetry: () async {
          retries += 1;
          return '/key-loss';
        },
        onReset: () async {
          resets += 1;
          return '/';
        },
      ),
    );
    expect(find.text('Local data cannot be opened'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await _capture(tester, 'key-loss-light-390.png');

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(retries, 1);
    expect(find.text('Local data cannot be opened'), findsOneWidget);

    await tester.tap(find.text('Reset local data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Delete local data?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Delete local data?'), findsNothing);
    expect(resets, 0);
    expect(find.text('Local data cannot be opened'), findsOneWidget);

    await tester.tap(find.text('Reset local data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Delete local data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(resets, 1);
    expect(find.text('Scaffold check'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('key loss actions stay reachable at text scale 2', (
    tester,
  ) async {
    const Size size = Size(390, 844);
    await _pump(
      tester,
      size: size,
      textScale: 2,
      initialLocation: '/key-loss',
      recovery: StorageRecovery(
        onRetry: () async => '/key-loss',
        onReset: () async => '/key-loss',
      ),
    );
    await _capture(tester, 'key-loss-light-390-scale-2.png');
    await tester.ensureVisible(find.text('Retry'));
    await tester.pump();
    expect(tester.getRect(find.text('Retry')).height, greaterThan(0));
    expect(
      tester.getRect(find.text('Retry')).bottom,
      lessThanOrEqualTo(size.height),
    );
    expect(tester.getRect(find.text('Retry')).top, greaterThanOrEqualTo(0));
    await tester.ensureVisible(find.text('Reset local data'));
    await tester.pump();
    expect(
      tester.getRect(find.text('Reset local data')).height,
      greaterThan(0),
    );
    expect(
      tester.getRect(find.text('Reset local data')).bottom,
      lessThanOrEqualTo(size.height),
    );
    expect(
      tester.getRect(find.text('Reset local data')).top,
      greaterThanOrEqualTo(0),
    );
    expect(tester.takeException(), isNull);
  });
}
