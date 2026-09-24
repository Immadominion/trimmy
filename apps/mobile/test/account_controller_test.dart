import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/account/wallet_possession_controller.dart';
import 'package:trimmy/account/wallet_possession_signer.dart';
import 'package:trimmy/account/wallet_setup.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/coordinator.dart';
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/practice_sync/protocol.dart';

import 'support/account_data_fixtures.dart' as account_data;
import 'support/wallet_possession_fakes.dart' show ProofSigner;

const _a = 'aa000000-0000-4000-8000-000000000001';
const _b = 'bb000000-0000-4000-8000-000000000002';
const _guestId = '71000000-0000-4000-8000-000000000001';
const _otherWallet = 'FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';
const _first = OfficeActivityIds.checkTheDate;
final _now = DateTime.utc(2026, 9, 14);
OfficeProgress _started() => OfficeProgress.empty().startActivity(_first);
OfficeProgress _completed() => _started()
    .advance()
    .advance()
    .selectChoice('add-year')
    .submitChoice(_now)
    .closeActivity();
PracticeSnapshot _empty() =>
    PracticeSnapshot(revision: 0, progress: null, updatedAt: null);
PracticeSnapshot _snapshot(int revision, OfficeProgress progress) =>
    PracticeSnapshot(revision: revision, progress: progress, updatedAt: _now);

class _Auth implements PracticeAuth {
  _Auth([this.state = const PracticeAuthState.signedIn('A')]);
  @override
  PracticeAuthState state;
  final events = StreamController<PracticeAuthState>.broadcast(sync: true);
  Future<void> Function()? initializeOverride;
  Future<PracticeSignInResult> Function()? signInOverride;
  Future<String?> Function(String)? tokenOverride;
  int signIns = 0;
  final tokenSubjects = <String>[];
  void emit(PracticeAuthState value) {
    state = value;
    events.add(value);
  }

  @override
  Stream<PracticeAuthState> get changes => events.stream;
  @override
  Future<void> initialize() async {
    await initializeOverride?.call();
  }

  final providers = <PracticeOAuthProvider>[];
  final sentCodes = <String>[];
  final codeLogins = <(String, String)>[];
  PracticeEmailCodeResult sendCodeResult = PracticeEmailCodeResult.sent;
  @override
  Future<PracticeSignInResult> signInWithOAuth(
    PracticeOAuthProvider provider,
  ) async {
    signIns++;
    providers.add(provider);
    return signInOverride == null
        ? PracticeSignInResult.cancelled
        : await signInOverride!();
  }

  @override
  Future<PracticeEmailCodeResult> sendEmailCode(String email) async {
    sentCodes.add(email);
    return sendCodeResult;
  }

  @override
  Future<PracticeSignInResult> signInWithEmailCode({
    required String email,
    required String code,
  }) async {
    signIns++;
    codeLogins.add((email, code));
    return signInOverride == null
        ? PracticeSignInResult.failed
        : await signInOverride!();
  }

  @override
  Future<void> signOut() async => emit(const PracticeAuthState.signedOut());
  @override
  Future<String?> accessToken({required String expectedSubject}) async {
    tokenSubjects.add(expectedSubject);
    if (tokenOverride != null) return tokenOverride!(expectedSubject);
    return state.subject == expectedSubject ? 'token-$expectedSubject' : null;
  }

  @override
  Future<void> close() => events.close();
}

class _Store implements PracticeSyncStore {
  final values = <String, String>{};
  final writes = <String>[];
  int reads = 0;
  bool failNext = false;
  Completer<bool>? nextWrite;
  @override
  Future<String?> read(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<bool> write(String key, String value) async {
    writes.add(value);
    final held = nextWrite;
    nextWrite = null;
    if (held != null && !await held.future) return false;
    if (failNext) {
      failNext = false;
      return false;
    }
    values[key] = value;
    return true;
  }

  PracticeSyncState saved([String account = _a]) => PracticeSyncState.decode(
    values[PracticeSyncCoordinator.storageKeyFor(account)]!,
    accountId: account,
  );
}

class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this.action);
  final Duration delay;
  final void Function() action;
  bool active = true;
  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
  @override
  void cancel() => active = false;
  void fire() {
    if (active) {
      active = false;
      action();
    }
  }
}

class _Timers {
  final all = <_ManualTimer>[];
  Timer create(Duration delay, void Function() action) {
    final timer = _ManualTimer(delay, action);
    all.add(timer);
    return timer;
  }

  List<_ManualTimer> get pending =>
      all.where((timer) => timer.isActive).toList();
  Future<void> fire() async {
    pending.first.fire();
    await _settle();
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
http.Response _error(String code, int status) => _json({
  'error': {
    'code': code,
    'message': 'Request failed.',
    'requestId': 'request-1',
  },
}, status);

Map<String, Object?> _contextFor(
  String account, {
  String wallet = account_data.wallet,
}) {
  final value =
      jsonDecode(jsonEncode(account_data.contextEnvelope()))
          as Map<String, dynamic>;
  value['userId'] = account;
  (value['embeddedSolanaWallet'] as Map<String, dynamic>)['address'] = wallet;
  return value;
}

Map<String, Object?> _holdingsFor(
  String account, {
  String wallet = account_data.wallet,
}) {
  final value =
      jsonDecode(jsonEncode(account_data.holdingsEnvelope()))
          as Map<String, dynamic>;
  value['userId'] = account;
  (value['wallet'] as Map<String, dynamic>)['address'] = wallet;
  final now = DateTime.now().toUtc();
  final observedAt = DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch,
    isUtc: true,
  ).subtract(const Duration(seconds: 1));
  (value['holdings'] as Map<String, dynamic>)['observedAt'] = observedAt
      .toIso8601String();
  return value;
}

class _Server {
  final contextCacheControls = <String?>[];
  final current = <String, PracticeSnapshot>{_a: _empty(), _b: _empty()};
  final requests = <(String, String)>[];
  final accountRequests = <(String, String)>[];
  final puts = <(String, PracticeMutation)>[];
  final receipts = <String, PracticeSnapshot>{};
  Future<http.Response> Function(String)? sessionOverride;
  Future<http.Response> Function(String)? getOverride;
  Future<http.Response> Function(String)? contextOverride;
  Future<http.Response> Function(String)? holdingsOverride;
  Future<http.Response> Function(PracticeMutation)? putOverride;
  Completer<void>? putGate;
  bool loseReply = false;
  late final client = MockClient(handle);
  Future<http.Response> handle(http.Request request) async {
    final account = request.headers['authorization'] == 'Bearer token-A'
        ? _a
        : _b;
    if (request.url.path == '/v1/account/context') {
      contextCacheControls.add(request.headers['cache-control']);
      accountRequests.add((request.url.path, account));
      return contextOverride == null
          ? _json(_contextFor(account))
          : await contextOverride!(account);
    }
    if (request.url.path == '/v1/account/holdings') {
      accountRequests.add((request.url.path, account));
      return holdingsOverride == null
          ? _json(_holdingsFor(account))
          : await holdingsOverride!(account);
    }
    requests.add((request.method, account));
    if (request.url.path == '/v1/practice/session') {
      return sessionOverride == null
          ? _json({'schemaVersion': 1, 'userId': account})
          : await sessionOverride!(account);
    }
    if (request.method == 'GET') {
      return getOverride == null
          ? _json(current[account]!.toJson())
          : await getOverride!(account);
    }
    final mutation = PracticeMutation.fromJson(jsonDecode(request.body));
    puts.add((account, mutation));
    if (putOverride != null) return putOverride!(mutation);
    await putGate?.future;
    final key = '$account:${mutation.mutationId}';
    if (receipts[key] case final receipt?) return _json(receipt.toJson());
    final previous = current[account]!;
    if (previous.revision != mutation.baseRevision) {
      return _json({
        'error': {
          'code': 'PRACTICE_REVISION_CONFLICT',
          'message': 'Changed.',
          'requestId': 'request-1',
        },
        'currentSnapshot': previous.toJson(),
      }, 409);
    }
    if (previous.progress != null) {
      assertPracticeHistoryPreserved(previous.progress!, mutation.progress);
    }
    final committed = _snapshot(previous.revision + 1, mutation.progress);
    current[account] = committed;
    receipts[key] = committed;
    if (loseReply) {
      loseReply = false;
      throw http.ClientException('Reply lost');
    }
    return _json(committed.toJson());
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 24; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Harness {
  _Harness({
    PracticeAuthState? authState,
    OfficeProgress? guestProgress,
    WalletPossessionSigner? walletSigner,
    WalletSetup? walletSetup,
    GuestSessionPort? guestSessions,
  }) {
    auth = _Auth(authState ?? const PracticeAuthState.signedIn('A'));
    guest = OfficeProgressRepository(
      read: (key) => key == OfficeProgressRepository.saveKey
          ? jsonEncode((guestProgress ?? OfficeProgress.empty()).toJson())
          : null,
      write: (_, value) async {
        guestWrites.add(value);
        return true;
      },
    );
    controller = AccountController(
      auth: auth,
      guestRepository: guest,
      store: store,
      httpClient: server.client,
      baseUri: Uri.parse('https://practice.example'),
      timerFactory: timers.create,
      walletSigner: walletSigner,
      walletSetup: walletSetup,
      guestSessions: guestSessions,
    );
  }
  final store = _Store();
  final server = _Server();
  final timers = _Timers();
  final guestWrites = <String>[];
  late final _Auth auth;
  late final OfficeProgressRepository guest;
  late final AccountController controller;
  Future<void> ready() async {
    await controller.initialize();
    await timers.fire();
  }

  Future<void> close() async {
    controller.dispose();
    await auth.close();
    server.client.close();
  }
}

class _WalletSetup implements WalletSetup {
  Future<String> Function()? action;
  final subjects = <String>[];
  @override
  Future<String> ensureSolanaWallet({required String expectedSubject}) async {
    subjects.add(expectedSubject);
    return action == null ? account_data.wallet : await action!();
  }
}

class _GuestSessions implements GuestSessionPort {
  final claims = <String>[];
  Future<void> Function(String)? claimOverride;
  int guestIdCalls = 0;
  int authorizationCalls = 0;

  @override
  Future<void> claimGuestDesk(String verifiedBearer) async {
    claims.add(verifiedBearer);
    await claimOverride?.call(verifiedBearer);
  }

  @override
  Future<String> guestId() async {
    guestIdCalls++;
    return _guestId;
  }

  @override
  Future<PaperAuthorization> paperAuthorization() async {
    authorizationCalls++;
    return const GuestPaperAuthorization(
      'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    );
  }
}

class _RecoverableGuestSessions extends _GuestSessions
    implements GuestSessionRecoveryPort, GuestSessionAccountLifecyclePort {
  int restarts = 0;
  int resumedAfterSignOut = 0;
  Object? restartError;
  GuestSessionFailure? observedFailure;

  @override
  Future<void> startNewGuestDesk({GuestSessionFailure? observedFailure}) async {
    restarts++;
    this.observedFailure = observedFailure;
    if (restartError case final error?) throw error;
  }

  @override
  void resumeGuestAccessAfterSignOut() => resumedAfterSignOut++;
}

void main() {
  test(
    'claims a pending guest desk before provisioning the verified account',
    () async {
      final sequence = <String>[];
      final guests = _GuestSessions()
        ..claimOverride = (_) async {
          sequence.add('claim');
        };
      final h = _Harness(guestSessions: guests);
      addTearDown(h.close);
      h.server.sessionOverride = (account) async {
        sequence.add('session');
        return _json({'schemaVersion': 1, 'userId': account});
      };

      await h.controller.initialize();
      expect(sequence, ['claim', 'session']);
      expect(guests.claims, ['token-A']);
      expect(h.controller.accountId, _a);
      expect(await h.controller.paperPrincipalKey(), _a);
      expect(guests.guestIdCalls, 0);
      expect(
        h.controller.paperAuthorization(),
        completion(isA<PrivyPaperAuthorization>()),
      );
    },
  );

  test(
    'an existing account opens while its unclaimed guest desk stays recoverable',
    () async {
      final guests = _GuestSessions()
        ..claimOverride = (_) async => throw const GuestSessionException(
          GuestSessionFailure.accountAlreadySaved,
        );
      final h = _Harness(guestSessions: guests);
      addTearDown(h.close);

      await h.controller.initialize();
      expect(h.server.requests, [('POST', _a)]);
      expect(h.controller.accountId, _a);
      expect(h.controller.phase, AccountPhase.active);
      expect(h.controller.isServerVerified, isTrue);
      expect(h.controller.hasPreservedGuestDesk, isTrue);
      expect(
        (await h.controller.paperAuthorization()).headerValue,
        'Bearer token-A',
      );

      await h.controller.signOut();
      expect(h.controller.phase, AccountPhase.guest);
      expect(h.controller.accountId, isNull);
      expect(h.controller.hasPreservedGuestDesk, isFalse);
      expect(
        (await h.controller.paperAuthorization()).headerValue,
        'Guest tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      );
      expect(guests.claims, ['token-A']);
      expect(guests.authorizationCalls, 1);
    },
  );

  test(
    'sign-in opens a separate account while an expired guest desk stays preserved',
    () async {
      final guests = _GuestSessions()
        ..claimOverride = (_) async =>
            throw const GuestSessionException(GuestSessionFailure.expired);
      final h = _Harness(guestSessions: guests);
      addTearDown(h.close);

      await h.controller.initialize();
      expect(h.server.requests, [('POST', _a)]);
      expect(h.controller.phase, AccountPhase.active);
      expect(h.controller.accountId, _a);
      expect(h.controller.hasPreservedGuestDesk, isTrue);
      expect(h.controller.hasExpiredGuestDesk, isTrue);
      expect(guests.claims, ['token-A']);

      await h.controller.signOut();
      expect(h.controller.phase, AccountPhase.guest);
      expect(h.controller.hasPreservedGuestDesk, isFalse);
      expect(h.controller.hasExpiredGuestDesk, isFalse);
    },
  );

  test(
    'a preserved guest notice requires the existing account to open',
    () async {
      final guests = _GuestSessions()
        ..claimOverride = (_) async => throw const GuestSessionException(
          GuestSessionFailure.accountAlreadySaved,
        );
      final h = _Harness(guestSessions: guests);
      addTearDown(h.close);
      h.server.sessionOverride = (_) async =>
          _error('PRACTICE_SYNC_UNAVAILABLE', 503);

      await h.controller.initialize();

      expect(h.controller.phase, AccountPhase.error);
      expect(h.controller.accountId, isNull);
      expect(h.controller.hasPreservedGuestDesk, isFalse);
      expect(
        (await h.controller.paperAuthorization()).headerValue,
        'Guest tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      );
    },
  );

  test('all other guest claim failures still block account opening', () async {
    for (final failure in GuestSessionFailure.values.where(
      (value) =>
          value != GuestSessionFailure.accountAlreadySaved &&
          value != GuestSessionFailure.expired,
    )) {
      final guests = _GuestSessions()
        ..claimOverride = (_) async => throw GuestSessionException(failure);
      final h = _Harness(guestSessions: guests);

      await h.controller.initialize();
      expect(h.server.requests, isEmpty, reason: failure.name);
      expect(h.controller.accountId, isNull, reason: failure.name);
      expect(h.controller.phase, AccountPhase.error, reason: failure.name);
      expect(h.controller.hasPreservedGuestDesk, isFalse, reason: failure.name);

      await h.close();
    }
  });

  test(
    'new guest desk replacement is exposed only in resolved guest mode',
    () async {
      final guests = _RecoverableGuestSessions();
      final h = _Harness(
        authState: const PracticeAuthState.signedOut(),
        guestSessions: guests,
      );
      addTearDown(h.close);

      expect(h.controller.canStartNewGuestDesk, isFalse);
      await h.controller.initialize();
      expect(h.controller.phase, AccountPhase.guest);
      expect(h.controller.canStartNewGuestDesk, isTrue);
      await h.controller.startNewGuestDesk();
      expect(guests.restarts, 1);
      expect(guests.observedFailure, isNull);

      h.auth.emit(const PracticeAuthState.signedIn('A'));
      await _settle();
      expect(h.controller.phase, AccountPhase.active);
      expect(h.controller.canStartNewGuestDesk, isFalse);
    },
  );

  test(
    'sign-out releases a successfully claimed guest for fresh access',
    () async {
      final guests = _RecoverableGuestSessions();
      final h = _Harness(guestSessions: guests);
      addTearDown(h.close);

      await h.controller.initialize();
      expect(h.controller.phase, AccountPhase.active);
      expect(guests.claims, ['token-A']);

      await h.controller.signOut();

      expect(h.controller.phase, AccountPhase.guest);
      expect(guests.resumedAfterSignOut, 1);
      expect(
        (await h.controller.paperAuthorization()).headerValue,
        'Guest tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      );
    },
  );

  test(
    'a late existing-account claim result cannot mark a replacement account',
    () async {
      final oldClaim = Completer<void>();
      final guests = _GuestSessions()
        ..claimOverride = (bearer) async {
          if (bearer == 'token-A') return oldClaim.future;
        };
      final h = _Harness(guestSessions: guests);
      addTearDown(h.close);

      final initializing = h.controller.initialize();
      await _settle();
      h.auth.emit(const PracticeAuthState.signedIn('B'));
      await _settle();
      expect(h.controller.accountId, _b);
      expect(h.controller.hasPreservedGuestDesk, isFalse);

      oldClaim.completeError(
        const GuestSessionException(GuestSessionFailure.accountAlreadySaved),
      );
      await initializing;
      expect(h.controller.accountId, _b);
      expect(h.controller.hasPreservedGuestDesk, isFalse);
    },
  );

  test(
    'paper identity refuses unresolved auth phases without creating a guest',
    () async {
      final guests = _GuestSessions();
      final h = _Harness(
        authState: const PracticeAuthState.initializing(),
        guestSessions: guests,
      );
      addTearDown(h.close);

      for (final operation in <Future<Object> Function()>[
        () => h.controller.paperPrincipalKey(),
        () => h.controller.paperAuthorization(),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<GuestSessionException>().having(
              (error) => error.failure,
              'failure',
              GuestSessionFailure.unavailable,
            ),
          ),
        );
      }
      expect(guests.guestIdCalls, 0);
      expect(guests.authorizationCalls, 0);

      await h.controller.initialize();
      h.auth.emit(const PracticeAuthState.signedOut());
      expect(h.controller.phase, AccountPhase.guest);
      expect(await h.controller.paperPrincipalKey(), _guestId);
      expect(guests.guestIdCalls, 1);

      final signIn = Completer<PracticeSignInResult>();
      h.auth.signInOverride = () => signIn.future;
      final connecting = h.controller.signIn(PracticeOAuthProvider.x);
      await _settle();
      expect(h.controller.phase, AccountPhase.connecting);
      await expectLater(
        h.controller.paperPrincipalKey(),
        throwsA(isA<GuestSessionException>()),
      );
      expect(guests.guestIdCalls, 1);
      signIn.complete(PracticeSignInResult.cancelled);
      await connecting;
      expect(h.controller.phase, AccountPhase.guest);

      h.auth.emit(const PracticeAuthState.failed());
      expect(h.controller.phase, AccountPhase.error);
      await expectLater(
        h.controller.paperPrincipalKey(),
        throwsA(isA<GuestSessionException>()),
      );
      expect(guests.guestIdCalls, 1);
    },
  );

  test(
    'wallet setup is explicit and refreshes the server link before showing balances',
    () async {
      final setup = _WalletSetup();
      final h = _Harness(walletSetup: setup);
      addTearDown(h.close);
      var linked = false;
      h.server.contextOverride = (account) async => _json(
        linked
            ? _contextFor(account)
            : {
                ..._contextFor(account),
                'embeddedSolanaWallet': {'status': 'missing'},
              },
      );
      setup.action = () async {
        linked = true;
        return account_data.wallet;
      };
      await h.ready();
      await h.controller.portfolioRepository!.whenIdle;
      expect(setup.subjects, isEmpty);
      expect(
        h.controller.portfolioState!.context!.embeddedSolanaWallet.isCandidate,
        false,
      );
      expect(await h.controller.setUpWallet(), WalletSetupOutcome.ready);
      expect(setup.subjects, ['A']);
      expect(
        h.server.contextCacheControls.where((v) => v == 'no-cache'),
        hasLength(1),
      );
      expect(
        h.controller.portfolioState!.portfolio!.holdings.wallet.address,
        account_data.wallet,
      );
    },
  );

  test('offline and duplicate setup do not invoke the provider', () async {
    final setup = _WalletSetup();
    final gate = Completer<String>();
    setup.action = () => gate.future;
    final h = _Harness(walletSetup: setup);
    addTearDown(h.close);
    await h.ready();
    h.controller.setNetworkAvailable(false);
    expect(await h.controller.setUpWallet(), WalletSetupOutcome.unavailable);
    expect(setup.subjects, isEmpty);
    h.controller.setNetworkAvailable(true);
    await h.controller.portfolioRepository!.whenIdle;
    final first = h.controller.setUpWallet();
    await _settle();
    expect(h.controller.walletSetupBusy, true);
    expect(await h.controller.setUpWallet(), WalletSetupOutcome.unavailable);
    gate.complete(account_data.wallet);
    expect(await first, WalletSetupOutcome.ready);
    expect(setup.subjects, ['A']);
  });

  test(
    'a wallet setup completed after sign-out cannot fetch or expose a wallet',
    () async {
      final setup = _WalletSetup();
      final gate = Completer<String>();
      setup.action = () => gate.future;
      final h = _Harness(walletSetup: setup);
      addTearDown(h.close);
      await h.ready();
      await h.controller.portfolioRepository!.whenIdle;
      final first = h.controller.setUpWallet();
      await _settle();
      await h.controller.signOut();
      h.server.accountRequests.clear();
      gate.complete(account_data.wallet);
      expect(await first, WalletSetupOutcome.accountChanged);
      expect(h.server.accountRequests, isEmpty);
      expect(h.controller.portfolioState, isNull);
    },
  );

  test('an unconfirmed server wallet never becomes a ready setup', () async {
    final h = _Harness(walletSetup: _WalletSetup());
    addTearDown(h.close);
    h.server.contextOverride = (account) async =>
        _json(_contextFor(account, wallet: _otherWallet));
    await h.ready();
    expect(await h.controller.setUpWallet(), WalletSetupOutcome.awaitingServer);
    expect(h.controller.walletSetupBusy, false);
  });

  test(
    'wallet proof mounts only for a verified account and makes no automatic request',
    () async {
      final signer = ProofSigner();
      final h = _Harness(walletSigner: signer);
      addTearDown(h.close);
      expect(h.controller.walletPossessionController, isNull);
      await h.ready();
      final proof = h.controller.walletPossessionController!;
      expect(proof.accountId, _a);
      expect(proof.phase, WalletPossessionPhase.idle);
      expect(signer.messages, isEmpty);
      // Only the existing portfolio context + holdings reads happened at mount.
      await h.controller.portfolioRepository!.whenIdle;
      expect(
        h.server.accountRequests.where((r) => r.$1 == '/v1/account/context'),
        hasLength(1),
      );
      expect(
        h.server.requests.every((r) => r.$1 == 'POST' || r.$1 == 'GET'),
        true,
      );
      h.controller.setForeground(false);
      expect(proof.canStart, false);
      await h.controller.signOut();
      expect(h.controller.walletPossessionController, isNull);
      expect(proof.phase, WalletPossessionPhase.closed);
      expect(signer.messages, isEmpty);
    },
  );

  test(
    'switching accounts replaces and closes the wallet proof controller',
    () async {
      final h = _Harness(walletSigner: ProofSigner());
      addTearDown(h.close);
      await h.ready();
      final first = h.controller.walletPossessionController!;
      h.auth.emit(const PracticeAuthState.signedIn('B'));
      await _settle();
      final second = h.controller.walletPossessionController!;
      expect(first.phase, WalletPossessionPhase.closed);
      expect(second.accountId, _b);
      expect(second, isNot(same(first)));
      expect(second.phase, WalletPossessionPhase.idle);
    },
  );

  test(
    'switching accounts clears invitation pages and retires the old controller',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.ready();
      final first = h.controller.invitationsController!;
      final firstRelationships = h.controller.relationshipsController!;
      expect(first.loaded, isFalse);
      expect(firstRelationships.friendsLoaded, isFalse);

      h.auth.emit(const PracticeAuthState.signedIn('B'));
      await _settle();
      final second = h.controller.invitationsController!;
      final secondRelationships = h.controller.relationshipsController!;
      expect(second, isNot(same(first)));
      expect(secondRelationships, isNot(same(firstRelationships)));
      expect(second.loaded, isFalse);
      expect(secondRelationships.friendsLoaded, isFalse);
      expect(first.invitations, isEmpty);
      expect(first.historyInvitations, isEmpty);
      expect(first.incomingInvitations, isNull);
      expect(firstRelationships.friends, isEmpty);
      expect(firstRelationships.blocks, isEmpty);

      final requestsBeforeOldRead = h.server.requests.length;
      await first.refresh();
      await firstRelationships.refreshFriends();
      expect(h.server.requests, hasLength(requestsBeforeOldRead));

      await h.controller.signOut();
      expect(h.controller.invitationsController, isNull);
      expect(h.controller.relationshipsController, isNull);
      expect(second.invitations, isEmpty);
      expect(second.historyInvitations, isEmpty);
      expect(secondRelationships.friends, isEmpty);
      expect(secondRelationships.blocks, isEmpty);
    },
  );

  test(
    'a rejected version downgrade protects the exact queue without retrying',
    () async {
      final h = _Harness();
      await h.ready();
      h.server.putOverride = (_) async =>
          _error('PRACTICE_VERSION_DOWNGRADE', 409);
      await h.controller.repository.startActivity(_first);
      await h.timers.fire();
      expect(h.controller.syncStatus, AccountSyncStatus.protected);
      expect(h.controller.errorCode, 'PRACTICE_VERSION_DOWNGRADE');
      final pending = h.store.saved().pending!.toJson();
      expect(h.server.puts, hasLength(1));
      expect(h.timers.pending, isEmpty);
      h.controller.setForeground(false);
      h.controller.setForeground(true);
      await h.controller.synchronize();
      expect(h.timers.pending, isEmpty);
      expect(h.server.puts, hasLength(1));
      expect(h.store.saved().pending!.toJson(), pending);
      await h.close();
    },
  );

  test(
    'a verified v3 empty account is clean and allows explicit guest import',
    () async {
      final h = _Harness(guestProgress: _started());
      final oldEmpty = OfficeProgress.fromJson({
        ...OfficeProgress.empty().toJson(),
        'version': 3,
      });
      h.server.current[_a] = _snapshot(1, oldEmpty);
      await h.ready();
      expect(h.controller.syncStatus, AccountSyncStatus.saved);
      expect(h.controller.canImportGuestProgress, isTrue);
      expect(h.server.puts, isEmpty);
      await h.controller.importGuestProgress();
      expect(h.controller.repository.state.wireVersion, 6);
      expect(h.controller.repository.state.active!.activityId, _first);
      await h.timers.fire();
      expect(h.controller.syncStatus, AccountSyncStatus.saved);
      expect(h.server.puts.single.$2.progress.wireVersion, 6);
      await h.close();
    },
  );

  test(
    'guest writes notify only after acknowledgment and never request account credentials',
    () async {
      final auth = _Auth(const PracticeAuthState.signedOut());
      final disk = Completer<bool>();
      final guest = OfficeProgressRepository(
        read: (_) => null,
        write: (_, _) => disk.future,
      );
      final server = _Server();
      final controller = AccountController(
        auth: auth,
        guestRepository: guest,
        store: _Store(),
        httpClient: server.client,
        baseUri: Uri.parse('https://practice.example'),
      );
      await controller.initialize();
      var notifications = 0;
      controller.addListener(() {
        notifications++;
      });
      final save = guest.startActivity(_first);
      await _settle();
      expect(notifications, 0);
      expect(guest.state.active, isNull);
      disk.complete(true);
      await save;
      expect(notifications, 1);
      expect(guest.localRevision, 1);
      expect(controller.repository, same(guest));
      expect(server.requests, isEmpty);
      expect(auth.tokenSubjects, isEmpty);
      controller.dispose();
      await auth.close();
      server.client.close();
    },
  );

  test(
    'server identity resolution mounts a separate account and a remote restore advances navigation epoch',
    () async {
      final h = _Harness(guestProgress: _started());
      h.server.current[_a] = _snapshot(3, _completed());
      await h.controller.initialize();
      expect(h.controller.accountId, _a);
      expect(h.controller.phase, AccountPhase.active);
      expect(h.controller.repository.state.active, isNull);
      expect(h.controller.canImportGuestProgress, isFalse);
      final epoch = h.controller.navigationEpoch;
      await h.timers.fire();
      expect(h.controller.syncStatus, AccountSyncStatus.saved);
      expect(h.controller.repository.state.completions, hasLength(1));
      expect(h.controller.navigationEpoch, epoch + 1);
      expect(h.guest.state.active!.stage, 0);
      expect(h.guestWrites, isEmpty);
      expect(h.server.puts, isEmpty);
      await h.controller.portfolioRepository!.whenIdle;
      expect(h.controller.portfolioState!.phase, AccountPortfolioPhase.ready);
      expect(h.controller.portfolioState!.accountId, _a);
      expect(h.server.accountRequests, [
        ('/v1/account/context', _a),
        ('/v1/account/holdings', _a),
      ]);
      expect(h.auth.tokenSubjects, ['A', 'A', 'A', 'A']);
      await h.close();
    },
  );

  test(
    'portfolio responses for another account or wallet fail closed',
    () async {
      for (final changedWallet in [false, true]) {
        final h = _Harness();
        if (changedWallet) {
          h.server.holdingsOverride = (account) async =>
              _json(_holdingsFor(account, wallet: _otherWallet));
        } else {
          h.server.contextOverride = (_) async => _json(_contextFor(_b));
        }

        await h.controller.initialize();
        final portfolio = h.controller.portfolioRepository!;
        await portfolio.whenIdle;

        expect(portfolio.state.portfolio, isNull);
        expect(
          portfolio.state.phase,
          changedWallet
              ? AccountPortfolioPhase.error
              : AccountPortfolioPhase.accountChanged,
        );
        expect(
          portfolio.state.issue,
          changedWallet
              ? AccountPortfolioIssue.walletChanged
              : AccountPortfolioIssue.accountChanged,
        );
        expect(h.controller.accountId, _a);
        await h.close();
      }
    },
  );

  test(
    'logout closes a held portfolio read and its late response cannot request holdings',
    () async {
      final h = _Harness();
      final context = Completer<http.Response>();
      h.server.contextOverride = (_) => context.future;
      await h.controller.initialize();
      await _settle();
      final oldPortfolio = h.controller.portfolioRepository!;
      expect(oldPortfolio.state.phase, AccountPortfolioPhase.loading);

      await h.controller.signOut();
      expect(h.controller.phase, AccountPhase.guest);
      expect(h.controller.accountId, isNull);
      expect(h.controller.portfolioRepository, isNull);
      expect(h.controller.portfolioState, isNull);
      expect(oldPortfolio.state.phase, AccountPortfolioPhase.closed);
      expect(oldPortfolio.state.portfolio, isNull);

      context.complete(_json(_contextFor(_a)));
      await _settle();
      expect(
        h.server.accountRequests.where(
          (request) => request == ('/v1/account/holdings', _a),
        ),
        isEmpty,
      );
      expect(h.controller.portfolioRepository, isNull);
      await h.close();
    },
  );

  test(
    'authentication failure and controller disposal clear their portfolio',
    () async {
      for (final disposeController in [false, true]) {
        final h = _Harness();
        await h.controller.initialize();
        final portfolio = h.controller.portfolioRepository!;
        await portfolio.whenIdle;
        expect(portfolio.state.phase, AccountPortfolioPhase.ready);

        if (disposeController) {
          h.controller.dispose();
        } else {
          h.auth.emit(const PracticeAuthState.failed());
        }

        expect(h.controller.portfolioRepository, isNull);
        expect(h.controller.portfolioState, isNull);
        expect(portfolio.state.phase, AccountPortfolioPhase.closed);
        expect(portfolio.state.portfolio, isNull);
        if (!disposeController) {
          expect(h.controller.phase, AccountPhase.error);
          expect(h.controller.syncStatus, AccountSyncStatus.loginRequired);
        }
        await h.close();
      }
    },
  );

  test(
    'a portfolio token completed after subject replacement never dispatches for the old account',
    () async {
      final h = _Harness();
      final oldToken = Completer<String?>();
      var subjectACalls = 0;
      h.auth.tokenOverride = (subject) {
        if (subject != 'A') return Future.value('token-B');
        subjectACalls++;
        return subjectACalls == 1 ? Future.value('token-A') : oldToken.future;
      };

      await h.controller.initialize();
      await _settle();
      final oldPortfolio = h.controller.portfolioRepository!;
      expect(subjectACalls, 2);
      expect(
        h.server.accountRequests.where((request) => request.$2 == _a),
        isEmpty,
      );

      h.auth.emit(const PracticeAuthState.signedIn('B'));
      await _settle();
      final newPortfolio = h.controller.portfolioRepository!;
      await newPortfolio.whenIdle;
      expect(h.controller.accountId, _b);
      expect(newPortfolio.state.phase, AccountPortfolioPhase.ready);
      expect(oldPortfolio.state.phase, AccountPortfolioPhase.closed);

      oldToken.complete('token-A');
      await _settle();
      expect(
        h.server.accountRequests.where((request) => request.$2 == _a),
        isEmpty,
      );
      expect(h.controller.portfolioRepository, same(newPortfolio));
      expect(h.controller.portfolioState!.accountId, _b);
      await h.close();
    },
  );

  test('reconnect refreshes the verified portfolio once', () async {
    final h = _Harness();
    await h.controller.initialize();
    await h.controller.portfolioRepository!.whenIdle;
    h.server.accountRequests.clear();

    h.controller.setNetworkAvailable(false);
    expect(h.controller.portfolioState!.phase, AccountPortfolioPhase.offline);
    h.controller.setNetworkAvailable(true);
    final first = h.controller.refreshPortfolio();
    final second = h.controller.refreshPortfolio();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    expect(h.controller.portfolioState!.phase, AccountPortfolioPhase.ready);
    expect(h.server.accountRequests, [
      ('/v1/account/context', _a),
      ('/v1/account/holdings', _a),
    ]);
    await h.close();
  });

  test(
    'cancelled sign-in and a late sign-in result after logout cannot mount an account',
    () async {
      final h = _Harness(authState: const PracticeAuthState.signedOut());
      await h.controller.initialize();
      await h.controller.signIn();
      expect(h.controller.phase, AccountPhase.guest);
      expect(h.server.requests, isEmpty);
      final held = Completer<PracticeSignInResult>();
      h.auth.signInOverride = () => held.future;
      final login = h.controller.signIn();
      await h.controller.signOut();
      h.auth.state = const PracticeAuthState.signedIn('A');
      held.complete(PracticeSignInResult.signedIn);
      await login;
      h.auth.emit(const PracticeAuthState.signedIn('A'));
      await _settle();
      expect(h.controller.phase, AccountPhase.guest);
      expect(h.controller.accountId, isNull);
      expect(h.server.requests, isEmpty);
      await h.close();
    },
  );

  test(
    'late initialization failure cannot unmount a later signed-in account',
    () async {
      final h = _Harness(authState: const PracticeAuthState.initializing());
      final initialization = Completer<void>();
      h.auth.initializeOverride = () => initialization.future;
      final loading = h.controller.initialize();
      h.auth.signInOverride = () async {
        h.auth.emit(const PracticeAuthState.signedIn('B'));
        return PracticeSignInResult.signedIn;
      };
      await h.controller.signIn();
      initialization.completeError(StateError('Late initialization'));
      await loading;
      expect(h.controller.accountId, _b);
      expect(h.controller.phase, AccountPhase.active);
      await h.close();
    },
  );

  test(
    'a delayed server session reply cannot remount the account replaced by a newer auth event',
    () async {
      final h = _Harness();
      final held = Completer<http.Response>();
      h.server.sessionOverride = (account) => account == _a
          ? held.future
          : Future.value(_json({'schemaVersion': 1, 'userId': account}));
      final initializing = h.controller.initialize();
      await _settle();
      h.auth.emit(const PracticeAuthState.signedIn('B'));
      await _settle();
      expect(h.controller.accountId, _b);
      expect(h.controller.phase, AccountPhase.active);
      held.complete(_json({'schemaVersion': 1, 'userId': _a}));
      await initializing;
      expect(h.controller.accountId, _b);
      expect(
        h.store.values.containsKey(PracticeSyncCoordinator.storageKeyFor(_a)),
        isFalse,
      );
      await h.close();
    },
  );

  test(
    'a token resolved after account switch or disposal never dispatches the obsolete HTTP request',
    () async {
      for (final dispose in [false, true]) {
        final h = _Harness();
        final token = Completer<String?>();
        h.auth.tokenOverride = (subject) =>
            subject == 'A' ? token.future : Future.value('token-B');
        final initializing = h.controller.initialize();
        await _settle();
        if (dispose) {
          h.controller.dispose();
        } else {
          h.auth.emit(const PracticeAuthState.signedIn('B'));
        }
        await _settle();
        token.complete('token-A');
        await initializing;
        expect(h.server.requests.where((request) => request.$2 == _a), isEmpty);
        if (!dispose) expect(h.controller.accountId, _b);
        await h.close();
      }
    },
  );

  test(
    'acknowledged edits debounce; held uploads preserve newer local work and schedule one follow-up',
    () async {
      final h = _Harness();
      await h.ready();
      h.store.failNext = true;
      await expectLater(
        h.controller.repository.startActivity(_first),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(h.timers.pending, isEmpty);
      await h.controller.repository.startActivity(_first);
      h.server.putGate = Completer<void>();
      await h.timers.fire();
      expect(h.server.puts, hasLength(1));
      expect(h.controller.syncStatus, AccountSyncStatus.syncing);
      await h.controller.repository.advance();
      expect(h.controller.repository.state.active!.stage, 1);
      expect(h.timers.pending, isEmpty);
      h.server.putGate!.complete();
      await _settle();
      expect(h.server.current[_a]!.progress!.active!.stage, 0);
      expect(h.controller.repository.state.active!.stage, 1);
      expect(h.timers.pending, hasLength(1));
      await h.timers.fire();
      expect(h.server.puts, hasLength(2));
      expect(h.server.current[_a]!.progress!.active!.stage, 1);
      expect(h.controller.syncStatus, AccountSyncStatus.saved);
      expect(h.timers.pending, isEmpty);
      await h.close();
    },
  );

  test(
    'offline retries stop after the finite budget and foreground explicitly restarts it',
    () async {
      final h = _Harness();
      h.server.getOverride = (_) async =>
          _error('PRACTICE_SYNC_UNAVAILABLE', 503);
      await h.controller.initialize();
      await h.timers.fire();
      expect(h.controller.syncStatus, AccountSyncStatus.offline);
      expect(h.timers.pending.single.delay, const Duration(seconds: 1));
      await h.timers.fire();
      expect(h.timers.pending.single.delay, const Duration(seconds: 4));
      await h.timers.fire();
      expect(h.timers.pending, isEmpty);
      expect(
        h.server.requests.where((request) => request.$1 == 'GET'),
        hasLength(3),
      );
      h.controller.setForeground(false);
      await h.controller.repository.startActivity(_first);
      expect(h.timers.pending, isEmpty);
      h.server.getOverride = null;
      h.controller.setForeground(true);
      await h.timers.fire();
      expect(h.controller.syncStatus, AccountSyncStatus.saved);
      expect(h.server.current[_a]!.progress!.active!.stage, 0);
      await h.close();
    },
  );

  test(
    '401 pauses retries while preserving local edits; a refreshed auth event resumes',
    () async {
      final h = _Harness();
      h.server.getOverride = (_) async =>
          _error('PRACTICE_UNAUTHENTICATED', 401);
      await h.controller.initialize();
      await h.timers.fire();
      expect(h.controller.syncStatus, AccountSyncStatus.loginRequired);
      expect(h.timers.pending, isEmpty);
      await h.controller.repository.startActivity(_first);
      expect(h.timers.pending, isEmpty);
      expect(h.store.saved().local.active!.stage, 0);
      h.server.getOverride = null;
      h.auth.emit(const PracticeAuthState.signedIn('A'));
      await h.timers.fire();
      expect(h.controller.syncStatus, AccountSyncStatus.saved);
      expect(h.server.current[_a]!.progress!.active!.stage, 0);
      await h.close();
    },
  );

  test(
    'guest import waits for an empty verified server copy and never happens automatically',
    () async {
      final h = _Harness(guestProgress: _completed());
      await h.controller.initialize();
      expect(h.controller.canImportGuestProgress, isFalse);
      await h.timers.fire();
      expect(h.controller.canImportGuestProgress, isTrue);
      expect(h.controller.repository.state.completions, isEmpty);
      await h.controller.importGuestProgress();
      expect(h.controller.repository.state.completions, hasLength(1));
      expect(h.guest.state.completions, hasLength(1));
      expect(h.guestWrites, isEmpty);
      await h.timers.fire();
      expect(h.server.current[_a]!.progress!.completions, hasLength(1));
      expect(h.controller.canImportGuestProgress, isFalse);
      await expectLater(
        h.controller.importGuestProgress(),
        throwsA(isA<PracticeSyncException>()),
      );
      await h.close();
    },
  );

  test(
    'persisted conflicts allow local work but require explicit reconciliation before uploading',
    () async {
      final h = _Harness();
      h.store.values[PracticeSyncCoordinator.storageKeyFor(
        _a,
      )] = PracticeSyncState(
        accountId: _a,
        local: _started(),
        base: null,
        pending: null,
        conflict: null,
      ).encode();
      h.server.current[_a] = _snapshot(1, _started().advance());
      await h.ready();
      expect(h.controller.syncStatus, AccountSyncStatus.conflict);
      await h.controller.repository.advance();
      await h.controller.repository.advance();
      expect(h.timers.pending, isEmpty);
      expect(h.server.puts, isEmpty);
      expect(h.controller.conflictingProgress!.active!.stage, 1);
      await h.controller.resolveConflict(h.controller.repository.state);
      await h.timers.fire();
      expect(h.controller.syncStatus, AccountSyncStatus.saved);
      expect(h.server.current[_a]!.progress!.active!.stage, 2);
      await h.close();
    },
  );

  test(
    'failed server session can retry without OAuth while future local records stay protected',
    () async {
      final h = _Harness(guestProgress: _started());
      h.server.sessionOverride = (_) async =>
          _error('PRACTICE_SYNC_UNAVAILABLE', 503);
      await h.controller.initialize();
      expect(h.controller.phase, AccountPhase.error);
      expect(h.timers.pending, isEmpty);
      final key = PracticeSyncCoordinator.storageKeyFor(_a);
      h.store.values[key] = '{"schemaVersion":999,"private":"retained"}';
      h.server.sessionOverride = null;
      await h.controller.retryConnection();
      expect(h.controller.syncStatus, AccountSyncStatus.protected);
      expect(h.controller.repository, same(h.guest));
      expect(h.controller.canImportGuestProgress, isFalse);
      expect(h.auth.signIns, 0);
      expect(h.store.values[key], '{"schemaVersion":999,"private":"retained"}');
      expect(h.timers.pending, isEmpty);
      await h.close();
    },
  );

  test(
    'returning to an account waits for its old upload receipt before reopening its record',
    () async {
      final h = _Harness();
      await h.ready();
      await h.controller.repository.startActivity(_first);
      h.server.putGate = Completer<void>();
      await h.timers.fire();
      h.auth.emit(const PracticeAuthState.signedOut());
      h.auth.emit(const PracticeAuthState.signedIn('A'));
      await _settle();
      expect(h.controller.phase, AccountPhase.connecting);
      expect(h.controller.repository, same(h.guest));
      h.server.putGate!.complete();
      await _settle();
      expect(h.controller.phase, AccountPhase.active);
      expect(h.controller.repository.state.active!.stage, 0);
      expect(h.store.saved().pending, isNull);
      await h.timers.fire();
      expect(h.server.puts, hasLength(1));
      await h.close();
    },
  );

  test(
    'returning to an account also waits for a previous initialization disk write',
    () async {
      final h = _Harness();
      final disk = Completer<bool>();
      h.store.nextWrite = disk;
      final initializing = h.controller.initialize();
      await _settle();
      expect(h.store.reads, 1);
      h.auth.emit(const PracticeAuthState.signedOut());
      h.auth.emit(const PracticeAuthState.signedIn('A'));
      await _settle();
      expect(h.store.reads, 1);
      expect(h.controller.phase, AccountPhase.connecting);
      disk.complete(true);
      await initializing;
      await _settle();
      expect(h.store.reads, 2);
      expect(h.store.writes, hasLength(1));
      expect(h.controller.phase, AccountPhase.active);
      await h.close();
    },
  );

  test(
    'an uncertain committed upload retries the same durable mutation through automatic recovery',
    () async {
      final h = _Harness();
      await h.ready();
      await h.controller.repository.startActivity(_first);
      h.server.loseReply = true;
      await h.timers.fire();
      expect(h.controller.syncStatus, AccountSyncStatus.offline);
      final pending = h.store.saved().pending!;
      expect(h.server.current[_a]!.revision, 1);
      await h.timers.fire();
      expect(h.server.puts, hasLength(2));
      expect(h.server.puts.last.$2.toJson(), pending.toJson());
      expect(h.server.current[_a]!.revision, 1);
      expect(h.controller.syncStatus, AccountSyncStatus.saved);
      expect(h.store.saved().pending, isNull);
      await h.close();
    },
  );

  test(
    'provider and email sign-in share the account binding path and report their result',
    () async {
      final h = _Harness(authState: const PracticeAuthState.signedOut());
      await h.controller.initialize();
      expect(h.controller.phase, AccountPhase.guest);
      h.auth.signInOverride = () async {
        h.auth.emit(const PracticeAuthState.signedIn('A'));
        return PracticeSignInResult.signedIn;
      };
      expect(
        await h.controller.signIn(PracticeOAuthProvider.google),
        PracticeSignInResult.signedIn,
      );
      expect(h.auth.providers, [PracticeOAuthProvider.google]);
      expect(h.controller.phase, AccountPhase.active);
      expect(h.controller.accountId, _a);
      await h.controller.signOut();
      expect(h.controller.phase, AccountPhase.guest);
      expect(
        await h.controller.sendEmailCode('person@example.test'),
        PracticeEmailCodeResult.sent,
      );
      expect(h.auth.sentCodes, ['person@example.test']);
      expect(
        h.controller.phase,
        AccountPhase.guest,
        reason: 'Sending a code changes no account state.',
      );
      h.auth.signInOverride = () async => PracticeSignInResult.failed;
      expect(
        await h.controller.signInWithEmailCode(
          email: 'person@example.test',
          code: '000000',
        ),
        PracticeSignInResult.failed,
      );
      expect(h.controller.phase, AccountPhase.guest);
      expect(h.controller.errorCode, 'PRACTICE_SIGN_IN_FAILED');
      h.auth.signInOverride = () async {
        h.auth.emit(const PracticeAuthState.signedIn('A'));
        return PracticeSignInResult.signedIn;
      };
      expect(
        await h.controller.signInWithEmailCode(
          email: 'person@example.test',
          code: '123456',
        ),
        PracticeSignInResult.signedIn,
      );
      expect(h.auth.codeLogins, [
        ('person@example.test', '000000'),
        ('person@example.test', '123456'),
      ]);
      expect(h.controller.phase, AccountPhase.active);
      expect(h.controller.errorCode, isNull);
      await h.close();
    },
  );
}
