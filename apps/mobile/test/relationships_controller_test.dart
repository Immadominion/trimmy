import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/social/http_relationships_client.dart';
import 'package:trimmy/social/relationship.dart';
import 'package:trimmy/social/relationship_mutation_store.dart';
import 'package:trimmy/social/relationships_controller.dart';

const _account = '90000000-0000-4000-8000-000000000001';
const _friendship = '10000000-0000-4000-8000-000000000001';
const _social = '20000000-0000-4000-8000-000000000001';
const _mutation = '30000000-0000-4000-8000-000000000001';
const _reason = '40000000-0000-4000-8000-000000000001';
const _report = '50000000-0000-4000-8000-000000000001';
final _base = Uri.parse('https://api.example');

final class _DelayedRemoveStore implements RelationshipMutationStore {
  RelationshipMutationCommand? command;
  final removeStarted = Completer<void>();
  final allowRemove = Completer<void>();

  @override
  Future<List<RelationshipMutationCommand>> read(String accountId) async => [
    ?command,
  ];

  @override
  Future<bool> write(
    String accountId,
    RelationshipMutationCommand value,
  ) async {
    command = value;
    return true;
  }

  @override
  Future<bool> remove(
    String accountId,
    RelationshipMutationCommand value,
  ) async {
    removeStarted.complete();
    await allowRemove.future;
    if (command != value) return false;
    command = null;
    return true;
  }
}

Map<String, Object?> _friendRow({
  String friendshipId = _friendship,
  String socialId = _social,
  int revision = 1,
}) => {
  'friendshipId': friendshipId,
  'revision': revision,
  'connectedAt': '2026-09-20T12:00:00.000Z',
  'person': {
    'socialId': socialId,
    'handle': 'ada_trade',
    'persona': 'oracle',
    'rank': {'id': 'rookie', 'label': 'Rookie'},
  },
};

Map<String, Object?> _friendPage(List<Object?> rows, {String? nextCursor}) => {
  'schemaVersion': 1,
  'friends': rows,
  'nextCursor': nextCursor,
};

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

({RelationshipsController controller, MockClient transport}) _build({
  required Future<http.Response> Function(http.Request request) route,
  RelationshipMutationStore? store,
  String mutationId = _mutation,
}) {
  final transport = MockClient(route);
  final controller = RelationshipsController(
    client: HttpRelationshipsClient(
      client: transport,
      baseUri: _base,
      accountId: _account,
      accessToken: () async => const PracticeAccessToken(
        accountId: _account,
        token: 'header.payload.signature',
      ),
    ),
    mutationStore: store,
    mutationId: () => mutationId,
  );
  addTearDown(() {
    controller.dispose();
    transport.close();
  });
  return (controller: controller, transport: transport);
}

void main() {
  test(
    'refresh and confirmed remove update only the account session',
    () async {
      final bodies = <Object?>[];
      final store = MemoryRelationshipMutationStore();
      final built = _build(
        store: store,
        route: (request) async {
          if (request.method == 'GET') {
            return _json(_friendPage([_friendRow()]));
          }
          bodies.add(jsonDecode(request.body));
          return _json({
            'schemaVersion': 1,
            'mutationId': _mutation,
            'friendshipId': _friendship,
            'appliedRevision': 2,
            'state': 'removed',
            'occurredAt': '2026-09-20T12:10:00.000Z',
          });
        },
      );

      expect(await built.controller.refreshFriends(), isTrue);
      expect(built.controller.friends.single.person.handle, 'ada_trade');
      expect(
        await built.controller.removeFriend(built.controller.friends.single),
        isTrue,
      );

      expect(bodies.single, {
        'schemaVersion': 1,
        'action': 'remove',
        'mutationId': _mutation,
        'expectedRevision': 1,
      });
      expect(built.controller.friends, isEmpty);
      expect(built.controller.notice, RelationshipNotice.friendRemoved);
      expect(await store.read(_account), isEmpty);
    },
  );

  test(
    'block reads exact inactive revision before persisting the write',
    () async {
      final calls = <http.Request>[];
      final store = MemoryRelationshipMutationStore();
      final built = _build(
        store: store,
        route: (request) async {
          calls.add(request);
          if (request.url.path == '/v1/social/friends') {
            return _json(_friendPage([_friendRow()]));
          }
          if (request.method == 'GET') {
            return _json({
              'schemaVersion': 1,
              'block': {
                'socialId': _social,
                'revision': 2,
                'blocked': false,
                'updatedAt': '2026-09-20T12:11:00.000Z',
              },
            });
          }
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['baseRevision'], 2);
          expect((await store.read(_account)).single, isA<BlockCommand>());
          return _json({
            'schemaVersion': 1,
            'mutationId': _mutation,
            'appliedRevision': 3,
            'block': {
              'socialId': _social,
              'revision': 3,
              'blocked': true,
              'updatedAt': '2026-09-20T12:12:00.000Z',
            },
          });
        },
      );
      await built.controller.refreshFriends();

      expect(
        await built.controller.setBlocked(
          socialId: _social,
          blocked: true,
          knownHandle: 'ada_trade',
        ),
        isTrue,
      );

      expect(calls.map((request) => '${request.method} ${request.url.path}'), [
        'GET /v1/social/friends',
        'GET /v1/social/blocks/$_social',
        'PUT /v1/social/blocks/$_social',
      ]);
      expect(built.controller.friends, isEmpty);
      expect(built.controller.blocks.single.handle, 'ada_trade');
      expect(built.controller.blocks.single.revision, 3);
      expect(built.controller.blocksLoaded, isFalse);
      expect(built.controller.notice, RelationshipNotice.blocked);
      expect(await store.read(_account), isEmpty);
    },
  );

  test(
    'ambiguous report survives restart and replays the original command',
    () async {
      final store = MemoryRelationshipMutationStore();
      final firstBodies = <Map<String, dynamic>>[];
      final first = _build(
        store: store,
        route: (request) async {
          firstBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          throw http.ClientException('response lost');
        },
      );

      expect(
        await first.controller.reportReason(
          reasonId: _reason,
          category: ReasonReportCategory.harassment,
        ),
        isFalse,
      );
      expect(first.controller.failure, RelationshipFailure.unavailable);
      expect(await store.read(_account), hasLength(1));
      first.controller.dispose();

      final secondBodies = <Map<String, dynamic>>[];
      final second = _build(
        store: store,
        mutationId: '30000000-0000-4000-8000-000000000002',
        route: (request) async {
          secondBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _json({
            'schemaVersion': 1,
            'report': {
              'reportId': _report,
              'reasonId': _reason,
              // Another device reported this reason as spam first. The server
              // returns that original durable receipt on the 200 replay path.
              'category': 'spam',
              'receivedAt': '2026-09-20T12:15:00.000Z',
            },
          });
        },
      );

      expect(await second.controller.resumePendingMutations(), isTrue);
      expect(secondBodies.single, firstBodies.single);
      expect(second.controller.hasReported(_reason), isTrue);
      expect(second.controller.notice, RelationshipNotice.reasonReported);
      expect(await store.read(_account), isEmpty);
    },
  );

  test(
    'revision conflict clears a resolved command and keeps local rows',
    () async {
      final store = MemoryRelationshipMutationStore();
      final built = _build(
        store: store,
        route: (request) async {
          if (request.url.path == '/v1/social/friends') {
            return _json(_friendPage([_friendRow()]));
          }
          if (request.method == 'GET') {
            return _json({
              'schemaVersion': 1,
              'block': {
                'socialId': _social,
                'revision': 2,
                'blocked': false,
                'updatedAt': '2026-09-20T12:11:00.000Z',
              },
            });
          }
          return _json({
            'error': {
              'code': 'SOCIAL_BLOCK_REVISION_CONFLICT',
              'message': 'The block changed.',
              'requestId': 'request-one',
            },
          }, 409);
        },
      );
      await built.controller.refreshFriends();

      expect(
        await built.controller.setBlocked(socialId: _social, blocked: true),
        isFalse,
      );

      expect(built.controller.failure, RelationshipFailure.revisionConflict);
      expect(built.controller.friends, hasLength(1));
      expect(built.controller.blocks, isEmpty);
      expect(await store.read(_account), isEmpty);
    },
  );

  test('disposal cannot be undone by delayed journal cleanup', () async {
    final store = _DelayedRemoveStore();
    final built = _build(
      store: store,
      route: (request) async {
        if (request.method == 'GET') {
          return _json(_friendPage([_friendRow()]));
        }
        return _json({
          'schemaVersion': 1,
          'mutationId': _mutation,
          'friendshipId': _friendship,
          'appliedRevision': 2,
          'state': 'removed',
          'occurredAt': '2026-09-20T12:10:00.000Z',
        });
      },
    );
    await built.controller.refreshFriends();

    final removing = built.controller.removeFriend(
      built.controller.friends.single,
    );
    await store.removeStarted.future;
    built.controller.dispose();
    store.allowRemove.complete();
    expect(await removing, isTrue);

    expect(built.controller.friends, isEmpty);
    expect(built.controller.blocks, isEmpty);
    expect(built.controller.notice, isNull);
    expect(await store.read(_account), isEmpty);
  });
}
