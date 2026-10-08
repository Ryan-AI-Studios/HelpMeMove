import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/components/destructive_button.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/main.dart';

const String _evidenceDirectory =
    r'C:\dev\HelpMeMove\conductor\0005-EncryptedLocalProfilesAndRecovery\ui-evidence';

bool _captureFontReady = false;

ThemeData _platformFont(ThemeData theme) {
  if (!_captureFontReady) {
    return theme;
  }
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Segoe UI'),
  );
}

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
    HelpMeMoveApp(
      initialLocation: initialLocation,
      recovery: recovery,
      adaptTheme: _platformFont,
    ),
  );
  await tester.pump();
}

Future<void> _capture(
  WidgetTester tester,
  String name, {
  Key key = const Key('storage-capture'),
  bool requirePhoneSize = true,
}) async {
  if (!_captureFontReady) {
    return;
  }
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(key));
  expect(boundary.size.width, greaterThan(200));
  if (requirePhoneSize) {
    expect(boundary.size.height, greaterThan(700));
  }
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
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final List<File> fonts = <File>[
      File(r'C:\Windows\Fonts\segoeui.ttf'),
      File(r'C:\Windows\Fonts\segoeuib.ttf'),
    ];
    if (fonts.any((File file) => !file.existsSync())) {
      return;
    }
    final FontLoader loader = FontLoader('Segoe UI');
    for (final File file in fonts) {
      final Uint8List bytes = await file.readAsBytes();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
    _captureFontReady = true;
  });

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
    await _capture(
      tester,
      'key-loss-confirm-390.png',
      key: const Key('storage-confirm-capture'),
      requirePhoneSize: false,
    );
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
    final Finder retry = find.widgetWithText(PrimaryButton, 'Retry');
    final Finder reset = find.widgetWithText(
      DestructiveButton,
      'Reset local data',
    );
    await tester.ensureVisible(retry);
    await tester.pump();
    await _capture(tester, 'key-loss-light-390-scale-2.png');
    expect(tester.getRect(retry).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(retry).bottom, lessThanOrEqualTo(size.height));
    await tester.ensureVisible(reset);
    await tester.pump();
    await _capture(tester, 'key-loss-light-390-scale-2-reset.png');
    expect(tester.getRect(reset).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(reset).bottom, lessThanOrEqualTo(size.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a retry that fails after reset still leaves storage failure', (
    tester,
  ) async {
    final Completer<void> resetHold = Completer<void>();
    final Completer<void> retryHold = Completer<void>();
    await _pump(
      tester,
      size: const Size(390, 844),
      textScale: 1,
      initialLocation: '/key-loss',
      recovery: StorageRecovery(
        onRetry: () async {
          await retryHold.future;
          return '/storage-failure';
        },
        onReset: () async {
          await resetHold.future;
          return '/';
        },
      ),
    );
    await tester.tap(find.text('Reset local data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Delete local data'));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    resetHold.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Scaffold check'), findsOneWidget);
    retryHold.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Storage is unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
