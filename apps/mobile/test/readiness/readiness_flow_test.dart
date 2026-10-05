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

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-readiness');
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
      random: Random(12),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    return store;
  }

  const String sessionId = '11111111-1111-4111-8111-111111111111';
  const String intake =
      '{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}],"schema_ack":"yes","schema_green":"present"}';
  const String assessment =
      '{"record_version":1,"instrument_id":"syn-assessment-core","stopped":false,"complete":true,"areas":[{"region":"shoulder","laterality":"left","rating":"limited"}],"note":""}';

  Future<String> program() =>
      File('test/program/green_shoulder_program.json').readAsString();

  String completedWorkout(String programJson, {int pain = 4}) {
    WorkoutView view = openWorkout(
      programJson: programJson,
      monotonicMillis: 1000,
      sessionId: sessionId,
    );
    expect(view.outcome, 'ready');
    String document = view.documentJson;
    String step(String event, int now) {
      view = applyWorkoutEvent(
        documentJson: document,
        eventJson: event,
        monotonicMillis: now,
      );
      expect(view.outcome, 'ready', reason: view.errorCode);
      document = view.documentJson;
      return document;
    }

    step(r'{"name":"ready"}', 1000);
    step(r'{"name":"ready"}', 1100);
    step(
      '{"name":"report_pain","reported_pain":$pain,"symptom":"mild_discomfort"}',
      1100,
    );
    step(r'{"name":"continue_after_pain"}', 1100);
    step(r'{"name":"resume"}', 1200);
    return step(r'{"name":"complete_rep"}', 1200);
  }

  Future<ProfileStore> seed({
    required String workout,
    bool withDraft = false,
  }) async {
    final ProfileStore store = openStore();
    await store.createProfile();
    await store.saveDraft(intake);
    await store.saveAssessmentRecord(assessment);
    await store.saveProgramRecord(await program());
    if (withDraft) {
      await store.saveWorkoutDraft(workout);
    } else {
      await store.saveWorkoutTerminal(
        sessionId: sessionId,
        documentJson: workout,
      );
    }
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

  Future<void> pumpRouter(
    WidgetTester tester,
    ProfileStore store, {
    String initialLocation = '/',
    bool movementGateOpen = false,
    String? previewAdaptation,
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
          movementGateOpen: movementGateOpen,
          previewAdaptation: previewAdaptation,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpBare(
    WidgetTester tester, {
    required String location,
    bool storageBlocked = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: buildHelpMeMoveRouter(
          initialLocation: location,
          storageBlocked: storageBlocked,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('home hides start until a maintain decision exists', (
    tester,
  ) async {
    final String programJson = await io(tester, program);
    final String workout = completedWorkout(programJson);
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await pumpRouter(tester, store);
    await until(tester, find.text('How are you feeling today?'));
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Resume workout'), findsNothing);

    await tester.tap(find.text('How are you feeling today?'));
    await until(tester, find.text('Low soreness'));
    expect(find.text('Moderate soreness'), findsOneWidget);
    expect(find.text('High soreness'), findsOneWidget);

    await tester.tap(find.text('Low soreness'));
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text(maintainReason));
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Check in on the last session'), findsOneWidget);
    expect(find.text('Foundations'), findsWidgets);
    expect(find.text('Back'), findsNothing);
    expect(find.text('How are you feeling today?'), findsNothing);
    await tester.tap(find.text('Check in on the last session'));
    await until(tester, find.text('Settled'));
    await tester.tap(find.text('Settled'));
    await until(tester, find.text(maintainReason));
    expect(find.text('Start workout'), findsOneWidget);
    await tester.tap(find.text('Start workout'));
    await until(tester, find.text("Today's session"));
    expect(find.text('HelpMeMove'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('high soreness shows the pause reason and hides start', (
    tester,
  ) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await pumpRouter(tester, store, initialLocation: '/focus/readiness');
    await until(tester, find.text('High soreness'));
    await tester.tap(find.text('High soreness'));
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text(pauseReason));
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Check in on the last session'), findsNothing);
    expect(find.text('Back'), findsNothing);
    expect(find.text('How are you feeling today?'), findsNothing);
  });

  testWidgets('a program with no terminal workout still shows start', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    final String programJson = await io(tester, program);
    await io(tester, () async {
      await store.createProfile();
      await store.saveProgramRecord(programJson);
    });
    await pumpRouter(tester, store);
    await until(tester, find.text('Start workout'));
    expect(find.text('How are you feeling today?'), findsNothing);
  });

  testWidgets('a decodable draft shows resume and no readiness card', (
    tester,
  ) async {
    final String programJson = await io(tester, program);
    final String workout = completedWorkout(programJson);
    final String opened = openWorkout(
      programJson: programJson,
      monotonicMillis: 1000,
      sessionId: sessionId,
    ).documentJson;
    final ProfileStore store = await io(
      tester,
      () => seed(workout: workout, withDraft: true),
    );
    await io(tester, () => store.saveWorkoutDraft(opened));
    await pumpRouter(tester, store);
    await until(tester, find.text('Resume workout'));
    expect(find.text('How are you feeling today?'), findsNothing);
    expect(find.text('Start workout'), findsNothing);
  });

  testWidgets('safety stopped shows the notice and no start', (tester) async {
    final String stopped = completedWorkout(await io(tester, program))
        .replaceAll('"completed"', '"safety_stopped"');
    final ProfileStore store = await io(tester, () => seed(workout: stopped));
    await pumpRouter(tester, store);
    await until(
      tester,
      find.text('The last session stopped. No change was saved.'),
    );
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('How are you feeling today?'), findsNothing);
  });

  test('a malformed exercise entry does not decode', () {
    const String session =
        '{"action":"maintain","reason":"Today\'s check keeps the same exercises.","record_version":1,"reported_pain":null,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111","exercises":';
    expect(
      () => StoredAdaptation.decode('$session[42]}'),
      throwsA(isA<AdaptationDocumentException>()),
    );
    expect(
      () => StoredAdaptation.decode(
        '$session[{"exercise_id":"syn-shoulder-isometric","sets":1,"reps":1}]}',
      ),
      throwsA(isA<AdaptationDocumentException>()),
    );
    StoredAdaptation.decode(
      '$session[{"exercise_id":"syn-shoulder-isometric","sets":1,"reps":1,"tempo":{"eccentric":2,"pause":1,"concentric":2}}]}',
    );
  });

  testWidgets('a malformed exercise clears the pair and returns check-in', (
    tester,
  ) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await io(
      tester,
      () => store.saveAdaptationPair(
        sessionId: sessionId,
        readinessJson: '{"record_version":1,"recorded_at_ms":1,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111","soreness":"low"}',
        adaptationJson: '{"action":"maintain","exercises":[42],"reason":"Today\'s check keeps the same exercises.","record_version":1,"reported_pain":null,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111"}',
        updatedAtMs: store.clockMillis(),
      ),
    );
    await pumpRouter(tester, store);
    await until(
      tester,
      find.text('The saved check could not be read. It was cleared.'),
    );
    expect(find.text('How are you feeling today?'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    expect(
      await io(tester, () => store.loadAdaptationRecord(sessionId)),
      isNull,
    );
    expect(
      await io(tester, () => store.loadReadinessRecord(sessionId)),
      isNull,
    );
    expect(await io(tester, store.loadProgramRecord), isNotNull);
  });

  testWidgets('a corrupt pair is cleared and the check-in returns', (
    tester,
  ) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await io(
      tester,
      () => store.saveAdaptationPair(
        sessionId: sessionId,
        readinessJson: '{"not":"readiness"}',
        adaptationJson: '{"not":"adaptation"}',
        updatedAtMs: store.clockMillis(),
      ),
    );
    await pumpRouter(tester, store);
    await until(
      tester,
      find.text('The saved check could not be read. It was cleared.'),
    );
    expect(find.text('How are you feeling today?'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    expect(
      await io(tester, () => store.loadAdaptationRecord(sessionId)),
      isNull,
    );
    expect(await io(tester, store.loadProgramRecord), isNotNull);
  });

  testWidgets('withheld returns home with the unchanged sentence', (
    tester,
  ) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await io(
      tester,
      () => store.saveDraft(
        '{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}],"schema_ack":"yes"}',
      ),
    );
    await pumpRouter(tester, store, initialLocation: '/focus/readiness');
    await until(tester, find.text('Low soreness'));
    await tester.tap(find.text('Low soreness'));
    await until(tester, find.text('No change was saved.'));
    await until(tester, find.text('How are you feeling today?'));
    expect(
      await io(tester, () => store.loadAdaptationRecord(sessionId)),
      isNull,
    );
  });

  testWidgets('program route gains neither button', (tester) async {
    final ProfileStore store = openStore();
    final String programJson = await io(tester, program);
    await io(tester, () async {
      await store.createProfile();
      await store.saveProgramRecord(programJson);
    });
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/program',
      movementGateOpen: true,
    );
    await until(tester, find.text('Home'));
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('How are you feeling today?'), findsNothing);
    expect(find.text('Check in on the last session'), findsNothing);
  });

  testWidgets('readiness ignores the movement gate', (tester) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/readiness',
      movementGateOpen: false,
    );
    await until(tester, find.text('Moderate soreness'));
  });

  testWidgets('modified plan reloads from the store without a route extra', (
    tester,
  ) async {
    final String workout = completedWorkout(
      await io(tester, program),
      pain: 10,
    );
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await pumpRouter(tester, store, initialLocation: '/focus/readiness');
    await until(tester, find.text('Low soreness'));
    await tester.tap(find.text('Low soreness'));
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text('Check in on the last session'));
    expect(find.text('Start workout'), findsNothing);
    await pumpRouter(tester, store, initialLocation: '/focus/modified-plan');
    await until(tester, find.text(maintainReason));
    expect(find.text('Start workout'), findsNothing);
  });

  testWidgets('large text keeps the readiness buttons on a phone surface', (
    tester,
  ) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/readiness',
      size: const Size(390, 844),
      textScale: 2,
    );
    await until(tester, find.text('Low soreness'));
    await tester.scrollUntilVisible(
      find.text('High soreness'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('High soreness'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide modified plan shows the reason and start', (tester) async {
    const String document =
        '{"action":"maintain","exercises":[],"reason":"Today\'s check keeps the same exercises.","record_version":1,"reported_pain":null,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111"}';
    final ProfileStore store = openStore();
    await io(tester, store.createProfile);
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/modified-plan',
      previewAdaptation: document,
      size: const Size(840, 1200),
      theme: AppTheme.dark(),
    );
    await until(tester, find.text(maintainReason));
    expect(find.text('Start workout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing profile uses the unavailable screen', (tester) async {
    await pumpBare(tester, location: '/focus/readiness');
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Low soreness'), findsNothing);
    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.pump();
    expect(find.text('HelpMeMove'), findsOneWidget);
  });

  testWidgets('a blocked store uses the unavailable screen', (tester) async {
    await pumpBare(
      tester,
      location: '/focus/modified-plan',
      storageBlocked: true,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
  });

  const String maintainPair =
      '{"action":"maintain","exercises":[],"reason":"Today\'s check keeps the same exercises.","record_version":1,"reported_pain":null,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111"}';
  const String readinessDocument =
      '{"record_version":1,"recorded_at_ms":1000,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111","soreness":"low"}';

  String flareEnvelope(String choice, String action, String reason) {
    return '{"decision":{"action":"$action","exercises":[],"reason":"$reason","record_version":1,"reported_pain":null,"rule_id":"syn-flare-core","rule_version":1,"session_id":"$sessionId"},"followup":{"choice":"$choice","record_version":1,"recorded_at_ms":1000,"rule_id":"syn-flare-core","rule_version":1,"session_id":"$sessionId"},"record_version":1}';
  }

  Future<ProfileStore> seedMaintain(String workout) async {
    final ProfileStore store = await seed(workout: workout);
    await store.saveAdaptationPair(
      sessionId: sessionId,
      readinessJson: readinessDocument,
      adaptationJson: maintainPair,
      updatedAtMs: store.clockMillis(),
    );
    return store;
  }

  testWidgets('maintain without a flare row hides start', (tester) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seedMaintain(workout));
    await pumpRouter(tester, store);
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text('Check in on the last session'));
    expect(find.text(maintainReason), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('How are you feeling today?'), findsNothing);
  });

  testWidgets('keep program shows start and no second check-in', (
    tester,
  ) async {
    final ProfileStore store = await io(tester, () async {
      final ProfileStore opened = await seedMaintain(
        completedWorkout(await program()),
      );
      await opened.saveFlareFollowup(
        sessionId: sessionId,
        documentJson: flareEnvelope('settled', 'keep_program', maintainReason),
        updatedAtMs: opened.clockMillis(),
      );
      return opened;
    });
    await pumpRouter(tester, store);
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text(maintainReason));
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Check in on the last session'), findsNothing);
  });

  testWidgets('modified plan shows start only after keep program', (
    tester,
  ) async {
    final ProfileStore store = await io(tester, () async {
      return seedMaintain(completedWorkout(await program()));
    });
    await pumpRouter(tester, store, initialLocation: '/focus/modified-plan');
    await until(tester, find.text(maintainReason));
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Back'), findsOneWidget);
    await io(tester, () async {
      return store.saveFlareFollowup(
        sessionId: sessionId,
        documentJson: flareEnvelope('same', 'keep_program', maintainReason),
        updatedAtMs: store.clockMillis(),
      );
    });
    await pumpRouter(tester, store, initialLocation: '/focus/modified-plan');
    await until(tester, find.text(maintainReason));
    expect(find.text('Start workout'), findsOneWidget);
  });

  testWidgets('modified plan hides start when the terminal cannot be read', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveWorkoutTerminal(
        sessionId: sessionId,
        documentJson: '{"not":"a session"}',
      );
    });
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/modified-plan',
      previewAdaptation: maintainPair,
    );
    await until(tester, find.text(maintainReason));
    expect(find.text('Start workout'), findsNothing);
  });

  testWidgets('modified plan hides start for an unfinished terminal', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      final WorkoutView opened = openWorkout(
        programJson: await program(),
        monotonicMillis: 1000,
        sessionId: sessionId,
      );
      expect(opened.outcome, 'ready');
      await store.saveWorkoutTerminal(
        sessionId: sessionId,
        documentJson: opened.documentJson,
      );
    });
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/modified-plan',
      previewAdaptation: maintainPair,
    );
    await until(tester, find.text(maintainReason));
    expect(find.text('Start workout'), findsNothing);
  });

  testWidgets('a saved pause hides start', (tester) async {
    final ProfileStore store = await io(tester, () async {
      final ProfileStore opened = await seedMaintain(
        completedWorkout(await program()),
      );
      await opened.saveFlareFollowup(
        sessionId: sessionId,
        documentJson: flareEnvelope('worse_today', 'pause_today', pauseReason),
        updatedAtMs: opened.clockMillis(),
      );
      return opened;
    });
    await pumpRouter(tester, store);
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text(pauseReason));
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Check in on the last session'), findsNothing);
  });

  testWidgets('worse today saves a pause and hides start', (tester) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seedMaintain(workout));
    await pumpRouter(tester, store, initialLocation: '/focus/flare-followup');
    await until(tester, find.text('Worse today'));
    await tester.tap(find.text('Worse today'));
    await until(tester, find.text(pauseReason));
    expect(find.text('Start workout'), findsNothing);
    await tester.tap(find.text('Back'));
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text(pauseReason));
    expect(find.text('Start workout'), findsNothing);
    expect(find.text('Check in on the last session'), findsNothing);
  });

  testWidgets('a corrupt flare envelope clears only that row', (tester) async {
    final ProfileStore store = await io(tester, () async {
      final ProfileStore opened = await seedMaintain(
        completedWorkout(await program()),
      );
      await opened.saveFlareFollowup(
        sessionId: sessionId,
        documentJson: '{"record_version":1,"exercises":[42]}',
        updatedAtMs: opened.clockMillis(),
      );
      return opened;
    });
    await pumpRouter(tester, store);
    await until(tester, find.text('HelpMeMove'));
    await until(
      tester,
      find.text('The saved check could not be read. It was cleared.'),
    );
    expect(find.text(maintainReason), findsOneWidget);
    expect(find.text('Check in on the last session'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    expect(
      await io(tester, () => store.loadReadinessRecord(sessionId)),
      readinessDocument,
    );
    expect(await io(tester, () => store.loadFlareFollowup(sessionId)), isNull);
  });

  testWidgets('a worse today keep program envelope is cleared', (tester) async {
    final ProfileStore store = await io(tester, () async {
      final ProfileStore opened = await seedMaintain(
        completedWorkout(await program()),
      );
      await opened.saveFlareFollowup(
        sessionId: sessionId,
        documentJson: flareEnvelope(
          'worse_today',
          'keep_program',
          maintainReason,
        ),
        updatedAtMs: opened.clockMillis(),
      );
      return opened;
    });
    await pumpRouter(tester, store);
    await until(tester, find.text('HelpMeMove'));
    await until(
      tester,
      find.text('The saved check could not be read. It was cleared.'),
    );
    expect(find.text('Check in on the last session'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
    expect(await io(tester, () => store.loadFlareFollowup(sessionId)), isNull);
    expect(
      await io(tester, () => store.loadReadinessRecord(sessionId)),
      readinessDocument,
    );
  });

  testWidgets('a same choice pause envelope is cleared', (tester) async {
    final ProfileStore store = await io(tester, () async {
      final ProfileStore opened = await seedMaintain(
        completedWorkout(await program()),
      );
      await opened.saveFlareFollowup(
        sessionId: sessionId,
        documentJson: flareEnvelope('same', 'pause_today', pauseReason),
        updatedAtMs: opened.clockMillis(),
      );
      return opened;
    });
    await pumpRouter(tester, store);
    await until(tester, find.text('HelpMeMove'));
    await until(
      tester,
      find.text('The saved check could not be read. It was cleared.'),
    );
    expect(find.text('Start workout'), findsNothing);
    expect(await io(tester, () => store.loadFlareFollowup(sessionId)), isNull);
  });

  testWidgets('a withheld flare query shows that nothing was saved', (
    tester,
  ) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seedMaintain(workout));
    await pumpRouter(tester, store, initialLocation: '/?flare=withheld');
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text('Check in on the last session'));
    expect(find.text('No change was saved.'), findsOneWidget);
    expect(find.text('Start workout'), findsNothing);
  });

  testWidgets('large text keeps the follow-up buttons on a phone surface', (
    tester,
  ) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/flare-followup',
      size: const Size(390, 844),
      textScale: 2,
    );
    await until(tester, find.text('Worse today'));
    await tester.scrollUntilVisible(
      find.text('Settled'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('About the same'), findsOneWidget);
    expect(find.text('Settled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide follow-up shows the three choices', (tester) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/flare-followup',
      size: const Size(840, 1200),
    );
    await until(tester, find.text('Worse today'));
    expect(find.text('About the same'), findsOneWidget);
    expect(find.text('Settled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('follow-up ignores the movement gate', (tester) async {
    final String workout = completedWorkout(await io(tester, program));
    final ProfileStore store = await io(tester, () => seed(workout: workout));
    await pumpRouter(
      tester,
      store,
      initialLocation: '/focus/flare-followup',
      movementGateOpen: false,
    );
    await until(tester, find.text('About the same'));
  });

  testWidgets('follow-up without a terminal returns home', (tester) async {
    final ProfileStore store = openStore();
    await io(tester, () async {
      await store.createProfile();
      await store.saveProgramRecord(await program());
    });
    await pumpRouter(tester, store, initialLocation: '/focus/flare-followup');
    await until(tester, find.text('HelpMeMove'));
    await until(tester, find.text('Start workout'));
    expect(find.text('Worse today'), findsNothing);
  });

  testWidgets('a missing profile on follow-up uses the unavailable screen', (
    tester,
  ) async {
    await pumpBare(tester, location: '/focus/flare-followup');
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Worse today'), findsNothing);
  });

  testWidgets('a blocked store on follow-up uses the unavailable screen', (
    tester,
  ) async {
    await pumpBare(
      tester,
      location: '/focus/flare-followup',
      storageBlocked: true,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settled'), findsNothing);
  });
}
