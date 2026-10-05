import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/main.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';

const String _validProgram =
    '{"record_version":1,"rule_id":"syn-program-core","rule_version":1,"safety_rule_id":"syn-safety-core","safety_rule_version":1,"session_minutes":15,"exercises":[{"exercise_id":"syn-shoulder-isometric","exercise_version":1,"regions":["shoulder"],"sets":1,"reps":1,"tempo":{"eccentric":2,"pause":1,"concentric":2},"reasons":[{"code":"region_match","region":"shoulder","equipment":null,"goal":null},{"code":"equipment_match","region":null,"equipment":"bodyweight","goal":null},{"code":"goal_match","region":null,"equipment":null,"goal":"control"},{"code":"screen_clear","region":null,"equipment":null,"goal":null},{"code":"fixture_defaults","region":null,"equipment":null,"goal":null}]}]}';

const String _sessionId = '11111111-1111-4111-8111-111111111111';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-report');
  });

  tearDown(() async {
    await live?.close();
    live = null;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  ProfileStore openStore() {
    final ProfileStore store = ProfileStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(14),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    return store;
  }

  Future<T> io<T>(WidgetTester tester, Future<T> Function() body) async {
    final T? value = await tester.runAsync(body);
    if (value is! T) {
      throw StateError('async work did not finish');
    }
    return value;
  }

  Future<void> until(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      if (finder.evaluate().isNotEmpty) {
        await tester.pump();
        return;
      }
    }
    final List<String?> seen = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text text) => text.data)
        .toList();
    fail('missing $finder; saw $seen');
  }

  double top(WidgetTester tester, String label) {
    return tester.getTopLeft(find.text(label)).dy;
  }

  Future<void> pumpRouter(
    WidgetTester tester,
    ProfileStore? store, {
    String initialLocation = '/',
    bool storageBlocked = false,
    bool movementGateOpen = false,
    Size size = const Size(390, 844),
    double textScale = 1,
    Key? appKey,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp.router(
        key: appKey,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        highContrastTheme: AppTheme.highContrastLight(),
        highContrastDarkTheme: AppTheme.highContrastDark(),
        routerConfig: buildHelpMeMoveRouter(
          initialLocation: initialLocation,
          store: store,
          storageBlocked: storageBlocked,
          movementGateOpen: movementGateOpen,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpApp(
    WidgetTester tester,
    ProfileStore store, {
    String initialLocation = '/',
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      HelpMeMoveApp(
        key: UniqueKey(),
        initialLocation: initialLocation,
        store: store,
      ),
    );
    await tester.pump();
  }

  Future<void> tapLabel(WidgetTester tester, String label) async {
    final Finder finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> expectHitTestable(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    final RenderObject object = tester.renderObject(finder);
    final HitTestResult result = tester.hitTestOnBinding(
      tester.getCenter(finder),
    );
    expect(
      result.path.any((HitTestEntry<HitTestTarget> entry) {
        final HitTestTarget target = entry.target;
        if (target == object) {
          return true;
        }
        if (target is! RenderObject) {
          return false;
        }
        RenderObject? current = object;
        while (current != null) {
          if (current == target) {
            return true;
          }
          current = current.parent;
        }
        return false;
      }),
      isTrue,
    );
  }

  testWidgets('home places report after privacy and before scaffold check', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(tester, store);
    await until(tester, find.text('Report a problem'));
    expect(find.text('Describe a limit'), findsOneWidget);
    expect(find.text('See local progress'), findsOneWidget);
    expect(find.text('Privacy and appearance'), findsOneWidget);
    expect(find.text('Scaffold check'), findsOneWidget);
    expect(find.text('Bridge check'), findsOneWidget);
    expect(
      top(tester, 'Privacy and appearance'),
      lessThan(top(tester, 'Report a problem')),
    );
    expect(
      top(tester, 'Report a problem'),
      lessThan(top(tester, 'Scaffold check')),
    );
  });

  testWidgets('report is hidden when the store is null or blocked', (
    tester,
  ) async {
    await pumpRouter(tester, null);
    await until(tester, find.text('Scaffold check'));
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    expect(find.text('Report a problem'), findsNothing);
    expect(find.text('Scaffold check'), findsOneWidget);

    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(tester, store, storageBlocked: true, appKey: UniqueKey());
    await until(tester, find.text('Scaffold check'));
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    expect(find.text('Report a problem'), findsNothing);
    expect(find.text('Privacy and appearance'), findsNothing);
    expect(find.text('Scaffold check'), findsOneWidget);
  });

  testWidgets('the report route does not read the movement gate', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/report',
      movementGateOpen: false,
    );
    await until(tester, find.text('Report a problem'));
    expect(find.text('This report stays on this device.'), findsOneWidget);
    expect(
      find.text('The synthetic rule is not allowing a movement check.'),
      findsNothing,
    );
    expect(
      find.text('The synthetic rule is not allowing a starting plan.'),
      findsNothing,
    );
  });

  testWidgets('a null or blocked store cannot open the report', (tester) async {
    await pumpRouter(tester, null, initialLocation: '/focus/report');
    await until(tester, find.text('Home'));
    expect(find.text('Report a problem'), findsNothing);

    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/report',
      storageBlocked: true,
      appKey: UniqueKey(),
    );
    await until(tester, find.text('Home'));
    expect(find.text('This report stays on this device.'), findsNothing);
    expect(find.text('Report a problem'), findsNothing);
  });

  testWidgets('save stays disabled until a category is chosen', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(tester, store, initialLocation: '/focus/report');
    await until(tester, find.text('Category'));
    final Finder save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(find.text('Saved on this device.'), findsNothing);
  });

  testWidgets(
    'safety concern shows the clinician sentence and app issue does not',
    (tester) async {
      final ProfileStore store = openStore();
      await io(tester, store.createProfile);
      await pumpRouter(tester, store, initialLocation: '/focus/report');
      await until(tester, find.text('Safety concern'));
      await tapLabel(tester, 'Safety concern');
      expect(find.text('This does not contact a clinician.'), findsOneWidget);
      await tapLabel(tester, 'App issue');
      expect(find.text('This does not contact a clinician.'), findsNothing);
      expect(find.text('No clinician is contacted.'), findsOneWidget);
    },
  );

  testWidgets('an empty note without a program shows the null readout', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(tester, store, initialLocation: '/focus/report');
    await until(tester, find.text('App issue'));
    await tapLabel(tester, 'App issue');
    await tapLabel(tester, 'Save');
    await until(tester, find.text('Saved on this device.'));
    expect(find.text('App issue'), findsOneWidget);
    expect(find.text('No stored program was attached.'), findsOneWidget);
    expect(find.text('No saved session was attached.'), findsOneWidget);
    expect(
      find.textContaining(
        RegExp(
          r'Report [0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Category'), findsNothing);
  });

  testWidgets('a stored program shows the copied rule versions', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveProgramRecord(_validProgram);
    });
    await pumpRouter(tester, store, initialLocation: '/focus/report');
    await until(tester, find.text('App issue'));
    await tapLabel(tester, 'App issue');
    await tapLabel(tester, 'Save');
    await until(tester, find.text('Saved on this device.'));
    expect(find.text('Program rule syn-program-core 1.'), findsOneWidget);
    expect(find.text('Safety rule syn-safety-core 1.'), findsOneWidget);
    expect(find.text('No stored program was attached.'), findsNothing);
  });

  testWidgets('a missing query session is not attached', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/report?session=$_sessionId',
    );
    await until(tester, find.text('The saved session could not be attached.'));
    await tapLabel(tester, 'App issue');
    await tapLabel(tester, 'Save');
    await until(tester, find.text('Saved on this device.'));
    expect(find.text('No saved session was attached.'), findsOneWidget);
    expect(find.text('Session $_sessionId.'), findsNothing);
  });

  testWidgets('a stored terminal session is attached', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveWorkoutTerminal(
        sessionId: _sessionId,
        documentJson: '{"session_id":"$_sessionId"}',
      );
    });
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/report?session=$_sessionId',
    );
    await until(tester, find.text('Report a problem'));
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      expect(
        find.text('The saved session could not be attached.'),
        findsNothing,
      );
    }
    await tapLabel(tester, 'Content issue');
    await tapLabel(tester, 'Save');
    await until(tester, find.text('Saved on this device.'));
    expect(find.text('Session $_sessionId.'), findsOneWidget);
    expect(find.text('No saved session was attached.'), findsNothing);
  });

  testWidgets('a storage error opens recovery', (tester) async {
    final ThrowingReportStore store = ThrowingReportStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(14),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await io(tester, store.createProfile);
    await pumpRouter(tester, store, initialLocation: '/focus/report');
    await until(tester, find.text('App issue'));
    await tapLabel(tester, 'App issue');
    await tapLabel(tester, 'Save');
    await until(tester, find.text('Storage is unavailable'));
  });

  testWidgets('large text keeps save and back hit-testable', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/report',
      size: const Size(390, 844),
      textScale: 2,
    );
    await until(tester, find.text('Report a problem'));
    await expectHitTestable(tester, find.text('Save'));
    await expectHitTestable(tester, find.text('Back'));
    expect(tester.takeException(), isNull);

    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/report',
      size: const Size(840, 844),
      appKey: UniqueKey(),
    );
    await until(tester, find.text('Report a problem'));
    await expectHitTestable(tester, find.text('Save'));
    await expectHitTestable(tester, find.text('Back'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report screen leaves the system theme alone', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpApp(tester, store, initialLocation: '/focus/report');
    await until(tester, find.text('Report a problem'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    await tapLabel(tester, 'Safety concern');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });
}

class ThrowingReportStore extends ProfileStore {
  ThrowingReportStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  @override
  Future<String> saveProblemReport({
    required String category,
    required String note,
    String? sessionId,
    String? exerciseId,
  }) async {
    throw const StorageIoException('save failed');
  }
}
