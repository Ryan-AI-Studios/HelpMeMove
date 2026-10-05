import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/assessment/assessment_document.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/intake/intake_draft.dart';
import 'package:helpmemove/main.dart';
import 'package:helpmemove/readiness/adaptation_document.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/encryption.dart';
import 'package:helpmemove/storage/profile_database.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/workout/session_document.dart';
import 'package:sqlite3/sqlite3.dart';

const String shoulderProgram =
    '{"record_version":1,"rule_id":"syn-program-core","rule_version":1,"safety_rule_id":"syn-safety-core","safety_rule_version":1,"session_minutes":15,"exercises":[{"exercise_id":"syn-shoulder-isometric","exercise_version":1,"regions":["shoulder"],"sets":1,"reps":1,"tempo":{"eccentric":2,"pause":1,"concentric":2},"reasons":[{"code":"region_match","region":"shoulder","equipment":null,"goal":null},{"code":"equipment_match","region":null,"equipment":"bodyweight","goal":null},{"code":"goal_match","region":null,"equipment":null,"goal":"control"},{"code":"screen_clear","region":null,"equipment":null,"goal":null},{"code":"fixture_defaults","region":null,"equipment":null,"goal":null}]}]}';

// These are the stored documents the existing readiness and flare screens require; the production intake test does not write this token and does not compose a plan.
const String permittingIntake =
    '{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}],"schema_ack":"yes","schema_green":"present"}';

const String permittingAssessment =
    '{"record_version":1,"instrument_id":"syn-assessment-core","stopped":false,"complete":true,"areas":[{"region":"shoulder","laterality":"left","rating":"limited"}],"note":""}';

const String loopSessionId = '11111111-1111-4111-8111-111111111111';

const String unmatchedSentence =
    'The synthetic rule did not match a triage row. Ordinary exercise generation stays off.';

const String blockedPlanSentence =
    'The synthetic rule is not allowing a starting plan.';

const String composeWithheldSentence =
    'The synthetic rule did not produce a starting plan. Nothing was saved.';

const String blockedCheckSentence =
    'The synthetic rule is not allowing a movement check.';

const String clearedWorkoutSentence =
    'The saved workout could not be read. It was cleared.';

const String clearedCheckSentence =
    'The saved check could not be read. It was cleared.';

const String stoppedNotice = 'The last session stopped. No change was saved.';

const String withheldNotice = 'No change was saved.';

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-loop');
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

  testWidgets(
    'production intake through Continue withholds a starting plan and saves no program row',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      await tester.runAsync(store.openActive);
      await pumpApp(tester, store, size: const Size(400, 1600));
      await until(tester, find.text('Describe a limit'));
      await tester.tap(find.text('Describe a limit'));
      await until(tester, find.text('I am not sure'));
      await tester.tap(find.text('I am not sure'));
      await tester.pump();
      await tapContinue(tester);
      expect(find.textContaining('syn-notice-1'), findsOneWidget);
      expect(find.textContaining('not a medical assessment'), findsOneWidget);
      await tapContinue(tester);
      await tester.ensureVisible(find.text('Control'));
      await tester.tap(find.text('Control'));
      await tester.pump();
      await tapContinue(tester);
      await tester.ensureVisible(find.text('Chair'));
      await tester.tap(find.text('Chair'));
      await tester.pump();
      await tapContinue(tester);
      await tester.ensureVisible(find.byKey(const Key('list-arm')));
      await tester.tap(find.byKey(const Key('list-arm')));
      await tester.pump();
      await tapContinue(tester);
      await tester.ensureVisible(find.byKey(const Key('intake-note')));
      await tester.enterText(
        find.byKey(const Key('intake-note')),
        'quiet note',
      );
      await tester.pump();
      await tapContinue(tester);
      await tester.ensureVisible(find.byType(Slider));
      final Slider slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(9);
      await tester.pump();
      expect(find.text('9 out of 10'), findsOneWidget);
      await tapContinue(tester);
      expect(
        find.text('The clinician question list is not available.'),
        findsOneWidget,
      );
      await tapContinue(tester);
      await until(tester, find.text(unmatchedSentence));
      expect(find.text('Check movement'), findsNothing);
      expect(find.text('Continue movement check'), findsNothing);
      final String? raw = await tester.runAsync<String?>(store.loadDraft);
      expect(raw, isNotNull);
      expect(raw!, contains('schema_ack'));
      expect(raw.contains('quiet note'), isTrue);
      expect(raw.contains('schema_${'green'}'), isFalse);
      expect(raw.contains('schema_red'), isFalse);
      expect(raw.contains('schema_yellow'), isFalse);
      expect(await tester.runAsync(store.loadProgramRecord), isNull);

      // Continue does not open the movement gate, so these routes stay blocked.
      final GoRouter router = GoRouter.of(
        tester.element(find.text(unmatchedSentence)),
      );
      router.go('/focus/program');
      await until(tester, find.text(blockedPlanSentence));
      expect(find.text(composeWithheldSentence), findsNothing);
      expect(await tester.runAsync(store.loadProgramRecord), isNull);
      router.go('/focus/assessment');
      await until(tester, find.text(blockedCheckSentence));
      expect(find.text('Start movement check'), findsNothing);

      final LocalIntakeDraft intake = LocalIntakeDraft.decode(raw);
      await tester.runAsync(
        () => store.saveAssessmentDraft(
          LocalAssessment(
            areas: <AssessmentArea>[
              for (final IntakeArea area in intake.areas)
                AssessmentArea(
                  region: area.region,
                  laterality: area.laterality,
                  rating: 'limited',
                ),
            ],
            stopped: false,
            complete: true,
          ).encode(),
        ),
      );
      await tester.pumpWidget(_OpenGateHost(store: store));
      await until(tester, find.text('Check starting plan'));
      expect(
        find.text('Saved on this device. No exercise program is created.'),
        findsOneWidget,
      );
      await tapLabel(tester, 'Check starting plan');
      await until(tester, find.text(composeWithheldSentence));
      expect(find.text('Your starting plan'), findsNothing);
      expect(await tester.runAsync(store.loadProgramRecord), isNull);
      final String? kept = await tester.runAsync<String?>(store.loadDraft);
      expect(kept, isNotNull);
      expect(kept!.contains('schema_${'green'}'), isFalse);
    },
  );

  testWidgets(
    'program before Continue shows the blocked sentence and does not write',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      await tester.runAsync(store.createProfile);
      await pumpApp(tester, store, initialLocation: '/focus/program');
      await until(tester, find.text(blockedPlanSentence));
      expect(find.text(composeWithheldSentence), findsNothing);
      expect(await tester.runAsync(store.loadProgramRecord), isNull);
    },
  );

  testWidgets(
    'a stored green-shoulder program completes a session and opens progress, privacy, and report',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      await tester.runAsync(() async {
        await store.createProfile();
        await store.saveProgramRecord(shoulderProgram);
        await store.saveDraft(permittingIntake);
        await store.saveAssessmentRecord(permittingAssessment);
      });
      await pumpApp(tester, store);
      await until(tester, find.text('Start workout'));
      await completeSession(tester);
      expect(find.text('Session saved'), findsOneWidget);
      await tapLabel(tester, 'Home');
      await until(tester, find.text('How are you feeling today?'));
      expect(find.text('Start workout'), findsNothing);
      await tapLabel(tester, 'How are you feeling today?');
      await until(tester, find.text('Low soreness'));
      await tapLabel(tester, 'Low soreness');
      await until(tester, find.text(maintainReason));
      await until(tester, find.text('Check in on the last session'));
      expect(find.text('Start workout'), findsNothing);
      expect(find.text(withheldNotice), findsNothing);
      final StoredTerminalWorkout? terminal = await tester
          .runAsync<StoredTerminalWorkout?>(store.loadNewestTerminalWorkout);
      expect(terminal, isNotNull);
      expect(LocalSession.decode(terminal!.documentJson).outcome, 'completed');
      expect(
        await tester.runAsync(
          () => store.loadAdaptationRecord(terminal.sessionId),
        ),
        contains('maintain'),
      );
      expect(await tester.runAsync(store.loadProgramRecord), shoulderProgram);
      await tapLabel(tester, 'Check in on the last session');
      await until(tester, find.text('Settled'));
      await tapLabel(tester, 'Settled');
      await until(tester, find.text('Start workout'));
      await tapLabel(tester, 'Back');
      await until(tester, find.text('HelpMeMove'));
      await until(tester, find.text('Start workout'));
      expect(find.text(withheldNotice), findsNothing);
      expect(
        await tester.runAsync(
          () => store.loadFlareFollowup(terminal.sessionId),
        ),
        contains('keep_program'),
      );

      await tapLabel(tester, 'See local progress');
      await until(tester, find.text('Completed sessions: 1'));
      await tapLabel(tester, 'Back');
      await until(tester, find.text('Privacy and appearance'));
      expect(find.text('Report a problem'), findsOneWidget);
      await tapLabel(tester, 'Privacy and appearance');
      await until(tester, find.text('This profile stays on this device.'));
      await tapLabel(tester, 'Back');
      await until(tester, find.text('Report a problem'));
      await tapLabel(tester, 'Report a problem');
      await until(tester, find.text('Nothing is sent off this device.'));
      await tapLabel(tester, 'App issue');
      await tapLabel(tester, 'Save');
      await until(tester, find.text('Saved on this device.'));
      expect(find.text('Program rule syn-program-core 1.'), findsOneWidget);
      expect(find.text('Safety rule syn-safety-core 1.'), findsOneWidget);
      expect(await tester.runAsync(store.loadProgramRecord), shoulderProgram);
    },
  );

  testWidgets(
    'a safety-stopped terminal shows the stopped notice and hides start, resume, and the readiness check',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      await tester.runAsync(() async {
        await store.createProfile();
        await store.saveProgramRecord(shoulderProgram);
      });
      await pumpApp(tester, store);
      await until(tester, find.text('Start workout'));
      await stopSession(tester);
      expect(find.text('Session stopped'), findsOneWidget);
      await tapLabel(tester, 'Home');
      await until(tester, find.text(stoppedNotice));
      expect(find.text('Start workout'), findsNothing);
      expect(find.text('Resume workout'), findsNothing);
      expect(find.text('How are you feeling today?'), findsNothing);
      final StoredTerminalWorkout? terminal = await tester
          .runAsync<StoredTerminalWorkout?>(store.loadNewestTerminalWorkout);
      expect(terminal, isNotNull);
      expect(
        LocalSession.decode(terminal!.documentJson).outcome,
        'safety_stopped',
      );
    },
  );

  testWidgets(
    'a decodable workout draft still offers Resume workout after the widget tree is replaced',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      final WorkoutView opened = openWorkout(
        programJson: shoulderProgram,
        monotonicMillis: 1000,
        sessionId: loopSessionId,
      );
      expect(opened.outcome, 'ready');
      final LocalSession session = LocalSession.decode(opened.documentJson);
      expect(session.sessionId, loopSessionId);
      await tester.runAsync(() async {
        await store.createProfile();
        await store.saveProgramRecord(shoulderProgram);
        await store.saveWorkoutDraft(opened.documentJson);
      });
      await pumpApp(tester, store);
      await until(tester, find.text('Resume workout'));
      expect(find.text('Start workout'), findsNothing);
      await tester.pumpWidget(HelpMeMoveApp(key: UniqueKey(), store: store));
      await until(tester, find.text('Resume workout'));
      expect(find.text('Start workout'), findsNothing);
    },
  );

  testWidgets(
    'high soreness on the production readiness screen hides start and the flare check',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      final String sessionId = await io(
        tester,
        () => seedCompletedProgram(store),
      );
      await pumpApp(tester, store);
      await until(tester, find.text('How are you feeling today?'));
      await tapLabel(tester, 'How are you feeling today?');
      await until(tester, find.text('High soreness'));
      await tapLabel(tester, 'High soreness');
      await until(tester, find.text(pauseReason));
      expect(find.text('Start workout'), findsNothing);
      expect(find.text('Check in on the last session'), findsNothing);
      expect(find.text('How are you feeling today?'), findsNothing);
      expect(
        await tester.runAsync(() => store.loadAdaptationRecord(sessionId)),
        contains('pause_today'),
      );
      expect(await tester.runAsync(store.loadProgramRecord), shoulderProgram);
    },
  );

  testWidgets(
    'flare pause and flare keep are tapped on the production flare screen',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      final String pausedSession = await io(
        tester,
        () => seedCompletedProgram(store),
      );
      await pumpApp(tester, store);
      await until(tester, find.text('How are you feeling today?'));
      await tapLabel(tester, 'How are you feeling today?');
      await until(tester, find.text('Low soreness'));
      await tapLabel(tester, 'Low soreness');
      await until(tester, find.text('Check in on the last session'));
      expect(find.text('Start workout'), findsNothing);
      await tapLabel(tester, 'Check in on the last session');
      await until(tester, find.text('Worse today'));
      await tapLabel(tester, 'Worse today');
      await until(tester, find.text(pauseReason));
      await tapLabel(tester, 'Back');
      await until(tester, find.text('HelpMeMove'));
      await until(tester, find.text('See local progress'));
      expect(find.text('Start workout'), findsNothing);
      expect(find.text(withheldNotice), findsNothing);
      expect(
        await tester.runAsync(() => store.loadFlareFollowup(pausedSession)),
        contains('pause_today'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      final String keptSession = await io(
        tester,
        () => seedCompletedProgram(store),
      );
      await pumpApp(tester, store);
      await until(tester, find.text('How are you feeling today?'));
      await tapLabel(tester, 'How are you feeling today?');
      await until(tester, find.text('Moderate soreness'));
      await tapLabel(tester, 'Moderate soreness');
      await until(tester, find.text('Check in on the last session'));
      await tapLabel(tester, 'Check in on the last session');
      await until(tester, find.text('Settled'));
      await tapLabel(tester, 'Settled');
      await until(tester, find.text('Start workout'));
      await tapLabel(tester, 'Back');
      await until(tester, find.text('HelpMeMove'));
      await until(tester, find.text('Start workout'));
      expect(find.text(withheldNotice), findsNothing);
      expect(
        await tester.runAsync(() => store.loadFlareFollowup(keptSession)),
        contains('keep_program'),
      );
    },
  );

  testWidgets(
    'a corrupt workout draft, an orphan adaptation pair, and a corrupt flare row are cleared',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      const String corruptSession = '{"clinical":true}';
      expect(
        () => LocalSession.decode(corruptSession),
        throwsA(isA<LocalSessionException>()),
      );
      await tester.runAsync(() async {
        await store.createProfile();
        await store.saveProgramRecord(shoulderProgram);
        await store.saveWorkoutDraft(corruptSession);
      });
      await pumpApp(tester, store);
      await until(tester, find.text(clearedWorkoutSentence));
      expect(find.text('Start workout'), findsOneWidget);
      expect(await tester.runAsync(store.loadWorkoutDraft), isNull);
      expect(await tester.runAsync(store.loadProgramRecord), shoulderProgram);

      await tester.pumpWidget(const SizedBox.shrink());
      final String orphanSession = await io(tester, () async {
        final String sessionId = await seedCompletedProgram(store);
        await store.saveAdaptationPair(
          sessionId: sessionId,
          readinessJson: readinessDocument(sessionId),
          adaptationJson: maintainDocument(sessionId),
          updatedAtMs: store.clockMillis(),
        );
        await deleteAdaptationRows(store);
        return sessionId;
      });
      expect(
        await tester.runAsync(() => store.loadReadinessRecord(orphanSession)),
        isNotNull,
      );
      expect(
        await tester.runAsync(() => store.loadAdaptationRecord(orphanSession)),
        isNull,
      );
      await pumpApp(tester, store);
      await until(tester, find.text(clearedCheckSentence));
      expect(find.text('How are you feeling today?'), findsOneWidget);
      expect(
        await tester.runAsync(() => store.loadReadinessRecord(orphanSession)),
        isNull,
      );
      expect(
        await tester.runAsync(() => store.loadAdaptationRecord(orphanSession)),
        isNull,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      const String corruptFlare = '{"record_version":1,"exercises":[42]}';
      expect(
        () => StoredFlareFollowup.decode(corruptFlare),
        throwsA(isA<AdaptationDocumentException>()),
      );
      final String flareSession = await io(tester, () async {
        final String sessionId = await seedCompletedProgram(store);
        await store.saveAdaptationPair(
          sessionId: sessionId,
          readinessJson: readinessDocument(sessionId),
          adaptationJson: maintainDocument(sessionId),
          updatedAtMs: store.clockMillis(),
        );
        await store.saveFlareFollowup(
          sessionId: sessionId,
          documentJson: corruptFlare,
          updatedAtMs: store.clockMillis(),
        );
        return sessionId;
      });
      await pumpApp(tester, store);
      await until(tester, find.text(clearedCheckSentence));
      expect(find.text('Check in on the last session'), findsOneWidget);
      expect(
        await tester.runAsync(() => store.loadFlareFollowup(flareSession)),
        isNull,
      );
      expect(
        await tester.runAsync(() => store.loadReadinessRecord(flareSession)),
        isNotNull,
      );
      expect(
        await tester.runAsync(() => store.loadAdaptationRecord(flareSession)),
        isNotNull,
      );
    },
  );

  testWidgets(
    'a second subject does not see the first subject program, session, or report',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      final String first = await io(tester, () async {
        final String subjectId = await store.createProfile();
        await store.saveProgramRecord(shoulderProgram);
        final String workout = completedWorkout(shoulderProgram);
        final LocalSession session = LocalSession.decode(workout);
        await store.saveWorkoutTerminal(
          sessionId: session.sessionId,
          documentJson: workout,
        );
        return subjectId;
      });
      final String reportId = await io(
        tester,
        () => store.saveProblemReport(category: 'app_issue', note: ''),
      );
      await tester.runAsync(store.createProfile);
      await pumpApp(tester, store);
      await until(tester, find.text('Describe a limit'));
      expect(find.text('Start workout'), findsNothing);
      expect(find.text('How are you feeling today?'), findsNothing);
      expect(find.text(stoppedNotice), findsNothing);
      GoRouter.of(tester.element(find.text('Describe a limit')))
          .go('/focus/report');
      await until(tester, find.text('Nothing is sent off this device.'));
      expect(find.textContaining(reportId), findsNothing);
      expect(await tester.runAsync(store.loadProgramRecord), isNull);
      expect(
        await tester.runAsync<StoredTerminalWorkout?>(
          store.loadNewestTerminalWorkout,
        ),
        isNull,
      );
      expect(
        await tester.runAsync<StoredProblemReport?>(
          () => store.loadProblemReport(reportId),
        ),
        isNull,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => store.switchTo(first));
      expect(await tester.runAsync(store.loadProgramRecord), shoulderProgram);
      final StoredTerminalWorkout? terminal = await tester
          .runAsync<StoredTerminalWorkout?>(store.loadNewestTerminalWorkout);
      expect(terminal, isNotNull);
      expect(LocalSession.decode(terminal!.documentJson).outcome, 'completed');
      final StoredProblemReport? report = await tester
          .runAsync<StoredProblemReport?>(
            () => store.loadProblemReport(reportId),
          );
      expect(report, isNotNull);
      expect(report!.programRuleId, 'syn-program-core');
      await pumpApp(tester, store);
      await until(tester, find.text('How are you feeling today?'));
      expect(find.text(stoppedNotice), findsNothing);
    },
  );

  testWidgets(
    'a null store and a blocked store hide the loop buttons and workout is unavailable',
    (WidgetTester tester) async {
      useView(tester);
      await tester.pumpWidget(const HelpMeMoveApp());
      await tester.pump();
      expect(find.text('Describe a limit'), findsNothing);
      expect(find.text('Start workout'), findsNothing);
      expect(find.text('See local progress'), findsNothing);
      expect(find.text('Privacy and appearance'), findsNothing);
      expect(find.text('Report a problem'), findsNothing);
      expect(find.text('Scaffold check'), findsOneWidget);
      GoRouter.of(tester.element(find.text('Scaffold check')))
          .go('/focus/workout');
      await until(tester, find.text('Home'));
      expect(find.text('Start'), findsNothing);
      expect(find.text("I'm ready"), findsNothing);
      expect(find.text('Start workout'), findsNothing);
      expect(find.text('Rep 1 of 1'), findsNothing);

      final ProfileStore store = openStore();
      await tester.runAsync(store.createProfile);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: buildHelpMeMoveRouter(
            store: store,
            storageBlocked: true,
          ),
        ),
      );
      await tester.pump();
      await until(tester, find.text('Scaffold check'));
      expect(find.text('Describe a limit'), findsNothing);
      expect(find.text('Start workout'), findsNothing);
      expect(find.text('See local progress'), findsNothing);
      expect(find.text('Privacy and appearance'), findsNothing);
      expect(find.text('Report a problem'), findsNothing);
      GoRouter.of(tester.element(find.text('Scaffold check')))
          .go('/focus/workout');
      await until(tester, find.text('Home'));
      expect(find.text('Start'), findsNothing);
      expect(find.text("I'm ready"), findsNothing);
      expect(find.text('Start workout'), findsNothing);
      expect(await tester.runAsync(store.createdAtMs), isNotNull);
    },
  );

  test('schemaVersion is 9', () async {
    final ProfileStore store = openStore();
    await store.createProfile();
    final String subjectId = (await store.keys.read(activeProfileItem))!;
    final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
    final File file = store.openDatabaseFile!;
    await store.close();
    final Database raw = sqlite3.open(file.path);
    applyEncryptionSetup(raw, keyHex);
    expect(raw.select('PRAGMA user_version').first.columnAt(0), 9);
    raw.close();
    final ProfileDatabase database = ProfileDatabase.open(
      file: file,
      keyHex: keyHex,
    );
    expect(database.schemaVersion, 9);
    await database.close();
  });

  testWidgets(
    'the stored-program Home action is hit-testable at 390 by 844 scale 2 and at width 840',
    (WidgetTester tester) async {
      final ProfileStore store = openStore();
      await tester.runAsync(() async {
        await store.createProfile();
        await store.saveProgramRecord(shoulderProgram);
      });
      useView(tester, textScale: 2);
      await tester.pumpWidget(HelpMeMoveApp(key: UniqueKey(), store: store));
      await until(tester, find.text('Start workout'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      await tester.scrollUntilVisible(
        find.text('Start workout'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Start workout').hitTestable(), findsOneWidget);

      tester.view.physicalSize = const Size(840, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      await tester.pumpWidget(HelpMeMoveApp(key: UniqueKey(), store: store));
      await until(tester, find.text('Start workout'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      await tester.scrollUntilVisible(
        find.text('Start workout'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Start workout').hitTestable(), findsOneWidget);
    },
  );
}

void useView(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> pumpApp(
  WidgetTester tester,
  ProfileStore store, {
  String initialLocation = '/',
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  useView(tester, size: size, textScale: textScale);
  await tester.pumpWidget(
    HelpMeMoveApp(
      key: UniqueKey(),
      initialLocation: initialLocation,
      store: store,
    ),
  );
  await tester.pump();
}

Future<T> io<T extends Object>(
  WidgetTester tester,
  Future<T> Function() body,
) async {
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

Future<void> tapLabel(WidgetTester tester, String label) async {
  final Finder finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> tapContinue(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Continue'));
  await tester.tap(find.text('Continue'));
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
  }
}

Future<void> completeSession(WidgetTester tester) async {
  await tapLabel(tester, 'Start workout');
  await until(tester, find.text('Start'));
  await tapLabel(tester, 'Start');
  await until(tester, find.text("I'm ready"));
  await tapLabel(tester, "I'm ready");
  await until(tester, find.text('Rep 1 of 1'));
  await tapLabel(tester, 'Rep 1 of 1');
  await until(tester, find.text('Session saved'));
}

Future<void> stopSession(WidgetTester tester) async {
  await tapLabel(tester, 'Start workout');
  await until(tester, find.text('Start'));
  await tapLabel(tester, 'Start');
  await until(tester, find.text("I'm ready"));
  await tapLabel(tester, "I'm ready");
  await until(tester, find.text('This hurts'));
  await tapLabel(tester, 'This hurts');
  await until(tester, find.text('End session'));
  await tapLabel(tester, 'End session');
  await until(tester, find.text('Session stopped'));
}

String completedWorkout(String programJson) {
  WorkoutView view = openWorkout(
    programJson: programJson,
    monotonicMillis: 1000,
    sessionId: loopSessionId,
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

  step('{"name":"ready"}', 1000);
  step('{"name":"ready"}', 1100);
  return step('{"name":"complete_rep"}', 1200);
}

Future<String> seedCompletedProgram(ProfileStore store) async {
  await store.createProfile();
  await store.saveProgramRecord(shoulderProgram);
  await store.saveDraft(permittingIntake);
  await store.saveAssessmentRecord(permittingAssessment);
  final String workout = completedWorkout(shoulderProgram);
  final LocalSession session = LocalSession.decode(workout);
  await store.saveWorkoutTerminal(
    sessionId: session.sessionId,
    documentJson: workout,
  );
  return session.sessionId;
}

String readinessDocument(String sessionId) {
  return jsonEncode(<String, Object>{
    'record_version': 1,
    'recorded_at_ms': 1000,
    'rule_id': 'syn-adaptation-core',
    'rule_version': 1,
    'session_id': sessionId,
    'soreness': 'low',
  });
}

String maintainDocument(String sessionId) {
  return jsonEncode(<String, Object?>{
    'action': 'maintain',
    'exercises': <Object>[],
    'reason': maintainReason,
    'record_version': 1,
    'reported_pain': null,
    'rule_id': 'syn-adaptation-core',
    'rule_version': 1,
    'session_id': sessionId,
  });
}

class _OpenGateHost extends StatefulWidget {
  const _OpenGateHost({required this.store});

  final ProfileStore store;

  @override
  State<_OpenGateHost> createState() => _OpenGateHostState();
}

class _OpenGateHostState extends State<_OpenGateHost> {
  late final GoRouter _router = buildHelpMeMoveRouter(
    store: widget.store,
    movementGateOpen: true,
    initialLocation: '/focus/assessment?step=summary',
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      highContrastTheme: AppTheme.highContrastLight(),
      highContrastDarkTheme: AppTheme.highContrastDark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

Future<void> deleteAdaptationRows(ProfileStore store) async {
  final String subjectId = (await store.keys.read(activeProfileItem))!;
  final String keyHex = (await store.keys.read(profileKeyItem(subjectId)))!;
  final File file = store.openDatabaseFile!;
  await store.close();
  final Database raw = sqlite3.open(file.path);
  applyEncryptionSetup(raw, keyHex);
  raw.execute('DELETE FROM adaptation_records');
  raw.close();
  await store.reopenActive();
}
