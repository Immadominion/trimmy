import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/career/career.dart';

const _mutation = '11111111-1111-4111-8111-111111111111';
const _mint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const _otherMint = 'So11111111111111111111111111111111111111112';
const _reasonA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _reasonB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _reasonC = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _orderA = '44444444-4444-4444-8444-444444444444';
const _orderB = '55555555-5555-4555-8555-555555555555';
const _social = '66666666-6666-4666-8666-666666666666';

void main() {
  test('strictly reads the default reason privacy', () async {
    final repository = HttpReasonSharingRepository(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/career/reason-privacy');
        expect(request.url.query, isEmpty);
        expect(request.body, isEmpty);
        expect(
          request.headers['authorization'],
          'Guest tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        );
        return _json({'schemaVersion': 1, 'reasonPrivacy': _privacy()});
      }),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async => const GuestPaperAuthorization(
        'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ),
    );

    final privacy = await repository.getPrivacy();

    expect(privacy.revision, 1);
    expect(privacy.visibility, ReasonVisibility.nobody);
    expect(privacy.configured, isFalse);
    expect(privacy.friendsSharingAvailable, isFalse);
    expect(privacy.createdAt, DateTime.utc(2026, 9, 20, 10));
    expect(privacy.updatedAt, privacy.createdAt);
  });

  test('accepts the server-owned friends sharing capability', () async {
    final repository = _repository(
      MockClient(
        (_) async => _json({
          'schemaVersion': 1,
          'reasonPrivacy': _privacy(friendsSharing: 'available'),
        }),
      ),
    );

    final privacy = await repository.getPrivacy();

    expect(privacy.friendsSharing, FriendsSharingAvailability.available);
    expect(privacy.friendsSharingAvailable, isTrue);
  });

  test('puts one exact privacy command and binds its receipt', () async {
    final repository = _repository(
      MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/v1/career/reason-privacy');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {
          'schemaVersion': 1,
          'mutationId': _mutation,
          'baseRevision': 1,
          'visibility': 'everyone',
        });
        return _json({
          'schemaVersion': 1,
          'reasonPrivacy': _privacy(revision: 2, visibility: 'everyone'),
        });
      }),
    );

    final receipt = await repository.putPrivacy(
      ReasonPrivacyWrite(
        mutationId: _mutation.toUpperCase(),
        baseRevision: 1,
        visibility: ReasonVisibility.everyone,
      ),
    );

    expect(receipt.mutationId, _mutation);
    expect(receipt.baseRevision, 1);
    expect(receipt.visibility, ReasonVisibility.everyone);
    expect(receipt.exact, isTrue);
    expect(receipt.privacy.revision, 2);
    expect(receipt.privacy.configured, isTrue);
    expect(receipt.privacy.visibility, ReasonVisibility.everyone);
  });

  test('accepts an exact replay answered by a later privacy change', () async {
    final repository = _repository(
      MockClient(
        (_) async => _json({
          'schemaVersion': 1,
          'reasonPrivacy': _privacy(revision: 3, visibility: 'friends'),
        }),
      ),
    );

    final receipt = await repository.putPrivacy(
      ReasonPrivacyWrite(
        mutationId: _mutation,
        baseRevision: 1,
        visibility: ReasonVisibility.everyone,
      ),
    );

    expect(receipt.exact, isFalse);
    expect(receipt.privacy.revision, 3);
    expect(receipt.privacy.visibility, ReasonVisibility.friends);
  });

  test('rejects privacy receipts that cannot prove the write', () async {
    for (final privacy in [
      _privacy(),
      _privacy(revision: 2, visibility: 'nobody'),
      _privacy(revision: 1, visibility: 'everyone', configured: true),
    ]) {
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({'schemaVersion': 1, 'reasonPrivacy': privacy}),
          ),
        ).putPrivacy(
          ReasonPrivacyWrite(
            mutationId: _mutation,
            baseRevision: 1,
            visibility: ReasonVisibility.everyone,
          ),
        ),
        throwsA(_failure(ReasonSharingFailure.invalidResponse)),
      );
    }
  });

  test('rejects malformed and impossible privacy resources', () async {
    final invalid = <Map<String, Object?>>[
      _privacy()..['extra'] = true,
      _privacy()..remove('friendsSharing'),
      _privacy()..['friendsSharing'] = 'sometimes',
      _privacy()..['visibility'] = 'public',
      _privacy()..['configured'] = 'no',
      _privacy(revision: 1, configured: true),
      _privacy(revision: 1, visibility: 'everyone'),
      _privacy(revision: 2, visibility: 'everyone', configured: true)
        ..['updatedAt'] = '2026-09-20T10:00:00.000Z',
      _privacy()..['updatedAt'] = '2026-09-20T09:59:59.000Z',
      _privacy()..['createdAt'] = '2026-09-20T10:00:00Z',
      _privacy()..['revision'] = 0,
    ];

    for (final privacy in invalid) {
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({'schemaVersion': 1, 'reasonPrivacy': privacy}),
          ),
        ).getPrivacy(),
        throwsA(_failure(ReasonSharingFailure.invalidResponse)),
        reason: jsonEncode(privacy),
      );
    }
  });

  test('validates privacy writes before network access', () {
    expect(
      () => ReasonPrivacyWrite(
        mutationId: 'not-a-uuid',
        baseRevision: 1,
        visibility: ReasonVisibility.nobody,
      ),
      throwsA(_failure(ReasonSharingFailure.invalidInput)),
    );
    expect(
      () => ReasonPrivacyWrite(
        mutationId: _mutation,
        baseRevision: 0,
        visibility: ReasonVisibility.nobody,
      ),
      throwsA(_failure(ReasonSharingFailure.invalidInput)),
    );
    final write = ReasonPrivacyWrite(
      mutationId: _mutation,
      baseRevision: 4,
      visibility: ReasonVisibility.friends,
    );
    final restored = ReasonPrivacyWrite.fromJson(write.toJson());
    expect(restored?.mutationId, _mutation);
    expect(restored?.baseRevision, 4);
    expect(restored?.visibility, ReasonVisibility.friends);
    expect(ReasonPrivacyWrite.fromJson(write.toJson()..['extra'] = 1), isNull);
    expect(
      ReasonPrivacyWrite.fromJson(write.toJson()..['visibility'] = 'all'),
      isNull,
    );
  });

  test(
    'lists everyone reasons for one exact stock and binds the cursor',
    () async {
      final second = _sharedReason(
        reasonId: _reasonB,
        savedAt: '2026-09-20T12:00:00.000Z',
        isViewer: true,
      );
      final cursor = _cursor(
        scope: 'everyone',
        savedAt: '2026-09-20T12:00:00.000Z',
        reasonId: _reasonB,
      );
      final repository = _repository(
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/v1/career/trade-reasons');
          expect(request.url.queryParameters, {
            'scope': 'everyone',
            'limit': '2',
            'assetId': 'apple',
            'variantMint': _mint,
          });
          return _json(
            _envelope(
              scope: 'everyone',
              limit: 2,
              reasons: [
                _sharedReason(
                  reasonId: _reasonA,
                  savedAt: '2026-09-20T12:00:01.000Z',
                ),
                second,
              ],
              nextCursor: cursor,
            ),
          );
        }),
      );

      final page = await repository.listSharedReasons(
        SharedReasonQuery(assetId: 'apple', variantMint: _mint, limit: 2),
      );

      expect(page.items, hasLength(2));
      expect(page.limit, 2);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, cursor);
      expect(page.items[0].reasonId, _reasonA);
      expect(page.items[0].author.handle, 'ada_trade');
      expect(page.items[0].author.rank, CareerRank.analyst);
      expect(page.items[0].author.rankLabel, 'Analyst');
      expect(page.items[0].author.isViewer, isFalse);
      expect(page.items[0].stock.symbol, 'AAPLx');
      expect(page.items[0].note, 'Margins improved for a second quarter.');
      expect(page.items[0].savedAt, DateTime.utc(2026, 9, 20, 12, 0, 1));
      expect(page.items[1].author.isViewer, isTrue);
      expect(() => page.items.clear(), throwsUnsupportedError);
      final decoded = ReasonCursor.decode(cursor);
      expect(decoded?.scope, 'everyone');
      expect(decoded?.assetId, 'apple');
      expect(decoded?.variantMint, _mint);
      expect(decoded?.reasonId, _reasonB);
    },
  );

  test('lists friends with their public social identity and persona', () async {
    final cursor = _cursor(
      scope: 'friends',
      savedAt: '2026-09-20T12:00:00.000Z',
      reasonId: _reasonA,
    );
    final repository = _repository(
      MockClient((request) async {
        expect(request.url.queryParameters, {
          'scope': 'friends',
          'limit': '1',
          'assetId': 'apple',
          'variantMint': _mint,
        });
        return _json(
          _envelope(
            scope: 'friends',
            limit: 1,
            reasons: [
              _friendReason(
                reasonId: _reasonA,
                savedAt: '2026-09-20T12:00:00.000Z',
              ),
            ],
            nextCursor: cursor,
          ),
        );
      }),
    );

    final page = await repository.listFriendReasons(
      SharedReasonQuery(assetId: 'apple', variantMint: _mint, limit: 1),
    );

    expect(page.items.single.author.socialId, _social);
    expect(page.items.single.author.persona, 'oracle');
    expect(page.items.single.author.isViewer, isFalse);
    expect(ReasonCursor.decode(cursor)?.scope, 'friends');
  });

  test('friends rows require the bounded public author projection', () async {
    for (final row in [
      _friendReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
        ..['author'] = _sharedReason(
          reasonId: _reasonA,
          savedAt: '2026-09-20T12:00:00.000Z',
        )['author'],
      _friendReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
        ..['author'] = {
          'socialId': _social,
          'handle': 'ada_trade',
          'persona': 'Oracle!',
          'rank': {'id': 'analyst', 'label': 'Analyst'},
          'isViewer': false,
        },
      _friendReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
        ..['author'] = {
          'socialId': _social,
          'handle': 'ada_trade',
          'persona': 'spark',
          'rank': {'id': 'analyst', 'label': 'Analyst'},
          'isViewer': false,
        },
      _friendReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
        ..['author'] = {
          'socialId': _social,
          'handle': 'ada_trade',
          'persona': 'oracle',
          'rank': {'id': 'analyst', 'label': 'Analyst'},
          'isViewer': true,
        },
    ]) {
      await expectLater(
        _repository(
          MockClient(
            (_) async =>
                _json(_envelope(scope: 'friends', limit: 20, reasons: [row])),
          ),
        ).listFriendReasons(
          SharedReasonQuery(assetId: 'apple', variantMint: _mint),
        ),
        throwsA(_failure(ReasonSharingFailure.invalidResponse)),
      );
    }
  });

  test('continues from a cursor and requires rows strictly after it', () async {
    final cursor = _cursor(
      scope: 'everyone',
      savedAt: '2026-09-20T12:00:00.000Z',
      reasonId: _reasonB,
    );
    http.Response respond(http.Request request, String reasonId) {
      expect(request.url.queryParameters['cursor'], cursor);
      return _json(
        _envelope(
          scope: 'everyone',
          limit: 20,
          reasons: [
            _sharedReason(
              reasonId: reasonId,
              savedAt: '2026-09-20T12:00:00.000Z',
            ),
          ],
        ),
      );
    }

    final page =
        await _repository(
          MockClient((request) async => respond(request, _reasonA)),
        ).listSharedReasons(
          SharedReasonQuery(
            assetId: 'apple',
            variantMint: _mint,
            cursor: cursor,
          ),
        );
    expect(page.items.single.reasonId, _reasonA);
    expect(page.hasMore, isFalse);

    await expectLater(
      _repository(
        MockClient((request) async => respond(request, _reasonC)),
      ).listSharedReasons(
        SharedReasonQuery(assetId: 'apple', variantMint: _mint, cursor: cursor),
      ),
      throwsA(_failure(ReasonSharingFailure.invalidResponse)),
    );
    await expectLater(
      _repository(MockClient((_) async => _json({}))).listSharedReasons(
        SharedReasonQuery(
          assetId: 'apple',
          variantMint: _otherMint,
          cursor: cursor,
        ),
      ),
      throwsA(_failure(ReasonSharingFailure.invalidInput)),
    );
  });

  test('lists the complete self history with order identity', () async {
    final repository = _repository(
      MockClient((request) async {
        expect(request.url.queryParameters, {'scope': 'self', 'limit': '20'});
        return _json(
          _envelope(
            scope: 'self',
            filter: null,
            limit: 20,
            reasons: [
              _ownReason(
                reasonId: _reasonA,
                orderId: _orderA,
                savedAt: '2026-09-20T12:00:00.000Z',
              ),
              _ownReason(
                reasonId: _reasonB,
                orderId: _orderB,
                savedAt: '2026-09-19T12:00:00.000Z',
                deskCycle: 'historical',
              ),
            ],
          ),
        );
      }),
    );

    final page = await repository.listOwnReasons(OwnReasonQuery());

    expect(page.items, hasLength(2));
    expect(page.items[0].orderId, _orderA);
    expect(page.items[0].deskCycle, ReasonDeskCycle.current);
    expect(page.items[0].author.isViewer, isTrue);
    expect(page.items[1].deskCycle, ReasonDeskCycle.historical);
    expect(page.hasMore, isFalse);
  });

  test('sends the exact self stock filter and checks the echo', () async {
    var calls = 0;
    final repository = _repository(
      MockClient((request) async {
        calls++;
        expect(request.url.queryParameters, {
          'scope': 'self',
          'limit': '50',
          'assetId': 'apple',
          'variantMint': _mint,
        });
        return _json(
          _envelope(
            scope: 'self',
            limit: 50,
            filter: calls == 1
                ? {'assetId': 'apple', 'variantMint': _mint}
                : {'assetId': 'apple', 'variantMint': _otherMint},
            reasons: const [],
          ),
        );
      }),
    );
    final query = OwnReasonQuery(
      assetId: 'apple',
      variantMint: _mint,
      limit: 50,
    );

    expect((await repository.listOwnReasons(query)).items, isEmpty);
    await expectLater(
      repository.listOwnReasons(query),
      throwsA(_failure(ReasonSharingFailure.invalidResponse)),
    );
  });

  test('rejects widened, disordered or mismatched reason pages', () async {
    Map<String, Object?> shared({
      List<Map<String, Object?>>? reasons,
      String? nextCursor,
      int limit = 20,
      String scope = 'everyone',
      Object? filter = const {'assetId': 'apple', 'variantMint': _mint},
    }) => _envelope(
      scope: scope,
      limit: limit,
      filter: filter,
      reasons:
          reasons ??
          [
            _sharedReason(
              reasonId: _reasonA,
              savedAt: '2026-09-20T12:00:00.000Z',
            ),
          ],
      nextCursor: nextCursor,
    );
    final cases = <String, Map<String, Object?>>{
      'public item with orderId': shared(
        reasons: [
          _sharedReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
            ..['orderId'] = _orderA,
        ],
      ),
      'public item with deskCycle': shared(
        reasons: [
          _sharedReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
            ..['deskCycle'] = 'current',
        ],
      ),
      'public item with money claim': shared(
        reasons: [
          _sharedReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
            ..['entryPrice'] = '231.42',
        ],
      ),
      'ascending order': shared(
        reasons: [
          _sharedReason(
            reasonId: _reasonA,
            savedAt: '2026-09-19T12:00:00.000Z',
          ),
          _sharedReason(
            reasonId: _reasonB,
            savedAt: '2026-09-20T12:00:00.000Z',
          ),
        ],
      ),
      'equal time with ascending id': shared(
        reasons: [
          _sharedReason(
            reasonId: _reasonA,
            savedAt: '2026-09-20T12:00:00.000Z',
          ),
          _sharedReason(
            reasonId: _reasonB,
            savedAt: '2026-09-20T12:00:00.000Z',
          ),
        ],
      ),
      'duplicate reason': shared(
        reasons: [
          _sharedReason(
            reasonId: _reasonA,
            savedAt: '2026-09-20T12:00:00.000Z',
          ),
          _sharedReason(
            reasonId: _reasonA,
            savedAt: '2026-09-19T12:00:00.000Z',
          ),
        ],
      ),
      'other stock row': shared(
        reasons: [
          _sharedReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
            ..['stock'] = {
              'assetId': 'tesla',
              'variantMint': _mint,
              'symbol': 'TSLAx',
            },
        ],
      ),
      'wrong rank label': shared(
        reasons: [
          _sharedReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
            ..['author'] = {
              'handle': 'ada_trade',
              'rank': {'id': 'analyst', 'label': 'Senior Analyst'},
              'isViewer': false,
            },
        ],
      ),
      'bad handle': shared(
        reasons: [
          _sharedReason(reasonId: _reasonA, savedAt: '2026-09-20T12:00:00.000Z')
            ..['author'] = {
              'handle': 'Ada Trade',
              'rank': {'id': 'analyst', 'label': 'Analyst'},
              'isViewer': false,
            },
        ],
      ),
      'too many rows': shared(
        limit: 1,
        reasons: [
          _sharedReason(
            reasonId: _reasonB,
            savedAt: '2026-09-20T12:00:00.000Z',
          ),
          _sharedReason(
            reasonId: _reasonA,
            savedAt: '2026-09-20T12:00:00.000Z',
          ),
        ],
      ),
      'cursor on a short page': shared(
        nextCursor: _cursor(
          scope: 'everyone',
          savedAt: '2026-09-20T12:00:00.000Z',
          reasonId: _reasonA,
        ),
      ),
      'cursor bound to another stock': shared(
        limit: 1,
        nextCursor: _cursor(
          scope: 'everyone',
          variantMint: _otherMint,
          savedAt: '2026-09-20T12:00:00.000Z',
          reasonId: _reasonA,
        ),
      ),
      'cursor bound to another scope': shared(
        limit: 1,
        nextCursor: _cursor(
          scope: 'self',
          savedAt: '2026-09-20T12:00:00.000Z',
          reasonId: _reasonA,
        ),
      ),
      'cursor not matching last row': shared(
        limit: 1,
        nextCursor: _cursor(
          scope: 'everyone',
          savedAt: '2026-09-20T12:00:00.000Z',
          reasonId: _reasonB,
        ),
      ),
      'padded cursor': shared(
        limit: 1,
        nextCursor:
            '${_cursor(scope: 'everyone', savedAt: '2026-09-20T12:00:00.000Z', reasonId: _reasonA)}=',
      ),
      'scope mismatch': shared(scope: 'self'),
      'filter mismatch': shared(
        filter: {'assetId': 'apple', 'variantMint': _otherMint},
      ),
      'missing filter': shared(filter: null),
      'page limit mismatch': shared(limit: 19),
      'extra envelope key': shared()..['total'] = 1,
    };

    for (final entry in cases.entries) {
      await expectLater(
        _repository(
          MockClient((_) async => _json(entry.value)),
        ).listSharedReasons(
          SharedReasonQuery(
            assetId: 'apple',
            variantMint: _mint,
            limit: entry.value['page'] is Map
                ? (entry.value['page']! as Map)['limit'] == 19
                      ? 20
                      : (entry.value['page']! as Map)['limit'] as int
                : 20,
          ),
        ),
        throwsA(_failure(ReasonSharingFailure.invalidResponse)),
        reason: entry.key,
      );
    }
  });

  test(
    'rejects self rows that are not the viewer or collide with orders',
    () async {
      final notViewer =
          _ownReason(
              reasonId: _reasonA,
              orderId: _orderA,
              savedAt: '2026-09-20T12:00:00.000Z',
            )
            ..['author'] = {
              'handle': 'ada_trade',
              'rank': {'id': 'analyst', 'label': 'Analyst'},
              'isViewer': false,
            };
      final sameIds = _ownReason(
        reasonId: _reasonA,
        orderId: _reasonA,
        savedAt: '2026-09-20T12:00:00.000Z',
      );
      final badCycle = _ownReason(
        reasonId: _reasonA,
        orderId: _orderA,
        savedAt: '2026-09-20T12:00:00.000Z',
        deskCycle: 'archived',
      );
      final missingOrder = _ownReason(
        reasonId: _reasonA,
        orderId: _orderA,
        savedAt: '2026-09-20T12:00:00.000Z',
      )..remove('orderId');

      for (final row in [notViewer, sameIds, badCycle, missingOrder]) {
        await expectLater(
          _repository(
            MockClient(
              (_) async => _json(
                _envelope(
                  scope: 'self',
                  filter: null,
                  limit: 20,
                  reasons: [row],
                ),
              ),
            ),
          ).listOwnReasons(OwnReasonQuery()),
          throwsA(_failure(ReasonSharingFailure.invalidResponse)),
        );
      }
    },
  );

  test('validates list queries before any request is sent', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _json({});
      }),
    );

    for (final input in [
      () => SharedReasonQuery(assetId: 'apple', variantMint: _mint, limit: 0),
      () => SharedReasonQuery(assetId: 'apple', variantMint: _mint, limit: 51),
      () => SharedReasonQuery(assetId: 'Apple', variantMint: _mint),
      () => SharedReasonQuery(assetId: 'apple', variantMint: '0$_mint'),
      () => SharedReasonQuery(
        assetId: 'apple',
        variantMint: _mint,
        cursor: 'not base64url=',
      ),
      () => OwnReasonQuery(assetId: 'apple'),
      () => OwnReasonQuery(variantMint: _mint),
      () => OwnReasonQuery(limit: 51),
    ]) {
      expect(input, throwsA(_failure(ReasonSharingFailure.invalidInput)));
    }
    expect(requests, 0);
    expect(repository, isNotNull);
  });

  test('maps every contract failure code without flattening it', () async {
    final cases = <(int, String), ReasonSharingFailure>{
      (400, 'CAREER_REASON_SHARING_INVALID_INPUT'):
          ReasonSharingFailure.invalidInput,
      (400, 'INVALID_REQUEST'): ReasonSharingFailure.invalidInput,
      (401, 'CAREER_REASON_SHARING_UNAUTHENTICATED'):
          ReasonSharingFailure.accountRequired,
      (403, 'CAREER_REASON_FRIENDS_ACCOUNT_REQUIRED'):
          ReasonSharingFailure.accountRequired,
      (404, 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND'):
          ReasonSharingFailure.accountNotFound,
      (409, 'CAREER_REASON_PRIVACY_REVISION_CONFLICT'):
          ReasonSharingFailure.revisionConflict,
      (409, 'CAREER_REASON_SHARING_IDEMPOTENCY_CONFLICT'):
          ReasonSharingFailure.idempotencyConflict,
      (409, 'CAREER_REASON_SHARING_REVISION_EXHAUSTED'):
          ReasonSharingFailure.revisionExhausted,
      (503, 'CAREER_REASON_SHARING_UNAVAILABLE'):
          ReasonSharingFailure.unavailable,
      (500, 'SOMETHING_NEW'): ReasonSharingFailure.unavailable,
      (422, 'SOMETHING_NEW'): ReasonSharingFailure.rejected,
      (504, 'GATEWAY'): ReasonSharingFailure.timeout,
    };

    for (final entry in cases.entries) {
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({
              'error': {
                'code': entry.key.$2,
                'message': 'Server-owned failure.',
                'requestId': 'request-1',
              },
            }, status: entry.key.$1),
          ),
        ).putPrivacy(
          ReasonPrivacyWrite(
            mutationId: _mutation,
            baseRevision: 1,
            visibility: ReasonVisibility.everyone,
          ),
        ),
        throwsA(_failure(entry.value)),
        reason: '${entry.key}',
      );
    }
  });

  test('keeps the exact Retry-After delay for a limited guest', () async {
    Future<ReasonSharingException> limited(Map<String, String> headers) async {
      final repository = _repository(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'GUEST_SESSION_RATE_LIMITED',
                'message': 'Too quick.',
                'requestId': 'request-1',
              },
            }),
            429,
            headers: {
              'content-type': 'application/json; charset=utf-8',
              ...headers,
            },
          ),
        ),
      );
      try {
        await repository.getPrivacy();
      } on ReasonSharingException catch (error) {
        return error;
      }
      fail('Expected a rate limit failure.');
    }

    final exact = await limited({'retry-after': '37'});
    expect(exact.failure, ReasonSharingFailure.rateLimited);
    expect(exact.retryAfter, const Duration(seconds: 37));
    expect(exact.ambiguous, isFalse);

    final missing = await limited({});
    expect(missing.failure, ReasonSharingFailure.rateLimited);
    expect(missing.retryAfter, isNull);

    final dated = await limited({
      'retry-after': 'Wed, 21 Oct 2026 07:28:00 GMT',
    });
    expect(dated.retryAfter, isNull);
  });

  test('preserves terminal guest failures and reports them once', () async {
    for (final entry in const {
      'GUEST_SESSION_EXPIRED': GuestSessionFailure.expired,
      'GUEST_SESSION_REVOKED': GuestSessionFailure.revoked,
    }.entries) {
      final reported = <GuestSessionFailure>[];
      final repository = HttpReasonSharingRepository(
        client: MockClient(
          (_) async => _json({
            'error': {
              'code': entry.key,
              'message': 'This guest session is unavailable.',
              'requestId': 'request-1',
            },
          }, status: 401),
        ),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async => const GuestPaperAuthorization(
          'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        ),
        onGuestSessionFailure: reported.add,
      );

      await expectLater(
        repository.listSharedReasons(
          SharedReasonQuery(assetId: 'apple', variantMint: _mint),
        ),
        throwsA(
          isA<GuestSessionException>().having(
            (error) => error.failure,
            'failure',
            entry.value,
          ),
        ),
      );
      expect(reported, [entry.value]);
    }
  });

  test('treats a stalled request as an ambiguous timeout', () async {
    final pending = Completer<http.Response>();
    final repository = HttpReasonSharingRepository(
      client: MockClient((_) => pending.future),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
      timeout: const Duration(milliseconds: 5),
    );

    ReasonSharingException? caught;
    try {
      await repository.putPrivacy(
        ReasonPrivacyWrite(
          mutationId: _mutation,
          baseRevision: 1,
          visibility: ReasonVisibility.everyone,
        ),
      );
    } on ReasonSharingException catch (error) {
      caught = error;
    }
    expect(caught?.failure, ReasonSharingFailure.timeout);
    expect(caught?.ambiguous, isTrue);

    repository.close();
    await expectLater(
      repository.getPrivacy(),
      throwsA(_failure(ReasonSharingFailure.unavailable)),
    );
  });

  test('treats a transport error as an ambiguous offline failure', () async {
    final repository = _repository(
      MockClient((_) async => throw http.ClientException('socket closed')),
    );

    ReasonSharingException? caught;
    try {
      await repository.getPrivacy();
    } on ReasonSharingException catch (error) {
      caught = error;
    }
    expect(caught?.failure, ReasonSharingFailure.offline);
    expect(caught?.ambiguous, isTrue);
  });

  test('rejects malformed credentials and ambiguous origins first', () async {
    var requests = 0;
    final repository = HttpReasonSharingRepository(
      client: MockClient((_) async {
        requests++;
        return _json({'schemaVersion': 1, 'reasonPrivacy': _privacy()});
      }),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const GuestPaperAuthorization('safe.token'),
    );

    await expectLater(
      repository.getPrivacy(),
      throwsA(_failure(ReasonSharingFailure.accountRequired)),
    );
    expect(requests, 0);
    expect(
      () => HttpReasonSharingRepository(
        client: MockClient((_) async => _json({})),
        baseUri: Uri.parse('https://api.trimmy.test.'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
      ),
      throwsA(_failure(ReasonSharingFailure.unavailable)),
    );
    expect(
      () => HttpReasonSharingRepository(
        client: MockClient((_) async => _json({})),
        baseUri: Uri.parse('http://api.trimmy.test'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
      ),
      throwsA(_failure(ReasonSharingFailure.unavailable)),
    );
  });
}

HttpReasonSharingRepository _repository(http.Client client) =>
    HttpReasonSharingRepository(
      client: client,
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );

Matcher _failure(ReasonSharingFailure failure) => isA<ReasonSharingException>()
    .having((error) => error.failure, 'failure', failure);

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _privacy({
  int revision = 1,
  String visibility = 'nobody',
  bool? configured,
  String friendsSharing = 'unavailable',
}) {
  final isConfigured = configured ?? revision > 1;
  return {
    'revision': revision,
    'visibility': visibility,
    'configured': isConfigured,
    'friendsSharing': friendsSharing,
    'createdAt': '2026-09-20T10:00:00.000Z',
    'updatedAt': isConfigured
        ? '2026-09-20T10:00:01.000Z'
        : '2026-09-20T10:00:00.000Z',
  };
}

Map<String, Object?> _envelope({
  required String scope,
  required int limit,
  required List<Map<String, Object?>> reasons,
  Object? filter = const {'assetId': 'apple', 'variantMint': _mint},
  String? nextCursor,
}) => {
  'schemaVersion': 1,
  'scope': scope,
  'filter': filter,
  'reasons': reasons,
  'page': {'limit': limit, 'nextCursor': nextCursor},
};

Map<String, Object?> _sharedReason({
  required String reasonId,
  required String savedAt,
  bool isViewer = false,
}) => {
  'reasonId': reasonId,
  'author': {
    'handle': 'ada_trade',
    'rank': {'id': 'analyst', 'label': 'Analyst'},
    'isViewer': isViewer,
  },
  'stock': {'assetId': 'apple', 'variantMint': _mint, 'symbol': 'AAPLx'},
  'note': 'Margins improved for a second quarter.',
  'savedAt': savedAt,
};

Map<String, Object?> _friendReason({
  required String reasonId,
  required String savedAt,
}) => {
  'reasonId': reasonId,
  'author': {
    'socialId': _social,
    'handle': 'ada_trade',
    'persona': 'oracle',
    'rank': {'id': 'analyst', 'label': 'Analyst'},
    'isViewer': false,
  },
  'stock': {'assetId': 'apple', 'variantMint': _mint, 'symbol': 'AAPLx'},
  'note': 'Margins improved for a second quarter.',
  'savedAt': savedAt,
};

Map<String, Object?> _ownReason({
  required String reasonId,
  required String orderId,
  required String savedAt,
  String deskCycle = 'current',
}) => {
  'reasonId': reasonId,
  'orderId': orderId,
  'author': {
    'handle': 'mira',
    'rank': {'id': 'rookie', 'label': 'Rookie'},
    'isViewer': true,
  },
  'stock': {'assetId': 'apple', 'variantMint': _mint, 'symbol': 'AAPLx'},
  'note': 'Bought after the product event.',
  'deskCycle': deskCycle,
  'savedAt': savedAt,
};

String _cursor({
  required String scope,
  required String savedAt,
  required String reasonId,
  String? assetId = 'apple',
  String? variantMint = _mint,
}) => base64Url
    .encode(
      utf8.encode(
        jsonEncode(
          scope == 'friends'
              ? [
                  2,
                  'career-reasons',
                  _social,
                  scope,
                  assetId,
                  variantMint,
                  savedAt,
                  reasonId,
                ]
              : [1, scope, assetId, variantMint, savedAt, reasonId],
        ),
      ),
    )
    .replaceAll('=', '');
