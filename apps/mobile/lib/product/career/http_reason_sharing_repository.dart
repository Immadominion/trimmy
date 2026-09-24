import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../account/guest_session.dart';
import 'career_repository.dart';
import 'reason_sharing_repository.dart';

const _privacyPath = '/v1/career/reason-privacy';
const _reasonsPath = '/v1/career/trade-reasons';
const _maxResponseBytes = 262144;
const _maxSafeInteger = 9007199254740991;

typedef ReasonSharingAuthorizationProvider =
    Future<PaperAuthorization> Function();

/// Reads and writes only the server-owned reason sharing contract. Every
/// read is `no-store` on the server, so nothing here is cached; callers own
/// any in-memory lifetime.
final class HttpReasonSharingRepository implements ReasonSharingRepository {
  factory HttpReasonSharingRepository({
    required http.Client client,
    required Uri baseUri,
    required ReasonSharingAuthorizationProvider authorizationProvider,
    void Function(GuestSessionFailure)? onGuestSessionFailure,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw const ReasonSharingException(ReasonSharingFailure.unavailable);
    }
    return HttpReasonSharingRepository._(
      client,
      _origin(baseUri, allowLoopbackForTests),
      authorizationProvider,
      onGuestSessionFailure,
      timeout,
    );
  }

  HttpReasonSharingRepository._(
    this._client,
    this._baseUri,
    this._authorization,
    this._onGuestSessionFailure,
    this._timeout,
  );

  final http.Client _client;
  final Uri _baseUri;
  final ReasonSharingAuthorizationProvider _authorization;
  final void Function(GuestSessionFailure)? _onGuestSessionFailure;
  final Duration _timeout;
  bool _closed = false;

  @override
  Future<ReasonPrivacy> getPrivacy() async {
    final decoded = await _request('GET', _privacyPath);
    final envelope = _object(decoded);
    _keys(envelope, const {'schemaVersion', 'reasonPrivacy'});
    if (envelope['schemaVersion'] != 1) _invalidResponse();
    return _privacy(envelope['reasonPrivacy']);
  }

  @override
  Future<ReasonPrivacyReceipt> putPrivacy(ReasonPrivacyWrite write) async {
    final decoded = await _request('PUT', _privacyPath, body: write.toJson());
    final envelope = _object(decoded);
    _keys(envelope, const {'schemaVersion', 'reasonPrivacy'});
    if (envelope['schemaVersion'] != 1) _invalidResponse();
    final privacy = _privacy(envelope['reasonPrivacy']);
    // A fresh write lands at exactly the next revision. An exact replay after
    // a later change returns that newer resource, never an older snapshot.
    if (!privacy.configured ||
        privacy.revision < write.baseRevision + 1 ||
        privacy.revision == write.baseRevision + 1 &&
            privacy.visibility != write.visibility) {
      _invalidResponse();
    }
    return ReasonPrivacyReceipt(
      mutationId: write.mutationId,
      baseRevision: write.baseRevision,
      visibility: write.visibility,
      privacy: privacy,
    );
  }

  @override
  Future<ReasonPage<OwnReason>> listOwnReasons(OwnReasonQuery query) async {
    _validateQueryCursor(
      query.cursor,
      scope: 'self',
      assetId: query.assetId,
      variantMint: query.variantMint,
    );
    final decoded = await _request(
      'GET',
      _reasonsPath,
      query: {
        'scope': 'self',
        'limit': '${query.limit}',
        if (query.assetId != null) 'assetId': query.assetId!,
        if (query.variantMint != null) 'variantMint': query.variantMint!,
        if (query.cursor != null) 'cursor': query.cursor!,
      },
    );
    return _page(
      decoded,
      scope: 'self',
      assetId: query.assetId,
      variantMint: query.variantMint,
      limit: query.limit,
      cursor: query.cursor,
      item: _ownReason,
      savedAt: (reason) => reason.savedAt,
      reasonId: (reason) => reason.reasonId,
      stock: (reason) => reason.stock,
    );
  }

  @override
  Future<ReasonPage<SharedReason>> listSharedReasons(
    SharedReasonQuery query,
  ) async {
    _validateQueryCursor(
      query.cursor,
      scope: 'everyone',
      assetId: query.assetId,
      variantMint: query.variantMint,
    );
    final decoded = await _request(
      'GET',
      _reasonsPath,
      query: {
        'scope': 'everyone',
        'limit': '${query.limit}',
        'assetId': query.assetId,
        'variantMint': query.variantMint,
        if (query.cursor != null) 'cursor': query.cursor!,
      },
    );
    return _page(
      decoded,
      scope: 'everyone',
      assetId: query.assetId,
      variantMint: query.variantMint,
      limit: query.limit,
      cursor: query.cursor,
      item: _sharedReason,
      savedAt: (reason) => reason.savedAt,
      reasonId: (reason) => reason.reasonId,
      stock: (reason) => reason.stock,
    );
  }

  @override
  Future<ReasonPage<SharedReason>> listFriendReasons(
    SharedReasonQuery query,
  ) async {
    _validateQueryCursor(
      query.cursor,
      scope: 'friends',
      assetId: query.assetId,
      variantMint: query.variantMint,
    );
    final decoded = await _request(
      'GET',
      _reasonsPath,
      query: {
        'scope': 'friends',
        'limit': '${query.limit}',
        'assetId': query.assetId,
        'variantMint': query.variantMint,
        if (query.cursor != null) 'cursor': query.cursor!,
      },
    );
    return _page(
      decoded,
      scope: 'friends',
      assetId: query.assetId,
      variantMint: query.variantMint,
      limit: query.limit,
      cursor: query.cursor,
      item: _friendReason,
      savedAt: (reason) => reason.savedAt,
      reasonId: (reason) => reason.reasonId,
      stock: (reason) => reason.stock,
    );
  }

  void close() => _closed = true;

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    if (_closed) {
      throw const ReasonSharingException(ReasonSharingFailure.unavailable);
    }
    var timedOut = false;
    final abort = Completer<void>();
    StreamIterator<List<int>>? iterator;

    Future<Object?> perform() async {
      PaperAuthorization authorization;
      try {
        authorization = await _authorization();
      } on GuestSessionException catch (error) {
        if (_isTerminalGuestFailure(error.failure)) {
          _onGuestSessionFailure?.call(error.failure);
          rethrow;
        }
        throw const ReasonSharingException(
          ReasonSharingFailure.accountRequired,
        );
      } catch (_) {
        throw const ReasonSharingException(
          ReasonSharingFailure.accountRequired,
        );
      }
      if (timedOut || _closed) {
        throw const ReasonSharingException(ReasonSharingFailure.timeout);
      }
      final header = _authorizationHeader(authorization);
      final request =
          http.AbortableRequest(
              method,
              _baseUri.replace(path: path, queryParameters: query),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['accept'] = 'application/json'
            ..headers['authorization'] = header;
      if (body != null) {
        final encoded = utf8.encode(jsonEncode(body));
        if (encoded.length > 512) {
          throw const ReasonSharingException(ReasonSharingFailure.invalidInput);
        }
        request
          ..headers['content-type'] = 'application/json'
          ..bodyBytes = encoded;
      }
      try {
        final response = await _client.send(request);
        if (timedOut || _closed) {
          await response.stream.listen(null).cancel();
          throw const ReasonSharingException(ReasonSharingFailure.timeout);
        }
        if (response.isRedirect ||
            response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.listen(null).cancel();
          throw const ReasonSharingException(
            ReasonSharingFailure.invalidResponse,
          );
        }
        if ((response.contentLength ?? 0) > _maxResponseBytes) {
          await response.stream.listen(null).cancel();
          throw const ReasonSharingException(
            ReasonSharingFailure.invalidResponse,
          );
        }
        _jsonContentType(response.headers['content-type']);
        final bytes = <int>[];
        iterator = StreamIterator(response.stream);
        while (await iterator!.moveNext()) {
          if (timedOut || _closed) {
            throw const ReasonSharingException(ReasonSharingFailure.timeout);
          }
          final chunk = iterator!.current;
          if (bytes.length + chunk.length > _maxResponseBytes) {
            throw const ReasonSharingException(
              ReasonSharingFailure.invalidResponse,
            );
          }
          bytes.addAll(chunk);
        }
        iterator = null;
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        } catch (_) {
          _invalidResponse();
        }
        if (response.statusCode != 200) {
          final terminalGuest = _terminalGuestFailure(decoded);
          if (terminalGuest != null) {
            _onGuestSessionFailure?.call(terminalGuest);
            throw GuestSessionException(terminalGuest);
          }
          throw ReasonSharingException(
            _failure(response.statusCode, decoded),
            retryAfter: response.statusCode == 429
                ? _retryAfter(response.headers['retry-after'])
                : null,
          );
        }
        return decoded;
      } on GuestSessionException {
        rethrow;
      } on ReasonSharingException {
        rethrow;
      } catch (_) {
        if (timedOut) {
          throw const ReasonSharingException(ReasonSharingFailure.timeout);
        }
        throw const ReasonSharingException(ReasonSharingFailure.offline);
      }
    }

    try {
      return await perform().timeout(
        _timeout,
        onTimeout: () {
          timedOut = true;
          if (!abort.isCompleted) abort.complete();
          final bodyIterator = iterator;
          if (bodyIterator != null) {
            unawaited(bodyIterator.cancel().catchError((Object _) {}));
          }
          throw const ReasonSharingException(ReasonSharingFailure.timeout);
        },
      );
    } finally {
      final bodyIterator = iterator;
      if (bodyIterator != null) {
        await bodyIterator.cancel().catchError((Object _) {});
      }
    }
  }
}

ReasonPrivacy _privacy(Object? input) {
  final value = _object(input);
  _keys(value, const {
    'revision',
    'visibility',
    'configured',
    'friendsSharing',
    'createdAt',
    'updatedAt',
  });
  final revision = _integer(value['revision'], minimum: 1);
  final visibility = _visibility(value['visibility']);
  final configured = value['configured'];
  if (configured is! bool) _invalidResponse();
  final friendsSharing = switch (value['friendsSharing']) {
    'unavailable' => FriendsSharingAvailability.unavailable,
    'available' => FriendsSharingAvailability.available,
    _ => _invalidResponse(),
  };
  final createdAt = _timestamp(value['createdAt']);
  final updatedAt = _timestamp(value['updatedAt']);
  if (updatedAt.isBefore(createdAt) ||
      !configured &&
          (revision != 1 ||
              visibility != ReasonVisibility.nobody ||
              updatedAt != createdAt) ||
      configured && (revision < 2 || !updatedAt.isAfter(createdAt))) {
    _invalidResponse();
  }
  return ReasonPrivacy(
    revision: revision,
    visibility: visibility,
    configured: configured,
    createdAt: createdAt,
    updatedAt: updatedAt,
    friendsSharing: friendsSharing,
  );
}

void _validateQueryCursor(
  String? cursor, {
  required String scope,
  required String? assetId,
  required String? variantMint,
}) {
  if (cursor == null) return;
  final decoded = ReasonCursor.decode(cursor);
  if (decoded == null ||
      decoded.scope != scope ||
      decoded.assetId != assetId ||
      decoded.variantMint != variantMint) {
    throw const ReasonSharingException(ReasonSharingFailure.invalidInput);
  }
}

ReasonPage<T> _page<T>(
  Object? input, {
  required String scope,
  required String? assetId,
  required String? variantMint,
  required int limit,
  required String? cursor,
  required T Function(Object?) item,
  required DateTime Function(T) savedAt,
  required String Function(T) reasonId,
  required ReasonStock Function(T) stock,
}) {
  final envelope = _object(input);
  _keys(envelope, const {
    'schemaVersion',
    'scope',
    'filter',
    'reasons',
    'page',
  });
  if (envelope['schemaVersion'] != 1 || envelope['scope'] != scope) {
    _invalidResponse();
  }
  final filter = envelope['filter'];
  if (assetId == null) {
    if (filter != null) _invalidResponse();
  } else {
    final value = _object(filter);
    _keys(value, const {'assetId', 'variantMint'});
    if (value['assetId'] != assetId || value['variantMint'] != variantMint) {
      _invalidResponse();
    }
  }
  final page = _object(envelope['page']);
  _keys(page, const {'limit', 'nextCursor'});
  if (page['limit'] != limit) _invalidResponse();
  final reasonsInput = envelope['reasons'];
  if (reasonsInput is! List || reasonsInput.length > limit) _invalidResponse();
  final items = <T>[];
  final seen = <String>{};
  final after = cursor == null ? null : ReasonCursor.decode(cursor);
  if (cursor != null &&
      (after == null ||
          after.scope != scope ||
          after.assetId != assetId ||
          after.variantMint != variantMint)) {
    throw const ReasonSharingException(ReasonSharingFailure.invalidInput);
  }
  for (final entry in reasonsInput) {
    final parsed = item(entry);
    final id = reasonId(parsed);
    final time = savedAt(parsed);
    final parsedStock = stock(parsed);
    if (!seen.add(id) ||
        assetId != null &&
            (parsedStock.assetId != assetId ||
                parsedStock.variantMint != variantMint) ||
        after != null && !_before(time, id, after.savedAt, after.reasonId)) {
      _invalidResponse();
    }
    if (items.isNotEmpty) {
      final previous = items.last;
      if (!_before(time, id, savedAt(previous), reasonId(previous))) {
        _invalidResponse();
      }
    }
    items.add(parsed);
  }
  final nextCursorInput = page['nextCursor'];
  String? nextCursor;
  if (nextCursorInput != null) {
    final text = _text(nextCursorInput, 512);
    final decoded = ReasonCursor.decode(text);
    if (items.length != limit ||
        decoded == null ||
        decoded.scope != scope ||
        decoded.assetId != assetId ||
        decoded.variantMint != variantMint ||
        decoded.savedAt != savedAt(items.last) ||
        decoded.reasonId != reasonId(items.last)) {
      _invalidResponse();
    }
    nextCursor = text;
  }
  return ReasonPage<T>(items: items, limit: limit, nextCursor: nextCursor);
}

/// Keyset order is `savedAt DESC, reasonId DESC`, so a later row is strictly
/// before its predecessor.
bool _before(DateTime time, String id, DateTime afterTime, String afterId) =>
    time.isBefore(afterTime) || time == afterTime && id.compareTo(afterId) < 0;

SharedReason _sharedReason(Object? input) {
  final value = _object(input);
  _keys(value, const {'reasonId', 'author', 'stock', 'note', 'savedAt'});
  return SharedReason(
    reasonId: _uuid(value['reasonId']),
    author: _author(value['author'], publicIdentity: false),
    stock: _stock(value['stock']),
    note: _note(value['note']),
    savedAt: _timestamp(value['savedAt']),
  );
}

SharedReason _friendReason(Object? input) {
  final value = _object(input);
  _keys(value, const {'reasonId', 'author', 'stock', 'note', 'savedAt'});
  final author = _author(value['author'], publicIdentity: true);
  if (author.isViewer) _invalidResponse();
  return SharedReason(
    reasonId: _uuid(value['reasonId']),
    author: author,
    stock: _stock(value['stock']),
    note: _note(value['note']),
    savedAt: _timestamp(value['savedAt']),
  );
}

OwnReason _ownReason(Object? input) {
  final value = _object(input);
  _keys(value, const {
    'reasonId',
    'orderId',
    'author',
    'stock',
    'note',
    'deskCycle',
    'savedAt',
  });
  final author = _author(value['author'], publicIdentity: false);
  if (!author.isViewer) _invalidResponse();
  final reasonId = _uuid(value['reasonId']);
  final orderId = _uuid(value['orderId']);
  if (reasonId == orderId) _invalidResponse();
  return OwnReason(
    reasonId: reasonId,
    orderId: orderId,
    author: author,
    stock: _stock(value['stock']),
    note: _note(value['note']),
    deskCycle: _deskCycle(value['deskCycle']),
    savedAt: _timestamp(value['savedAt']),
  );
}

ReasonAuthor _author(Object? input, {required bool publicIdentity}) {
  final value = _object(input);
  _keys(
    value,
    publicIdentity
        ? const {'socialId', 'handle', 'persona', 'rank', 'isViewer'}
        : const {'handle', 'rank', 'isViewer'},
  );
  final rank = _object(value['rank']);
  _keys(rank, const {'id', 'label'});
  final rankId = _rank(rank['id']);
  final label = _text(rank['label'], 40);
  if (label != _rankLabels[rankId]) _invalidResponse();
  final isViewer = value['isViewer'];
  if (isViewer is! bool) _invalidResponse();
  return ReasonAuthor(
    handle: _handle(value['handle']),
    rank: rankId,
    rankLabel: label,
    isViewer: isViewer,
    socialId: publicIdentity ? _uuid(value['socialId']) : null,
    persona: publicIdentity ? _persona(value['persona']) : null,
  );
}

ReasonStock _stock(Object? input) {
  final value = _object(input);
  _keys(value, const {'assetId', 'variantMint', 'symbol'});
  return ReasonStock(
    assetId: _assetId(value['assetId']),
    variantMint: _mint(value['variantMint']),
    symbol: _text(value['symbol'], 30),
  );
}

ReasonSharingFailure _failure(int status, Object? input) {
  if (status == 408 || status == 504) return ReasonSharingFailure.timeout;
  final envelope = _object(input);
  _keys(envelope, const {'error'});
  final error = _object(envelope['error']);
  _keys(error, const {'code', 'message', 'requestId'});
  final code = _text(error['code'], 100);
  _text(error['message'], 1024);
  _text(error['requestId'], 128);
  return switch (code) {
    'CAREER_REASON_SHARING_INVALID_INPUT' ||
    'INVALID_REQUEST' => ReasonSharingFailure.invalidInput,
    'CAREER_REASON_SHARING_UNAUTHENTICATED' ||
    'GUEST_SESSION_EXPIRED' ||
    'GUEST_SESSION_REVOKED' ||
    'GUEST_SESSION_UNAUTHENTICATED' => ReasonSharingFailure.accountRequired,
    'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND' =>
      ReasonSharingFailure.accountNotFound,
    'CAREER_REASON_FRIENDS_ACCOUNT_REQUIRED' =>
      ReasonSharingFailure.accountRequired,
    'CAREER_REASON_SHARING_UNAVAILABLE' => ReasonSharingFailure.unavailable,
    'CAREER_REASON_PRIVACY_REVISION_CONFLICT' =>
      ReasonSharingFailure.revisionConflict,
    'CAREER_REASON_SHARING_IDEMPOTENCY_CONFLICT' =>
      ReasonSharingFailure.idempotencyConflict,
    'CAREER_REASON_SHARING_REVISION_EXHAUSTED' =>
      ReasonSharingFailure.revisionExhausted,
    'GUEST_SESSION_RATE_LIMITED' => ReasonSharingFailure.rateLimited,
    _ when status == 401 || status == 403 =>
      ReasonSharingFailure.accountRequired,
    _ when status == 429 => ReasonSharingFailure.rateLimited,
    _ when status >= 500 => ReasonSharingFailure.unavailable,
    _ => ReasonSharingFailure.rejected,
  };
}

/// Only the exact delay-seconds form is trusted. Anything else is unknown.
Duration? _retryAfter(String? value) {
  if (value == null || !RegExp(r'^(?:0|[1-9][0-9]{0,5})$').hasMatch(value)) {
    return null;
  }
  return Duration(seconds: int.parse(value));
}

GuestSessionFailure? _terminalGuestFailure(Object? input) {
  String? code;
  if (input case {'error': final Map<String, dynamic> error}) {
    if (error['code'] case final String value) code = value;
  }
  return switch (code) {
    'GUEST_SESSION_EXPIRED' => GuestSessionFailure.expired,
    'GUEST_SESSION_REVOKED' => GuestSessionFailure.revoked,
    _ => null,
  };
}

bool _isTerminalGuestFailure(GuestSessionFailure failure) =>
    failure == GuestSessionFailure.expired ||
    failure == GuestSessionFailure.revoked;

const _rankLabels = <CareerRank, String>{
  CareerRank.rookie: 'Rookie',
  CareerRank.analyst: 'Analyst',
  CareerRank.trader: 'Trader',
  CareerRank.seniorTrader: 'Senior Trader',
  CareerRank.partner: 'Partner',
  CareerRank.legend: 'Legend',
};

CareerRank _rank(Object? input) => switch (_text(input, 20)) {
  'rookie' => CareerRank.rookie,
  'analyst' => CareerRank.analyst,
  'trader' => CareerRank.trader,
  'senior-trader' => CareerRank.seniorTrader,
  'partner' => CareerRank.partner,
  'legend' => CareerRank.legend,
  _ => _invalidResponse(),
};

ReasonVisibility _visibility(Object? input) => switch (_text(input, 20)) {
  'nobody' => ReasonVisibility.nobody,
  'everyone' => ReasonVisibility.everyone,
  'friends' => ReasonVisibility.friends,
  _ => _invalidResponse(),
};

ReasonDeskCycle _deskCycle(Object? input) => switch (_text(input, 20)) {
  'current' => ReasonDeskCycle.current,
  'historical' => ReasonDeskCycle.historical,
  _ => _invalidResponse(),
};

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) _invalidResponse();
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length || !expected.every(value.containsKey)) {
    _invalidResponse();
  }
}

int _integer(Object? value, {int minimum = 0}) {
  if (value is! int || value < minimum || value > _maxSafeInteger) {
    _invalidResponse();
  }
  return value;
}

String _text(Object? value, int maximum) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximum ||
      value.trim() != value ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    _invalidResponse();
  }
  return value;
}

String _note(Object? value) {
  final text = _text(value, 360);
  if (text.runes.length > 180) _invalidResponse();
  return text;
}

String _handle(Object? value) {
  final text = _text(value, 18);
  if (!RegExp(r'^[a-z][a-z0-9_]{2,17}$').hasMatch(text)) _invalidResponse();
  return text;
}

String _persona(Object? value) {
  final text = _text(value, 31);
  if (!const {'wolf', 'oracle', 'shark'}.contains(text)) {
    _invalidResponse();
  }
  return text;
}

String _uuid(Object? value) {
  final text = _text(value, 36).toLowerCase();
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(text)) {
    _invalidResponse();
  }
  return text;
}

String _assetId(Object? value) {
  final text = _text(value, 100);
  if (!isReasonSharingAssetId(text)) _invalidResponse();
  return text;
}

String _mint(Object? value) {
  final text = _text(value, 44);
  if (!isReasonSharingMint(text)) _invalidResponse();
  return text;
}

DateTime _timestamp(Object? value) {
  final parsed = parseReasonSharingTimestamp(_text(value, 24));
  if (parsed == null) _invalidResponse();
  return parsed;
}

Uri _origin(Uri uri, bool allowLoopbackForTests) {
  final loopback =
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1');
  if (!uri.hasScheme ||
      uri.host.isEmpty ||
      uri.host.endsWith('.') ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.path != '' && uri.path != '/' ||
      uri.scheme != 'https' && !(allowLoopbackForTests && loopback)) {
    throw const ReasonSharingException(ReasonSharingFailure.unavailable);
  }
  return uri.replace(path: '');
}

String _authorizationHeader(PaperAuthorization value) {
  return switch (value) {
    PrivyPaperAuthorization(:final token) =>
      _validBearer(token) ? 'Bearer $token' : _invalidAuthorization(),
    GuestPaperAuthorization(:final token) =>
      RegExp(r'^tg1_[A-Za-z0-9_-]{43}$').hasMatch(token)
          ? 'Guest $token'
          : _invalidAuthorization(),
  };
}

bool _validBearer(String value) {
  final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(value);
  return value.isNotEmpty &&
      value.length <= 8192 &&
      match?.start == 0 &&
      match?.end == value.length;
}

Never _invalidAuthorization() =>
    throw const ReasonSharingException(ReasonSharingFailure.accountRequired);

void _jsonContentType(String? value) {
  final parts = value?.toLowerCase().split(';').map((part) => part.trim());
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

Never _invalidResponse() =>
    throw const ReasonSharingException(ReasonSharingFailure.invalidResponse);
