import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/account/config.dart';
import 'package:trimmy/account/privy_auth.dart';

const subjectA = 'did:privy:accountA';
const subjectB = 'did:privy:accountB';
const appId = 'testApp';
final now = DateTime.utc(2026, 9, 14, 12);

String token({String subject = subjectA, Map<String, Object?>? overrides}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'ES256', 'typ': 'JWT'})}.'
      '${encode({'sub': subject, 'aud': appId, 'iss': 'privy.io', 'iat': now.millisecondsSinceEpoch ~/ 1000 - 5, 'exp': now.millisecondsSinceEpoch ~/ 1000 + 300, 'sid': 'testSession', ...?overrides})}.c3ludGhldGlj';
}

class FakeSdk implements PrivySdkFacade {
  final events = StreamController<PrivySdkState>.broadcast(sync: true);
  PrivySdkState current = const PrivySdkState(ready: true);
  Future<PrivySdkState> Function()? read;
  Future<PrivySdkLogin> Function()? login;
  Future<bool> Function(String)? sendCode;
  Future<PrivySdkLogin> Function(String, String)? codeLogin;
  Future<String?> Function()? tokenRead;
  Future<void> Function()? logOut;
  final providers = <PracticeOAuthProvider>[];
  final sentCodes = <String>[];
  final codeLogins = <(String, String)>[];
  int logins = 0;
  int logouts = 0;
  int tokens = 0;

  @override
  Stream<PrivySdkState> get changes => events.stream;
  @override
  Future<PrivySdkState> readState() async => read == null ? current : read!();
  @override
  Future<PrivySdkLogin> loginWithOAuth(PracticeOAuthProvider provider) async {
    logins++;
    providers.add(provider);
    if (login != null) return login!();
    current = const PrivySdkState(ready: true, subject: subjectA);
    return const PrivySdkLogin.signedIn(subjectA);
  }

  @override
  Future<bool> sendEmailCode(String email) async {
    sentCodes.add(email);
    return sendCode == null ? true : sendCode!(email);
  }

  @override
  Future<PrivySdkLogin> loginWithEmailCode({
    required String email,
    required String code,
  }) async {
    codeLogins.add((email, code));
    if (codeLogin != null) return codeLogin!(email, code);
    current = const PrivySdkState(ready: true, subject: subjectA);
    return const PrivySdkLogin.signedIn(subjectA);
  }

  @override
  Future<void> logout() async {
    logouts++;
    if (logOut != null) return logOut!();
    current = const PrivySdkState(ready: true);
  }

  @override
  Future<String?> accessToken(String expectedSubject) async {
    tokens++;
    return tokenRead == null ? token() : tokenRead!();
  }

  void emit(PrivySdkState state) {
    current = state;
    events.add(state);
  }
}

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configuration disables empty builds and unsupported platforms', () {
    expect(
      PracticeAccountConfig.parse(
        appId: '',
        appClientId: '',
        apiUrl: '',
        nativeSupported: true,
      ).enabled,
      isFalse,
    );
    final web = PracticeAccountConfig.parse(
      appId: appId,
      appClientId: 'testClient',
      apiUrl: 'https://api.example.test',
      nativeSupported: false,
    );
    expect(web.enabled, isFalse);
    expect(createPracticeAuth(web), isA<DisabledPracticeAuth>());
  });

  test('configuration rejects partial, credentials, paths and unsafe URLs', () {
    for (final bad in [
      '',
      'http://api.example.test',
      'http://localhost:3000',
      'https://name:password@example.test',
      'https://example.test/path',
      'https://example.test?token=secret',
      'https://example.test#fragment',
      'https://example.test:0',
      'https://example.test:65536',
      'https://example.test\n',
      '//example.test',
    ]) {
      expect(
        () => PracticeAccountConfig.parse(
          appId: appId,
          appClientId: 'testClient',
          apiUrl: bad,
          nativeSupported: true,
        ),
        throwsA(isA<PracticeConfigurationException>()),
      );
    }
    for (final id in ['', 'bad id', 'test\n', 'x' * 129]) {
      expect(
        () => PracticeAccountConfig.parse(
          appId: id,
          appClientId: 'testClient',
          apiUrl: 'https://api.example.test',
          nativeSupported: true,
        ),
        throwsA(isA<PracticeConfigurationException>()),
      );
    }
    expect(
      PracticeAccountConfig.parse(
        appId: appId,
        appClientId: 'testClient',
        apiUrl: 'http://127.0.0.1:3000',
        nativeSupported: true,
        allowLoopbackForTests: true,
      ).apiUri,
      Uri.parse('http://127.0.0.1:3000'),
    );
  });

  test(
    'initialization restores only a valid SDK DID and emits stable state',
    () async {
      final sdk = FakeSdk()
        ..current = const PrivySdkState(ready: true, subject: subjectA);
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk, now: () => now);
      addTearDown(auth.close);
      final states = <PracticeAuthState>[];
      auth.changes.listen(states.add);
      await Future.wait([auth.initialize(), auth.initialize()]);
      expect(auth.state, const PracticeAuthState.signedIn(subjectA));
      expect(states, [const PracticeAuthState.signedIn(subjectA)]);
      expect(await auth.accessToken(expectedSubject: subjectA), token());
      expect(await auth.accessToken(expectedSubject: subjectB), isNull);
      expect(sdk.tokens, 1);
    },
  );

  test(
    'unverified, invalid and failed initialization cannot return a token',
    () async {
      for (final malformed in [null, 'walletAddress', 'did:privy:bad\n']) {
        final sdk = FakeSdk()
          ..current = PrivySdkState(ready: true, subject: malformed);
        final auth = PrivyPracticeAuth(appId: appId, sdk: sdk, now: () => now);
        await auth.initialize();
        expect(auth.state.subject, isNull);
        expect(await auth.accessToken(expectedSubject: subjectA), isNull);
        await auth.close();
      }
      final sdk = FakeSdk()
        ..read = () async => throw StateError('private SDK text');
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
      await auth.initialize();
      expect(auth.state.status, PracticeAuthStatus.failed);
      await auth.close();
    },
  );

  test('explicit login, cancellation and failure remain distinct', () async {
    final sdk = FakeSdk();
    final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
    addTearDown(auth.close);
    sdk.login = () async => const PrivySdkLogin.cancelled();
    expect(await auth.signInWithX(), PracticeSignInResult.cancelled);
    sdk.login = () async => throw StateError('private SDK text');
    expect(await auth.signInWithX(), PracticeSignInResult.failed);
    sdk.login = null;
    expect(await auth.signInWithX(), PracticeSignInResult.signedIn);
    expect(auth.state.subject, subjectA);
  });

  test(
    'a late login and native event after logout cannot revive the session',
    () async {
      final sdk = FakeSdk();
      final login = Completer<PrivySdkLogin>();
      sdk.login = () => login.future;
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
      addTearDown(auth.close);
      final result = auth.signInWithX();
      await settle();
      await auth.signOut();
      sdk.emit(const PrivySdkState(ready: true, subject: subjectA));
      login.complete(const PrivySdkLogin.signedIn(subjectA));
      expect(await result, PracticeSignInResult.sessionChanged);
      sdk.events.add(sdk.current);
      await settle();
      expect(auth.state.status, PracticeAuthStatus.signedOut);
      expect(await auth.accessToken(expectedSubject: subjectA), isNull);
    },
  );

  test('late restored state after logout and close is ignored', () async {
    for (final close in [false, true]) {
      final read = Completer<PrivySdkState>();
      final sdk = FakeSdk()..read = () => read.future;
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
      final init = auth.initialize();
      if (close) {
        await auth.close();
      } else {
        await auth.signOut();
      }
      read.complete(const PrivySdkState(ready: true, subject: subjectA));
      await init;
      expect(auth.state.subject, isNull);
      await auth.close();
    }
  });

  test(
    'a changed native DID invalidates instead of silently switching accounts',
    () async {
      final sdk = FakeSdk()
        ..current = const PrivySdkState(ready: true, subject: subjectA);
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
      addTearDown(auth.close);
      await auth.initialize();
      sdk.emit(const PrivySdkState(ready: true, subject: subjectB));
      await settle();
      expect(auth.state.status, PracticeAuthStatus.signedOut);
      sdk.emit(const PrivySdkState(ready: true, subject: subjectA));
      await settle();
      expect(auth.state.status, PracticeAuthStatus.signedOut);
    },
  );

  test(
    'token awaits are invalidated by logout, native switch and disposal',
    () async {
      for (final action in ['logout', 'switch', 'close']) {
        final sdk = FakeSdk()
          ..current = const PrivySdkState(ready: true, subject: subjectA);
        final read = Completer<String?>();
        sdk.tokenRead = () => read.future;
        final auth = PrivyPracticeAuth(appId: appId, sdk: sdk, now: () => now);
        await auth.initialize();
        final pending = auth.accessToken(expectedSubject: subjectA);
        await settle();
        switch (action) {
          case 'logout':
            await auth.signOut();
          case 'switch':
            sdk.current = const PrivySdkState(ready: true, subject: subjectB);
          case 'close':
            await auth.close();
        }
        read.complete(token());
        expect(await pending, isNull);
        await auth.close();
      }
    },
  );

  test(
    'wrong or malformed token claims fail the local identity binding',
    () async {
      final sdk = FakeSdk()
        ..current = const PrivySdkState(ready: true, subject: subjectA);
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk, now: () => now);
      addTearDown(auth.close);
      await auth.initialize();
      for (final value in <String?>[
        null,
        '',
        'opaque',
        '${token()}\n',
        token(subject: subjectB),
        token(overrides: {'aud': 'otherApp'}),
        token(overrides: {'iss': 'otherIssuer'}),
        token(overrides: {'sid': null}),
        token(
          overrides: {
            'iat': now.millisecondsSinceEpoch ~/ 1000 - 1000,
            'exp': now.millisecondsSinceEpoch ~/ 1000 - 301,
          },
        ),
        token(overrides: {'exp': now.millisecondsSinceEpoch ~/ 1000 - 10}),
        token(
          overrides: {
            'iat': now.millisecondsSinceEpoch ~/ 1000 + 301,
            'exp': now.millisecondsSinceEpoch ~/ 1000 + 900,
          },
        ),
        token(overrides: {'iat': null}),
      ]) {
        sdk.tokenRead = () async => value;
        expect(await auth.accessToken(expectedSubject: subjectA), isNull);
      }
    },
  );

  test(
    'a device clock a little behind or ahead of the provider still binds',
    () async {
      // A phone one second behind Privy sees a fresh token "from the future";
      // a phone ahead sees one "already expired". Neither may block sync.
      final sdk = FakeSdk()
        ..current = const PrivySdkState(ready: true, subject: subjectA);
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk, now: () => now);
      addTearDown(auth.close);
      await auth.initialize();
      final second = now.millisecondsSinceEpoch ~/ 1000;
      for (final value in <String>[
        token(overrides: {'iat': second + 1}),
        token(overrides: {'iat': second + 299}),
        token(overrides: {'iat': second - 1000, 'exp': second}),
        token(overrides: {'iat': second - 1000, 'exp': second - 299}),
      ]) {
        sdk.tokenRead = () async => value;
        expect(await auth.accessToken(expectedSubject: subjectA), value);
      }
      expect(PrivyPracticeAuth.clockSkewTolerance, const Duration(minutes: 5));
    },
  );

  test(
    'diagnostics narrate transitions and rejections without secrets',
    () async {
      final events = <String>[];
      final sdk = FakeSdk()
        ..current = const PrivySdkState(ready: true, subject: subjectA);
      final auth = PrivyPracticeAuth(
        appId: appId,
        sdk: sdk,
        now: () => now,
        diagnostics: events.add,
      );
      addTearDown(auth.close);
      await auth.initialize();
      final future = token(
        overrides: {
          'iat': now.millisecondsSinceEpoch ~/ 1000 + 301,
          'exp': now.millisecondsSinceEpoch ~/ 1000 + 900,
        },
      );
      sdk.tokenRead = () async => future;
      expect(await auth.accessToken(expectedSubject: subjectA), isNull);
      sdk.tokenRead = () async => null;
      expect(await auth.accessToken(expectedSubject: subjectA), isNull);
      sdk.tokenRead = () async => throw StateError('native detail');
      expect(await auth.accessToken(expectedSubject: subjectA), isNull);
      expect(events, contains('state signedIn subject=true'));
      expect(events, contains('token rejected locally: issued in the future'));
      expect(events, contains('token unavailable from sdk'));
      expect(events, contains('token read threw StateError'));
      for (final event in events) {
        expect(event, isNot(contains(future)));
        expect(event, isNot(contains(subjectA)));
        expect(event, isNot(contains('native detail')));
      }
    },
  );

  test('a throwing diagnostics sink never breaks the adapter', () async {
    final sdk = FakeSdk()
      ..current = const PrivySdkState(ready: true, subject: subjectA)
      ..tokenRead = (() async => token());
    final auth = PrivyPracticeAuth(
      appId: appId,
      sdk: sdk,
      now: () => now,
      diagnostics: (_) => throw StateError('sink broke'),
    );
    addTearDown(auth.close);
    await auth.initialize();
    expect(auth.state.status, PracticeAuthStatus.signedIn);
    expect(await auth.accessToken(expectedSubject: subjectA), token());
  });

  test(
    'failed native logout invalidates first and exposes no SDK text',
    () async {
      final sdk = FakeSdk()
        ..current = const PrivySdkState(ready: true, subject: subjectA)
        ..logOut = () async => throw StateError('private native details');
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
      addTearDown(auth.close);
      await auth.initialize();
      final pending = auth.signOut();
      expect(auth.state.status, PracticeAuthStatus.signedOut);
      await expectLater(
        pending,
        throwsA(
          isA<PracticeAuthException>().having(
            (error) => error.code,
            'code',
            'PRACTICE_SIGN_OUT_FAILED',
          ),
        ),
      );
      expect(await auth.accessToken(expectedSubject: subjectA), isNull);
    },
  );

  test('login success for a different current native DID is denied', () async {
    final sdk = FakeSdk()
      ..login = () async => const PrivySdkLogin.signedIn(subjectA);
    final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
    addTearDown(auth.close);
    await auth.initialize();
    sdk.current = const PrivySdkState(ready: true, subject: subjectB);
    expect(await auth.signInWithX(), PracticeSignInResult.sessionChanged);
    expect(auth.state.subject, isNull);
  });

  test('auth stream error invalidates an outstanding login callback', () async {
    final pending = Completer<PrivySdkLogin>();
    final sdk = FakeSdk()..login = () => pending.future;
    final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
    addTearDown(auth.close);
    final login = auth.signInWithX();
    await settle();
    sdk.events.addError(StateError('private event-channel failure'));
    sdk.current = const PrivySdkState(ready: true, subject: subjectA);
    pending.complete(const PrivySdkLogin.signedIn(subjectA));
    expect(await login, PracticeSignInResult.sessionChanged);
    expect(auth.state.status, PracticeAuthStatus.failed);
  });

  test(
    'published native facade uses OAuth/token APIs with no wallet requests',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('privy_flutter');
      const events = MethodChannel('privy_flutter/authState');
      final calls = <MethodCall>[];
      String? subject;
      String? failure;
      messenger.setMockMethodCallHandler(events, (_) async => null);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getAuthState':
            return subject == null
                ? {'type': 'Unauthenticated'}
                : {
                    'type': 'Authenticated',
                    'user': {'id': subject, 'linkedAccounts': []},
                  };
          case 'oauthLogin':
            if (failure != null) {
              throw PlatformException(
                code: 'OAUTH_LOGIN_ERROR',
                message: failure,
              );
            }
            subject = subjectA;
            return {'id': subject, 'linkedAccounts': []};
          case 'emailSendCode':
            if (failure != null) {
              throw PlatformException(code: 'SEND_OTP_ERROR', message: failure);
            }
            return true;
          case 'emailLoginWithCode':
            if (failure != null) {
              throw PlatformException(code: 'LOGIN_ERROR', message: failure);
            }
            subject = subjectA;
            return {'id': subject, 'linkedAccounts': []};
          case 'getAccessToken':
            return token();
          case 'logout':
            subject = null;
            return null;
          case 'initializePrivy':
          case 'setPubDevVersion':
            return null;
          default:
            fail('Unexpected SDK method: ${call.method}');
        }
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      final facade = NativePrivySdkFacade(
        PracticeAccountConfig.parse(
          appId: appId,
          appClientId: 'testClient',
          apiUrl: 'https://api.example.test',
          nativeSupported: true,
        ),
      );
      expect((await facade.readState()).subject, isNull);
      expect(
        (await facade.loginWithOAuth(PracticeOAuthProvider.x)).subject,
        subjectA,
      );
      expect(await facade.accessToken(subjectA), token());
      expect(await facade.accessToken(subjectB), isNull);
      await facade.logout();
      expect(
        (await facade.loginWithOAuth(PracticeOAuthProvider.apple)).subject,
        subjectA,
      );
      await facade.logout();
      expect(await facade.sendEmailCode('person@example.test'), isTrue);
      expect(
        (await facade.loginWithEmailCode(
          email: 'person@example.test',
          code: '123456',
        )).subject,
        subjectA,
      );
      await facade.logout();
      for (final wording in [
        'User cancelled',
        'OAuth flow cancelled by user',
        'Chrome tab closed by user without completing OAuth',
        'The operation couldn’t be completed. (com.apple.AuthenticationServices.WebAuthenticationSession error 1.)',
      ]) {
        failure = wording;
        expect(
          (await facade.loginWithOAuth(PracticeOAuthProvider.google)).cancelled,
          isTrue,
          reason: wording,
        );
      }
      failure = 'Opaque private provider error';
      expect(
        (await facade.loginWithOAuth(PracticeOAuthProvider.x)).cancelled,
        isFalse,
      );
      expect(await facade.sendEmailCode('person@example.test'), isFalse);
      expect(
        (await facade.loginWithEmailCode(
          email: 'person@example.test',
          code: '123456',
        )).cancelled,
        isFalse,
      );
      final configuration =
          calls
                  .singleWhere((call) => call.method == 'initializePrivy')
                  .arguments
              as Map;
      expect(configuration['logLevel'], 'NONE');
      expect(configuration['disableAutomaticMigration'], isTrue);
      final oauth = calls
          .where((call) => call.method == 'oauthLogin')
          .map((call) => call.arguments as Map)
          .toList();
      expect(oauth.first['provider'], 'twitter');
      expect(oauth.last['provider'], 'twitter');
      expect(oauth[1]['provider'], 'apple');
      expect(oauth[2]['provider'], 'google');
      expect(oauth.map((call) => call['appUrlScheme']).toSet(), {
        PracticeAccountConfig.oauthScheme,
      });
      final email =
          calls.firstWhere((call) => call.method == 'emailSendCode').arguments
              as Map;
      expect(email, {'email': 'person@example.test'});
      final codeLogin =
          calls
                  .firstWhere((call) => call.method == 'emailLoginWithCode')
                  .arguments
              as Map;
      expect(codeLogin, {'email': 'person@example.test', 'code': '123456'});
      expect(
        calls.where((call) => call.method.toLowerCase().contains('wallet')),
        isEmpty,
      );
    },
  );

  test(
    'Google and X forward their provider and share the same session rules',
    () async {
      final sdk = FakeSdk();
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
      addTearDown(auth.close);
      expect(await auth.signInWithGoogle(), PracticeSignInResult.signedIn);
      expect(sdk.providers, [PracticeOAuthProvider.google]);
      expect(auth.state.subject, subjectA);
      // Already signed in: no second browser flow is opened.
      expect(await auth.signInWithX(), PracticeSignInResult.signedIn);
      expect(sdk.providers, [PracticeOAuthProvider.google]);
    },
  );

  test(
    'email code sign-in validates locally, sends once and binds the returned DID',
    () async {
      final sdk = FakeSdk();
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk, now: () => now);
      addTearDown(auth.close);
      expect(
        await auth.sendEmailCode('not an email'),
        PracticeEmailCodeResult.invalidEmail,
      );
      expect(
        await auth.sendEmailCode(' person@example.test '),
        PracticeEmailCodeResult.sent,
      );
      expect(sdk.sentCodes, ['person@example.test']);
      expect(
        await auth.signInWithEmailCode(
          email: 'person@example.test',
          code: 'abc',
        ),
        PracticeSignInResult.failed,
      );
      expect(sdk.codeLogins, isEmpty);
      expect(
        await auth.signInWithEmailCode(
          email: 'person@example.test',
          code: '123 456',
        ),
        PracticeSignInResult.signedIn,
      );
      expect(sdk.codeLogins, [('person@example.test', '123456')]);
      expect(auth.state, const PracticeAuthState.signedIn(subjectA));
      expect(
        await auth.sendEmailCode('person@example.test'),
        PracticeEmailCodeResult.unavailable,
      );
      expect(await auth.accessToken(expectedSubject: subjectA), token());
    },
  );

  test(
    'a rejected or failing email code is a plain failure without a session',
    () async {
      final sdk = FakeSdk()
        ..codeLogin = (_, _) async => const PrivySdkLogin.failed();
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
      addTearDown(auth.close);
      expect(
        await auth.signInWithEmailCode(
          email: 'person@example.test',
          code: '000000',
        ),
        PracticeSignInResult.failed,
      );
      expect(auth.state.status, PracticeAuthStatus.signedOut);
      sdk.sendCode = (_) async => throw StateError('private SDK text');
      expect(
        await auth.sendEmailCode('person@example.test'),
        PracticeEmailCodeResult.failed,
      );
      sdk.codeLogin = (_, _) async => throw StateError('private SDK text');
      expect(
        await auth.signInWithEmailCode(
          email: 'person@example.test',
          code: '000000',
        ),
        PracticeSignInResult.failed,
      );
      expect(await auth.accessToken(expectedSubject: subjectA), isNull);
    },
  );

  test(
    'a late email code completion after logout cannot revive the session',
    () async {
      final sdk = FakeSdk();
      final login = Completer<PrivySdkLogin>();
      sdk.codeLogin = (_, _) => login.future;
      final auth = PrivyPracticeAuth(appId: appId, sdk: sdk);
      addTearDown(auth.close);
      final result = auth.signInWithEmailCode(
        email: 'person@example.test',
        code: '123456',
      );
      await settle();
      await auth.signOut();
      sdk.emit(const PrivySdkState(ready: true, subject: subjectA));
      login.complete(const PrivySdkLogin.signedIn(subjectA));
      expect(await result, PracticeSignInResult.sessionChanged);
      expect(auth.state.status, PracticeAuthStatus.signedOut);
      expect(await auth.accessToken(expectedSubject: subjectA), isNull);
    },
  );

  test('email and code normalization is bounded and conservative', () {
    expect(
      normalizePracticeEmail('Person@Example.test'),
      'Person@Example.test',
    );
    for (final bad in [
      '',
      'person',
      '@example.test',
      'person@',
      'person@example',
      'per son@example.test',
      'person@.example.test',
      'person@example..test',
      'a@b\n.c',
      '${'a' * 250}@example.test',
      'person@example.test,other@example.test',
    ]) {
      expect(normalizePracticeEmail(bad), isNull, reason: bad);
    }
    expect(normalizePracticeEmailCode(' 123-456 '), '123456');
    for (final bad in ['', '123', '1234567890', 'abc123', '12 34 5x']) {
      expect(normalizePracticeEmailCode(bad), isNull, reason: bad);
    }
  });
}
