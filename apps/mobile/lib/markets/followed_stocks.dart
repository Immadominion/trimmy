import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../practice_sync/http_transport.dart';
import '../practice_sync/protocol.dart';

const _followingPath = '/v1/following';
const _maxResponseBytes = 65536;
const _maxFollowed = 50;

/// Why a followed-list call could not be completed.
enum FollowedStocksFailure {
  invalidConfiguration,
  invalidRequest,
  unauthenticated,
  accountMismatch,

  /// Someone or something changed the list first; it was reloaded.
  revisionConflict,

  /// The list is full.
  limitReached,

  /// The server has the real followed list switched off.
  notConfigured,
  unavailable,
  invalidResponse,
  timeout,
  busy,
  closed,
}

class FollowedStocksException implements Exception {
  const FollowedStocksException(this.failure);

  final FollowedStocksFailure failure;

  @override
  String toString() => 'FollowedStocksException(${failure.name})';
}

Never _invalidResponse() =>
    throw const FollowedStocksException(FollowedStocksFailure.invalidResponse);

/// The list exactly as the server reported it.
///
/// It holds identifiers only. Following something records a name someone kept;
/// it is not an approval, a price, a holding or a permission to trade.
final class FollowedStocks {
  const FollowedStocks({
    required this.revision,
    required this.assetIds,
    required this.updatedAt,
  });

  final int revision;
  final List<String> assetIds;
  final DateTime? updatedAt;

  static final _assetId = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

  bool contains(String assetId) => assetIds.contains(assetId);

  static bool isStorableId(String value) =>
      value.length <= 100 && _assetId.firstMatch(value)?.group(0) == value;

  static FollowedStocks fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.length != 4 ||
        value['schemaVersion'] != 1) {
      _invalidResponse();
    }
    final revision = value['revision'];
    final rows = value['assetIds'];
    final updated = value['updatedAt'];
    if (revision is! int ||
        revision < 0 ||
        rows is! List ||
        rows.length > _maxFollowed) {
      _invalidResponse();
    }
    final ids = <String>[];
    for (final row in rows) {
      if (row is! String || !isStorableId(row) || ids.contains(row)) {
        _invalidResponse();
      }
      ids.add(row);
    }
    if (revision == 0 && (ids.isNotEmpty || updated != null)) {
      _invalidResponse();
    }
    DateTime? at;
    if (revision != 0) {
      if (updated is! String || !updated.endsWith('Z')) _invalidResponse();
      at = DateTime.tryParse(updated)?.toUtc();
      if (at == null) _invalidResponse();
    }
    return FollowedStocks(
      revision: revision,
      assetIds: List.unmodifiable(ids),
      updatedAt: at,
    );
  }
}

/// Reads and rewrites the signed-in account's real followed list.
///
/// One request at a time, bounded and cancellable. Every call obtains a fresh
/// bearer for the account fixed at construction, and a token issued for a
/// different account is refused before anything is sent.
class HttpFollowedStocksClient {
  factory HttpFollowedStocksClient({
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
      throw const FollowedStocksException(
        FollowedStocksFailure.invalidConfiguration,
      );
    }
    final String normalized;
    try {
      normalized = normalizePracticeUuid(accountId);
    } catch (_) {
      throw const FollowedStocksException(
        FollowedStocksFailure.invalidConfiguration,
      );
    }
    return HttpFollowedStocksClient._(
      client,
      baseUri,
      normalized,
      accessToken,
      timeout,
    );
  }

  HttpFollowedStocksClient._(
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

  Future<FollowedStocks> read() => _send(method: 'GET');

  /// Replaces the whole list at [baseRevision]. The server refuses a stale one.
  Future<FollowedStocks> write({
    required int baseRevision,
    required List<String> assetIds,
    required String mutationId,
  }) {
    if (baseRevision < 0 ||
        assetIds.length > _maxFollowed ||
        assetIds.toSet().length != assetIds.length ||
        assetIds.any((id) => !FollowedStocks.isStorableId(id))) {
      throw const FollowedStocksException(FollowedStocksFailure.invalidRequest);
    }
    return _send(
      method: 'PUT',
      body: <String, Object?>{
        'schemaVersion': 1,
        'mutationId': mutationId,
        'baseRevision': baseRevision,
        'assetIds': assetIds,
      },
    );
  }

  Future<FollowedStocks> _send({
    required String method,
    Map<String, Object?>? body,
  }) async {
    if (_disposed) {
      throw const FollowedStocksException(FollowedStocksFailure.closed);
    }
    if (_busy) {
      throw const FollowedStocksException(FollowedStocksFailure.busy);
    }
    _busy = true;
    try {
      return await _perform(method, body).timeout(
        _timeout,
        onTimeout: () =>
            throw const FollowedStocksException(FollowedStocksFailure.timeout),
      );
    } finally {
      _busy = false;
    }
  }

  Future<FollowedStocks> _perform(
    String method,
    Map<String, Object?>? body,
  ) async {
    final token = await _bearer();
    final request = http.Request(method, _baseUri.replace(path: _followingPath))
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
      throw const FollowedStocksException(FollowedStocksFailure.unavailable);
    }
    final text = await _readBounded(response);
    if (_disposed) {
      throw const FollowedStocksException(FollowedStocksFailure.closed);
    }
    if (response.isRedirect) _invalidResponse();
    if (response.statusCode == 200) {
      final type = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      if (type != 'application/json') _invalidResponse();
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        _invalidResponse();
      }
      return FollowedStocks.fromJson(decoded);
    }
    throw FollowedStocksException(_failure(response.statusCode, text));
  }

  /// The server's own code separates the conflicts that share one status.
  FollowedStocksFailure _failure(int status, String text) {
    String? code;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic> && error['code'] is String) {
          code = error['code'] as String;
        }
      }
    } catch (_) {
      code = null;
    }
    return switch (status) {
      400 => FollowedStocksFailure.invalidRequest,
      401 => FollowedStocksFailure.unauthenticated,
      403 => FollowedStocksFailure.accountMismatch,
      404 => FollowedStocksFailure.accountMismatch,
      409 =>
        code == 'WATCHLIST_IDEMPOTENCY_CONFLICT'
            ? FollowedStocksFailure.invalidRequest
            : FollowedStocksFailure.revisionConflict,
      503 =>
        code == 'WATCHLIST_REVISION_EXHAUSTED'
            ? FollowedStocksFailure.limitReached
            : FollowedStocksFailure.notConfigured,
      _ => FollowedStocksFailure.unavailable,
    };
  }

  Future<String> _bearer() async {
    final PracticeAccessToken token;
    try {
      token = await _accessToken();
    } catch (_) {
      throw const FollowedStocksException(
        FollowedStocksFailure.unauthenticated,
      );
    }
    if (token.accountId != accountId) {
      throw const FollowedStocksException(
        FollowedStocksFailure.accountMismatch,
      );
    }
    return token.token;
  }

  Future<String> _readBounded(http.StreamedResponse response) async {
    final declared = response.contentLength;
    if (declared != null && declared > _maxResponseBytes) _invalidResponse();
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (bytes.length > _maxResponseBytes) _invalidResponse();
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return _invalidResponse();
    }
  }
}
