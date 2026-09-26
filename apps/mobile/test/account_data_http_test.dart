import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:trimmy/account/account_data.dart';
import 'package:trimmy/practice_sync/http_transport.dart';

import 'support/account_data_fixtures.dart';

const token = 'private.fresh.token';
final origin = Uri.parse('https://trimmy.example');

final class _Client extends http.BaseClient {
  _Client(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final requests = <http.BaseRequest>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse reply(Object? data, {int status = 200}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(data))),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> errorEnvelope(String code) => {
  'error': {
    'code': code,
    'message': 'Private provider diagnostic $token',
    'requestId': 'cccccccc-1234-5678-cccc-123456789abc',
  },
};

HttpAccountDataClient _accountClient(
  _Client client, {
  Future<PracticeAccessToken> Function()? accessToken,
  Uri? baseUri,
  String accountId = account,
  Duration timeout = const Duration(seconds: 1),
  bool loopback = false,
}) => HttpAccountDataClient(
  client: client,
  baseUri: baseUri ?? origin,
  accountId: accountId,
  accessToken:
      accessToken ??
      () async => const PracticeAccessToken(accountId: account, token: token),
  timeout: timeout,
  allowLoopbackForTests: loopback,
);

Matcher fails(AccountDataFailure failure) => throwsA(
  isA<AccountDataException>()
      .having((error) => error.failure, 'failure', failure)
      .having((error) => error.toString(), 'safe error', isNot(contains(token)))
      .having(
        (error) => error.toString(),
        'safe error',
        isNot(contains('Private provider diagnostic')),
      ),
);

void main() {
  test(
    'exact GETs each use a fresh account-bound bearer and no body',
    () async {
      var tokenCalls = 0;
      final client = _Client((request) async {
        expect(request.method, 'GET');
        expect(request.url.hasQuery, isFalse);
        expect(request.url.fragment, isEmpty);
        expect(
          request.url.path,
          anyOf('/v1/account/context', '/v1/account/holdings'),
        );
        expect(request.headers['authorization'], 'Bearer fresh-$tokenCalls');
        expect(request.headers['accept'], 'application/json');
        expect(
          request.headers['x-trimmy-holdings-version'],
          request.url.path.endsWith('/holdings') ? '2' : null,
        );
        expect(request.headers.containsKey('content-type'), isFalse);
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(await request.finalize().toBytes(), isEmpty);
        return request.url.path.endsWith('/context')
            ? reply(contextEnvelope())
            : reply(holdingsEnvelope());
      });
      final reader = _accountClient(
        client,
        accessToken: () async => PracticeAccessToken(
          accountId: account.toUpperCase(),
          token: 'fresh-${++tokenCalls}',
        ),
      );

      final context = await reader.readContext();
      final holdings = await reader.readHoldings();
      expect(context.userId, account);
      expect(context.xIdentity.usernameSnapshot, 'trimmyhq');
      expect(holdings.userId, account);
      expect(holdings.usdc.amountRaw, '18446744073709551615');
      expect(tokenCalls, 2);
      expect(client.requests.length, 2);

      reader.close();
      expect(client.closed, isFalse);
      await expectLater(reader.readContext(), fails(AccountDataFailure.closed));
    },
  );

  test(
    'holdings V2 preserves all held stock tokens after version negotiation',
    () async {
      final client = _Client((request) async {
        expect(request.headers['x-trimmy-holdings-version'], '2');
        return reply(holdingsEnvelopeV2());
      });
      final reader = _accountClient(client);
      final holdings = await reader.readHoldings();
      expect(holdings.stockTokens.map((token) => token.symbol), [
        'AAPLx',
        'NVDAx',
      ]);
      expect(holdings.holdingForMint(nvidiaMint)?.amountRaw, '123456789');
      reader.close();
    },
  );

  test('confirmed transaction slot is bound to holdings reads only', () async {
    final client = _Client((request) async {
      expect(request.headers['x-trimmy-holdings-version'], '2');
      expect(request.headers['x-trimmy-holdings-min-slot'], '447040359');
      return reply(holdingsEnvelopeV2());
    });
    final reader = _accountClient(client);
    await reader.readHoldings(minimumObservedSlot: 447040359);
    for (final slot in [0, -1, 9007199254740992]) {
      await expectLater(
        reader.readHoldings(minimumObservedSlot: slot),
        fails(AccountDataFailure.invalidRequest),
      );
    }
    expect(client.requests.length, 1);
    reader.close();
  });

  test('wrong accounts and unsafe fresh bearers never reach HTTP', () async {
    for (final credential in [
      const PracticeAccessToken(accountId: otherAccount, token: token),
      const PracticeAccessToken(accountId: 'invalid', token: token),
      const PracticeAccessToken(accountId: account, token: ''),
      const PracticeAccessToken(accountId: account, token: 'unsafe\nheader'),
    ]) {
      final client = _Client((_) async => reply(contextEnvelope()));
      final reader = _accountClient(
        client,
        accessToken: () async => credential,
      );
      await expectLater(
        reader.readContext(),
        fails(
          credential.accountId == account
              ? AccountDataFailure.unauthenticated
              : AccountDataFailure.accountMismatch,
        ),
      );
      expect(client.requests, isEmpty);
    }
    final client = _Client((_) async => reply(contextEnvelope()));
    final reader = _accountClient(
      client,
      accessToken: () async => throw Exception('private $token'),
    );
    await expectLater(
      reader.readContext(),
      fails(AccountDataFailure.unauthenticated),
    );
    expect(client.requests, isEmpty);
  });

  test(
    'response account drift fails even after a correctly bound token',
    () async {
      final client = _Client((request) async {
        final body = request.url.path.endsWith('/context')
            ? contextEnvelope()
            : holdingsEnvelope();
        body['userId'] = otherAccount;
        return reply(body);
      });
      final reader = _accountClient(client);
      await expectLater(
        reader.readContext(),
        fails(AccountDataFailure.accountMismatch),
      );
      await expectLater(
        reader.readHoldings(),
        fails(AccountDataFailure.accountMismatch),
      );
      expect(client.requests.length, 2);
    },
  );

  test('HTTPS configuration rejects authority and path injection', () async {
    final client = _Client((_) async => reply(contextEnvelope()));
    for (final uri in [
      'http://trimmy.example',
      'http://localhost.evil.example',
      'http://127.0.0.2',
      'http://127.1',
      'http://[::ffff:127.0.0.1]',
      'https://user:secret@trimmy.example',
      'https://trimmy.example/path',
      'https://trimmy.example?secret=x',
      'https://trimmy.example#part',
      'https://trimmy.example.',
      'https://trimmy.example:0',
      'https://trimmy.example:65536',
      '/relative',
    ]) {
      expect(
        () => _accountClient(client, baseUri: Uri.parse(uri), loopback: true),
        fails(AccountDataFailure.invalidConfiguration),
      );
    }
    for (final uri in [
      'http://localhost:8899',
      'http://127.0.0.1:8899',
      'http://[::1]:8899',
    ]) {
      expect(
        () => _accountClient(client, baseUri: Uri.parse(uri)),
        fails(AccountDataFailure.invalidConfiguration),
      );
      final result = await _accountClient(
        client,
        baseUri: Uri.parse(uri),
        loopback: true,
      ).readContext();
      expect(result, isA<AccountContextSnapshot>());
    }
    for (final invalidAccount in ['', 'caller-selected', '$account\n']) {
      expect(
        () => _accountClient(client, accountId: invalidAccount),
        fails(AccountDataFailure.invalidConfiguration),
      );
    }
    for (final timeout in [
      Duration.zero,
      const Duration(seconds: -1),
      const Duration(seconds: 16),
    ]) {
      expect(
        () => _accountClient(client, timeout: timeout),
        fails(AccountDataFailure.invalidConfiguration),
      );
    }
  });

  test('context server failures map only exact status-code pairs', () async {
    for (final (status, code, expected) in [
      (
        400,
        'ACCOUNT_CONTEXT_INVALID_REQUEST',
        AccountDataFailure.invalidRequest,
      ),
      (
        401,
        'ACCOUNT_CONTEXT_UNAUTHENTICATED',
        AccountDataFailure.unauthenticated,
      ),
      (502, 'PRIVY_USER_RESPONSE_INVALID', AccountDataFailure.invalidResponse),
      (502, 'PRIVY_USER_UNAVAILABLE', AccountDataFailure.unavailable),
      (503, 'ACCOUNT_CONTEXT_UNAVAILABLE', AccountDataFailure.notConfigured),
      (
        503,
        'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED',
        AccountDataFailure.notConfigured,
      ),
      (503, 'PRIVY_VERIFIED_IDENTITY_INVALID', AccountDataFailure.unavailable),
      (504, 'PRIVY_USER_TIMEOUT', AccountDataFailure.timeout),
      (500, 'INTERNAL_ERROR', AccountDataFailure.unavailable),
    ]) {
      final client = _Client(
        (_) async => reply(errorEnvelope(code), status: status),
      );
      await expectLater(_accountClient(client).readContext(), fails(expected));
      expect(client.requests.length, 1);
    }
    final client = _Client(
      (_) async => reply(errorEnvelope('PRIVY_USER_TIMEOUT'), status: 502),
    );
    await expectLater(
      _accountClient(client).readContext(),
      fails(AccountDataFailure.invalidResponse),
    );
  });

  test(
    'holdings failures distinguish wallet state and provider safety',
    () async {
      for (final (status, code, expected) in [
        (
          400,
          'ACCOUNT_HOLDINGS_INVALID_REQUEST',
          AccountDataFailure.invalidRequest,
        ),
        (
          401,
          'ACCOUNT_HOLDINGS_UNAUTHENTICATED',
          AccountDataFailure.unauthenticated,
        ),
        (
          409,
          'ACCOUNT_HOLDINGS_WALLET_MISSING',
          AccountDataFailure.walletMissing,
        ),
        (
          409,
          'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS',
          AccountDataFailure.walletAmbiguous,
        ),
        (503, 'ACCOUNT_HOLDINGS_UNAVAILABLE', AccountDataFailure.unavailable),
        (
          503,
          'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED',
          AccountDataFailure.notConfigured,
        ),
        (
          503,
          'PRIVY_VERIFIED_IDENTITY_INVALID',
          AccountDataFailure.unavailable,
        ),
        (
          502,
          'PRIVY_USER_RESPONSE_INVALID',
          AccountDataFailure.invalidResponse,
        ),
        (502, 'PRIVY_USER_UNAVAILABLE', AccountDataFailure.unavailable),
        (504, 'PRIVY_USER_TIMEOUT', AccountDataFailure.timeout),
        (
          502,
          'STOCK_HOLDINGS_OWNER_INVALID',
          AccountDataFailure.invalidResponse,
        ),
        (
          502,
          'STOCK_HOLDINGS_OWNER_UNVERIFIED',
          AccountDataFailure.invalidResponse,
        ),
        (
          503,
          'STOCK_HOLDINGS_CONFIGURATION_INVALID',
          AccountDataFailure.unavailable,
        ),
        (502, 'STOCK_HOLDINGS_RPC_UNAVAILABLE', AccountDataFailure.unavailable),
        (504, 'STOCK_HOLDINGS_RPC_TIMEOUT', AccountDataFailure.timeout),
        (
          502,
          'STOCK_HOLDINGS_RPC_RESPONSE_INVALID',
          AccountDataFailure.invalidResponse,
        ),
        (503, 'STOCK_HOLDINGS_WRONG_NETWORK', AccountDataFailure.unavailable),
      ]) {
        final client = _Client(
          (_) async => reply(errorEnvelope(code), status: status),
        );
        await expectLater(
          _accountClient(client).readHoldings(),
          fails(expected),
        );
        expect(client.requests.length, 1);
      }
    },
  );

  test('redirects and malformed or oversized envelopes fail closed', () async {
    final responses = [
      http.StreamedResponse(const Stream.empty(), 302),
      http.StreamedResponse(const Stream.empty(), 200, isRedirect: true),
      http.StreamedResponse(
        Stream.value([0xff]),
        200,
        headers: {'content-type': 'application/json'},
      ),
      http.StreamedResponse(
        Stream.value(utf8.encode('{}')),
        200,
        headers: {'content-type': 'text/html'},
      ),
      http.StreamedResponse(
        Stream.value(utf8.encode('{')),
        200,
        headers: {'content-type': 'application/json'},
      ),
      http.StreamedResponse(
        Stream.value(utf8.encode('{}')),
        200,
        contentLength: 65537,
        headers: {'content-type': 'application/json'},
      ),
      http.StreamedResponse(
        Stream.value(List.filled(65537, 32)),
        200,
        headers: {'content-type': 'application/json'},
      ),
    ];
    for (final response in responses) {
      await expectLater(
        _accountClient(_Client((_) async => response)).readContext(),
        fails(AccountDataFailure.invalidResponse),
      );
    }
  });

  test('timeout before a fresh token arrives prevents late dispatch', () async {
    final delayed = Completer<PracticeAccessToken>();
    final client = _Client((_) async => reply(contextEnvelope()));
    final reader = _accountClient(
      client,
      accessToken: () => delayed.future,
      timeout: const Duration(milliseconds: 5),
    );
    await expectLater(reader.readContext(), fails(AccountDataFailure.timeout));
    delayed.complete(
      const PracticeAccessToken(accountId: account, token: token),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.requests, isEmpty);
  });

  test(
    'timeout cancels a stalled response body even if abort is ignored',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final client = _Client(
        (_) async => http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        _accountClient(
          client,
          timeout: const Duration(milliseconds: 5),
        ).readHoldings(),
        fails(AccountDataFailure.timeout),
      );
      expect(cancelled, isTrue);
      await body.close();
    },
  );

  test('timeout discards a late response when send ignores abort', () async {
    final delayed = Completer<http.StreamedResponse>();
    final client = _Client((_) => delayed.future);
    final reader = _accountClient(
      client,
      timeout: const Duration(milliseconds: 5),
    );
    await expectLater(reader.readContext(), fails(AccountDataFailure.timeout));
    var cancelled = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    delayed.complete(
      http.StreamedResponse(
        body.stream,
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isTrue);
    expect(client.requests.length, 1);
    await body.close();
  });

  test('cancel and busy states spend no extra token or request', () async {
    var tokenCalls = 0;
    final firstToken = Completer<PracticeAccessToken>();
    final client = _Client(
      (request) async => request.url.path.endsWith('/context')
          ? reply(contextEnvelope())
          : reply(holdingsEnvelope()),
    );
    final reader = _accountClient(
      client,
      accessToken: () {
        tokenCalls++;
        return tokenCalls == 1
            ? firstToken.future
            : Future.value(
                const PracticeAccessToken(accountId: account, token: token),
              );
      },
    );
    final first = reader.readContext();
    final firstAssertion = expectLater(
      first,
      fails(AccountDataFailure.cancelled),
    );
    await expectLater(reader.readHoldings(), fails(AccountDataFailure.busy));
    expect(tokenCalls, 1);
    reader.cancelPending();
    await firstAssertion;
    expect(await reader.readHoldings(), isA<AccountHoldingsSnapshot>());
    firstToken.complete(
      const PracticeAccessToken(accountId: otherAccount, token: token),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.requests.length, 1);
    expect(tokenCalls, 2);
  });

  test(
    'close settles a pending token and permanently blocks dispatch',
    () async {
      final delayed = Completer<PracticeAccessToken>();
      final client = _Client((_) async => reply(contextEnvelope()));
      final reader = _accountClient(client, accessToken: () => delayed.future);
      final pending = reader.readHoldings();
      final assertion = expectLater(
        pending,
        fails(AccountDataFailure.cancelled),
      );
      reader.close();
      await assertion;
      delayed.complete(
        const PracticeAccessToken(accountId: account, token: token),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.requests, isEmpty);
      expect(client.closed, isFalse);
      await expectLater(
        reader.readHoldings(),
        fails(AccountDataFailure.closed),
      );
    },
  );

  test('network failures become local safe unavailable errors', () async {
    final client = _Client((_) async => throw Exception('rpc-url $token'));
    await expectLater(
      _accountClient(client).readHoldings(),
      fails(AccountDataFailure.unavailable),
    );
  });
}
