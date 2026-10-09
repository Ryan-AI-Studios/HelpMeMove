import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/main.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';
import 'package:sqlite3/sqlite3.dart';

const Key _captureKey = Key('privacy-ready-capture');

bool _captureFontReady = false;

ThemeData _captureTheme() {
  final ThemeData theme = AppTheme.light();
  if (!_captureFontReady) {
    return theme;
  }
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Segoe UI'),
  );
}

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadCaptureFont();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-privacy');
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

  Future<void> tapVisible(WidgetTester tester, String label) async {
    final Finder finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
  }

  Future<void> pumpRouter(
    WidgetTester tester,
    ProfileStore? store, {
    String initialLocation = '/',
    bool storageBlocked = false,
    bool movementGateOpen = false,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp.router(
          theme: _captureTheme(),
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

  void expectChoice(WidgetTester tester, String token) {
    final RadioGroup<String> group = tester.widget(
      find.byType(RadioGroup<String>),
    );
    expect(group.groupValue, token);
    expect(find.byType(Radio<String>), findsNWidgets(3));
  }

  Future<void> untilChoice(WidgetTester tester, String token) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      final Finder finder = find.byType(RadioGroup<String>);
      if (finder.evaluate().isNotEmpty) {
        final RadioGroup<String> group = tester.widget(finder);
        if (group.groupValue == token) {
          await tester.pump();
          return;
        }
      }
    }
    fail('choice $token was not selected');
  }

  Future<void> untilTheme(WidgetTester tester, ThemeMode mode) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      final Finder finder = find.byType(MaterialApp);
      if (finder.evaluate().isNotEmpty) {
        final MaterialApp app = tester.widget(finder);
        if (app.themeMode == mode) {
          await tester.pump();
          return;
        }
      }
    }
    fail('theme mode $mode was not applied');
  }

  testWidgets('a null choice selects System and keeps the four sentences', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(tester, store, initialLocation: '/focus/privacy');
    await until(tester, find.text('Privacy and appearance'));
    expect(find.text('This profile stays on this device.'), findsOneWidget);
    expect(find.text('The profile database is encrypted.'), findsOneWidget);
    expect(find.text('Cloud sync is not connected.'), findsOneWidget);
    expect(find.text('No AI coach is active.'), findsOneWidget);
    expect(find.text('Analytics are not in this build.'), findsOneWidget);
    expect(find.text('Crash reports are not in this build.'), findsOneWidget);
    expect(find.text('Workout video is not stored.'), findsOneWidget);
    expect(find.text('Health apps are not in this build.'), findsOneWidget);
    expect(
      find.text('The launch region for this build is the United States.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The stated retention for this profile is 3 months. This build removes it only when you choose Remove it.',
      ),
      findsOneWidget,
    );
    expect(find.text('Prepare a copy on this phone'), findsOneWidget);
    expect(find.text('Delete the profile on this phone'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.textContaining('Export'), findsNothing);
    expect(find.textContaining('account'), findsNothing);
    expect(
      top(tester, 'No AI coach is active.'),
      lessThan(top(tester, 'Analytics are not in this build.')),
    );
    expect(
      top(tester, 'Analytics are not in this build.'),
      lessThan(top(tester, 'Crash reports are not in this build.')),
    );
    expect(
      top(tester, 'Crash reports are not in this build.'),
      lessThan(top(tester, 'Workout video is not stored.')),
    );
    expect(
      top(tester, 'Workout video is not stored.'),
      lessThan(top(tester, 'Health apps are not in this build.')),
    );
    expect(
      top(tester, 'Health apps are not in this build.'),
      lessThan(
        top(tester, 'The launch region for this build is the United States.'),
      ),
    );
    expect(
      top(tester, 'The launch region for this build is the United States.'),
      lessThan(
        top(
          tester,
          'The stated retention for this profile is 3 months. This build removes it only when you choose Remove it.',
        ),
      ),
    );
    expect(
      top(
        tester,
        'The stated retention for this profile is 3 months. This build removes it only when you choose Remove it.',
      ),
      lessThan(top(tester, 'Appearance')),
    );
    expectChoice(tester, 'system');
    expect(await io(tester, store.loadAppearanceChoice), isNull);
    await _capture(tester, 'privacy-ready-390x844.png');
    await tapVisible(tester, 'Back');
    await until(tester, find.text('See local progress'));
    expect(find.text('Privacy and appearance'), findsOneWidget);
  });

  testWidgets('Light, Dark, and System save and apply on the same app', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpApp(tester, store, initialLocation: '/focus/privacy');
    await until(tester, find.text('System'));
    expectChoice(tester, 'system');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await tapVisible(tester, 'Light');
    await untilChoice(tester, 'light');
    await untilTheme(tester, ThemeMode.light);
    await tester.pump(const Duration(milliseconds: 300));
    expect(await io(tester, store.loadAppearanceChoice), 'light');
    expectChoice(tester, 'light');
    expect(
      Theme.of(tester.element(find.text('Privacy and appearance'))).brightness,
      Brightness.light,
    );

    await tapVisible(tester, 'Dark');
    await untilChoice(tester, 'dark');
    await untilTheme(tester, ThemeMode.dark);
    await tester.pump(const Duration(milliseconds: 300));
    expect(await io(tester, store.loadAppearanceChoice), 'dark');
    expectChoice(tester, 'dark');
    expect(
      Theme.of(tester.element(find.text('Privacy and appearance'))).brightness,
      Brightness.dark,
    );
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.highContrastTheme, isNotNull);
    expect(app.highContrastDarkTheme, isNotNull);

    await tapVisible(tester, 'System');
    await untilChoice(tester, 'system');
    await untilTheme(tester, ThemeMode.system);
    expect(await io(tester, store.loadAppearanceChoice), 'system');
    expectChoice(tester, 'system');
  });

  testWidgets('a save that finishes after Back still applies the theme', (
    tester,
  ) async {
    final DelayedAppearanceStore store = DelayedAppearanceStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(14),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await io(tester, store.createProfile);
    await pumpApp(tester, store, initialLocation: '/focus/privacy');
    await until(tester, find.text('Light'));
    await tapVisible(tester, 'Light');
    await tester.pump();
    await tapVisible(tester, 'Back');
    await until(tester, find.text('See local progress'));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    store.releaseSave();
    await untilTheme(tester, ThemeMode.light);
    expect(await io(tester, store.loadAppearanceChoice), 'light');
    expect(find.text('See local progress'), findsOneWidget);
  });

  testWidgets('a stored light choice opens selected and themed', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveAppearanceChoice('light');
    });
    await pumpApp(tester, store, initialLocation: '/focus/privacy');
    await untilChoice(tester, 'light');
    await untilTheme(tester, ThemeMode.light);
    await tester.pump(const Duration(milliseconds: 300));
    expectChoice(tester, 'light');
    expect(
      Theme.of(tester.element(find.text('Privacy and appearance'))).brightness,
      Brightness.light,
    );
  });

  testWidgets('an unreadable token keeps the row and the system theme', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final UnreadableAppearanceStore store = UnreadableAppearanceStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(14),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await io(tester, () async {
      await store.createProfile();
      await store.saveAppearanceChoice('dark');
    });
    await pumpApp(tester, store, initialLocation: '/focus/privacy');
    await until(tester, find.text('The saved appearance could not be read.'));
    expect(find.text('Privacy and appearance'), findsNothing);
    expect(find.text('System'), findsNothing);
    expect(find.text('Back'), findsOneWidget);
    expect(await io(tester, store.storedChoice), 'dark');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    await tapVisible(tester, 'Back');
    await until(tester, find.text('HelpMeMove'));
    expect(await io(tester, store.storedChoice), 'dark');
  });

  testWidgets('a storage error opens recovery and writes nothing', (
    tester,
  ) async {
    final ThrowingAppearanceStore store = ThrowingAppearanceStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(14),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await io(tester, store.createProfile);
    await pumpRouter(tester, store, initialLocation: '/focus/privacy');
    await until(tester, find.text('Storage is unavailable'));
    expect(find.text('The saved appearance could not be read.'), findsNothing);
    expect(find.text('Privacy and appearance'), findsNothing);
    expect(await io(tester, store.storedChoice), isNull);
  });

  testWidgets('a sqlite read error opens recovery and keeps the profile', (
    tester,
  ) async {
    final SqliteThrowingAppearanceStore store = SqliteThrowingAppearanceStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(14),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await io(tester, () async {
      await store.createProfile();
      await store.saveAppearanceChoice('light');
    });
    await pumpRouter(tester, store, initialLocation: '/focus/privacy');
    await until(tester, find.text('Storage is unavailable'));
    expect(await io(tester, store.storedChoice), 'light');
  });

  testWidgets('switching subjects restores that subject theme', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final ProfileStore store = openStore();
    final String first = await io(tester, () async {
      final String subjectId = await store.createProfile();
      await store.saveAppearanceChoice('dark');
      return subjectId;
    });
    await io(tester, store.createProfile);
    await pumpApp(tester, store, initialLocation: '/focus/privacy');
    await until(tester, find.text('System'));
    expectChoice(tester, 'system');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await io(tester, () => store.switchTo(first));
    await pumpApp(tester, store, initialLocation: '/focus/privacy');
    await untilChoice(tester, 'dark');
    await untilTheme(tester, ThemeMode.dark);
    await tester.pump(const Duration(milliseconds: 300));
    expectChoice(tester, 'dark');
    expect(
      Theme.of(tester.element(find.text('Privacy and appearance'))).brightness,
      Brightness.dark,
    );
    expect(await io(tester, store.loadAppearanceChoice), 'dark');
  });

  testWidgets(
    'home places privacy after progress and keeps the other buttons',
    (tester) async {
      final String programJson = await io(
        tester,
        () => File('test/program/green_shoulder_program.json').readAsString(),
      );
      final ProfileStore store = openStore();
      await io(tester, () async {
        await store.createProfile();
        await store.saveProgramRecord(programJson);
      });
      await pumpRouter(tester, store);
      await until(tester, find.text('Privacy and appearance'));
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('Describe a limit'), findsOneWidget);
      expect(find.text('See local progress'), findsOneWidget);
      expect(find.text('Scaffold check'), findsOneWidget);
      expect(find.text('Foundations'), findsWidgets);
      expect(
        top(tester, 'Start workout'),
        lessThan(top(tester, 'Describe a limit')),
      );
      expect(
        top(tester, 'Describe a limit'),
        lessThan(top(tester, 'See local progress')),
      );
      expect(
        top(tester, 'See local progress'),
        lessThan(top(tester, 'Privacy and appearance')),
      );
      expect(
        top(tester, 'Privacy and appearance'),
        lessThan(top(tester, 'Scaffold check')),
      );
      await tester.tap(find.text('Privacy and appearance'));
      await until(tester, find.text('This profile stays on this device.'));
      expect(find.text('HelpMeMove'), findsNothing);
      expectChoice(tester, 'system');
    },
  );

  testWidgets('privacy does not read the movement gate', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/privacy',
      movementGateOpen: false,
    );
    await until(tester, find.text('Privacy and appearance'));
    expect(
      find.text('The synthetic rule is not allowing a movement check.'),
      findsNothing,
    );
    expect(
      find.text('The synthetic rule is not allowing a starting plan.'),
      findsNothing,
    );
  });

  testWidgets('a missing or blocked store cannot open privacy', (tester) async {
    await pumpRouter(tester, null, initialLocation: '/focus/privacy');
    await until(tester, find.text('Home'));
    expect(find.text('Privacy and appearance'), findsNothing);
    expect(find.text('Analytics are not in this build.'), findsNothing);
    expect(find.text('Crash reports are not in this build.'), findsNothing);

    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/privacy',
      storageBlocked: true,
    );
    await until(tester, find.text('Home'));
    expect(find.text('This profile stays on this device.'), findsNothing);
    expect(find.text('Privacy and appearance'), findsNothing);
    expect(find.text('Analytics are not in this build.'), findsNothing);
    expect(find.text('Crash reports are not in this build.'), findsNothing);
  });

  testWidgets('large text keeps the six sentences reachable', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/privacy',
      size: const Size(390, 844),
      textScale: 2,
    );
    await until(tester, find.text('Privacy and appearance'));
    for (final String sentence in <String>[
      'This profile stays on this device.',
      'The profile database is encrypted.',
      'Cloud sync is not connected.',
      'No AI coach is active.',
      'Analytics are not in this build.',
      'Crash reports are not in this build.',
      'Workout video is not stored.',
      'Health apps are not in this build.',
      'The launch region for this build is the United States.',
      'The stated retention for this profile is 3 months. This build removes it only when you choose Remove it.',
      'Prepare a copy on this phone',
      'Delete the profile on this phone',
    ]) {
      await tester.scrollUntilVisible(
        find.text(sentence),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(sentence), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.text('Back'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide window keeps the privacy column', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/privacy',
      size: const Size(840, 900),
    );
    await until(tester, find.text('Privacy and appearance'));
    expect(find.text('No AI coach is active.'), findsOneWidget);
    expect(find.text('Analytics are not in this build.'), findsOneWidget);
    expect(find.text('Crash reports are not in this build.'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expectChoice(tester, 'system');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _loadCaptureFont() async {
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
}

Future<void> _capture(WidgetTester tester, String name) async {
  final String? directory = Platform.environment['HMM_UI_EVIDENCE'];
  if (directory == null || directory.isEmpty) {
    return;
  }
  expect(_captureFontReady, isTrue, reason: 'capture font was not loaded');
  await tester.pump();
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(_captureKey),
  );
  ui.Image? image;
  try {
    image = await tester.runAsync<ui.Image>(
      () => boundary.toImage(pixelRatio: 1).timeout(const Duration(seconds: 5)),
    );
    if (image == null) {
      return;
    }
    final ui.Image captured = image;
    final ByteData? data = await tester.runAsync<ByteData?>(
      () => captured
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(const Duration(seconds: 5)),
    );
    if (data == null) {
      return;
    }
    Directory(directory).createSync(recursive: true);
    final File file = File('$directory/$name');
    file.writeAsBytesSync(data.buffer.asUint8List());
    expect(file.existsSync(), isTrue, reason: file.path);
  } finally {
    image?.dispose();
  }
}

class DelayedAppearanceStore extends ProfileStore {
  DelayedAppearanceStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  final Completer<void> _gate = Completer<void>();

  void releaseSave() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<void> saveAppearanceChoice(String choice) async {
    await _gate.future;
    await super.saveAppearanceChoice(choice);
  }
}

class UnreadableAppearanceStore extends ProfileStore {
  UnreadableAppearanceStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  @override
  Future<String?> loadAppearanceChoice() async {
    await super.loadAppearanceChoice();
    return 'purple';
  }

  Future<String?> storedChoice() => super.loadAppearanceChoice();
}

class ThrowingAppearanceStore extends ProfileStore {
  ThrowingAppearanceStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  @override
  Future<String?> loadAppearanceChoice() async {
    throw const StorageIoException('read failed');
  }

  Future<String?> storedChoice() => super.loadAppearanceChoice();
}

class SqliteThrowingAppearanceStore extends ProfileStore {
  SqliteThrowingAppearanceStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  @override
  Future<String?> loadAppearanceChoice() async {
    throw SqliteException(extendedResultCode: 1, message: 'read failed');
  }

  Future<String?> storedChoice() => super.loadAppearanceChoice();
}
