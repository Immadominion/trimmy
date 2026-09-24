import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:trimmy/practice_sync/protocol.dart';

class PracticeAccessToken {
  const PracticeAccessToken({required this.accountId, required this.token});
  final String accountId;
  final String token;

  @override
  String toString() => 'PracticeAccessToken([redacted])';
}

/// No retries, token persistence or Client ownership. Each instance is bound to
/// one account; a caller must retain an uncertain mutation for an exact retry.
class HttpPracticeTransport implements PracticeTransport {
  HttpPracticeTransport({
    required http.Client client,
    required Uri baseUri,
    required String accountId,
    required this._accessToken,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) : accountId = normalizePracticeUuid(accountId),
       _http = _PracticeHttp(client, baseUri, timeout, allowLoopbackForTests);

  @override
  final String accountId;
  final Future<PracticeAccessToken> Function() _accessToken;
  final _PracticeHttp _http;

  Future<String> _boundToken() async {
    final token = await _accessToken();
    try {
      if (normalizePracticeUuid(token.accountId) != accountId) {
        throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
      }
    } catch (_) {
      throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
    }
    return token.token;
  }

  @override
  Future<PracticeSnapshot> getProgress() async {
    final response = await _http.request(
      'GET',
      '/v1/practice/progress',
      _boundToken,
    );
    if (response.status != 200) _failure(response);
    return _snapshot(response.body);
  }

  @override
  Future<PracticeSnapshot> putProgress(PracticeMutation mutation) async {
    final response = await _http.request(
      'PUT',
      '/v1/practice/progress',
      _boundToken,
      body: mutation.toJson(),
    );
    if (response.status != 200) {
      _failure(response, allowRevisionConflict: true);
    }
    final snapshot = _snapshot(response.body);
    if (mutation.baseRevision == practiceMaxRevision ||
        snapshot.revision != mutation.baseRevision + 1 ||
        snapshot.progress == null ||
        canonicalProgress(snapshot.progress!) !=
            canonicalProgress(mutation.progress)) {
      _invalidResponse();
    }
    return snapshot;
  }
}

/// Sends a fresh access token for server verification and account resolution.
/// The caller supplies no account UUID before the server resolves the identity.
class HttpPracticeSessionClient {
  HttpPracticeSessionClient({
    required http.Client client,
    required Uri baseUri,
    required this._accessToken,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) : _http = _PracticeHttp(client, baseUri, timeout, allowLoopbackForTests);

  final Future<String> Function() _accessToken;
  final _PracticeHttp _http;

  Future<String> openSession() async {
    final response = await _http.request(
      'POST',
      '/v1/practice/session',
      _accessToken,
      body: const {},
    );
    if (response.status != 200) _failure(response);
    final data = _object(response.body, const {'schemaVersion', 'userId'});
    if (data['schemaVersion'] is! int || data['schemaVersion'] != 1) {
      _invalidResponse();
    }
    try {
      return normalizePracticeUuid(data['userId']);
    } catch (_) {
      _invalidResponse();
    }
  }
}

class _PracticeHttp {
  _PracticeHttp(this.client, this.baseUri, this.timeout, bool allowLoopback) {
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(baseUri.host.toLowerCase());
    if (!baseUri.hasAuthority ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.path.isNotEmpty && baseUri.path != '/') ||
        baseUri.port < 1 ||
        baseUri.port > 65535 ||
        (baseUri.scheme != 'https' &&
            !(allowLoopback && baseUri.scheme == 'http' && loopback)) ||
        timeout <= Duration.zero ||
        timeout > const Duration(minutes: 1)) {
      throw const PracticeSyncException('PRACTICE_INVALID_CONFIGURATION');
    }
  }

  final http.Client client;
  final Uri baseUri;
  final Duration timeout;

  Future<_JsonResponse> request(
    String method,
    String path,
    Future<String> Function() accessToken, {
    Map<String, Object?>? body,
  }) async {
    final aborted = Completer<void>();
    var expired = false;
    StreamIterator<List<int>>? bodyIterator;

    Future<_JsonResponse> perform() async {
      String token;
      try {
        token = await accessToken();
      } catch (error) {
        if (error is PracticeSyncException &&
            error.code == 'PRACTICE_ACCOUNT_MISMATCH') {
          rethrow;
        }
        throw const PracticeSyncException('PRACTICE_TOKEN_UNAVAILABLE');
      }
      // Future.timeout does not cancel a token provider. Never dispatch late.
      if (expired) throw const PracticeSyncException('PRACTICE_TIMEOUT');
      _bearer(token);
      final request =
          http.AbortableRequest(
              method,
              baseUri.replace(path: path),
              abortTrigger: aborted.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['authorization'] = 'Bearer $token'
            ..headers['accept'] = 'application/json';
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        if (bytes.length > practiceMaxEnvelopeBytes) {
          throw const PracticeSyncException('PRACTICE_INVALID_PROTOCOL');
        }
        request.headers['content-type'] = 'application/json';
        request.bodyBytes = bytes;
      }

      try {
        final response = await client.send(request);
        if (expired) {
          await response.stream.listen(null).cancel();
          throw const PracticeSyncException('PRACTICE_TIMEOUT');
        }
        if (response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.listen(null).cancel();
          throw const PracticeSyncException('PRACTICE_REDIRECT_REJECTED');
        }
        if ((response.contentLength ?? 0) > practiceMaxEnvelopeBytes) {
          await response.stream.listen(null).cancel();
          throw const PracticeSyncException('PRACTICE_RESPONSE_TOO_LARGE');
        }
        final bytes = <int>[];
        final iterator = StreamIterator(response.stream);
        bodyIterator = iterator;
        var completed = false;
        try {
          while (await iterator.moveNext()) {
            if (expired) throw const PracticeSyncException('PRACTICE_TIMEOUT');
            final chunk = iterator.current;
            if (bytes.length + chunk.length > practiceMaxEnvelopeBytes) {
              throw const PracticeSyncException('PRACTICE_RESPONSE_TOO_LARGE');
            }
            bytes.addAll(chunk);
          }
          completed = true;
        } finally {
          // An exhausted stream has already released its subscription. Its
          // no-op cancel uses a shared SDK future across FakeAsync zones.
          if (!completed) await iterator.cancel();
          bodyIterator = null;
        }
        if (expired) throw const PracticeSyncException('PRACTICE_TIMEOUT');
        _jsonContentType(response.headers['content-type']);
        try {
          final text = utf8.decode(bytes, allowMalformed: false);
          return _JsonResponse(response.statusCode, jsonDecode(text));
        } catch (_) {
          _invalidResponse();
        }
      } on PracticeSyncException {
        rethrow;
      } catch (_) {
        throw PracticeSyncException(
          expired ? 'PRACTICE_TIMEOUT' : 'PRACTICE_NETWORK_ERROR',
        );
      }
    }

    return perform().timeout(
      timeout,
      onTimeout: () {
        expired = true;
        aborted.complete();
        // Injected clients need not implement Abortable. Cancel a received body
        // independently so a stalled stream cannot outlive this operation.
        final iterator = bodyIterator;
        if (iterator != null) {
          unawaited(iterator.cancel().catchError((Object _) {}));
        }
        throw const PracticeSyncException('PRACTICE_TIMEOUT');
      },
    );
  }
}

void _bearer(String token) {
  final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(token);
  if (token.isEmpty ||
      token.length > 8192 ||
      match?.start != 0 ||
      match?.end != token.length) {
    throw const PracticeSyncException('PRACTICE_INVALID_TOKEN');
  }
}

void _jsonContentType(String? type) {
  final parts = type?.toLowerCase().split(';').map((part) => part.trim());
  if (parts == null ||
      parts.first != 'application/json' ||
      parts
          .skip(1)
          .any(
            (part) => part != 'charset=utf-8' && part != 'charset="utf-8"',
          )) {
    _invalidResponse();
  }
}

PracticeSnapshot _snapshot(Object? body) {
  try {
    return PracticeSnapshot.fromJson(body);
  } catch (_) {
    _invalidResponse();
  }
}

class _JsonResponse {
  const _JsonResponse(this.status, this.body);
  final int status;
  final Object? body;
}

Map<String, dynamic> _object(Object? body, Set<String> fields) {
  if (body is! Map<String, dynamic> ||
      body.length != fields.length ||
      !fields.every(body.containsKey)) {
    _invalidResponse();
  }
  return body;
}

Never _failure(_JsonResponse response, {bool allowRevisionConflict = false}) {
  final body = response.body;
  if (body is! Map<String, dynamic> || body['error'] is! Map<String, dynamic>) {
    _invalidResponse();
  }
  final error = _object(body['error'], const {'code', 'message', 'requestId'});
  final code = error['code'];
  final message = error['message'];
  final requestId = error['requestId'];
  if (code is! String ||
      message is! String ||
      message.length > 1024 ||
      requestId is! String ||
      requestId.isEmpty ||
      requestId.length > 128) {
    _invalidResponse();
  }
  if (response.status == 409 && code == 'PRACTICE_REVISION_CONFLICT') {
    if (!allowRevisionConflict) _invalidResponse();
    _object(body, const {'error', 'currentSnapshot'});
    throw PracticeRevisionConflict(_snapshot(body['currentSnapshot']));
  }
  _object(body, const {'error'});
  const known = <int, Set<String>>{
    400: {'PRACTICE_INVALID_INPUT', 'INVALID_REQUEST'},
    401: {'PRACTICE_UNAUTHENTICATED'},
    403: {'PRACTICE_ACCOUNT_UNAVAILABLE'},
    404: {'PRACTICE_ACCOUNT_NOT_FOUND'},
    409: {
      'PRACTICE_IDEMPOTENCY_CONFLICT',
      'PRACTICE_HISTORY_CONFLICT',
      'PRACTICE_VERSION_DOWNGRADE',
    },
    413: {'PAYLOAD_TOO_LARGE'},
    415: {'UNSUPPORTED_MEDIA_TYPE'},
    500: {'PRACTICE_STORAGE_INVALID', 'PRACTICE_RUNTIME_ROLE_INVALID'},
    503: {'PRACTICE_SYNC_UNAVAILABLE', 'PRACTICE_REVISION_EXHAUSTED'},
  };
  if (known[response.status]?.contains(code) ?? false) {
    throw PracticeSyncException(code);
  }
  if (response.status == 409) _invalidResponse();
  throw PracticeSyncException(
    response.status == 429 ? 'PRACTICE_RATE_LIMITED' : 'PRACTICE_HTTP_ERROR',
  );
}

Never _invalidResponse() =>
    throw const PracticeSyncException('PRACTICE_INVALID_RESPONSE');
