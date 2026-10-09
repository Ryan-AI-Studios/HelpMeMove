import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var storageChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "helpmemove/storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    storageChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = call.arguments as? String, !path.isEmpty else {
        result(
          FlutterError(
            code: "bad_args",
            message: "excludeFromBackup needs a path",
            details: nil
          )
        )
        return
      }
      do {
        try Self.excludeFromBackup(path)
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "backup",
            message: "Could not exclude local storage from backup",
            details: nil
          )
        )
      }
    }
  }

  private static func excludeFromBackup(_ path: String) throws {
    var root = URL(fileURLWithPath: path)
    var rootValues = URLResourceValues()
    rootValues.isExcludedFromBackup = true
    try root.setResourceValues(rootValues)
    let names = ["helpmemove.db", "helpmemove.db-wal", "helpmemove.db-shm", "sync-copy-accepted", "export.json"]
    for name in names {
      let child = URL(fileURLWithPath: path).appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: child.path) {
        var url = child
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
      }
    }
  }
}
