import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/assessment/assessment_document.dart';
import 'package:helpmemove/assessment/assessment_flow.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/intake/intake_draft.dart';
import 'package:helpmemove/main.dart';
import 'package:helpmemove/program/program_document.dart';
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
    temp = Directory.systemTemp.createTempSync('helpmemove-program-ui');
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

  test('token labels match the assessment words', () {
    expect(programTokenLabel('head_neck'), 'Head and neck');
    expect(programTokenLabel('shoulder'), 'Shoulder');
    expect(programTokenLabel('resistance_band'), 'Resistance band');
    expect(programTokenLabel('bodyweight'), 'Bodyweight');
    expect(programTokenLabel('control'), 'Control');
  });

  test('program document rejects an extra key without echoing it', () {
    const String raw =
        '{"record_version":1,"rule_id":"syn-program-core","rule_version":1,"safety_rule_id":"syn-safety-core","safety_rule_version":1,"session_minutes":15,"exercises":[],"clinical":true}';
    expect(
      () => LocalProgram.decode(raw),
      throwsA(
        isA<LocalProgramException>().having(
          (LocalProgramException error) => error.toString(),
          'toString',
          isNot(contains('clinical')),
        ),
      ),
    );
  });

  test('the renderer golden decodes as the green shoulder plan', () {
    final String raw = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final LocalProgram program = LocalProgram.decode(raw);
    expect(program.exercises.single.sets, 1);
    expect(program.exercises.single.reps, 1);
    expect(programReasonSentences(program.exercises.single), <String>[
      'Included because the saved check lists Shoulder.',
      'Included because the saved equipment includes Bodyweight.',
      'Included because the saved goal includes Control.',
      'The synthetic rule did not reject this exercise.',
      'The counts are the synthetic fixture defaults, not a prescription.',
    ]);
  });

  testWidgets('summary incomplete or gate closed hides the plan button', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(_intake().encode());
      await store.saveAssessmentDraft(
        LocalAssessment(
          areas: const <AssessmentArea>[
            AssessmentArea(
              region: 'shoulder',
              laterality: 'left',
              rating: null,
            ),
          ],
        ).encode(),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssessmentFlow(store: store, initialStep: 'summary'),
      ),
    );
    await _until(
      tester,
      find.text('This check is incomplete. No exercise program is created.'),
    );
    expect(find.text('Check starting plan'), findsNothing);

    await tester.pumpWidget(
      _Host(initialLocation: '/focus/assessment?step=summary', store: store),
    );
    await tester.pump();
    expect(
      find.text('The synthetic rule is not allowing a movement check.'),
      findsOneWidget,
    );
    expect(find.text('Check starting plan'), findsNothing);
    expect(
      find.text('This check is incomplete. No exercise program is created.'),
      findsNothing,
    );
  });

  testWidgets('a complete open gate opens the starting plan route', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(840, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(_intake().encode());
      await store.saveAssessmentDraft(
        LocalAssessment(
          areas: const <AssessmentArea>[
            AssessmentArea(
              region: 'shoulder',
              laterality: 'left',
              rating: 'limited',
            ),
          ],
          complete: true,
        ).encode(),
      );
    });
    await tester.pumpWidget(
      _Host(
        initialLocation: '/focus/assessment?step=summary',
        store: store,
        movementGateOpen: true,
      ),
    );
    await _until(tester, find.text('Check starting plan'));
    expect(
      find.text('Saved on this device. No exercise program is created.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Check starting plan'));
    await _until(
      tester,
      find.text(
        'The synthetic rule did not produce a starting plan. Nothing was saved.',
      ),
    );
    expect(find.text('Check starting plan'), findsNothing);
    final String? record = await tester.runAsync<String?>(
      () => store.loadAssessmentRecord(),
    );
    final LocalAssessment saved = LocalAssessment.decode(record!);
    expect(saved.complete, isTrue);
    expect(saved.areas.single.region, 'shoulder');
    expect(saved.areas.single.rating, 'limited');
    expect(await tester.runAsync(() => store.loadAssessmentDraft()), isNotNull);
    expect(await tester.runAsync(() => store.loadProgramRecord()), isNull);
  });

  testWidgets('a closed program route does not compose or write', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() => store.openActive());
    await tester.pumpWidget(
      _Host(initialLocation: '/focus/program', store: store),
    );
    await tester.pump();
    expect(
      find.text('The synthetic rule is not allowing a starting plan.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The synthetic rule did not produce a starting plan. Nothing was saved.',
      ),
      findsNothing,
    );
    expect(await tester.runAsync(() => store.loadProgramRecord()), isNull);
  });

  testWidgets('an open program route withholds and writes nothing', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(_intake().encode());
      await store.saveAssessmentRecord(
        LocalAssessment(
          areas: const <AssessmentArea>[
            AssessmentArea(
              region: 'shoulder',
              laterality: 'left',
              rating: 'limited',
            ),
          ],
          complete: true,
        ).encode(),
      );
    });
    await tester.pumpWidget(
      _Host(
        initialLocation: '/focus/program',
        store: store,
        movementGateOpen: true,
      ),
    );
    await _until(
      tester,
      find.text(
        'The synthetic rule did not produce a starting plan. Nothing was saved.',
      ),
    );
    expect(find.text('Your starting plan'), findsNothing);
    expect(await tester.runAsync(() => store.loadProgramRecord()), isNull);
  });

  testWidgets('a withheld program route keeps an existing program row', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    const String existing =
        '{"record_version":1,"rule_id":"syn-program-core","kept":true}';
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(_intake().encode());
      await store.saveAssessmentRecord(
        LocalAssessment(
          areas: const <AssessmentArea>[
            AssessmentArea(
              region: 'shoulder',
              laterality: 'left',
              rating: 'limited',
            ),
          ],
          complete: true,
        ).encode(),
      );
      await store.saveProgramRecord(existing);
    });
    await tester.pumpWidget(
      _Host(
        initialLocation: '/focus/program',
        store: store,
        movementGateOpen: true,
      ),
    );
    await _until(
      tester,
      find.text(
        'The synthetic rule did not produce a starting plan. Nothing was saved.',
      ),
    );
    expect(await tester.runAsync(() => store.loadProgramRecord()), existing);
  });

  testWidgets('an open program route without a profile shows home only', (
    tester,
  ) async {
    final GoRouter router = buildHelpMeMoveRouter(
      initialLocation: '/focus/program',
      movementGateOpen: true,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
    expect(
      find.text('The synthetic rule is not allowing a starting plan.'),
      findsNothing,
    );
    expect(
      find.text(
        'The synthetic rule did not produce a starting plan. Nothing was saved.',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'a throwing intake load opens storage failure and keeps the program row',
    (tester) async {
      final ProfileStore store = _ThrowingDraftStore(
        keys: MemoryProfileKeyStore(),
        supportDirectory: temp,
        clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
        random: Random(11),
        excludeFromBackup: (String path) async {},
      );
      live = store;
      const String existing =
          '{"record_version":1,"rule_id":"syn-program-core","kept":true}';
      await tester.runAsync(() async {
        await store.openActive();
        await store.saveProgramRecord(existing);
      });
      await tester.pumpWidget(
        _Host(
          initialLocation: '/focus/program',
          store: store,
          movementGateOpen: true,
        ),
      );
      await _until(tester, find.text('Storage is unavailable'));
      expect(
        find.text(
          'The synthetic rule did not produce a starting plan. Nothing was saved.',
        ),
        findsNothing,
      );
      expect(await tester.runAsync(() => store.loadProgramRecord()), existing);
    },
  );

  testWidgets('a preview plan shows the fixture notice and reasons', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() => store.openActive());
    await tester.pumpWidget(
      _Host(
        initialLocation: '/focus/program',
        store: store,
        movementGateOpen: true,
        previewProgram: _preview(),
      ),
    );
    await _until(tester, find.text('Your starting plan'));
    expect(find.textContaining('syn-program-core'), findsOneWidget);
    expect(find.textContaining('not a medical program'), findsOneWidget);
    expect(find.text('About 15 minutes/session'), findsOneWidget);
    expect(find.text('Synthetic syn shoulder isometric'), findsOneWidget);
    expect(find.text('1 \u00D7 1'), findsOneWidget);
    expect(
      find.text('Included because the saved check lists Shoulder.'),
      findsOneWidget,
    );
    expect(
      find.text('Included because the saved equipment includes Bodyweight.'),
      findsOneWidget,
    );
    expect(
      find.text('Included because the saved goal includes Control.'),
      findsOneWidget,
    );
    expect(
      find.text('The synthetic rule did not reject this exercise.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The counts are the synthetic fixture defaults, not a prescription.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('°'), findsNothing);
    expect(find.textContaining('131'), findsNothing);
    expect(find.textContaining('4 days'), findsNothing);
    expect(find.text('START FIRST SESSION'), findsNothing);
    expect(await tester.runAsync(() => store.loadProgramRecord()), isNull);
  });

  testWidgets('the exercise sheet shows the fixture instructions', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() => store.openActive());
    await tester.pumpWidget(
      _Host(
        initialLocation: '/focus/program',
        store: store,
        movementGateOpen: true,
        previewProgram: _preview(),
      ),
    );
    await _until(tester, find.text('Synthetic syn shoulder isometric'));
    await tester.tap(find.text('Synthetic syn shoulder isometric'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Synthetic fixture. Not an exercise prescription.'),
      findsOneWidget,
    );
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('START FIRST SESSION'), findsNothing);
  });

  testWidgets('large text can scroll the sheet close action into reach', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final ProfileStore store = openStore();
    await tester.runAsync(() => store.openActive());
    await tester.pumpWidget(
      _Host(
        initialLocation: '/focus/program',
        store: store,
        movementGateOpen: true,
        previewProgram: _preview(),
      ),
    );
    await _until(tester, find.text('Synthetic syn shoulder isometric'));
    await tester.tap(find.text('Synthetic syn shoulder isometric'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      find.text('Close'),
      200,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Close').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an 840-wide plan has no horizontal overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(840, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProfileStore store = openStore();
    await tester.runAsync(() => store.openActive());
    await tester.pumpWidget(
      _Host(
        initialLocation: '/focus/program',
        store: store,
        movementGateOpen: true,
        previewProgram: _preview(),
      ),
    );
    await _until(tester, find.text('Your starting plan'));
    expect(find.text('About 15 minutes/session'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home does not show a starting plan', (tester) async {
    await tester.pumpWidget(const HelpMeMoveApp());
    await tester.pump();
    expect(find.text('Your starting plan'), findsNothing);
    expect(find.text('Check starting plan'), findsNothing);
    expect(find.text('Scaffold check'), findsOneWidget);
  });
}

class _ThrowingDraftStore extends ProfileStore {
  _ThrowingDraftStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  @override
  Future<String?> loadDraft() async {
    throw const FileSystemException('intake read failed');
  }
}

class _Host extends StatefulWidget {
  const _Host({
    required this.initialLocation,
    required this.store,
    this.movementGateOpen = false,
    this.previewProgram,
  });

  final String initialLocation;
  final ProfileStore store;
  final bool movementGateOpen;
  final LocalProgram? previewProgram;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final GoRouter _router = buildHelpMeMoveRouter(
    initialLocation: widget.initialLocation,
    store: widget.store,
    movementGateOpen: widget.movementGateOpen,
    previewProgram: widget.previewProgram,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(theme: AppTheme.light(), routerConfig: _router);
  }
}

LocalIntakeDraft _intake() {
  return LocalIntakeDraft(
    goals: <String>['control'],
    equipment: <String>['bodyweight'],
    areas: const <IntakeArea>[
      IntakeArea(region: 'shoulder', laterality: 'left'),
    ],
    step: 'check',
  );
}

LocalProgram _preview() {
  return LocalProgram(
    recordVersion: 1,
    ruleId: 'syn-program-core',
    ruleVersion: 1,
    safetyRuleId: 'syn-safety-core',
    safetyRuleVersion: 1,
    sessionMinutes: 15,
    exercises: <ProgramExercise>[
      const ProgramExercise(
        exerciseId: 'syn-shoulder-isometric',
        exerciseVersion: 1,
        regions: <String>['shoulder'],
        sets: 1,
        reps: 1,
        tempo: ProgramTempo(eccentric: 2, pause: 1, concentric: 2),
        reasons: <ProgramReason>[
          ProgramReason(code: 'region_match', region: 'shoulder'),
          ProgramReason(code: 'equipment_match', equipment: 'bodyweight'),
          ProgramReason(code: 'goal_match', goal: 'control'),
          ProgramReason(code: 'screen_clear'),
          ProgramReason(code: 'fixture_defaults'),
        ],
      ),
    ],
  );
}

Future<void> _until(WidgetTester tester, Finder finder) async {
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
  fail('Timed out waiting for $finder');
}
