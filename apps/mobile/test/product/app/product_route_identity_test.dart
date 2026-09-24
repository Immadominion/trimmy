import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/markets/config.dart';
import 'package:trimmy/markets/stock_research_host.dart';
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/product/app/product_app.dart';
import 'package:trimmy/product/app/product_session.dart';
import 'package:trimmy/product/design/product_theme.dart';

const _principal = '71000000-0000-4000-8000-000000000001';

void main() {
  testWidgets(
    'cancelled sign-in preserves its routes and confirmed account change clears them',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final auth = _Auth();
      final client = MockClient((_) async => http.Response('', 503));
      final account = _MutableAccountController(
        auth: auth,
        guestRepository: OfficeProgressRepository.fromPreferences(preferences),
        store: _Store(),
        client: client,
      );
      final session = ProductSession.fromPreferences(preferences);
      final navigatorKey = GlobalKey<NavigatorState>();
      addTearDown(() async {
        session.dispose();
        account.dispose();
        await auth.close();
        client.close();
      });

      await tester.pumpWidget(
        StockResearchHost(
          config: StockResearchConfig.parse(apiUrl: ''),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: productTheme(),
            home: ListenableBuilder(
              listenable: account,
              builder: (context, _) => ProductExperience(
                preferences: preferences,
                session: session,
                account: account,
                accountConfigurationFailed: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      unawaited(
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Settings route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Sign-in route')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      account.move(AccountPhase.connecting);
      await tester.pumpAndSettle();
      expect(find.text('Sign-in route'), findsOneWidget);

      account.move(AccountPhase.guest, principalKey: _principal);
      await tester.pumpAndSettle();
      expect(find.text('Sign-in route'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isTrue);

      account.move(AccountPhase.connecting);
      await tester.pumpAndSettle();
      expect(find.text('Sign-in route'), findsOneWidget);

      account.move(
        AccountPhase.active,
        accountId: _principal,
        principalKey: _principal,
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign-in route'), findsNothing);
      expect(find.text('Settings route'), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);
    },
  );
}

final class _MutableAccountController extends AccountController {
  _MutableAccountController({
    required super.auth,
    required super.guestRepository,
    required super.store,
    required http.Client client,
  }) : super(httpClient: client, baseUri: Uri.parse('https://api.trimmy.test'));

  AccountPhase _currentPhase = AccountPhase.guest;
  String? _currentAccountId;
  String _currentPrincipalKey = _principal;

  @override
  AccountPhase get phase => _currentPhase;

  @override
  String? get accountId => _currentAccountId;

  @override
  Future<String> paperPrincipalKey() async {
    if (_currentPhase != AccountPhase.guest &&
        _currentPhase != AccountPhase.active) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
    return _currentPrincipalKey;
  }

  void move(AccountPhase phase, {String? accountId, String? principalKey}) {
    _currentPhase = phase;
    _currentAccountId = accountId;
    if (principalKey != null) _currentPrincipalKey = principalKey;
    notifyListeners();
  }
}

final class _Auth implements PracticeAuth {
  final _events = StreamController<PracticeAuthState>.broadcast();

  @override
  PracticeAuthState state = const PracticeAuthState.signedOut();

  @override
  Stream<PracticeAuthState> get changes => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken({required String expectedSubject}) async => null;

  @override
  Future<PracticeSignInResult> signInWithOAuth(
    PracticeOAuthProvider provider,
  ) async => PracticeSignInResult.cancelled;

  @override
  Future<PracticeEmailCodeResult> sendEmailCode(String email) async =>
      PracticeEmailCodeResult.unavailable;

  @override
  Future<PracticeSignInResult> signInWithEmailCode({
    required String email,
    required String code,
  }) async => PracticeSignInResult.failed;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> close() => _events.close();
}

final class _Store implements PracticeSyncStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<bool> write(String key, String value) async => true;
}
