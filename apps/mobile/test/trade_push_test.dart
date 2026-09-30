import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/product/notifications/trade_push.dart';

class Device implements TradePushDevice {
  @override
  String? platform = 'android';
  String? nextToken = 'a' * 24;
  Completer<String?>? pending;
  int prompts = 0, disabled = 0;
  bool revokeFails = false;
  late void Function(Map<String, dynamic>, bool) message;
  late VoidCallback rotate;
  @override
  Future<String?> token({required bool askPermission}) async {
    if (askPermission) prompts++;
    return pending?.future ?? nextToken;
  }

  @override
  Future<void> disable() async {
    disabled++;
    if (revokeFails) throw StateError("native token service unavailable");
  }

  @override
  void listen({
    required VoidCallback onToken,
    required void Function(Map<String, dynamic>, bool) onMessage,
  }) {
    rotate = onToken;
    message = onMessage;
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late Device device;
  late PushIdentity? identity;
  late TradePushController controller;
  late List<http.Request> requests;
  late int opens, foreground;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    device = Device();
    requests = [];
    opens = 0;
    foreground = 0;
    identity = PushIdentity('owner', () async => 'verified-token');
    controller = TradePushController(
      preferences: preferences,
      origin: Uri.parse('https://api.example'),
      identity: () => identity,
      device: device,
      onOpen: () => opens++,
      onForeground: () => foreground++,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(
            request.method == 'GET'
                ? {
                    'tradePush': true,
                    'platforms': ['android'],
                  }
                : {'enabled': request.method == 'PUT'},
          ),
          200,
        );
      }),
    );
    controller.bind();
    await controller.refresh();
  });
  tearDown(() => controller.dispose());
  test(
    'default is off, only explicit opt-in requests permission and persists consent',
    () async {
      expect(controller.available, true);
      expect(controller.enabled, false);
      expect(device.prompts, 0);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      await controller.setEnabled(true);
      expect(controller.enabled, true);
      expect(device.prompts, 1);
      final put = requests.lastWhere((r) => r.method == 'PUT');
      expect(put.headers['authorization'], 'Bearer verified-token');
      expect(jsonDecode(put.body), {'token': 'a' * 24, 'platform': 'android'});
      expect(
        put.url.path,
        matches(RegExp(r'/v1/notifications/devices/[a-f0-9-]{36}$')),
      );
    },
  );
  test('permission denial does not register or claim success', () async {
    device.nextToken = null;
    await controller.setEnabled(true);
    expect(controller.enabled, false);
    expect(controller.error, contains('device settings'));
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
  });
  test(
    'late permission result after account switch cannot opt in the new account',
    () async {
      device.pending = Completer();
      final enabling = controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      identity = PushIdentity('someone-else', () async => 'other-token');
      controller.bind();
      device.pending!.complete('a' * 24);
      await enabling;
      await controller.refresh();
      expect(controller.enabled, false);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    },
  );
  test(
    'logout and login as the same account still cancels a stale permission result',
    () async {
      device.pending = Completer();
      final enabling = controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      identity = null;
      controller.bind();
      identity = PushIdentity('owner', () async => 'new-token');
      controller.bind();
      device.pending!.complete('a' * 24);
      await enabling;
      await controller.refresh();
      expect(controller.enabled, false);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    },
  );
  test(
    'opt-out deletes registration and revokes SDK token; no automatic re-enrollment',
    () async {
      await controller.setEnabled(true);
      final oldPrompts = device.prompts;
      await controller.setEnabled(false);
      await controller.refresh();
      expect(controller.enabled, false);
      expect(requests.last.method, 'DELETE');
      expect(device.disabled, greaterThan(0));
      expect(device.prompts, oldPrompts);
    },
  );
  test(
    'notification taps require matching signed-in account and consent; foreground does not navigate',
    () async {
      final message = {'kind': 'trade_update', 'accountId': 'owner'};
      device.message(message, true);
      expect(opens, 0);
      await controller.setEnabled(true);
      device.message({...message, 'accountId': 'stranger'}, true);
      expect(opens, 0);
      device.message(message, false);
      expect(foreground, 1);
      expect(opens, 0);
      device.message(message, true);
      expect(opens, 1);
      identity = null;
      controller.bind();
      device.message(message, false);
      expect(foreground, 1);
      await controller.refresh();
    },
  );
  test('cold launch notification waits for the matching account', () async {
    await controller.setEnabled(true);
    identity = null;
    controller.bind();
    await controller.refresh();
    device.message({'kind': 'trade_update', 'accountId': 'owner'}, true);
    expect(opens, 0);
    identity = PushIdentity('owner', () async => 'token');
    controller.bind();
    await controller.refresh();
    expect(opens, 1);
  });
  test(
    'permission revoked in system settings disables consent and removes binding',
    () async {
      await controller.setEnabled(true);
      device.nextToken = null;
      await controller.refresh();
      expect(controller.enabled, false);
      expect(requests.last.method, 'DELETE');
    },
  );
  test(
    'native revocation failure cannot hide settings or retain server consent',
    () async {
      await controller.setEnabled(true);
      device.revokeFails = true;
      await controller.setEnabled(false);
      expect(controller.enabled, false);
      expect(requests.last.method, 'DELETE');
      expect(controller.available, true);
      device.revokeFails = false;
      await controller.refresh();
      expect(controller.error, isNull);
    },
  );
}
