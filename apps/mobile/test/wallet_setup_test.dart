import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/config.dart';
import 'package:trimmy/account/privy_auth.dart';
import 'package:trimmy/account/wallet_setup.dart';

const subject = 'did:privy:setupA';
const address = 'So11111111111111111111111111111111111111112';
const channel = MethodChannel('privy_flutter');
const events = MethodChannel('privy_flutter/authState');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late String currentSubject;
  late List<Map<String, Object?>> wallets;
  late List<MethodCall> calls;
  Future<void> Function()? onRefresh;
  Future<void> Function()? onCreate;
  Map<String, Object?> wallet() => {
    'type': 'solanaWallet',
    'id': 'walletA',
    'address': address,
    'hdWalletIndex': 0,
  };
  Map<String, Object?> user() => {
    'id': currentSubject,
    'linkedAccounts': wallets,
  };
  NativePrivySdkFacade facade() => NativePrivySdkFacade(
    PracticeAccountConfig.parse(
      appId: 'testApp',
      appClientId: 'testClient',
      apiUrl: 'https://api.example.test',
      nativeSupported: true,
    ),
  );
  Matcher failure(WalletSetupFailure value) =>
      isA<WalletSetupException>().having((e) => e.failure, 'failure', value);
  setUp(() {
    currentSubject = subject;
    wallets = [];
    calls = [];
    onRefresh = null;
    onCreate = null;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initializePrivy':
        case 'setPubDevVersion':
          return null;
        case 'getAuthState':
          return {'type': 'Authenticated', 'user': user()};
        case 'refreshUser':
          await onRefresh?.call();
          return user();
        case 'createSolanaWallet':
          expect(call.arguments, {'allowAdditional': false});
          await onCreate?.call();
          wallets = [wallet()];
          return wallet();
        default:
          fail('Unexpected native operation ${call.method}');
      }
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test(
    'creates once, verifies the linked wallet and never requests a signature',
    () async {
      final sdk = facade();
      expect(await sdk.ensureSolanaWallet(expectedSubject: subject), address);
      expect(await sdk.ensureSolanaWallet(expectedSubject: subject), address);
      expect(
        calls.where((call) => call.method == 'createSolanaWallet'),
        hasLength(1),
      );
    },
  );

  test(
    'the normal authentication adapter exposes the same wallet capability',
    () async {
      final auth = PrivyPracticeAuth(appId: 'testApp', sdk: facade());
      addTearDown(auth.close);
      await auth.initialize();
      expect(await auth.ensureSolanaWallet(expectedSubject: subject), address);
      expect(
        calls.where((call) => call.method == 'createSolanaWallet'),
        hasLength(1),
      );
    },
  );

  test(
    'refresh discovers an existing wallet and avoids a second creation',
    () async {
      onRefresh = () async {
        wallets = [wallet()];
      };
      expect(
        await facade().ensureSolanaWallet(expectedSubject: subject),
        address,
      );
      expect(
        calls.where((call) => call.method == 'createSolanaWallet'),
        isEmpty,
      );
    },
  );

  test('ambiguous wallets never select the first or create another', () async {
    wallets = [
      wallet(),
      {...wallet(), 'id': 'walletB'},
    ];
    await expectLater(
      facade().ensureSolanaWallet(expectedSubject: subject),
      throwsA(failure(WalletSetupFailure.multipleWallets)),
    );
    expect(calls.where((call) => call.method == 'createSolanaWallet'), isEmpty);
  });

  test(
    'a different current account is refused before native mutation',
    () async {
      currentSubject = 'did:privy:setupB';
      await expectLater(
        facade().ensureSolanaWallet(expectedSubject: subject),
        throwsA(failure(WalletSetupFailure.accountChanged)),
      );
      expect(
        calls.where((call) => call.method == 'createSolanaWallet'),
        isEmpty,
      );
    },
  );

  test('account switching during refresh cannot create a wallet', () async {
    onRefresh = () async {
      currentSubject = 'did:privy:setupB';
    };
    await expectLater(
      facade().ensureSolanaWallet(expectedSubject: subject),
      throwsA(failure(WalletSetupFailure.accountChanged)),
    );
    expect(calls.where((call) => call.method == 'createSolanaWallet'), isEmpty);
  });

  test('a late creation result is discarded after account switching', () async {
    onCreate = () async {
      currentSubject = 'did:privy:setupB';
    };
    await expectLater(
      facade().ensureSolanaWallet(expectedSubject: subject),
      throwsA(failure(WalletSetupFailure.accountChanged)),
    );
  });

  test('concurrent requests cannot create additional wallets', () async {
    final gate = Completer<void>();
    onCreate = () => gate.future;
    final sdk = facade();
    final first = sdk.ensureSolanaWallet(expectedSubject: subject);
    await expectLater(
      sdk.ensureSolanaWallet(expectedSubject: subject),
      throwsA(failure(WalletSetupFailure.busy)),
    );
    gate.complete();
    expect(await first, address);
    expect(
      calls.where((call) => call.method == 'createSolanaWallet'),
      hasLength(1),
    );
  });

  test('provider errors remain retryable and do not leak SDK text', () async {
    onCreate = () async {
      throw PlatformException(
        code: 'network',
        message: 'sensitive provider message',
      );
    };
    final sdk = facade();
    await expectLater(
      sdk.ensureSolanaWallet(expectedSubject: subject),
      throwsA(failure(WalletSetupFailure.unavailable)),
    );
    onCreate = null;
    expect(await sdk.ensureSolanaWallet(expectedSubject: subject), address);
  });
}
