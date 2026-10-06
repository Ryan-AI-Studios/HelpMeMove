import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/design/app_theme.dart';
import 'package:helpmemove/workout/camera_guidance.dart';
import 'package:helpmemove/workout/camera_preview_host.dart';

void main() {
  test('production preview host does not stream, save, or measure', () {
    final String source = File('lib/workout/camera_preview_host.dart')
        .readAsStringSync();
    for (final String forbidden in [
      'startImageStream',
      'takePicture',
      'startVideoRecording',
      'pauseVideoRecording',
      'stopVideoRecording',
      'MovementVision',
      'acceptPoseFrame',
      'present_claim',
      'fps:',
      'videoBitrate',
      'audioBitrate',
      'imageFormatGroup',
    ]) {
      expect(source.contains(forbidden), isFalse, reason: forbidden);
    }
    expect(source.contains('enableAudio: false'), isTrue);
    expect(source.contains('ResolutionPreset.medium'), isTrue);
    expect(source.contains('cameras.isEmpty'), isTrue);
    expect(source.contains('on CameraException'), isTrue);
    expect(source.contains('on Object'), isTrue);
  });

  testWidgets('permission, preview, and unavailable states stay unmeasured', (
    WidgetTester tester,
  ) async {
    for (final Size size in const [Size(400, 800), Size(800, 600)]) {
      await _pump(
        tester,
        size: size,
        host: _FakeHost(const CameraOpenUnavailable()),
      );
      expect(
        find.text('Use your camera for a positioning preview?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The preview stays on this device and is not saved. It does not measure a joint or count a rep.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Keep other people, especially children, out of the view.'),
        findsOneWidget,
      );
      _expectNoMeasurement(tester);
      await _capture(
        tester,
        'permission-${size.width.toInt()}x${size.height.toInt()}.png',
      );

      final _FakeHost previewHost = _FakeHost(
        const CameraOpened(SizedBox(key: Key('preview-box'))),
      );
      var left = 0;
      await _pump(tester, size: size, host: previewHost, onLeave: () => left++);
      await _tap(tester, 'Not now');
      expect(left, 1);
      expect(previewHost.closes, greaterThan(0));

      await _pump(tester, size: size, host: previewHost, onLeave: () => left++);
      await _tap(tester, 'Enable camera');
      expect(find.byKey(const Key('preview-box')), findsOneWidget);
      expect(find.text('Position your phone'), findsOneWidget);
      expect(
        find.text('Step back until your whole body fits in the guide.'),
        findsOneWidget,
      );
      _expectNoMeasurement(tester);
      await _capture(
        tester,
        'preview-${size.width.toInt()}x${size.height.toInt()}.png',
      );
      final int closesBeforeContinue = previewHost.closes;
      await _tap(tester, 'Continue');
      expect(left, 2);
      expect(previewHost.closes, greaterThan(closesBeforeContinue));

      await _pump(tester, size: size, host: previewHost, onLeave: () => left++);
      await _tap(tester, 'Enable camera');
      await _tap(tester, 'Continue without camera');
      expect(left, 3);

      final _FakeHost denied = _FakeHost(const CameraOpenUnavailable());
      await _pump(tester, size: size, host: denied, onLeave: () => left++);
      await _tap(tester, 'Enable camera');
      expect(find.text('Camera unavailable'), findsOneWidget);
      expect(
        find.text('You can continue the workout without the camera.'),
        findsOneWidget,
      );
      _expectNoMeasurement(tester);
      await _capture(
        tester,
        'unavailable-${size.width.toInt()}x${size.height.toInt()}.png',
      );
      await _tap(tester, 'Continue without camera');
      expect(left, 4);
      expect(denied.opens, 1);
    }
  });

  testWidgets('leaving the foreground closes the preview', (
    WidgetTester tester,
  ) async {
    final _FakeHost host = _FakeHost(
      const CameraOpened(SizedBox(key: Key('preview-box'))),
    );
    await _pump(tester, host: host);
    await _tap(tester, 'Enable camera');
    expect(find.text('Position your phone'), findsOneWidget);
    final int closes = host.closes;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Use your camera for a positioning preview?'),
      findsOneWidget,
    );
    expect(host.closes, greaterThan(closes));
    final int opens = host.opens;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(host.opens, opens);
    expect(
      find.text('Use your camera for a positioning preview?'),
      findsOneWidget,
    );
  });

  testWidgets('dark theme and large text keep the permission actions', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      size: const Size(400, 800),
      textScale: 1.6,
      theme: AppTheme.dark(),
      host: _FakeHost(const CameraOpenUnavailable()),
    );
    expect(find.text('Enable camera'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    _expectNoMeasurement(tester);
  });

  test('the route builder does not construct a camera host', () {
    final String source = File('lib/design/router.dart').readAsStringSync();
    expect(source.contains('DeviceCameraPreviewHost('), isFalse);
    expect(source.contains('CameraGuidanceRoute('), isTrue);
  });

  test('an empty camera list does not bind a preview', () async {
    var binds = 0;
    final DeviceCameraPreviewHost host = DeviceCameraPreviewHost(
      listCameras: () async => const <PreviewCamera>[],
      bindPreview: (PreviewCamera camera) async {
        binds += 1;
        return BoundPreview(
          SizedBox(key: ValueKey<bool>(camera.back)),
          () async {},
        );
      },
    );
    final CameraOpenResult result = await host.open();
    expect(result, isA<CameraOpenUnavailable>());
    expect(binds, 0);
    await host.close();
  });

  test('a cancelled catalog cannot bind or close a later preview', () async {
    final Completer<List<PreviewCamera>> catalog =
        Completer<List<PreviewCamera>>();
    final List<int> closed = <int>[];
    var binds = 0;
    final DeviceCameraPreviewHost host = DeviceCameraPreviewHost(
      listCameras: () => catalog.future,
      bindPreview: (PreviewCamera camera) async {
        binds += 1;
        return BoundPreview(const SizedBox(), () async {
          closed.add(binds);
        });
      },
    );
    final Future<CameraOpenResult> first = host.open();
    final Future<void> closing = host.close();
    catalog.complete(const <PreviewCamera>[PreviewCamera(back: true)]);
    expect(await first, isA<CameraOpenUnavailable>());
    await closing;
    expect(binds, 0);

    final Completer<void> release = Completer<void>();
    final Completer<void> started = Completer<void>();
    final DeviceCameraPreviewHost second = DeviceCameraPreviewHost(
      listCameras: () async => const <PreviewCamera>[
        PreviewCamera(back: false),
        PreviewCamera(back: true),
      ],
      bindPreview: (PreviewCamera camera) async {
        expect(camera.back, isTrue);
        if (!started.isCompleted) {
          started.complete();
        }
        await release.future;
        return BoundPreview(const Text('later'), () async {
          closed.add(2);
        });
      },
    );
    final Future<CameraOpenResult> opening = second.open();
    await started.future;
    final Future<void> closingSecond = second.close();
    release.complete();
    expect(await opening, isA<CameraOpenUnavailable>());
    await closingSecond;
    expect(closed, <int>[2]);

    final CameraOpenResult kept = await DeviceCameraPreviewHost(
      listCameras: () async => const <PreviewCamera>[
        PreviewCamera(back: false),
      ],
      bindPreview: (PreviewCamera camera) async {
        expect(camera.back, isFalse);
        return BoundPreview(const Text('front'), () async {});
      },
    ).open();
    expect(kept, isA<CameraOpened>());
  });

  test('a stale bind closes before the next host binds', () async {
    final List<String> order = <String>[];
    final Completer<void> release = Completer<void>();
    final DeviceCameraPreviewHost first = DeviceCameraPreviewHost(
      listCameras: () async => const <PreviewCamera>[PreviewCamera(back: true)],
      bindPreview: (PreviewCamera camera) async {
        order.add('bindA');
        await release.future;
        return BoundPreview(Text(camera.back.toString()), () async {
          order.add('closeA');
        });
      },
    );
    final DeviceCameraPreviewHost second = DeviceCameraPreviewHost(
      listCameras: () async => const <PreviewCamera>[PreviewCamera(back: true)],
      bindPreview: (PreviewCamera camera) async {
        order.add('bindB');
        return BoundPreview(Text(camera.back.toString()), () async {});
      },
    );
    final Future<CameraOpenResult> opening = first.open();
    while (!order.contains('bindA')) {
      await Future<void>.delayed(Duration.zero);
    }
    final Future<void> closing = first.close();
    final Future<CameraOpenResult> next = second.open();
    await Future<void>.delayed(Duration.zero);
    expect(order, <String>['bindA']);
    release.complete();
    expect(await opening, isA<CameraOpenUnavailable>());
    await closing;
    expect(await next, isA<CameraOpened>());
    expect(order, <String>['bindA', 'closeA', 'bindB']);
  });

  test('a failed catalog stays unavailable', () async {
    final DeviceCameraPreviewHost host = DeviceCameraPreviewHost(
      listCameras: () async => throw StateError('denied'),
      bindPreview: (PreviewCamera camera) async {
        throw StateError('bound ${camera.back}');
      },
    );
    expect(await host.open(), isA<CameraOpenUnavailable>());
    await host.close();
  });

  testWidgets('a stale open does not close the next attempt', (
    WidgetTester tester,
  ) async {
    final _GateHost host = _GateHost(
      const CameraOpened(SizedBox(key: Key('preview-box'))),
    );
    await _pump(tester, host: host);
    await _tap(tester, 'Enable camera');
    expect(host.opens, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Use your camera for a positioning preview?'),
      findsOneWidget,
    );
    final int closes = host.closes;
    await _tap(tester, 'Enable camera');
    expect(host.opens, 2);
    host.release();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('preview-box')), findsOneWidget);
    expect(host.closes, closes);
  });

  testWidgets('replacing the host closes only the previous preview', (
    WidgetTester tester,
  ) async {
    final _GateHost first = _GateHost(
      const CameraOpened(SizedBox(key: Key('first-preview'))),
    );
    final _GateHost second = _GateHost(
      const CameraOpened(SizedBox(key: Key('second-preview'))),
    );
    CameraPreviewHost current = first;
    Future<void> pump() {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: CameraGuidance(
            key: const ValueKey<String>('stable-guidance'),
            host: current,
            onLeave: () {},
          ),
        ),
      );
    }

    await pump();
    await tester.pump();
    await _tap(tester, 'Enable camera');
    first.release();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('first-preview')), findsOneWidget);

    current = second;
    await pump();
    await tester.pump();
    expect(first.closes, greaterThan(0));
    expect(second.closes, 0);
    expect(
      find.text('Use your camera for a positioning preview?'),
      findsOneWidget,
    );
    await _tap(tester, 'Enable camera');
    second.release();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('second-preview')), findsOneWidget);
    expect(second.closes, 0);
  });
}

class _GateHost implements CameraPreviewHost {
  _GateHost(this.result);

  final CameraOpenResult result;
  final Completer<void> _gate = Completer<void>();
  int opens = 0;
  int closes = 0;

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<CameraOpenResult> open() async {
    opens += 1;
    await _gate.future;
    return result;
  }

  @override
  Future<void> close() async {
    closes += 1;
  }
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

Future<void> _pump(
  WidgetTester tester, {
  required CameraPreviewHost host,
  Size size = const Size(400, 800),
  double textScale = 1,
  ThemeData? theme,
  VoidCallback? onLeave,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: RepaintBoundary(
        key: const Key('guidance-capture'),
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

Future<void> _tap(WidgetTester tester, String label) async {
  final Finder finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final String? directory = Platform.environment['HMM_UI_EVIDENCE'];
  if (directory == null || directory.isEmpty) {
    return;
  }
  await tester.pump();
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(const Key('guidance-capture')),
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

void _expectNoMeasurement(WidgetTester tester) {
  final String joined = tester
      .widgetList<Text>(find.byType(Text))
      .map((Text text) => text.data ?? '')
      .join('\n');
  expect(joined.contains('°'), isFalse);
  expect(joined.contains('ROM'), isFalse);
}
