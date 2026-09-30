import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/notifications/firebase_trade_push.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  const channel = MethodChannel('plugins.flutter.io/firebase_messaging');
  late FirebaseTradePushDevice device;
  late List<String> calls;
  var authorized = true;
  var appleTokenReady = true;
  var failFcm = false;
  var missingFcm = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    device = FirebaseTradePushDevice();
    calls = [];
    authorized = true;
    appleTokenReady = true;
    failFcm = false;
    missingFcm = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'Messaging#getInitialMessage':
              return null;
            case 'Messaging#requestPermission':
            case 'Messaging#getNotificationSettings':
              return {'authorizationStatus': authorized ? 1 : 0};
            case 'Messaging#setAutoInitEnabled':
              final enabled = (call.arguments as Map)['enabled'] as bool;
              calls.add('autoInit:$enabled');
              return {'isAutoInitEnabled': enabled};
            case 'Messaging#getAPNSToken':
              return {'token': appleTokenReady ? 'apple-test-token' : null};
            case 'Messaging#getToken':
              if (failFcm) throw PlatformException(code: 'unavailable');
              return {'token': missingFcm ? null : 'fcm-test-token'};
            case 'Messaging#deleteToken':
              return null;
            default:
              throw StateError('Unexpected Firebase call: ${call.method}');
          }
        });
  });

  tearDown(() {
    device.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initial cleanup never enrolls or requests permission', () async {
    await device.disable();
    expect(calls, contains('autoInit:false'));
    expect(calls, isNot(contains('autoInit:true')));
    expect(calls, isNot(contains('Messaging#getToken')));
    expect(calls, isNot(contains('Messaging#requestPermission')));
  });

  test('permission denial does not register with Apple or Firebase', () async {
    authorized = false;
    expect(await device.token(askPermission: true), isNull);
    expect(calls, isNot(contains('autoInit:true')));
    expect(calls, isNot(contains('Messaging#getToken')));
  });

  test('iPhone waits for Apple before asking Firebase for a token', () async {
    appleTokenReady = false;
    final result = device.token(askPermission: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, contains('autoInit:true'));
    expect(calls, isNot(contains('Messaging#getToken')));
    appleTokenReady = true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(await result, 'fcm-test-token');
    expect(
      calls.indexOf('Messaging#requestPermission'),
      lessThan(calls.indexOf('autoInit:true')),
    );
  });

  test(
    'Apple registration timeout rolls back without claiming denial',
    () async {
      appleTokenReady = false;
      final assertion = expectLater(
        device.token(askPermission: true),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Couldn’t connect notifications. Please try again.',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await assertion;
      expect(calls, contains('autoInit:false'));
      expect(calls, isNot(contains('Messaging#getToken')));
    },
  );

  test('Firebase failure turns off automatic iPhone registration', () async {
    failFcm = true;
    await expectLater(device.token(askPermission: true), throwsException);
    expect(calls.last, 'autoInit:false');
  });

  test(
    'missing Firebase token is retryable and does not claim OS denial',
    () async {
      missingFcm = true;
      await expectLater(
        device.token(askPermission: true),
        throwsA(isA<FormatException>()),
      );
      expect(calls.last, 'autoInit:false');
    },
  );

  test('Android does not use Apple registration', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await device.token(askPermission: false), 'fcm-test-token');
    expect(calls, isNot(contains('Messaging#getAPNSToken')));
    expect(calls, isNot(contains('autoInit:true')));
    expect(calls, isNot(contains('Messaging#requestPermission')));
  });
}
