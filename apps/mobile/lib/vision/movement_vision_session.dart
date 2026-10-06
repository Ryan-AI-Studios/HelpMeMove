import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:movement_vision/movement_vision.dart';

/// One normalized pose frame for the process. No image and no camera.
class MovementVisionSession {
  MovementVisionSession({Future<void> Function()? stop})
    : _stop = stop ?? MovementVision.stop;

  static MovementVisionSession? _installed;

  final Future<void> Function() _stop;
  PoseFrame? _frame;
  int _dropCount = 0;

  PoseFrame? get frame => _frame;

  int get dropCount => _dropCount;

  static MovementVisionSession? get installed => _installed;

  static void install(MovementVisionSession session) {
    _installed = session;
  }

  /// Clears the process-wide slot. An empty slot does nothing.
  static Future<void> releaseInstalled() {
    final MovementVisionSession? session = _installed;
    _installed = null;
    if (session == null) {
      return Future<void>.value();
    }
    return session.release();
  }

  Future<void> accept({
    required List<double> x,
    required List<double> y,
    required List<double> z,
    required List<double> visibility,
    required List<double> presence,
    required int timestampUnixMs,
    required int rotationDegrees,
    required bool mirrored,
  }) async {
    final PoseFrame next = acceptPoseFrame(
      x: x,
      y: y,
      z: z,
      visibility: visibility,
      presence: presence,
      timestampUnixMs: timestampUnixMs,
      rotationDegrees: rotationDegrees,
      mirrored: mirrored,
    );
    final PoseFrame? held = _frame;
    if (held != null && next.timestampUnixMs <= held.timestampUnixMs) {
      _dropCount += 1;
      return;
    }
    _frame = next;
  }

  /// Drops the frame before stop. A stop failure does not restore it.
  Future<void> release() async {
    _frame = null;
    _dropCount = 0;
    try {
      await _stop();
    } on Object {
      // The frame stays cleared.
    }
  }
}
