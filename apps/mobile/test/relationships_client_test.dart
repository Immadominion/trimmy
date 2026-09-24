import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/social/http_relationships_client.dart';
import 'package:trimmy/social/relationship.dart';

const _account = '90000000-0000-4000-8000-000000000001';
const _otherAccount = '90000000-0000-4000-8000-000000000002';
const _friendship = '10000000-0000-4000-8000-000000000001';
const _social = '20000000-0000-4000-8000-000000000001';
const _mutation = '30000000-0000-4000-8000-000000000001';
const _reason = '40000000-0000-4000-8000-000000000001';
const _report = '50000000-0000-4000-8000-000000000001';
final _base = Uri.parse('https://api.example');

const _person = {
  'socialId': _social,
  'handle': 'ada_trade',
  'persona': 'oracle',
  'rank': {'id': 'rookie', 'label': 'Rookie'},
};

Map<String, Object?> _friend({
  String friendshipId = _friendship,
  String connectedAt = '2026-09-20T12:00:00.000Z',
}) => {
  'friendshipId': friendshipId,
  'revision': 1,
  'connectedAt': connectedAt,
  'person': _person,
};

Map<String, Object?> _block({
  String socialId = _social,
  String? handle = 'ada_trade',
  int revision = 1,
  String updatedAt = '2026-09-20T12:12:00.000Z',
}) => {
  'socialId': socialId,
  'handle': handle,
  'revision': revision,
  'updatedAt': updatedAt,
};

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

HttpRelationshipsClient _client(
  Future<http.Response> Function(http.Request request) route, {
  String tokenAccount = _account,
}) => HttpRelationshipsClient(
  client: MockClient(route),
  baseUri: _base,
  accountId: _account,
  accessToken: () async => PracticeAccessToken(
    accountId: tokenAccount,
    token: 'header.payload.signature',
  ),
);

Future<RelationshipFailure> _failure(Future<Object?> work) async {
  try {
    await work;
  } on RelationshipException catch (error) {
    return error.failure;
  }
  throw StateError('expected relationship failure');
}

void main() {
  test(
    'friends list is bounded, account-bound and strictly projected',
    () async {
      late http.Request sent;
      final client = _client((request) async {
        sent = request;
        return _json({
          'schemaVersion': 1,
          'friends': [_friend()],
          'nextCursor': 'next_page',
        });
      });

      final page = await client.listFriends(limit: 7, cursor: 'current_page');

      expect(sent.method, 'GET');
      expect(sent.url.path, '/v1/social/friends');
      expect(sent.url.queryParameters, {
        'limit': '7',
        'cursor': 'current_page',
      });
      expect(sent.headers['authorization'], 'Bearer header.payload.signature');
      expect(sent.headers['cache-control'], 'no-store');
      expect(page.friends.single.friendshipId, _friendship);
      expect(page.friends.single.person.socialId, _social);
      expect(page.friends.single.person.rank.label, 'Rookie');
      expect(page.nextCursor, 'next_page');
    },
  );

  test('friend rows reject duplicates, wrong order and extra fields', () {
    final earlier = _friend(
      friendshipId: '10000000-0000-4000-8000-000000000002',
      connectedAt: '2026-09-20T11:00:00.000Z',
    );
    for (final rows in [
      [_friend(), _friend()],
      [earlier, _friend()],
      [
        {..._friend(), 'internalUserId': _account},
      ],
    ]) {
      expect(
        () => FriendPage.fromJson({
          'schemaVersion': 1,
          'friends': rows,
          'nextCursor': null,
        }, limit: 20),
        throwsA(
          isA<RelationshipException>().having(
            (error) => error.failure,
            'failure',
            RelationshipFailure.invalidResponse,
          ),
        ),
      );
    }
  });

  test('friend rows reject personas outside the public enum', () {
    expect(
      () => FriendPage.fromJson({
        'schemaVersion': 1,
        'friends': [
          {
            ..._friend(),
            'person': {..._person, 'persona': 'unknown-persona'},
          },
        ],
        'nextCursor': null,
      }, limit: 20),
      throwsA(isA<RelationshipException>()),
    );
  });

  test('remove sends one exact revision-checked command', () async {
    late http.Request sent;
    final command = FriendRemoveCommand(
      friendshipId: _friendship,
      mutationId: _mutation,
      expectedRevision: 1,
    );
    final client = _client((request) async {
      sent = request;
      return _json({
        'schemaVersion': 1,
        'mutationId': _mutation,
        'friendshipId': _friendship,
        'appliedRevision': 2,
        'state': 'removed',
        'occurredAt': '2026-09-20T12:10:00.000Z',
      });
    });

    final receipt = await client.removeFriend(command);

    expect(sent.method, 'POST');
    expect(sent.url.path, '/v1/social/friends/$_friendship/actions');
    expect(jsonDecode(sent.body), command.body);
    expect(receipt.appliedRevision, 2);
  });

  test(
    'blocks list retains a closed target without inventing a handle',
    () async {
      final client = _client(
        (_) async => _json({
          'schemaVersion': 1,
          'blocks': [_block(handle: null, revision: 4)],
          'nextCursor': null,
        }),
      );

      final page = await client.listBlocks();

      expect(page.blocks.single.handle, isNull);
      expect(page.blocks.single.revision, 4);
    },
  );

  test('exact block lookup exposes absent and inactive caller state', () async {
    var reads = 0;
    final client = _client((request) async {
      reads++;
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/social/blocks/$_social');
      return _json({
        'schemaVersion': 1,
        'block': reads == 1
            ? {
                'socialId': _social,
                'revision': 0,
                'blocked': false,
                'updatedAt': null,
              }
            : {
                'socialId': _social,
                'revision': 2,
                'blocked': false,
                'updatedAt': '2026-09-20T12:14:00.000Z',
              },
      });
    });

    final absent = await client.getBlock(_social);
    final inactive = await client.getBlock(_social);

    expect(absent.revision, 0);
    expect(absent.updatedAt, isNull);
    expect(inactive.revision, 2);
    expect(inactive.updatedAt, DateTime.utc(2026, 9, 20, 12, 14));
  });

  test('block lookup rejects mismatched and impossible snapshots', () async {
    for (final block in [
      {
        'socialId': '20000000-0000-4000-8000-000000000002',
        'revision': 0,
        'blocked': false,
        'updatedAt': null,
      },
      {'socialId': _social, 'revision': 0, 'blocked': true, 'updatedAt': null},
      {'socialId': _social, 'revision': 2, 'blocked': false, 'updatedAt': null},
    ]) {
      final client = _client(
        (_) async => _json({'schemaVersion': 1, 'block': block}),
      );
      expect(
        await _failure(client.getBlock(_social)),
        RelationshipFailure.invalidResponse,
      );
    }
  });

  test('block and report accept only their exact public receipts', () async {
    final calls = <http.Request>[];
    final client = _client((request) async {
      calls.add(request);
      if (request.url.path.startsWith('/v1/social/blocks/')) {
        return _json({
          'schemaVersion': 1,
          'mutationId': _mutation,
          'appliedRevision': 1,
          'block': {
            'socialId': _social,
            'revision': 1,
            'blocked': true,
            'updatedAt': '2026-09-20T12:12:00.000Z',
          },
        });
      }
      return _json({
        'schemaVersion': 1,
        'report': {
          'reportId': _report,
          'reasonId': _reason,
          'category': 'harassment',
          'receivedAt': '2026-09-20T12:15:00.000Z',
        },
      }, 202);
    });
    final block = BlockCommand(
      socialId: _social,
      mutationId: _mutation,
      baseRevision: 0,
      blocked: true,
    );
    final report = ReasonReportCommand(
      mutationId: _mutation,
      reasonId: _reason,
      category: ReasonReportCategory.harassment,
    );

    expect((await client.putBlock(block)).block.blocked, isTrue);
    expect((await client.reportReason(report)).reportId, _report);
    expect(calls[0].method, 'PUT');
    expect(calls[0].url.path, '/v1/social/blocks/$_social');
    expect(jsonDecode(calls[0].body), block.body);
    expect(calls[1].method, 'POST');
    expect(calls[1].url.path, '/v1/social/reason-reports');
    expect(jsonDecode(calls[1].body), report.body);
  });

  test(
    'block receipt binds the requested state at its applied revision',
    () async {
      final command = BlockCommand(
        socialId: _social,
        mutationId: _mutation,
        baseRevision: 0,
        blocked: true,
      );
      final client = _client(
        (_) async => _json({
          'schemaVersion': 1,
          'mutationId': _mutation,
          'appliedRevision': 1,
          'block': {
            'socialId': _social,
            'revision': 1,
            'blocked': false,
            'updatedAt': '2026-09-20T12:12:00.000Z',
          },
        }),
      );

      expect(
        await _failure(client.putBlock(command)),
        RelationshipFailure.invalidResponse,
      );
    },
  );

  test('maximum safe revisions remain readable', () {
    final page = FriendPage.fromJson({
      'schemaVersion': 1,
      'friends': [
        {..._friend(), 'revision': 9007199254740991},
      ],
      'nextCursor': null,
    }, limit: 20);

    expect(page.friends.single.revision, 9007199254740991);
  });

  test(
    'report replay returns the original category without getting stuck',
    () async {
      final command = ReasonReportCommand(
        mutationId: _mutation,
        reasonId: _reason,
        category: ReasonReportCategory.harassment,
      );
      Object response() => {
        'schemaVersion': 1,
        'report': {
          'reportId': _report,
          'reasonId': _reason,
          'category': 'spam',
          'receivedAt': '2026-09-20T12:15:00.000Z',
        },
      };
      final replayClient = _client((_) async => _json(response()));
      final createdClient = _client((_) async => _json(response(), 202));

      expect(
        (await replayClient.reportReason(command)).category,
        ReasonReportCategory.spam,
      );
      expect(
        await _failure(createdClient.reportReason(command)),
        RelationshipFailure.invalidResponse,
      );
    },
  );

  test('mismatched receipts and response leaks fail closed', () async {
    final command = ReasonReportCommand(
      mutationId: _mutation,
      reasonId: _reason,
      category: ReasonReportCategory.spam,
    );
    for (final report in [
      {
        'reportId': _report,
        'reasonId': '40000000-0000-4000-8000-000000000002',
        'category': 'spam',
        'receivedAt': '2026-09-20T12:15:00.000Z',
      },
      {
        'reportId': _report,
        'reasonId': _reason,
        'category': 'spam',
        'receivedAt': '2026-09-20T12:15:00.000Z',
        'authorId': _account,
      },
    ]) {
      final client = _client(
        (_) async => _json({'schemaVersion': 1, 'report': report}, 202),
      );
      expect(
        await _failure(client.reportReason(command)),
        RelationshipFailure.invalidResponse,
      );
    }
  });

  test('stable safety errors map without provider details', () async {
    for (final entry in const <String, RelationshipFailure>{
      'SOCIAL_RELATIONSHIP_REVISION_CONFLICT':
          RelationshipFailure.revisionConflict,
      'SOCIAL_BLOCK_IDEMPOTENCY_CONFLICT':
          RelationshipFailure.idempotencyConflict,
      'SOCIAL_PAIR_UNAVAILABLE': RelationshipFailure.pairUnavailable,
      'SOCIAL_RATE_LIMITED': RelationshipFailure.rateLimited,
    }.entries) {
      final client = _client(
        (_) async => _json({
          'error': {
            'code': entry.key,
            'message': 'Safe public message.',
            'requestId': 'request-one',
          },
        }, entry.key == 'SOCIAL_RATE_LIMITED' ? 429 : 409),
      );
      expect(
        await _failure(client.listFriends()),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('malformed or widened error responses fail closed', () async {
    for (final response in [
      _json({
        'error': {
          'code': 'SOCIAL_RATE_LIMITED',
          'message': 'Safe public message.',
          'requestId': 'request-one',
          'providerPayload': 'private',
        },
      }, 429),
      http.Response(
        '<html>gateway</html>',
        503,
        headers: const {'content-type': 'text/html'},
      ),
    ]) {
      final client = _client((_) async => response);
      expect(
        await _failure(client.listFriends()),
        RelationshipFailure.invalidResponse,
      );
    }
  });

  test('token account mismatch and invalid page controls never send', () async {
    var calls = 0;
    final client = _client((_) async {
      calls++;
      return _json(const {});
    }, tokenAccount: _otherAccount);

    expect(
      await _failure(client.listFriends()),
      RelationshipFailure.accountMismatch,
    );
    expect(
      await _failure(client.listBlocks(limit: 51)),
      RelationshipFailure.invalidRequest,
    );
    expect(calls, 0);
  });
}
