import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/workout/spoken_cue.dart';
import 'package:helpmemove/workout/spoken_cue_host.dart';
import 'package:helpmemove/workout/workout_flow.dart';

void main() {
  late String activeDocument;

  setUpAll(() async {
    await RustLib.init();
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final String opened = openWorkout(
      programJson: program,
      monotonicMillis: 0,
      sessionId: '11111111-1111-4111-8111-111111111111',
    ).documentJson;
    final String demonstrating = applyWorkoutEvent(
      documentJson: opened,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 0,
    ).documentJson;
    activeDocument = applyWorkoutEvent(
      documentJson: demonstrating,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 0,
    ).documentJson;
  });

  test('spoken cue text is the three titles', () {
    expect(SpokenAnnouncement.values, hasLength(3));
    expect(spokenCueText(SpokenAnnouncement.sessionPaused), 'Session paused');
    expect(spokenCueText(SpokenAnnouncement.rest), 'Rest');
    expect(spokenCueText(SpokenAnnouncement.exercisePaused), 'Exercise paused');
    expect(
      spokenAnnouncementFor(reporting: false, state: 'paused'),
      SpokenAnnouncement.sessionPaused,
    );
    expect(
      spokenAnnouncementFor(reporting: false, state: 'resting'),
      SpokenAnnouncement.rest,
    );
    expect(
      spokenAnnouncementFor(reporting: true, state: 'active'),
      SpokenAnnouncement.exercisePaused,
    );
    expect(spokenAnnouncementFor(reporting: false, state: 'active'), isNull);
  });

  test('only the spoken cue host imports flutter_tts', () {
    final List<String> hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .where(
          (File file) => file.readAsStringSync().contains(
            'package:flutter_tts/flutter_tts.dart',
          ),
        )
        .map((File file) => file.path.replaceAll('\\', '/'))
        .toList();
    expect(hits, <String>['lib/workout/spoken_cue_host.dart']);
  });

  test('the production host does not call forbidden speech APIs', () {
    final String source = File('lib/workout/spoken_cue_host.dart')
        .readAsStringSync();
    for (final String name in <String>[
      'synthesizeToFile',
      'speech_to_text',
      'playAndRecord',
      'RecognitionService',
      'present_claim',
      'step_movement',
      'CueToken',
    ]) {
      expect(source.contains(name), isFalse, reason: name);
    }
  });

  test('the manifest queries TTS and still removes the microphone', () {
    final String manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest.split('<queries>'), hasLength(2));
    expect(manifest.contains('android.intent.action.TTS_SERVICE'), isTrue);
    expect(
      manifest.contains('android.permission.RECORD_AUDIO" tools:node="remove"'),
      isTrue,
    );
    expect(manifest.contains('RecognitionService'), isFalse);
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist.contains('NSSpeechRecognitionUsageDescription'), isFalse);
    expect(
      plist.contains('HelpMeMove does not record audio for this preview.'),
      isTrue,
    );
    expect(
      File('pubspec.yaml').readAsStringSync().contains('flutter_tts: 4.2.5'),
      isTrue,
    );
    expect(
      File('pubspec.yaml').readAsStringSync().contains('speech_to_text'),
      isFalse,
    );
  });

  testWidgets('speech stays off while Pause and This hurts still work', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final Size size in const <Size>[Size(400, 800), Size(800, 600)]) {
      final FakeSpokenCueHost host = FakeSpokenCueHost();
      final int impacts = await _countImpacts(tester, () async {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(_harness(activeDocument, host: host));
        await _until(tester, find.text('Pause'));
        expect(find.text('Spoken cues'), findsOneWidget);
        expect(_switchValue(tester), isFalse);
        await _tap(tester, 'Pause');
        await _until(tester, find.text('Session paused'));
        expect(host.spoken, isEmpty);
        expect(_caption(tester, 'Session paused').maxLines, 2);
        expect(find.text('Resume'), findsOneWidget);
        expect(find.text('End session'), findsOneWidget);
        expect(find.text('This hurts'), findsNothing);
      });
      expect(impacts, 1);
      expect(tester.takeException(), isNull);

      final FakeSpokenCueHost painHost = FakeSpokenCueHost();
      final int painImpacts = await _countImpacts(tester, () async {
        await tester.pumpWidget(_harness(activeDocument, host: painHost));
        await _until(tester, find.text('This hurts'));
        await _tap(tester, 'This hurts');
        await _until(tester, find.text('Exercise paused'));
        expect(painHost.spoken, isEmpty);
        expect(_caption(tester, 'Exercise paused').maxLines, 2);
        expect(find.text('Mild discomfort'), findsOneWidget);
        expect(find.text('0'), findsWidgets);
        expect(find.text('10'), findsOneWidget);
        expect(find.text('Continue'), findsOneWidget);
        expect(find.text('End session'), findsOneWidget);
      });
      expect(painImpacts, 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Session paused is spoken once and mute calls stop', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800));
    final FakeSpokenCueHost host = FakeSpokenCueHost();
    final int impacts = await _countImpacts(tester, () async {
      await tester.pumpWidget(_harness(activeDocument, host: host));
      await _until(tester, find.text('Spoken cues'));
      await _tap(tester, 'Spoken cues');
      await tester.pump();
      expect(_switchValue(tester), isTrue);
      expect(host.spoken, isEmpty);
      await _tap(tester, 'Pause');
      await _until(tester, find.text('Session paused'));
      await tester.pump();
      expect(host.spoken, <String>['Session paused']);
      final int stopsBeforeMute = host.stops;
      await _tap(tester, 'Spoken cues');
      await tester.pump();
      expect(_switchValue(tester), isFalse);
      expect(host.stops, greaterThan(stopsBeforeMute));
      expect(host.spoken, <String>['Session paused']);
      await _tap(tester, 'Resume');
      await _until(tester, find.text('Pause'));
      await tester.pump();
      expect(host.spoken, <String>['Session paused']);
    });
    expect(impacts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rest is spoken without the remaining seconds', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 600));
    final FakeSpokenCueHost host = FakeSpokenCueHost();
    final String resting = File('test/workout/opened_shoulder_session.json')
        .readAsStringSync()
        .trim()
        .replaceFirst('"state":"preparing"', '"state":"resting"')
        .replaceFirst('"rest_until_ms":null', '"rest_until_ms":6000');
    await tester.pumpWidget(
      _harness(
        resting,
        host: host,
        spokenCues: true,
        clock: ManualWorkoutClock(),
      ),
    );
    await _until(tester, find.text('Rest'));
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Spoken cues'), findsOneWidget);
    expect(host.spoken, <String>['Rest']);
    expect(host.spoken.single.contains(RegExp(r'\d')), isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(host.spoken, <String>['Rest']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Exercise paused does not speak a symptom or a pain digit', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(400, 800));
    final FakeSpokenCueHost host = FakeSpokenCueHost();
    await tester.pumpWidget(
      _harness(activeDocument, host: host, spokenCues: true),
    );
    await _until(tester, find.text('This hurts'));
    await _tap(tester, 'This hurts');
    await _until(tester, find.text('Exercise paused'));
    await tester.pump();
    expect(host.spoken, <String>['Exercise paused']);
    expect(host.spoken.single.contains(RegExp(r'\d')), isFalse);
    expect(host.spoken.single.contains('mild'), isFalse);
    expect(host.spoken.single.contains('sharp'), isFalse);
    expect(host.spoken.single.contains('numb'), isFalse);
    expect(find.text('Sharp pain'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    await _tap(tester, '7');
    await tester.pump();
    expect(host.spoken, <String>['Exercise paused']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rep tap does not speak or haptic', (
    WidgetTester tester,
  ) async {
    final FakeSpokenCueHost host = FakeSpokenCueHost();
    final int impacts = await _countImpacts(tester, () async {
      await tester.pumpWidget(
        _harness(activeDocument, host: host, spokenCues: true),
      );
      await _until(tester, find.text('Rep 1 of 1'));
      await _tap(tester, 'Rep 1 of 1');
      await _until(tester, find.text('Session saved'));
      await tester.pump();
      expect(host.spoken, isEmpty);
    });
    expect(impacts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive calls stop and resume does not speak again', (
    WidgetTester tester,
  ) async {
    final FakeSpokenCueHost host = FakeSpokenCueHost();
    final String paused = activeDocument.replaceFirst(
      '"state":"active"',
      '"state":"paused"',
    );
    await tester.pumpWidget(_harness(paused, host: host, spokenCues: true));
    await _until(tester, find.text('Session paused'));
    await tester.pump();
    expect(host.spoken, <String>['Session paused']);
    final int spoken = host.spoken.length;
    final int stops = host.stops;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(host.stops, greaterThan(stops));
    expect(host.spoken, hasLength(spoken));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(host.spoken, hasLength(spoken));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lifecycle pause stays silent after resume', (
    WidgetTester tester,
  ) async {
    final FakeSpokenCueHost host = FakeSpokenCueHost();
    await tester.pumpWidget(
      _harness(activeDocument, host: host, spokenCues: true),
    );
    await _until(tester, find.text('Pause'));
    expect(host.spoken, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _until(tester, find.text('Session paused'));
    await tester.pump();
    expect(host.spoken, isEmpty);
    await _tap(tester, 'Resume');
    await _until(tester, find.text('Pause'));
    await _tap(tester, 'Pause');
    await _until(tester, find.text('Session paused'));
    await tester.pump();
    expect(host.spoken, <String>['Session paused']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lifecycle pain commit does not silence the next pause', (
    WidgetTester tester,
  ) async {
    final FakeSpokenCueHost host = FakeSpokenCueHost();
    await tester.pumpWidget(
      _harness(activeDocument, host: host, spokenCues: true),
    );
    await _until(tester, find.text('This hurts'));
    await _tap(tester, 'This hurts');
    await _until(tester, find.text('Exercise paused'));
    await tester.pump();
    expect(host.spoken, <String>['Exercise paused']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(host.spoken, <String>['Exercise paused']);
    await _tap(tester, 'Continue');
    await _until(tester, find.text('Session paused'));
    await tester.pump();
    expect(host.spoken, <String>['Exercise paused', 'Session paused']);
    expect(tester.takeException(), isNull);
  });

  test('setup is shared and a failed setup does not speak', () async {
    final Completer<void> gate = Completer<void>();
    final List<String> spoken = <String>[];
    final FlutterSpokenCueHost host = FlutterSpokenCueHost(
      configure: () async {
        await gate.future;
        return <Object?>[1, 1];
      },
      speakText: (String text) async {
        spoken.add(text);
        return 1;
      },
    );
    final Future<void> first = host.speak('Session paused');
    final Future<void> second = host.speak('Rest');
    await Future<void>.delayed(Duration.zero);
    expect(spoken, isEmpty);
    gate.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(spoken, <String>['Rest']);

    final List<String> failed = <String>[];
    final FlutterSpokenCueHost broken = FlutterSpokenCueHost(
      configure: () async {
        throw StateError('setup failed');
      },
      speakText: (String text) async {
        failed.add(text);
        return 1;
      },
    );
    await broken.speak('Session paused');
    await broken.speak('Exercise paused');
    expect(failed, isEmpty);

    for (final Future<List<Object?>?> Function() configure
        in <Future<List<Object?>?> Function()>[
          () async => <Object?>[0, 1],
          () async => <Object?>[1, 0],
          () async => null,
        ]) {
      final List<String> quiet = <String>[];
      final FlutterSpokenCueHost rejected = FlutterSpokenCueHost(
        configure: configure,
        speakText: (String text) async {
          quiet.add(text);
          return 1;
        },
      );
      await rejected.speak('Session paused');
      await rejected.speak('Rest');
      expect(quiet, isEmpty);
    }
  });

  testWidgets('a held ready becomes a silent lifecycle pause', (
    WidgetTester tester,
  ) async {
    final Directory temp = Directory.systemTemp.createTempSync(
      'helpmemove-cue',
    );
    final _HoldingDraftStore store = _HoldingDraftStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(11),
      excludeFromBackup: (String path) async {},
    );
    addTearDown(() async {
      await store.close();
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final String opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    ).documentJson;
    final String demonstrating = applyWorkoutEvent(
      documentJson: opened,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 1000,
    ).documentJson;
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
      await store.saveWorkoutDraft(demonstrating);
    });
    final FakeSpokenCueHost host = FakeSpokenCueHost();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WorkoutFlow(store: store, cues: host, spokenCues: true),
      ),
    );
    await _until(tester, find.text("I'm ready"));
    store.hold = Completer<void>();
    await tester.tap(find.text("I'm ready"));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    store.hold!.complete();
    store.hold = null;
    await _until(tester, find.text('Session paused'));
    await tester.pump();
    expect(host.spoken, isEmpty);
    await _tap(tester, 'Resume');
    await _until(tester, find.text('Pause'));
    await _tap(tester, 'Pause');
    await _until(tester, find.text('Session paused'));
    await tester.pump();
    expect(host.spoken, <String>['Session paused']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a held nonfinal rep keeps the lifecycle pause silent', (
    WidgetTester tester,
  ) async {
    final Directory temp = Directory.systemTemp.createTempSync(
      'helpmemove-cue',
    );
    final _HoldingDraftStore store = _HoldingDraftStore(
      keys: MemoryProfileKeyStore(),
      supportDirectory: temp,
      clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      random: Random(11),
      excludeFromBackup: (String path) async {},
    );
    addTearDown(() async {
      await store.close();
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });
    final String program = File('test/program/green_shoulder_program.json')
        .readAsStringSync()
        .trim();
    final String opened = openWorkout(
      programJson: program,
      monotonicMillis: 1000,
      sessionId: '11111111-1111-4111-8111-111111111111',
    ).documentJson;
    final String demonstrating = applyWorkoutEvent(
      documentJson: opened,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 1000,
    ).documentJson;
    final String active = applyWorkoutEvent(
      documentJson: demonstrating,
      eventJson: '{"name":"ready"}',
      monotonicMillis: 1000,
    ).documentJson;
    await tester.runAsync(() async {
      await store.createProfile();
      await store.saveProgramRecord(program);
      await store.saveWorkoutDraft(active);
    });
    final FakeSpokenCueHost host = FakeSpokenCueHost();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WorkoutFlow(
          store: store,
          cues: host,
          spokenCues: true,
          // The committed dose is one rep, so a real complete_rep finishes
          // the session and never reaches the lifecycle pause. This seam
          // keeps that document active while its draft save is held.
          applyEvent: (String document, String event, int at) {
            if (event == '{"name":"complete_rep"}') {
              return WorkoutView(
                outcome: 'ready',
                errorCode: '',
                documentJson: document,
              );
            }
            return applyWorkoutEvent(
              documentJson: document,
              eventJson: event,
              monotonicMillis: at,
            );
          },
        ),
      ),
    );
    await _until(tester, find.text('Rep 1 of 1'));
    store.hold = Completer<void>();
    await tester.tap(find.text('Rep 1 of 1'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.ensureVisible(find.text('This hurts'));
    await tester.tap(find.text('This hurts'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pump();
    expect(find.text('Exercise paused'), findsOneWidget);
    expect(host.spoken, isEmpty);
    store.hold!.complete();
    store.hold = null;
    await _until(tester, find.text('Session paused'));
    await tester.pump();
    expect(host.spoken, isEmpty);
    await _tap(tester, 'Resume');
    await _until(tester, find.text('Pause'));
    await _tap(tester, 'Pause');
    await _until(tester, find.text('Session paused'));
    await tester.pump();
    expect(host.spoken, <String>['Session paused']);
    expect(tester.takeException(), isNull);
  });
}

class _HoldingDraftStore extends ProfileStore {
  _HoldingDraftStore({
    required super.keys,
    required super.supportDirectory,
    required super.clock,
    required super.random,
    required super.excludeFromBackup,
  });

  Completer<void>? hold;

  @override
  Future<void> saveWorkoutDraft(String documentJson) async {
    final Completer<void>? pending = hold;
    if (pending != null && !pending.isCompleted) {
      await pending.future;
    }
    await super.saveWorkoutDraft(documentJson);
  }
}

class FakeSpokenCueHost implements SpokenCueHost {
  final List<String> spoken = <String>[];
  int stops = 0;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stops += 1;
  }
}

Widget _harness(
  String document, {
  required FakeSpokenCueHost host,
  bool spokenCues = false,
  WorkoutClock? clock,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: WorkoutFlow(
      key: UniqueKey(),
      previewDocument: document,
      cues: host,
      spokenCues: spokenCues,
      clock: clock,
    ),
  );
}

Text _caption(WidgetTester tester, String text) {
  return tester.widget<Text>(find.text(text));
}

bool _switchValue(WidgetTester tester) {
  return tester.widget<Switch>(find.byType(Switch)).value;
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
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

Future<void> _tap(WidgetTester tester, String label) async {
  final Finder finder = find.text(label);
  final Finder scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(finder, 200, scrollable: scrollable.last);
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<int> _countImpacts(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  var impacts = 0;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'HapticFeedback.vibrate' &&
          call.arguments == 'HapticFeedbackType.lightImpact') {
        impacts += 1;
      }
      return null;
    },
  );
  try {
    await body();
    return impacts;
  } finally {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  }
}
