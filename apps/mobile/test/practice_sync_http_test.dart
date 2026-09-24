import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/practice_sync/protocol.dart';

const _account = 'aaaaaaaa-1234-5678-aaaa-123456789abc';
const _otherAccount = 'bbbbbbbb-1234-5678-bbbb-123456789abc';
const _mutationId = 'cccccccc-1234-5678-cccc-123456789abc';
const _token = 'fresh.jwt-token_123';
final _origin = Uri.parse('https://practice.example');

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

http.StreamedResponse _reply(
  Object? body, {
  int status = 200,
  Map<String, String>? headers,
}) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(body))),
  status,
  headers: headers ?? {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _snapshot({int revision = 0, OfficeProgress? progress}) =>
    {
      'schemaVersion': 1,
      'revision': revision,
      'progress': revision == 0
          ? null
          : (progress ?? OfficeProgress.empty()).toJson(),
      'updatedAt': revision == 0 ? null : '2026-09-14T10:20:30.123Z',
    };

Map<String, Object?> _error(String code, {Object? snapshot}) => {
  'error': {
    'code': code,
    'message': 'Never reveal this database detail or $_token',
    'requestId': 'dddddddd-1234-5678-dddd-123456789abc',
  },
  'currentSnapshot': ?snapshot,
};

PracticeMutation _mutation({int baseRevision = 0}) => PracticeMutation(
  mutationId: _mutationId,
  baseRevision: baseRevision,
  progress: OfficeProgress.empty().startActivity(
    OfficeActivityIds.checkTheDate,
  ),
);

HttpPracticeTransport _transport(
  _Client client, {
  Future<PracticeAccessToken> Function()? token,
  Duration timeout = const Duration(seconds: 1),
  Uri? origin,
  bool allowLoopback = false,
}) => HttpPracticeTransport(
  client: client,
  baseUri: origin ?? _origin,
  accountId: _account,
  accessToken:
      token ??
      () async => const PracticeAccessToken(accountId: _account, token: _token),
  timeout: timeout,
  allowLoopbackForTests: allowLoopback,
);

Matcher _fails(String code) => throwsA(
  isA<PracticeSyncException>()
      .having((error) => error.code, 'code', code)
      .having(
        (error) => error.toString(),
        'safe diagnostic',
        isNot(contains(_token)),
      )
      .having(
        (error) => error.toString(),
        'safe diagnostic',
        isNot(contains('database detail')),
      ),
);

void main() {
  test(
    'GET and PUT use exact routes, fresh bound tokens and strict receipts',
    () async {
      final mutation = _mutation(baseRevision: 4);
      var tokenCalls = 0;
      final client = _Client((request) async {
        expect(
          request.url.toString(),
          'https://practice.example/v1/practice/progress',
        );
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(request.headers['accept'], 'application/json');
        expect(request.headers['authorization'], 'Bearer fresh-$tokenCalls');
        if (request.method == 'GET') {
          expect(await request.finalize().toBytes(), isEmpty);
          return _reply(_snapshot());
        }
        expect(request.method, 'PUT');
        expect(request.headers['content-type'], 'application/json');
        expect(
          jsonDecode(await request.finalize().bytesToString()),
          mutation.toJson(),
        );
        return _reply(_snapshot(revision: 5, progress: mutation.progress));
      });
      final transport = _transport(
        client,
        token: () async {
          tokenCalls++;
          return PracticeAccessToken(
            accountId: _account.toUpperCase(),
            token: 'fresh-$tokenCalls',
          );
        },
      );
      expect(transport.accountId, _account);
      expect((await transport.getProgress()).revision, 0);
      expect((await transport.putProgress(mutation)).revision, 5);
      expect(tokenCalls, 2);
      expect(client.requests, hasLength(2));
      expect(client.closed, isFalse);
    },
  );

  test(
    'session POST resolves a server UUID and supplies no caller identity',
    () async {
      var calls = 0;
      final client = _Client((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/practice/session');
        expect(request.followRedirects, isFalse);
        expect(request.headers['authorization'], 'Bearer session-$calls');
        expect(await request.finalize().bytesToString(), '{}');
        return _reply({'schemaVersion': 1, 'userId': _account.toUpperCase()});
      });
      final session = HttpPracticeSessionClient(
        client: client,
        baseUri: _origin,
        accessToken: () async => 'session-${++calls}',
      );
      expect(await session.openSession(), _account);
      expect(await session.openSession(), _account);
      expect(calls, 2);
      expect(client.closed, isFalse);
    },
  );

  test(
    'only HTTPS origins or explicitly opted-in exact loopback HTTP are accepted',
    () async {
      final client = _Client((_) async => _reply(_snapshot()));
      for (final origin in [
        'http://practice.example',
        'http://localhost.evil.example',
        'http://127.0.0.2',
        'http://[::ffff:127.0.0.1]',
        'https://user:secret@practice.example',
        'https://practice.example/base',
        'https://practice.example?token=private',
        'https://practice.example#fragment',
        'https://practice.example:0',
        'https://practice.example:65536',
        'file:///tmp/practice',
        '/relative',
      ]) {
        expect(
          () => _transport(
            client,
            origin: Uri.parse(origin),
            allowLoopback: true,
          ),
          _fails('PRACTICE_INVALID_CONFIGURATION'),
          reason: origin,
        );
      }
      for (final origin in [
        'http://localhost:9999',
        'http://127.0.0.1:9999',
        'http://[::1]:9999',
      ]) {
        expect(
          () => _transport(client, origin: Uri.parse(origin)),
          _fails('PRACTICE_INVALID_CONFIGURATION'),
        );
        expect(
          (await _transport(
            client,
            origin: Uri.parse(origin),
            allowLoopback: true,
          ).getProgress()).revision,
          0,
        );
      }
      expect(
        (await _transport(
          client,
          origin: Uri.parse('https://practice.example/'),
        ).getProgress()).revision,
        0,
      );
      for (final timeout in [
        Duration.zero,
        const Duration(milliseconds: -1),
        const Duration(minutes: 2),
      ]) {
        expect(
          () => _transport(client, timeout: timeout),
          _fails('PRACTICE_INVALID_CONFIGURATION'),
        );
      }
    },
  );

  test(
    'a token for a different or malformed account is rejected before sending',
    () async {
      final client = _Client((_) async => _reply(_snapshot()));
      for (final account in [_otherAccount, 'invalid-account']) {
        final transport = _transport(
          client,
          token: () async =>
              PracticeAccessToken(accountId: account, token: _token),
        );
        await expectLater(
          transport.getProgress(),
          _fails('PRACTICE_ACCOUNT_MISMATCH'),
        );
        await expectLater(
          transport.putProgress(_mutation()),
          _fails('PRACTICE_ACCOUNT_MISMATCH'),
        );
      }
      expect(client.requests, isEmpty);
      expect(
        const PracticeAccessToken(
          accountId: _account,
          token: _token,
        ).toString(),
        isNot(contains(_token)),
      );
    },
  );

  test(
    'unsafe bearer strings and token-provider errors never reach the client',
    () async {
      final client = _Client((_) async => _reply(_snapshot()));
      for (final token in [
        '',
        ' ',
        'Bearer $_token',
        'a b',
        'a\r\nX-Evil: 1',
        'é',
        'a' * 8193,
        'a=b',
        'abc\n',
      ]) {
        await expectLater(
          _transport(
            client,
            token: () async =>
                PracticeAccessToken(accountId: _account, token: token),
          ).getProgress(),
          _fails('PRACTICE_INVALID_TOKEN'),
        );
      }
      await expectLater(
        _transport(
          client,
          token: () async => throw StateError('database detail $_token'),
        ).getProgress(),
        _fails('PRACTICE_TOKEN_UNAVAILABLE'),
      );
      expect(client.requests, isEmpty);
    },
  );

  test(
    'a late token cannot dispatch a request after the operation times out',
    () async {
      final token = Completer<PracticeAccessToken>();
      final client = _Client((_) async => _reply(_snapshot()));
      final transport = _transport(
        client,
        token: () => token.future,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        transport.putProgress(_mutation()),
        _fails('PRACTICE_TIMEOUT'),
      );
      token.complete(
        const PracticeAccessToken(accountId: _account, token: _token),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(client.requests, isEmpty);
    },
  );

  test(
    'late headers after timeout abort and cancel without acknowledging or retrying a write',
    () async {
      final headers = Completer<http.StreamedResponse>();
      final aborted = Completer<void>();
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () => cancelled.complete(),
      );
      final mutation = _mutation();
      final original = jsonEncode(mutation.toJson());
      final client = _Client((request) {
        unawaited(
          (request as http.AbortableRequest).abortTrigger!.then(
            (_) => aborted.complete(),
          ),
        );
        return headers.future;
      });
      await expectLater(
        _transport(
          client,
          timeout: const Duration(milliseconds: 20),
        ).putProgress(mutation),
        _fails('PRACTICE_TIMEOUT'),
      );
      await aborted.future;
      headers.complete(
        http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await cancelled.future.timeout(const Duration(seconds: 1));
      expect(client.requests, hasLength(1));
      expect(jsonEncode(mutation.toJson()), original);
      await body.close();
    },
  );

  test(
    'timeout cancels a stalled body even when an injected client ignores abort',
    () async {
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () => cancelled.complete(),
      );
      final client = _Client(
        (_) async => http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        _transport(
          client,
          timeout: const Duration(milliseconds: 20),
        ).getProgress(),
        _fails('PRACTICE_TIMEOUT'),
      );
      await cancelled.future.timeout(const Duration(seconds: 1));
      expect(client.requests, hasLength(1));
      await body.close();
    },
  );

  test(
    'network errors stay safe and never trigger an automatic write retry',
    () async {
      final client = _Client(
        (_) async => throw http.ClientException('database detail $_token'),
      );
      await expectLater(
        _transport(client).putProgress(_mutation()),
        _fails('PRACTICE_NETWORK_ERROR'),
      );
      expect(client.requests, hasLength(1));
    },
  );

  test(
    'declared and streamed oversized bodies are rejected and cancelled',
    () async {
      for (final declared in [true, false]) {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final client = _Client(
          (_) async => http.StreamedResponse(
            body.stream,
            200,
            contentLength: declared ? practiceMaxEnvelopeBytes + 1 : null,
            headers: {'content-type': 'application/json'},
          ),
        );
        final operation = _transport(client).getProgress();
        final expectation = expectLater(
          operation,
          _fails('PRACTICE_RESPONSE_TOO_LARGE'),
        );
        if (!declared) {
          body.add(List.filled(20000, 32));
          body.add(List.filled(20000, 32));
        }
        await expectation;
        expect(cancelled, isTrue);
        await body.close();
      }
    },
  );

  test('strict UTF8, JSON and response media type are required', () async {
    final responses = [
      http.StreamedResponse(
        Stream.value([0xc3, 0x28]),
        200,
        headers: {'content-type': 'application/json'},
      ),
      http.StreamedResponse(
        Stream.value(utf8.encode('{broken')),
        200,
        headers: {'content-type': 'application/json'},
      ),
      _reply(_snapshot(), headers: {'content-type': 'text/html'}),
      _reply(
        _snapshot(),
        headers: {'content-type': 'application/json; charset=iso-8859-1'},
      ),
      _reply(_snapshot(), headers: {}),
    ];
    for (final response in responses) {
      await expectLater(
        _transport(_Client((_) async => response)).getProgress(),
        _fails('PRACTICE_INVALID_RESPONSE'),
      );
    }
  });

  test(
    'all redirect statuses are rejected without forwarding credentials',
    () async {
      for (final status in [301, 302, 303, 307, 308]) {
        final client = _Client((request) async {
          expect(request.followRedirects, isFalse);
          return _reply(
            null,
            status: status,
            headers: {'location': 'https://untrusted.example'},
          );
        });
        await expectLater(
          _transport(client).putProgress(_mutation()),
          _fails('PRACTICE_REDIRECT_REJECTED'),
        );
        expect(client.requests, hasLength(1));
      }
    },
  );

  test(
    'PUT accepts an exact retry receipt but rejects stale or unrelated success',
    () async {
      final mutation = _mutation(baseRevision: 9);
      final valid = _snapshot(revision: 10, progress: mutation.progress);
      final client = _Client((_) async => _reply(valid));
      final transport = _transport(client);
      expect((await transport.putProgress(mutation)).revision, 10);
      expect((await transport.putProgress(mutation)).revision, 10);
      expect(
        await client.requests[0].finalize().bytesToString(),
        await client.requests[1].finalize().bytesToString(),
      );
      for (final body in [
        {...valid, 'revision': 9},
        {...valid, 'revision': 11},
        {...valid, 'revision': practiceMaxRevision + 1},
        _snapshot(revision: 10),
        _snapshot(),
        {...valid, 'accountId': _otherAccount},
      ]) {
        await expectLater(
          _transport(_Client((_) async => _reply(body))).putProgress(mutation),
          _fails('PRACTICE_INVALID_RESPONSE'),
        );
      }
    },
  );

  test(
    'revision conflicts expose only a strictly validated current snapshot',
    () async {
      final current = _snapshot(revision: 5);
      final client = _Client(
        (_) async => _reply(
          _error('PRACTICE_REVISION_CONFLICT', snapshot: current),
          status: 409,
        ),
      );
      await expectLater(
        _transport(client).putProgress(_mutation()),
        throwsA(
          isA<PracticeRevisionConflict>().having(
            (error) => error.currentSnapshot.toJson(),
            'snapshot',
            current,
          ),
        ),
      );
      await expectLater(
        _transport(client).getProgress(),
        _fails('PRACTICE_INVALID_RESPONSE'),
      );
      for (final body in [
        _error('PRACTICE_REVISION_CONFLICT'),
        _error(
          'PRACTICE_REVISION_CONFLICT',
          snapshot: {...current, 'revision': -1},
        ),
        {
          ..._error('PRACTICE_REVISION_CONFLICT', snapshot: current),
          'token': _token,
        },
        _error('UNKNOWN_CONFLICT'),
      ]) {
        await expectLater(
          _transport(
            _Client((_) async => _reply(body, status: 409)),
          ).putProgress(_mutation()),
          _fails('PRACTICE_INVALID_RESPONSE'),
        );
      }
    },
  );

  test(
    'server errors use only known status-code pairs and never raw text',
    () async {
      const pairs = {
        400: ['PRACTICE_INVALID_INPUT', 'INVALID_REQUEST'],
        401: ['PRACTICE_UNAUTHENTICATED'],
        403: ['PRACTICE_ACCOUNT_UNAVAILABLE'],
        404: ['PRACTICE_ACCOUNT_NOT_FOUND'],
        409: ['PRACTICE_HISTORY_CONFLICT', 'PRACTICE_IDEMPOTENCY_CONFLICT'],
        413: ['PAYLOAD_TOO_LARGE'],
        415: ['UNSUPPORTED_MEDIA_TYPE'],
        500: ['PRACTICE_STORAGE_INVALID', 'PRACTICE_RUNTIME_ROLE_INVALID'],
        503: ['PRACTICE_SYNC_UNAVAILABLE', 'PRACTICE_REVISION_EXHAUSTED'],
      };
      for (final pair in pairs.entries) {
        for (final code in pair.value) {
          await expectLater(
            _transport(
              _Client((_) async => _reply(_error(code), status: pair.key)),
            ).putProgress(_mutation()),
            _fails(code),
          );
        }
      }
      await expectLater(
        _transport(
          _Client(
            (_) async =>
                _reply(_error('PRACTICE_UNAUTHENTICATED'), status: 500),
          ),
        ).getProgress(),
        _fails('PRACTICE_HTTP_ERROR'),
      );
      await expectLater(
        _transport(
          _Client(
            (_) async => _reply(_error('provider-private-error'), status: 429),
          ),
        ).getProgress(),
        _fails('PRACTICE_RATE_LIMITED'),
      );
      await expectLater(
        _transport(
          _Client(
            (_) async => _reply({
              'error': {'code': 'PRACTICE_SYNC_UNAVAILABLE'},
            }, status: 503),
          ),
        ).getProgress(),
        _fails('PRACTICE_INVALID_RESPONSE'),
      );
    },
  );

  test(
    'session responses are exact and share bounded safe transport failures',
    () async {
      for (final body in [
        {'schemaVersion': 1, 'userId': 'local-user'},
        {'schemaVersion': 2, 'userId': _account},
        {'schemaVersion': 1.0, 'userId': _account},
        {'schemaVersion': 1, 'userId': _account, 'token': _token},
        {'schemaVersion': 1},
        null,
      ]) {
        final session = HttpPracticeSessionClient(
          client: _Client((_) async => _reply(body)),
          baseUri: _origin,
          accessToken: () async => _token,
        );
        await expectLater(
          session.openSession(),
          _fails('PRACTICE_INVALID_RESPONSE'),
        );
      }
      final closed = HttpPracticeSessionClient(
        client: _Client(
          (_) async =>
              _reply(_error('PRACTICE_ACCOUNT_UNAVAILABLE'), status: 403),
        ),
        baseUri: _origin,
        accessToken: () async => _token,
      );
      await expectLater(
        closed.openSession(),
        _fails('PRACTICE_ACCOUNT_UNAVAILABLE'),
      );
      final redirect = HttpPracticeSessionClient(
        client: _Client((_) async => _reply(null, status: 307)),
        baseUri: _origin,
        accessToken: () async => _token,
      );
      await expectLater(
        redirect.openSession(),
        _fails('PRACTICE_REDIRECT_REJECTED'),
      );
    },
  );
}
