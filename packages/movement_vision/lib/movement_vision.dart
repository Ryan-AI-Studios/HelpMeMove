import 'package:flutter/services.dart';

/// Native pose capture. This build opens no camera.
class MovementVision {
  static const MethodChannel channel = MethodChannel(
    'helpmemove/movement_vision',
  );

  static Future<void> start() {
    return channel.invokeMethod<void>('start');
  }

  static Future<void> stop() {
    return channel.invokeMethod<void>('stop');
  }
}
