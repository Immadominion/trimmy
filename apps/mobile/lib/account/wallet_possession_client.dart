import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../practice_sync/http_transport.dart';
import '../practice_sync/protocol.dart';
import 'wallet_possession_models.dart';

export 'wallet_possession_models.dart';

abstract interface class WalletPossessionClient {
  String get accountId;
  Future<WalletPossessionChallenge> issueChallenge({
    required String expectedWalletAddress,
  });
  Future<WalletPossessionReceipt> verify({
    required WalletPossessionChallenge challenge,
    required String signature,
  });
  void cancelPending();
  void close();
}

/// Account-bound, single-flight possession requests. No transactions, retries,
/// bearer persistence or ownership of the supplied HTTP transport.
final class HttpWalletPossessionClient implements WalletPossessionClient {
  factory HttpWalletPossessionClient({
    required http.Client client,
    required Uri baseUri,
    required String accountId,
    required Future<PracticeAccessToken> Function() accessToken,
    DateTime Function()? now,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) {
    String normalized;
    try {
      normalized = normalizePracticeUuid(accountId);
    } catch (_) {
      throw const WalletPossessionException(
        WalletPossessionFailure.invalidConfiguration,
      );
    }
    if (!_validOrigin(baseUri, allowLoopbackForTests) ||
        timeout <= Duration.zero ||
        timeout > const Duration(seconds: 20)) {
      throw const WalletPossessionException(
        WalletPossessionFailure.invalidConfiguration,
      );
    }
    return HttpWalletPossessionClient._(
      client,
      baseUri,
      normalized,
      accessToken,
      now ?? DateTime.now,
      timeout,
    );
  }

  HttpWalletPossessionClient._(
    this._client,
    this._baseUri,
    this.accountId,
    this._accessToken,
    this._now,
    this._timeout,
  );

  final http.Client _client;
  final Uri _baseUri;
  @override
  final String accountId;
  final Future<PracticeAccessToken> Function() _accessToken;
  final DateTime Function() _now;
  final Duration _timeout;
  _Operation? _active;
  WalletPossessionChallenge? _issued;
  var _closed = false;

  DateTime _clock() {
    try {
      final value = _now().toUtc();
      if (value.year < 1 || value.year > 9999) throw StateError('clock');
      return value;
    } catch (_) {
      throw const WalletPossessionException(
        WalletPossessionFailure.invalidConfiguration,
      );
    }
  }

  void _fresh(WalletPossessionChallenge challenge) {
    final now = _clock();
    if (challenge.isExpired(now)) {
      throw const WalletPossessionException(
        WalletPossessionFailure.challengeExpired,
      );
    }
    if (challenge.issuedAt.isAfter(now.add(const Duration(minutes: 5)))) {
      throw const WalletPossessionException(
        WalletPossessionFailure.invalidChallenge,
      );
    }
  }

  @override
  Future<WalletPossessionChallenge> issueChallenge({
    required String expectedWalletAddress,
  }) async {
    if (!isWalletPossessionAddress(expectedWalletAddress)) {
      throw const WalletPossessionException(
        WalletPossessionFailure.walletMismatch,
      );
    }
    return _request(
      path: '/v1/account/wallet/challenge',
      status: 201,
      body: const {},
      decode: (body) {
        final challenge = WalletPossessionChallenge.fromEnvelope(
          body,
          expectedAccountId: accountId,
          expectedWalletAddress: expectedWalletAddress,
        );
        _fresh(challenge);
        _issued = challenge;
        return challenge;
      },
    );
  }

  @override
  Future<WalletPossessionReceipt> verify({
    required WalletPossessionChallenge challenge,
    required String signature,
  }) async {
    if (_closed) {
      throw const WalletPossessionException(WalletPossessionFailure.closed);
    }
    if (challenge.accountId != accountId) {
      throw const WalletPossessionException(
        WalletPossessionFailure.accountMismatch,
      );
    }
    if (!identical(_issued, challenge)) {
      throw const WalletPossessionException(
        WalletPossessionFailure.invalidChallenge,
      );
    }
    if (!isWalletPossessionSignature(signature)) {
      throw const WalletPossessionException(
        WalletPossessionFailure.invalidSignature,
      );
    }
    _fresh(challenge);
    return _request(
      path: '/v1/account/wallet/possession',
      status: 200,
      body: {'challengeId': challenge.challengeId, 'signature': signature},
      beforeSend: () {
        _fresh(challenge);
        if (!identical(_issued, challenge)) {
          throw const WalletPossessionException(
            WalletPossessionFailure.invalidChallenge,
          );
        }
        // The API consumes the challenge on verification. A lost response must
        // never cause an automatic replay or reuse of this local proof.
        _issued = null;
      },
      decode: (body) {
        final receipt = WalletPossessionReceipt.fromEnvelope(
          body,
          challenge: challenge,
        );
        if (receipt.verifiedAt.isAfter(
          _clock().add(const Duration(minutes: 5)),
        )) {
          throw const WalletPossessionException(
            WalletPossessionFailure.invalidResponse,
          );
        }
        return receipt;
      },
    );
  }

  Future<T> _request<T>({
    required String path,
    required int status,
    required Map<String, Object?> body,
    required T Function(Object?) decode,
    void Function()? beforeSend,
  }) async {
    if (_closed) {
      throw const WalletPossessionException(WalletPossessionFailure.closed);
    }
    if (_active != null) {
      throw const WalletPossessionException(WalletPossessionFailure.busy);
    }
    _clock();
    final operation = _Operation();
    _active = operation;
    final timer = Timer(
      _timeout,
      () => operation.stop(WalletPossessionFailure.timeout),
    );
    try {
      final result = await Future.any(<Future<T>>[
        _perform(operation, path, status, body, decode, beforeSend),
        operation.failed<T>(),
      ]);
      operation.check();
      return result;
    } finally {
      timer.cancel();
      operation.disposeBody();
      if (identical(_active, operation)) _active = null;
    }
  }

  @override
  void cancelPending() {
    _issued = null;
    _active?.stop(WalletPossessionFailure.cancelled);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _issued = null;
    _active?.stop(WalletPossessionFailure.closed);
  }

  Future<T> _perform<T>(
    _Operation operation,
    String path,
    int status,
    Map<String, Object?> body,
    T Function(Object?) decode,
    void Function()? beforeSend,
  ) async {
    PracticeAccessToken access;
    try {
      access = await _accessToken();
    } catch (error) {
      operation.check();
      if (error is PracticeSyncException &&
          error.code == 'PRACTICE_ACCOUNT_MISMATCH') {
        throw const WalletPossessionException(
          WalletPossessionFailure.accountMismatch,
        );
      }
      throw const WalletPossessionException(
        WalletPossessionFailure.unauthenticated,
      );
    }
    operation.check();
    String tokenAccount;
    try {
      tokenAccount = normalizePracticeUuid(access.accountId);
    } catch (_) {
      throw const WalletPossessionException(
        WalletPossessionFailure.accountMismatch,
      );
    }
    if (tokenAccount != accountId) {
      throw const WalletPossessionException(
        WalletPossessionFailure.accountMismatch,
      );
    }
    final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(access.token);
    if (access.token.isEmpty ||
        access.token.length > 8192 ||
        match?.start != 0 ||
        match?.end != access.token.length) {
      throw const WalletPossessionException(
        WalletPossessionFailure.unauthenticated,
      );
    }
    beforeSend?.call();
    operation.check();
    final uri = _baseUri.replace(path: path);
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: operation.abort.future)
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers['accept'] = 'application/json'
          ..headers['content-type'] = 'application/json'
          ..headers['authorization'] = 'Bearer ${access.token}'
          ..body = jsonEncode(body);
    try {
      final response = await _client.send(request);
      if (operation.stopped != null) {
        _discard(response.stream);
        operation.check();
      }
      final reported = response.request;
      if (response.isRedirect ||
          response.statusCode >= 300 && response.statusCode < 400 ||
          reported != null &&
              (reported.method != 'POST' || reported.url != uri) ||
          (response.contentLength ?? 0) > _maxResponseBytes ||
          !_jsonType(response.headers['content-type'])) {
        _discard(response.stream);
        throw const WalletPossessionException(
          WalletPossessionFailure.invalidResponse,
        );
      }
      final bytes = <int>[];
      final iterator = StreamIterator(response.stream);
      operation.body = iterator;
      while (await iterator.moveNext()) {
        operation.check();
        if (bytes.length + iterator.current.length > _maxResponseBytes) {
          throw const WalletPossessionException(
            WalletPossessionFailure.invalidResponse,
          );
        }
        bytes.addAll(iterator.current);
      }
      operation.body = null;
      operation.check();
      Object? value;
      try {
        value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      } catch (_) {
        throw const WalletPossessionException(
          WalletPossessionFailure.invalidResponse,
        );
      }
      if (response.statusCode != status) {
        _serverFailure(response.statusCode, value);
      }
      return decode(value);
    } on WalletPossessionException {
      rethrow;
    } catch (_) {
      operation.check();
      throw const WalletPossessionException(
        WalletPossessionFailure.unavailable,
      );
    }
  }
}

const _maxResponseBytes = 8192;

bool _validOrigin(Uri value, bool loopbackAllowed) {
  final loopback = {
    'localhost',
    '127.0.0.1',
    '::1',
    '[::1]',
  }.contains(value.host);
  return value.hasAuthority &&
      value.host.isNotEmpty &&
      !value.host.endsWith('.') &&
      value.userInfo.isEmpty &&
      !value.hasQuery &&
      !value.hasFragment &&
      (value.path.isEmpty || value.path == '/') &&
      value.port > 0 &&
      value.port <= 65535 &&
      (value.scheme == 'https' ||
          loopbackAllowed && loopback && value.scheme == 'http');
}

bool _jsonType(String? value) {
  final parts = value
      ?.toLowerCase()
      .split(';')
      .map((part) => part.trim())
      .toList();
  return parts != null &&
      parts.length <= 2 &&
      parts.first == 'application/json' &&
      parts
          .skip(1)
          .every(
            (part) => part == 'charset=utf-8' || part == 'charset="utf-8"',
          );
}

void _discard(Stream<List<int>> stream) {
  unawaited(stream.listen(null).cancel().catchError((Object _) {}));
}

final class _Operation {
  final abort = Completer<void>();
  final _failure = Completer<WalletPossessionFailure>();
  WalletPossessionFailure? stopped;
  StreamIterator<List<int>>? body;

  Future<T> failed<T>() async =>
      throw WalletPossessionException(await _failure.future);
  void check() {
    if (stopped != null) throw WalletPossessionException(stopped!);
  }

  void stop(WalletPossessionFailure failure) {
    if (stopped != null) return;
    stopped = failure;
    abort.complete();
    disposeBody();
    _failure.complete(failure);
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
  const invalid = WalletPossessionException(
    WalletPossessionFailure.invalidResponse,
  );
  if (value is! Map<String, Object?> ||
      value.length != 1 ||
      !value.containsKey('error')) {
    throw invalid;
  }
  final error = value['error'];
  if (error is! Map<String, Object?> ||
      error.length != 3 ||
      !{'code', 'message', 'requestId'}.every(error.containsKey) ||
      error['code'] is! String ||
      error['message'] is! String ||
      (error['message'] as String).length > 1024 ||
      error['requestId'] is! String ||
      (error['requestId'] as String).isEmpty ||
      (error['requestId'] as String).length > 128) {
    throw invalid;
  }
  final failure = _failures[status]?[error['code']];
  if (failure == null) throw invalid;
  throw WalletPossessionException(failure);
}

const _failures = <int, Map<String, WalletPossessionFailure>>{
  400: {
    'WALLET_POSSESSION_INPUT_INVALID': WalletPossessionFailure.invalidChallenge,
    'INVALID_REQUEST': WalletPossessionFailure.invalidResponse,
  },
  401: {
    'ACCOUNT_WALLET_UNAUTHENTICATED': WalletPossessionFailure.unauthenticated,
  },
  403: {
    'BROWSER_ORIGIN_DENIED': WalletPossessionFailure.unavailable,
    'BROWSER_PREFLIGHT_DENIED': WalletPossessionFailure.unavailable,
  },
  404: {'NOT_FOUND': WalletPossessionFailure.notConfigured},
  409: {
    'ACCOUNT_WALLET_MISSING': WalletPossessionFailure.walletMissing,
    'ACCOUNT_WALLET_AMBIGUOUS': WalletPossessionFailure.walletAmbiguous,
    'WALLET_POSSESSION_WALLET_CHANGED': WalletPossessionFailure.walletMismatch,
    'WALLET_POSSESSION_CHALLENGE_NOT_FOUND':
        WalletPossessionFailure.challengeNotFound,
    'WALLET_POSSESSION_CHALLENGE_EXPIRED':
        WalletPossessionFailure.challengeExpired,
    'WALLET_POSSESSION_SIGNATURE_INVALID':
        WalletPossessionFailure.signatureRejected,
  },
  429: {
    'WALLET_POSSESSION_RATE_LIMITED': WalletPossessionFailure.rateLimited,
    'PRIVY_USER_RATE_LIMITED': WalletPossessionFailure.rateLimited,
  },
  500: {'INTERNAL_ERROR': WalletPossessionFailure.unavailable},
  502: {
    'PRIVY_USER_RESPONSE_INVALID': WalletPossessionFailure.invalidResponse,
    'PRIVY_USER_UNAVAILABLE': WalletPossessionFailure.unavailable,
  },
  503: {
    'ACCOUNT_WALLET_UNAVAILABLE': WalletPossessionFailure.notConfigured,
    'FINANCIAL_OPERATIONS_DISABLED': WalletPossessionFailure.notConfigured,
    'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED':
        WalletPossessionFailure.notConfigured,
    'WALLET_POSSESSION_CONFIGURATION_INVALID':
        WalletPossessionFailure.notConfigured,
    'PRIVY_VERIFIED_IDENTITY_INVALID': WalletPossessionFailure.unavailable,
    'WALLET_POSSESSION_STORE_UNAVAILABLE': WalletPossessionFailure.unavailable,
  },
  504: {'PRIVY_USER_TIMEOUT': WalletPossessionFailure.timeout},
};
