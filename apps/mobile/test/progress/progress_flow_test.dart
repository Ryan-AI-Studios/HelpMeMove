import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/readiness/adaptation_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-progress');
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

  Future<String> program() =>
      File('test/program/green_shoulder_program.json').readAsString();

  String workout(
    String programJson,
    String sessionId, {
    String outcome = 'completed',
    int? pain,
  }) {
    WorkoutView view = openWorkout(
      programJson: programJson,
      monotonicMillis: 1000,
      sessionId: sessionId,
    );
    expect(view.outcome, 'ready');
    String document = view.documentJson;
    String step(String event) {
      view = applyWorkoutEvent(
        documentJson: document,
        eventJson: event,
        monotonicMillis: 1200,
      );
      expect(view.outcome, 'ready', reason: view.errorCode);
      document = view.documentJson;
      return document;
    }

    step(r'{"name":"ready"}');
    step(r'{"name":"ready"}');
    if (pain != null) {
      step(
        '{"name":"report_pain","reported_pain":$pain,"symptom":"mild_discomfort"}',
      );
      if (outcome == 'safety_stopped') {
        return step(r'{"name":"end_session"}');
      }
      step(r'{"name":"continue_after_pain"}');
      if (outcome == 'abandoned') {
        return step(r'{"name":"end_session"}');
      }
      step(r'{"name":"resume"}');
    } else if (outcome == 'abandoned') {
      step(r'{"name":"pause"}');
      return step(r'{"name":"end_session"}');
    }
    return step(r'{"name":"complete_rep"}');
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

  Future<void> pumpRouter(
    WidgetTester tester,
    ProfileStore? store, {
    String initialLocation = '/',
    bool storageBlocked = false,
    bool movementGateOpen = false,
    Size size = const Size(390, 844),
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: theme ?? AppTheme.light(),
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

  double top(WidgetTester tester, String label) {
    return tester.getTopLeft(find.text(label)).dy;
  }

  test('the summary decoder accepts only the counted document', () {
    const String ready =
        '{"abandoned_count":0,"completed_count":1,"copied_pain":0,"record_version":1,"rule_id":"syn-progress-core","rule_version":1,"safety_stopped_count":0}';
    final StoredProgressSummary summary = StoredProgressSummary.decode(ready);
    expect(summary.completedCount, 1);
    expect(summary.copiedPain, 0);
    expect(
      StoredProgressSummary.decode(
        ready.replaceAll('"copied_pain":0', '"copied_pain":null'),
      ).copiedPain,
      isNull,
    );
    expect(
      () => StoredProgressSummary.decode(
        ready.replaceAll('"copied_pain":0', '"copied_pain":11'),
      ),
      throwsA(isA<AdaptationDocumentException>()),
    );
    expect(
      () => StoredProgressSummary.decode(
        ready.replaceAll('"completed_count":1', '"completed_count":2147483648'),
      ),
      throwsA(isA<AdaptationDocumentException>()),
    );
    expect(
      () => StoredProgressSummary.decode(
        ready.replaceAll('"completed_count":1', '"completed_count":-1'),
      ),
      throwsA(isA<AdaptationDocumentException>()),
    );
    expect(
      () => StoredProgressSummary.decode(
        ready.replaceAll('"completed_count":1', '"completed_count":1.5'),
      ),
      throwsA(isA<AdaptationDocumentException>()),
    );
    expect(
      () => StoredProgressSummary.decode('{"completed_count":1}'),
      throwsA(isA<AdaptationDocumentException>()),
    );
    expect(
      () => StoredProgressSummary.decode(ready.replaceAll('}', ',"trend":1}')),
      throwsA(isA<AdaptationDocumentException>()),
    );
  });

  testWidgets('an empty profile shows the empty sentence in dark mode', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/progress',
      theme: AppTheme.dark(),
    );
    await until(tester, find.text('No stored session yet.'));
    expect(find.text('Local progress'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.textContaining('Completed sessions'), findsNothing);
    expect(find.textContaining('Abandoned sessions'), findsNothing);
    expect(find.textContaining('Safety stops'), findsNothing);
    expect(find.textContaining('Last stored pain'), findsNothing);
    expect(find.textContaining('milestone'), findsNothing);
    expect(find.text('The saved sessions could not be read.'), findsNothing);
    await tester.tap(find.text('Back'));
    await until(tester, find.text('HelpMeMove'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('counted sessions show every total and the copied pain', (
    tester,
  ) async {
    final String programJson = await io(tester, program);
    const String completedId = 'aaaaaaaa-1111-4111-8111-111111111111';
    const String abandonedId = 'mmmmmmmm-2222-4222-8222-222222222222';
    const String stoppedId = 'zzzzzzzz-3333-4333-8333-333333333333';
    final String completed = workout(programJson, completedId, pain: 1);
    final String abandoned = workout(
      programJson,
      abandonedId,
      outcome: 'abandoned',
    );
    final String stopped = workout(
      programJson,
      stoppedId,
      outcome: 'safety_stopped',
      pain: 7,
    );
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveProgramRecord(programJson);
      await store.saveWorkoutTerminal(
        sessionId: completedId,
        documentJson: completed,
      );
      await store.saveWorkoutTerminal(
        sessionId: abandonedId,
        documentJson: abandoned,
      );
      await store.saveWorkoutTerminal(
        sessionId: stoppedId,
        documentJson: stopped,
      );
    });
    await pumpRouter(tester, store, initialLocation: '/focus/progress');
    await until(tester, find.text('Local progress'));
    expect(find.text('Completed sessions: 1'), findsOneWidget);
    expect(find.text('Abandoned sessions: 1'), findsOneWidget);
    expect(find.text('Safety stops: 1'), findsOneWidget);
    expect(find.text('A stored session is on this device.'), findsOneWidget);
    expect(find.text('Last stored pain: 7'), findsOneWidget);
    expect(find.text('No stored session yet.'), findsNothing);
    expect(find.textContaining('milestone'), findsNothing);
    expect(
      find.text('The synthetic rule is not allowing a movement check.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('home keeps the check-in and intake beside local progress', (
    tester,
  ) async {
    final String programJson = await io(tester, program);
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    final String document = workout(programJson, sessionId, pain: 4);
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveProgramRecord(programJson);
      await store.saveWorkoutTerminal(
        sessionId: sessionId,
        documentJson: document,
      );
    });
    await pumpRouter(tester, store);
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text('See local progress'));
    expect(find.text('How are you feeling today?'), findsOneWidget);
    expect(find.text('Describe a limit'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Resume workout'), findsNothing);
    expect(find.text('Check in on the last session'), findsNothing);
    expect(find.text('Scaffold check'), findsOneWidget);
    expect(
      top(tester, 'How are you feeling today?'),
      lessThan(top(tester, 'Describe a limit')),
    );
    expect(
      top(tester, 'Describe a limit'),
      lessThan(top(tester, 'See local progress')),
    );
    expect(
      top(tester, 'See local progress'),
      lessThan(top(tester, 'Scaffold check')),
    );
    await tester.tap(find.text('See local progress'));
    await until(tester, find.text('Last stored pain: 4'));
    expect(find.text('HelpMeMove'), findsNothing);
  });

  testWidgets('null pain omits the pain line and still counts', (tester) async {
    final String programJson = await io(tester, program);
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    final String document = workout(programJson, sessionId);
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveWorkoutTerminal(
        sessionId: sessionId,
        documentJson: document,
      );
    });
    await pumpRouter(tester, store, initialLocation: '/focus/progress');
    await until(tester, find.text('Completed sessions: 1'));
    expect(find.text('Abandoned sessions: 0'), findsOneWidget);
    expect(find.text('Safety stops: 0'), findsOneWidget);
    expect(find.text('A stored session is on this device.'), findsOneWidget);
    expect(find.textContaining('Last stored pain'), findsNothing);
    expect(await io(tester, store.workoutRecordCount), 1);
  });

  testWidgets('an unreadable row stays stored', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveWorkoutTerminal(
        sessionId: '11111111-1111-4111-8111-111111111111',
        documentJson: '{}',
      );
    });
    await pumpRouter(tester, store, initialLocation: '/focus/progress');
    await until(tester, find.text('The saved sessions could not be read.'));
    expect(find.text('Local progress'), findsNothing);
    expect(find.text('Back'), findsOneWidget);
    expect(await io(tester, store.workoutRecordCount), 1);
    await tester.tap(find.text('Back'));
    await until(tester, find.text('HelpMeMove'));
    expect(await io(tester, store.workoutRecordCount), 1);
  });

  testWidgets('a storage error leaves the rows and opens recovery', (
    tester,
  ) async {
    final ThrowingProgressStore store = ThrowingProgressStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(14),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await io(tester, () async {
      await store.createProfile();
      await store.saveWorkoutTerminal(
        sessionId: '11111111-1111-4111-8111-111111111111',
        documentJson: '{}',
      );
    });
    await pumpRouter(tester, store, initialLocation: '/focus/progress');
    await until(tester, find.text('Storage is unavailable'));
    expect(find.text('The saved sessions could not be read.'), findsNothing);
    expect(await io(tester, store.workoutRecordCount), 1);
  });

  testWidgets('a sqlite read error opens recovery and keeps the row', (
    tester,
  ) async {
    final SqliteThrowingProgressStore store = SqliteThrowingProgressStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(14),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await io(tester, () async {
      await store.createProfile();
      await store.saveWorkoutTerminal(
        sessionId: '11111111-1111-4111-8111-111111111111',
        documentJson: '{}',
      );
    });
    await pumpRouter(tester, store, initialLocation: '/focus/progress');
    await until(tester, find.text('Storage is unavailable'));
    expect(await io(tester, store.workoutRecordCount), 1);
  });

  testWidgets('progress does not read the movement gate', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/progress',
      movementGateOpen: false,
    );
    await until(tester, find.text('No stored session yet.'));
    expect(
      find.text('The synthetic rule is not allowing a movement check.'),
      findsNothing,
    );
  });

  testWidgets('a missing or blocked store cannot open progress', (
    tester,
  ) async {
    await pumpRouter(tester, null, initialLocation: '/focus/progress');
    await until(tester, find.text('Home'));
    expect(find.text('Local progress'), findsNothing);

    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/progress',
      storageBlocked: true,
    );
    await until(tester, find.text('Home'));
    expect(find.text('See local progress'), findsNothing);
    expect(find.text('Local progress'), findsNothing);
  });

  testWidgets('large text and a wide window keep the counted lines', (
    tester,
  ) async {
    final String programJson = await io(tester, program);
    const String sessionId = '11111111-1111-4111-8111-111111111111';
    final String document = workout(programJson, sessionId, pain: 0);
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveWorkoutTerminal(
        sessionId: sessionId,
        documentJson: document,
      );
    });
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/progress',
      size: const Size(390, 844),
      textScale: 2,
    );
    await until(tester, find.text('Last stored pain: 0'));
    expect(find.text('Completed sessions: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/progress',
      size: const Size(840, 900),
    );
    await until(tester, find.text('A stored session is on this device.'));
    expect(find.text('Last stored pain: 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class SqliteThrowingProgressStore extends ProfileStore {
  SqliteThrowingProgressStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  @override
  Future<List<StoredTerminalWorkout>> loadWorkoutRecords() async {
    throw SqliteException(extendedResultCode: 1, message: 'read failed');
  }
}

class ThrowingProgressStore extends ProfileStore {
  ThrowingProgressStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  @override
  Future<List<StoredTerminalWorkout>> loadWorkoutRecords() async {
    throw const StorageIoException('read failed');
  }
}
