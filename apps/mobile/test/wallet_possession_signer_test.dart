import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/account/config.dart';
import 'package:trimmy/account/privy_auth.dart';
import 'package:trimmy/account/wallet_possession_models.dart';
import 'package:trimmy/account/wallet_possession_signer.dart';

const subject = 'did:privy:signerA';
const anotherSubject = 'did:privy:signerB';
const walletAddress = 'So11111111111111111111111111111111111111112';
const anotherWallet = '11111111111111111111111111111112';
const accountId = '12345678-1234-1234-1234-123456789abc';
const challengeId = 'abcdefab-1234-1234-1234-123456789abc';
final issued = DateTime.utc(2026, 9, 17, 12);
final signatureBytes = List<int>.generate(64, (index) => index);
final nativeSignature = base64.encode(signatureBytes);
// Independently encoded using @solana/kit's base58 decoder for bytes 0..63.
const apiSignature =
    '1GMkH3brNXiNNs1tiFZHu4yZSRrzJwxi5wB9bHFtMinfCXNnR1adh8Vo8NTheK4evneedH4qmvjeqcBBNAefgS';

WalletPossessionChallenge challenge() {
  final expires = issued.add(const Duration(minutes: 5));
  final message = [
    'Trimmy wallet possession',
    'This signature proves you control this wallet for your Trimmy account.',
    'It authorizes no transfer, swap or payment.',
    'challenge: $challengeId',
    'account: $accountId',
    'wallet: $walletAddress',
    'network: mainnet-beta',
    'nonce: ${'ab' * 32}',
    'issued: ${issued.toIso8601String()}',
    'expires: ${expires.toIso8601String()}',
  ].join('\n');
  return WalletPossessionChallenge.fromEnvelope(
    {
      'schemaVersion': 1,
      'challenge': {
        'challengeId': challengeId,
        'walletAddress': walletAddress,
        'network': 'mainnet-beta',
        'message': message,
        'issuedAt': issued.toIso8601String(),
        'expiresAt': expires.toIso8601String(),
      },
    },
    expectedAccountId: accountId,
    expectedWalletAddress: walletAddress,
  );
}

Matcher failure(WalletPossessionFailure value) =>
    isA<WalletPossessionException>().having(
      (error) => error.failure,
      'failure',
      value,
    );

Map<String, Object?> embedded({
  String address = walletAddress,
  String id = 'walletA',
  int index = 0,
}) => {
  'type': 'solanaWallet',
  'id': id,
  'address': address,
  'hdWalletIndex': index,
};

/// The published SDK and real provider execute against fake method channels.
/// Unexpected calls fail, including wallet creation and transaction signing.
class NativeFixture {
  NativeFixture() {
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initializePrivy':
        case 'setPubDevVersion':
          return null;
        case 'getAuthState':
          return currentSubject == null
              ? {'type': 'Unauthenticated'}
              : {
                  'type': 'Authenticated',
                  'user': {'id': currentSubject, 'linkedAccounts': wallets},
                };
        case 'solanaSignMessage':
          return onSign == null ? nativeSignature : await onSign!();
        default:
          fail('Unexpected SDK call: ${call.method}');
      }
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(events, null);
    });
  }

  static const channel = MethodChannel('privy_flutter');
  static const events = MethodChannel('privy_flutter/authState');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  String? currentSubject = subject;
  List<Map<String, Object?>> wallets = [embedded()];
  DateTime now = issued;
  Future<Object?> Function()? onSign;
  late final facade = NativePrivySdkFacade(
    PracticeAccountConfig.parse(
      appId: 'testApp',
      appClientId: 'testClient',
      apiUrl: 'https://api.example.test',
      nativeSupported: true,
    ),
    now: () => now,
  );
  int get signs =>
      calls.where((call) => call.method == 'solanaSignMessage').length;
  Future<String> sign() => facade.signWalletPossession(
    expectedSubject: subject,
    challenge: challenge(),
  );
}

class AuthSdk implements PrivySdkFacade, PrivyWalletSigningFacade {
  final events = StreamController<PrivySdkState>.broadcast(sync: true);
  PrivySdkState current = const PrivySdkState(ready: true, subject: subject);
  Future<String> Function()? onSign;
  int signs = 0;
  @override
  Stream<PrivySdkState> get changes => events.stream;
  @override
  Future<PrivySdkState> readState() async => current;
  @override
  Future<void> logout() async => current = const PrivySdkState(ready: true);
  @override
  Future<PrivySdkLogin> loginWithOAuth(PracticeOAuthProvider provider) async {
    current = const PrivySdkState(ready: true, subject: subject);
    return const PrivySdkLogin.signedIn(subject);
  }

  @override
  Future<String> signWalletPossession({
    required String expectedSubject,
    required WalletPossessionChallenge challenge,
  }) async {
    signs++;
    return onSign == null ? apiSignature : await onSign!();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected auth operation');
}

Future<PrivyPracticeAuth> authenticated(
  AuthSdk sdk, {
  DateTime Function()? now,
}) async {
  final auth = PrivyPracticeAuth(
    appId: 'testApp',
    sdk: sdk,
    now: now ?? () => issued,
  );
  addTearDown(() async {
    await auth.close();
    await sdk.events.close();
  });
  await auth.initialize();
  return auth;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'canonical base64 bytes become canonical base58 including leading zeroes',
    () {
      expect(
        walletPossessionSignatureFromBase64(nativeSignature),
        apiSignature,
      );
      expect(
        walletPossessionSignatureFromBase64(
          base64.encode([...List.filled(63, 0), 1]),
        ),
        '${'1' * 63}2',
      );
    },
  );

  test(
    'malformed, noncanonical and wrong-length native signatures are rejected',
    () {
      for (final value in [
        '',
        '$nativeSignature\n',
        nativeSignature.replaceAll('=', ''),
        base64.encode(List.filled(63, 1)),
        base64.encode(List.filled(65, 1)),
        base64.encode(List.filled(64, 0)),
        nativeSignature.replaceFirst('Pw==', 'Px=='),
        '${'_' * 86}==',
      ]) {
        expect(
          () => walletPossessionSignatureFromBase64(value),
          throwsA(failure(WalletPossessionFailure.invalidSignature)),
        );
      }
    },
  );

  test(
    'real pinned SDK signs exact reviewed bytes with matching existing wallet and one SDK',
    () async {
      final f = NativeFixture();
      expect((await f.facade.readState()).subject, subject);
      expect(await f.sign(), apiSignature);
      final request =
          f.calls
                  .singleWhere((call) => call.method == 'solanaSignMessage')
                  .arguments
              as Map;
      expect(request['walletAddress'], walletAddress);
      expect(
        request['message'],
        base64.encode(utf8.encode(challenge().message)),
      );
      expect(
        f.calls.where((call) => call.method == 'initializePrivy'),
        hasLength(1),
      );
      expect(
        f.calls.every(
          (call) => {
            'initializePrivy',
            'setPubDevVersion',
            'getAuthState',
            'solanaSignMessage',
          }.contains(call.method),
        ),
        isTrue,
      );
    },
  );

  test(
    'native signer rejects missing, mismatched or multiple wallets without signing',
    () async {
      final f = NativeFixture();
      for (final wallets in <List<Map<String, Object?>>>[
        [],
        [embedded(address: anotherWallet)],
        [embedded(), embedded(id: 'duplicate')],
        [embedded(), embedded(address: anotherWallet, id: 'another')],
      ]) {
        f.wallets = wallets;
        await expectLater(
          f.sign(),
          throwsA(
            failure(
              wallets.length == 2
                  ? WalletPossessionFailure.walletAmbiguous
                  : wallets.isEmpty
                  ? WalletPossessionFailure.walletMissing
                  : WalletPossessionFailure.walletMismatch,
            ),
          ),
        );
      }
      expect(f.signs, 0);
    },
  );

  test(
    'linked external wallets do not count as an existing embedded wallet',
    () async {
      final f = NativeFixture()
        ..wallets = [
          {'type': 'wallet', 'address': walletAddress, 'chainType': 'Solana'},
        ];
      await expectLater(
        f.sign(),
        throwsA(failure(WalletPossessionFailure.walletMissing)),
      );
      expect(f.signs, 0);
    },
  );

  test(
    'native signer rejects absent or different user before signing',
    () async {
      final f = NativeFixture()..currentSubject = null;
      await expectLater(
        f.sign(),
        throwsA(failure(WalletPossessionFailure.unauthenticated)),
      );
      f.currentSubject = anotherSubject;
      await expectLater(
        f.sign(),
        throwsA(failure(WalletPossessionFailure.accountMismatch)),
      );
      expect(f.signs, 0);
    },
  );

  test('native signer discards a signature after user changes', () async {
    final f = NativeFixture();
    f.onSign = () async {
      f.currentSubject = anotherSubject;
      return nativeSignature;
    };
    await expectLater(
      f.sign(),
      throwsA(failure(WalletPossessionFailure.accountMismatch)),
    );
    expect(f.signs, 1);
  });

  test(
    'native signer rejects wallet disappearance, ambiguity and identity drift after signing',
    () async {
      final f = NativeFixture();
      for (final change
          in <(List<Map<String, Object?>>, WalletPossessionFailure)>[
            ([], WalletPossessionFailure.walletMissing),
            ([embedded(), embedded()], WalletPossessionFailure.walletAmbiguous),
            (
              [embedded(), embedded(address: anotherWallet, id: 'another')],
              WalletPossessionFailure.walletAmbiguous,
            ),
            (
              [embedded(address: anotherWallet)],
              WalletPossessionFailure.walletMismatch,
            ),
            ([embedded(id: 'changed')], WalletPossessionFailure.walletMismatch),
            ([embedded(index: 1)], WalletPossessionFailure.walletMismatch),
          ]) {
        f.wallets = [embedded()];
        f.onSign = () async {
          f.wallets = change.$1;
          return nativeSignature;
        };
        await expectLater(f.sign(), throwsA(failure(change.$2)));
      }
    },
  );

  test(
    'native signer rejects expired challenge both before and after SDK request',
    () async {
      final f = NativeFixture()..now = challenge().expiresAt;
      await expectLater(
        f.sign(),
        throwsA(failure(WalletPossessionFailure.challengeExpired)),
      );
      expect(f.signs, 0);
      f.now = issued;
      f.onSign = () async {
        f.now = challenge().expiresAt;
        return nativeSignature;
      };
      await expectLater(
        f.sign(),
        throwsA(failure(WalletPossessionFailure.challengeExpired)),
      );
    },
  );

  test(
    'native failure and cancellation are sanitized without provider diagnostics',
    () async {
      final f = NativeFixture();
      f.onSign = () async => throw PlatformException(
        code: 'SOLANA_SIGN_MESSAGE_ERROR',
        message: 'private signature or token',
      );
      await expectLater(
        f.sign(),
        throwsA(failure(WalletPossessionFailure.signatureRejected)),
      );
      f.onSign = () async => throw PlatformException(
        code: 'SOLANA_SIGN_MESSAGE_ERROR',
        message: 'User cancelled',
      );
      await expectLater(
        f.sign(),
        throwsA(failure(WalletPossessionFailure.cancelled)),
      );
    },
  );

  test(
    'native pending request stays exclusive even after its caller times out',
    () async {
      final f = NativeFixture();
      final pending = Completer<Object?>();
      f.onSign = () => pending.future;
      final first = f.sign();
      await expectLater(
        first.timeout(const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        f.sign(),
        throwsA(failure(WalletPossessionFailure.busy)),
      );
      expect(f.signs, 1);
      pending.complete(nativeSignature);
      expect(await first, apiSignature);
      f.onSign = null;
      expect(await f.sign(), apiSignature);
    },
  );

  test('auth capability remains bound to the signed-in subject', () async {
    final sdk = AuthSdk();
    final auth = await authenticated(sdk);
    expect(
      await auth.sign(expectedSubject: subject, challenge: challenge()),
      apiSignature,
    );
    await expectLater(
      auth.sign(expectedSubject: anotherSubject, challenge: challenge()),
      throwsA(failure(WalletPossessionFailure.accountMismatch)),
    );
    expect(sdk.signs, 1);
  });

  test(
    'auth disposal discards an in-flight signature and blocks subsequent requests',
    () async {
      final sdk = AuthSdk();
      final pending = Completer<String>();
      sdk.onSign = () => pending.future;
      final auth = await authenticated(sdk);
      final first = auth.sign(expectedSubject: subject, challenge: challenge());
      await Future<void>.delayed(Duration.zero);
      await auth.close();
      final rejected = expectLater(
        first,
        throwsA(failure(WalletPossessionFailure.closed)),
      );
      pending.complete(apiSignature);
      await rejected;
      await expectLater(
        auth.sign(expectedSubject: subject, challenge: challenge()),
        throwsA(failure(WalletPossessionFailure.closed)),
      );
      expect(sdk.signs, 1);
    },
  );

  test(
    'sign-out discards an in-flight signature without waiting for the signer',
    () async {
      final sdk = AuthSdk();
      final pending = Completer<String>();
      sdk.onSign = () => pending.future;
      final auth = await authenticated(sdk);
      final first = auth.sign(expectedSubject: subject, challenge: challenge());
      await Future<void>.delayed(Duration.zero);
      await auth.signOut();
      final rejected = expectLater(
        first,
        throwsA(failure(WalletPossessionFailure.unauthenticated)),
      );
      pending.complete(apiSignature);
      await rejected;
      expect(auth.state.status, PracticeAuthStatus.signedOut);
    },
  );

  test(
    'sign-out and same-user sign-in cannot revive an older signing result',
    () async {
      final sdk = AuthSdk();
      final pending = Completer<String>();
      sdk.onSign = () => pending.future;
      final auth = await authenticated(sdk);
      final first = auth.sign(expectedSubject: subject, challenge: challenge());
      await Future<void>.delayed(Duration.zero);
      await auth.signOut();
      expect(
        await auth.signInWithOAuth(PracticeOAuthProvider.x),
        PracticeSignInResult.signedIn,
      );
      final rejected = expectLater(
        first,
        throwsA(failure(WalletPossessionFailure.accountMismatch)),
      );
      pending.complete(apiSignature);
      await rejected;
      expect(auth.state.subject, subject);
    },
  );

  test(
    'auth serialization persists after caller timeout and releases on SDK completion',
    () async {
      final sdk = AuthSdk();
      final pending = Completer<String>();
      sdk.onSign = () => pending.future;
      final auth = await authenticated(sdk);
      final first = auth.sign(expectedSubject: subject, challenge: challenge());
      await expectLater(
        first.timeout(const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        auth.sign(expectedSubject: subject, challenge: challenge()),
        throwsA(failure(WalletPossessionFailure.busy)),
      );
      expect(sdk.signs, 1);
      pending.complete(apiSignature);
      expect(await first, apiSignature);
    },
  );

  test(
    'auth catches native subject drift and invalid signatures without exposing raw errors',
    () async {
      final sdk = AuthSdk();
      final auth = await authenticated(sdk);
      sdk.onSign = () async {
        sdk.current = const PrivySdkState(ready: true, subject: anotherSubject);
        return apiSignature;
      };
      await expectLater(
        auth.sign(expectedSubject: subject, challenge: challenge()),
        throwsA(failure(WalletPossessionFailure.accountMismatch)),
      );
      sdk.current = const PrivySdkState(ready: true, subject: subject);
      sdk.onSign = () async => 'not a signature';
      await expectLater(
        auth.sign(expectedSubject: subject, challenge: challenge()),
        throwsA(failure(WalletPossessionFailure.invalidSignature)),
      );
      sdk.onSign = () async => throw StateError('private signature or token');
      await expectLater(
        auth.sign(expectedSubject: subject, challenge: challenge()),
        throwsA(failure(WalletPossessionFailure.unavailable)),
      );
    },
  );
}
