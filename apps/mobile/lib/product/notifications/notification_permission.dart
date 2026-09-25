import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../onboarding/onboarding_models.dart';

abstract final class ProductNotificationPermission {
  static const _channel = MethodChannel('com.trimmy.trimmy/notifications');
  static Future<void> _scheduleQueue = Future.value();

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<OnboardingNotificationStatus> request() async {
    if (!_supported) {
      return OnboardingNotificationStatus.unavailable;
    }
    try {
      final value = await _channel.invokeMethod<String>('requestPermission');
      return switch (value) {
        'granted' => OnboardingNotificationStatus.granted,
        'denied' => OnboardingNotificationStatus.denied,
        _ => OnboardingNotificationStatus.unavailable,
      };
    } on PlatformException {
      return OnboardingNotificationStatus.unavailable;
    } on MissingPluginException {
      return OnboardingNotificationStatus.unavailable;
    }
  }

  /// Replaces the device's reminder schedule. This never asks for permission.
  /// Native delivery follows local wall-clock time, including timezone changes.
  static Future<bool> setReminder(String preference) {
    if (!const {'daily', 'occasional', 'off'}.contains(preference)) {
      throw ArgumentError.value(preference, 'preference');
    }
    final result = _scheduleQueue.then((_) async {
      if (!_supported) return preference == 'off';
      try {
        return await _channel.invokeMethod<bool>('setReminder', {
              'preference': preference,
            }) ??
            false;
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return preference == 'off';
      }
    });
    _scheduleQueue = result.then<void>((_) {});
    return result;
  }

  static void setOnOpenCareer(VoidCallback? callback) {
    _channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'openCareer') callback();
            },
    );
  }

  /// Consumes a tap retained before the Flutter navigator was ready.
  static Future<bool> consumeOpenCareer() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('consumeOpenCareer') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
