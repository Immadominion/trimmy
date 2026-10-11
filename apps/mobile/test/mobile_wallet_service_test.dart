import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/mobile_wallet_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.trimmy.trimmy/mobile_wallet');
  const source = '11111111111111111111111111111111';
  final signature = '1' * 64;
  final hash = 'a' * 64;
  final wire = base64Encode(Uint8List(180));
  const service = MethodChannelMobileWalletService(supported: true);
  final calls = <MethodCall>[];
  Object? response;
  String? errorCode;

  setUp(() {
    calls.clear();
    response = null;
    errorCode = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (errorCode != null) {
            throw PlatformException(code: errorCode!, message: 'not exposed');
          }
          return response;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Matcher code(String value) =>
      isA<MobileWalletException>().having((error) => error.code, 'code', value);

  test('unsupported platform never opens a wallet', () async {
    const unsupported = MethodChannelMobileWalletService(supported: false);
    expect(unsupported.available, isFalse);
    await expectLater(
      unsupported.connect(),
      throwsA(code('MOBILE_WALLET_UNSUPPORTED')),
    );
    expect(calls, isEmpty);
  });

  test(
    'connection returns funding identity without exposing auth token',
    () async {
      response = {'address': source, 'label': 'Wallet', 'authToken': 'ignored'};
      final account = await service.connect();
      expect(account.address, source);
      expect(account.label, 'Wallet');
      expect(calls.single.method, 'connect');
    },
  );

  test('invalid connection response is rejected', () async {
    response = {'address': 'not a wallet'};
    await expectLater(
      service.connect(),
      throwsA(code('MOBILE_WALLET_UNAVAILABLE')),
    );
  });

  test('send binds exact expected source and reviewed wire', () async {
    response = {'signature': signature};
    expect(
      await service.signAndSend(address: source, unsignedTransaction: wire),
      signature,
    );
    expect(calls.single.method, 'signAndSend');
    expect(calls.single.arguments, {
      'address': source,
      'unsignedTransaction': wire,
    });
  });

  test('bad or oversized wire never reaches native signing', () async {
    for (final bad in ['%', base64Encode(Uint8List(1233))]) {
      await expectLater(
        service.signAndSend(address: source, unsignedTransaction: bad),
        throwsA(code('MOBILE_WALLET_INVALID_TRANSACTION')),
      );
    }
    expect(calls, isEmpty);
  });

  test('malformed returned signature preserves an uncertain outcome', () async {
    response = {'signature': 'invalid'};
    await expectLater(
      service.signAndSend(address: source, unsignedTransaction: wire),
      throwsA(code('MOBILE_WALLET_OUTCOME_UNKNOWN')),
    );
  });

  test(
    'unknown native send error is never translated into safe cancellation',
    () async {
      errorCode = 'provider_failure';
      await expectLater(
        service.signAndSend(address: source, unsignedTransaction: wire),
        throwsA(code('MOBILE_WALLET_OUTCOME_UNKNOWN')),
      );
    },
  );

  test('native explicit outcome codes are preserved', () async {
    for (final nativeCode in [
      'MOBILE_WALLET_CANCELLED',
      'MOBILE_WALLET_OUTCOME_UNKNOWN',
      'MOBILE_WALLET_BUSY',
    ]) {
      errorCode = nativeCode;
      await expectLater(
        service.signAndSend(address: source, unsignedTransaction: wire),
        throwsA(code(nativeCode)),
      );
    }
  });

  test(
    'process-restored pending operation retains hash and optional signature',
    () async {
      response = {'address': source, 'requestHash': hash};
      final unknown = await service.getPendingOperation();
      expect(unknown!.requestHash, hash);
      expect(unknown.signature, isNull);
      response = {
        'address': source,
        'requestHash': hash,
        'signature': signature,
      };
      expect((await service.getPendingOperation())!.signature, signature);
    },
  );

  test('invalid pending marker fails closed', () async {
    response = {'address': source, 'requestHash': 'bad'};
    await expectLater(
      service.getPendingOperation(),
      throwsA(code('MOBILE_WALLET_OUTCOME_UNKNOWN')),
    );
  });

  test(
    'resolution and explicit acknowledgement target exact operation',
    () async {
      await service.resolvePending(requestHash: hash, signature: signature);
      await service.acknowledgeUnknownOutcome(requestHash: hash);
      await service.disconnect();
      expect(calls.map((call) => call.method), [
        'resolvePending',
        'acknowledgeUnknownOutcome',
        'disconnect',
      ]);
      expect(calls.first.arguments, {
        'requestHash': hash,
        'signature': signature,
      });
      expect(calls[1].arguments, {'requestHash': hash});
    },
  );
}
