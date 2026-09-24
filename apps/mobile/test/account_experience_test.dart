import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/account/account_host.dart';
import 'package:trimmy/account/account_settings.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/account/reconciliation.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/main.dart' as entry;
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/practice_sync/protocol.dart';
import 'package:trimmy/product/app/product_app.dart';

import 'support/account_data_fixtures.dart' as account_data;

const _account = 'aa000000-0000-4000-8000-000000000001';
const _first = OfficeActivityIds.checkTheDate;
final _now = DateTime.utc(2026, 9, 14);
OfficeProgress _started() => OfficeProgress.empty().startActivity(_first);
OfficeProgress _completed({DateTime? at}) => _started()
    .advance()
    .advance()
    .selectChoice('add-year')
    .submitChoice(at ?? _now)
    .closeActivity();

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

class _Auth implements PracticeAuth {
  @override
  PracticeAuthState state = const PracticeAuthState.signedOut();
  final events = StreamController<PracticeAuthState>.broadcast(sync: true);
  void emit(PracticeAuthState next) {
    state = next;
    events.add(next);
  }

  @override
  Stream<PracticeAuthState> get changes => events.stream;
  @override
  Future<void> initialize() async {}
  final providers = <PracticeOAuthProvider>[];
  final sentCodes = <String>[];
  final codeLogins = <(String, String)>[];
  PracticeEmailCodeResult sendCodeResult = PracticeEmailCodeResult.sent;
  bool rejectCode = false;
  @override
  Future<PracticeSignInResult> signInWithOAuth(
    PracticeOAuthProvider provider,
  ) async {
    providers.add(provider);
    emit(const PracticeAuthState.signedIn('did:privy:accountTest'));
    return PracticeSignInResult.signedIn;
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
    codeLogins.add((email, code));
    if (rejectCode) return PracticeSignInResult.failed;
    emit(const PracticeAuthState.signedIn('did:privy:accountTest'));
    return PracticeSignInResult.signedIn;
  }

  @override
  Future<void> signOut() async => emit(const PracticeAuthState.signedOut());
  @override
  Future<String?> accessToken({required String expectedSubject}) async =>
      state.subject == expectedSubject ? 'local-test-token' : null;
  @override
  Future<void> close() => events.close();
}

class _Store implements PracticeSyncStore {
  final records = <String, String>{};
  @override
  Future<String?> read(String key) async => records[key];

  @override
  Future<bool> write(String key, String value) async {
    records[key] = value;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reconciliation retains both histories and explicitly selects the draft',
    () {
      final local = _started().advance();
      final remote = _completed().startActivity(
        OfficeActivityIds.salesAndProfit,
      );
      final fromLocal = reconcilePracticeDrafts(
        local: local,
        remote: remote,
        useRemoteDraft: false,
      )!;
      final fromRemote = reconcilePracticeDrafts(
        local: local,
        remote: remote,
        useRemoteDraft: true,
      )!;
      expect(
        fromLocal.completions[_first]!.toJson(),
        remote.completions[_first]!.toJson(),
      );
      expect(fromLocal.active!.stage, 1);
      expect(fromRemote.active!.activityId, OfficeActivityIds.salesAndProfit);
      expect(local.completions, isEmpty);
      expect(remote.active!.stage, 0);
    },
  );

  test(
    'reconciliation cannot replace even one microsecond of first history',
    () {
      final local = _completed();
      final remote = _completed(at: _now.add(const Duration(microseconds: 1)));
      for (final useRemote in [true, false]) {
        expect(
          reconcilePracticeDrafts(
            local: local,
            remote: remote,
            useRemoteDraft: useRemote,
          ),
          isNull,
        );
      }
    },
  );

  test('identical first notes with nested answer parts remain compatible', () {
    final first = _completed();
    final copy = OfficeProgress.fromJson(
      jsonDecode(jsonEncode(first.toJson())) as Map<String, dynamic>,
    );
    expect(
      reconcilePracticeDrafts(
        local: first,
        remote: copy,
        useRemoteDraft: true,
      )!.toJson(),
      first.toJson(),
    );
  });

  testWidgets(
    'unconfigured and invalid configuration stay usable without a login action',
    (tester) async {
      for (final invalid in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AccountSettings(
                controller: null,
                configurationFailed: invalid,
              ),
            ),
          ),
        );
        expect(find.text('Continue with X'), findsNothing);
        expect(
          find.text('Your practice is saved on this device.'),
          findsOneWidget,
        );
        expect(
          find.text(
            invalid
                ? 'Sign-in is unavailable in this build.'
                : 'Account sign-in is not connected in this build.',
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'default entry opens the stocks-first product with unconfigured guest access',
    (tester) async {
      expect(const String.fromEnvironment('PRIVY_APP_ID'), isEmpty);
      expect(const String.fromEnvironment('PRIVY_APP_CLIENT_ID'), isEmpty);
      expect(const String.fromEnvironment('TRIMMY_API_URL'), isEmpty);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await entry.main();
      // Welcome deliberately keeps its heartbeat running; settle the finite
      // startup transition without waiting for all animation to stop.
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(TrimmyProductApp), findsOneWidget);
      expect(find.text('Start my first day'), findsOneWidget);
      expect(find.byType(entry.TrimmyApp), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sign in replaces old routes, syncs acknowledged edits, and sign out restores the guest',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final auth = _Auth();
      final guest = OfficeProgressRepository.fromPreferences(preferences);
      await guest.startActivity(_first);
      await guest.advance();
      var server = PracticeSnapshot(
        revision: 0,
        progress: null,
        updatedAt: null,
      );
      var puts = 0;
      final requestTokens = <String?>[];
      final portfolioRequests = <String>[];
      final baseRevisions = <int>[];
      final store = _Store();
      final client = MockClient((request) async {
        // Assert collected requests from the test zone, outside the timer's
        // MockClient callback where test failures become transport failures.
        requestTokens.add(request.headers['authorization']);
        if (request.url.path == '/v1/account/context') {
          portfolioRequests.add(request.url.path);
          return http.Response(
            jsonEncode(_contextFor(_account)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/v1/account/holdings') {
          portfolioRequests.add(request.url.path);
          return http.Response(
            jsonEncode(_holdingsFor(_account)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({'schemaVersion': 1, 'userId': _account}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'PUT') {
          final command = PracticeMutation.fromJson(jsonDecode(request.body));
          baseRevisions.add(command.baseRevision);
          server = PracticeSnapshot(
            revision: server.revision + 1,
            progress: command.progress,
            updatedAt: _now,
          );
          puts++;
        }
        return http.Response(
          jsonEncode(server.toJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final controller = AccountController(
        auth: auth,
        guestRepository: guest,
        store: store,
        httpClient: client,
        baseUri: Uri.parse('https://api.trimmy.test'),
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        controller.dispose();
        client.close();
        await auth.close();
      });
      await tester.pumpWidget(
        PracticeAccountHost(
          preferences: preferences,
          controller: controller,
          builder: (context, account, invalid) => OfficeStudy(
            key: ValueKey(account!.navigationEpoch),
            preferences: preferences,
            progressRepository: account.repository,
            accountController: account,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with X'), findsOneWidget);
      await tester.tap(find.text('Continue with X'));
      await tester.pumpAndSettle();
      expect(controller.phase, AccountPhase.active);
      await controller.portfolioRepository!.whenIdle;
      expect(controller.portfolioState!.phase, AccountPortfolioPhase.ready);
      expect(portfolioRequests, [
        '/v1/account/context',
        '/v1/account/holdings',
      ]);
      expect(
        find.byType(AccountSettings),
        findsNothing,
        reason: 'Account switch removes the guest route stack.',
      );
      expect(
        controller.repository.state.active,
        isNull,
        reason: 'Guest practice must not import automatically.',
      );
      expect(guest.state.active!.stage, 1);
      await controller.repository.startActivity(_first);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(puts, 1);
      expect(controller.syncStatus, AccountSyncStatus.saved);
      expect(requestTokens, everyElement('Bearer local-test-token'));
      expect(baseRevisions, [0]);
      portfolioRequests.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(controller.isForeground, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await controller.portfolioRepository!.whenIdle;
      expect(controller.isForeground, true);
      expect(portfolioRequests, [
        '/v1/account/context',
        '/v1/account/holdings',
      ]);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(controller.phase, AccountPhase.guest);
      expect(controller.portfolioRepository, isNull);
      expect(controller.portfolioState, isNull);
      expect(identical(controller.repository, guest), true);
      expect(controller.repository.state.active!.stage, 1);
      expect(find.byType(AccountSettings), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'email sign-in asks for a code, reports a wrong code and then binds the account',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final auth = _Auth();
      http.Response respond(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
      final client = MockClient((request) async {
        if (request.url.path == '/v1/account/context') {
          return respond(_contextFor(_account));
        }
        if (request.url.path == '/v1/account/holdings') {
          return respond(_holdingsFor(_account));
        }
        if (request.method == 'POST') {
          return respond({'schemaVersion': 1, 'userId': _account});
        }
        return respond({
          'schemaVersion': 1,
          'revision': 0,
          'progress': null,
          'updatedAt': null,
        });
      });
      final controller = AccountController(
        auth: auth,
        guestRepository: OfficeProgressRepository.fromPreferences(preferences),
        store: _Store(),
        httpClient: client,
        baseUri: Uri.parse('https://api.trimmy.test'),
      );
      addTearDown(() async {
        controller.dispose();
        client.close();
        await auth.close();
      });
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountSettings(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue with X'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with X'), findsNothing);
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a full email address, like name@example.com.'),
        findsOneWidget,
      );
      expect(auth.sentCodes, isEmpty);
      await tester.enterText(find.byType(TextField), 'person@example.test');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(auth.sentCodes, ['person@example.test']);
      expect(
        find.text('Enter the code we sent to person@example.test.'),
        findsOneWidget,
      );
      auth.rejectCode = true;
      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(
        find.text("That code didn't work. Try again or send a new code."),
        findsOneWidget,
      );
      expect(controller.phase, AccountPhase.guest);
      auth.rejectCode = false;
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(auth.codeLogins, [
        ('person@example.test', '000000'),
        ('person@example.test', '123456'),
      ]);
      expect(controller.phase, AccountPhase.active);
      expect(controller.accountId, _account);
      expect(find.text('Sign in'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(controller.phase, AccountPhase.guest);
      expect(find.text('Continue with X'), findsOneWidget);
      expect(find.text('Continue with email'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
