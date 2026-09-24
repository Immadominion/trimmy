import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/core/device_time_zone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    MethodChannelDeviceTimeZoneProvider.channelName,
  );
  const provider = MethodChannelDeviceTimeZoneProvider(channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reads a named IANA time zone through the native channel', () async {
    MethodCall? receivedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return 'Africa/Lagos';
    });

    expect(await provider.currentIanaTimeZoneId(), 'Africa/Lagos');
    expect(receivedCall?.method, 'getTimeZoneId');
    expect(receivedCall?.arguments, isNull);
  });

  test('accepts named zones with multiple components', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => 'America/Argentina/Buenos_Aires',
    );

    expect(
      await provider.currentIanaTimeZoneId(),
      'America/Argentina/Buenos_Aires',
    );
  });

  test('accepts UTC and canonicalizes the exact GMT alias', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'UTC');
    expect(await provider.currentIanaTimeZoneId(), 'UTC');

    messenger.setMockMethodCallHandler(channel, (_) async => 'GMT');
    expect(await provider.currentIanaTimeZoneId(), 'UTC');
  });

  test('rejects abbreviations, offsets and malformed native values', () async {
    final rejected = <Object?>[
      null,
      60,
      '',
      'WAT',
      '+01:00',
      'GMT+01:00',
      ' Africa/Lagos',
      'Africa/Lagos ',
      'Africa//Lagos',
      'Africa/../Lagos',
      'Africa/Lag os',
    ];

    for (final value in rejected) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      expect(
        await provider.currentIanaTimeZoneId(),
        isNull,
        reason: 'The native value $value must fail closed.',
      );
    }
  });

  test('fails closed when the platform channel is unavailable', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );

    expect(await provider.currentIanaTimeZoneId(), isNull);
  });

  test(
    'fails closed when the native implementation reports an error',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'TIME_ZONE_UNAVAILABLE'),
      );

      expect(await provider.currentIanaTimeZoneId(), isNull);
    },
  );
}
