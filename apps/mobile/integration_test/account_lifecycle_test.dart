import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/account_host.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/markets/stock_research_host.dart';
import 'package:trimmy/practice_sync/account_progress_session.dart';
import 'package:trimmy/practice_sync/http_transport.dart';

/// Drives the real office, Settings and Portfolio on a device against the local
/// secure API with locally signed tokens. The API verifies them with a test key
/// supplied by the harness; nothing here talks to Privy, so the Privy browser
/// callback is out of scope. Everything after the token is exercised for real in
/// one app process against a real TLS database, with the real SharedPreferences
/// plugin persisting between simulated relaunches: account creation, progress
/// sync, renewal failure and recovery, sign-out, a second account, restore after
/// switching, a cold relaunch and an offline cold reopen.
const _apiUrl = String.fromEnvironment('TRIMMY_LIFECYCLE_API_URL');
const _caBase64 = String.fromEnvironment('TRIMMY_LIFECYCLE_CA_BASE64');
const _appId = String.fromEnvironment('TRIMMY_LIFECYCLE_APP_ID');
const _subjectA = String.fromEnvironment('TRIMMY_LIFECYCLE_SUBJECT_A');
const _subjectB = String.fromEnvironment('TRIMMY_LIFECYCLE_SUBJECT_B');
const _tokenA = String.fromEnvironment('TRIMMY_LIFECYCLE_TOKEN_A');
const _tokenB = String.fromEnvironment('TRIMMY_LIFECYCLE_TOKEN_B');
const _expiredA = String.fromEnvironment('TRIMMY_LIFECYCLE_EXPIRED_A');

final _started = DateTime.now();

void _step(String name) {
  final elapsed = DateTime.now().difference(_started).inMilliseconds;
  // ignore: avoid_print
  print('TRIMMY_LIFECYCLE_STEP +${elapsed}ms $name');
}

void _report(Map<String, Object?> result) {
  // The harness parses this exact prefix from the test runner's output.
  // ignore: avoid_print
  print('TRIMMY_LIFECYCLE_RESULT ${jsonEncode(result)}');
}

/// A signed-in provider identity for the device. It never contacts Privy; the
/// token it returns is verified by the API's test key. Renewal failure is
/// simulated by returning an expired token for the same subject.
class _DeviceAuth implements PracticeAuth {
  _DeviceAuth(this.state);
  @override
  PracticeAuthState state;
  String nextSubject = _subjectA;
  String? expiredFor;
  final _events = StreamController<PracticeAuthState>.broadcast(sync: true);
  int tokenReads = 0;

  void _emit(PracticeAuthState next) {
    state = next;
    _events.add(next);
  }

  @override
  Stream<PracticeAuthState> get changes => _events.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<PracticeSignInResult> signInWithOAuth(
    PracticeOAuthProvider provider,
  ) async {
    _emit(PracticeAuthState.signedIn(nextSubject));
    return PracticeSignInResult.signedIn;
  }

  @override
  Future<PracticeEmailCodeResult> sendEmailCode(String email) async =>
      PracticeEmailCodeResult.unavailable;
  @override
  Future<PracticeSignInResult> signInWithEmailCode({
    required String email,
    required String code,
  }) async => PracticeSignInResult.unavailable;
  @override
  Future<void> signOut() async => _emit(const PracticeAuthState.signedOut());
  @override
  Future<String?> accessToken({required String expectedSubject}) async {
    tokenReads++;
    if (state.subject != expectedSubject) return null;
    if (expiredFor == expectedSubject) return _expiredA;
    return expectedSubject == _subjectA ? _tokenA : _tokenB;
  }

  @override
  Future<void> close() => _events.close();
}

/// Every send fails, simulating no network while keeping the same API origin so
/// a cached server-account binding still matches its key.
class _OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(const SocketException('offline'));
  @override
  void close() {}
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  String reason = 'condition',
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for $reason. Visible: ${_visibleTexts()}');
    }
    await tester.pump(const Duration(milliseconds: 150));
  }
  await tester.pump(const Duration(milliseconds: 150));
}

String _visibleTexts() => find
    .byType(Text)
    .evaluate()
    .map((element) => (element.widget as Text).data ?? '')
    .where((text) => text.trim().isNotEmpty)
    .take(40)
    .join(' | ');

/// Taps [text] and, when [next]/[until] is given, retries until it holds. Page
/// transitions fade the office through paper, so a tap can land on a not-yet
/// hittable frame; retrying is the honest device behavior.
Future<void> _tap(
  WidgetTester tester,
  String text, {
  String? next,
  bool Function()? until,
}) async {
  await _pumpUntil(
    tester,
    () => find.text(text).evaluate().isNotEmpty,
    reason: 'text "$text"',
  );
  final done =
      until ??
      (next == null ? null : () => find.text(next).evaluate().isNotEmpty);
  for (var attempt = 0; attempt < 8; attempt++) {
    await tester.pump(const Duration(milliseconds: 250));
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) break;
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first, warnIfMissed: false);
    if (done == null) {
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
    for (var wait = 0; wait < 12; wait++) {
      await tester.pump(const Duration(milliseconds: 150));
      if (done()) return;
    }
  }
  if (done != null && !done()) {
    fail(
      'Tapping "$text" did not reach ${next ?? 'its expected state'}. '
      'Visible: ${_visibleTexts()}',
    );
  }
}

Future<void> _openSettings(WidgetTester tester) async {
  if (find.text('Your account').evaluate().isNotEmpty) {
    await _settleSheet(tester);
    return;
  }
  await _pumpUntil(
    tester,
    () => find.byTooltip('Settings').evaluate().isNotEmpty,
    reason: 'Settings control',
  );
  for (var attempt = 0; attempt < 12; attempt++) {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Settings').first, warnIfMissed: false);
    for (var wait = 0; wait < 6; wait++) {
      await tester.pump(const Duration(milliseconds: 150));
      if (find.text('Your account').evaluate().isNotEmpty) {
        await _settleSheet(tester);
        return;
      }
    }
  }
  fail('The Settings sheet did not open.');
}

/// The sheet slides in; tapping mid-animation can hit the scrim and dismiss it.
Future<void> _settleSheet(WidgetTester tester) async {
  Offset? previous;
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
    final finder = find.text('Your account');
    if (finder.evaluate().isEmpty) return;
    final position = tester.getTopLeft(finder.first);
    if (previous == position) {
      await tester.pump(const Duration(milliseconds: 120));
      return;
    }
    previous = position;
  }
}

Future<void> _closeSheet(WidgetTester tester) => _tap(
  tester,
  'Done',
  until: () => find.text('Your account').evaluate().isEmpty,
);

Future<void> _expectText(WidgetTester tester, String text) => _pumpUntil(
  tester,
  () => find.text(text).evaluate().isNotEmpty,
  reason: 'text "$text"',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'account lifecycle on device',
    timeout: const Timeout(Duration(minutes: 10)),
    (tester) async {
      expect(_apiUrl, startsWith('https://'));
      expect(_caBase64, isNotEmpty);
      expect(_tokenA, isNotEmpty);
      expect(_tokenB, isNotEmpty);

      final preferences = await SharedPreferences.getInstance();
      await preferences.clear();
      final baseUri = Uri.parse(_apiUrl);
      final context = SecurityContext(withTrustedRoots: true)
        ..setTrustedCertificatesBytes(base64.decode(_caBase64));
      final result = <String, Object?>{};
      final closers = <Future<void> Function()>[];
      addTearDown(() async {
        for (final close in closers.reversed) {
          await close();
        }
      });

      late _DeviceAuth auth;
      late AccountController controller;

      // Builds one live app process view. Each call replaces the controller and
      // client but reuses the same on-disk SharedPreferences, so a call models a
      // cold relaunch of the installed app.
      Future<void> mount({
        required PracticeAuthState initial,
        http.Client? httpClient,
      }) async {
        auth = _DeviceAuth(initial);
        final client = httpClient ?? IOClient(HttpClient(context: context));
        controller = AccountController(
          auth: auth,
          guestRepository: OfficeProgressRepository.fromPreferences(
            preferences,
          ),
          store: PreferencesPracticeSyncStore(preferences),
          httpClient: client,
          baseUri: baseUri,
          bindingAppId: _appId,
          debounce: const Duration(milliseconds: 150),
        );
        final localController = controller;
        final localAuth = auth;
        closers.add(() async {
          localController.dispose();
          client.close();
          await localAuth.close();
        });
        await tester.pumpWidget(
          StockResearchHost(
            child: PracticeAccountHost(
              preferences: preferences,
              controller: localController,
              builder: (context, account, configurationFailed) => OfficeStudy(
                key: ValueKey(account?.navigationEpoch ?? 0),
                preferences: preferences,
                progressRepository: account?.repository,
                accountController: account,
                accountConfigurationFailed: configurationFailed,
              ),
            ),
          ),
        );
        await _pumpUntil(
          tester,
          () => find.text('Your office').evaluate().isNotEmpty,
          reason: 'the office',
        );
      }

      Future<void> relaunch({
        required PracticeAuthState initial,
        http.Client? httpClient,
      }) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 200));
        await mount(initial: initial, httpClient: httpClient);
      }

      Future<void> waitSaved() => _pumpUntil(
        tester,
        () =>
            controller.phase == AccountPhase.active &&
            controller.isServerVerified &&
            controller.syncStatus == AccountSyncStatus.saved,
        reason: 'active verified account with saved sync',
        timeout: const Duration(seconds: 40),
      );

      Future<Map<String, Object?>> serverProgress(
        String accountId,
        String token,
      ) async {
        final client = IOClient(HttpClient(context: context));
        try {
          final transport = HttpPracticeTransport(
            client: client,
            baseUri: baseUri,
            accountId: accountId,
            accessToken: () async =>
                PracticeAccessToken(accountId: accountId, token: token),
          );
          final snapshot = await transport.getProgress();
          return {
            'revision': snapshot.revision,
            'completions': snapshot.progress?.completions.keys.toList() ?? [],
            'active': snapshot.progress?.active?.activityId,
          };
        } finally {
          client.close();
        }
      }

      // 1. Sign in as A through the real Settings sheet.
      _step('sign in A');
      await mount(initial: const PracticeAuthState.signedOut());
      await _expectText(tester, '0 of 4 activities saved.');
      await _openSettings(tester);
      await _tap(
        tester,
        'Continue with X',
        until: () => controller.phase != AccountPhase.guest,
      );
      await waitSaved();
      final accountA = controller.accountId!;
      result['accountA'] = accountA;
      await _openSettings(tester);
      await _expectText(tester, 'Saved to your account.');
      await _closeSheet(tester);

      // 2. Complete Check the date through the real activity UI.
      _step('complete Check the date');
      await _tap(tester, 'Start activity', next: 'Open the report');
      await _tap(tester, 'Open the report', next: 'Choose an answer');
      await _tap(tester, 'Choose an answer', next: 'Add the year');
      await _tap(tester, 'Add the year', next: 'Submit answer');
      await _tap(tester, 'Submit answer', next: 'Good catch.');
      await _tap(tester, 'Back to your office', next: 'Your office');
      await waitSaved();
      await _expectText(tester, '1 of 4 activities saved.');
      final afterCompletion = await serverProgress(accountA, _tokenA);
      result['serverAfterCompletion'] = afterCompletion;
      expect(afterCompletion['completions'], contains('check-the-date'));

      // 3. Renewal failure surfaces "sign in again", then a fresh token recovers.
      _step('renewal failure');
      auth.expiredFor = _subjectA;
      await _tap(tester, 'Start activity', next: 'Open the report');
      await tester.binding.handlePopRoute();
      await _pumpUntil(
        tester,
        () => controller.syncStatus == AccountSyncStatus.loginRequired,
        reason: 'login required after an expired token',
      );
      await _openSettings(tester);
      await _expectText(tester, 'Sign in again to continue account sync.');
      result['renewalFailureShown'] = true;
      auth.expiredFor = null;
      await _tap(
        tester,
        'Continue with X',
        until: () => controller.phase != AccountPhase.guest,
      );
      await waitSaved();
      final afterRecovery = await serverProgress(accountA, _tokenA);
      result['serverAfterRecovery'] = afterRecovery;
      expect(afterRecovery['active'], 'sales-and-profit');
      expect(
        afterRecovery['revision'],
        greaterThan(afterCompletion['revision'] as int),
      );

      // 4. Sign out returns to guest practice.
      _step('sign out');
      await _openSettings(tester);
      await _tap(
        tester,
        'Sign out',
        until: () => controller.phase == AccountPhase.guest,
      );
      await _expectText(tester, '0 of 4 activities saved.');

      // 5. A second account is separate and empty; its panel reports the server
      //    has no account-context adapter rather than pretending to be offline.
      _step('sign in B');
      auth.nextSubject = _subjectB;
      await _openSettings(tester);
      await _tap(
        tester,
        'Continue with X',
        until: () => controller.phase != AccountPhase.guest,
      );
      await waitSaved();
      final accountB = controller.accountId!;
      result['accountB'] = accountB;
      expect(accountB, isNot(accountA));
      expect(controller.repository.state.completions, isEmpty);
      await _expectText(tester, '0 of 4 activities saved.');
      await _tap(tester, 'Portfolio', next: 'Your account');
      await _expectText(
        tester,
        'Account details are not available on this server yet.',
      );
      result['accountPanelWithoutContextAdapter'] = true;
      await _tap(tester, 'Office', next: 'Your office');
      await _openSettings(tester);
      await _tap(
        tester,
        'Sign out',
        until: () => controller.phase == AccountPhase.guest,
      );

      // 6. Signing in as A again restores the saved work from the server.
      _step('restore A after switch');
      auth.nextSubject = _subjectA;
      await _openSettings(tester);
      await _tap(
        tester,
        'Continue with X',
        until: () => controller.phase != AccountPhase.guest,
      );
      await waitSaved();
      expect(controller.accountId, accountA);
      await _expectText(tester, '1 of 4 activities saved.');
      await _expectText(tester, 'Continue activity');
      result['restoredAfterSwitch'] = true;
      result['tokenReads'] = auth.tokenReads;

      // 7. Cold relaunch, already signed in as A, restores from the server.
      _step('cold relaunch online');
      await relaunch(initial: const PracticeAuthState.signedIn(_subjectA));
      await waitSaved();
      expect(controller.accountId, accountA);
      await _expectText(tester, '1 of 4 activities saved.');
      await _expectText(tester, 'Continue activity');
      result['relaunchRestored'] = true;

      // 8. Offline cold reopen: the cached binding and local record reopen the
      //    account read-only, and nothing syncs until the network returns.
      _step('offline cold reopen');
      await relaunch(
        initial: const PracticeAuthState.signedIn(_subjectA),
        httpClient: _OfflineClient(),
      );
      await _pumpUntil(
        tester,
        () =>
            controller.phase == AccountPhase.active &&
            !controller.isServerVerified,
        reason: 'offline cached account',
      );
      expect(controller.accountId, accountA);
      await _expectText(tester, '1 of 4 activities saved.');
      await _openSettings(tester);
      await _expectText(
        tester,
        'Saved on this device. Account sync will try again.',
      );
      await _closeSheet(tester);
      await _tap(tester, 'Portfolio', next: 'Your account');
      await _expectText(
        tester,
        "Your account will be checked when you're back online.",
      );
      result['offlineReopen'] = {
        'accountId': controller.accountId,
        'syncStatus': controller.syncStatus.name,
        'serverVerified': controller.isServerVerified,
      };

      // 9. Back online, the same account re-verifies and syncs again.
      _step('recover online');
      await relaunch(initial: const PracticeAuthState.signedIn(_subjectA));
      await waitSaved();
      expect(controller.accountId, accountA);
      await _expectText(tester, '1 of 4 activities saved.');
      result['recoveredOnline'] = true;

      _report(result);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
