import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/social/social.dart';

const account = 'aaaaaaaa-1234-5678-aaaa-123456789abc';
const other = 'bbbbbbbb-1234-5678-bbbb-123456789abc';
const token = 'private.fresh.token';
final origin = Uri.parse('https://trimmy.example');

class _Client extends http.BaseClient {
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

Map<String, Object?> _profile([Map<String, Object?> delta = const {}]) => {
  'provider': 'x',
  'id': '2087926187729227777',
  'username': 'trimmyhq',
  'name': 'Trimmy',
  'lookedUpAt': '2026-09-14T17:28:27.109Z',
  'ownershipVerified': false,
  ...delta,
};
Map<String, Object?> _envelope([Map<String, Object?> delta = const {}]) => {
  'schemaVersion': 1,
  'profile': _profile(delta),
  'invitationCreated': false,
};
http.StreamedResponse _reply(Object? data, {int status = 200}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(data))),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
Map<String, Object?> _error(String code) => {
  'error': {
    'code': code,
    'message': 'Private provider diagnostic $token',
    'requestId': 'cccccccc-1234-5678-cccc-123456789abc',
  },
};
HttpXProfileClient _lookup(
  _Client client, {
  Future<PracticeAccessToken> Function()? accessToken,
  Uri? baseUri,
  Duration timeout = const Duration(seconds: 1),
  bool loopback = false,
}) => HttpXProfileClient(
  client: client,
  baseUri: baseUri ?? origin,
  accountId: account,
  accessToken:
      accessToken ??
      () async => const PracticeAccessToken(accountId: account, token: token),
  timeout: timeout,
  allowLoopbackForTests: loopback,
);
Matcher _fails(SocialLookupFailure failure) => throwsA(
  isA<SocialLookupException>()
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
    'one GET uses a new bound token per call and returns only public data',
    () async {
      var tokenCalls = 0;
      final client = _Client((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.toString(),
          'https://trimmy.example/v1/social/x/profile?username=trimmyhq',
        );
        expect(request.headers['authorization'], 'Bearer fresh-$tokenCalls');
        expect(request.headers['accept'], 'application/json');
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(await request.finalize().toBytes(), isEmpty);
        return _reply(_envelope());
      });
      final lookup = _lookup(
        client,
        accessToken: () async => PracticeAccessToken(
          accountId: account.toUpperCase(),
          token: 'fresh-${++tokenCalls}',
        ),
      );
      for (var index = 0; index < 2; index++) {
        final result = await lookup.lookup('trimmyhq');
        expect(result.id, '2087926187729227777');
        expect(result.name, 'Trimmy');
        expect(result.ownershipVerified, isFalse);
        expect(result.invitationCreated, isFalse);
        expect(result.lookedUpAt.isUtc, isTrue);
      }
      expect(tokenCalls, 2);
      expect(client.requests.length, 2);
      lookup.close();
      expect(client.closed, isFalse);
    },
  );

  test(
    'invalid usernames spend neither a token request nor a network request',
    () async {
      var tokenCalls = 0;
      final client = _Client((_) async => _reply(_envelope()));
      final lookup = _lookup(
        client,
        accessToken: () async {
          tokenCalls++;
          return const PracticeAccessToken(accountId: account, token: token);
        },
      );
      for (final username in [
        '',
        '@trimmyhq',
        ' trimmyhq',
        'trimmyhq ',
        'trimmyhq\n',
        'a' * 16,
        '../users',
        'name?token=x',
        'trímmyhq',
      ]) {
        await expectLater(
          lookup.lookup(username),
          _fails(SocialLookupFailure.invalidUsername),
        );
      }
      expect(tokenCalls, 0);
      expect(client.requests, isEmpty);
    },
  );

  test('wrong account or unsafe fresh token never reaches HTTP', () async {
    for (final credential in [
      const PracticeAccessToken(accountId: other, token: token),
      const PracticeAccessToken(accountId: 'invalid', token: token),
      const PracticeAccessToken(accountId: account, token: ''),
      const PracticeAccessToken(accountId: account, token: 'unsafe\nheader'),
    ]) {
      final client = _Client((_) async => _reply(_envelope()));
      await expectLater(
        _lookup(client, accessToken: () async => credential).lookup('trimmyhq'),
        _fails(
          credential.accountId == account
              ? SocialLookupFailure.unauthenticated
              : SocialLookupFailure.accountMismatch,
        ),
      );
      expect(client.requests, isEmpty);
    }
    final client = _Client((_) async => _reply(_envelope()));
    await expectLater(
      _lookup(
        client,
        accessToken: () async => throw Exception(token),
      ).lookup('trimmyhq'),
      _fails(SocialLookupFailure.unauthenticated),
    );
    expect(client.requests, isEmpty);
  });

  test(
    'HTTPS origin configuration rejects aliases, credentials and path/query injection',
    () async {
      final client = _Client((_) async => _reply(_envelope()));
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
          () => _lookup(client, baseUri: Uri.parse(uri), loopback: true),
          _fails(SocialLookupFailure.invalidConfiguration),
        );
      }
      for (final uri in [
        'http://localhost:8899',
        'http://127.0.0.1:8899',
        'http://[::1]:8899',
      ]) {
        expect(
          () => _lookup(client, baseUri: Uri.parse(uri)),
          _fails(SocialLookupFailure.invalidConfiguration),
        );
        expect(
          await _lookup(
            client,
            baseUri: Uri.parse(uri),
            loopback: true,
          ).lookup('trimmyhq'),
          isA<XPublicProfile>(),
        );
      }
      for (final timeout in [
        Duration.zero,
        const Duration(seconds: -1),
        const Duration(seconds: 16),
      ]) {
        expect(
          () => _lookup(client, timeout: timeout),
          _fails(SocialLookupFailure.invalidConfiguration),
        );
      }
    },
  );

  test(
    'success rejects unknown fields, changed flags, IDs, names and mismatched usernames',
    () {
      for (final value in [
        {..._envelope(), 'schemaVersion': 1.0},
        {..._envelope(), 'schemaVersion': 2},
        {..._envelope(), 'invitationCreated': true},
        {..._envelope(), 'token': token},
        _envelope({'ownershipVerified': true}),
        _envelope({'private': token}),
        _envelope({'id': 2087926187729227777}),
        _envelope({'id': '0'}),
        _envelope({'id': '01'}),
        _envelope({'id': '123\n'}),
        _envelope({'id': '18446744073709551616'}),
        _envelope({'provider': 'privy'}),
        _envelope({'username': 'another'}),
        _envelope({'username': 'trimmyhq\n'}),
        _envelope({'name': 'bad\u0000name'}),
        _envelope({'name': 'a' * 101}),
        _envelope({'name': ''}),
      ]) {
        expect(
          () =>
              XPublicProfile.fromEnvelope(value, expectedUsername: 'trimmyhq'),
          _fails(SocialLookupFailure.invalidResponse),
        );
      }
      expect(
        XPublicProfile.fromEnvelope(
          _envelope({'id': '18446744073709551615', 'username': 'TrimmyHQ'}),
          expectedUsername: 'trimmyhq',
        ).id,
        '18446744073709551615',
      );
    },
  );

  test(
    'observation timestamp is exact UTC milliseconds with no normalized dates or microseconds',
    () {
      for (final time in [
        '2026-02-30T17:28:27.109Z',
        '2026-09-14T17:28:27.109000Z',
        '2026-09-14T17:28:27.109+00:00',
        '2026-09-14T17:28:27Z',
        '2026-09-14T17:28:27.109Z\n',
      ]) {
        expect(
          () => XPublicProfile.fromEnvelope(
            _envelope({'lookedUpAt': time}),
            expectedUsername: 'trimmyhq',
          ),
          _fails(SocialLookupFailure.invalidResponse),
        );
      }
    },
  );

  test(
    'known server errors map to safe states and never retry or surface messages',
    () async {
      for (final (status, code, expected) in [
        (401, 'SOCIAL_X_UNAUTHENTICATED', SocialLookupFailure.unauthenticated),
        (503, 'SOCIAL_X_UNAVAILABLE', SocialLookupFailure.unavailable),
        (503, 'X_PROVIDER_PAYMENT_REQUIRED', SocialLookupFailure.unavailable),
        (429, 'X_LOOKUP_RATE_LIMITED', SocialLookupFailure.rateLimited),
        (429, 'X_PROVIDER_RATE_LIMITED', SocialLookupFailure.rateLimited),
        (404, 'X_PROFILE_NOT_FOUND', SocialLookupFailure.notFound),
        (404, 'NOT_FOUND', SocialLookupFailure.unavailable),
        (504, 'X_LOOKUP_TIMEOUT', SocialLookupFailure.timeout),
        (502, 'X_RESPONSE_INVALID', SocialLookupFailure.invalidResponse),
        (400, 'X_HANDLE_INVALID', SocialLookupFailure.invalidUsername),
      ]) {
        final client = _Client(
          (_) async => _reply(_error(code), status: status),
        );
        await expectLater(_lookup(client).lookup('trimmyhq'), _fails(expected));
        expect(client.requests.length, 1);
      }
      final client = _Client((_) async => _reply(_error(token), status: 401));
      await expectLater(
        _lookup(client).lookup('trimmyhq'),
        _fails(SocialLookupFailure.invalidResponse),
      );
    },
  );

  test(
    'redirects, non-JSON, malformed UTF8 and declared/actual large bodies fail closed',
    () async {
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
          contentLength: 16385,
          headers: {'content-type': 'application/json'},
        ),
        http.StreamedResponse(
          Stream.value(List.filled(16385, 32)),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ];
      for (final response in responses) {
        await expectLater(
          _lookup(_Client((_) async => response)).lookup('trimmyhq'),
          _fails(SocialLookupFailure.invalidResponse),
        );
      }
    },
  );

  test(
    'timeout while waiting for a token prevents a late HTTP dispatch',
    () async {
      final delayed = Completer<PracticeAccessToken>();
      final client = _Client((_) async => _reply(_envelope()));
      final lookup = _lookup(
        client,
        accessToken: () => delayed.future,
        timeout: const Duration(milliseconds: 5),
      );
      await expectLater(
        lookup.lookup('trimmyhq'),
        _fails(SocialLookupFailure.timeout),
      );
      delayed.complete(
        const PracticeAccessToken(accountId: account, token: token),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.requests, isEmpty);
    },
  );

  test(
    'timeout settles when send ignores abort and cancels any late response body',
    () async {
      final delayed = Completer<http.StreamedResponse>();
      final client = _Client((_) => delayed.future);
      final lookup = _lookup(client, timeout: const Duration(milliseconds: 5));
      await expectLater(
        lookup.lookup('trimmyhq'),
        _fails(SocialLookupFailure.timeout),
      );
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      delayed.complete(http.StreamedResponse(body.stream, 200));
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      expect(client.requests.length, 1);
      await body.close();
    },
  );

  test(
    'stalled body cancellation is independent of an uncooperative abort client',
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
        _lookup(
          client,
          timeout: const Duration(milliseconds: 5),
        ).lookup('trimmyhq'),
        _fails(SocialLookupFailure.timeout),
      );
      expect(cancelled, isTrue);
      await body.close();
    },
  );

  test(
    'explicit cancel and close settle pending tokens without future dispatch or Client ownership',
    () async {
      for (final close in [false, true]) {
        final delayed = Completer<PracticeAccessToken>();
        final client = _Client((_) async => _reply(_envelope()));
        final lookup = _lookup(client, accessToken: () => delayed.future);
        final pending = lookup.lookup('trimmyhq');
        final assertion = expectLater(
          pending,
          _fails(SocialLookupFailure.cancelled),
        );
        if (close) {
          lookup.close();
        } else {
          lookup.cancelPending();
        }
        await assertion;
        delayed.complete(
          const PracticeAccessToken(accountId: account, token: token),
        );
        await Future<void>.delayed(Duration.zero);
        expect(client.requests, isEmpty);
        expect(client.closed, isFalse);
        if (close) {
          await expectLater(
            lookup.lookup('trimmyhq'),
            _fails(SocialLookupFailure.closed),
          );
        }
      }
    },
  );

  test(
    'concurrent call cannot spend a second token or request; cancelled lookup can be replaced',
    () async {
      var tokenCalls = 0;
      final firstToken = Completer<PracticeAccessToken>();
      final client = _Client((_) async => _reply(_envelope()));
      final lookup = _lookup(
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
      final first = lookup.lookup('trimmyhq');
      final firstAssertion = expectLater(
        first,
        _fails(SocialLookupFailure.cancelled),
      );
      await expectLater(
        lookup.lookup('trimmyhq'),
        _fails(SocialLookupFailure.busy),
      );
      expect(tokenCalls, 1);
      lookup.cancelPending();
      await firstAssertion;
      expect(await lookup.lookup('trimmyhq'), isA<XPublicProfile>());
      firstToken.complete(
        const PracticeAccessToken(accountId: other, token: token),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.requests.length, 1);
      expect(tokenCalls, 2);
    },
  );

  test(
    'network exception maps to unavailable without retaining the exception text',
    () async {
      final client = _Client(
        (_) async => throw Exception('Private provider diagnostic $token'),
      );
      await expectLater(
        _lookup(client).lookup('trimmyhq'),
        _fails(SocialLookupFailure.unavailable),
      );
    },
  );

  test(
    'close settles immediately even if received body cancellation never completes',
    () async {
      var cancelled = false;
      final cancelFinished = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
          return cancelFinished.future;
        },
      );
      final received = Completer<void>();
      final client = _Client((_) async {
        received.complete();
        return http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final lookup = _lookup(client);
      final pending = lookup.lookup('trimmyhq');
      final assertion = expectLater(
        pending,
        _fails(SocialLookupFailure.cancelled),
      );
      await received.future;
      await Future<void>.delayed(Duration.zero);
      lookup.close();
      await assertion;
      expect(cancelled, isTrue);
      expect(client.closed, isFalse);
      cancelFinished.complete();
      await body.close();
    },
  );
}
