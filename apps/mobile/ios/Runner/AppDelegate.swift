import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var reminders: FlutterMethodChannel?
  private let reminderIds = ["trimmy.checkin.daily", "trimmy.checkin.2", "trimmy.checkin.4", "trimmy.checkin.6"]
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
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
        self.scheduleReminder(preference, result: result)
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

  private func scheduleReminder(_ preference: String, result: @escaping FlutterResult) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: reminderIds)
    if preference == "off" {
      center.removeDeliveredNotifications(withIdentifiers: reminderIds)
      result(true)
      return
    }
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
        DispatchQueue.main.async { result(false) }
        return
      }
      let weekdays: [Int?] = preference == "daily" ? [nil] : [2, 4, 6]
      let group = DispatchGroup()
      let lock = NSLock()
      var failed = false
      for weekday in weekdays {
        var date = DateComponents()
        date.hour = 19
        date.minute = 0
        date.weekday = weekday
        let content = UNMutableNotificationContent()
        content.title = "Your desk is waiting"
        content.body = "Clock in for today's Trimmy challenge."
        content.sound = .default
        content.userInfo = ["trimmy.open_career": true]
        let id = weekday.map { "trimmy.checkin.\($0)" } ?? "trimmy.checkin.daily"
        let request = UNNotificationRequest(identifier: id, content: content,
          trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true))
        group.enter()
        center.add(request) { error in
          if error != nil { lock.lock(); failed = true; lock.unlock() }
          group.leave()
        }
      }
      group.notify(queue: .main) {
        if failed { center.removePendingNotificationRequests(withIdentifiers: self.reminderIds) }
        result(!failed)
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
