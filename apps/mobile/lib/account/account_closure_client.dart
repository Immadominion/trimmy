import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../practice_sync/http_transport.dart';
import '../practice_sync/protocol.dart';

/// The exact words the server requires. Anything else is refused, so a stray or
/// replayed request cannot close an account.
const accountClosureConfirmation = 'close my account';
const _closurePath = '/v1/account/closure';
const _maxResponseBytes = 8192;

enum AccountClosureFailure {
  invalidConfiguration,
  unauthenticated,
  accountMismatch,
  notConfigured,
  invalidResponse,
  unavailable,
  timeout,
  busy,
  closed,
}

class AccountClosureException implements Exception {
  const AccountClosureException(this.failure);

  final AccountClosureFailure failure;

  @override
  String toString() => 'AccountClosureException(${failure.name})';
}

/// What the server did, reported back plainly.
class AccountClosureOutcome {
  const AccountClosureOutcome({
    required this.closed,
    required this.canceledInvitations,
  });

  /// True when this request closed the account, false when it already was.
  final bool closed;

  /// Open invitations this account had sent that were cancelled with it.
  final int canceledInvitations;
}

/// Closes the signed-in account. One request at a time, bounded and cancellable.
///
/// Closing locks the account: it can never sign in again and there is no reopen
/// call. It does not erase saved history, and this client does not pretend to.
class AccountClosureClient {
  factory AccountClosureClient({
    required http.Client client,
    required Uri baseUri,
    required String accountId,
    required Future<PracticeAccessToken> Function() accessToken,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) {
    final loopback =
        baseUri.host == 'localhost' ||
        baseUri.host == '127.0.0.1' ||
        baseUri.host == '10.0.2.2';
    final secure =
        baseUri.scheme == 'https' || (allowLoopbackForTests && loopback);
    if (!secure ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        !baseUri.hasAuthority ||
        timeout <= Duration.zero ||
        timeout > const Duration(seconds: 20)) {
      throw const AccountClosureException(
        AccountClosureFailure.invalidConfiguration,
      );
    }
    final String normalized;
    try {
      normalized = normalizePracticeUuid(accountId);
    } catch (_) {
      throw const AccountClosureException(
        AccountClosureFailure.invalidConfiguration,
      );
    }
    return AccountClosureClient._(
      client,
      baseUri,
      normalized,
      accessToken,
      timeout,
    );
  }

  AccountClosureClient._(
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
  bool _busy = false;
  bool _disposed = false;

  /// Invalidates a late result. The caller keeps the HTTP client.
  void close() => _disposed = true;

  Future<AccountClosureOutcome> closeAccount() async {
    if (_disposed) {
      throw const AccountClosureException(AccountClosureFailure.closed);
    }
    if (_busy) {
      throw const AccountClosureException(AccountClosureFailure.busy);
    }
    _busy = true;
    try {
      return await _perform().timeout(
        _timeout,
        onTimeout: () =>
            throw const AccountClosureException(AccountClosureFailure.timeout),
      );
    } finally {
      _busy = false;
    }
  }

  Future<AccountClosureOutcome> _perform() async {
    final token = await _bearer();
    final request = http.Request('POST', _baseUri.replace(path: _closurePath))
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['accept'] = 'application/json'
      ..headers['content-type'] = 'application/json'
      ..headers['authorization'] = 'Bearer $token'
      ..body = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'confirm': accountClosureConfirmation,
      });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (_) {
      throw const AccountClosureException(AccountClosureFailure.unavailable);
    }
    final body = await _readBounded(response);
    if (_disposed) {
      throw const AccountClosureException(AccountClosureFailure.closed);
    }
    if (response.isRedirect) {
      throw const AccountClosureException(
        AccountClosureFailure.invalidResponse,
      );
    }
    switch (response.statusCode) {
      case 200:
        return _decode(body, response.headers['content-type']);
      case 400:
        // The server refused the confirmation this client always sends, so the
        // contract has changed rather than the person mistyping anything.
        throw const AccountClosureException(
          AccountClosureFailure.invalidResponse,
        );
      case 401:
        throw const AccountClosureException(
          AccountClosureFailure.unauthenticated,
        );
      case 404:
        throw const AccountClosureException(
          AccountClosureFailure.accountMismatch,
        );
      case 503:
        throw const AccountClosureException(
          AccountClosureFailure.notConfigured,
        );
      default:
        throw const AccountClosureException(AccountClosureFailure.unavailable);
    }
  }

  Future<String> _bearer() async {
    PracticeAccessToken access;
    try {
      access = await _accessToken();
    } catch (error) {
      if (error is PracticeSyncException &&
          error.code == 'PRACTICE_ACCOUNT_MISMATCH') {
        throw const AccountClosureException(
          AccountClosureFailure.accountMismatch,
        );
      }
      throw const AccountClosureException(
        AccountClosureFailure.unauthenticated,
      );
    }
    String tokenAccount;
    try {
      tokenAccount = normalizePracticeUuid(access.accountId);
    } catch (_) {
      throw const AccountClosureException(
        AccountClosureFailure.accountMismatch,
      );
    }
    if (tokenAccount != accountId) {
      throw const AccountClosureException(
        AccountClosureFailure.accountMismatch,
      );
    }
    final token = access.token;
    final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(token);
    if (token.isEmpty ||
        token.length > 8192 ||
        match?.start != 0 ||
        match?.end != token.length) {
      throw const AccountClosureException(
        AccountClosureFailure.unauthenticated,
      );
    }
    return token;
  }

  Future<String> _readBounded(http.StreamedResponse response) async {
    if ((response.contentLength ?? 0) > _maxResponseBytes) {
      throw const AccountClosureException(
        AccountClosureFailure.invalidResponse,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length > _maxResponseBytes) {
        throw const AccountClosureException(
          AccountClosureFailure.invalidResponse,
        );
      }
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      throw const AccountClosureException(
        AccountClosureFailure.invalidResponse,
      );
    }
  }

  AccountClosureOutcome _decode(String body, String? contentType) {
    final type = (contentType ?? '').split(';').first.trim().toLowerCase();
    if (type != 'application/json') {
      throw const AccountClosureException(
        AccountClosureFailure.invalidResponse,
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const AccountClosureException(
        AccountClosureFailure.invalidResponse,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const AccountClosureException(
        AccountClosureFailure.invalidResponse,
      );
    }
    final closed = decoded['closed'];
    final canceled = decoded['canceledInvitations'];
    if (decoded['schemaVersion'] != 1 ||
        closed is! bool ||
        canceled is! int ||
        canceled < 0 ||
        canceled > 1000000) {
      throw const AccountClosureException(
        AccountClosureFailure.invalidResponse,
      );
    }
    return AccountClosureOutcome(closed: closed, canceledInvitations: canceled);
  }
}
