import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/screens/home_screen.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';

const String _evidenceDirectory =
    r'C:\dev\HelpMeMove\conductor\0022-SignedContentPacksAndRecall\ui-evidence';

const String _recall = 'A stored session used a recalled rule.';
const String _stopped = 'The last session stopped. No change was saved.';
const String _session =
    '{"elapsed_ms":0,"exercises":[{"exercise_id":"syn-shoulder-isometric","reps":1,"reps_done":0,"set_index":0,"sets":1,"skipped":false,"tempo":{"concentric":2,"eccentric":2,"pause":1}}],"monotonic_ms":1000,"outcome":"safety_stopped","record_version":1,"reported_pain":null,"rest_until_ms":null,"rule_id":"syn-program-core","session_id":"11111111-1111-4111-8111-111111111111","state":"safety_stopped","symptom":null}';
const String _recallingList =
    '{"schema_version":1,"entries":[{"kind":"rule","id":"syn-program-core","version":1}]}';
const String _shoulderProgram =
    '{"record_version":1,"rule_id":"syn-program-core","rule_version":1,"safety_rule_id":"syn-safety-core","safety_rule_version":1,"session_minutes":15,"exercises":[{"exercise_id":"syn-shoulder-isometric","exercise_version":1,"regions":["shoulder"],"sets":1,"reps":1,"tempo":{"eccentric":2,"pause":1,"concentric":2},"reasons":[{"code":"region_match","region":"shoulder","equipment":null,"goal":null},{"code":"equipment_match","region":null,"equipment":"bodyweight","goal":null},{"code":"goal_match","region":null,"equipment":null,"goal":"control"},{"code":"screen_clear","region":null,"equipment":null,"goal":null},{"code":"fixture_defaults","region":null,"equipment":null,"goal":null}]}]}';

bool _captureFontReady = false;

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
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

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-recall');
  });

  tearDown(() async {
    await live?.close();
    live = null;
    if (temp.existsSync()) {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Temp files can stay locked while a widget future closes.
      }
    }
  });

  Future<void> untilText(WidgetTester tester, String label) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      if (find.text(label).evaluate().isNotEmpty) {
        await tester.pump();
        return;
      }
    }
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    HomeScreen? home,
    Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) {
            return home ?? const HomeScreen();
          },
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        routerConfig: router,
      ),
    );
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final RenderRepaintBoundary boundary = tester
        .renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('home-capture')),
        );
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final ByteData? data = await tester.runAsync<ByteData?>(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    image.dispose();
    expect(data, isNotNull);
    if (!_captureFontReady) {
      return;
    }
    final File file = File(
      '$_evidenceDirectory${Platform.pathSeparator}$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  }

  testWidgets('empty recall stays quiet', (WidgetTester tester) async {
    await pumpHome(tester);
    expect(find.text(_recall), findsNothing);
    await capture(tester, 'home-empty-light-390');
  });

  testWidgets('injected recalling list shows the sentence', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      home: const HomeScreen(
        recalledDocuments: <String>[_session],
        disableListJson: _recallingList,
      ),
    );
    await untilText(tester, _recall);
    expect(find.text(_recall), findsOneWidget);
    await capture(tester, 'home-recall-light-390');
  });

  testWidgets('storage blocked omits the recall sentence', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      home: const HomeScreen(
        storageBlocked: true,
        recalledDocuments: <String>[_session],
        disableListJson: _recallingList,
      ),
    );
    await tester.pump();
    expect(find.text(_recall), findsNothing);
    await capture(tester, 'home-blocked-light-390');
  });

  testWidgets('no store stays quiet', (WidgetTester tester) async {
    await pumpHome(tester, home: const HomeScreen());
    expect(find.text(_recall), findsNothing);
  });

  testWidgets('recall sits above a stopped move notice', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = ProfileStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(11),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(_shoulderProgram);
      await store.saveWorkoutTerminal(
        sessionId: '11111111-1111-4111-8111-111111111111',
        documentJson: _session,
      );
    });
    await pumpHome(
      tester,
      home: HomeScreen(
        store: store,
        recalledDocuments: const <String>[_session],
        disableListJson: _recallingList,
      ),
    );
    await untilText(tester, _recall);
    expect(find.text(_recall), findsOneWidget);
    expect(find.text(_stopped), findsOneWidget);
    await capture(tester, 'home-recall-notice-light-390');
  });

  testWidgets('captures remaining viewports when fonts exist', (
    WidgetTester tester,
  ) async {
    const HomeScreen recalling = HomeScreen(
      recalledDocuments: <String>[_session],
      disableListJson: _recallingList,
    );
    Future<void> shot(
      String name, {
      Brightness brightness = Brightness.light,
      Size size = const Size(390, 844),
      double textScale = 1,
    }) async {
      await pumpHome(
        tester,
        home: recalling,
        brightness: brightness,
        size: size,
        textScale: textScale,
      );
      await untilText(tester, _recall);
      await capture(tester, name);
    }

    await shot('home-recall-dark-390', brightness: Brightness.dark);
    await shot('home-recall-light-840', size: const Size(840, 1200));
    await shot('home-recall-light-390-t1.3', textScale: 1.3);
    await pumpHome(tester, brightness: Brightness.dark);
    await capture(tester, 'home-empty-dark-390');
    await pumpHome(tester, size: const Size(840, 1200));
    await capture(tester, 'home-empty-light-840');
    await pumpHome(tester, textScale: 1.3);
    await capture(tester, 'home-empty-light-390-t1.3');
    await pumpHome(
      tester,
      home: const HomeScreen(storageBlocked: true),
      brightness: Brightness.dark,
    );
    await capture(tester, 'home-blocked-dark-390');
    await pumpHome(
      tester,
      home: const HomeScreen(storageBlocked: true),
      size: const Size(840, 1200),
    );
    await capture(tester, 'home-blocked-light-840');
    await pumpHome(
      tester,
      home: const HomeScreen(storageBlocked: true),
      textScale: 1.3,
    );
    await capture(tester, 'home-blocked-light-390-t1.3');
  });
}
