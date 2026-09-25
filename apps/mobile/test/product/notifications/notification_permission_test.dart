import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/product/notifications/notification_permission.dart';
import 'package:trimmy/product/onboarding/first_stock_followup.dart';
import 'package:trimmy/product/onboarding/onboarding_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.trimmy.trimmy/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    ProductNotificationPermission.setOnOpenCareer(null);
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'iOS requests native permission rather than reporting unavailable',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'requestPermission');
        return 'granted';
      });
      expect(
        await ProductNotificationPermission.request(),
        OnboardingNotificationStatus.granted,
      );
    },
  );

  test(
    'account sync replaces frequency without prompting and signout cancels',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      final prefs = await SharedPreferences.getInstance();
      await ReminderPreferences.save(
        prefs,
        'a',
        ReminderPreference.daily,
        OnboardingNotificationStatus.denied,
      );
      await ReminderPreferences.save(
        prefs,
        'b',
        ReminderPreference.occasional,
        OnboardingNotificationStatus.granted,
      );
      // OS permission may have been enabled after denial; native rechecks it.
      expect(await ReminderPreferences.sync(prefs, 'a'), isTrue);
      expect(await ReminderPreferences.sync(prefs, 'b'), isTrue);
      expect(await ReminderPreferences.sync(prefs, null), isTrue);
      expect(await ReminderPreferences.sync(prefs, 'unknown'), isTrue);
      expect(calls.map((c) => c.method), everyElement('setReminder'));
      expect(calls.map((c) => (c.arguments as Map)['preference']), [
        'daily',
        'occasional',
        'off',
        'off',
      ]);
    },
  );

  test(
    'rapid profile changes serialize schedules so the latest choice wins',
    () async {
      final first = Completer<bool>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final value = (call.arguments as Map)['preference'] as String;
        calls.add(value);
        return calls.length == 1 ? first.future : true;
      });
      final daily = ProductNotificationPermission.setReminder('daily');
      final off = ProductNotificationPermission.setReminder('off');
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['daily']);
      first.complete(true);
      expect(await daily, isTrue);
      expect(await off, isTrue);
      expect(calls, ['daily', 'off']);
    },
  );

  test('native failures never pretend a reminder is scheduled', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'SCHEDULE_FAILED');
    });
    expect(await ProductNotificationPermission.setReminder('daily'), isFalse);
    expect(await ProductNotificationPermission.consumeOpenCareer(), isFalse);
    expect(
      () => ProductNotificationPermission.setReminder('hourly'),
      throwsArgumentError,
    );
    messenger.setMockMethodCallHandler(channel, null);
    expect(await ProductNotificationPermission.setReminder('daily'), isFalse);
    expect(await ProductNotificationPermission.setReminder('off'), isTrue);
  });

  test(
    'native taps notify the router and cold-start taps can be consumed',
    () async {
      var opened = 0;
      ProductNotificationPermission.setOnOpenCareer(() => opened++);
      final complete = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('openCareer'),
        ),
        (_) => complete.complete(),
      );
      await complete.future;
      expect(opened, 1);
      var pending = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'consumeOpenCareer');
        final result = pending;
        pending = false;
        return result;
      });
      expect(await ProductNotificationPermission.consumeOpenCareer(), isTrue);
      expect(await ProductNotificationPermission.consumeOpenCareer(), isFalse);
    },
  );
}
