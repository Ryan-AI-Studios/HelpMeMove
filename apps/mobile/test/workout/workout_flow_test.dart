import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/main.dart';
import 'package:helpmemove/program/program_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';
import 'package:helpmemove/workout/session_document.dart';
import 'package:helpmemove/workout/workout_flow.dart';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-workout');
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
      random: Random(11),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    return store;
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

  Future<void> tapText(WidgetTester tester, String label) async {
    final Finder finder = find.text(label);
    final Finder scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(finder, 200, scrollable: scrollable.last);
    }
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
  }

  test('the golden session document decodes the opened shoulder session', () {
    final String raw = File('test/workout/opened_shoulder_session.json')
        .readAsStringSync()
        .trim();
    final LocalSession session = LocalSession.decode(raw);
    expect(session.state, 'preparing');
    expect(session.monotonicMs, 1000);
    expect(session.elapsedMs, 0);
    expect(session.outcome, isNull);
    expect(session.reportedPain, isNull);
    expect(session.symptom, isNull);
    expect(session.exercises.single.exerciseId, 'syn-shoulder-isometric');
    expect(session.exercises.single.sets, 1);
    expect(session.exercises.single.reps, 1);
    expect(session.exercises.single.repsDone, 0);
    expect(
      () => LocalSession.decode(raw.replaceFirst('"sets":1', '"sets":2')),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      () => LocalSession.decode(
        raw.replaceFirst('syn-shoulder-isometric', 'syn-not-a-fixture'),
      ),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      () => LocalSession.decode(
        raw.replaceFirst('"set_index":0', '"set_index":4294967296'),
      ),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      () => LocalSession.decode(
        raw.replaceFirst('"reps_done":0', '"reps_done":4294967296'),
      ),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      () => LocalSession.decode('$raw,"clinical":true}'),
      throwsA(
        isA<LocalSessionException>().having(
          (LocalSessionException error) => error.toString(),
          'toString',
          isNot(contains('clinical')),
        ),
      ),
    );
    expect(
      () => LocalSession.decode(
        raw.replaceFirst('"state":"preparing"', '"state":"positioning"'),
      ),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      () => LocalSession.decode(raw.replaceFirst(',"symptom":null', '')),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      () => LocalSession.decode(
        raw.replaceFirst('"symptom":null}', '"symptom":null,"extra":1}'),
      ),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      LocalSession.decode(
        raw.replaceFirst('"elapsed_ms":0', '"elapsed_ms":9223372036854775807'),
      ).elapsedMs,
      9223372036854775807,
    );
    expect(
      () => LocalSession.decode(
        raw.replaceFirst('"elapsed_ms":0', '"elapsed_ms":9223372036854775808'),
      ),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      () => LocalSession.decode(
        raw.replaceFirst('"elapsed_ms":0', '"elapsed_ms":18446744073709551616'),
      ),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      () => LocalSession.decode(
        raw.replaceFirst(
          '"monotonic_ms":1000',
          '"monotonic_ms":18446744073709551616',
        ),
      ),
      throwsA(isA<LocalSessionException>()),
    );
    expect(
      () => LocalSession.decode(
        raw.replaceFirst(
          '"rest_until_ms":null',
          '"rest_until_ms":18446744073709551616',
        ),
      ),
      throwsA(isA<LocalSessionException>()),
    );
  });

  testWidgets('home shows one workout card and the program route has none', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.createProfile();
    });
    await tester.pumpWidget(HelpMeMoveApp(key: UniqueKey(), store: store));
    await until(tester, find.text('Describe a limit'));
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Resume workout'), findsNothing);
    expect(find.text('Your starting plan'), findsNothing);

    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    await tester.runAsync(() => store.saveProgramRecord(program));
    await tester.pumpWidget(HelpMeMoveApp(key: UniqueKey(), store: store));
    await until(tester, find.text('Start workout'));
    expect(find.text('Resume workout'), findsNothing);
    expect(find.text('Describe a limit'), findsOneWidget);

    final WorkoutView opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    );
    await tester.runAsync(() => store.saveWorkoutDraft(opened.documentJson));
    await tester.pumpWidget(HelpMeMoveApp(key: UniqueKey(), store: store));
    await until(tester, find.text('Resume workout'));
    expect(find.text('Start workout'), findsNothing);

    final LocalProgram preview = LocalProgram.decode(program);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: buildHelpMeMoveRouter(
          initialLocation: '/focus/program',
          store: store,
          previewProgram: preview,
          movementGateOpen: true,
        ),
      ),
    );
    await until(tester, find.text('Your starting plan'));
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Resume workout'), findsNothing);
  });

  testWidgets('a saved program walks through a rep, pain, pause, and skip', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(tester, find.text('Start workout'));
    await tester.tap(find.text('Start workout'));
    await until(tester, find.text("Today's session"));
    expect(
      find.text('Synthetic session. Not a medical workout.'),
      findsOneWidget,
    );
    expect(find.text('About 15 minutes'), findsOneWidget);
    expect(find.text('1 × 1'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    expect(find.text('Synthetic syn shoulder isometric'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await until(tester, find.text("I'm ready"));
    expect(
      find.text('Synthetic fixture. Not an exercise prescription.'),
      findsOneWidget,
    );

    await tester.tap(find.text("I'm ready"));
    await until(tester, find.text('This hurts'));
    expect(find.text('Set 1 of 1'), findsOneWidget);
    expect(find.text('Rep 1 of 1'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Rest'), findsNothing);

    await tester.tap(find.text('Rep 1 of 1'));
    await until(tester, find.text('Session saved'));
    expect(find.text('1 exercise. 1 completed rep.'), findsOneWidget);
    expect(find.text('Great'), findsNothing);
    expect(find.textContaining('°'), findsNothing);
    final List<String> saved =
        await tester.runAsync(store.workoutRecordDocuments) ?? <String>[];
    expect(saved, hasLength(1));
    expect(saved.single, contains('"outcome":"completed"'));
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
    expect(await tester.runAsync(store.loadProgramRecord), program);

    await tester.tap(find.text('Home'));
    await until(tester, find.text('Start workout'));
    expect(find.text('Resume workout'), findsNothing);
    await tester.tap(find.text('Start workout'));
    await until(tester, find.text('Start'));
    await tester.tap(find.text('Start'));
    await until(tester, find.text("I'm ready"));
    await tester.tap(find.text("I'm ready"));
    await until(tester, find.text('This hurts'));
    await tester.tap(find.text('This hurts'));
    await until(tester, find.text('Exercise paused'));
    expect(find.text('Mild discomfort'), findsOneWidget);
    expect(find.text('Sharp pain'), findsOneWidget);
    expect(find.text('Pain increased noticeably'), findsOneWidget);
    expect(find.text('Numbness / tingling'), findsOneWidget);
    expect(find.text('Weakness / instability'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);
    await tapText(tester, '10');
    await tapText(tester, 'Numbness / tingling');
    expect(find.text('Exercise paused'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);
    expect(find.text('Session stopped'), findsNothing);
    await tapText(tester, 'End session');
    await until(tester, find.text('Session stopped'));
    expect(
      find.text(
        'You ended this synthetic session. Nothing was marked complete.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('911'), findsNothing);
    expect(find.textContaining('evaluation'), findsNothing);
    final List<String> records =
        await tester.runAsync(store.workoutRecordDocuments) ?? <String>[];
    expect(records, hasLength(2));
    final String stopped = records.singleWhere(
      (String row) => row.contains('"outcome":"safety_stopped"'),
    );
    expect(stopped, contains('"reported_pain":10'));
    expect(stopped, contains('numbness_tingling'));

    await tester.tap(find.text('Home'));
    await until(tester, find.text('Start workout'));
    await tester.tap(find.text('Start workout'));
    await until(tester, find.text('Start'));
    await tester.tap(find.text('Start'));
    await until(tester, find.text("I'm ready"));
    await tester.tap(find.text("I'm ready"));
    await until(tester, find.text('Pause'));
    await tester.tap(find.text('Pause'));
    await until(tester, find.text('Session paused'));
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Make session shorter'), findsOneWidget);
    expect(find.text('Skip current exercise'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);
    expect(find.textContaining('remaining'), findsNothing);
    await tapText(tester, 'End session');
    await until(tester, find.text('Session ended'));
    expect(
      find.text('This synthetic session was not saved as complete.'),
      findsOneWidget,
    );
    final List<String> abandoned =
        await tester.runAsync(store.workoutRecordDocuments) ?? <String>[];
    expect(
      abandoned.where((String row) => row.contains('"outcome":"abandoned"')),
      hasLength(1),
    );
  });

  testWidgets('skip from the active exercise abandons without a rep', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(tester, find.text('Start workout'));
    await tester.tap(find.text('Start workout'));
    await until(tester, find.text('Start'));
    await tester.tap(find.text('Start'));
    await until(tester, find.text("I'm ready"));
    await tester.tap(find.text("I'm ready"));
    await until(tester, find.text('Skip'));
    await tester.tap(find.text('Skip'));
    await until(tester, find.text('Session ended'));
    final List<String> records =
        await tester.runAsync(store.workoutRecordDocuments) ?? <String>[];
    expect(records.single, contains('"outcome":"abandoned"'));
    expect(records.single, contains('"reps_done":0'));
  });

  testWidgets('no profile and no program write nothing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: buildHelpMeMoveRouter(initialLocation: '/focus/workout'),
      ),
    );
    await until(tester, find.text('Home'));
    expect(find.text('There is no saved session.'), findsNothing);
    expect(find.text("Today's session"), findsNothing);

    final ProfileStore store = openStore();
    await tester.runAsync(store.createProfile);
    final List<String> events =
        await tester.runAsync(store.eventPayloads) ?? <String>[];
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: buildHelpMeMoveRouter(
          initialLocation: '/focus/workout',
          store: store,
        ),
      ),
    );
    await until(tester, find.text('There is no saved session.'));
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
    expect(await tester.runAsync(store.workoutRecordCount), 0);
    expect(await tester.runAsync(store.eventPayloads), events);
  });

  testWidgets('a storage read failure leaves the program row', (
    WidgetTester tester,
  ) async {
    final ThrowingWorkoutStore store = ThrowingWorkoutStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(11),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
    });
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: buildHelpMeMoveRouter(
          initialLocation: '/focus/workout',
          store: store,
        ),
      ),
    );
    await until(tester, find.text('Storage is unavailable'));
    expect(await tester.runAsync(store.loadProgramRecord), program);
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
  });

  testWidgets('a corrupt draft is cleared and is not a record', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
      await store.saveWorkoutDraft('{"clinical":true}');
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(
      tester,
      find.text('The saved workout could not be read. It was cleared.'),
    );
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Resume workout'), findsNothing);
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
    expect(await tester.runAsync(store.workoutRecordCount), 0);
    expect(await tester.runAsync(store.loadProgramRecord), program);
    final List<String> events =
        await tester.runAsync(store.eventPayloads) ?? <String>[];
    expect(events, <String>['helpmemove-storage-probe']);
  });

  testWidgets('background pause does not add later time to the rep clock', (
    WidgetTester tester,
  ) async {
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final WorkoutView opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    );
    final String demonstrating = applyWorkoutEvent(
      documentJson: opened.documentJson,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 1000,
    ).documentJson;
    final String active = applyWorkoutEvent(
      documentJson: demonstrating,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 1000,
    ).documentJson;
    final ManualWorkoutClock clock = ManualWorkoutClock();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WorkoutFlow(previewDocument: active, clock: clock),
      ),
    );
    await until(tester, find.text('This hurts'));
    clock.start();
    clock.advance(1500);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(tester, find.text('Session paused'));
    expect(find.text('0:01'), findsOneWidget);
    final int frozen = clock.elapsedMilliseconds;
    clock.advance(9000);
    expect(clock.elapsedMilliseconds, frozen);
    await tester.pump();
    expect(find.text('0:01'), findsOneWidget);
    expect(find.textContaining('remaining'), findsNothing);
  });

  testWidgets('a completion in flight ignores a background pause', (
    WidgetTester tester,
  ) async {
    final HoldingTerminalStore store = HoldingTerminalStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(11),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(tester, find.text('Start workout'));
    await tester.tap(find.text('Start workout'));
    await until(tester, find.text('Start'));
    await tester.tap(find.text('Start'));
    await until(tester, find.text("I'm ready"));
    await tester.tap(find.text("I'm ready"));
    await until(tester, find.text('Rep 1 of 1'));
    store.holdTerminal = Completer<void>();
    await tester.tap(find.text('Rep 1 of 1'));
    await tester.pump();
    expect(store.terminalEntered, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    expect(store.draftsWhileHolding, 0);
    // paused disables frames. resumed does not dispatch a session resume.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    store.holdTerminal!.complete();
    await until(tester, find.text('Session saved'));
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
    final List<String> records =
        await tester.runAsync(store.workoutRecordDocuments) ?? <String>[];
    expect(records, hasLength(1));
    expect(records.single, contains('"outcome":"completed"'));
  });

  testWidgets('leaving during a terminal save does not restore the draft', (
    WidgetTester tester,
  ) async {
    final HoldingTerminalStore store = HoldingTerminalStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(11),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(tester, find.text('Start workout'));
    await tester.tap(find.text('Start workout'));
    await until(tester, find.text('Start'));
    await tester.tap(find.text('Start'));
    await until(tester, find.text("I'm ready"));
    await tester.tap(find.text("I'm ready"));
    await until(tester, find.text('Rep 1 of 1'));
    store.holdTerminal = Completer<void>();
    await tester.tap(find.text('Rep 1 of 1'));
    await tester.pump();
    expect(store.terminalEntered, 1);
    await tester.pumpWidget(HelpMeMoveApp(key: UniqueKey(), store: store));
    store.holdTerminal!.complete();
    await until(tester, find.text('Start workout'));
    expect(find.text('Resume workout'), findsNothing);
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
    final List<String> records =
        await tester.runAsync(store.workoutRecordDocuments) ?? <String>[];
    expect(records, hasLength(1));
    expect(records.single, contains('"outcome":"completed"'));
  });

  testWidgets('backgrounding the pain form stores the visible selection', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(tester, find.text('Start workout'));
    await tester.tap(find.text('Start workout'));
    await until(tester, find.text('Start'));
    await tester.tap(find.text('Start'));
    await until(tester, find.text("I'm ready"));
    await tester.tap(find.text("I'm ready"));
    await until(tester, find.text('This hurts'));
    await tester.tap(find.text('This hurts'));
    await until(tester, find.text('Exercise paused'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Numbness / tingling'),
          )
          .onPressed,
      isNotNull,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    final String? draft = await tester.runAsync<String?>(
      store.loadWorkoutDraft,
    );
    expect(draft, contains('"state":"pain_check"'));
    expect(draft, contains('"symptom":"mild_discomfort"'));
    expect(draft, contains('"reported_pain":0'));
    expect(find.text('Exercise paused'), findsOneWidget);
    expect(find.text('Session stopped'), findsNothing);
    expect(await tester.runAsync(store.workoutRecordCount), 0);
  });

  testWidgets('a restored pain check keeps the stored selection', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final WorkoutView opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    );
    final String demonstrating = applyWorkoutEvent(
      documentJson: opened.documentJson,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 1000,
    ).documentJson;
    final String active = applyWorkoutEvent(
      documentJson: demonstrating,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 1000,
    ).documentJson;
    final String pain = applyWorkoutEvent(
      documentJson: active,
      eventJson: '{"name":"report_pain","symptom":"mild_discomfort","reported_pain":0}',
      monotonicMillis: 1000,
    ).documentJson;
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
      await store.saveWorkoutDraft(pain);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(tester, find.text('Resume workout'));
    await tester.tap(find.text('Resume workout'));
    await until(tester, find.text('Exercise paused'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Mild discomfort'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Numbness / tingling'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'End session'),
          )
          .onPressed,
      isNotNull,
    );
    await tapText(tester, 'Numbness / tingling');
    await tapText(tester, '10');
    await tapText(tester, 'End session');
    await until(tester, find.text('Session stopped'));
    final List<String> records =
        await tester.runAsync(store.workoutRecordDocuments) ?? <String>[];
    expect(records.single, contains('"symptom":"mild_discomfort"'));
    expect(records.single, contains('"reported_pain":0'));
    expect(records.single, isNot(contains('numbness_tingling')));
  });

  testWidgets('a foreground return before resume save still pauses', (
    WidgetTester tester,
  ) async {
    final HoldingTerminalStore store = HoldingTerminalStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(11),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final WorkoutView opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    );
    final String demonstrating = applyWorkoutEvent(
      documentJson: opened.documentJson,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 1000,
    ).documentJson;
    final String active = applyWorkoutEvent(
      documentJson: demonstrating,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 1000,
    ).documentJson;
    final String paused = applyWorkoutEvent(
      documentJson: active,
      eventJson: '{"name":"pause"}',
      monotonicMillis: 1000,
    ).documentJson;
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
      await store.saveWorkoutDraft(paused);
    });
    final ManualWorkoutClock clock = ManualWorkoutClock();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WorkoutFlow(store: store, clock: clock),
      ),
    );
    await until(tester, find.text('Session paused'));
    expect(find.text('0:00'), findsOneWidget);
    store.holdTerminal = Completer<void>();
    await tester.tap(find.text('Resume'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    expect(store.draftsWhileHolding, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    store.holdTerminal!.complete();
    store.holdTerminal = null;
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
    }
    final int frozen = clock.elapsedMilliseconds;
    clock.advance(5000);
    expect(clock.elapsedMilliseconds, frozen);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await until(tester, find.text('Session paused'));
    final String? draft = await tester.runAsync<String?>(
      store.loadWorkoutDraft,
    );
    expect(draft, contains('"state":"paused"'));
    expect(draft, contains('"elapsed_ms":0'));
    expect(find.text('0:00'), findsOneWidget);
    expect(await tester.runAsync(store.workoutRecordCount), 0);
  });

  testWidgets('a draft with fixture-mismatched doses is cleared', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final String opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    ).documentJson.replaceFirst('"sets":1', '"sets":2');
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
      await store.saveWorkoutDraft(opened);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(
      tester,
      find.text('The saved workout could not be read. It was cleared.'),
    );
    expect(find.text('Resume workout'), findsNothing);
    expect(find.text('Start workout'), findsOneWidget);
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
    expect(await tester.runAsync(store.workoutRecordCount), 0);
    expect(await tester.runAsync(store.loadProgramRecord), program);
  });

  testWidgets('a draft with an unknown exercise is cleared', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final String opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    ).documentJson.replaceFirst('syn-shoulder-isometric', 'syn-not-a-fixture');
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
      await store.saveWorkoutDraft(opened);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(
      tester,
      find.text('The saved workout could not be read. It was cleared.'),
    );
    expect(find.text('Resume workout'), findsNothing);
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
    expect(await tester.runAsync(store.workoutRecordCount), 0);
    expect(await tester.runAsync(store.loadProgramRecord), program);
  });

  testWidgets('a draft with an oversized set index is cleared', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final String opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    ).documentJson.replaceFirst('"set_index":0', '"set_index":4294967296');
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
      await store.saveWorkoutDraft(opened);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(
      tester,
      find.text('The saved workout could not be read. It was cleared.'),
    );
    expect(find.text('Resume workout'), findsNothing);
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
    expect(await tester.runAsync(store.workoutRecordCount), 0);
    expect(await tester.runAsync(store.loadProgramRecord), program);
  });

  testWidgets('a draft with an oversized rep count is cleared', (
    WidgetTester tester,
  ) async {
    final ProfileStore store = openStore();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final String opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    ).documentJson.replaceFirst('"reps_done":0', '"reps_done":4294967296');
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
      await store.saveWorkoutDraft(opened);
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await until(
      tester,
      find.text('The saved workout could not be read. It was cleared.'),
    );
    expect(find.text('Resume workout'), findsNothing);
    expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
    expect(await tester.runAsync(store.workoutRecordCount), 0);
    expect(await tester.runAsync(store.loadProgramRecord), program);
  });

  testWidgets('large text keeps This hurts reachable and 840 stays on screen', (
    WidgetTester tester,
  ) async {
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final WorkoutView opened = openWorkout(
      programJson: program,
      monotonicMillis: 0,
      sessionId: '11111111-1111-4111-8111-111111111111',
    );
    final String demonstrating = applyWorkoutEvent(
      documentJson: opened.documentJson,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 0,
    ).documentJson;
    final String active = applyWorkoutEvent(
      documentJson: demonstrating,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 0,
    ).documentJson;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: WorkoutFlow(previewDocument: active),
      ),
    );
    await until(tester, find.text('Pause'));
    await tester.scrollUntilVisible(
      find.text('This hurts'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('This hurts'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(840, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WorkoutFlow(previewDocument: active),
      ),
    );
    await until(tester, find.text('Set 1 of 1'));
    expect(tester.takeException(), isNull);
  });
}

class HoldingTerminalStore extends ProfileStore {
  HoldingTerminalStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  Completer<void>? holdTerminal;
  int terminalEntered = 0;
  int draftsWhileHolding = 0;

  @override
  Future<void> onWorkoutQueueEntered() async {
    terminalEntered += 1;
    final Completer<void>? hold = holdTerminal;
    if (hold != null) {
      await hold.future;
    }
  }

  @override
  Future<void> saveWorkoutDraft(String documentJson) async {
    final Completer<void>? hold = holdTerminal;
    if (hold != null && !hold.isCompleted) {
      draftsWhileHolding += 1;
      await hold.future;
    }
    await super.saveWorkoutDraft(documentJson);
  }
}

class ThrowingWorkoutStore extends ProfileStore {
  ThrowingWorkoutStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  int _draftReads = 0;

  @override
  Future<String?> loadWorkoutDraft() async {
    _draftReads += 1;
    if (_draftReads == 1) {
      throw const StorageIoException('read failed');
    }
    return super.loadWorkoutDraft();
  }
}
