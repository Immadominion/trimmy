import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../practice_sync/http_transport.dart';
import '../practice_sync/protocol.dart';
import 'relationship.dart';

const _friendsPath = '/v1/social/friends';
const _blocksPath = '/v1/social/blocks';
const _reportsPath = '/v1/social/reason-reports';
const _relationshipMaxResponseBytes = 262144;

/// Account-bound transport for relationship and safety controls.
///
/// The caller supplies only public social identifiers and durable mutation
/// commands. A fresh bearer is obtained and account-bound for every request.
final class HttpRelationshipsClient {
  factory HttpRelationshipsClient({
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
      throw const RelationshipException(
        RelationshipFailure.invalidConfiguration,
      );
    }
    final String normalized;
    try {
      normalized = normalizePracticeUuid(accountId);
    } catch (_) {
      throw const RelationshipException(
        RelationshipFailure.invalidConfiguration,
      );
    }
    return HttpRelationshipsClient._(
      client,
      baseUri,
      normalized,
      accessToken,
      timeout,
    );
  }

  HttpRelationshipsClient._(
    this._client,
    this._baseUri,
    this.accountId,
    this._accessToken,
    this._timeout,
  );

  final http.Client _client;
  final Uri _baseUri;
  final Future<PracticeAccessToken> Function() _accessToken;
  final Duration _timeout;
  final String accountId;
  bool _busy = false;
  bool _closed = false;

  void close() => _closed = true;

  Future<FriendPage> listFriends({int limit = 20, String? cursor}) async {
    _validatePage(limit, cursor);
    return _send(
      method: 'GET',
      path: _friendsPath,
      queryParameters: {'limit': '$limit', 'cursor': ?cursor},
      successStatuses: const {200},
      decode: (value, _) => FriendPage.fromJson(value, limit: limit),
    );
  }

  Future<FriendRemoveReceipt> removeFriend(FriendRemoveCommand command) =>
      _send(
        method: 'POST',
        path: '$_friendsPath/${command.friendshipId}/actions',
        body: command.body,
        successStatuses: const {200},
        decode: (value, _) =>
            FriendRemoveReceipt.fromJson(value, command: command),
      );

  Future<BlockPage> listBlocks({int limit = 20, String? cursor}) async {
    _validatePage(limit, cursor);
    return _send(
      method: 'GET',
      path: _blocksPath,
      queryParameters: {'limit': '$limit', 'cursor': ?cursor},
      successStatuses: const {200},
      decode: (value, _) => BlockPage.fromJson(value, limit: limit),
    );
  }

  Future<BlockState> getBlock(String socialId) {
    if (!isRelationshipUuid(socialId)) {
      throw const RelationshipException(RelationshipFailure.invalidRequest);
    }
    return _send(
      method: 'GET',
      path: '$_blocksPath/$socialId',
      successStatuses: const {200},
      decode: (value, _) => BlockState.fromJson(value, socialId: socialId),
    );
  }

  Future<BlockReceipt> putBlock(BlockCommand command) => _send(
    method: 'PUT',
    path: '$_blocksPath/${command.socialId}',
    body: command.body,
    successStatuses: const {200},
    decode: (value, _) => BlockReceipt.fromJson(value, command: command),
  );

  Future<ReasonReportReceipt> reportReason(ReasonReportCommand command) =>
      _send(
        method: 'POST',
        path: _reportsPath,
        body: command.body,
        successStatuses: const {200, 202},
        decode: (value, status) => ReasonReportReceipt.fromJson(
          value,
          command: command,
          created: status == 202,
        ),
      );

  void _validatePage(int limit, String? cursor) {
    if (limit < 1 ||
        limit > 50 ||
        (cursor != null &&
            !RegExp(r'^[A-Za-z0-9_-]{1,512}$').hasMatch(cursor))) {
      throw const RelationshipException(RelationshipFailure.invalidRequest);
    }
  }

  Future<T> _send<T>({
    required String method,
    required String path,
    required Set<int> successStatuses,
    required T Function(Object?, int) decode,
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
  }) async {
    if (_closed) {
      throw const RelationshipException(RelationshipFailure.closed);
    }
    if (_busy) {
      throw const RelationshipException(RelationshipFailure.busy);
    }
    _busy = true;
    try {
      return await _perform(
        method: method,
        path: path,
        successStatuses: successStatuses,
        decode: decode,
        body: body,
        queryParameters: queryParameters,
      ).timeout(
        _timeout,
        onTimeout: () =>
            throw const RelationshipException(RelationshipFailure.timeout),
      );
    } finally {
      _busy = false;
    }
  }

  Future<T> _perform<T>({
    required String method,
    required String path,
    required Set<int> successStatuses,
    required T Function(Object?, int) decode,
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
  }) async {
    final bearer = await _bearer();
    final request =
        http.Request(
            method,
            _baseUri.replace(path: path, queryParameters: queryParameters),
          )
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers['accept'] = 'application/json'
          ..headers['authorization'] = 'Bearer $bearer'
          ..headers['cache-control'] = 'no-store';
    if (body != null) {
      request
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode(body);
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (_) {
      throw const RelationshipException(RelationshipFailure.unavailable);
    }
    final text = await _readBounded(response);
    if (_closed) {
      throw const RelationshipException(RelationshipFailure.closed);
    }
    if (response.isRedirect) invalidRelationshipResponse();
    final type = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (type != 'application/json') invalidRelationshipResponse();
    if (successStatuses.contains(response.statusCode)) {
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        invalidRelationshipResponse();
      }
      return decode(decoded, response.statusCode);
    }
    throw RelationshipException(_failure(response.statusCode, text));
  }

  RelationshipFailure _failure(int status, String text) {
    late final String code;
    try {
      final decoded = jsonDecode(text);
      final envelope = relationshipObject(decoded, const {'error'});
      final error = relationshipObject(envelope['error'], const {
        'code',
        'message',
        'requestId',
      });
      final rawCode = error['code'];
      final message = error['message'];
      final requestId = error['requestId'];
      if (rawCode is! String ||
          rawCode.isEmpty ||
          rawCode.length > 100 ||
          message is! String ||
          message.isEmpty ||
          message.length > 1024 ||
          requestId is! String ||
          requestId.isEmpty ||
          requestId.length > 128) {
        invalidRelationshipResponse();
      }
      code = rawCode;
    } on RelationshipException {
      return RelationshipFailure.invalidResponse;
    } catch (_) {
      return RelationshipFailure.invalidResponse;
    }
    switch (code) {
      case 'SOCIAL_RELATIONSHIP_REVISION_CONFLICT':
      case 'SOCIAL_BLOCK_REVISION_CONFLICT':
        return RelationshipFailure.revisionConflict;
      case 'SOCIAL_RELATIONSHIP_IDEMPOTENCY_CONFLICT':
      case 'SOCIAL_BLOCK_IDEMPOTENCY_CONFLICT':
      case 'SOCIAL_REPORT_IDEMPOTENCY_CONFLICT':
        return RelationshipFailure.idempotencyConflict;
      case 'SOCIAL_RELATIONSHIP_NOT_ACTIVE':
        return RelationshipFailure.notActive;
      case 'SOCIAL_FRIEND_LIMIT_REACHED':
        return RelationshipFailure.limitReached;
      case 'SOCIAL_PAIR_UNAVAILABLE':
        return RelationshipFailure.pairUnavailable;
      case 'SOCIAL_RATE_LIMITED':
        return RelationshipFailure.rateLimited;
      case 'SOCIAL_ACCOUNT_NOT_FOUND':
      case 'SOCIAL_PROFILE_MISSING':
        return RelationshipFailure.accountMismatch;
      case 'SOCIAL_RELATIONSHIP_NOT_FOUND':
      case 'SOCIAL_REASON_UNAVAILABLE':
        return RelationshipFailure.notFound;
      case 'SOCIAL_RELATIONSHIP_FORBIDDEN':
        return RelationshipFailure.forbidden;
      case 'SOCIAL_RELATIONSHIP_UNAVAILABLE':
      case 'SOCIAL_UNAVAILABLE':
        return RelationshipFailure.notConfigured;
    }
    return switch (status) {
      400 => RelationshipFailure.invalidRequest,
      401 => RelationshipFailure.unauthenticated,
      403 => RelationshipFailure.forbidden,
      404 => RelationshipFailure.notFound,
      409 => RelationshipFailure.revisionConflict,
      429 => RelationshipFailure.rateLimited,
      503 => RelationshipFailure.notConfigured,
      504 => RelationshipFailure.timeout,
      _ => RelationshipFailure.unavailable,
    };
  }

  Future<String> _bearer() async {
    PracticeAccessToken access;
    try {
      access = await _accessToken();
    } catch (error) {
      if (error is PracticeSyncException &&
          error.code == 'PRACTICE_ACCOUNT_MISMATCH') {
        throw const RelationshipException(RelationshipFailure.accountMismatch);
      }
      throw const RelationshipException(RelationshipFailure.unauthenticated);
    }
    String tokenAccount;
    try {
      tokenAccount = normalizePracticeUuid(access.accountId);
    } catch (_) {
      throw const RelationshipException(RelationshipFailure.accountMismatch);
    }
    if (tokenAccount != accountId) {
      throw const RelationshipException(RelationshipFailure.accountMismatch);
    }
    final token = access.token;
    final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(token);
    if (token.isEmpty ||
        token.length > 8192 ||
        match?.start != 0 ||
        match?.end != token.length) {
      throw const RelationshipException(RelationshipFailure.unauthenticated);
    }
    return token;
  }

  Future<String> _readBounded(http.StreamedResponse response) async {
    if ((response.contentLength ?? 0) > _relationshipMaxResponseBytes) {
      invalidRelationshipResponse();
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length > _relationshipMaxResponseBytes) {
        invalidRelationshipResponse();
      }
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return invalidRelationshipResponse();
    }
  }
}
