import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let deviceTimeZoneChannel = FlutterMethodChannel(
      name: "com.trimmy.trimmy/device_timezone",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    deviceTimeZoneChannel.setMethodCallHandler { call, result in
      guard call.method == "getTimeZoneId" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(TimeZone.current.identifier)
    }
  }
}
