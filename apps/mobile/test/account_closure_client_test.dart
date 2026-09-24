import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/account_closure_client.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/practice_sync/protocol.dart';

const _account = '9f000000-0000-4000-8000-000000000001';
const _other = '9f000000-0000-4000-8000-000000000002';
final _base = Uri.parse('https://api.example');

class _Recorded {
  _Recorded(this.method, this.url, this.headers, this.body);
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;
}

/// A client that answers with one fixed response and records what was sent.
http.Client _stub({
  int status = 200,
  Object? json,
  String? rawBody,
  String contentType = 'application/json',
  List<_Recorded>? sent,
  Exception? throws,
}) {
  return MockClient((request) async {
    sent?.add(
      _Recorded(request.method, request.url, request.headers, request.body),
    );
    if (throws != null) throw throws;
    final body = rawBody ?? jsonEncode(json ?? const {});
    return http.Response(body, status, headers: {'content-type': contentType});
  });
}

AccountClosureClient _client(
  http.Client transport, {
  String account = _account,
  String tokenAccount = _account,
  String token = 'header.payload.signature',
  Object? tokenError,
}) => AccountClosureClient(
  client: transport,
  baseUri: _base,
  accountId: account,
  accessToken: () async {
    if (tokenError != null) throw tokenError;
    return PracticeAccessToken(accountId: tokenAccount, token: token);
  },
);

AccountClosureFailure _failureOf(Object error) =>
    (error as AccountClosureException).failure;

void main() {
  test(
    'a successful closure sends the exact confirmation and reports it',
    () async {
      final sent = <_Recorded>[];
      final client = _client(
        _stub(
          json: {
            'schemaVersion': 1,
            'closed': true,
            'canceledInvitations': 2,
            'note': 'kept',
          },
          sent: sent,
        ),
      );
      final outcome = await client.closeAccount();
      expect(outcome.closed, isTrue);
      expect(outcome.canceledInvitations, 2);
      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '/v1/account/closure');
      expect(
        sent.single.headers['authorization'],
        'Bearer header.payload.signature',
      );
      final body = jsonDecode(sent.single.body) as Map<String, Object?>;
      expect(body, {'schemaVersion': 1, 'confirm': 'close my account'});
    },
  );

  test('an already closed account is reported without an error', () async {
    final client = _client(
      _stub(
        json: {'schemaVersion': 1, 'closed': false, 'canceledInvitations': 0},
      ),
    );
    final outcome = await client.closeAccount();
    expect(outcome.closed, isFalse);
    expect(outcome.canceledInvitations, 0);
  });

  test('each server status maps to one honest failure', () async {
    for (final entry in {
      401: AccountClosureFailure.unauthenticated,
      404: AccountClosureFailure.accountMismatch,
      503: AccountClosureFailure.notConfigured,
      500: AccountClosureFailure.unavailable,
      429: AccountClosureFailure.unavailable,
      // The client always sends the exact words, so a 400 means the contract
      // changed rather than anyone mistyping.
      400: AccountClosureFailure.invalidResponse,
    }.entries) {
      final client = _client(_stub(status: entry.key, json: {'error': {}}));
      expect(
        await client
            .closeAccount()
            .then<Object?>((_) => null)
            .catchError(_failureOf),
        entry.value,
        reason: '${entry.key}',
      );
    }
  });

  test('a malformed or oversized body never becomes a false success', () async {
    final cases = <Map<String, Object?>>[
      {'rawBody': 'not json'},
      {'rawBody': '[]'},
      {
        'json': {'schemaVersion': 2, 'closed': true, 'canceledInvitations': 0},
      },
      {
        'json': {'schemaVersion': 1, 'closed': 'yes', 'canceledInvitations': 0},
      },
      {
        'json': {'schemaVersion': 1, 'closed': true, 'canceledInvitations': -1},
      },
      {
        'json': {'schemaVersion': 1, 'closed': true},
      },
      {
        'json': {'schemaVersion': 1, 'closed': true, 'canceledInvitations': 0},
        'contentType': 'text/html',
      },
      {'rawBody': 'x' * 9000},
    ];
    for (final options in cases) {
      final client = _client(
        _stub(
          rawBody: options['rawBody'] as String?,
          json: options['json'],
          contentType:
              (options['contentType'] as String?) ?? 'application/json',
        ),
      );
      expect(
        await client
            .closeAccount()
            .then<Object?>((_) => null)
            .catchError(_failureOf),
        AccountClosureFailure.invalidResponse,
        reason: options.toString(),
      );
    }
  });

  test('a token for a different account never closes this one', () async {
    final sent = <_Recorded>[];
    final client = _client(_stub(sent: sent), tokenAccount: _other);
    expect(
      await client
          .closeAccount()
          .then<Object?>((_) => null)
          .catchError(_failureOf),
      AccountClosureFailure.accountMismatch,
    );
    expect(sent, isEmpty, reason: 'nothing is sent for the wrong account');
  });

  test('token problems and transport failures stay separate', () async {
    final mismatch = _client(
      _stub(),
      tokenError: const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH'),
    );
    expect(
      await mismatch
          .closeAccount()
          .then<Object?>((_) => null)
          .catchError(_failureOf),
      AccountClosureFailure.accountMismatch,
    );
    final unavailableToken = _client(
      _stub(),
      tokenError: StateError('no token'),
    );
    expect(
      await unavailableToken
          .closeAccount()
          .then<Object?>((_) => null)
          .catchError(_failureOf),
      AccountClosureFailure.unauthenticated,
    );
    final malformed = _client(_stub(), token: 'not a token');
    expect(
      await malformed
          .closeAccount()
          .then<Object?>((_) => null)
          .catchError(_failureOf),
      AccountClosureFailure.unauthenticated,
    );
    final offline = _client(_stub(throws: http.ClientException('offline')));
    expect(
      await offline
          .closeAccount()
          .then<Object?>((_) => null)
          .catchError(_failureOf),
      AccountClosureFailure.unavailable,
    );
  });

  test('configuration is refused before any account can be closed', () {
    for (final base in [
      Uri.parse('http://api.example'),
      Uri.parse('https://api.example?x=1'),
      Uri.parse('https://api.example#x'),
    ]) {
      expect(
        () => AccountClosureClient(
          client: _stub(),
          baseUri: base,
          accountId: _account,
          accessToken: () async =>
              PracticeAccessToken(accountId: _account, token: 'a.b.c'),
        ),
        throwsA(isA<AccountClosureException>()),
        reason: base.toString(),
      );
    }
    expect(
      () => AccountClosureClient(
        client: _stub(),
        baseUri: _base,
        accountId: 'not-a-uuid',
        accessToken: () async =>
            PracticeAccessToken(accountId: _account, token: 'a.b.c'),
      ),
      throwsA(isA<AccountClosureException>()),
    );
    // Loopback is allowed only when a test asks for it.
    expect(
      () => AccountClosureClient(
        client: _stub(),
        baseUri: Uri.parse('http://127.0.0.1:4100'),
        accountId: _account,
        accessToken: () async =>
            PracticeAccessToken(accountId: _account, token: 'a.b.c'),
      ),
      throwsA(isA<AccountClosureException>()),
    );
    expect(
      AccountClosureClient(
        client: _stub(),
        baseUri: Uri.parse('http://127.0.0.1:4100'),
        accountId: _account,
        accessToken: () async =>
            PracticeAccessToken(accountId: _account, token: 'a.b.c'),
        allowLoopbackForTests: true,
      ).accountId,
      _account,
    );
  });

  test(
    'one request at a time, and a closed client refuses late work',
    () async {
      final client = _client(
        _stub(
          json: {'schemaVersion': 1, 'closed': true, 'canceledInvitations': 0},
        ),
      );
      final first = client.closeAccount();
      expect(
        await client
            .closeAccount()
            .then<Object?>((_) => null)
            .catchError(_failureOf),
        AccountClosureFailure.busy,
      );
      await first;
      client.close();
      expect(
        await client
            .closeAccount()
            .then<Object?>((_) => null)
            .catchError(_failureOf),
        AccountClosureFailure.closed,
      );
    },
  );
}
