import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';
import 'package:helpmemove/vision/movement_vision_session.dart';
import 'package:movement_vision/movement_vision.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  tearDown(() async {
    await MovementVisionSession.releaseInstalled();
  });

  List<double> row(double value) {
    return List<double>.filled(33, value);
  }

  Future<MovementVisionSession> hold({
    required int timestampUnixMs,
    Future<void> Function()? stop,
    int rotationDegrees = 0,
    bool mirrored = false,
    List<double>? x,
    List<double>? y,
  }) async {
    final MovementVisionSession session = MovementVisionSession(stop: stop);
    await session.accept(
      x: x ?? row(0.2),
      y: y ?? row(0.1),
      z: row(0.0),
      visibility: row(1.0),
      presence: row(1.0),
      timestampUnixMs: timestampUnixMs,
      rotationDegrees: rotationDegrees,
      mirrored: mirrored,
    );
    return session;
  }

  test('a later timestamp replaces the held frame', () async {
    final MovementVisionSession session = await hold(timestampUnixMs: 10);
    expect(session.frame?.timestampUnixMs, 10);
    expect(session.frame?.points[0].x, 0.2);

    await session.accept(
      x: row(0.2),
      y: row(0.1),
      z: row(0.0),
      visibility: row(1.0),
      presence: row(1.0),
      timestampUnixMs: 10,
      rotationDegrees: 0,
      mirrored: false,
    );
    expect(session.dropCount, 1);
    expect(session.frame?.timestampUnixMs, 10);

    await session.accept(
      x: row(0.2),
      y: row(0.1),
      z: row(0.0),
      visibility: row(1.0),
      presence: row(1.0),
      timestampUnixMs: 9,
      rotationDegrees: 0,
      mirrored: false,
    );
    expect(session.dropCount, 2);
    expect(session.frame?.timestampUnixMs, 10);

    await session.accept(
      x: row(0.2),
      y: row(0.1),
      z: row(0.0),
      visibility: row(0.0),
      presence: row(1.0),
      timestampUnixMs: 11,
      rotationDegrees: 90,
      mirrored: false,
    );
    expect(session.dropCount, 2);
    expect(session.frame?.timestampUnixMs, 11);
    expect(session.frame?.points[0].x, 0.9);
    expect(session.frame?.points[0].y, 0.2);
    expect(session.frame?.points[0].visibility, 0.0);
  });

  test('release clears the frame before a failing stop', () async {
    final MovementVisionSession session = await hold(
      timestampUnixMs: 4,
      stop: () async {
        throw PlatformException(code: 'unavailable');
      },
    );
    await session.release();
    expect(session.frame, isNull);
    expect(session.dropCount, 0);
  });

  test('releaseInstalled is a no-op when the slot is empty', () async {
    expect(MovementVisionSession.installed, isNull);
    await MovementVisionSession.releaseInstalled();
    expect(MovementVisionSession.installed, isNull);
  });

  test(
    'start is unavailable and stop succeeds on the method channel',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MovementVision.channel, (
            MethodCall call,
          ) async {
            if (call.method == 'start') {
              throw PlatformException(code: 'unavailable');
            }
            if (call.method == 'stop') {
              return null;
            }
            throw PlatformException(code: 'missing');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MovementVision.channel, null);
      });

      await expectLater(
        MovementVision.start(),
        throwsA(
          isA<PlatformException>().having(
            (PlatformException error) => error.code,
            'code',
            'unavailable',
          ),
        ),
      );

      final MovementVisionSession session = MovementVisionSession();
      MovementVisionSession.install(session);
      await session.accept(
        x: row(0.5),
        y: row(0.5),
        z: row(0.0),
        visibility: row(1.0),
        presence: row(1.0),
        timestampUnixMs: 3,
        rotationDegrees: 0,
        mirrored: false,
      );
      await MovementVisionSession.releaseInstalled();
      expect(session.frame, isNull);
      expect(MovementVisionSession.installed, isNull);
    },
  );
}
