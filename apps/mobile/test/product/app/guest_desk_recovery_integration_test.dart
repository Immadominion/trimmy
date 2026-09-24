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

class _SignedOutAuth implements PracticeAuth {
  @override
  PracticeAuthState state = const PracticeAuthState.signedOut();
  final events = StreamController<PracticeAuthState>.broadcast();

  @override
  Stream<PracticeAuthState> get changes => events.stream;
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
  Future<void> close() => events.close();
}

class _SignedInAuth implements PracticeAuth {
  @override
  PracticeAuthState state = const PracticeAuthState.signedIn('subject-a');
  final events = StreamController<PracticeAuthState>.broadcast();

  @override
  Stream<PracticeAuthState> get changes => events.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken({required String expectedSubject}) async =>
      expectedSubject == 'subject-a' ? 'safe.token' : null;
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
  Future<void> close() => events.close();
}

class _MemorySyncStore implements PracticeSyncStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<bool> write(String key, String value) async {
    values[key] = value;
    return true;
  }
}

class _ExpiredGuests implements GuestSessionPort, GuestSessionRecoveryPort {
  _ExpiredGuests([this.failure = GuestSessionFailure.expired]);

  final GuestSessionFailure failure;
  var restarted = false;
  var guestIdCalls = 0;
  var restartCalls = 0;
  GuestSessionFailure? observedFailure;

  @override
  Future<String> guestId() async {
    guestIdCalls++;
    if (!restarted) {
      throw GuestSessionException(failure);
    }
    return '71000000-0000-4000-8000-000000000002';
  }

  @override
  Future<PaperAuthorization> paperAuthorization() async =>
      const GuestPaperAuthorization(
        'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      );

  @override
  Future<void> claimGuestDesk(String verifiedBearer) async {}

  @override
  Future<void> startNewGuestDesk({GuestSessionFailure? observedFailure}) async {
    restartCalls++;
    this.observedFailure = observedFailure;
    restarted = true;
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.hitTestable().evaluate().isNotEmpty) return;
    await tester.drag(scrollable, const Offset(0, -180));
    await tester.pump();
  }
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('expired paper identity becomes a stable recovery gate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = _SignedOutAuth();
    final guests = _ExpiredGuests();
    final client = MockClient((_) async => http.Response('', 503));
    final account = AccountController(
      auth: auth,
      guestRepository: OfficeProgressRepository.fromPreferences(preferences),
      store: _MemorySyncStore(),
      httpClient: client,
      baseUri: Uri.parse('https://api.trimmy.test'),
      guestSessions: guests,
    );
    addTearDown(() async {
      account.dispose();
      await auth.close();
      client.close();
    });
    await account.initialize();

    await tester.pumpWidget(
      StockResearchHost(
        config: StockResearchConfig.parse(apiUrl: ''),
        child: TrimmyProductApp(
          preferences: preferences,
          account: account,
          accountConfigurationFailed: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guest session expired'), findsOneWidget);
    expect(guests.guestIdCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(guests.guestIdCalls, 1, reason: 'rebuilds must not retry expiry');
    expect(find.textContaining('10,000 paper'), findsNothing);

    final start = find.byKey(const ValueKey('guest-recovery-start-new'));
    await _reveal(tester, start);
    await tester.tap(start.hitTestable());
    await tester.pump();
    expect(guests.restartCalls, 0);

    final confirm = find.byKey(
      const ValueKey('guest-recovery-confirm-start-new'),
    );
    await _reveal(tester, confirm);
    await tester.tap(confirm.hitTestable());
    await tester.pumpAndSettle();

    expect(guests.restartCalls, 1);
    expect(guests.observedFailure, GuestSessionFailure.expired);
    expect(guests.guestIdCalls, 2);
    expect(find.text('Guest session expired'), findsNothing);
    expect(find.textContaining('10,000 paper'), findsNothing);
  });

  testWidgets('server-revoked guest identity reaches explicit recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = _SignedOutAuth();
    final guests = _ExpiredGuests(GuestSessionFailure.revoked);
    final client = MockClient((_) async => http.Response('', 503));
    final account = AccountController(
      auth: auth,
      guestRepository: OfficeProgressRepository.fromPreferences(preferences),
      store: _MemorySyncStore(),
      httpClient: client,
      baseUri: Uri.parse('https://api.trimmy.test'),
      guestSessions: guests,
    );
    addTearDown(() async {
      account.dispose();
      await auth.close();
      client.close();
    });
    await account.initialize();

    await tester.pumpWidget(
      StockResearchHost(
        config: StockResearchConfig.parse(apiUrl: ''),
        child: TrimmyProductApp(
          preferences: preferences,
          account: account,
          accountConfigurationFailed: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guest session ended'), findsOneWidget);
    final start = find.byKey(const ValueKey('guest-recovery-start-new'));
    await _reveal(tester, start);
    await tester.tap(start.hitTestable());
    await tester.pump();
    final confirm = find.byKey(
      const ValueKey('guest-recovery-confirm-start-new'),
    );
    await _reveal(tester, confirm);
    await tester.tap(confirm.hitTestable());
    await tester.pumpAndSettle();

    expect(guests.restartCalls, 1);
    expect(guests.observedFailure, GuestSessionFailure.revoked);
    expect(find.text('Guest session ended'), findsNothing);
  });

  testWidgets('account profile retry reconnects server identity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = _SignedInAuth();
    var sessionRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/practice/session') sessionRequests++;
      return http.Response(
        '{"error":{"code":"PRACTICE_SYNC_UNAVAILABLE","message":"Unavailable.","requestId":"request-1"}}',
        503,
        headers: const {'content-type': 'application/json'},
      );
    });
    final account = AccountController(
      auth: auth,
      guestRepository: OfficeProgressRepository.fromPreferences(preferences),
      store: _MemorySyncStore(),
      httpClient: client,
      baseUri: Uri.parse('https://api.trimmy.test'),
    );
    addTearDown(() async {
      account.dispose();
      await auth.close();
      client.close();
    });
    await account.initialize();
    expect(account.phase, AccountPhase.error);
    expect(sessionRequests, 1);

    await tester.pumpWidget(
      StockResearchHost(
        config: StockResearchConfig.parse(apiUrl: ''),
        child: TrimmyProductApp(
          preferences: preferences,
          account: account,
          accountConfigurationFailed: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t open Trimmy'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(sessionRequests, 2);
    expect(account.phase, AccountPhase.error);
  });
}
