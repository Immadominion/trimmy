import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/auth.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/durable_state.dart';

const _account = 'aa000000-0000-4000-8000-000000000001';
const _subject = 'did:privy:noticeTest';
const _id = '11111111-1111-4111-8111-111111111111';
const _social = '44444444-4444-4444-8444-444444444444';
const _senderJson = {
  'socialId': _social,
  'handle': 'mira_trade',
  'persona': 'oracle',
  'rank': {'id': 'rookie', 'label': 'Rookie'},
};
const _recipientJson = {'provider': 'x', 'handleSnapshot': 'ada_builds'};

class _Auth implements PracticeAuth {
  @override
  PracticeAuthState state = const PracticeAuthState.signedIn(_subject);
  final events = StreamController<PracticeAuthState>.broadcast(sync: true);

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

Map<String, Object?> _offeredToMe() => <String, Object?>{
  'schemaVersion': 2,
  'id': _id,
  'state': 'offered',
  'funding': 'unfunded',
  'sender': _senderJson,
  'recipient': _recipientJson,
  'expiresAt': '2030-01-01T12:00:00.000Z',
  'createdAt': '2026-09-16T10:00:00.000Z',
  'acceptedAt': null,
  'version': 2,
  'role': 'recipient',
};

Future<AccountController> _office(
  WidgetTester tester, {
  required List<Map<String, Object?>> invitations,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final auth = _Auth();
  final client = MockClient((request) async {
    if (request.url.path == '/v1/invitations') {
      return _json({
        'schemaVersion': 2,
        'incomingInvitations': 'available',
        'invitations': invitations,
        'nextCursor': null,
      });
    }
    if (request.method == 'POST' &&
        request.url.path == '/v1/practice/session') {
      return _json({'schemaVersion': 1, 'userId': _account});
    }
    if (request.url.path.startsWith('/v1/account/')) {
      return _json({
        'error': {'code': 'X', 'message': 'no', 'requestId': 'r'},
      }, 503);
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
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    OfficeStudy(
      preferences: preferences,
      progressRepository: controller.repository,
      accountController: controller,
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [('Manrope', 'manrope'), ('Rubik', 'rubik')]) {
      await (FontLoader(font.$1)..addFont(
            rootBundle.load('assets/fonts/${font.$2}/${font.$1}-Variable.ttf'),
          ))
          .load();
    }
  });

  testWidgets('the bell is a real control and claims nothing it cannot know', (
    tester,
  ) async {
    final controller = await _office(tester, invitations: [_offeredToMe()]);
    expect(controller.invitationsController, isNotNull);
    expect(
      find.byKey(const ValueKey('office-notices')),
      findsOneWidget,
      reason: 'the bell is no longer inert',
    );
    // Nothing polls, so the office does not read invitations behind the scenes
    // and the badge keeps reporting practice rather than inventing a count.
    expect(controller.invitationsController?.loaded, isFalse);
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the badge opens the invitations panel', (tester) async {
    await _office(tester, invitations: [_offeredToMe()]);
    await tester.tap(find.byKey(const ValueKey('office-notices')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('invitations-create')), findsOneWidget);
    expect(find.textContaining('carries no money'), findsOneWidget);
    // The person it was offered to is given only an answer.
    expect(
      find.byKey(const ValueKey('invitation-accept-$_id')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('invitation-decline-$_id')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty list is reported as empty, not as an error', (
    tester,
  ) async {
    await _office(tester, invitations: const []);
    await tester.tap(find.byKey(const ValueKey('office-notices')));
    await tester.pumpAndSettle();
    expect(find.text('No open invitations.'), findsOneWidget);
    expect(find.byKey(const ValueKey('invitations-failure')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a guest office has no notices control at all', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OfficeStudy(preferences: preferences));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('office-notices')), findsNothing);
    // The original badge meaning is untouched for a guest.
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
