import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/workout/camera_guidance.dart';
import 'package:helpmemove/workout/spoken_cue_host.dart';
import 'package:helpmemove/workout/workout_flow.dart';

const Key _captureKey = Key('fail-closed-capture');

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
  late String activeDocument;

  setUpAll(() async {
    await RustLib.init();
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadCaptureFont();
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

  test('shipped preview and speech sources stay fail-closed', () {
    final String preview = File('lib/workout/camera_preview_host.dart')
        .readAsStringSync();
    expect(preview.contains('enableAudio: false'), isTrue);
    for (final String forbidden in <String>[
      'takePicture',
      'startVideoRecording',
      'startImageStream',
      'enableAudio: true',
    ]) {
      expect(preview.contains(forbidden), isFalse, reason: forbidden);
    }

    final String speech = File('lib/workout/spoken_cue_host.dart')
        .readAsStringSync();
    for (final String forbidden in <String>[
      'synthesizeToFile',
      'speech_to_text',
      'playAndRecord',
      'RecognitionService',
      'present_claim',
      'step_movement',
      'CueToken',
    ]) {
      expect(speech.contains(forbidden), isFalse, reason: forbidden);
    }

    final String manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(
      manifest.contains('android.permission.RECORD_AUDIO" tools:node="remove"'),
      isTrue,
    );
    final int queries = manifest.indexOf('<queries>');
    final int queriesEnd = manifest.indexOf('</queries>');
    expect(queries, greaterThanOrEqualTo(0));
    expect(queriesEnd, greaterThan(queries));
    expect(
      manifest
          .substring(queries, queriesEnd)
          .contains('android.intent.action.TTS_SERVICE'),
      isTrue,
    );
    expect(manifest.contains('android.speech.RecognitionService'), isFalse);

    final String plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist.contains('NSSpeechRecognitionUsageDescription'), isFalse);
    expect(
      plist.contains('HelpMeMove does not record audio for this preview.'),
      isTrue,
    );

    for (final String path in <String>[
      '../../packages/movement_vision/android/src/main/kotlin/app/helpmemove/movement_vision/MovementVisionPlugin.kt',
      '../../packages/movement_vision/ios/movement_vision/Sources/movement_vision/MovementVisionPlugin.swift',
    ]) {
      _expectUnavailableStart(path);
    }

    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('camera: 0.12.1'), isTrue);
    expect(pubspec.contains('flutter_tts: 4.2.5'), isTrue);
    expect(pubspec.contains('speech_to_text'), isFalse);
    expect(
      File('lib/storage/profile_database.dart')
          .readAsStringSync()
          .contains('int get schemaVersion => 10'),
      isTrue,
    );

    final String router = File('lib/design/router.dart').readAsStringSync();
    final int route = router.indexOf("path: 'camera-guidance'");
    expect(route, greaterThanOrEqualTo(0));
    final int routeEnd = route + 800 < router.length
        ? route + 800
        : router.length;
    expect(
      router
          .substring(route, routeEnd)
          .contains("context.go('/focus/workout')"),
      isTrue,
    );
    expect(
      File('lib/assessment/assessment_flow.dart')
          .readAsStringSync()
          .contains('package:camera/camera.dart'),
      isFalse,
    );
  });

  testWidgets('a denied camera returns without a measurement', (
    WidgetTester tester,
  ) async {
    for (final Size size in const <Size>[Size(400, 800), Size(800, 600)]) {
      final _FakeHost host = _FakeHost(const CameraOpenUnavailable());
      var left = 0;
      await _pumpGuidance(
        tester,
        size: size,
        host: host,
        onLeave: () => left++,
      );
      expect(
        find.text('Use your camera for a positioning preview?'),
        findsOneWidget,
      );
      if (size == const Size(400, 800)) {
        await _capture(tester, 'guidance-permission-400x800.png');
      }
      if (size == const Size(800, 600)) {
        await _capture(tester, 'guidance-permission-800x600.png');
      }
      await _tap(tester, 'Enable camera');
      expect(host.opens, 1);
      expect(find.text('Camera unavailable'), findsOneWidget);
      expect(
        find.text('You can continue the workout without the camera.'),
        findsOneWidget,
      );
      _expectNoDegree(tester);
      if (size == const Size(400, 800)) {
        await _capture(tester, 'guidance-unavailable-400x800.png');
      }
      await _tap(tester, 'Continue without camera');
      expect(left, 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('leaving the foreground closes the preview', (
    WidgetTester tester,
  ) async {
    for (final Size size in const <Size>[Size(400, 800), Size(800, 600)]) {
      final _FakeHost host = _FakeHost(
        const CameraOpened(SizedBox(key: Key('preview-box'))),
      );
      await _pumpGuidance(tester, size: size, host: host);
      await _tap(tester, 'Enable camera');
      expect(find.byKey(const Key('preview-box')), findsOneWidget);
      final int closes = host.closes;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.pump();
      expect(host.closes, greaterThan(closes));
      expect(
        find.text('Use your camera for a positioning preview?'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a failed speech host stays silent for Pause and This hurts', (
    WidgetTester tester,
  ) async {
    final List<String> spoken = <String>[];
    for (final Size size in const <Size>[Size(400, 800), Size(800, 600)]) {
      await _pumpWorkout(
        tester,
        document: activeDocument,
        size: size,
        host: _failedHost(spoken),
        spokenCues: true,
      );
      await _until(tester, find.text('Pause'));
      await _tap(tester, 'Pause');
      await _until(tester, find.text('Session paused'));
      await _settle(tester);
      expect(find.text('This hurts'), findsNothing);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Make session shorter'), findsOneWidget);
      expect(find.text('Skip current exercise'), findsOneWidget);
      expect(find.text('End session'), findsOneWidget);
      _expectCaptionHasNoDigit(tester, 'Session paused');
      expect(spoken, isEmpty);
      expect(tester.takeException(), isNull);

      await _pumpWorkout(
        tester,
        document: activeDocument,
        size: size,
        host: _failedHost(spoken),
        spokenCues: true,
      );
      await _until(tester, find.text('This hurts'));
      await _tap(tester, 'This hurts');
      await _until(tester, find.text('Exercise paused'));
      await _settle(tester);
      _expectCaptionHasNoDigit(tester, 'Exercise paused');
      expect(spoken, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the paused capture keeps spoken cues off', (
    WidgetTester tester,
  ) async {
    for (final Size size in const <Size>[Size(400, 800), Size(800, 600)]) {
      await _pumpWorkout(
        tester,
        document: activeDocument,
        size: size,
        host: _failedHost(<String>[]),
      );
      await _until(tester, find.text('Pause'));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await _tap(tester, 'Pause');
      await _until(tester, find.text('Session paused'));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      if (size == const Size(400, 800)) {
        await _capture(tester, 'workout-paused-400x800.png');
      }
      expect(tester.takeException(), isNull);
    }
  });
}

FlutterSpokenCueHost _failedHost(List<String> spoken) {
  return FlutterSpokenCueHost(
    configure: () async {
      throw StateError('setup failed');
    },
    speakText: (String text) async {
      spoken.add(text);
      return 1;
    },
  );
}

class _FakeHost implements CameraPreviewHost {
  _FakeHost(this.result);

  final CameraOpenResult result;
  int opens = 0;
  int closes = 0;

  @override
  Future<CameraOpenResult> open() async {
    opens += 1;
    return result;
  }

  @override
  Future<void> close() async {
    closes += 1;
  }
}

Future<void> _pumpGuidance(
  WidgetTester tester, {
  required Size size,
  required CameraPreviewHost host,
  VoidCallback? onLeave,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: _captureTheme(),
      home: RepaintBoundary(
        key: _captureKey,
        child: CameraGuidance(
          key: UniqueKey(),
          host: host,
          onLeave: onLeave ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpWorkout(
  WidgetTester tester, {
  required String document,
  required Size size,
  required FlutterSpokenCueHost host,
  bool spokenCues = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: _captureTheme(),
      home: RepaintBoundary(
        key: _captureKey,
        child: WorkoutFlow(
          key: UniqueKey(),
          previewDocument: document,
          cues: host,
          spokenCues: spokenCues,
        ),
      ),
    ),
  );
  await tester.pump();
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
  await tester.pump();
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
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

void _expectUnavailableStart(String path) {
  final String plugin = File(path).readAsStringSync();
  expect(plugin.contains('MediaPipeTasksVision'), isFalse, reason: path);
  expect(plugin.contains('pose_landmarker'), isFalse, reason: path);
  final bool kotlin = path.endsWith('.kt');
  final String start = _branch(
    plugin,
    kotlin ? '"start"' : 'case "start"',
    kotlin ? '"stop"' : 'case "stop"',
  );
  final RegExp error = kotlin
      ? RegExp(
          r'"start"\s*->\s*result\.error\(\s*"unavailable"\s*,\s*"Live pose capture is not available\."\s*,',
        )
      : RegExp(
          r'case\s+"start"\s*:\s*result\(\s*FlutterError\(\s*code:\s*"unavailable"\s*,\s*message:\s*"Live pose capture is not available\."\s*,',
        );
  expect(error.hasMatch(start), isTrue, reason: path);
  expect(start.contains('result.success'), isFalse, reason: path);
  expect(RegExp(r'result\(\s*"').hasMatch(start), isFalse, reason: path);
}

String _branch(String source, String startMarker, String endMarker) {
  final int start = source.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0), reason: startMarker);
  final int end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, greaterThan(start), reason: endMarker);
  return source.substring(start, end);
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
    File('$directory/$name').writeAsBytesSync(data.buffer.asUint8List());
  } finally {
    image?.dispose();
  }
}

void _expectNoDegree(WidgetTester tester) {
  final String joined = tester
      .widgetList<Text>(find.byType(Text))
      .map((Text text) => text.data ?? '')
      .join('\n');
  expect(joined.contains('degree'), isFalse);
  expect(joined.contains('ROM'), isFalse);
  expect(joined.contains('°'), isFalse);
}

void _expectCaptionHasNoDigit(WidgetTester tester, String caption) {
  final String data = tester.widget<Text>(find.text(caption)).data ?? '';
  expect(RegExp('[0-9]').hasMatch(data), isFalse);
}
