import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:trimmy/account/wallet_possession_client.dart';
import 'package:trimmy/practice_sync/http_transport.dart';

const _account = '10000000-0000-4000-a000-000000000001';
const _otherAccount = '40000000-0000-4000-a000-000000000004';
const _wallet = 'HzU7VK2ivwSBM5SFM3vBWE9xjDNnzdCckdM91zujyKX8';
final _signature = '2' * 88;
final _now = DateTime.parse('2026-09-17T10:00:02.000Z');

Map<String, dynamic> _contract() =>
    jsonDecode(
          File('../../contracts/wallet-possession-v1.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
Matcher _failure(WalletPossessionFailure failure) =>
    isA<WalletPossessionException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );

class _Client extends http.BaseClient {
  _Client(this.reply);
  final Future<http.StreamedResponse> Function(http.BaseRequest) reply;
  final requests = <http.BaseRequest>[];
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return reply(request);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse _response(
  Object? body,
  int status, {
  http.BaseRequest? request,
  String type = 'application/json',
  int? contentLength,
}) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(body))),
  status,
  request: request,
  contentLength: contentLength,
  headers: {'content-type': type},
);

HttpWalletPossessionClient _create(
  _Client transport, {
  Future<PracticeAccessToken> Function()? accessToken,
  DateTime Function()? now,
  Duration timeout = const Duration(seconds: 1),
}) {
  final client = HttpWalletPossessionClient(
    client: transport,
    baseUri: Uri.parse('https://api.example.test'),
    accountId: _account,
    accessToken:
        accessToken ??
        () async => const PracticeAccessToken(
          accountId: _account,
          token: 'test.bearer',
        ),
    now: now ?? () => _now,
    timeout: timeout,
  );
  addTearDown(client.close);
  return client;
}

void main() {
  test(
    'account drift between challenge and verification stops the signature request',
    () async {
      var reads = 0;
      final transport = _Client(
        (request) async =>
            _response(_contract()['challenge'], 201, request: request),
      );
      final client = _create(
        transport,
        accessToken: () async => PracticeAccessToken(
          accountId: ++reads == 1 ? _account : _otherAccount,
          token: 'test.bearer',
        ),
      );
      final challenge = await client.issueChallenge(
        expectedWalletAddress: _wallet,
      );
      await expectLater(
        client.verify(challenge: challenge, signature: _signature),
        throwsA(_failure(WalletPossessionFailure.accountMismatch)),
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'an uncertain verification response cannot replay a consumed challenge',
    () async {
      final transport = _Client((request) async {
        if (request.url.path.endsWith('/challenge')) {
          return _response(_contract()['challenge'], 201, request: request);
        }
        throw StateError('private provider diagnostic');
      });
      final client = _create(transport);
      final challenge = await client.issueChallenge(
        expectedWalletAddress: _wallet,
      );
      await expectLater(
        client.verify(challenge: challenge, signature: _signature),
        throwsA(_failure(WalletPossessionFailure.unavailable)),
      );
      await expectLater(
        client.verify(challenge: challenge, signature: _signature),
        throwsA(_failure(WalletPossessionFailure.invalidChallenge)),
      );
      expect(transport.requests, hasLength(2));
    },
  );

  test(
    'cancelling a ready challenge invalidates its later signature',
    () async {
      final transport = _Client(
        (request) async =>
            _response(_contract()['challenge'], 201, request: request),
      );
      final client = _create(transport);
      final challenge = await client.issueChallenge(
        expectedWalletAddress: _wallet,
      );
      client.cancelPending();
      await expectLater(
        client.verify(challenge: challenge, signature: _signature),
        throwsA(_failure(WalletPossessionFailure.invalidChallenge)),
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'a broken clock fails before asking for credentials or issuing a challenge',
    () async {
      var reads = 0;
      final transport = _Client((_) async => throw StateError('no network'));
      final client = _create(
        transport,
        now: () => throw StateError('private clock diagnostic'),
        accessToken: () async {
          reads++;
          return const PracticeAccessToken(
            accountId: _account,
            token: 'test.bearer',
          );
        },
      );
      await expectLater(
        client.issueChallenge(expectedWalletAddress: _wallet),
        throwsA(_failure(WalletPossessionFailure.invalidConfiguration)),
      );
      expect(reads, 0);
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'challenge and verify use fresh account bearers and exact request bodies',
    () async {
      final contract = _contract();
      var tokenReads = 0;
      final transport = _Client(
        (request) async => request.url.path.endsWith('/challenge')
            ? _response(contract['challenge'], 201, request: request)
            : _response(contract['possession'], 200, request: request),
      );
      final client = _create(
        transport,
        accessToken: () async => PracticeAccessToken(
          accountId: _account,
          token: 'bearer-${++tokenReads}',
        ),
      );
      final challenge = await client.issueChallenge(
        expectedWalletAddress: _wallet,
      );
      final receipt = await client.verify(
        challenge: challenge,
        signature: _signature,
      );
      expect(tokenReads, 2);
      expect(transport.requests, hasLength(2));
      expect(transport.requests.map((r) => r.method), ['POST', 'POST']);
      expect(transport.requests.map((r) => r.url.toString()), [
        'https://api.example.test/v1/account/wallet/challenge',
        'https://api.example.test/v1/account/wallet/possession',
      ]);
      expect((transport.requests.first as http.Request).body, '{}');
      expect(jsonDecode((transport.requests.last as http.Request).body), {
        'challengeId': challenge.challengeId,
        'signature': _signature,
      });
      expect(transport.requests.map((r) => r.headers['authorization']), [
        'Bearer bearer-1',
        'Bearer bearer-2',
      ]);
      expect(
        transport.requests.every(
          (r) => !r.followRedirects && r.maxRedirects == 0,
        ),
        isTrue,
      );
      expect(receipt.accountId, _account);
      await expectLater(
        client.verify(challenge: challenge, signature: _signature),
        throwsA(_failure(WalletPossessionFailure.invalidChallenge)),
      );
      expect(
        transport.requests,
        hasLength(2),
        reason: 'a consumed challenge never repeats',
      );
      client.close();
      expect(transport.closed, isFalse);
    },
  );

  test(
    'changed account is refused before dispatch and no raw token enters the error',
    () async {
      final transport = _Client((_) async => throw StateError('no network'));
      final client = _create(
        transport,
        accessToken: () async => const PracticeAccessToken(
          accountId: _otherAccount,
          token: 'secret-token',
        ),
      );
      await expectLater(
        client.issueChallenge(expectedWalletAddress: _wallet),
        throwsA(_failure(WalletPossessionFailure.accountMismatch)),
      );
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'token failures and malformed bearers never enter the transport',
    () async {
      for (final token in [
        '',
        'secret\r\nAuthorization: invalid',
        'x' * 8193,
      ]) {
        final transport = _Client((_) async => throw StateError('no network'));
        final client = _create(
          transport,
          accessToken: () async =>
              PracticeAccessToken(accountId: _account, token: token),
        );
        await expectLater(
          client.issueChallenge(expectedWalletAddress: _wallet),
          throwsA(_failure(WalletPossessionFailure.unauthenticated)),
        );
        expect(transport.requests, isEmpty);
      }
      final transport = _Client((_) async => throw StateError('no network'));
      final client = _create(
        transport,
        accessToken: () async => throw StateError('secret provider diagnostic'),
      );
      await expectLater(
        client.issueChallenge(expectedWalletAddress: _wallet),
        throwsA(_failure(WalletPossessionFailure.unauthenticated)),
      );
      expect(transport.requests, isEmpty);
    },
  );

  test(
    'verification cannot reuse a challenge from another client or a malformed signature',
    () async {
      final transport = _Client(
        (request) async =>
            _response(_contract()['challenge'], 201, request: request),
      );
      final client = _create(transport);
      final issued = await client.issueChallenge(
        expectedWalletAddress: _wallet,
      );
      final copied = WalletPossessionChallenge.fromEnvelope(
        _contract()['challenge'],
        expectedAccountId: _account,
        expectedWalletAddress: _wallet,
      );
      await expectLater(
        client.verify(challenge: copied, signature: _signature),
        throwsA(_failure(WalletPossessionFailure.invalidChallenge)),
      );
      await expectLater(
        client.verify(challenge: issued, signature: 'not-base58'),
        throwsA(_failure(WalletPossessionFailure.invalidSignature)),
      );
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'expiry after signing or while waiting for a fresh bearer prevents submission',
    () async {
      for (final expireDuringToken in [false, true]) {
        var current = _now;
        var reads = 0;
        final transport = _Client(
          (request) async =>
              _response(_contract()['challenge'], 201, request: request),
        );
        final client = _create(
          transport,
          now: () => current,
          accessToken: () async {
            if (++reads == 2 && expireDuringToken) {
              current = DateTime.parse('2026-09-17T10:05:00Z');
            }
            return const PracticeAccessToken(
              accountId: _account,
              token: 'test.bearer',
            );
          },
        );
        final challenge = await client.issueChallenge(
          expectedWalletAddress: _wallet,
        );
        if (!expireDuringToken) current = challenge.expiresAt;
        await expectLater(
          client.verify(challenge: challenge, signature: _signature),
          throwsA(_failure(WalletPossessionFailure.challengeExpired)),
        );
        expect(transport.requests, hasLength(1));
      }
    },
  );

  test(
    'already expired or implausibly future challenges are never offered to sign',
    () async {
      for (final (now, failure) in [
        (
          DateTime.parse('2026-09-17T10:05:00Z'),
          WalletPossessionFailure.challengeExpired,
        ),
        (
          DateTime.parse('2026-09-17T09:54:59Z'),
          WalletPossessionFailure.invalidChallenge,
        ),
      ]) {
        final transport = _Client(
          (request) async =>
              _response(_contract()['challenge'], 201, request: request),
        );
        await expectLater(
          _create(
            transport,
            now: () => now,
          ).issueChallenge(expectedWalletAddress: _wallet),
          throwsA(_failure(failure)),
        );
      }
    },
  );

  test('timeout covers a stalled token and prevents late dispatch', () async {
    final token = Completer<PracticeAccessToken>();
    final transport = _Client((_) async => throw StateError('no network'));
    final client = _create(
      transport,
      accessToken: () => token.future,
      timeout: const Duration(milliseconds: 5),
    );
    await expectLater(
      client.issueChallenge(expectedWalletAddress: _wallet),
      throwsA(_failure(WalletPossessionFailure.timeout)),
    );
    token.complete(
      const PracticeAccessToken(accountId: _account, token: 'late.bearer'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.requests, isEmpty);
  });

  test(
    'cancel and close settle pending work and invalidate late responses',
    () async {
      for (final close in [false, true]) {
        final pending = Completer<http.StreamedResponse>();
        final transport = _Client((_) => pending.future);
        final client = _create(transport);
        final operation = client.issueChallenge(expectedWalletAddress: _wallet);
        final checked = expectLater(
          operation,
          throwsA(
            _failure(
              close
                  ? WalletPossessionFailure.closed
                  : WalletPossessionFailure.cancelled,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        if (close) {
          client.close();
        } else {
          client.cancelPending();
        }
        await checked;
        pending.complete(_response(_contract()['challenge'], 201));
        await Future<void>.delayed(Duration.zero);
        expect(transport.requests, hasLength(1));
        if (close) {
          await expectLater(
            client.issueChallenge(expectedWalletAddress: _wallet),
            throwsA(_failure(WalletPossessionFailure.closed)),
          );
        }
      }
    },
  );

  test(
    'single-flight refuses concurrent requests without a second bearer read',
    () async {
      final pending = Completer<PracticeAccessToken>();
      var reads = 0;
      final transport = _Client((_) async => throw StateError('no network'));
      final client = _create(
        transport,
        accessToken: () {
          reads++;
          return pending.future;
        },
      );
      final first = client.issueChallenge(expectedWalletAddress: _wallet);
      final checked = expectLater(
        first,
        throwsA(_failure(WalletPossessionFailure.cancelled)),
      );
      await expectLater(
        client.issueChallenge(expectedWalletAddress: _wallet),
        throwsA(_failure(WalletPossessionFailure.busy)),
      );
      expect(reads, 1);
      client.cancelPending();
      await checked;
      pending.complete(
        const PracticeAccessToken(accountId: _account, token: 'late.bearer'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.requests, isEmpty);
    },
  );

  test('body deadline cancels a stalled stream and no retry occurs', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final transport = _Client(
      (_) async => http.StreamedResponse(
        stream.stream,
        201,
        headers: {'content-type': 'application/json'},
      ),
    );
    final client = _create(transport, timeout: const Duration(milliseconds: 5));
    await expectLater(
      client.issueChallenge(expectedWalletAddress: _wallet),
      throwsA(_failure(WalletPossessionFailure.timeout)),
    );
    expect(cancelled, isTrue);
    expect(transport.requests, hasLength(1));
    await stream.close();
  });

  test(
    'redirects, final URI/method drift, non-JSON and size violations are rejected',
    () async {
      final envelope = _contract()['challenge'];
      final replies = <Future<http.StreamedResponse> Function(http.BaseRequest)>[
        (request) async => _response(envelope, 302, request: request),
        (_) async => _response(
          envelope,
          201,
          request: http.Request(
            'GET',
            Uri.parse('https://api.example.test/v1/account/wallet/challenge'),
          ),
        ),
        (_) async => _response(
          envelope,
          201,
          request: http.Request(
            'POST',
            Uri.parse('https://elsewhere.test/v1/account/wallet/challenge'),
          ),
        ),
        (_) async => _response(
          envelope,
          201,
          request: http.Request(
            'POST',
            Uri.parse(
              'https://api.example.test/v1/account/wallet/challenge?extra=1',
            ),
          ),
        ),
        (_) async => _response(envelope, 201, type: 'text/html'),
        (_) async =>
            _response(envelope, 201, type: 'application/json; charset=latin1'),
        (_) async => _response(envelope, 201, contentLength: 8193),
        (_) async => http.StreamedResponse(
          Stream.value(List.filled(8193, 32)),
          201,
          headers: {'content-type': 'application/json'},
        ),
        (_) async => http.StreamedResponse(
          Stream.value([255, 255]),
          201,
          headers: {'content-type': 'application/json'},
        ),
      ];
      for (final reply in replies) {
        final transport = _Client(reply);
        await expectLater(
          _create(transport).issueChallenge(expectedWalletAddress: _wallet),
          throwsA(_failure(WalletPossessionFailure.invalidResponse)),
        );
        expect(transport.requests, hasLength(1));
      }
    },
  );

  test(
    'known server failures become safe categories and unknown diagnostics stay private',
    () async {
      for (final (status, code, expected) in [
        (
          401,
          'ACCOUNT_WALLET_UNAUTHENTICATED',
          WalletPossessionFailure.unauthenticated,
        ),
        (409, 'ACCOUNT_WALLET_MISSING', WalletPossessionFailure.walletMissing),
        (
          409,
          'ACCOUNT_WALLET_AMBIGUOUS',
          WalletPossessionFailure.walletAmbiguous,
        ),
        (
          409,
          'WALLET_POSSESSION_WALLET_CHANGED',
          WalletPossessionFailure.walletMismatch,
        ),
        (
          409,
          'WALLET_POSSESSION_CHALLENGE_EXPIRED',
          WalletPossessionFailure.challengeExpired,
        ),
        (
          409,
          'WALLET_POSSESSION_SIGNATURE_INVALID',
          WalletPossessionFailure.signatureRejected,
        ),
        (
          429,
          'WALLET_POSSESSION_RATE_LIMITED',
          WalletPossessionFailure.rateLimited,
        ),
        (404, 'NOT_FOUND', WalletPossessionFailure.notConfigured),
        (
          503,
          'FINANCIAL_OPERATIONS_DISABLED',
          WalletPossessionFailure.notConfigured,
        ),
        (
          503,
          'WALLET_POSSESSION_STORE_UNAVAILABLE',
          WalletPossessionFailure.unavailable,
        ),
        (503, 'unknown_private_code', WalletPossessionFailure.invalidResponse),
      ]) {
        final transport = _Client(
          (_) async => _response({
            'error': {
              'code': code,
              'message': 'secret provider detail',
              'requestId': 'test-id',
            },
          }, status),
        );
        await expectLater(
          _create(transport).issueChallenge(expectedWalletAddress: _wallet),
          throwsA(_failure(expected)),
        );
        expect(transport.requests, hasLength(1));
        expect(
          WalletPossessionException(expected).toString(),
          isNot(contains('secret')),
        );
      }
    },
  );

  test(
    'invalid origins, timeout and account configuration fail before credentials',
    () {
      final transport = _Client((_) async => throw StateError('no network'));
      for (final raw in [
        'http://api.example.test',
        'https://user:pass@api.example.test',
        'https://api.example.test/prefix',
        'https://api.example.test?query=1',
        'https://api.example.test#fragment',
        'https://api.example.test.',
      ]) {
        expect(
          () => HttpWalletPossessionClient(
            client: transport,
            baseUri: Uri.parse(raw),
            accountId: _account,
            accessToken: () async => throw StateError('no credentials'),
          ),
          throwsA(_failure(WalletPossessionFailure.invalidConfiguration)),
        );
      }
      expect(
        () => _create(transport, timeout: Duration.zero),
        throwsA(_failure(WalletPossessionFailure.invalidConfiguration)),
      );
      expect(transport.requests, isEmpty);
    },
  );
}
