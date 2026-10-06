import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:helpmemove/workout/camera_guidance.dart';

/// A camera the host may open. Tests can build this without a device.
class PreviewCamera {
  const PreviewCamera({required this.back});

  final bool back;
}

/// A live preview and the close that belongs to that attempt only.
class BoundPreview {
  const BoundPreview(this.preview, this.close);

  final Widget preview;
  final Future<void> Function() close;
}

class _DeviceCamera extends PreviewCamera {
  _DeviceCamera(this.description)
    : super(back: description.lensDirection == CameraLensDirection.back);

  final CameraDescription description;
}

/// Device preview. Audio stays off. No still, no recording, and no frame stream.
class DeviceCameraPreviewHost implements CameraPreviewHost {
  DeviceCameraPreviewHost({
    Future<List<PreviewCamera>> Function()? listCameras,
    Future<BoundPreview> Function(PreviewCamera camera)? bindPreview,
  }) : _listCameras = listCameras ?? _listDeviceCameras,
       _bindPreview = bindPreview ?? _bindDeviceCamera;

  final Future<List<PreviewCamera>> Function() _listCameras;
  final Future<BoundPreview> Function(PreviewCamera camera) _bindPreview;

  /// One queue for every host. CameraX dispose releases the shared preview.
  static Future<void> _platformTail = Future<void>.value();

  int _attempt = 0;
  BoundPreview? _bound;

  bool _current(int attempt) => attempt == _attempt;

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final Completer<T> done = Completer<T>();
    _platformTail = _platformTail.catchError((Object _) {}).then((_) async {
      try {
        done.complete(await action());
      } on Object catch (error, stackTrace) {
        done.completeError(error, stackTrace);
      }
    });
    return done.future;
  }

  @override
  Future<CameraOpenResult> open() {
    final int attempt = ++_attempt;
    return _serialize(() => _openAttempt(attempt));
  }

  Future<CameraOpenResult> _openAttempt(int attempt) async {
    if (!_current(attempt)) {
      return const CameraOpenUnavailable();
    }
    await _dropBound();
    if (!_current(attempt)) {
      return const CameraOpenUnavailable();
    }
    try {
      final List<PreviewCamera> cameras = await _listCameras();
      if (!_current(attempt)) {
        return const CameraOpenUnavailable();
      }
      if (cameras.isEmpty) {
        return const CameraOpenUnavailable();
      }
      PreviewCamera chosen = cameras.first;
      for (final PreviewCamera camera in cameras) {
        if (camera.back) {
          chosen = camera;
          break;
        }
      }
      if (!_current(attempt)) {
        return const CameraOpenUnavailable();
      }
      final BoundPreview bound = await _bindPreview(chosen);
      if (!_current(attempt)) {
        await bound.close();
        return const CameraOpenUnavailable();
      }
      _bound = bound;
      return CameraOpened(bound.preview);
    } on CameraException {
      await _dropIfCurrent(attempt);
      return const CameraOpenUnavailable();
    } on Object {
      await _dropIfCurrent(attempt);
      return const CameraOpenUnavailable();
    }
  }

  @override
  Future<void> close() {
    _attempt += 1;
    return _serialize(_dropBound);
  }

  Future<void> _dropIfCurrent(int attempt) async {
    if (_current(attempt)) {
      await _dropBound();
    }
  }

  Future<void> _dropBound() async {
    final BoundPreview? bound = _bound;
    _bound = null;
    if (bound == null) {
      return;
    }
    await bound.close();
  }
}

Future<List<PreviewCamera>> _listDeviceCameras() async {
  final List<CameraDescription> cameras = await availableCameras();
  if (cameras.isEmpty) {
    return const <PreviewCamera>[];
  }
  return <PreviewCamera>[
    for (final CameraDescription camera in cameras) _DeviceCamera(camera),
  ];
}

Future<BoundPreview> _bindDeviceCamera(PreviewCamera camera) async {
  if (camera is! _DeviceCamera) {
    throw StateError('device preview');
  }
  final CameraController controller = CameraController(
    camera.description,
    ResolutionPreset.medium,
    enableAudio: false,
  );
  try {
    await controller.initialize();
    if (!controller.value.isInitialized) {
      throw StateError('preview not initialized');
    }
  } on Object {
    await controller.dispose();
    rethrow;
  }
  return BoundPreview(CameraPreview(controller), controller.dispose);
}

/// Owns one device host for the life of this route state.
class CameraGuidanceRoute extends StatefulWidget {
  const CameraGuidanceRoute({super.key, required this.onLeave, this.host});

  final VoidCallback onLeave;
  final CameraPreviewHost? host;

  @override
  State<CameraGuidanceRoute> createState() => _CameraGuidanceRouteState();
}

class _CameraGuidanceRouteState extends State<CameraGuidanceRoute> {
  CameraPreviewHost? _owned;

  @override
  void initState() {
    super.initState();
    if (widget.host == null) {
      _owned = DeviceCameraPreviewHost();
    }
  }

  @override
  void dispose() {
    final CameraPreviewHost? owned = _owned;
    _owned = null;
    if (owned != null) {
      unawaited(owned.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CameraGuidance(
      host: widget.host ?? _owned!,
      onLeave: widget.onLeave,
    );
  }
}
