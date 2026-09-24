import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/guest_session.dart';

const _guestId = '71000000-0000-4000-8000-000000000001';
const _nextGuestId = '71000000-0000-4000-8000-000000000002';
const _claimId = '72000000-0000-4000-8000-000000000001';
const _nextClaimId = '72000000-0000-4000-8000-000000000002';
const _issuanceId = '73000000-0000-4000-8000-000000000001';
const _replaySecret = 'gr1_AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
const _token = 'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _nextToken = 'tg1_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
final _now = DateTime.utc(2026, 9, 20, 12);

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

class _Store implements GuestCredentialStore {
  GuestSessionCredential? value;
  GuestIssuanceRequest? issuanceRequest;
  int writes = 0;
  int clears = 0;
  int issuanceWrites = 0;
  bool failNextWrite = false;
  @override
  Future<GuestSessionCredential?> read() async => value;
  @override
  Future<void> write(GuestSessionCredential next) async {
    writes++;
    if (failNextWrite) {
      failNextWrite = false;
      throw const GuestSessionException(GuestSessionFailure.protectedStorage);
    }
    value = next;
    issuanceRequest = null;
  }

  @override
  Future<GuestIssuanceRequest?> readIssuanceRequest() async => issuanceRequest;

  @override
  Future<void> writeIssuanceRequest(GuestIssuanceRequest value) async {
    issuanceWrites++;
    issuanceRequest = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    issuanceRequest = null;
    value = null;
  }
}

GuestSessionCredential _credential({
  DateTime? expiresAt,
  DateTime? hardExpiresAt,
}) => GuestSessionCredential(
  guestId: _guestId,
  token: _token,
  expiresAt: expiresAt ?? _now.add(const Duration(days: 30)),
  hardExpiresAt: hardExpiresAt ?? _now.add(const Duration(days: 90)),
  claimIdempotencyKey: _claimId,
);

void main() {
  test(
    'secure storage atomically replaces the pending issuance record',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const secure = FlutterSecureStorage();
      final store = SecureGuestCredentialStore(secure);

      await store.writeIssuanceRequest(
        const GuestIssuanceRequest(
          requestId: _issuanceId,
          replaySecret: _replaySecret,
        ),
      );
      expect(await store.read(), isNull);
      expect((await store.readIssuanceRequest())?.requestId, _issuanceId);
      expect((await store.readIssuanceRequest())?.replaySecret, _replaySecret);

      await store.write(_credential());
      expect((await store.read())?.token, _token);
      expect(await store.readIssuanceRequest(), isNull);

      await store.clear();
      expect(await store.read(), isNull);
      expect(await store.readIssuanceRequest(), isNull);
    },
  );

  test(
    'creates one server guest and keeps the opaque credential in its store',
    () async {
      var calls = 0;
      final store = _Store();
      final controller = GuestSessionController(
        store: store,
        now: () => _now,
        client: HttpGuestSessionClient(
          client: MockClient((request) async {
            calls++;
            expect(request.url.path, '/v1/guest/session');
            expect(request.headers['authorization'], isNull);
            expect(jsonDecode(request.body), {
              'schemaVersion': 1,
              'requestId': _issuanceId,
              'replaySecret': _replaySecret,
            });
            return _json({
              'schemaVersion': 1,
              'requestId': _issuanceId,
              'guestId': _guestId,
              'token': _token,
              'expiresAt': _now.add(const Duration(days: 30)).toIso8601String(),
              'hardExpiresAt': _now
                  .add(const Duration(days: 90))
                  .toIso8601String(),
            }, status: 201);
          }),
          baseUri: Uri.parse('https://api.trimmy.test'),
          newId: () => _claimId,
        ),
        newIssuanceRequestId: () => _issuanceId,
        newIssuanceReplaySecret: () => _replaySecret,
      );

      final first = await controller.paperAuthorization();
      final second = await controller.paperAuthorization();
      expect(first.headerValue, 'Guest $_token');
      expect(second.headerValue, 'Guest $_token');
      expect(store.value?.token, _token);
      expect(store.value?.claimIdempotencyKey, _claimId);
      expect(store.writes, 1);
      expect(store.issuanceWrites, 1);
      expect(store.issuanceRequest, isNull);
      expect(calls, 1);
    },
  );

  test(
    'a lost create response retries the same durable issuance request',
    () async {
      final store = _Store();
      final requestIds = <String>[];
      final replaySecrets = <String>[];
      var replyLost = true;

      HttpGuestSessionClient client() => HttpGuestSessionClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          requestIds.add(body['requestId'] as String);
          replaySecrets.add(body['replaySecret'] as String);
          if (replyLost) {
            replyLost = false;
            throw http.ClientException('response lost after commit');
          }
          return _json({
            'schemaVersion': 1,
            'requestId': _issuanceId,
            'guestId': _guestId,
            'token': _token,
            'expiresAt': _now.add(const Duration(days: 30)).toIso8601String(),
            'hardExpiresAt': _now
                .add(const Duration(days: 90))
                .toIso8601String(),
          }, status: 201);
        }),
        baseUri: Uri.parse('https://api.trimmy.test'),
        newId: () => _claimId,
      );

      final first = GuestSessionController(
        store: store,
        client: client(),
        now: () => _now,
        newIssuanceRequestId: () => _issuanceId,
        newIssuanceReplaySecret: () => _replaySecret,
      );
      await expectLater(
        first.paperAuthorization(),
        throwsA(
          isA<GuestSessionException>().having(
            (error) => error.failure,
            'failure',
            GuestSessionFailure.offline,
          ),
        ),
      );
      expect(store.value, isNull);
      expect(store.issuanceRequest?.requestId, _issuanceId);
      expect(store.issuanceRequest?.replaySecret, _replaySecret);
      expect(store.issuanceWrites, 1);

      final restarted = GuestSessionController(
        store: store,
        client: client(),
        now: () => _now,
        newIssuanceRequestId: () => fail('must reuse the stored request ID'),
        newIssuanceReplaySecret: () => fail('must reuse the stored secret'),
      );
      expect(
        (await restarted.paperAuthorization()).headerValue,
        'Guest $_token',
      );
      expect(requestIds, [_issuanceId, _issuanceId]);
      expect(replaySecrets, [_replaySecret, _replaySecret]);
      expect(store.issuanceWrites, 1);
      expect(store.issuanceRequest, isNull);
      expect(store.value?.guestId, _guestId);
    },
  );

  test(
    'a mismatched create reply cannot replace the pending request',
    () async {
      const otherRequest = '74000000-0000-4000-8000-000000000001';
      final store = _Store();
      final controller = GuestSessionController(
        store: store,
        now: () => _now,
        newIssuanceRequestId: () => _issuanceId,
        newIssuanceReplaySecret: () => _replaySecret,
        client: HttpGuestSessionClient(
          client: MockClient(
            (_) async => _json({
              'schemaVersion': 1,
              'requestId': otherRequest,
              'guestId': _guestId,
              'token': _token,
              'expiresAt': _now.add(const Duration(days: 30)).toIso8601String(),
              'hardExpiresAt': _now
                  .add(const Duration(days: 90))
                  .toIso8601String(),
            }, status: 201),
          ),
          baseUri: Uri.parse('https://api.trimmy.test'),
        ),
      );

      await expectLater(
        controller.ensureActive(),
        throwsA(
          isA<GuestSessionException>().having(
            (error) => error.failure,
            'failure',
            GuestSessionFailure.rejected,
          ),
        ),
      );
      expect(store.value, isNull);
      expect(store.issuanceRequest?.requestId, _issuanceId);
      expect(store.issuanceRequest?.replaySecret, _replaySecret);
    },
  );

  test('a credential write failure retains the issuance request', () async {
    final store = _Store()..failNextWrite = true;
    final requestIds = <String>[];
    final client = HttpGuestSessionClient(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requestIds.add(body['requestId'] as String);
        return _json({
          'schemaVersion': 1,
          'requestId': _issuanceId,
          'guestId': _guestId,
          'token': _token,
          'expiresAt': _now.add(const Duration(days: 30)).toIso8601String(),
          'hardExpiresAt': _now.add(const Duration(days: 90)).toIso8601String(),
        }, status: 201);
      }),
      baseUri: Uri.parse('https://api.trimmy.test'),
      newId: () => _claimId,
    );
    final first = GuestSessionController(
      store: store,
      client: client,
      now: () => _now,
      newIssuanceRequestId: () => _issuanceId,
      newIssuanceReplaySecret: () => _replaySecret,
    );

    await expectLater(
      first.ensureActive(),
      throwsA(
        isA<GuestSessionException>().having(
          (error) => error.failure,
          'failure',
          GuestSessionFailure.protectedStorage,
        ),
      ),
    );
    expect(store.value, isNull);
    expect(store.issuanceRequest?.requestId, _issuanceId);
    expect(store.issuanceRequest?.replaySecret, _replaySecret);

    final restarted = GuestSessionController(
      store: store,
      client: client,
      now: () => _now,
      newIssuanceRequestId: () => fail('must reuse the stored request ID'),
      newIssuanceReplaySecret: () => fail('must reuse the stored secret'),
    );
    expect((await restarted.ensureActive()).guestId, _guestId);
    expect(requestIds, [_issuanceId, _issuanceId]);
    expect(store.value?.token, _token);
    expect(store.issuanceRequest, isNull);
  });

  test(
    'refresh extends the same credential and preserves the claim key',
    () async {
      final store = _Store()
        ..value = _credential(expiresAt: _now.add(const Duration(days: 2)));
      final controller = GuestSessionController(
        store: store,
        now: () => _now,
        client: HttpGuestSessionClient(
          client: MockClient((request) async {
            expect(request.url.path, '/v1/guest/session/refresh');
            expect(request.headers['authorization'], 'Guest $_token');
            return _json({
              'schemaVersion': 1,
              'guestId': _guestId,
              'expiresAt': _now.add(const Duration(days: 30)).toIso8601String(),
              'hardExpiresAt': _now
                  .add(const Duration(days: 90))
                  .toIso8601String(),
            });
          }),
          baseUri: Uri.parse('https://api.trimmy.test'),
        ),
      );

      expect((await controller.ensureActive()).claimIdempotencyKey, _claimId);
      expect(store.value?.token, _token);
      expect(store.value?.expiresAt, _now.add(const Duration(days: 30)));
      expect(store.writes, 1);
    },
  );

  test(
    'the final refresh at hard expiry survives secure-store reload',
    () async {
      final hardExpiry = _now.add(const Duration(days: 90));
      final nearHardExpiry = _now.add(const Duration(days: 85));
      final store = _Store()
        ..value = GuestSessionCredential(
          guestId: _guestId,
          token: _token,
          expiresAt: nearHardExpiry.add(const Duration(days: 1)),
          hardExpiresAt: hardExpiry,
          claimIdempotencyKey: _claimId,
        );
      final controller = GuestSessionController(
        store: store,
        now: () => nearHardExpiry,
        client: HttpGuestSessionClient(
          client: MockClient((request) async {
            expect(request.url.path, '/v1/guest/session/refresh');
            return _json({
              'schemaVersion': 1,
              'guestId': _guestId,
              'expiresAt': hardExpiry.toIso8601String(),
              'hardExpiresAt': hardExpiry.toIso8601String(),
            });
          }),
          baseUri: Uri.parse('https://api.trimmy.test'),
        ),
      );

      final refreshed = await controller.ensureActive();
      expect(refreshed.expiresAt, hardExpiry);
      final reloaded = GuestSessionCredential.fromJson(
        jsonDecode(jsonEncode(store.value!.toJson())),
      );
      expect(reloaded.expiresAt, hardExpiry);
      expect(reloaded.hardExpiresAt, hardExpiry);
      expect(reloaded.token, _token);
    },
  );

  test(
    'claim sends both proofs and clears storage only after server confirmation',
    () async {
      final store = _Store()..value = _credential();
      var fail = true;
      final controller = GuestSessionController(
        store: store,
        now: () => _now,
        client: HttpGuestSessionClient(
          client: MockClient((request) async {
            expect(request.url.path, '/v1/guest/claim');
            expect(
              request.headers['authorization'],
              'Bearer privy.token.value',
            );
            expect(request.headers['x-trimmy-guest'], _token);
            expect(jsonDecode(request.body), {
              'schemaVersion': 1,
              'idempotencyKey': _claimId,
            });
            if (fail) {
              fail = false;
              throw http.ClientException('reply lost');
            }
            return _json({
              'schemaVersion': 1,
              'status': 'claimed',
              'guestId': _guestId,
              'claimedAt': _now.toIso8601String(),
            });
          }),
          baseUri: Uri.parse('https://api.trimmy.test'),
        ),
      );

      await expectLater(
        controller.claimGuestDesk('privy.token.value'),
        throwsA(
          isA<GuestSessionException>().having(
            (error) => error.failure,
            'failure',
            GuestSessionFailure.offline,
          ),
        ),
      );
      expect(store.value, isNotNull);
      expect(store.clears, 0);
      await controller.claimGuestDesk('privy.token.value');
      expect(store.value, isNull);
      expect(store.clears, 1);
    },
  );

  test(
    'an expired stored desk is preserved and never silently replaced',
    () async {
      final store = _Store()
        ..value = _credential(
          expiresAt: _now.subtract(const Duration(seconds: 1)),
        );
      var calls = 0;
      final controller = GuestSessionController(
        store: store,
        now: () => _now,
        client: HttpGuestSessionClient(
          client: MockClient((_) async {
            calls++;
            return _json({});
          }),
          baseUri: Uri.parse('https://api.trimmy.test'),
        ),
      );
      await expectLater(
        controller.ensureActive(),
        throwsA(
          isA<GuestSessionException>().having(
            (error) => error.failure,
            'failure',
            GuestSessionFailure.expired,
          ),
        ),
      );
      expect(store.value?.guestId, _guestId);
      expect(calls, 0);
    },
  );

  test(
    'explicit restart replaces a hard-expired desk only after that action',
    () async {
      final store = _Store()
        ..value = _credential(
          expiresAt: _now.subtract(const Duration(days: 1)),
          hardExpiresAt: _now.subtract(const Duration(seconds: 1)),
        );
      var creates = 0;
      final controller = GuestSessionController(
        store: store,
        now: () => _now,
        newIssuanceRequestId: () => _issuanceId,
        newIssuanceReplaySecret: () => _replaySecret,
        client: HttpGuestSessionClient(
          client: MockClient((request) async {
            creates++;
            expect(request.url.path, '/v1/guest/session');
            return _json({
              'schemaVersion': 1,
              'requestId': _issuanceId,
              'guestId': _guestId,
              'token': _token,
              'expiresAt': _now.add(const Duration(days: 30)).toIso8601String(),
              'hardExpiresAt': _now
                  .add(const Duration(days: 90))
                  .toIso8601String(),
            }, status: 201);
          }),
          baseUri: Uri.parse('https://api.trimmy.test'),
          newId: () => _claimId,
        ),
      );

      await expectLater(
        controller.ensureActive(),
        throwsA(
          isA<GuestSessionException>().having(
            (error) => error.failure,
            'failure',
            GuestSessionFailure.expired,
          ),
        ),
      );
      expect(store.clears, 0);
      expect(creates, 0);

      await controller.startNewGuestDesk();
      expect(store.clears, 1);
      expect(store.writes, 1);
      expect(store.issuanceWrites, 1);
      expect(creates, 1);
      expect((await controller.ensureActive()).token, _token);
    },
  );

  test('explicit restart cannot erase a still-active desk', () async {
    final store = _Store()..value = _credential();
    var calls = 0;
    final controller = GuestSessionController(
      store: store,
      now: () => _now,
      client: HttpGuestSessionClient(
        client: MockClient((_) async {
          calls++;
          return _json({});
        }),
        baseUri: Uri.parse('https://api.trimmy.test'),
      ),
    );

    await expectLater(
      controller.startNewGuestDesk(),
      throwsA(
        isA<GuestSessionException>().having(
          (error) => error.failure,
          'failure',
          GuestSessionFailure.rejected,
        ),
      ),
    );
    expect(store.value?.guestId, _guestId);
    expect(store.clears, 0);
    expect(calls, 0);
  });

  test(
    'server-confirmed expiry or revocation can be replaced only explicitly',
    () async {
      for (final observedFailure in const [
        GuestSessionFailure.expired,
        GuestSessionFailure.revoked,
      ]) {
        final store = _Store()..value = _credential();
        var creates = 0;
        final controller = GuestSessionController(
          store: store,
          now: () => _now,
          newIssuanceRequestId: () => _issuanceId,
          newIssuanceReplaySecret: () => _replaySecret,
          client: HttpGuestSessionClient(
            client: MockClient((request) async {
              creates++;
              return _json({
                'schemaVersion': 1,
                'requestId': _issuanceId,
                'guestId': _nextGuestId,
                'token': _nextToken,
                'expiresAt': _now
                    .add(const Duration(days: 30))
                    .toIso8601String(),
                'hardExpiresAt': _now
                    .add(const Duration(days: 90))
                    .toIso8601String(),
              }, status: 201);
            }),
            baseUri: Uri.parse('https://api.trimmy.test'),
            newId: () => _nextClaimId,
          ),
        );

        expect((await controller.ensureActive()).guestId, _guestId);
        expect(store.clears, 0);
        await controller.startNewGuestDesk(observedFailure: observedFailure);

        expect(store.clears, 1, reason: observedFailure.name);
        expect(creates, 1, reason: observedFailure.name);
        expect((await controller.ensureActive()).guestId, _nextGuestId);
      }
    },
  );

  test(
    'a claimed desk opens a fresh guest after account sign-out in one process',
    () async {
      final store = _Store()..value = _credential();
      var creates = 0;
      final controller = GuestSessionController(
        store: store,
        now: () => _now,
        newIssuanceRequestId: () => _issuanceId,
        newIssuanceReplaySecret: () => _replaySecret,
        client: HttpGuestSessionClient(
          client: MockClient((request) async {
            if (request.url.path == '/v1/guest/claim') {
              return _json({
                'schemaVersion': 1,
                'status': 'claimed',
                'guestId': _guestId,
                'claimedAt': _now.toIso8601String(),
              });
            }
            creates++;
            return _json({
              'schemaVersion': 1,
              'requestId': _issuanceId,
              'guestId': _nextGuestId,
              'token': _nextToken,
              'expiresAt': _now.add(const Duration(days: 30)).toIso8601String(),
              'hardExpiresAt': _now
                  .add(const Duration(days: 90))
                  .toIso8601String(),
            }, status: 201);
          }),
          baseUri: Uri.parse('https://api.trimmy.test'),
          newId: () => _nextClaimId,
        ),
      );

      await controller.claimGuestDesk('privy.token.value');
      expect(store.value, isNull);
      await expectLater(
        controller.paperAuthorization(),
        throwsA(
          isA<GuestSessionException>().having(
            (error) => error.failure,
            'failure',
            GuestSessionFailure.revoked,
          ),
        ),
      );

      controller.resumeGuestAccessAfterSignOut();
      expect(
        (await controller.paperAuthorization()).headerValue,
        'Guest $_nextToken',
      );
      expect(creates, 1);
      expect(store.clears, 1, reason: 'claim cleared only the claimed key');
    },
  );

  test(
    'claim waits for an in-flight first desk instead of provisioning past it',
    () async {
      final store = _Store();
      final createStarted = Completer<void>();
      final createReply = Completer<http.Response>();
      var claimCalls = 0;
      final controller = GuestSessionController(
        store: store,
        now: () => _now,
        client: HttpGuestSessionClient(
          client: MockClient((request) async {
            if (request.url.path == '/v1/guest/session') {
              createStarted.complete();
              return createReply.future;
            }
            expect(request.url.path, '/v1/guest/claim');
            claimCalls++;
            expect(request.headers['x-trimmy-guest'], _token);
            return _json({
              'schemaVersion': 1,
              'status': 'claimed',
              'guestId': _guestId,
              'claimedAt': _now.toIso8601String(),
            });
          }),
          baseUri: Uri.parse('https://api.trimmy.test'),
          newId: () => _claimId,
        ),
        newIssuanceRequestId: () => _issuanceId,
        newIssuanceReplaySecret: () => _replaySecret,
      );

      final opening = controller.paperAuthorization();
      await createStarted.future;
      final claiming = controller.claimGuestDesk('privy.token.value');
      await Future<void>.delayed(Duration.zero);
      expect(claimCalls, 0);
      createReply.complete(
        _json({
          'schemaVersion': 1,
          'requestId': _issuanceId,
          'guestId': _guestId,
          'token': _token,
          'expiresAt': _now.add(const Duration(days: 30)).toIso8601String(),
          'hardExpiresAt': _now.add(const Duration(days: 90)).toIso8601String(),
        }, status: 201),
      );
      expect((await opening).headerValue, 'Guest $_token');
      await claiming;
      expect(claimCalls, 1);
      expect(store.value, isNull);
      await expectLater(
        controller.paperAuthorization(),
        throwsA(
          isA<GuestSessionException>().having(
            (error) => error.failure,
            'failure',
            GuestSessionFailure.revoked,
          ),
        ),
      );
    },
  );
}
