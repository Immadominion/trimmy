import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/account/server_account_binding.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/coordinator.dart';
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/practice_sync/protocol.dart';

import 'support/account_data_fixtures.dart' as account_data;

const _a = 'aa000000-0000-4000-8000-000000000001';
const _b = 'bb000000-0000-4000-8000-000000000002';
const _didA = 'did:privy:accountA';
const _didB = 'did:privy:accountB';
const _appId = 'public-test-app';
final _api = Uri.parse('https://practice.example');

class _Auth implements PracticeAuth {
  _Auth([this.state = const PracticeAuthState.signedIn(_didA)]);
  @override
  PracticeAuthState state;
  final events = StreamController<PracticeAuthState>.broadcast(sync: true);
  void emit(PracticeAuthState value) {
    state = value;
    events.add(value);
  }

  @override
  Stream<PracticeAuthState> get changes => events.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<PracticeSignInResult> signInWithOAuth(
    PracticeOAuthProvider provider,
  ) async => PracticeSignInResult.signedIn;
  @override
  Future<PracticeEmailCodeResult> sendEmailCode(String email) async =>
      PracticeEmailCodeResult.sent;
  @override
  Future<PracticeSignInResult> signInWithEmailCode({
    required String email,
    required String code,
  }) async => PracticeSignInResult.signedIn;
  @override
  Future<void> signOut() async => emit(const PracticeAuthState.signedOut());
  @override
  Future<String?> accessToken({required String expectedSubject}) async =>
      state.subject == expectedSubject
      ? (expectedSubject == _didA ? 'token-a' : 'token-b')
      : null;
  @override
  Future<void> close() => events.close();
}

class _Store implements PracticeSyncStore {
  final values = <String, String>{};
  final reads = <String>[];
  final writes = <String>[];
  bool failBindingWrite = false;
  Completer<void>? bindingGate, bindingStarted;
  @override
  Future<String?> read(String key) async {
    reads.add(key);
    return values[key];
  }

  @override
  Future<bool> write(String key, String value) async {
    writes.add(key);
    if (key.startsWith('trimmy.server-account-binding.')) {
      final gate = bindingGate;
      bindingGate = null;
      if (gate != null) {
        bindingStarted?.complete();
        await gate.future;
      }
      if (failBindingWrite) return false;
    }
    values[key] = value;
    return true;
  }

  ServerAccountBindingStore bindings({Uri? api, String app = _appId}) =>
      ServerAccountBindingStore(store: this, apiUri: api ?? _api, appId: app);
  PracticeSyncState progress([String account = _a]) => PracticeSyncState.decode(
    values[PracticeSyncCoordinator.storageKeyFor(account)]!,
    accountId: account,
  );
}

class _Timer implements Timer {
  @override
  bool isActive = true;
  @override
  int get tick => 0;
  @override
  void cancel() => isActive = false;
}

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _contextFor(String account) {
  final value =
      jsonDecode(jsonEncode(account_data.contextEnvelope()))
          as Map<String, dynamic>;
  value['userId'] = account;
  return value;
}

Map<String, Object?> _holdingsFor(String account) {
  final value =
      jsonDecode(jsonEncode(account_data.holdingsEnvelope()))
          as Map<String, dynamic>;
  value['userId'] = account;
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
  final requests = <String>[];
  final accountRequests = <String>[];
  final puts = <PracticeMutation>[];
  final receipts = <String, PracticeSnapshot>{};
  final states = <String, PracticeSnapshot>{
    _a: PracticeSnapshot(revision: 0, progress: null, updatedAt: null),
    _b: PracticeSnapshot(revision: 0, progress: null, updatedAt: null),
  };
  bool offline = false, loseReply = false;
  int? sessionStatus;
  String? mappedAccount;
  late final client = MockClient((request) async {
    final account = request.headers['authorization'] == 'Bearer token-a'
        ? _a
        : _b;
    if (request.url.path == '/v1/account/context' ||
        request.url.path == '/v1/account/holdings') {
      accountRequests.add(request.url.path);
      if (offline) throw http.ClientException('Offline test transport');
      return request.url.path == '/v1/account/context'
          ? _json(_contextFor(account))
          : _json(_holdingsFor(account));
    }
    requests.add(request.method);
    if (offline) throw http.ClientException('Offline test transport');
    if (request.method == 'POST') {
      if (sessionStatus case final status?) {
        return _json({
          'error': {
            'code': status == 503
                ? 'PRACTICE_SYNC_UNAVAILABLE'
                : 'PRACTICE_UNAUTHENTICATED',
            'message': 'Unavailable.',
            'requestId': 'test-request',
          },
        }, status);
      }
      return _json({'schemaVersion': 1, 'userId': mappedAccount ?? account});
    }
    if (request.method == 'GET') return _json(states[account]!.toJson());
    final mutation = PracticeMutation.fromJson(jsonDecode(request.body));
    puts.add(mutation);
    final key = '$account:${mutation.mutationId}';
    if (receipts[key] case final receipt?) return _json(receipt.toJson());
    expect(mutation.baseRevision, states[account]!.revision);
    final next = PracticeSnapshot(
      revision: mutation.baseRevision + 1,
      progress: mutation.progress,
      updatedAt: DateTime.utc(2026, 9, 14),
    );
    states[account] = next;
    receipts[key] = next;
    if (loseReply) {
      loseReply = false;
      throw http.ClientException('Reply lost after commit');
    }
    return _json(next.toJson());
  });
}

AccountController _controller(
  _Auth auth,
  _Store store,
  _Server server, {
  Uri? api,
  String appId = _appId,
}) => AccountController(
  auth: auth,
  guestRepository: OfficeProgressRepository(
    read: (_) => null,
    write: (_, _) async => true,
  ),
  store: store,
  httpClient: server.client,
  baseUri: api ?? _api,
  bindingAppId: appId,
  timerFactory: (_, _) => _Timer(),
);

Future<void> _settle() async {
  for (var index = 0; index < 30; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _seed(
  _Store store,
  _Server server, {
  bool uncertain = false,
}) async {
  final auth = _Auth();
  final controller = _controller(auth, store, server);
  await controller.initialize();
  await controller.synchronize();
  await controller.repository.startActivity(OfficeActivityIds.checkTheDate);
  if (uncertain) {
    server.loseReply = true;
    await controller.synchronize();
  }
  controller.dispose();
  await auth.close();
}

void main() {
  test(
    'offline cold reopen preserves queued edits and re-verifies before exact retry',
    () async {
      final store = _Store();
      final server = _Server();
      await _seed(store, server, uncertain: true);
      final pending = store.progress().pending!;
      expect(server.states[_a]!.revision, 1);
      server.requests.clear();
      server.accountRequests.clear();
      server.offline = true;
      final auth = _Auth();
      final controller = _controller(auth, store, server);
      await controller.initialize();
      expect(controller.phase, AccountPhase.active);
      expect(controller.accountId, _a);
      expect(controller.isServerVerified, isFalse);
      expect(controller.portfolioRepository, isNull);
      expect(controller.portfolioState, isNull);
      expect(server.accountRequests, isEmpty);
      expect(controller.repository.state.active!.stage, 0);
      expect(controller.guestRepository.state.active, isNull);
      await controller.repository.advance();
      await controller.synchronize();
      expect(store.progress().local.active!.stage, 1);
      expect(store.progress().pending!.toJson(), pending.toJson());
      expect(server.requests.every((method) => method == 'POST'), isTrue);
      expect(server.accountRequests, isEmpty);
      server.offline = false;
      await controller.retryConnection();
      await controller.portfolioRepository!.whenIdle;
      expect(controller.isServerVerified, isTrue);
      expect(controller.portfolioState!.phase, AccountPortfolioPhase.ready);
      expect(server.accountRequests, [
        '/v1/account/context',
        '/v1/account/holdings',
      ]);
      expect(server.puts[1].toJson(), pending.toJson());
      expect(server.states[_a]!.revision, 1);
      expect(controller.repository.state.active!.stage, 1);
      await controller.synchronize();
      expect(server.states[_a]!.revision, 2);
      expect(server.states[_a]!.progress!.active!.stage, 1);
      controller.dispose();
      await auth.close();
      server.client.close();
    },
  );

  test(
    'a changed server mapping protects the old local account without any progress upload',
    () async {
      final store = _Store();
      final server = _Server();
      await _seed(store, server);
      final bindingKey = store.bindings().keyFor(_didA);
      final bindingBefore = store.values[bindingKey];
      server.offline = true;
      final auth = _Auth();
      final controller = _controller(auth, store, server);
      await controller.initialize();
      await controller.repository.advance();
      final before = store.values[PracticeSyncCoordinator.storageKeyFor(_a)];
      server.offline = false;
      server.mappedAccount = _b;
      server.requests.clear();
      await controller.retryConnection();
      expect(controller.syncStatus, AccountSyncStatus.protected);
      expect(controller.errorCode, 'PRACTICE_BINDING_ACCOUNT_MISMATCH');
      expect(controller.isServerVerified, isFalse);
      expect(controller.accountId, _a);
      expect(server.requests, ['POST']);
      expect(store.values[bindingKey], bindingBefore);
      expect(store.values[PracticeSyncCoordinator.storageKeyFor(_a)], before);
      expect(
        store.values.containsKey(PracticeSyncCoordinator.storageKeyFor(_b)),
        isFalse,
      );
      controller.dispose();
      await auth.close();
      server.client.close();
    },
  );

  test(
    'foreground re-verifies a cached account before fetching progress',
    () async {
      final store = _Store();
      final server = _Server();
      await _seed(store, server);
      server.sessionStatus = 503;
      final auth = _Auth();
      final controller = _controller(auth, store, server);
      await controller.initialize();
      expect(controller.phase, AccountPhase.active);
      expect(controller.isServerVerified, isFalse);
      expect(controller.portfolioRepository, isNull);
      controller.setForeground(false);
      server.sessionStatus = null;
      server.requests.clear();
      server.accountRequests.clear();
      controller.setForeground(true);
      await _settle();
      await controller.portfolioRepository!.whenIdle;
      expect(controller.isServerVerified, isTrue);
      expect(server.requests.first, 'POST');
      expect(server.requests, contains('GET'));
      expect(server.accountRequests, [
        '/v1/account/context',
        '/v1/account/holdings',
      ]);
      expect(controller.portfolioState!.phase, AccountPortfolioPhase.ready);
      controller.dispose();
      await auth.close();
      server.client.close();
    },
  );

  test(
    '401 never permits a cache fallback and signed-out state reads no account data',
    () async {
      final store = _Store();
      final server = _Server();
      await _seed(store, server);
      server.sessionStatus = 401;
      final auth = _Auth();
      final controller = _controller(auth, store, server);
      await controller.initialize();
      expect(controller.phase, AccountPhase.error);
      expect(controller.syncStatus, AccountSyncStatus.loginRequired);
      expect(
        identical(controller.repository, controller.guestRepository),
        isTrue,
      );
      controller.dispose();
      await auth.close();
      store.reads.clear();
      server.requests.clear();
      final signedOut = _Auth(const PracticeAuthState.signedOut());
      final guest = _controller(signedOut, store, server);
      await guest.initialize();
      expect(guest.phase, AccountPhase.guest);
      expect(store.reads, isEmpty);
      expect(server.requests, isEmpty);
      guest.dispose();
      await signedOut.close();
      server.client.close();
    },
  );

  test(
    'corrupt, future and wrong-scope bindings remain protected and untouched',
    () async {
      for (final kind in ['corrupt', 'future', 'wrong-scope']) {
        final store = _Store();
        final server = _Server();
        await _seed(store, server);
        final key = store.bindings().keyFor(_didA);
        final data = jsonDecode(store.values[key]!) as Map<String, dynamic>;
        if (kind == 'future') data['schemaVersion'] = 2;
        if (kind == 'wrong-scope') data['subject'] = _didB;
        store.values[key] = kind == 'corrupt' ? '{broken' : jsonEncode(data);
        final original = Map<String, String>.from(store.values);
        store.writes.clear();
        server.requests.clear();
        final auth = _Auth();
        final controller = _controller(auth, store, server);
        await controller.initialize();
        expect(controller.phase, AccountPhase.error);
        expect(controller.syncStatus, AccountSyncStatus.protected);
        expect(store.values, original);
        expect(store.writes, isEmpty);
        expect(server.requests, isEmpty);
        controller.dispose();
        await auth.close();
        server.client.close();
      }
    },
  );

  test(
    'binding scope includes API origin, public app ID and full SDK subject',
    () async {
      final store = _Store();
      final server = _Server();
      await _seed(store, server);
      final a = store.bindings().keyFor(_didA);
      expect(store.bindings().keyFor(_didB), isNot(a));
      expect(store.bindings(app: 'other-app').keyFor(_didA), isNot(a));
      expect(
        store.bindings(api: Uri.parse('https://other.example')).keyFor(_didA),
        isNot(a),
      );
      expect(
        store
            .bindings(api: Uri.parse('https://practice.example/'))
            .keyFor(_didA),
        a,
      );
      for (final changedApp in [false, true]) {
        server.offline = true;
        final auth = _Auth();
        final controller = _controller(
          auth,
          store,
          server,
          api: changedApp ? _api : Uri.parse('https://other.example'),
          appId: changedApp ? 'other-app' : _appId,
        );
        await controller.initialize();
        expect(controller.phase, AccountPhase.error);
        expect(
          identical(controller.repository, controller.guestRepository),
          isTrue,
        );
        controller.dispose();
        await auth.close();
      }
      expect(
        store.values.values.any((value) => value.contains('token-a')),
        isFalse,
      );
      server.client.close();
    },
  );

  test(
    'a failed first binding acknowledgment does not mount or create an account record',
    () async {
      final store = _Store()..failBindingWrite = true;
      final server = _Server();
      final auth = _Auth();
      final controller = _controller(auth, store, server);
      await controller.initialize();
      expect(controller.phase, AccountPhase.error);
      expect(controller.syncStatus, AccountSyncStatus.protected);
      expect(controller.isServerVerified, isFalse);
      expect(store.values, isEmpty);
      expect(server.requests, ['POST']);
      controller.dispose();
      await auth.close();
      server.client.close();
    },
  );

  test(
    'a late binding acknowledgment cannot mount an obsolete SDK identity',
    () async {
      final store = _Store();
      final server = _Server();
      final auth = _Auth();
      final gate = Completer<void>();
      store.bindingGate = gate;
      store.bindingStarted = Completer<void>();
      final controller = _controller(auth, store, server);
      final initializing = controller.initialize();
      await store.bindingStarted!.future;
      auth.emit(const PracticeAuthState.signedIn(_didB));
      gate.complete();
      await initializing;
      await _settle();
      expect(controller.accountId, _b);
      expect(controller.phase, AccountPhase.active);
      expect(
        store.values.containsKey(PracticeSyncCoordinator.storageKeyFor(_a)),
        isFalse,
      );
      expect(
        store.values.containsKey(PracticeSyncCoordinator.storageKeyFor(_b)),
        isTrue,
      );
      final oldBinding =
          jsonDecode(store.values[store.bindings().keyFor(_didA)]!) as Map;
      final newBinding =
          jsonDecode(store.values[store.bindings().keyFor(_didB)]!) as Map;
      expect(oldBinding['accountId'], _a);
      expect(newBinding['accountId'], _b);
      controller.dispose();
      await auth.close();
      server.client.close();
    },
  );
}
