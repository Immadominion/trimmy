import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/markets/followed_stocks.dart';
import 'package:trimmy/markets/followed_stocks_controller.dart';
import 'package:trimmy/practice_sync/http_transport.dart';

const _account = '9f000000-0000-4000-8000-000000000001';
final _base = Uri.parse('https://api.example');

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _snapshot({
  int revision = 1,
  List<String> assetIds = const ['apple'],
  String? updatedAt = '2026-09-19T10:00:00.000Z',
}) => <String, Object?>{
  'schemaVersion': 1,
  'revision': revision,
  'assetIds': assetIds,
  'updatedAt': revision == 0 ? null : updatedAt,
};

HttpFollowedStocksClient _client(
  http.Client transport, {
  String account = _account,
}) => HttpFollowedStocksClient(
  client: transport,
  baseUri: _base,
  accountId: account,
  accessToken: () async =>
      PracticeAccessToken(accountId: _account, token: 'a.b.c'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the followed list client', () {
    test('reads a snapshot and an empty list', () async {
      final client = _client(
        MockClient((request) async {
          expect(request.url.path, '/v1/following');
          expect(request.method, 'GET');
          return _json(_snapshot(revision: 0, assetIds: const []));
        }),
      );
      final list = await client.read();
      expect(list.revision, 0);
      expect(list.assetIds, isEmpty);
      expect(list.updatedAt, isNull);
    });

    test('writes the whole list at the revision it saw', () async {
      String? sent;
      final client = _client(
        MockClient((request) async {
          sent = request.body;
          return _json(
            _snapshot(revision: 2, assetIds: const ['apple', 'tesla']),
          );
        }),
      );
      final saved = await client.write(
        baseRevision: 1,
        assetIds: const ['apple', 'tesla'],
        mutationId: '11111111-1111-4111-8111-111111111111',
      );
      final body = jsonDecode(sent!) as Map<String, dynamic>;
      expect(body['schemaVersion'], 1);
      expect(body['baseRevision'], 1);
      expect(body['assetIds'], ['apple', 'tesla']);
      expect(saved.revision, 2);
    });

    test(
      'refuses identifiers the server would refuse, before sending',
      () async {
        var sends = 0;
        final client = _client(
          MockClient((request) async {
            sends += 1;
            return _json(_snapshot());
          }),
        );
        for (final bad in [
          ['Apple'],
          ['apple '],
          ['-apple'],
          ['apple--x'],
          ['a' * 101],
          ['apple', 'apple'],
        ]) {
          expect(
            () => client.write(
              baseRevision: 0,
              assetIds: bad,
              mutationId: '11111111-1111-4111-8111-111111111111',
            ),
            throwsA(isA<FollowedStocksException>()),
            reason: bad.toString(),
          );
        }
        expect(sends, 0, reason: 'nothing unusable reaches the network');
      },
    );

    test(
      'refuses a non-HTTPS origin and a token for another account',
      () async {
        expect(
          () => HttpFollowedStocksClient(
            client: MockClient((_) async => _json(_snapshot())),
            baseUri: Uri.parse('http://api.example'),
            accountId: _account,
            accessToken: () async =>
                PracticeAccessToken(accountId: _account, token: 'a.b.c'),
          ),
          throwsA(isA<FollowedStocksException>()),
        );
        final mismatched = HttpFollowedStocksClient(
          client: MockClient((_) async => _json(_snapshot())),
          baseUri: _base,
          accountId: _account,
          accessToken: () async => PracticeAccessToken(
            accountId: '9f000000-0000-4000-8000-000000000002',
            token: 'a.b.c',
          ),
        );
        await expectLater(
          mismatched.read(),
          throwsA(
            isA<FollowedStocksException>().having(
              (error) => error.failure,
              'failure',
              FollowedStocksFailure.accountMismatch,
            ),
          ),
        );
      },
    );

    test('separates the failures that share a status', () async {
      final cases =
          <({int status, String code, FollowedStocksFailure failure})>[
            (
              status: 401,
              code: 'WATCHLIST_UNAUTHENTICATED',
              failure: FollowedStocksFailure.unauthenticated,
            ),
            (
              status: 409,
              code: 'WATCHLIST_REVISION_CONFLICT',
              failure: FollowedStocksFailure.revisionConflict,
            ),
            (
              status: 409,
              code: 'WATCHLIST_IDEMPOTENCY_CONFLICT',
              failure: FollowedStocksFailure.invalidRequest,
            ),
            (
              status: 503,
              code: 'WATCHLIST_UNAVAILABLE',
              failure: FollowedStocksFailure.notConfigured,
            ),
            (
              status: 503,
              code: 'WATCHLIST_REVISION_EXHAUSTED',
              failure: FollowedStocksFailure.limitReached,
            ),
          ];
      for (final row in cases) {
        final client = _client(
          MockClient(
            (_) async => _json({
              'error': {'code': row.code, 'message': 'x', 'requestId': 'r'},
            }, row.status),
          ),
        );
        await expectLater(
          client.read(),
          throwsA(
            isA<FollowedStocksException>().having(
              (error) => error.failure,
              'failure',
              row.failure,
            ),
          ),
          reason: row.code,
        );
      }
    });
  });

  group('the followed list controller', () {
    test('following adds one asset and keeps the rest', () async {
      var revision = 1;
      var stored = <String>['apple'];
      final controller = FollowedStocksController(
        client: _client(
          MockClient((request) async {
            if (request.method == 'GET') {
              return _json(_snapshot(revision: revision, assetIds: stored));
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['baseRevision'], revision);
            stored = (body['assetIds'] as List).cast<String>();
            revision += 1;
            return _json(_snapshot(revision: revision, assetIds: stored));
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.isFollowing('tesla'), isFalse);
      await controller.follow('tesla');
      expect(controller.assetIds, ['apple', 'tesla']);
      expect(controller.failure, isNull);
    });

    test('following something already followed writes nothing', () async {
      var writes = 0;
      final controller = FollowedStocksController(
        client: _client(
          MockClient((request) async {
            if (request.method != 'GET') writes += 1;
            return _json(_snapshot(assetIds: const ['apple']));
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.follow('apple');
      expect(writes, 0);
      expect(controller.assetIds, ['apple']);
    });

    test('unfollowing removes exactly one asset', () async {
      var stored = <String>['apple', 'tesla'];
      final controller = FollowedStocksController(
        client: _client(
          MockClient((request) async {
            if (request.method == 'GET') {
              return _json(_snapshot(revision: 3, assetIds: stored));
            }
            stored = ((jsonDecode(request.body) as Map)['assetIds'] as List)
                .cast<String>();
            return _json(_snapshot(revision: 4, assetIds: stored));
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.unfollow('apple');
      expect(controller.assetIds, ['tesla']);
    });

    test('a concurrent change is reloaded and the tap is not lost', () async {
      // The list moved to revision 5 elsewhere while this client held 1.
      var serverRevision = 1;
      var stored = <String>['apple'];
      var refusals = 0;
      final controller = FollowedStocksController(
        client: _client(
          MockClient((request) async {
            if (request.method == 'GET') {
              return _json(
                _snapshot(revision: serverRevision, assetIds: stored),
              );
            }
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (body['baseRevision'] != serverRevision) {
              refusals += 1;
              return _json({
                'error': {
                  'code': 'WATCHLIST_REVISION_CONFLICT',
                  'message': 'x',
                  'requestId': 'r',
                },
                'currentSnapshot': _snapshot(
                  revision: serverRevision,
                  assetIds: stored,
                ),
              }, 409);
            }
            stored = (body['assetIds'] as List).cast<String>();
            serverRevision += 1;
            return _json(_snapshot(revision: serverRevision, assetIds: stored));
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      // Someone else adds one and moves the revision on.
      serverRevision = 5;
      stored = ['apple', 'nvidia'];
      await controller.follow('tesla');
      expect(refusals, 1, reason: 'the stale write must be refused once');
      expect(controller.failure, isNull, reason: 'the retry succeeded');
      expect(
        controller.assetIds,
        ['apple', 'nvidia', 'tesla'],
        reason: 'the other change is kept and this one is applied on top',
      );
    });

    test(
      'a full list is reported rather than silently dropping the tap',
      () async {
        final full = List<String>.generate(50, (index) => 'asset-$index');
        final controller = FollowedStocksController(
          client: _client(
            MockClient((request) async {
              expect(request.method, 'GET', reason: 'a full list never writes');
              return _json(_snapshot(revision: 2, assetIds: full));
            }),
          ),
        );
        addTearDown(controller.dispose);
        await controller.refresh();
        expect(controller.isFull, isTrue);
        await controller.follow('tesla');
        expect(controller.failure, FollowedStocksFailure.limitReached);
      },
    );

    test('nothing is read until something asks', () async {
      var reads = 0;
      final controller = FollowedStocksController(
        client: _client(
          MockClient((_) async {
            reads += 1;
            return _json(_snapshot());
          }),
        ),
      );
      addTearDown(controller.dispose);
      expect(reads, 0);
      expect(controller.loaded, isFalse);
      await controller.refresh();
      expect(reads, 1);
    });
  });
}
