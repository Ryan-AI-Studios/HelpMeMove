import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/assessment/assessment_document.dart';
import 'package:helpmemove/assessment/assessment_flow.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/components/pain_slider.dart';
import 'package:helpmemove/intake/intake_draft.dart';
import 'package:helpmemove/intake/intake_outcome.dart';
import 'package:helpmemove/main.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';

const SafetyView _green = SafetyView(
  code: 'green',
  level: 'green',
  escalation: 'none',
  permitsOrdinaryGeneration: true,
  emergencyDisplay: '',
  emergencyCode: 'region',
);

const SafetyView _yellow = SafetyView(
  code: 'yellow',
  level: 'yellow',
  escalation: 'none',
  permitsOrdinaryGeneration: true,
  emergencyDisplay: '',
  emergencyCode: 'region',
);

const SafetyView _orange = SafetyView(
  code: 'orange',
  level: 'orange',
  escalation: 'evaluation',
  permitsOrdinaryGeneration: true,
  emergencyDisplay: '',
  emergencyCode: 'region',
);

const SafetyView _red = SafetyView(
  code: 'red',
  level: 'red',
  escalation: 'emergency',
  permitsOrdinaryGeneration: false,
  emergencyDisplay: '',
  emergencyCode: 'region',
);

const SafetyView _unmatched = SafetyView(
  code: 'unmatched',
  level: '',
  escalation: '',
  permitsOrdinaryGeneration: false,
  emergencyDisplay: '',
  emergencyCode: 'region',
);

const SafetyView _ineligible = SafetyView(
  code: 'ineligible',
  level: '',
  escalation: 'none',
  permitsOrdinaryGeneration: false,
  emergencyDisplay: '',
  emergencyCode: 'region',
);

void main() {
  late Directory temp;
  ProfileStore? live;

  setUpAll(() async {
    await RustLib.init();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('helpmemove-assessment-ui');
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

  Future<ProfileStore> pumpCheck(
    WidgetTester tester, {
    required SafetyView view,
    String location = '/focus/intake?step=check',
    LocalIntakeDraft? intake,
    String? assessmentRaw,
  }) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      if (intake != null) {
        await store.saveDraft(intake.encode());
      }
      if (assessmentRaw != null) {
        await store.saveAssessmentDraft(assessmentRaw);
      }
    });
    await tester.pumpWidget(
      HelpMeMoveApp(
        initialLocation: location,
        store: store,
        previewSafetyView: view,
      ),
    );
    return store;
  }

  testWidgets('generation off keeps start over and hides the movement button', (
    tester,
  ) async {
    await _expectMovement(tester, _unmatched, showsButton: false);
    await _expectMovement(tester, _red, showsButton: false);
    await _expectMovement(tester, _ineligible, showsButton: false);
  });

  testWidgets('permitting views show check or continue movement', (
    tester,
  ) async {
    await _expectMovement(tester, _green, showsButton: true);
    await _expectMovement(tester, _yellow, showsButton: true);
    await _expectMovement(tester, _orange, showsButton: true);
    await _expectMovement(tester, _green, showsButton: true, hasDraft: true);
    await _expectMovement(tester, _yellow, showsButton: true, hasDraft: true);
    await _expectMovement(tester, _orange, showsButton: true, hasDraft: true);
  });

  testWidgets('pressing check movement opens the intro', (tester) async {
    await pumpCheck(tester, view: _green);
    await _until(tester, find.text('Check movement'));
    await tester.tap(find.text('Check movement'));
    await _until(tester, find.text("Let's see how you move"));
    expect(find.textContaining('syn-assessment-core'), findsOneWidget);
    expect(find.textContaining('not a medical assessment'), findsOneWidget);
    expect(find.textContaining('does not measure angles'), findsOneWidget);
    expect(find.text('Start movement check'), findsOneWidget);
    expect(find.textContaining('Camera'), findsNothing);
    expect(find.textContaining('camera'), findsNothing);
    expect(find.byType(PainSlider), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.text('The synthetic rule is not allowing a movement check.'),
      findsNothing,
    );
  });

  testWidgets('an existing draft continues into the intro', (tester) async {
    await pumpCheck(
      tester,
      view: _yellow,
      assessmentRaw: LocalAssessment().encode(),
    );
    await _until(tester, find.text('Continue movement check'));
    await tester.tap(find.text('Continue movement check'));
    await _until(tester, find.text('Start movement check'));
    expect(
      find.text('The synthetic rule is not allowing a movement check.'),
      findsNothing,
    );
  });

  testWidgets('a direct route with the gate false shows the blocked sentence', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() => store.openActive());
    await tester.pumpWidget(
      HelpMeMoveApp(
        initialLocation: '/focus/assessment?step=area',
        store: store,
      ),
    );
    await tester.pump();
    expect(
      find.text('The synthetic rule is not allowing a movement check.'),
      findsOneWidget,
    );
    expect(find.text('Start movement check'), findsNothing);
    expect(find.text('Normal'), findsNothing);
    expect(find.text('Skip'), findsNothing);
    expect(await tester.runAsync(() => store.loadAssessmentDraft()), isNull);
    await tester.tap(find.text('Home'));
    await _until(tester, find.text('Scaffold check'));
  });

  testWidgets('area step offers five words and no degree', (tester) async {
    final ProfileStore store = await _openArea(tester, pumpCheck, const [
      IntakeArea(region: 'shoulder', laterality: 'left'),
    ]);
    await _until(tester, find.text('Shoulder Left'));
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Limited'), findsOneWidget);
    expect(find.text('Painful'), findsOneWidget);
    expect(find.text('Very painful'), findsOneWidget);
    expect(find.text('Unable'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Normal')).dy,
      lessThan(tester.getTopLeft(find.text('Limited')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Limited')).dy,
      lessThan(tester.getTopLeft(find.text('Painful')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Painful')).dy,
      lessThan(tester.getTopLeft(find.text('Very painful')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Very painful')).dy,
      lessThan(tester.getTopLeft(find.text('Unable')).dy),
    );
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.byType(PainSlider), findsNothing);
    expect(find.textContaining('quiet note'), findsNothing);
    expect(find.textContaining('out of 10'), findsNothing);
    _expectNoMeasurement(tester);
    expect(store.openDatabaseFile, isNotNull);
  });

  testWidgets('large text can scroll the area primary into reach', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _openArea(tester, pumpCheck, const [
      IntakeArea(region: 'shoulder', laterality: 'left'),
    ]);
    await _until(tester, find.text('Shoulder Left'));
    await tester.tap(find.text('Normal'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Continue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Continue').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet width shows five choices without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(840, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openArea(tester, pumpCheck, const [
      IntakeArea(region: 'head_neck', laterality: 'right'),
    ]);
    await _until(tester, find.text('Head and neck Right'));
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Limited'), findsOneWidget);
    expect(find.text('Painful'), findsOneWidget);
    expect(find.text('Very painful'), findsOneWidget);
    expect(find.text('Unable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stop keeps the chosen word and leaves the check incomplete', (
    tester,
  ) async {
    final ProfileStore store = await _openArea(tester, pumpCheck, const [
      IntakeArea(region: 'shoulder', laterality: 'left'),
    ]);
    await _until(tester, find.text('Shoulder Left'));
    await tester.tap(find.text('Painful'));
    await tester.pump();
    await tester.ensureVisible(find.text('Stop'));
    await tester.tap(find.text('Stop'));
    await _until(
      tester,
      find.text('This check is incomplete. No exercise program is created.'),
    );
    expect(find.text('Painful'), findsOneWidget);
    expect(find.text('Skipped'), findsNothing);
    expect(
      find.text('Saved on this device. No exercise program is created.'),
      findsNothing,
    );
    expect(find.text('BUILD MY PLAN'), findsNothing);
    _expectNoMeasurement(tester);
    final String? raw = await tester.runAsync<String?>(
      () => store.loadAssessmentDraft(),
    );
    expect(raw, isNotNull);
    expect(raw!, contains('"stopped":true'));
    expect(raw.contains('"complete":false'), isTrue);
    expect(raw.contains('"rating":"painful"'), isTrue);
    expect(raw.contains('quiet note'), isFalse);
    expect(
      await tester.runAsync(() => store.loadDraft()),
      contains('quiet note'),
    );
  });

  testWidgets('skip stores null and leaves the check incomplete', (
    tester,
  ) async {
    final ProfileStore store = await _openArea(tester, pumpCheck, const [
      IntakeArea(region: 'shoulder', laterality: 'left'),
    ]);
    await _until(tester, find.text('Shoulder Left'));
    await tester.ensureVisible(find.text('Skip'));
    await tester.tap(find.text('Skip'));
    await _until(tester, find.text('Skipped'));
    expect(
      find.text('This check is incomplete. No exercise program is created.'),
      findsOneWidget,
    );
    expect(find.text('BUILD MY PLAN'), findsNothing);
    _expectNoMeasurement(tester);
    final String? raw = await tester.runAsync<String?>(
      () => store.loadAssessmentDraft(),
    );
    expect(raw, isNotNull);
    expect(raw!, contains('"rating":null'));
    expect(raw.contains('"stopped":false'), isTrue);
    expect(raw.contains('"complete":false'), isTrue);
  });

  testWidgets('ratings follow vocabulary order and a full set can complete', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProfileStore store = await _openArea(tester, pumpCheck, const [
      IntakeArea(region: 'foot', laterality: 'bilateral'),
      IntakeArea(region: 'arm', laterality: 'left'),
    ]);
    await _until(tester, find.text('Arm Left'));
    expect(find.text('Foot Both'), findsNothing);
    await tester.tap(find.text('Normal'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Continue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continue'));
    await _until(tester, find.text('Foot Both'));
    await tester.tap(find.text('Unable'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Continue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continue'));
    await _until(
      tester,
      find.text('Saved on this device. No exercise program is created.'),
    );
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Unable'), findsOneWidget);
    expect(find.text('BUILD MY PLAN'), findsNothing);
    expect(find.text('Arm Left'), findsOneWidget);
    expect(find.text('Foot Both'), findsOneWidget);
    _expectNoMeasurement(tester);
    final String? raw = await tester.runAsync<String?>(
      () => store.loadAssessmentDraft(),
    );
    expect(raw, isNotNull);
    expect(raw!.indexOf('arm'), lessThan(raw.indexOf('foot')));
    expect(raw.contains('"complete":true'), isTrue);
    expect(raw.contains('"stopped":false'), isTrue);
    expect(raw.contains('quiet note'), isFalse);
    await tester.scrollUntilVisible(
      find.text('Done'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Done'));
    await _until(tester, find.text('Scaffold check'));
    expect(await tester.runAsync(() => store.loadAssessmentDraft()), isNull);
    final String? record = await tester.runAsync<String?>(
      () => store.loadAssessmentRecord(),
    );
    expect(record, raw);
    expect(
      await tester.runAsync(() => store.loadDraft()),
      contains('quiet note'),
    );
  });

  testWidgets('an unreadable draft is deleted only by start over', (
    tester,
  ) async {
    final ProfileStore store = await pumpCheck(
      tester,
      view: _green,
      intake: _intake(const [
        IntakeArea(region: 'shoulder', laterality: 'left'),
      ]),
      assessmentRaw: '{',
    );
    await _until(tester, find.text('Continue movement check'));
    await tester.tap(find.text('Continue movement check'));
    await _until(
      tester,
      find.text('The saved movement check could not be opened.'),
    );
    expect(find.text('Start movement check'), findsNothing);
    expect(find.text('{'), findsNothing);
    expect(await tester.runAsync(() => store.loadAssessmentDraft()), '{');
    await tester.tap(find.text('Start over'));
    await _until(tester, find.text('Start movement check'));
    expect(
      find.text('The saved movement check could not be opened.'),
      findsNothing,
    );
    expect(await tester.runAsync(() => store.loadAssessmentDraft()), isNull);
    expect(
      await tester.runAsync(() => store.loadDraft()),
      contains('shoulder'),
    );
    expect(await tester.runAsync(() => store.loadAssessmentRecord()), isNull);
  });

  testWidgets('a missing intake writes nothing', (tester) async {
    final ProfileStore store = await pumpCheck(tester, view: _green);
    await _until(tester, find.text('Check movement'));
    await tester.tap(find.text('Check movement'));
    await _until(tester, find.text('Start movement check'));
    await tester.tap(find.text('Start movement check'));
    await _until(
      tester,
      find.text('The saved intake could not be used for this check.'),
    );
    expect(find.text('Normal'), findsNothing);
    expect(find.text('Skip'), findsNothing);
    expect(await tester.runAsync(() => store.loadAssessmentDraft()), isNull);
    expect(await tester.runAsync(() => store.loadAssessmentRecord()), isNull);
  });

  testWidgets('start over deletes the assessment draft and keeps intake', (
    tester,
  ) async {
    final ProfileStore store = await _openArea(tester, pumpCheck, const [
      IntakeArea(region: 'shoulder', laterality: 'left'),
    ]);
    await _until(tester, find.text('Shoulder Left'));
    expect(await tester.runAsync(() => store.loadAssessmentDraft()), isNotNull);
    await tester.ensureVisible(find.text('Start over'));
    await tester.tap(find.text('Start over'));
    await _until(tester, find.text('Start movement check'));
    expect(await tester.runAsync(() => store.loadAssessmentDraft()), isNull);
    expect(
      await tester.runAsync(() => store.loadDraft()),
      contains('shoulder'),
    );
    expect(await tester.runAsync(() => store.loadAssessmentRecord()), isNull);
  });

  testWidgets('a forged complete flag stays incomplete on the summary', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(
        _intake(const [IntakeArea(region: 'shoulder', laterality: 'left')])
            .encode(),
      );
      await store.saveAssessmentDraft(LocalAssessment(complete: true).encode());
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
    expect(
      find.text('Saved on this device. No exercise program is created.'),
      findsNothing,
    );
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('unusable intake on the summary writes no record', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    final String forged = LocalAssessment(complete: true).encode();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveAssessmentDraft(forged);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AssessmentFlow(store: store, initialStep: 'summary'),
      ),
    );
    await _until(
      tester,
      find.text('The saved intake could not be used for this check.'),
    );
    expect(find.text('Done'), findsNothing);
    expect(
      find.text('Saved on this device. No exercise program is created.'),
      findsNothing,
    );
    expect(await tester.runAsync(() => store.loadAssessmentDraft()), forged);
    expect(await tester.runAsync(() => store.loadAssessmentRecord()), isNull);
  });

  testWidgets('a storage read failure does not replace the assessment draft', (
    tester,
  ) async {
    final _FailingReadStore store = _FailingReadStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(11),
      excludeFromBackup: (String path) async {},
    );
    live = store;
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(
        _intake(const [IntakeArea(region: 'shoulder', laterality: 'left')])
            .encode(),
      );
      await store.saveAssessmentDraft('kept-marker');
      store.assessmentSaves = 0;
      store.failRead = true;
    });
    await tester.pumpWidget(
      HelpMeMoveApp(
        initialLocation: '/focus/intake?step=check',
        store: store,
        previewSafetyView: _green,
      ),
    );
    await _until(tester, find.text('Check movement'));
    await tester.tap(find.text('Check movement'));
    await _until(tester, find.text('Storage is unavailable'));
    expect(
      find.text(
        'HelpMeMove could not open local storage on this device. Nothing was saved.',
      ),
      findsOneWidget,
    );
    expect(find.text('Start movement check'), findsNothing);
    expect(store.assessmentSaves, 0);
    store.failRead = false;
    expect(
      await tester.runAsync(() => store.loadAssessmentDraft()),
      'kept-marker',
    );
  });
}

class _FailingReadStore extends ProfileStore {
  _FailingReadStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  int assessmentSaves = 0;
  bool failRead = false;

  @override
  Future<String?> loadAssessmentDraft() async {
    if (failRead) {
      throw const StorageIoException('read');
    }
    return super.loadAssessmentDraft();
  }

  @override
  Future<void> saveAssessmentDraft(String documentJson) async {
    assessmentSaves += 1;
    await super.saveAssessmentDraft(documentJson);
  }
}

LocalIntakeDraft _intake(List<IntakeArea> areas) {
  return LocalIntakeDraft(
    intent: 'fitness',
    noticeId: 'syn-notice-1',
    schemaAck: 'yes',
    goals: <String>['mobility'],
    equipment: <String>['chair'],
    areas: areas,
    note: 'quiet note',
    severity: 7,
    step: 'check',
  );
}

Future<ProfileStore> _openArea(
  WidgetTester tester,
  Future<ProfileStore> Function(
    WidgetTester tester, {
    required SafetyView view,
    String location,
    LocalIntakeDraft? intake,
    String? assessmentRaw,
  })
  pumpCheck,
  List<IntakeArea> areas,
) async {
  final ProfileStore store = await pumpCheck(
    tester,
    view: _green,
    intake: _intake(areas),
  );
  await _until(tester, find.text('Check movement'));
  await tester.tap(find.text('Check movement'));
  await _until(tester, find.text('Start movement check'));
  await tester.tap(find.text('Start movement check'));
  return store;
}

void _expectNoMeasurement(WidgetTester tester) {
  expect(find.textContaining('°'), findsNothing);
  expect(find.textContaining('131'), findsNothing);
  expect(find.byType(PainSlider), findsNothing);
}

Future<void> _expectMovement(
  WidgetTester tester,
  SafetyView view, {
  required bool showsButton,
  bool hasDraft = false,
}) async {
  var pressed = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: IntakeOutcome(
          view: view,
          onStartOver: () {},
          onContinue: () {
            pressed = true;
          },
          hasAssessmentDraft: hasDraft,
        ),
      ),
    ),
  );
  expect(find.text('Start over'), findsOneWidget);
  final String label = hasDraft ? 'Continue movement check' : 'Check movement';
  if (showsButton) {
    expect(find.text(label), findsOneWidget);
    await tester.tap(find.text(label));
    await tester.pump();
    expect(pressed, isTrue);
  } else {
    expect(find.text('Check movement'), findsNothing);
    expect(find.text('Continue movement check'), findsNothing);
    expect(pressed, isFalse);
  }
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
