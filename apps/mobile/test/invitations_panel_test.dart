import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/social/http_invitations_client.dart';
import 'package:trimmy/social/invitations_controller.dart';
import 'package:trimmy/social/invitations_panel.dart';

const _account = '9f000000-0000-4000-8000-000000000001';
const _id = '11111111-1111-4111-8111-111111111111';
const _second = '22222222-2222-4222-8222-222222222222';
const _mutation = '33333333-3333-4333-8333-333333333333';
const _social = '44444444-4444-4444-8444-444444444444';
final _base = Uri.parse('https://api.example');

const _senderJson = {
  'socialId': _social,
  'handle': 'mira_trade',
  'persona': 'oracle',
  'rank': {'id': 'rookie', 'label': 'Rookie'},
};
const _recipientJson = {'provider': 'x', 'handleSnapshot': 'ada_builds'};

Map<String, Object?> _row({
  String state = 'draft',
  String role = 'sender',
  Object? recipient,
  int version = 0,
  String id = _id,
  String? acceptedAt,
  String createdAt = '2026-09-16T10:00:00.000Z',
  String expiresAt = '2030-01-01T12:00:00.000Z',
}) => <String, Object?>{
  'schemaVersion': 2,
  'id': id,
  'state': state,
  'funding': 'unfunded',
  'sender': _senderJson,
  'recipient': recipient,
  'expiresAt': expiresAt,
  'createdAt': createdAt,
  'acceptedAt': acceptedAt,
  'version': version,
  'role': role,
};

Map<String, Object?> _page(
  List<Object?> rows, {
  String incoming = 'available',
  String? nextCursor,
}) => {
  'schemaVersion': 2,
  'incomingInvitations': incoming,
  'invitations': rows,
  'nextCursor': nextCursor,
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Future<({InvitationsController controller, List<http.BaseRequest> calls})>
_mount(
  WidgetTester tester, {
  required Future<http.Response> Function(http.BaseRequest request) route,
}) async {
  final calls = <http.BaseRequest>[];
  final transport = MockClient((request) {
    calls.add(request);
    return route(request);
  });
  final controller = InvitationsController(
    client: HttpInvitationsClient(
      client: transport,
      baseUri: _base,
      accountId: _account,
      accessToken: () async =>
          const PracticeAccessToken(accountId: _account, token: 'a.b.c'),
    ),
    mutationId: () => _mutation,
  );
  addTearDown(() {
    controller.dispose();
    transport.close();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InvitationsPanel(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (controller: controller, calls: calls);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opening reads the open box and keeps the no-money promise', (
    tester,
  ) async {
    var reads = 0;
    await _mount(
      tester,
      route: (request) async {
        if (request.method == 'GET') reads++;
        return _json(_page(const []));
      },
    );
    expect(reads, 1);
    expect(find.textContaining('carries no money'), findsOneWidget);
    expect(find.text('No open invitations.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('invitations-refresh')));
    await tester.pumpAndSettle();
    expect(reads, 2);
  });

  testWidgets('missing X link is a clear inbox state', (tester) async {
    await _mount(
      tester,
      route: (_) async => _json(_page(const [], incoming: 'x_link_required')),
    );
    expect(
      find.byKey(const ValueKey('invitations-x-link-required')),
      findsOneWidget,
    );
    expect(find.textContaining('Link one X account'), findsOneWidget);
    expect(find.byKey(const ValueKey('invitations-create')), findsOneWidget);
  });

  testWidgets('a sender addresses by handle and then offers', (tester) async {
    var state = 'draft';
    var version = 0;
    final mounted = await _mount(
      tester,
      route: (request) async {
        if (request.url.path.endsWith('/actions')) {
          final body = jsonDecode((request as http.Request).body) as Map;
          state = body['action'] == 'address' ? 'addressed' : 'offered';
          version++;
          return _json(
            _row(state: state, recipient: _recipientJson, version: version),
          );
        }
        if (request.method == 'POST') {
          final body = jsonDecode((request as http.Request).body) as Map;
          return _json(_row(expiresAt: body['expiresAt'] as String));
        }
        return _json(_page(const []));
      },
    );

    await tester.tap(find.byKey(const ValueKey('invitations-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('invitation-handle-$_id')),
      'ada_builds',
    );
    await tester.tap(find.byKey(const ValueKey('invitation-address-$_id')));
    await tester.pumpAndSettle();
    expect(find.text('Addressed to @ada_builds, not sent'), findsOneWidget);

    final address =
        mounted.calls
                .where((request) => request.url.path.endsWith('/actions'))
                .first
            as http.Request;
    expect(jsonDecode(address.body), {
      'schemaVersion': 2,
      'action': 'address',
      'expectedVersion': 0,
      'xHandle': 'ada_builds',
    });
    expect(
      mounted.calls.where(
        (request) => request.url.path.startsWith('/v1/social/x'),
      ),
      isEmpty,
    );

    await tester.tap(find.byKey(const ValueKey('invitation-offer-$_id')));
    await tester.pumpAndSettle();
    expect(
      find.text('Offered to @ada_builds, waiting for an answer'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('invitation-cancel-$_id')),
      findsOneWidget,
    );
  });

  testWidgets('a recipient sees the sender and only answer actions', (
    tester,
  ) async {
    await _mount(
      tester,
      route: (_) async => _json(
        _page([
          _row(
            state: 'offered',
            role: 'recipient',
            recipient: _recipientJson,
            version: 2,
          ),
        ]),
      ),
    );
    expect(find.text('@mira_trade invited you'), findsOneWidget);
    expect(find.text('From @mira_trade'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invitation-accept-$_id')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('invitation-decline-$_id')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('invitation-offer-$_id')), findsNothing);
    expect(find.byKey(const ValueKey('invitation-cancel-$_id')), findsNothing);
  });

  testWidgets('history is fetched separately and can load another page', (
    tester,
  ) async {
    await _mount(
      tester,
      route: (request) async {
        if (request.url.queryParameters['box'] != 'history') {
          return _json(_page(const []));
        }
        final more = request.url.queryParameters.containsKey('cursor');
        return _json(
          _page([
            _row(
              id: more ? _second : _id,
              state: 'canceled',
              createdAt: more
                  ? '2026-09-16T09:00:00.000Z'
                  : '2026-09-16T10:00:00.000Z',
            ),
          ], nextCursor: more ? null : 'next_history'),
        );
      },
    );

    await tester.tap(find.byKey(const ValueKey('invitations-history')));
    await tester.pumpAndSettle();
    expect(find.text('Past invitations'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('invitations-history-more')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('invitations-history-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('invitation-state-$_second')), findsOneWidget);
  });

  testWidgets('a refused step is explained in plain words', (tester) async {
    await _mount(
      tester,
      route: (request) async {
        if (request.url.path.endsWith('/actions')) {
          return _json({
            'error': {
              'code': 'INVITATION_LIMIT_REACHED',
              'message': 'Too many open invitations.',
              'requestId': 'panel-test-request',
            },
          }, 409);
        }
        return _json(
          _page([
            _row(state: 'addressed', recipient: _recipientJson, version: 1),
          ]),
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('invitation-offer-$_id')));
    await tester.pumpAndSettle();
    expect(find.textContaining('too many invitations open'), findsOneWidget);
  });
}
