import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_settings.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/design_study/craft.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/durable_state.dart';

const _account = 'aa000000-0000-4000-8000-000000000001';
const _subject = 'did:privy:closureTest';

class _Auth implements PracticeAuth {
  @override
  PracticeAuthState state = const PracticeAuthState.signedIn(_subject);
  final events = StreamController<PracticeAuthState>.broadcast(sync: true);
  int signOuts = 0;

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
  Future<void> signOut() async {
    signOuts += 1;
    state = const PracticeAuthState.signedOut();
    events.add(state);
  }

  @override
  Future<String?> accessToken({required String expectedSubject}) async =>
      state.subject == expectedSubject ? 'local.test.token' : null;
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

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

/// A signed-in controller whose closure endpoint answers however the test asks.
Future<(AccountController, _Auth, List<String>)> _signedIn(
  WidgetTester tester, {
  int closureStatus = 200,
  Object closureBody = const {
    'schemaVersion': 1,
    'closed': true,
    'canceledInvitations': 1,
    'note': 'kept',
  },
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final auth = _Auth();
  final closureCalls = <String>[];
  final client = MockClient((request) async {
    if (request.url.path == '/v1/account/closure') {
      closureCalls.add(request.body);
      return _json(closureBody, closureStatus);
    }
    if (request.method == 'POST' &&
        request.url.path == '/v1/practice/session') {
      return _json({'schemaVersion': 1, 'userId': _account});
    }
    return _json({
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
  return (controller, auth, closureCalls);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'closing is explained honestly and stays behind the exact words',
    (tester) async {
      final (controller, auth, calls) = await _signedIn(tester);
      expect(
        controller.canCloseAccount,
        isTrue,
        reason: 'a verified account can close',
      );

      // The consequences are stated before anything can be pressed, including
      // the part people most need: history is kept rather than deleted.
      expect(find.textContaining('cannot sign in again'), findsOneWidget);
      expect(find.textContaining('no undo'), findsOneWidget);
      expect(find.textContaining('kept, not deleted'), findsOneWidget);
      // Nothing is armed yet.
      expect(find.byKey(const ValueKey('account-close-confirm')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('account-close-open')));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('account-close-confirmed'));
      expect(button, findsOneWidget);
      expect(find.textContaining('close my account'), findsWidgets);

      // A near miss leaves the button unpressable.
      for (final typed in [
        '',
        'close account',
        'Close My Account',
        'close  my account',
      ]) {
        await tester.enterText(
          find.byKey(const ValueKey('account-close-confirm')),
          typed,
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<CraftButton>(button).onPressed,
          isNull,
          reason: typed,
        );
      }
      // The exact words, allowing for surrounding spaces, do arm it.
      await tester.enterText(
        find.byKey(const ValueKey('account-close-confirm')),
        ' close my account ',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<CraftButton>(button).onPressed, isNotNull);
      expect(calls, isEmpty, reason: 'nothing is sent until it is pressed');
      expect(auth.signOuts, 0);
    },
  );

  testWidgets(
    'the exact words close the account, send one request and sign out',
    (tester) async {
      final (controller, auth, calls) = await _signedIn(tester);
      await tester.tap(find.byKey(const ValueKey('account-close-open')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('account-close-confirm')),
        'close my account',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-close-confirmed')));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(jsonDecode(calls.single), {
        'schemaVersion': 1,
        'confirm': 'close my account',
      });
      expect(controller.lastClosure?.closed, isTrue);
      expect(controller.lastClosure?.canceledInvitations, 1);
      // A closed account cannot authenticate, so the session ends locally too.
      expect(auth.signOuts, 1);
      expect(controller.phase, AccountPhase.guest);
    },
  );

  testWidgets('a refused closure keeps the session and reports a safe reason', (
    tester,
  ) async {
    final (controller, auth, calls) = await _signedIn(
      tester,
      closureStatus: 503,
      closureBody: const {
        'error': {'code': 'ACCOUNT_CLOSURE_UNAVAILABLE'},
      },
    );
    await tester.tap(find.byKey(const ValueKey('account-close-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-close-confirm')),
      'close my account',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-close-confirmed')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(controller.lastClosure, isNull, reason: 'nothing was closed');
    expect(auth.signOuts, 0, reason: 'the session survives a refused closure');
    expect(controller.errorCode, 'PRACTICE_ACCOUNT_CLOSURE_NOTCONFIGURED');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a verified account reaches invitations in their own sheet', (
    tester,
  ) async {
    final (controller, _, _) = await _signedIn(tester);
    expect(controller.invitationsController, isNotNull);
    final open = find.byKey(const ValueKey('invitations-open'));
    expect(open, findsOneWidget);
    // Settings itself stays short: the list is not inlined above sign-out.
    expect(find.byKey(const ValueKey('invitations-create')), findsNothing);
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invitations-create')), findsOneWidget);
    expect(find.textContaining('carries no money'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a guest is never offered account closing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final auth = _Auth()..state = const PracticeAuthState.signedOut();
    final client = MockClient((request) async => _json({'schemaVersion': 1}));
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
    expect(controller.canCloseAccount, isFalse);
    expect(find.byKey(const ValueKey('account-close-open')), findsNothing);
    // A guest has no account, so there are no invitations to reach either.
    expect(controller.invitationsController, isNull);
    expect(find.byKey(const ValueKey('invitations-open')), findsNothing);
  });
}
