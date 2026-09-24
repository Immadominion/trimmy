import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/social/http_invitations_client.dart';
import 'package:trimmy/social/http_relationships_client.dart';
import 'package:trimmy/social/invitations_controller.dart';
import 'package:trimmy/social/relationships_controller.dart';
import 'package:trimmy/social/relationships_panel.dart';

const _account = '90000000-0000-4000-8000-000000000001';
const _friendship = '10000000-0000-4000-8000-000000000001';
const _social = '20000000-0000-4000-8000-000000000001';
const _mutation = '30000000-0000-4000-8000-000000000001';
final _base = Uri.parse('https://api.example');

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

void main() {
  testWidgets(
    'friend can be blocked and later unblocked with plain consequences',
    (tester) async {
      var blocked = false;
      var revision = 0;
      final requests = <String>[];
      final transport = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path == '/v1/social/friends') {
          return _json({
            'schemaVersion': 1,
            'friends': [
              {
                'friendshipId': _friendship,
                'revision': 1,
                'connectedAt': '2026-09-20T12:00:00.000Z',
                'person': {
                  'socialId': _social,
                  'handle': 'ada_trade',
                  'persona': 'oracle',
                  'rank': {'id': 'rookie', 'label': 'Rookie'},
                },
              },
            ],
            'nextCursor': null,
          });
        }
        if (request.url.path == '/v1/invitations') {
          return _json({
            'schemaVersion': 2,
            'incomingInvitations': 'available',
            'invitations': const [],
            'nextCursor': null,
          });
        }
        if (request.url.path == '/v1/social/blocks/$_social' &&
            request.method == 'GET') {
          return _json({
            'schemaVersion': 1,
            'block': {
              'socialId': _social,
              'revision': revision,
              'blocked': blocked,
              'updatedAt': revision == 0
                  ? null
                  : '2026-09-20T12:12:0${revision - 1}.000Z',
            },
          });
        }
        if (request.url.path == '/v1/social/blocks' &&
            request.method == 'GET') {
          return _json({
            'schemaVersion': 1,
            'blocks': blocked
                ? [
                    {
                      'socialId': _social,
                      'handle': 'ada_trade',
                      'revision': revision,
                      'updatedAt': '2026-09-20T12:12:0${revision - 1}.000Z',
                    },
                  ]
                : const [],
            'nextCursor': null,
          });
        }
        if (request.url.path == '/v1/social/blocks/$_social' &&
            request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['baseRevision'], revision);
          blocked = body['blocked'] as bool;
          revision++;
          return _json({
            'schemaVersion': 1,
            'mutationId': _mutation,
            'appliedRevision': revision,
            'block': {
              'socialId': _social,
              'revision': revision,
              'blocked': blocked,
              'updatedAt': '2026-09-20T12:12:0${revision - 1}.000Z',
            },
          });
        }
        throw StateError('Unexpected request ${request.method} ${request.url}');
      });
      Future<PracticeAccessToken> token() async => const PracticeAccessToken(
        accountId: _account,
        token: 'header.payload.signature',
      );
      final relationships = RelationshipsController(
        client: HttpRelationshipsClient(
          client: transport,
          baseUri: _base,
          accountId: _account,
          accessToken: token,
        ),
        mutationId: () => _mutation,
      );
      final invitations = InvitationsController(
        client: HttpInvitationsClient(
          client: transport,
          baseUri: _base,
          accountId: _account,
          accessToken: token,
        ),
      );
      addTearDown(() {
        relationships.dispose();
        invitations.dispose();
        transport.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RelationshipsPanel(
                relationships: relationships,
                invitations: invitations,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('@ada_trade'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('relationship-block-$_friendship')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('cancels open invitations'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Block'));
      await tester.pumpAndSettle();

      expect(find.text('@ada_trade'), findsNothing);
      expect(
        find.textContaining('friendship and open invitations'),
        findsOneWidget,
      );
      expect(blocked, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('relationships-blocks-toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('relationship-blocked-$_social')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('relationship-unblock-$_social')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('does not restore'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('relationship-blocked-$_social')),
        findsNothing,
      );
      expect(blocked, isFalse);
      expect(requests, contains('GET /v1/social/blocks/$_social'));
      expect(requests.where((value) => value.startsWith('PUT ')), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}
