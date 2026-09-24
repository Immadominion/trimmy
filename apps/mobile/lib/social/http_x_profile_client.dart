import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/practice_sync/protocol.dart';
import 'package:trimmy/social/x_profile.dart';

const _maxBytes = 16384;
const _path = '/v1/social/x/profile';

/// Standalone read client bound to one existing server account. The token
/// callback must obtain a fresh token from the authenticated Privy account port.
/// No Client ownership, retry, cache, token persistence or invitation operation.
class HttpXProfileClient {
  HttpXProfileClient({
    required this._client,
    required Uri baseUri,
    required String accountId,
    required this._accessToken,
    Duration timeout = const Duration(seconds: 8),
    bool allowLoopbackForTests = false,
  }) : accountId = _account(accountId),
       _baseUri = baseUri,
       _timeout = timeout {
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(baseUri.host.toLowerCase());
    if (!baseUri.hasAuthority ||
        baseUri.host.isEmpty ||
        baseUri.host.endsWith('.') ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.path.isNotEmpty && baseUri.path != '/') ||
        baseUri.port < 1 ||
        baseUri.port > 65535 ||
        (baseUri.scheme != 'https' &&
            !(allowLoopbackForTests && loopback && baseUri.scheme == 'http')) ||
        timeout <= Duration.zero ||
        timeout > const Duration(seconds: 15)) {
      throw const SocialLookupException(
        SocialLookupFailure.invalidConfiguration,
      );
    }
  }

  final String accountId;
  final http.Client _client;
  final Uri _baseUri;
  final Duration _timeout;
  final Future<PracticeAccessToken> Function() _accessToken;
  _Operation? _active;
  bool _closed = false;

  Future<XPublicProfile> lookup(String username) async {
    if (_closed) throw const SocialLookupException(SocialLookupFailure.closed);
    if (!isXUsername(username)) {
      throw const SocialLookupException(SocialLookupFailure.invalidUsername);
    }
    if (_active != null) {
      throw const SocialLookupException(SocialLookupFailure.busy);
    }
    final operation = _Operation();
    _active = operation;
    final timer = Timer(
      _timeout,
      () => operation.stop(SocialLookupFailure.timeout),
    );
    try {
      return await Future.any([
        _perform(operation, username),
        operation.failure.future,
      ]);
    } finally {
      timer.cancel();
      operation.disposeBody();
      if (identical(_active, operation)) _active = null;
    }
  }

  /// Cancels even a stalled token provider or client that ignores Abortable.
  /// A request already sent may have consumed server/provider quota.
  void cancelPending() => _active?.stop(SocialLookupFailure.cancelled);

  /// Invalidates late responses; the owner remains responsible for the Client.
  void close() {
    if (_closed) return;
    _closed = true;
    cancelPending();
  }

  Future<XPublicProfile> _perform(_Operation operation, String username) async {
    PracticeAccessToken access;
    try {
      access = await _accessToken();
    } catch (error) {
      operation.check();
      if (error is PracticeSyncException &&
          error.code == 'PRACTICE_ACCOUNT_MISMATCH') {
        throw const SocialLookupException(SocialLookupFailure.accountMismatch);
      }
      throw const SocialLookupException(SocialLookupFailure.unauthenticated);
    }
    operation.check(); // No dispatch after a late token or cancelled account.
    String tokenAccount;
    try {
      tokenAccount = normalizePracticeUuid(access.accountId);
    } catch (_) {
      throw const SocialLookupException(SocialLookupFailure.accountMismatch);
    }
    if (tokenAccount != accountId) {
      throw const SocialLookupException(SocialLookupFailure.accountMismatch);
    }
    final token = access.token;
    final tokenMatch = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(token);
    if (token.isEmpty ||
        token.length > 8192 ||
        tokenMatch?.start != 0 ||
        tokenMatch?.end != token.length) {
      throw const SocialLookupException(SocialLookupFailure.unauthenticated);
    }
    final request =
        http.AbortableRequest(
            'GET',
            _baseUri.replace(
              path: _path,
              queryParameters: {'username': username},
            ),
            abortTrigger: operation.abort.future,
          )
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers['accept'] = 'application/json'
          ..headers['authorization'] = 'Bearer $token';
    try {
      final response = await _client.send(request);
      if (operation.stopped != null) {
        _discard(response.stream);
        operation.check();
      }
      if (response.isRedirect ||
          response.statusCode >= 300 && response.statusCode < 400) {
        _discard(response.stream);
        invalidSocialResponse();
      }
      if ((response.contentLength ?? 0) > _maxBytes) {
        _discard(response.stream);
        invalidSocialResponse();
      }
      final type = response.headers['content-type']
          ?.toLowerCase()
          .split(';')
          .map((value) => value.trim())
          .toList();
      if (type == null ||
          type.first != 'application/json' ||
          type
              .skip(1)
              .any(
                (value) =>
                    value != 'charset=utf-8' && value != 'charset="utf-8"',
              )) {
        _discard(response.stream);
        invalidSocialResponse();
      }
      final bytes = <int>[];
      final iterator = StreamIterator(response.stream);
      operation.body = iterator;
      while (await iterator.moveNext()) {
        operation.check();
        if (bytes.length + iterator.current.length > _maxBytes) {
          invalidSocialResponse();
        }
        bytes.addAll(iterator.current);
      }
      operation.body = null; // Exhausted streams need no cancellation await.
      operation.check();
      Object? data;
      try {
        data = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      } catch (_) {
        invalidSocialResponse();
      }
      if (response.statusCode != 200) _serverFailure(response.statusCode, data);
      return XPublicProfile.fromEnvelope(data, expectedUsername: username);
    } on SocialLookupException {
      rethrow;
    } catch (_) {
      operation.check();
      throw const SocialLookupException(SocialLookupFailure.unavailable);
    }
  }
}

String _account(String accountId) {
  try {
    return normalizePracticeUuid(accountId);
  } catch (_) {
    throw const SocialLookupException(SocialLookupFailure.invalidConfiguration);
  }
}

void _discard(Stream<List<int>> stream) {
  unawaited(stream.listen(null).cancel().catchError((Object _) {}));
}

class _Operation {
  final abort = Completer<void>();
  final failure = Completer<XPublicProfile>();
  SocialLookupFailure? stopped;
  StreamIterator<List<int>>? body;

  void check() {
    final reason = stopped;
    if (reason != null) throw SocialLookupException(reason);
  }

  void stop(SocialLookupFailure reason) {
    if (stopped != null) return;
    stopped = reason;
    abort.complete();
    disposeBody();
    failure.completeError(SocialLookupException(reason));
  }

  void disposeBody() {
    final iterator = body;
    body = null;
    if (iterator != null) {
      unawaited(iterator.cancel().catchError((Object _) {}));
    }
  }
}

Never _serverFailure(int status, Object? value) {
  final envelope = socialObject(value, const {'error'});
  final error = socialObject(envelope['error'], const {
    'code',
    'message',
    'requestId',
  });
  final code = error['code'];
  final message = error['message'];
  final requestId = error['requestId'];
  if (code is! String ||
      message is! String ||
      message.length > 1024 ||
      requestId is! String ||
      requestId.isEmpty ||
      requestId.length > 128) {
    invalidSocialResponse();
  }
  const failures = <int, Map<String, SocialLookupFailure>>{
    400: {
      'INVALID_REQUEST': SocialLookupFailure.invalidUsername,
      'X_HANDLE_INVALID': SocialLookupFailure.invalidUsername,
    },
    401: {'SOCIAL_X_UNAUTHENTICATED': SocialLookupFailure.unauthenticated},
    404: {
      'X_PROFILE_NOT_FOUND': SocialLookupFailure.notFound,
      'NOT_FOUND': SocialLookupFailure.unavailable,
    },
    429: {
      'X_LOOKUP_RATE_LIMITED': SocialLookupFailure.rateLimited,
      'X_PROVIDER_RATE_LIMITED': SocialLookupFailure.rateLimited,
    },
    502: {
      'X_RESPONSE_INVALID': SocialLookupFailure.invalidResponse,
      'X_PROVIDER_UNAVAILABLE': SocialLookupFailure.unavailable,
    },
    503: {
      'SOCIAL_X_UNAVAILABLE': SocialLookupFailure.unavailable,
      'X_LOOKUP_NOT_CONFIGURED': SocialLookupFailure.unavailable,
      'X_LOOKUP_BUDGET_UNAVAILABLE': SocialLookupFailure.unavailable,
      'X_PROVIDER_AUTH_FAILED': SocialLookupFailure.unavailable,
      'X_PROVIDER_ACCESS_DENIED': SocialLookupFailure.unavailable,
      'X_PROVIDER_PAYMENT_REQUIRED': SocialLookupFailure.unavailable,
    },
    504: {'X_LOOKUP_TIMEOUT': SocialLookupFailure.timeout},
    500: {'INTERNAL_ERROR': SocialLookupFailure.unavailable},
  };
  final failure = failures[status]?[code];
  if (failure == null) invalidSocialResponse();
  throw SocialLookupException(failure);
}
