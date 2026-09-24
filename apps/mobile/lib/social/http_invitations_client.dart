import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../practice_sync/http_transport.dart';
import '../practice_sync/protocol.dart';
import 'invitation.dart';

const _invitationsPath = '/v1/invitations';
const _maxResponseBytes = 262144;

/// Reads and changes the signed-in account's unfunded invitations.
///
/// One request at a time, bounded and cancellable. Every call obtains a fresh
/// bearer for the account fixed at construction, and a token issued for a
/// different account is refused before anything is sent. No call funds, holds
/// or delivers anything.
class HttpInvitationsClient {
  factory HttpInvitationsClient({
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
      throw const InvitationException(InvitationFailure.invalidConfiguration);
    }
    final String normalized;
    try {
      normalized = normalizePracticeUuid(accountId);
    } catch (_) {
      throw const InvitationException(InvitationFailure.invalidConfiguration);
    }
    return HttpInvitationsClient._(
      client,
      baseUri,
      normalized,
      accessToken,
      timeout,
    );
  }

  HttpInvitationsClient._(
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

  /// Invalidates late results. The caller keeps the HTTP client.
  void close() => _disposed = true;

  /// One bounded invitation page. [cursor] is opaque and stays bound to [box].
  Future<InvitationPage> list({
    InvitationBox box = InvitationBox.open,
    int limit = 20,
    String? cursor,
  }) async {
    if (limit < 1 ||
        limit > 50 ||
        (cursor != null &&
            !RegExp(r'^[A-Za-z0-9_-]{1,512}$').hasMatch(cursor))) {
      throw const InvitationException(InvitationFailure.invalidRequest);
    }
    return await _send(
      method: 'GET',
      path: _invitationsPath,
      queryParameters: <String, String>{
        'box': box.wireValue,
        'limit': '$limit',
        'cursor': ?cursor,
      },
      decode: (value) => InvitationPage.fromJson(value, box: box, limit: limit),
    );
  }

  /// Creates an unaddressed draft that stops being usable at [expiresAt].
  Future<InvitationRecord> create({
    required String mutationId,
    required DateTime expiresAt,
  }) async {
    final instant = expiresAt.toUtc();
    // A persisted retry may appear expired under a changed device clock. Send
    // the exact command and let the server replay its receipt or reject it.
    if (_checkedIdOrNull(mutationId) == null) {
      throw const InvitationException(InvitationFailure.invalidRequest);
    }
    return await _send(
      method: 'POST',
      path: _invitationsPath,
      body: <String, Object?>{
        'schemaVersion': 2,
        'mutationId': mutationId,
        'expiresAt': _millisecondIso(instant),
      },
      decode: (value) {
        final record = InvitationRecord.fromJson(value);
        // A receipt replay returns the invitation's current state. Another
        // device may have addressed, offered or closed the draft after this
        // device lost the original create response.
        if (!record.isSender || record.expiresAt != instant) {
          invalidInvitationResponse();
        }
        return record;
      },
    );
  }

  /// Takes one step on one invitation. Only addressing carries [xHandle]. The
  /// server resolves it and never accepts a client-supplied X subject.
  Future<InvitationRecord> act({
    required String invitationId,
    required InvitationAction action,
    required int expectedVersion,
    String? xHandle,
  }) async {
    final id = _checkedId(invitationId);
    final hasHandle = xHandle != null;
    final validHandle =
        xHandle == null ||
        RegExp(r'^[A-Za-z0-9_]{1,15}$').firstMatch(xHandle)?.group(0) ==
            xHandle;
    if ((action == InvitationAction.address) != hasHandle ||
        !validHandle ||
        expectedVersion < 0 ||
        expectedVersion >= 9007199254740991) {
      throw const InvitationException(InvitationFailure.invalidRequest);
    }
    return await _send(
      method: 'POST',
      path: '$_invitationsPath/$id/actions',
      body: <String, Object?>{
        'schemaVersion': 2,
        'action': action.name,
        'expectedVersion': expectedVersion,
        'xHandle': ?xHandle,
      },
      decode: InvitationRecord.fromJson,
    );
  }

  static String _millisecondIso(DateTime utc) {
    final text = utc.toIso8601String();
    // The server accepts exactly millisecond precision with a Z suffix.
    final trimmed = text.contains('.')
        ? '${text.substring(0, text.indexOf('.') + 4)}Z'
        : '${text.replaceAll('Z', '')}.000Z';
    return trimmed;
  }

  String _checkedId(String value) {
    if (_checkedIdOrNull(value) == null) {
      throw const InvitationException(InvitationFailure.invalidRequest);
    }
    return value;
  }

  String? _checkedIdOrNull(String value) {
    final match = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).firstMatch(value);
    return match?.group(0) == value ? value : null;
  }

  Future<T> _send<T>({
    required String method,
    required String path,
    required T Function(Object?) decode,
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
  }) async {
    if (_disposed) {
      throw const InvitationException(InvitationFailure.closed);
    }
    if (_busy) {
      throw const InvitationException(InvitationFailure.busy);
    }
    _busy = true;
    try {
      return await _perform(
        method,
        path,
        decode,
        body,
        queryParameters,
      ).timeout(
        _timeout,
        onTimeout: () =>
            throw const InvitationException(InvitationFailure.timeout),
      );
    } finally {
      _busy = false;
    }
  }

  Future<T> _perform<T>(
    String method,
    String path,
    T Function(Object?) decode,
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
  ) async {
    final token = await _bearer();
    final request =
        http.Request(
            method,
            _baseUri.replace(path: path, queryParameters: queryParameters),
          )
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers['accept'] = 'application/json'
          ..headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode(body);
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (_) {
      throw const InvitationException(InvitationFailure.unavailable);
    }
    final text = await _readBounded(response);
    if (_disposed) {
      throw const InvitationException(InvitationFailure.closed);
    }
    if (response.isRedirect) invalidInvitationResponse();
    final type = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (type != 'application/json') invalidInvitationResponse();
    if (response.statusCode == 200 || response.statusCode == 201) {
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        invalidInvitationResponse();
      }
      return decode(decoded);
    }
    throw InvitationException(_failure(response.statusCode, text));
  }

  /// The server's own error code decides between the several conflicts that
  /// share one status, so the interface can say something true.
  InvitationFailure _failure(int status, String text) {
    late final String code;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 1 ||
          decoded['error'] is! Map<String, dynamic>) {
        return InvitationFailure.invalidResponse;
      }
      final error = decoded['error'] as Map<String, dynamic>;
      final rawCode = error['code'];
      final message = error['message'];
      final requestId = error['requestId'];
      if (error.length != 3 ||
          rawCode is! String ||
          rawCode.isEmpty ||
          rawCode.length > 100 ||
          message is! String ||
          message.isEmpty ||
          message.length > 1024 ||
          requestId is! String ||
          requestId.isEmpty ||
          requestId.length > 128) {
        return InvitationFailure.invalidResponse;
      }
      code = rawCode;
    } catch (_) {
      return InvitationFailure.invalidResponse;
    }
    switch (code) {
      case 'INVITATION_VERSION_CONFLICT':
        return InvitationFailure.versionConflict;
      case 'INVITATION_INVALID_TRANSITION':
        return InvitationFailure.invalidTransition;
      case 'INVITATION_EXPIRED':
        return InvitationFailure.expired;
      case 'INVITATION_LIMIT_REACHED':
        return InvitationFailure.limitReached;
      case 'SOCIAL_INVITATION_IDEMPOTENCY_CONFLICT':
        return InvitationFailure.idempotencyConflict;
      case 'SOCIAL_IDENTITY_UNAVAILABLE':
        return InvitationFailure.xLinkRequired;
      case 'SOCIAL_IDENTITY_CONFLICT':
        return InvitationFailure.identityConflict;
      case 'SOCIAL_PAIR_UNAVAILABLE':
        return InvitationFailure.relationshipUnavailable;
      case 'SOCIAL_FRIEND_LIMIT_REACHED':
        return InvitationFailure.limitReached;
      case 'SOCIAL_RATE_LIMITED':
      case 'X_LOOKUP_RATE_LIMITED':
      case 'X_PROVIDER_RATE_LIMITED':
      case 'X_PROFILE_RATE_LIMITED':
        return InvitationFailure.rateLimited;
      case 'SOCIAL_PROFILE_MISSING':
        return InvitationFailure.accountMismatch;
      case 'INVITATION_INVALID_INPUT':
        return InvitationFailure.invalidRequest;
      case 'X_PROFILE_INVALID_USERNAME':
      case 'X_HANDLE_INVALID':
        return InvitationFailure.invalidXHandle;
      case 'X_PROFILE_NOT_FOUND':
        return InvitationFailure.xHandleNotFound;
      case 'INVITATION_FORBIDDEN':
        return InvitationFailure.forbidden;
      case 'INVITATION_NOT_FOUND':
        return InvitationFailure.notFound;
      case 'INVITATION_ACCOUNT_NOT_FOUND':
        return InvitationFailure.accountMismatch;
      case 'INVITATION_UNAVAILABLE':
        return InvitationFailure.notConfigured;
    }
    return switch (status) {
      400 => InvitationFailure.invalidRequest,
      401 => InvitationFailure.unauthenticated,
      403 => InvitationFailure.forbidden,
      404 => InvitationFailure.notFound,
      409 => InvitationFailure.versionConflict,
      429 => InvitationFailure.rateLimited,
      503 => InvitationFailure.notConfigured,
      504 => InvitationFailure.timeout,
      _ => InvitationFailure.unavailable,
    };
  }

  Future<String> _bearer() async {
    PracticeAccessToken access;
    try {
      access = await _accessToken();
    } catch (error) {
      if (error is PracticeSyncException &&
          error.code == 'PRACTICE_ACCOUNT_MISMATCH') {
        throw const InvitationException(InvitationFailure.accountMismatch);
      }
      throw const InvitationException(InvitationFailure.unauthenticated);
    }
    String tokenAccount;
    try {
      tokenAccount = normalizePracticeUuid(access.accountId);
    } catch (_) {
      throw const InvitationException(InvitationFailure.accountMismatch);
    }
    if (tokenAccount != accountId) {
      throw const InvitationException(InvitationFailure.accountMismatch);
    }
    final token = access.token;
    final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(token);
    if (token.isEmpty ||
        token.length > 8192 ||
        match?.start != 0 ||
        match?.end != token.length) {
      throw const InvitationException(InvitationFailure.unauthenticated);
    }
    return token;
  }

  Future<String> _readBounded(http.StreamedResponse response) async {
    if ((response.contentLength ?? 0) > _maxResponseBytes) {
      invalidInvitationResponse();
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length > _maxResponseBytes) invalidInvitationResponse();
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return invalidInvitationResponse();
    }
  }
}
