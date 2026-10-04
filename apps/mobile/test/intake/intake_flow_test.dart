import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/design/components/pain_slider.dart';
import 'package:helpmemove/design/router.dart';
import 'package:helpmemove/intake/intake_draft.dart';
import 'package:helpmemove/intake/intake_outcome.dart';
import 'package:helpmemove/main.dart';
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
    temp = Directory.systemTemp.createTempSync('helpmemove-intake-ui');
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

  Future<ProfileStore> pumpHome(WidgetTester tester) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() => store.openActive());
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await _until(tester, find.text('Describe a limit'));
    return store;
  }

  testWidgets('home starts intake and keeps the scaffold and bridge checks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpHome(tester);
    expect(find.text('Describe a limit'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Scaffold check'));
    await tester.pump();
    expect(find.text('Scaffold check completed'), findsOneWidget);

    await tester.tap(find.text('Bridge check'));
    await tester.pump();
    expect(find.text('Bridge check completed'), findsOneWidget);

    await tester.tap(find.text('Describe a limit'));
    await _until(tester, find.text('What brings you here'));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('What brings you here'), findsOneWidget);
  });

  testWidgets('key loss hides the intake button', (tester) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() => store.openActive());
    await tester.pumpWidget(
      HelpMeMoveApp(initialLocation: '/key-loss', store: store),
    );
    await tester.pump();
    expect(find.text('Describe a limit'), findsNothing);
    expect(find.text('Continue intake'), findsNothing);
  });

  testWidgets('home shows continue intake after a draft is saved', (
    tester,
  ) async {
    final ProfileStore store = await pumpHome(tester);
    await tester.tap(find.text('Describe a limit'));
    await _until(tester, find.text('Something hurts or feels limited'));
    await tester.tap(find.text('Something hurts or feels limited'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _until(tester, find.text('A note about this fixture'));
    await tester.tap(find.byTooltip('Back'));
    await _until(tester, find.text('What brings you here'));
    await tester.tap(find.byTooltip('Back'));
    await _until(tester, find.text('Continue intake'));
    expect(find.text('Describe a limit'), findsNothing);
    await tester.tap(find.text('Continue intake'));
    await _until(tester, find.text('A note about this fixture'));
    expect(find.text('A note about this fixture'), findsOneWidget);
    final String? raw = await tester.runAsync<String?>(() => store.loadDraft());
    expect(raw, isNotNull);
    expect(raw!, contains('"step":"notice"'));
  });

  testWidgets('start over clears the home button back to describe a limit', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(
        LocalIntakeDraft(
          intent: 'fitness',
          noticeId: 'syn-notice-1',
          schemaAck: 'yes',
          goals: <String>['mobility'],
          equipment: <String>['chair'],
          areas: const <IntakeArea>[
            IntakeArea(region: 'arm', laterality: 'bilateral'),
          ],
          step: 'check',
        ).encode(),
      );
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await _until(tester, find.text('Continue intake'));
    await tester.tap(find.text('Continue intake'));
    await _until(tester, find.textContaining('did not match a triage row'));
    expect(
      find.text('The clinician question list is not available.'),
      findsNothing,
    );
    await tester.tap(find.text('Start over'));
    await _until(tester, find.text('What brings you here'));
    await tester.tap(find.byTooltip('Back'));
    await _until(tester, find.text('Describe a limit'));
    expect(find.text('Continue intake'), findsNothing);
    final String? raw = await tester.runAsync<String?>(() => store.loadDraft());
    expect(raw, isNull);
  });

  testWidgets('key loss reset reveals the intake button', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProfileStore store = openStore();
    await tester.runAsync(() => store.openActive());
    await tester.pumpWidget(
      HelpMeMoveApp(
        initialLocation: '/key-loss',
        store: store,
        recovery: StorageRecovery(
          onRetry: () async => '/key-loss',
          onReset: () async => '/',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Describe a limit'), findsNothing);
    await tester.tap(find.text('Reset local data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Delete local data'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Scaffold check'), findsOneWidget);
    await _until(tester, find.text('Describe a limit'));
    expect(find.text('Continue intake'), findsNothing);
  });

  testWidgets('continue saves and back keeps the draft', (tester) async {
    final ProfileStore store = await pumpHome(tester);
    await tester.tap(find.text('Describe a limit'));
    await _until(tester, find.text('Something hurts or feels limited'));
    await tester.tap(find.text('Something hurts or feels limited'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _until(tester, find.text('A note about this fixture'));
    expect(find.text('A note about this fixture'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _until(tester, find.text('Something hurts or feels limited'));
    expect(find.text('Something hurts or feels limited'), findsOneWidget);
    final String? raw = await tester.runAsync<String?>(() => store.loadDraft());
    expect(raw, isNotNull);
    expect(raw!, contains('pain_or_limit'));
    expect(raw.contains('schema_red'), isFalse);
  });

  testWidgets('a saved draft resumes on its step', (tester) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(
        LocalIntakeDraft(
          intent: 'fitness',
          goals: <String>['mobility'],
          step: 'goals',
        ).encode(),
      );
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await _until(tester, find.text('Continue intake'));
    expect(find.text('Continue intake'), findsOneWidget);
    await tester.tap(find.text('Continue intake'));
    await _until(tester, find.text('Goals'));
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Mobility'), findsOneWidget);
  });

  testWidgets('resume on check classifies again and keeps the draft', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(
        LocalIntakeDraft(
          intent: 'not_sure',
          noticeId: 'syn-notice-1',
          schemaAck: 'yes',
          goals: <String>['control'],
          equipment: <String>['chair'],
          areas: const <IntakeArea>[
            IntakeArea(region: 'arm', laterality: 'bilateral'),
          ],
          note: 'quiet note',
          severity: 4,
          step: 'check',
        ).encode(),
      );
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await _until(tester, find.text('Continue intake'));
    await tester.tap(find.text('Continue intake'));
    await _until(
      tester,
      find.text(
        'The synthetic rule did not match a triage row. Ordinary exercise generation stays off.',
      ),
    );
    expect(
      find.text('The clinician question list is not available.'),
      findsNothing,
    );
    final String? raw = await tester.runAsync<String?>(() => store.loadDraft());
    expect(raw, isNotNull);
    expect(raw!, contains('quiet note'));
    expect(raw.contains('"step":"check"'), isTrue);
    expect(raw.contains('schema_green'), isFalse);
    expect(raw.contains('Ordinary exercise generation stays off'), isFalse);
  });

  testWidgets('the user path stores an unmatched view without the note', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProfileStore store = await pumpHome(tester);
    await tester.tap(find.text('Describe a limit'));
    await _until(tester, find.text('I am not sure'));
    await tester.tap(find.text('I am not sure'));
    await tester.pump();
    await _continue(tester);
    expect(find.textContaining('syn-notice-1'), findsOneWidget);
    expect(find.textContaining('not a medical assessment'), findsOneWidget);
    await _continue(tester);
    await tester.ensureVisible(find.text('Control'));
    await tester.tap(find.text('Control'));
    await tester.pump();
    await _continue(tester);
    await tester.ensureVisible(find.text('Chair'));
    await tester.tap(find.text('Chair'));
    await tester.pump();
    await _continue(tester);
    await tester.ensureVisible(find.byKey(const Key('list-arm')));
    await tester.tap(find.byKey(const Key('list-arm')));
    await tester.pump();
    await _continue(tester);
    await tester.ensureVisible(find.byKey(const Key('intake-note')));
    await tester.enterText(find.byKey(const Key('intake-note')), 'quiet note');
    await tester.pump();
    await _continue(tester);
    await tester.ensureVisible(find.byType(Slider));
    final Slider slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(9.0);
    await tester.pump();
    expect(find.text('9 out of 10'), findsOneWidget);
    await _continue(tester);
    expect(
      find.text('The clinician question list is not available.'),
      findsOneWidget,
    );
    await _continue(tester);
    expect(
      find.text(
        'The synthetic rule did not match a triage row. Ordinary exercise generation stays off.',
      ),
      findsOneWidget,
    );
    expect(find.text('No emergency number is configured.'), findsOneWidget);
    expect(find.textContaining('quiet note'), findsNothing);
    expect(find.textContaining('tel:'), findsNothing);
    final String? raw = await tester.runAsync<String?>(() => store.loadDraft());
    expect(raw, isNotNull);
    expect(raw!, contains('quiet note'));
    expect(raw.contains('"severity":9'), isTrue);
    expect(raw.contains('schema_ack'), isTrue);
    expect(raw.contains('schema_green'), isFalse);
    expect(raw.contains('schema_red'), isFalse);
  });

  testWidgets('body screen scrolls at large text and fits a tablet width', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(
        LocalIntakeDraft(
          intent: 'pain_or_limit',
          noticeId: 'syn-notice-1',
          schemaAck: 'yes',
          goals: <String>['mobility'],
          equipment: <String>['chair'],
          step: 'body',
        ).encode(),
      );
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      HelpMeMoveApp(key: const Key('phone'), store: store),
    );
    await _until(tester, find.text('Continue intake'));
    await tester.tap(find.text('Continue intake'));
    await _until(tester, find.text('Map'));
    expect(find.byType(NavigationBar), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Continue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(840, 1200);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpWidget(
      HelpMeMoveApp(key: const Key('tablet'), store: store),
    );
    await _until(tester, find.text('Continue intake'));
    await tester.tap(find.text('Continue intake'));
    await _until(tester, find.text('List'));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('List'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('map-arm')));
    await tester.pump();
    final Material map = tester.widget<Material>(
      find.byKey(const Key('map-arm')),
    );
    final Material mirror = tester.widget<Material>(
      find.byKey(const Key('map-arm-right')),
    );
    final Material list = tester.widget<Material>(
      find.byKey(const Key('list-arm')),
    );
    final Color selected = AppColors.light.accent.withValues(alpha: 0.30);
    expect(map.color, selected);
    expect(mirror.color, selected);
    expect(list.color, selected);
    final RoundedRectangleBorder border = map.shape! as RoundedRectangleBorder;
    expect(border.side.color, AppColors.light.accent);
  });

  testWidgets('dark body selection uses the dark accent', (tester) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(LocalIntakeDraft(step: 'body').encode());
    });
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await _until(tester, find.text('Continue intake'));
    await tester.tap(find.text('Continue intake'));
    await _until(tester, find.text('Map'));
    await _reveal(tester, find.byKey(const Key('map-foot')));
    await tester.tap(find.byKey(const Key('map-foot')));
    await tester.pump();
    final Color selected = AppColors.dark.accent.withValues(alpha: 0.30);
    expect(
      tester.widget<Material>(find.byKey(const Key('map-foot'))).color,
      selected,
    );
    expect(
      tester.widget<Material>(find.byKey(const Key('map-foot-right'))).color,
      selected,
    );
    expect(find.textContaining('Foot'), findsWidgets);
  });

  testWidgets('body map stays in sync with the list', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(
        LocalIntakeDraft(
          intent: 'pain_or_limit',
          noticeId: 'syn-notice-1',
          schemaAck: 'yes',
          goals: <String>['mobility'],
          equipment: <String>['chair'],
          step: 'body',
        ).encode(),
      );
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await _until(tester, find.text('Continue intake'));
    await tester.tap(find.text('Continue intake'));
    await _until(tester, find.byKey(const Key('body-front')));
    expect(find.byKey(const Key('body-back')), findsNothing);
    expect(find.byKey(const Key('body-spine')), findsNothing);
    expect(
      tester.getCenter(find.byKey(const Key('map-head_neck'))).dy,
      lessThan(tester.getCenter(find.byKey(const Key('map-shoulder'))).dy),
    );
    expect(
      tester.getCenter(find.byKey(const Key('map-shoulder'))).dy,
      lessThan(tester.getCenter(find.byKey(const Key('map-torso'))).dy),
    );
    expect(
      tester.getCenter(find.byKey(const Key('map-torso'))).dy,
      lessThan(tester.getCenter(find.byKey(const Key('map-leg'))).dy),
    );
    expect(
      tester.getCenter(find.byKey(const Key('map-leg'))).dy,
      lessThan(tester.getCenter(find.byKey(const Key('map-foot'))).dy),
    );
    expect(
      tester.getCenter(find.byKey(const Key('map-arm'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('map-torso'))).dx),
    );
    expect(
      tester.getCenter(find.byKey(const Key('map-arm-right'))).dx,
      greaterThan(tester.getTopRight(find.byKey(const Key('map-torso'))).dx),
    );
    expect(
      tester.getCenter(find.byKey(const Key('map-leg-right'))).dx,
      greaterThan(tester.getCenter(find.byKey(const Key('map-leg'))).dx),
    );
    expect(
      tester.getCenter(find.byKey(const Key('map-foot-right'))).dx,
      greaterThan(tester.getCenter(find.byKey(const Key('map-foot'))).dx),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('list-arm'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('list-foot'))).dy),
    );
    expect(
      tester.getSize(find.byKey(const Key('list-arm'))).width,
      greaterThan(tester.getSize(find.byKey(const Key('body-front'))).width),
    );

    await tester.tap(find.text('Left'));
    await tester.pump();
    await _reveal(tester, find.byKey(const Key('map-foot')));
    await tester.tap(find.byKey(const Key('map-foot')));
    await tester.pump();
    expect(find.text('Foot Left'), findsOneWidget);
    expect(find.text('Foot'), findsNWidgets(2));
    final Color selected = AppColors.light.accent.withValues(alpha: 0.30);
    expect(
      tester.widget<Material>(find.byKey(const Key('map-foot'))).color,
      selected,
    );
    expect(
      tester.widget<Material>(find.byKey(const Key('map-foot-right'))).color,
      selected,
    );
    expect(
      tester.widget<Material>(find.byKey(const Key('list-foot'))).color,
      selected,
    );

    await tester.tap(find.text('Both'));
    await tester.pump();
    await _reveal(tester, find.byKey(const Key('list-shoulder')));
    await tester.tap(find.byKey(const Key('list-shoulder')));
    await tester.pump();
    expect(
      tester.widget<Material>(find.byKey(const Key('map-shoulder'))).color,
      selected,
    );
    expect(find.text('Shoulder Both'), findsOneWidget);
    expect(find.text('Shoulders'), findsOneWidget);
    expect(find.text('Foot Left'), findsOneWidget);

    await _reveal(tester, find.text('Back').first);
    await tester.tap(find.text('Back').first);
    await tester.pump();
    expect(find.byKey(const Key('body-back')), findsOneWidget);
    expect(find.byKey(const Key('body-spine')), findsOneWidget);
    expect(find.text('Foot Left'), findsOneWidget);
    expect(
      tester.widget<Material>(find.byKey(const Key('map-foot'))).color,
      selected,
    );
    expect(
      tester.widget<Material>(find.byKey(const Key('map-foot-right'))).color,
      selected,
    );

    await _reveal(tester, find.text('Front').first);
    await tester.tap(find.text('Front').first);
    await tester.pump();
    expect(find.byKey(const Key('body-front')), findsOneWidget);
    expect(find.byKey(const Key('body-spine')), findsNothing);
    expect(find.text('Foot Left'), findsOneWidget);
  });

  testWidgets('start over clears an unreadable draft and continues', (
    tester,
  ) async {
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft('{');
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await _until(tester, find.text('Describe a limit'));
    await tester.tap(find.text('Describe a limit'));
    await _until(tester, find.text('The saved draft could not be opened.'));
    await tester.tap(find.text('Start over'));
    await _until(tester, find.text('I want general movement'));
    expect(find.text('The saved draft could not be opened.'), findsNothing);
    await tester.tap(find.text('I want general movement'));
    await tester.pump();
    await _continue(tester);
    await _until(tester, find.text('A note about this fixture'));
    final String? raw = await tester.runAsync<String?>(() => store.loadDraft());
    expect(raw, isNotNull);
    final LocalIntakeDraft saved = LocalIntakeDraft.decode(raw!);
    expect(saved.intent, 'fitness');
    expect(saved.step, 'notice');
  });

  testWidgets('note input keeps 200 scalars including one supplementary', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const String smile = '\u{1F600}';
    final String prefix = 'n' * 199;
    final String tooLong = '$prefix${smile}Z';
    expect(tooLong.runes.length, 201);
    final ProfileStore store = openStore();
    await tester.runAsync(() async {
      await store.openActive();
      await store.saveDraft(LocalIntakeDraft(step: 'note').encode());
    });
    await tester.pumpWidget(HelpMeMoveApp(store: store));
    await _until(tester, find.text('Continue intake'));
    await tester.tap(find.text('Continue intake'));
    await _until(tester, find.byKey(const Key('intake-note')));
    await tester.enterText(find.byKey(const Key('intake-note')), tooLong);
    await tester.pump();
    expect(find.text('200 of 200'), findsOneWidget);
    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('intake-note')),
    );
    expect(field.controller!.text.runes.length, 200);
    expect(field.controller!.text.endsWith(smile), isTrue);
    await _continue(tester);
    await _until(tester, find.text('How strong is it right now'));
    final String? raw = await tester.runAsync<String?>(() => store.loadDraft());
    expect(raw, isNotNull);
    final LocalIntakeDraft saved = LocalIntakeDraft.decode(raw!);
    expect(saved.note.runes.length, 200);
    expect(saved.note.endsWith(smile), isTrue);
    expect(saved.note.contains('Z'), isFalse);
  });

  testWidgets('storage retry uses the store created during retry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ProfileStore opened = openStore();
    await tester.runAsync(() => opened.openActive());
    ProfileStore? visible;
    await tester.pumpWidget(
      HelpMeMoveApp(
        initialLocation: '/storage-failure',
        readStore: () => visible,
        recovery: StorageRecovery(
          onRetry: () async {
            visible = opened;
            return '/';
          },
          onReset: () async => '/storage-failure',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Describe a limit'), findsNothing);
    expect(find.text('Storage is unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _until(tester, find.text('Describe a limit'));
    await tester.tap(find.text('Describe a limit'));
    await _until(tester, find.text('What brings you here'));
    await tester.tap(find.text('I want general movement'));
    await tester.pump();
    await _continue(tester);
    await _until(tester, find.text('A note about this fixture'));
    final String? raw = await tester.runAsync<String?>(
      () => opened.loadDraft(),
    );
    expect(raw, isNotNull);
    expect(LocalIntakeDraft.decode(raw!).intent, 'fitness');
  });

  testWidgets('pain levels 7 to 10 stay off critical red', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: PainSlider(value: 9, onChanged: _ignore)),
      ),
    );
    final ColoredBox box = tester.widget<ColoredBox>(
      find.byKey(const Key('pain-value-background')),
    );
    expect(box.color, AppColors.light.warningSoft);
    expect(box.color, isNot(AppColors.light.critical));
    expect(box.color, isNot(AppColors.light.criticalSoft));
    expect(find.text('9 out of 10'), findsOneWidget);
  });

  testWidgets('injected views show the four sentences and generation flag', (
    tester,
  ) async {
    await _expectOutcome(
      tester,
      const SafetyView(
        code: 'green',
        level: 'green',
        escalation: 'none',
        permitsOrdinaryGeneration: true,
        emergencyDisplay: 'schema-emergency',
        emergencyCode: 'ok',
      ),
      'The synthetic rule returned green. This is not a clinical clearance.',
      allowed: true,
      emergency: 'Fixture display: schema-emergency',
    );
    await _expectOutcome(
      tester,
      const SafetyView(
        code: 'yellow',
        level: 'yellow',
        escalation: 'none',
        permitsOrdinaryGeneration: true,
        emergencyDisplay: '',
        emergencyCode: 'region',
      ),
      'The synthetic rule returned yellow. This is not a clinical restriction.',
      allowed: true,
      emergency: 'No emergency number is configured.',
    );
    await _expectOutcome(
      tester,
      const SafetyView(
        code: 'orange',
        level: 'orange',
        escalation: 'evaluation',
        permitsOrdinaryGeneration: true,
        emergencyDisplay: '',
        emergencyCode: 'unknown-region',
      ),
      'The synthetic rule returned orange. Progression stays paused. This is not a referral.',
      allowed: true,
      emergency: 'No emergency number is configured.',
    );
    await _expectOutcome(
      tester,
      const SafetyView(
        code: 'red',
        level: 'red',
        escalation: 'emergency',
        permitsOrdinaryGeneration: false,
        emergencyDisplay: '',
        emergencyCode: 'region',
      ),
      'The synthetic rule returned red. Ordinary exercise generation stays off. This is not an emergency instruction.',
      allowed: false,
      emergency: 'No emergency number is configured.',
    );
    await _expectOutcome(
      tester,
      const SafetyView(
        code: 'ineligible',
        level: '',
        escalation: 'none',
        permitsOrdinaryGeneration: false,
        emergencyDisplay: '',
        emergencyCode: 'region',
      ),
      'The synthetic notice was not acknowledged. Ordinary exercise generation stays off.',
      allowed: false,
      emergency: 'No emergency number is configured.',
    );
  });
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 30; attempt++) {
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

Future<void> _continue(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Continue'));
  await tester.tap(find.text('Continue'));
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
  }
}

Future<void> _expectOutcome(
  WidgetTester tester,
  SafetyView view,
  String sentence, {
  required bool allowed,
  required String emergency,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: IntakeOutcome(view: view)),
    ),
  );
  expect(find.text(sentence), findsOneWidget);
  expect(
    find.text(
      allowed
          ? 'Ordinary exercise generation is allowed by this fixture.'
          : 'Ordinary exercise generation stays off.',
    ),
    findsWidgets,
  );
  expect(find.text(emergency), findsOneWidget);
  expect(find.byType(Icon), findsOneWidget);
  expect(find.textContaining('tel:'), findsNothing);
}

void _ignore(int value) {}
