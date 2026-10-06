import Flutter
import UIKit

public class MovementVisionPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "helpmemove/movement_vision",
      binaryMessenger: registrar.messenger()
    )
    let instance = MovementVisionPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      result(
        FlutterError(
          code: "unavailable",
          message: "Live pose capture is not available.",
          details: nil
        )
      )
    case "stop":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
