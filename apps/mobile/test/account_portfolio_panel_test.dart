import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/account/account_portfolio_panel.dart';
import 'package:trimmy/account/wallet_setup.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/durable_state.dart';

import 'support/account_data_fixtures.dart' as fixtures;

const _account = fixtures.account;

class _Auth implements PracticeAuth {
  _Auth(this.state);
  @override
  PracticeAuthState state;
  final events = StreamController<PracticeAuthState>.broadcast(sync: true);
  @override
  Stream<PracticeAuthState> get changes => events.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<PracticeSignInResult> signInWithOAuth(
    PracticeOAuthProvider provider,
  ) async => PracticeSignInResult.unavailable;
  @override
  Future<PracticeEmailCodeResult> sendEmailCode(String email) async =>
      PracticeEmailCodeResult.unavailable;
  @override
  Future<PracticeSignInResult> signInWithEmailCode({
    required String email,
    required String code,
  }) async => PracticeSignInResult.unavailable;
  @override
  Future<void> signOut() async {
    state = const PracticeAuthState.signedOut();
    events.add(state);
  }

  @override
  Future<String?> accessToken({required String expectedSubject}) async =>
      state.subject == expectedSubject ? 'token' : null;
  @override
  Future<void> close() => events.close();
}

class _Store implements PracticeSyncStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> write(String key, String value) async {
    values[key] = value;
    return true;
  }
}

class _Timer implements Timer {
  _Timer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int get tick => 0;
  @override
  void cancel() => isActive = false;
}

class _FakeReader implements AccountPortfolioReader {
  _FakeReader({required this.context, required this.holdings});
  AccountContextSnapshot context;
  AccountHoldingsSnapshot holdings;
  AccountDataFailure? contextFailure;
  @override
  String get accountId => _account;
  @override
  Future<AccountContextSnapshot> readContext() async {
    if (contextFailure case final failure?) {
      throw AccountDataException(failure);
    }
    return context;
  }

  @override
  Future<AccountHoldingsSnapshot> readHoldings() async => holdings;
  @override
  void cancelPending() {}
  @override
  void close() {}
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _holdingsNow() {
  final value =
      jsonDecode(jsonEncode(fixtures.holdingsEnvelope()))
          as Map<String, dynamic>;
  final observedAt = DateTime.now().toUtc().subtract(
    const Duration(seconds: 1),
  );
  (value['holdings'] as Map<String, dynamic>)['observedAt'] =
      DateTime.fromMillisecondsSinceEpoch(
        observedAt.millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();
  return value;
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('view states', () {
    final observedAt = DateTime.parse('2026-09-14T17:28:27.109Z');
    late DateTime now;
    late AccountPortfolioRepository repository;
    late _FakeReader reader;

    setUp(() {
      now = observedAt.add(const Duration(seconds: 1));
      reader = _FakeReader(
        context: AccountContextSnapshot.fromEnvelope(
          fixtures.contextEnvelope(),
          expectedUserId: _account,
        ),
        holdings: AccountHoldingsSnapshot.fromEnvelope(
          fixtures.holdingsEnvelope(),
          expectedUserId: _account,
        ),
      );
      repository = AccountPortfolioRepository(
        reader: reader,
        clock: () => now,
        timerFactory: (_, callback) => _Timer(callback),
      );
    });

    tearDown(() => repository.dispose());

    testWidgets('guest and unverified states ask for sign-in or network', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AccountPortfolioView(
            state: null,
            signedIn: false,
            verified: false,
          ),
        ),
      );
      expect(find.text('Your account'), findsOneWidget);
      expect(find.text('Read-only'), findsOneWidget);
      expect(
        find.text(
          'Sign in from Settings to see the wallet linked to your account.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(
        _wrap(
          const AccountPortfolioView(
            state: null,
            signedIn: true,
            verified: false,
          ),
        ),
      );
      expect(
        find.text("Your account will be checked when you're back online."),
        findsOneWidget,
      );
      expect(find.text('Check again'), findsNothing);
    });

    testWidgets('ready, stale and offline show exact balances with freshness', (
      tester,
    ) async {
      await repository.refresh();
      expect(repository.state.phase, AccountPortfolioPhase.ready);
      var taps = 0;
      Widget view() => AccountPortfolioView(
        state: repository.state,
        signedIn: true,
        verified: true,
        onCheckAgain: () => taps++,
      );
      await tester.pumpWidget(_wrap(view()));
      final time = observedAt.toLocal();
      final clock =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      expect(find.text('Checked at $clock.'), findsOneWidget);
      expect(find.text('FVen…S96Z'), findsOneWidget);
      expect(find.text('@trimmyhq'), findsOneWidget);
      expect(find.text('9,007,199.254740991'), findsOneWidget);
      expect(find.text('18,446,744,073,709.551615'), findsOneWidget);
      expect(find.text('Some USDC is in a frozen account.'), findsOneWidget);
      expect(find.text('USDC is held in 2 accounts.'), findsOneWidget);
      expect(find.text('Amount not confirmed'), findsOneWidget);
      expect(
        find.textContaining('share amount is not confirmed'),
        findsOneWidget,
      );
      expect(
        find.text('Balances only. No prices, no buying or selling.'),
        findsOneWidget,
      );
      expect(find.textContaining(r'$'), findsNothing);
      await tester.tap(find.text('Check again'));
      expect(taps, 1);

      now = observedAt.add(const Duration(seconds: 60));
      expect(repository.state.phase, AccountPortfolioPhase.stale);
      await tester.pumpWidget(_wrap(view()));
      expect(
        find.text('Checked at $clock. This may have changed.'),
        findsOneWidget,
      );
      expect(find.text('9,007,199.254740991'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);

      repository.setNetworkAvailable(false);
      await tester.pumpWidget(_wrap(view()));
      expect(
        find.text("You're offline. This is what we saw at $clock."),
        findsOneWidget,
      );
      expect(find.text('Check again'), findsNothing);
    });

    testWidgets('a server without the account adapter is not called offline', (
      tester,
    ) async {
      reader.contextFailure = AccountDataFailure.notConfigured;
      await repository.refresh();
      expect(repository.state.phase, AccountPortfolioPhase.error);
      expect(repository.state.issue, AccountPortfolioIssue.notConfigured);
      await tester.pumpWidget(
        _wrap(
          AccountPortfolioView(
            state: repository.state,
            signedIn: true,
            verified: true,
            onCheckAgain: () {},
          ),
        ),
      );
      expect(
        find.text('Account details are not available on this server yet.'),
        findsOneWidget,
      );
      expect(find.textContaining('offline'), findsNothing);
    });

    testWidgets('missing and ambiguous wallets explain why balances are absent', (
      tester,
    ) async {
      for (final status in ['missing', 'ambiguous']) {
        reader.context = AccountContextSnapshot.fromEnvelope(
          fixtures.contextEnvelope(embeddedWallet: {'status': status}),
          expectedUserId: _account,
        );
        await repository.refresh();
        expect(repository.state.phase, AccountPortfolioPhase.error);
        await tester.pumpWidget(
          _wrap(
            AccountPortfolioView(
              state: repository.state,
              signedIn: true,
              verified: true,
              onCheckAgain: () {},
            ),
          ),
        );
        expect(
          find.text(
            status == 'missing'
                ? 'No wallet is linked to this account yet.'
                : 'This account has more than one wallet, so balances are not shown.',
          ),
          findsOneWidget,
        );
        expect(find.text('SOL'), findsNothing);
        expect(find.text('@trimmyhq'), findsOneWidget);
        expect(find.text('Check again'), findsOneWidget);
      }
    });
  });

  group('controller-bound panel', () {
    testWidgets(
      'guest shows the sign-in hint and a verified account renders balances then a holdings failure',
      (tester) async {
        var holdingsStatus = 200;
        final client = MockClient((request) async {
          if (request.url.path == '/v1/account/context') {
            return _json(fixtures.contextEnvelope());
          }
          if (request.url.path == '/v1/account/holdings') {
            return holdingsStatus == 200
                ? _json(_holdingsNow())
                : _json({
                    'error': {
                      'code': 'ACCOUNT_HOLDINGS_UNAVAILABLE',
                      'message': 'Unavailable.',
                      'requestId': 'r1',
                    },
                  }, holdingsStatus);
          }
          if (request.method == 'POST') {
            return _json({'schemaVersion': 1, 'userId': _account});
          }
          return _json({
            'schemaVersion': 1,
            'revision': 0,
            'progress': null,
            'updatedAt': null,
          });
        });
        final auth = _Auth(const PracticeAuthState.signedOut());
        final controller = AccountController(
          auth: auth,
          guestRepository: OfficeProgressRepository(
            read: (_) => null,
            write: (_, _) async => true,
          ),
          store: _Store(),
          httpClient: client,
          baseUri: Uri.parse('https://api.trimmy.test'),
          timerFactory: (_, callback) => _Timer(callback),
        );
        addTearDown(() async {
          controller.dispose();
          client.close();
          await auth.close();
        });
        await controller.initialize();
        await tester.pumpWidget(
          _wrap(AccountPortfolioPanel(controller: controller)),
        );
        expect(
          find.text(
            'Sign in from Settings to see the wallet linked to your account.',
          ),
          findsOneWidget,
        );

        auth.state = const PracticeAuthState.signedIn('did:privy:panel');
        auth.events.add(auth.state);
        await tester.pumpAndSettle();
        await controller.portfolioRepository!.whenIdle;
        await tester.pump();
        expect(controller.portfolioState!.phase, AccountPortfolioPhase.ready);
        expect(find.text('FVen…S96Z'), findsOneWidget);
        expect(find.text('9,007,199.254740991'), findsOneWidget);
        expect(find.textContaining('Checked at '), findsOneWidget);

        holdingsStatus = 503;
        await tester.tap(find.text('Check again'));
        await tester.pumpAndSettle();
        await controller.portfolioRepository!.whenIdle;
        await tester.pump();
        expect(controller.portfolioState!.phase, AccountPortfolioPhase.offline);
        expect(find.textContaining("You're offline."), findsOneWidget);
        expect(
          find.text('9,007,199.254740991'),
          findsOneWidget,
          reason: 'Retained balances stay visible with their time.',
        );

        await controller.signOut();
        await tester.pump();
        expect(
          find.text(
            'Sign in from Settings to see the wallet linked to your account.',
          ),
          findsOneWidget,
        );
        expect(find.text('FVen…S96Z'), findsNothing);
      },
    );

    testWidgets(
      'create wallet, open address and sign out is usable at large text',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var linked = false;
        final setup = _Setup(() {
          linked = true;
        });
        final client = MockClient((request) async {
          if (request.url.path == '/v1/account/context') {
            return _json(
              fixtures.contextEnvelope(
                embeddedWallet: linked ? null : {'status': 'missing'},
              ),
            );
          }
          if (request.url.path == '/v1/account/holdings') {
            return _json(_holdingsNow());
          }
          if (request.method == 'POST') {
            return _json({'schemaVersion': 1, 'userId': _account});
          }
          return _json({
            'schemaVersion': 1,
            'revision': 0,
            'progress': null,
            'updatedAt': null,
          });
        });
        final auth = _Auth(const PracticeAuthState.signedIn('did:privy:panel'));
        final controller = AccountController(
          auth: auth,
          guestRepository: OfficeProgressRepository(
            read: (_) => null,
            write: (_, _) async => true,
          ),
          store: _Store(),
          httpClient: client,
          baseUri: Uri.parse('https://api.trimmy.test'),
          timerFactory: (_, callback) => _Timer(callback),
          walletSetup: setup,
        );
        addTearDown(() async {
          controller.dispose();
          client.close();
          await auth.close();
        });
        await controller.initialize();
        await tester.pumpWidget(
          _wrap(AccountPortfolioPanel(controller: controller)),
        );
        await tester.pumpAndSettle();
        expect(setup.calls, 0);
        final create = find.byKey(const ValueKey('portfolio-create-wallet'));
        await tester.ensureVisible(create);
        expect(tester.getSemantics(create).label, 'Create wallet');
        await tester.tap(create);
        await tester.pumpAndSettle();
        expect(setup.calls, 1);
        expect(create, findsNothing);
        final view = find.byKey(const ValueKey('portfolio-wallet-address'));
        await tester.ensureVisible(view);
        await tester.tap(view);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('portfolio-full-address')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await controller.signOut();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('portfolio-full-address')),
          findsNothing,
        );
        expect(find.text('View wallet address'), findsNothing);
        semantics.dispose();
      },
    );

    testWidgets('an unconfigured build renders nothing', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountPortfolioPanel(controller: null)),
      );
      expect(find.text('Your account'), findsNothing);
    });
  });
}

class _Setup implements WalletSetup {
  _Setup(this.onSetup);
  final void Function() onSetup;
  int calls = 0;
  @override
  Future<String> ensureSolanaWallet({required String expectedSubject}) async {
    calls++;
    onSetup();
    return fixtures.wallet;
  }
}
