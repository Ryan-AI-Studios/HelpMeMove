import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/coach/explain_screen.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_theme.dart';

const String _evidenceDirectory =
    r'C:\dev\HelpMeMove\Conductor\0030-ValidatedConversationalCoach\ui-evidence';

const String _consent =
    'Send the selected area or focus to Ollama Cloud for an explanation? It does not send typed or spoken symptoms.';

const String _reply = 'Sample explanation.';

bool _captureFontReady = false;

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

  const List<_Viewport> viewports = <_Viewport>[
    _Viewport(
      brightness: Brightness.light,
      size: Size(390, 844),
      textScale: 1,
      themeName: 'light',
      widthLabel: '390',
    ),
    _Viewport(
      brightness: Brightness.dark,
      size: Size(390, 844),
      textScale: 1,
      themeName: 'dark',
      widthLabel: '390',
    ),
    _Viewport(
      brightness: Brightness.light,
      size: Size(840, 1200),
      textScale: 1,
      themeName: 'light',
      widthLabel: '840',
    ),
    _Viewport(
      brightness: Brightness.light,
      size: Size(390, 844),
      textScale: 1.3,
      themeName: 'light',
      widthLabel: '390',
    ),
  ];

  testWidgets('no selection', (WidgetTester tester) async {
    for (final _Viewport viewport in viewports) {
      await _pumpExplain(
        tester,
        viewport: viewport,
        screen: ExplainScreen(apiBase: '', httpClientFactory: _failFactory),
      );
      _expectTheme(tester, viewport.brightness);
      expect(find.text('This note stays on this device.'), findsNothing);
      expect(find.text('Send'), findsNothing);
      await _capture(tester, viewport.fileName('none'));
    }
  });

  testWidgets('selected area with the local sentence', (
    WidgetTester tester,
  ) async {
    for (final _Viewport viewport in viewports) {
      await _pumpExplain(
        tester,
        viewport: viewport,
        screen: ExplainScreen(apiBase: '', httpClientFactory: _failFactory),
      );
      await tester.tap(find.text('Head and neck'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      _expectTheme(tester, viewport.brightness);
      expect(find.text('This note stays on this device.'), findsOneWidget);
      expect(find.text('Send'), findsNothing);
      await _capture(tester, viewport.fileName('local'));
    }
  });

  testWidgets('consent line', (WidgetTester tester) async {
    for (final _Viewport viewport in viewports) {
      await _pumpExplain(
        tester,
        viewport: viewport,
        screen: ExplainScreen(
          apiBase: 'http://127.0.0.1:8787',
          httpClientFactory: _failFactory,
        ),
      );
      await tester.tap(find.text('Head and neck'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      _expectTheme(tester, viewport.brightness);
      expect(find.text(_consent), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Keep it on this device'), findsOneWidget);
      await _capture(tester, viewport.fileName('consent'));
    }
  });

  testWidgets('keep', (WidgetTester tester) async {
    for (final _Viewport viewport in viewports) {
      await _pumpExplain(
        tester,
        viewport: viewport,
        screen: ExplainScreen(
          apiBase: 'http://127.0.0.1:8787',
          httpClientFactory: _failFactory,
        ),
      );
      await tester.tap(find.text('Head and neck'));
      await tester.pump();
      await tester.tap(find.text('Keep it on this device'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      _expectTheme(tester, viewport.brightness);
      expect(find.text('This note stays on this device.'), findsOneWidget);
      expect(find.text('Send'), findsNothing);
      await _capture(tester, viewport.fileName('keep'));
    }
  });

  testWidgets('injected model reply', (WidgetTester tester) async {
    for (final _Viewport viewport in viewports) {
      await _pumpExplain(
        tester,
        viewport: viewport,
        screen: ExplainScreen(
          apiBase: 'http://127.0.0.1:8787',
          httpClientFactory: HttpClient.new,
          poster: (HttpClient client, Uri uri, String jsonBody) async {
            return _reply;
          },
        ),
      );
      await tester.tap(find.text('Head and neck'));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      _expectTheme(tester, viewport.brightness);
      final Text reply = tester.widget<Text>(
        find.byKey(const Key('explain-reply')),
      );
      expect(reply.data, _reply);
      expect(
        find.text('This explanation is not a change to your plan.'),
        findsOneWidget,
      );
      await _capture(tester, viewport.fileName('reply'));
    }
  });
}

HttpClient _failFactory() {
  throw StateError('factory');
}

void _expectTheme(WidgetTester tester, Brightness brightness) {
  final ThemeData theme = Theme.of(tester.element(find.byType(ExplainScreen)));
  expect(theme.brightness, brightness);
  final Color surface = brightness == Brightness.dark
      ? AppColors.dark.surface
      : AppColors.light.surface;
  expect(theme.scaffoldBackgroundColor, surface);
  final Color text = brightness == Brightness.dark
      ? AppColors.dark.textPrimary
      : AppColors.light.textPrimary;
  expect(
    DefaultTextStyle.of(tester.element(find.text('Area'))).style.color,
    text,
  );
}

Future<void> _pumpExplain(
  WidgetTester tester, {
  required _Viewport viewport,
  required ExplainScreen screen,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport.size;
  tester.platformDispatcher.textScaleFactorTestValue = viewport.textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return screen;
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  ThemeData withFont(ThemeData base) {
    if (!_captureFontReady) {
      return base;
    }
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Segoe UI'),
    );
  }

  await tester.pumpWidget(
    MaterialApp.router(
      theme: withFont(AppTheme.light()),
      darkTheme: withFont(AppTheme.dark()),
      themeMode: viewport.brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      routerConfig: router,
    ),
  );
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_captureFontReady) {
    return;
  }
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('explain-capture')),
      );
  boundary.markNeedsPaint();
  await tester.pump();
  final ui.Image image = await boundary.toImage(pixelRatio: 1);
  final ByteData? data = await tester.runAsync<ByteData?>(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  image.dispose();
  expect(data, isNotNull);
  final File file = File(
    '$_evidenceDirectory${Platform.pathSeparator}$name.png',
  );
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
}

class _Viewport {
  const _Viewport({
    required this.brightness,
    required this.size,
    required this.textScale,
    required this.themeName,
    required this.widthLabel,
  });

  final Brightness brightness;
  final Size size;
  final double textScale;
  final String themeName;
  final String widthLabel;

  String fileName(String state) {
    final String scale = textScale == 1 ? '' : '-t1.3';
    return 'explain-$state-$themeName-$widthLabel$scale';
  }
}
