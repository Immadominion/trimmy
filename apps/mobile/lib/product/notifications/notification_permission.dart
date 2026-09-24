import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../onboarding/onboarding_models.dart';

abstract final class ProductNotificationPermission {
  static const _channel = MethodChannel('com.trimmy.trimmy/notifications');

  static Future<OnboardingNotificationStatus> request() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
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
}
