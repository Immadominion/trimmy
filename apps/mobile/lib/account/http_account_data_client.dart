import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../practice_sync/http_transport.dart';
import '../practice_sync/protocol.dart';
import 'account_data_models.dart';

const _contextPath = '/v1/account/context';
const _holdingsPath = '/v1/account/holdings';
const _maxResponseBytes = 65536;

enum _Endpoint { context, holdings }

/// A read-only account adapter. Every call obtains a fresh Privy bearer for the
/// account fixed at construction. It has no token storage, retry, cache,
/// provisioning, wallet, transaction, signing, simulation or broadcast API.
class HttpAccountDataClient {
  factory HttpAccountDataClient({
    required http.Client client,
    required Uri baseUri,
    required String accountId,
    required Future<PracticeAccessToken> Function() accessToken,
    Duration timeout = const Duration(seconds: 8),
    bool allowLoopbackForTests = false,
  }) {
    if (!_validOrigin(baseUri, allowLoopbackForTests) ||
        timeout <= Duration.zero ||
        timeout > const Duration(seconds: 15)) {
      throw const AccountDataException(AccountDataFailure.invalidConfiguration);
    }
    return HttpAccountDataClient._(
      client,
      baseUri,
      _configuredAccount(accountId),
      accessToken,
      timeout,
    );
  }

  HttpAccountDataClient._(
    this._client,
    this._baseUri,
    this.accountId,
    this._accessToken,
    this._timeout,
  );

  final String accountId;
  final http.Client _client;
  final Uri _baseUri;
  final Future<PracticeAccessToken> Function() _accessToken;
  final Duration _timeout;
  _Operation? _active;
  bool _closed = false;

  Future<AccountContextSnapshot> readContext({bool fresh = false}) => _read(
    endpoint: _Endpoint.context,
    path: _contextPath,
    fresh: fresh,
    decode: (body) =>
        AccountContextSnapshot.fromEnvelope(body, expectedUserId: accountId),
  );

  Future<AccountHoldingsSnapshot> readHoldings({int? minimumObservedSlot}) {
    if (minimumObservedSlot != null &&
        (minimumObservedSlot < 1 || minimumObservedSlot > 9007199254740991)) {
      return Future.error(
        const AccountDataException(AccountDataFailure.invalidRequest),
      );
    }
    return _read(
      endpoint: _Endpoint.holdings,
      path: _holdingsPath,
      minimumObservedSlot: minimumObservedSlot,
      decode: (body) =>
          AccountHoldingsSnapshot.fromEnvelope(body, expectedUserId: accountId),
    );
  }

  Future<T> _read<T>({
    required _Endpoint endpoint,
    required String path,
    required T Function(Object?) decode,
    bool fresh = false,
    int? minimumObservedSlot,
  }) async {
    if (_closed) {
      throw const AccountDataException(AccountDataFailure.closed);
    }
    if (_active != null) {
      throw const AccountDataException(AccountDataFailure.busy);
    }
    final operation = _Operation();
    _active = operation;
    final timer = Timer(
      _timeout,
      () => operation.stop(AccountDataFailure.timeout),
    );
    try {
      return await Future.any(<Future<T>>[
        _perform(operation, endpoint, path, decode, fresh, minimumObservedSlot),
        operation.failed<T>(),
      ]);
    } finally {
      timer.cancel();
      operation.disposeBody();
      if (identical(_active, operation)) _active = null;
    }
  }

  /// Cancels a stalled token read, request, or body. A request already sent may
  /// have consumed server or provider quota.
  void cancelPending() => _active?.stop(AccountDataFailure.cancelled);

  /// Invalidates late results. The caller retains ownership of the HTTP client.
  void close() {
    if (_closed) return;
    _closed = true;
    cancelPending();
  }

  Future<T> _perform<T>(
    _Operation operation,
    _Endpoint endpoint,
    String path,
    T Function(Object?) decode,
    bool fresh,
    int? minimumObservedSlot,
  ) async {
    PracticeAccessToken access;
    try {
      access = await _accessToken();
    } catch (error) {
      operation.check();
      if (error is PracticeSyncException &&
          error.code == 'PRACTICE_ACCOUNT_MISMATCH') {
        throw const AccountDataException(AccountDataFailure.accountMismatch);
      }
      throw const AccountDataException(AccountDataFailure.unauthenticated);
    }
    operation.check();
    String tokenAccount;
    try {
      tokenAccount = normalizePracticeUuid(access.accountId);
    } catch (_) {
      throw const AccountDataException(AccountDataFailure.accountMismatch);
    }
    if (tokenAccount != accountId) {
      throw const AccountDataException(AccountDataFailure.accountMismatch);
    }
    final token = access.token;
    final tokenMatch = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(token);
    if (token.isEmpty ||
        token.length > 8192 ||
        tokenMatch?.start != 0 ||
        tokenMatch?.end != token.length) {
      throw const AccountDataException(AccountDataFailure.unauthenticated);
    }

    final request =
        http.AbortableRequest(
            'GET',
            _baseUri.replace(path: path),
            abortTrigger: operation.abort.future,
          )
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers['accept'] = 'application/json'
          ..headers['authorization'] = 'Bearer $token';
    if (fresh) request.headers['cache-control'] = 'no-cache';
    if (endpoint == _Endpoint.holdings) {
      request.headers['x-trimmy-holdings-version'] = '2';
      if (minimumObservedSlot != null) {
        request.headers['x-trimmy-holdings-min-slot'] = '$minimumObservedSlot';
      }
    }
    try {
      final response = await _client.send(request);
      if (operation.stopped != null) {
        _discard(response.stream);
        operation.check();
      }
      if (response.isRedirect ||
          response.statusCode >= 300 && response.statusCode < 400) {
        _discard(response.stream);
        invalidAccountDataResponse();
      }
      if ((response.contentLength ?? 0) > _maxResponseBytes) {
        _discard(response.stream);
        invalidAccountDataResponse();
      }
      _jsonContentType(response.headers['content-type'], response.stream);

      final bytes = <int>[];
      final iterator = StreamIterator(response.stream);
      operation.body = iterator;
      while (await iterator.moveNext()) {
        operation.check();
        if (bytes.length + iterator.current.length > _maxResponseBytes) {
          invalidAccountDataResponse();
        }
        bytes.addAll(iterator.current);
      }
      operation.body = null;
      operation.check();
      Object? body;
      try {
        body = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      } catch (_) {
        invalidAccountDataResponse();
      }
      if (response.statusCode != 200) {
        _serverFailure(endpoint, response.statusCode, body);
      }
      return decode(body);
    } on AccountDataException {
      rethrow;
    } catch (_) {
      operation.check();
      throw const AccountDataException(AccountDataFailure.unavailable);
    }
  }
}

bool _validOrigin(Uri value, bool allowLoopback) {
  try {
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(value.host.toLowerCase());
    return value.hasAuthority &&
        value.host.isNotEmpty &&
        !value.host.endsWith('.') &&
        value.userInfo.isEmpty &&
        !value.hasQuery &&
        !value.hasFragment &&
        (value.path.isEmpty || value.path == '/') &&
        value.port >= 1 &&
        value.port <= 65535 &&
        (value.scheme == 'https' ||
            allowLoopback && loopback && value.scheme == 'http');
  } catch (_) {
    return false;
  }
}

String _configuredAccount(String value) {
  try {
    return normalizePracticeUuid(value);
  } catch (_) {
    throw const AccountDataException(AccountDataFailure.invalidConfiguration);
  }
}

void _jsonContentType(String? type, Stream<List<int>> stream) {
  final parts = type
      ?.toLowerCase()
      .split(';')
      .map((value) => value.trim())
      .toList();
  if (parts == null ||
      parts.length > 2 ||
      parts.first != 'application/json' ||
      parts
          .skip(1)
          .any(
            (value) => value != 'charset=utf-8' && value != 'charset="utf-8"',
          )) {
    _discard(stream);
    invalidAccountDataResponse();
  }
}

void _discard(Stream<List<int>> stream) {
  unawaited(stream.listen(null).cancel().catchError((Object _) {}));
}

final class _Operation {
  final abort = Completer<void>();
  final _failure = Completer<AccountDataFailure>();
  AccountDataFailure? stopped;
  StreamIterator<List<int>>? body;

  Future<T> failed<T>() async {
    final reason = await _failure.future;
    throw AccountDataException(reason);
  }

  void check() {
    final reason = stopped;
    if (reason != null) throw AccountDataException(reason);
  }

  void stop(AccountDataFailure reason) {
    if (stopped != null) return;
    stopped = reason;
    abort.complete();
    disposeBody();
    _failure.complete(reason);
  }

  void disposeBody() {
    final iterator = body;
    body = null;
    if (iterator != null) {
      unawaited(iterator.cancel().catchError((Object _) {}));
    }
  }
}

Never _serverFailure(_Endpoint endpoint, int status, Object? value) {
  final envelope = _strictObject(value, const {'error'});
  final error = _strictObject(envelope['error'], const {
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
    invalidAccountDataResponse();
  }
  final failure = switch (endpoint) {
    _Endpoint.context => _contextFailures[status]?[code],
    _Endpoint.holdings => _holdingsFailures[status]?[code],
  };
  if (failure == null) invalidAccountDataResponse();
  throw AccountDataException(failure);
}

const _contextFailures = <int, Map<String, AccountDataFailure>>{
  400: {
    'ACCOUNT_CONTEXT_INVALID_REQUEST': AccountDataFailure.invalidRequest,
    'INVALID_REQUEST': AccountDataFailure.invalidRequest,
  },
  401: {'ACCOUNT_CONTEXT_UNAUTHENTICATED': AccountDataFailure.unauthenticated},
  403: {
    'BROWSER_ORIGIN_DENIED': AccountDataFailure.unavailable,
    'BROWSER_PREFLIGHT_DENIED': AccountDataFailure.unavailable,
  },
  404: {'NOT_FOUND': AccountDataFailure.unavailable},
  413: {'PAYLOAD_TOO_LARGE': AccountDataFailure.invalidRequest},
  415: {'UNSUPPORTED_MEDIA_TYPE': AccountDataFailure.invalidRequest},
  500: {'INTERNAL_ERROR': AccountDataFailure.unavailable},
  502: {
    'PRIVY_USER_RESPONSE_INVALID': AccountDataFailure.invalidResponse,
    'PRIVY_USER_UNAVAILABLE': AccountDataFailure.unavailable,
  },
  503: {
    // The route exists but its adapter is not configured on this server.
    'ACCOUNT_CONTEXT_UNAVAILABLE': AccountDataFailure.notConfigured,
    'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED': AccountDataFailure.notConfigured,
    'PRIVY_VERIFIED_IDENTITY_INVALID': AccountDataFailure.unavailable,
  },
  504: {'PRIVY_USER_TIMEOUT': AccountDataFailure.timeout},
};

const _holdingsFailures = <int, Map<String, AccountDataFailure>>{
  400: {
    'ACCOUNT_HOLDINGS_INVALID_REQUEST': AccountDataFailure.invalidRequest,
    'INVALID_REQUEST': AccountDataFailure.invalidRequest,
  },
  401: {'ACCOUNT_HOLDINGS_UNAUTHENTICATED': AccountDataFailure.unauthenticated},
  403: {
    'BROWSER_ORIGIN_DENIED': AccountDataFailure.unavailable,
    'BROWSER_PREFLIGHT_DENIED': AccountDataFailure.unavailable,
  },
  404: {'NOT_FOUND': AccountDataFailure.unavailable},
  409: {
    'ACCOUNT_HOLDINGS_WALLET_MISSING': AccountDataFailure.walletMissing,
    'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS': AccountDataFailure.walletAmbiguous,
  },
  413: {'PAYLOAD_TOO_LARGE': AccountDataFailure.invalidRequest},
  415: {'UNSUPPORTED_MEDIA_TYPE': AccountDataFailure.invalidRequest},
  500: {'INTERNAL_ERROR': AccountDataFailure.unavailable},
  502: {
    'PRIVY_USER_RESPONSE_INVALID': AccountDataFailure.invalidResponse,
    'PRIVY_USER_UNAVAILABLE': AccountDataFailure.unavailable,
    'STOCK_HOLDINGS_OWNER_INVALID': AccountDataFailure.invalidResponse,
    'STOCK_HOLDINGS_OWNER_UNVERIFIED': AccountDataFailure.invalidResponse,
    'STOCK_HOLDINGS_RPC_UNAVAILABLE': AccountDataFailure.unavailable,
    'STOCK_HOLDINGS_RPC_RESPONSE_INVALID': AccountDataFailure.invalidResponse,
  },
  503: {
    'ACCOUNT_HOLDINGS_UNAVAILABLE': AccountDataFailure.unavailable,
    'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED': AccountDataFailure.notConfigured,
    'PRIVY_VERIFIED_IDENTITY_INVALID': AccountDataFailure.unavailable,
    'STOCK_HOLDINGS_CONFIGURATION_INVALID': AccountDataFailure.unavailable,
    'STOCK_HOLDINGS_WRONG_NETWORK': AccountDataFailure.unavailable,
  },
  504: {
    'PRIVY_USER_TIMEOUT': AccountDataFailure.timeout,
    'STOCK_HOLDINGS_RPC_TIMEOUT': AccountDataFailure.timeout,
  },
};

Map<String, dynamic> _strictObject(Object? value, Set<String> fields) {
  if (value is! Map<String, dynamic> ||
      value.length != fields.length ||
      !fields.every(value.containsKey)) {
    invalidAccountDataResponse();
  }
  return value;
}
