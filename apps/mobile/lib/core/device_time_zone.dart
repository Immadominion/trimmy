import 'package:flutter/services.dart';

/// Reads the device's named time zone without falling back to an abbreviation
/// or numeric UTC offset.
abstract interface class DeviceTimeZoneProvider {
  Future<String?> currentIanaTimeZoneId();
}

/// Native device time zone reader used by Career day-boundary requests.
final class MethodChannelDeviceTimeZoneProvider
    implements DeviceTimeZoneProvider {
  const MethodChannelDeviceTimeZoneProvider([
    this._channel = const MethodChannel(channelName),
  ]);

  static const channelName = 'com.trimmy.trimmy/device_timezone';
  static const methodName = 'getTimeZoneId';

  final MethodChannel _channel;

  @override
  Future<String?> currentIanaTimeZoneId() async {
    try {
      final value = await _channel.invokeMethod<Object?>(methodName);
      if (value == 'GMT') return 'UTC';
      return value is String && isIanaTimeZoneId(value) ? value : null;
    } catch (_) {
      // Time zone context improves date boundaries, but a missing or failed
      // platform bridge must not prevent the rest of the app from loading.
      return null;
    }
  }

  /// Performs a conservative shape check. Native APIs remain the authority
  /// for whether a named zone exists on the current operating system.
  static bool isIanaTimeZoneId(String value) {
    if (value == 'UTC') return true;
    if (value.isEmpty || value.length > 255 || value != value.trim()) {
      return false;
    }

    final segments = value.split('/');
    if (segments.length < 2) return false;

    for (final segment in segments) {
      if (!_ianaSegment.hasMatch(segment)) return false;
    }
    return true;
  }

  static final _ianaSegment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$');
}
