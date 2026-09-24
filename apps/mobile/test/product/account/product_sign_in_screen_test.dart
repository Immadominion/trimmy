import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/product/account/product_sign_in_screen.dart';
import 'package:trimmy/product/account/sign_in_methods_page.dart';
import 'package:trimmy/product/design/product_theme.dart';

const _accountId = 'aa000000-0000-4000-8000-000000000001';
const _subject = 'test-subject';

void main() {
  testWidgets(
    'startup Back cannot grant guest access; the guest action is explicit',
    (tester) async {
      final h = _Harness();
      await _mount(tester, h, entryGate: true);
      expect(find.byKey(const ValueKey('sign-in-close')), findsNothing);
      await tester.binding.handlePopRoute();
      await _flush(tester);
      expect(h.later, 0);
      await _tap(tester, find.byKey(const ValueKey('sign-in-guest')));
      expect(h.later, 1);
      expect(h.completed, 0);
    },
  );
  testWidgets('unconfigured sign-in is honest and keeps the guest exit', (
    tester,
  ) async {
    final h = _Harness();
    await _mount(tester, h, configured: false);
    expect(find.textContaining('not set up in this build'), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-in-google')), findsNothing);
    expect(find.byKey(const ValueKey('sign-in-x')), findsNothing);
    await _tap(tester, find.byKey(const ValueKey('sign-in-later')));
    expect(h.later, 1);
    expect(h.completed, 0);
    expect(h.auth.providers, isEmpty);
  });

  testWidgets('disabled auth does not expose usable production providers', (
    tester,
  ) async {
    final h = _Harness()..auth.state = const PracticeAuthState.disabled();
    await _mount(tester, h);
    expect(find.textContaining('not set up in this build'), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-in-google')), findsNothing);
    expect(find.byKey(const ValueKey('sign-in-x')), findsNothing);
    expect(h.completed, 0);
  });

  testWidgets('system Back on the root account gate calls its guest exit', (
    tester,
  ) async {
    final h = _Harness();
    await _mount(tester, h);
    await tester.binding.handlePopRoute();
    await _flush(tester);
    expect(h.later, 1);
    expect(h.completed, 0);
    expect(h.controller.phase, AccountPhase.guest);
    expect(h.auth.providers, isEmpty);
    expect(h.guests.claims, isEmpty);
  });

  testWidgets('initialization blocks attempts and exits until state resolves', (
    tester,
  ) async {
    final ready = Completer<void>();
    final h = _Harness()..auth.initialization = ready.future;
    final initialization = h.controller.initialize();
    await _mount(tester, h, initialize: false, pushed: true);
    await _tap(tester, find.byKey(const ValueKey('sign-in-google')));
    await _tap(tester, find.byKey(const ValueKey('sign-in-email')));
    await _tap(tester, find.byKey(const ValueKey('sign-in-close')));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ProductSignInScreen), findsOneWidget);
    expect(h.auth.providers, isEmpty);
    expect(h.later, 0);
    expect(find.byKey(const ValueKey('sign-in-email-field')), findsNothing);

    ready.complete();
    await initialization;
    await _flush(tester);
    expect(h.controller.phase, AccountPhase.guest);
    await _tap(tester, find.byKey(const ValueKey('sign-in-close')));
    expect(h.later, 1);
  });

  for (final provider in PracticeOAuthProvider.values) {
    testWidgets(
      '${provider.name} delegates to the real account controller',
      (tester) async {
        final h = _Harness();
        await _mount(tester, h);
        expect(find.byKey(const ValueKey('sign-in-apple')), findsOneWidget);
        await _tap(tester, find.byKey(ValueKey('sign-in-${provider.name}')));
        expect(h.auth.providers, [provider]);
        expect(h.controller.phase, AccountPhase.guest);
        expect(h.completed, 0);
        expect(h.sessionRequests, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'Android only offers providers the native SDK supports',
    (tester) async {
      final h = _Harness();
      await _mount(tester, h);
      expect(find.byKey(const ValueKey('sign-in-apple')), findsNothing);
      expect(find.byKey(const ValueKey('sign-in-google')), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-x')), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('guest sits below email and above the social divider', (
    tester,
  ) async {
    final h = _Harness();
    await _mount(tester, h, entryGate: true);
    final email = tester.getRect(find.byKey(const ValueKey('sign-in-email')));
    final guest = tester.getRect(find.byKey(const ValueKey('sign-in-guest')));
    final divider = tester.getRect(find.text('OR'));
    final google = tester.getRect(find.byKey(const ValueKey('sign-in-google')));
    expect(guest.top, greaterThanOrEqualTo(email.bottom));
    expect(guest.bottom, lessThan(divider.top));
    expect(divider.bottom, lessThan(google.top));
    expect(find.byType(Divider), findsNWidgets(2));
    expect(google.bottom, lessThan(852 - 34));
  });

  testWidgets(
    'Apple remains visible and disabled during its login',
    (tester) async {
      final pending = Completer<PracticeSignInResult>();
      final h = _Harness()..auth.login = () => pending.future;
      await _mount(tester, h);
      final apple = find.byKey(const ValueKey('sign-in-apple'));
      await _tap(tester, apple);
      expect(apple, findsOneWidget);
      await _tap(tester, apple);
      expect(h.auth.providers, [PracticeOAuthProvider.apple]);
      pending.complete(PracticeSignInResult.cancelled);
      await _flush(tester);
      expect(apple, findsOneWidget);
      expect(h.completed, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('pending OAuth blocks double taps, other methods and all exits', (
    tester,
  ) async {
    final pending = Completer<PracticeSignInResult>();
    final h = _Harness();
    h.auth.login = () => pending.future;
    await _mount(tester, h, pushed: true);
    await _tap(tester, find.byKey(const ValueKey('sign-in-google')));
    expect(h.controller.phase, AccountPhase.connecting);
    for (final key in [
      'sign-in-google',
      'sign-in-x',
      'sign-in-email',
      'sign-in-close',
    ]) {
      await _tap(tester, find.byKey(ValueKey(key)));
    }
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ProductSignInScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-in-email-field')), findsNothing);
    expect(h.auth.providers, [PracticeOAuthProvider.google]);
    expect(h.auth.sentCodes, isEmpty);
    expect(h.later, 0);
    expect(h.completed, 0);

    pending.complete(PracticeSignInResult.cancelled);
    await _flush(tester);
    await _tap(tester, find.byKey(const ValueKey('sign-in-close')));
    expect(h.later, 1);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProductSignInScreen), findsNothing);
  });

  testWidgets(
    'queued close and email callbacks cannot bypass a pending login',
    (tester) async {
      final pending = Completer<PracticeSignInResult>();
      final h = _Harness();
      h.auth.login = () => pending.future;
      await _mount(tester, h);
      final methods = tester.widget<SignInMethodsPage>(
        find.byType(SignInMethodsPage),
      );
      final queuedClose = methods.onClose!;
      final queuedEmail = methods.onEmail!;
      await _tap(tester, find.byKey(const ValueKey('sign-in-google')));
      queuedClose();
      queuedEmail();
      await _flush(tester);
      expect(h.controller.phase, AccountPhase.connecting);
      expect(h.later, 0);
      expect(h.completed, 0);
      expect(find.byType(SignInMethodsPage), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-email-field')), findsNothing);
      expect(h.auth.providers, [PracticeOAuthProvider.google]);
      expect(h.auth.sentCodes, isEmpty);
      pending.complete(PracticeSignInResult.cancelled);
      await _flush(tester);
    },
  );

  testWidgets('cancellation keeps the guest desk and allows another attempt', (
    tester,
  ) async {
    final h = _Harness();
    await _mount(tester, h);
    final guestBefore = jsonEncode(h.guest.state.toJson());
    await _tap(tester, find.byKey(const ValueKey('sign-in-google')));
    await _expectError(tester);
    expect(find.textContaining('closed'), findsOneWidget);
    expect(identical(h.controller.repository, h.guest), isTrue);
    expect(jsonEncode(h.guest.state.toJson()), guestBefore);
    expect(h.guests.claims, isEmpty);
    expect(h.completed, 0);
    await _tap(tester, find.byKey(const ValueKey('sign-in-x')));
    expect(h.auth.providers, [
      PracticeOAuthProvider.google,
      PracticeOAuthProvider.x,
    ]);
  });

  for (final result in [
    PracticeSignInResult.failed,
    PracticeSignInResult.unavailable,
  ]) {
    testWidgets(
      'provider ${result.name} shows an error without account success',
      (tester) async {
        final h = _Harness();
        h.auth.login = () async => result;
        await _mount(tester, h);
        await _tap(tester, find.byKey(const ValueKey('sign-in-google')));
        await _expectError(tester);
        expect(h.completed, 0);
        expect(h.controller.phase, AccountPhase.guest);
        expect(h.sessionRequests, 0);
      },
    );
  }

  testWidgets('provider success waits for server binding and completes once', (
    tester,
  ) async {
    final session = Completer<http.Response>();
    final h = _Harness();
    h.auth.login = () async => PracticeSignInResult.signedIn;
    h.sessionResponse = () => session.future;
    await _mount(tester, h);
    await _tap(tester, find.byKey(const ValueKey('sign-in-google')));
    expect(h.auth.state.status, PracticeAuthStatus.signedIn);
    expect(h.controller.phase, AccountPhase.connecting, reason: h.diagnostic);
    expect(h.guests.claims, ['test-token']);
    expect(h.sessionRequests, 1);
    expect(h.completed, 0);

    session.complete(_session());
    await _flush(tester);
    expect(h.controller.phase, AccountPhase.active);
    expect(h.controller.isServerVerified, isTrue);
    expect(h.completed, 1);
    h.controller.setForeground(false);
    await _flush(tester);
    h.controller.setForeground(true);
    await _flush(tester);
    expect(
      h.completed,
      1,
      reason: 'Active account notifications are not logins.',
    );
  });

  for (final failClaim in [true, false]) {
    testWidgets(
      failClaim
          ? 'provider success cannot hide a failed guest claim'
          : 'provider success cannot hide a failed server session',
      (tester) async {
        final h = _Harness();
        h.auth.login = () async => PracticeSignInResult.signedIn;
        if (failClaim) {
          h.guests.failure = GuestSessionFailure.unavailable;
        } else {
          h.sessionResponse = () async => _backendUnavailable();
        }
        await _mount(tester, h);
        await _tap(tester, find.byKey(const ValueKey('sign-in-google')));
        expect(h.auth.state.status, PracticeAuthStatus.signedIn);
        expect(h.controller.phase, AccountPhase.error);
        expect(h.controller.accountId, isNull);
        expect(h.completed, 0);
        expect(h.guests.claims, ['test-token']);
        expect(h.sessionRequests, failClaim ? 0 : 1, reason: h.diagnostic);
        await _expectError(tester);
        await _tap(tester, find.byKey(const ValueKey('sign-in-close')));
        expect(h.later, 1);
      },
    );
  }

  testWidgets('email validates, sends once, then verifies its bound address', (
    tester,
  ) async {
    final codeSent = Completer<PracticeEmailCodeResult>();
    final verified = Completer<PracticeSignInResult>();
    final h = _Harness();
    h.auth.sendCode = () => codeSent.future;
    h.auth.login = () => verified.future;
    await _mount(tester, h);
    await _tap(tester, find.byKey(const ValueKey('sign-in-email')));
    final email = find.byKey(const ValueKey('sign-in-email-field'));
    await tester.enterText(email, 'not-an-email');
    await _tap(tester, find.byKey(const ValueKey('sign-in-send-code')));
    expect(h.auth.sentCodes, isEmpty);
    await _expectError(tester);

    await tester.enterText(email, '  person@example.test  ');
    final lateEmailSubmit = tester.widget<TextField>(email).onSubmitted!;
    await _tap(tester, find.byKey(const ValueKey('sign-in-send-code')));
    expect(h.auth.sentCodes, ['person@example.test']);
    expect(h.controller.phase, AccountPhase.guest);
    expect(h.completed, 0);
    // An already-queued keyboard submission must respect the pending lock.
    lateEmailSubmit('person@example.test');
    await tester.pump();
    expect(h.auth.sentCodes, hasLength(1));

    codeSent.complete(PracticeEmailCodeResult.sent);
    await _flush(tester);
    final code = find.byKey(const ValueKey('sign-in-code-field'));
    expect(code, findsOneWidget);
    expect(find.textContaining('person@example.test'), findsOneWidget);
    await tester.enterText(code, 'bad-code');
    await _tap(tester, find.byKey(const ValueKey('sign-in-verify')));
    expect(h.auth.codeLogins, isEmpty);
    await _expectError(tester);
    await tester.enterText(code, '12 34-56');
    final lateCodeSubmit = tester.widget<TextField>(code).onSubmitted!;
    await _tap(tester, find.byKey(const ValueKey('sign-in-verify')));
    lateCodeSubmit('123456');
    await _tap(tester, find.byKey(const ValueKey('sign-in-close')));
    expect(h.auth.codeLogins, [('person@example.test', '123456')]);
    expect(h.completed, 0);
    expect(h.later, 0);
    verified.complete(PracticeSignInResult.signedIn);
    await _flush(tester);
    expect(h.controller.phase, AccountPhase.active, reason: h.diagnostic);
    expect(h.completed, 1);
    h.controller.setForeground(false);
    await _flush(tester);
    expect(h.completed, 1);
  });

  testWidgets('email send and verification failures remain retryable', (
    tester,
  ) async {
    final h = _Harness();
    h.auth.sendCode = () async => PracticeEmailCodeResult.failed;
    h.auth.login = () async => PracticeSignInResult.failed;
    await _mount(tester, h);
    await _tap(tester, find.byKey(const ValueKey('sign-in-email')));
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-email-field')),
      'person@example.test',
    );
    await _tap(tester, find.byKey(const ValueKey('sign-in-send-code')));
    await _expectError(tester);
    expect(find.byKey(const ValueKey('sign-in-code-field')), findsNothing);
    h.auth.sendCode = () async => PracticeEmailCodeResult.sent;
    await _tap(tester, find.byKey(const ValueKey('sign-in-send-code')));
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-code-field')),
      '000000',
    );
    await _tap(tester, find.byKey(const ValueKey('sign-in-verify')));
    await _expectError(tester);
    expect(find.byKey(const ValueKey('sign-in-code-field')), findsOneWidget);
    expect(h.auth.codeLogins, [('person@example.test', '000000')]);
    expect(h.completed, 0);
    expect(h.controller.phase, AccountPhase.guest);
  });

  testWidgets(
    'a stale email reply cannot affect a later A to B to A operation',
    (tester) async {
      final oldReply = Completer<PracticeEmailCodeResult>();
      final newReply = Completer<PracticeEmailCodeResult>();
      final a = _Harness();
      a.auth.sendCode = () => oldReply.future;
      final b = _Harness();
      final selection = ValueNotifier(a.controller);
      addTearDown(() async {
        selection.dispose();
        await b.close();
      });
      await b.controller.initialize();
      await _mount(tester, a, controllerSelection: selection);
      await _tap(tester, find.byKey(const ValueKey('sign-in-email')));
      final email = find.byKey(const ValueKey('sign-in-email-field'));
      await tester.enterText(email, 'old@example.test');
      await _tap(tester, find.byKey(const ValueKey('sign-in-send-code')));

      selection.value = b.controller;
      await _flush(tester);
      selection.value = a.controller;
      await _flush(tester);
      a.auth.sendCode = () => newReply.future;
      await tester.enterText(email, 'fresh@example.test');
      await _tap(tester, find.byKey(const ValueKey('sign-in-send-code')));
      expect(a.auth.sentCodes, ['old@example.test', 'fresh@example.test']);

      oldReply.complete(PracticeEmailCodeResult.sent);
      await _flush(tester);
      expect(find.byKey(const ValueKey('sign-in-code-field')), findsNothing);
      expect(tester.widget<TextField>(email).enabled, isFalse);
      await _tap(tester, find.byKey(const ValueKey('sign-in-close')));
      expect(a.later, 0, reason: 'The newer email operation is still pending.');
      expect(a.completed, 0);

      newReply.complete(PracticeEmailCodeResult.sent);
      await _flush(tester);
      expect(find.byKey(const ValueKey('sign-in-code-field')), findsOneWidget);
      expect(find.textContaining('fresh@example.test'), findsOneWidget);
      expect(find.textContaining('old@example.test'), findsNothing);
      expect(b.auth.sentCodes, isEmpty);
    },
  );

  testWidgets('expired guest sign-in never promises to save the expired desk', (
    tester,
  ) async {
    final h = _Harness();
    await _mount(tester, h, configured: false, expiredGuestRecovery: true);
    expect(
      find.textContaining('expired guest desk stays separate'),
      findsOneWidget,
    );
    expect(find.textContaining('stays preserved'), findsWidgets);
    expect(find.text('Save your desk.'), findsNothing);
  });

  for (final (size, scale) in [
    (const Size(320, 568), 1.0),
    (const Size(393, 852), 2.0),
  ]) {
    testWidgets(
      'methods and email remain usable at $size with text scale $scale',
      (tester) async {
        final h = _Harness();
        await _mount(tester, h, size: size, textScale: scale);
        for (final key in ['sign-in-google', 'sign-in-x', 'sign-in-email']) {
          final action = find.byKey(ValueKey(key));
          await tester.ensureVisible(action);
          await tester.pump();
          expect(action.hitTestable(), findsOneWidget);
        }
        await _tap(tester, find.byKey(const ValueKey('sign-in-email')));
        await tester.enterText(
          find.byKey(const ValueKey('sign-in-email-field')),
          'person@example.test',
        );
        await _tap(tester, find.byKey(const ValueKey('sign-in-send-code')));
        expect(
          find.byKey(const ValueKey('sign-in-code-field')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _expectError(WidgetTester tester) async {
  final error = find.byKey(const ValueKey('sign-in-error'));
  expect(error, findsOneWidget);
  await tester.ensureVisible(error);
  await tester.pump();
  expect(error.hitTestable(), findsOneWidget);
  final text = find.descendant(
    of: error,
    matching: find.byType(Text),
    matchRoot: true,
  );
  expect(
    tester
        .widgetList<Text>(text)
        .map((widget) => widget.data ?? '')
        .join()
        .trim(),
    isNotEmpty,
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _flush(tester);
}

Future<void> _flush(WidgetTester tester) async {
  // Drain controller/HTTP microtasks and completion callbacks without waiting
  // on the deliberately held provider/backend operations used by some tests.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _mount(
  WidgetTester tester,
  _Harness h, {
  bool initialize = true,
  bool configured = true,
  bool pushed = false,
  bool entryGate = false,
  bool expiredGuestRecovery = false,
  ValueNotifier<AccountController>? controllerSelection,
  Size size = const Size(393, 852),
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await h.close();
    await tester.binding.setSurfaceSize(null);
    expect(h.sessionMethods, everyElement('POST'));
    expect(h.sessionAuthMatches, everyElement(isTrue));
  });
  if (initialize) await h.controller.initialize();
  final navigator = GlobalKey<NavigatorState>();
  Widget accountScreen(AccountController controller) => ProductSignInScreen(
    entryGate: entryGate,
    controller: configured ? controller : null,
    configurationFailed: !configured,
    expiredGuestRecovery: expiredGuestRecovery,
    onLater: () {
      h.later++;
      if (pushed) navigator.currentState!.pop();
    },
    onSignedIn: () => h.completed++,
  );
  Widget screen() => controllerSelection == null
      ? accountScreen(h.controller)
      : ValueListenableBuilder<AccountController>(
          valueListenable: controllerSelection,
          builder: (_, controller, _) => accountScreen(controller),
        );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: productTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
          padding: const EdgeInsets.only(top: 47, bottom: 34),
        ),
        child: child!,
      ),
      home: pushed ? const Scaffold(body: Text('Guest desk')) : screen(),
    ),
  );
  if (pushed) {
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => screen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  await _flush(tester);
}

class _Harness {
  _Harness() {
    client = MockClient((request) async {
      requests.add(
        '${request.method} ${request.url.path} '
        'expectedAuth=${request.headers['authorization'] == 'Bearer test-token'}',
      );
      if (request.url.path == '/v1/practice/session') {
        sessionRequests++;
        // Flutter's guarded expect must run in the test body/teardown, not
        // inside a transport callback pumped by the widget binding.
        sessionMethods.add(request.method);
        sessionAuthMatches.add(
          request.headers['authorization'] == 'Bearer test-token',
        );
        return sessionResponse == null ? _session() : await sessionResponse!();
      }
      // Portfolio refresh is independent of account binding. These tests do
      // not manufacture wallet/holdings data to make authentication succeed.
      return _backendUnavailable();
    });
    controller = AccountController(
      auth: auth,
      guestRepository: guest,
      store: _MemoryStore(),
      httpClient: client,
      baseUri: Uri.parse('https://account.example'),
      guestSessions: guests,
      timerFactory: (_, _) => _QuietTimer(),
    );
  }

  final auth = _Auth();
  final guests = _Guests();
  final guest = OfficeProgressRepository(
    read: (key) => key == OfficeProgressRepository.saveKey
        ? jsonEncode(
            OfficeProgress.empty()
                .startActivity(OfficeActivityIds.checkTheDate)
                .toJson(),
          )
        : null,
    write: (_, _) async => true,
  );
  late final MockClient client;
  late final AccountController controller;
  Future<http.Response> Function()? sessionResponse;
  int sessionRequests = 0;
  int completed = 0;
  int later = 0;
  final requests = <String>[];
  final sessionMethods = <String>[];
  final sessionAuthMatches = <bool>[];
  String get diagnostic =>
      'Account error=${controller.errorCode}; HTTP=$requests; claims=${guests.claims.length}';

  Future<void> close() async {
    controller.dispose();
    await auth.close();
    client.close();
  }
}

class _Auth implements PracticeAuth {
  @override
  PracticeAuthState state = const PracticeAuthState.signedOut();
  final _events = StreamController<PracticeAuthState>.broadcast(sync: true);
  final providers = <PracticeOAuthProvider>[];
  final sentCodes = <String>[];
  final codeLogins = <(String, String)>[];
  Future<void>? initialization;
  Future<PracticeSignInResult> Function()? login;
  Future<PracticeEmailCodeResult> Function()? sendCode;

  @override
  Stream<PracticeAuthState> get changes => _events.stream;
  @override
  Future<void> initialize() async {
    await initialization;
  }

  Future<PracticeSignInResult> _login() async {
    final result =
        await (login?.call() ?? Future.value(PracticeSignInResult.cancelled));
    if (result == PracticeSignInResult.signedIn) {
      state = const PracticeAuthState.signedIn(_subject);
      _events.add(state);
    }
    return result;
  }

  @override
  Future<PracticeSignInResult> signInWithOAuth(PracticeOAuthProvider provider) {
    providers.add(provider);
    return _login();
  }

  @override
  Future<PracticeEmailCodeResult> sendEmailCode(String email) async {
    sentCodes.add(email);
    return sendCode == null ? PracticeEmailCodeResult.sent : await sendCode!();
  }

  @override
  Future<PracticeSignInResult> signInWithEmailCode({
    required String email,
    required String code,
  }) {
    codeLogins.add((email, code));
    return _login();
  }

  @override
  Future<String?> accessToken({required String expectedSubject}) async =>
      state.subject == expectedSubject ? 'test-token' : null;
  @override
  Future<void> signOut() async {
    state = const PracticeAuthState.signedOut();
    _events.add(state);
  }

  @override
  Future<void> close() => _events.close();
}

class _Guests implements GuestSessionPort {
  final claims = <String>[];
  GuestSessionFailure? failure;
  @override
  Future<void> claimGuestDesk(String verifiedBearer) async {
    claims.add(verifiedBearer);
    if (failure case final failure?) throw GuestSessionException(failure);
  }

  @override
  Future<String> guestId() async => '71000000-0000-4000-8000-000000000001';
  @override
  Future<PaperAuthorization> paperAuthorization() async =>
      const GuestPaperAuthorization(
        'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      );
}

class _MemoryStore implements PracticeSyncStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<bool> write(String key, String value) async {
    _values[key] = value;
    return true;
  }
}

// Background progress synchronization is outside these sign-in tests. Keep its
// scheduling inert while exercising the real auth, claim and account mount.
class _QuietTimer implements Timer {
  bool _active = true;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
  @override
  void cancel() => _active = false;
}

http.Response _session() => _json({'schemaVersion': 1, 'userId': _accountId});
http.Response _backendUnavailable() => _json({
  'error': {
    'code': 'PRACTICE_SYNC_UNAVAILABLE',
    'message': 'Unavailable',
    'requestId': 'test-request',
  },
}, 503);
http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
