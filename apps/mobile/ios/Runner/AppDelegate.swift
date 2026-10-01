import Flutter
import UIKit
import UserNotifications
import firebase_messaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var reminders: FlutterMethodChannel?
  private let reminderIds = ["trimmy.checkin.daily", "trimmy.checkin.2", "trimmy.checkin.4", "trimmy.checkin.6"]
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    // UIScene registers plugins after launch. Configure the notification
    // delegate early; FlutterFire preserves this FlutterAppDelegate and forwards
    // remote messages through it, alongside our local career reminders.
    FLTFirebaseMessagingPlugin.configureNotificationCenterDelegate()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    reminders = FlutterMethodChannel(
      name: "com.trimmy.trimmy/notifications",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    reminders?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      let center = UNUserNotificationCenter.current()
      switch call.method {
      case "requestPermission":
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          DispatchQueue.main.async { result(error == nil ? (granted ? "granted" : "denied") : "unavailable") }
        }
      case "setReminder":
        guard let args = call.arguments as? [String: Any],
          let preference = args["preference"] as? String,
          ["daily", "occasional", "off"].contains(preference) else {
          result(FlutterError(code: "INVALID_FREQUENCY", message: "Choose a reminder frequency.", details: nil))
          return
        }
        self.scheduleReminder(
          preference, at: args["at"] as? NSNumber, title: args["title"] as? String,
          body: args["body"] as? String, result: result)
      case "consumeOpenCareer":
        let pending = UserDefaults.standard.bool(forKey: "trimmy.open_career")
        UserDefaults.standard.removeObject(forKey: "trimmy.open_career")
        result(pending)
      default: result(FlutterMethodNotImplemented)
      }
    }
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

  /// `title` and `body` arrive from Dart in the language chosen in the app.
  /// Without them, the reminder reads in the phone's language.
  private func scheduleReminder(
    _ preference: String, at: NSNumber?, title: String?, body: String?, result: @escaping FlutterResult
  ) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: reminderIds)
    center.removeDeliveredNotifications(withIdentifiers: reminderIds)
    guard preference != "off", let millis = at?.doubleValue,
      millis.isFinite, millis / 1000 > Date().timeIntervalSince1970 else {
      result(true)
      return
    }
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
        DispatchQueue.main.async { result(false) }
        return
      }
      let date = Date(timeIntervalSince1970: millis / 1000)
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
      components.timeZone = calendar.timeZone
      let content = UNMutableNotificationContent()
      content.title = String((title ?? NSLocalizedString(
        "reminder.title", comment: "Title of the workday reminder notification.")).prefix(120))
      content.body = String((body ?? NSLocalizedString(
        "reminder.body", comment: "Body of the workday reminder when no workday title is known.")).prefix(240))
      content.sound = .default
      content.userInfo = ["trimmy.open_career": true]
      let request = UNNotificationRequest(identifier: "trimmy.checkin.daily", content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
      center.add(request) { error in
        DispatchQueue.main.async { result(error == nil) }
      }
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.content.userInfo["trimmy.open_career"] as? Bool == true {
      UserDefaults.standard.set(true, forKey: "trimmy.open_career")
      DispatchQueue.main.async { self.reminders?.invokeMethod("openCareer", arguments: nil) }
      completionHandler()
    } else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.content.userInfo["trimmy.open_career"] as? Bool == true {
      // A person already using Trimmy does not need a check-in interruption.
      completionHandler([])
    } else {
      super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
  }
}
