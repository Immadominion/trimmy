import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _sessionPath = '/v1/guest/session';
const _refreshPath = '/v1/guest/session/refresh';
const _claimPath = '/v1/guest/claim';
const _storageKey = 'trimmy.guest.session.v1';
const _maxResponseBytes = 16384;

enum GuestSessionFailure {
  unavailable,
  offline,
  timeout,
  expired,
  revoked,
  rateLimited,
  accountAlreadySaved,
  alreadyClaimed,
  rejected,
  protectedStorage,
}

final class GuestSessionException implements Exception {
  const GuestSessionException(this.failure);
  final GuestSessionFailure failure;
}

/// Durable material for one anonymous-session creation attempt.
///
/// The UUID identifies the request but grants no access. The replay secret is
/// kept only in secure storage and proves an exact retry after an uncertain
/// response. Neither value is a paper-session credential.
final class GuestIssuanceRequest {
  const GuestIssuanceRequest({
    required this.requestId,
    required this.replaySecret,
  });

  final String requestId;
  final String replaySecret;

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'requestId': requestId,
    'replaySecret': replaySecret,
  };
}

final class GuestSessionCredential {
  const GuestSessionCredential({
    required this.guestId,
    required this.token,
    required this.expiresAt,
    required this.hardExpiresAt,
    required this.claimIdempotencyKey,
  });

  final String guestId;
  final String token;
  final DateTime expiresAt;
  final DateTime hardExpiresAt;
  final String claimIdempotencyKey;

  GuestSessionCredential withExpiry({
    required DateTime expiresAt,
    required DateTime hardExpiresAt,
  }) => GuestSessionCredential(
    guestId: guestId,
    token: token,
    expiresAt: expiresAt,
    hardExpiresAt: hardExpiresAt,
    claimIdempotencyKey: claimIdempotencyKey,
  );

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'guestId': guestId,
    'token': token,
    'expiresAt': expiresAt.toIso8601String(),
    'hardExpiresAt': hardExpiresAt.toIso8601String(),
    'claimIdempotencyKey': claimIdempotencyKey,
  };

  static GuestSessionCredential fromJson(Object? input) {
    if (input is! Map<String, dynamic> ||
        input.length != 6 ||
        input['schemaVersion'] != 1) {
      throw const GuestSessionException(GuestSessionFailure.protectedStorage);
    }
    final guestId = _uuid(input['guestId']);
    final token = _guestToken(input['token']);
    final expiresAt = _utc(input['expiresAt']);
    final hardExpiresAt = _utc(input['hardExpiresAt']);
    final claimIdempotencyKey = _uuid(input['claimIdempotencyKey']);
    if (expiresAt.isAfter(hardExpiresAt) ||
        hardExpiresAt.difference(expiresAt) > const Duration(days: 90)) {
      throw const GuestSessionException(GuestSessionFailure.protectedStorage);
    }
    return GuestSessionCredential(
      guestId: guestId,
      token: token,
      expiresAt: expiresAt,
      hardExpiresAt: hardExpiresAt,
      claimIdempotencyKey: claimIdempotencyKey,
    );
  }
}

abstract interface class GuestCredentialStore {
  Future<GuestSessionCredential?> read();

  /// Atomically replaces any pending issuance proof with the active record.
  Future<void> write(GuestSessionCredential value);

  /// Persists issuance material before the first create request. It survives
  /// an uncertain response so retry cannot fork another guest.
  Future<GuestIssuanceRequest?> readIssuanceRequest();
  Future<void> writeIssuanceRequest(GuestIssuanceRequest value);

  Future<void> clear();
}

/// Stores either the pending replay proof or the active guest credential in
/// one platform-secure record. Neither secret reaches SharedPreferences or
/// diagnostics.
final class SecureGuestCredentialStore implements GuestCredentialStore {
  SecureGuestCredentialStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(migrateWithBackup: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<GuestSessionCredential?> read() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (_storedIssuanceRequest(decoded) != null) return null;
      return GuestSessionCredential.fromJson(decoded);
    } catch (error) {
      if (error is GuestSessionException) rethrow;
      throw const GuestSessionException(GuestSessionFailure.protectedStorage);
    }
  }

  @override
  Future<void> write(GuestSessionCredential value) async {
    try {
      await _storage.write(key: _storageKey, value: jsonEncode(value.toJson()));
    } catch (_) {
      throw const GuestSessionException(GuestSessionFailure.protectedStorage);
    }
  }

  @override
  Future<GuestIssuanceRequest?> readIssuanceRequest() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      final issuance = _storedIssuanceRequest(decoded);
      if (issuance != null) return issuance;
      GuestSessionCredential.fromJson(decoded);
      return null;
    } catch (_) {
      throw const GuestSessionException(GuestSessionFailure.protectedStorage);
    }
  }

  @override
  Future<void> writeIssuanceRequest(GuestIssuanceRequest value) async {
    final issuance = GuestIssuanceRequest(
      requestId: _uuid(value.requestId).toLowerCase(),
      replaySecret: _replaySecret(value.replaySecret),
    );
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        final existing = _storedIssuanceRequest(decoded);
        if (existing?.requestId == issuance.requestId &&
            existing?.replaySecret == issuance.replaySecret) {
          return;
        }
        if (existing != null) {
          throw const GuestSessionException(
            GuestSessionFailure.protectedStorage,
          );
        }
        GuestSessionCredential.fromJson(decoded);
        throw const GuestSessionException(GuestSessionFailure.protectedStorage);
      }
      await _storage.write(
        key: _storageKey,
        value: jsonEncode(issuance.toJson()),
      );
    } on GuestSessionException {
      rethrow;
    } catch (_) {
      throw const GuestSessionException(GuestSessionFailure.protectedStorage);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {
      throw const GuestSessionException(GuestSessionFailure.protectedStorage);
    }
  }
}

sealed class PaperAuthorization {
  const PaperAuthorization();
  String get headerValue;
}

final class PrivyPaperAuthorization extends PaperAuthorization {
  const PrivyPaperAuthorization(this.token);
  final String token;
  @override
  String get headerValue => 'Bearer $token';
}

final class GuestPaperAuthorization extends PaperAuthorization {
  const GuestPaperAuthorization(this.token);
  final String token;
  @override
  String get headerValue => 'Guest $token';
}

abstract interface class GuestDeskClaimPort {
  Future<void> claimGuestDesk(String verifiedBearer);
}

abstract interface class GuestSessionPort implements GuestDeskClaimPort {
  /// Stable opaque key for paper state. This never exposes the credential.
  Future<String> guestId();
  Future<PaperAuthorization> paperAuthorization();
}

/// Destructive guest recovery kept separate from ordinary authorization.
///
/// Product UI must expose this only after an expired credential has been
/// observed and the player has explicitly chosen to leave that desk behind.
/// Reading or retrying an expired desk never clears it.
abstract interface class GuestSessionRecoveryPort {
  Future<void> startNewGuestDesk({GuestSessionFailure? observedFailure});
}

/// Restores guest access after a successfully claimed desk is signed out.
///
/// Claim already moved the old desk to the verified account and removed its
/// device credential. This transition only releases the in-memory claim guard;
/// it never deletes a preserved guest credential.
abstract interface class GuestSessionAccountLifecyclePort {
  void resumeGuestAccessAfterSignOut();
}

final class HttpGuestSessionClient {
  HttpGuestSessionClient({
    required this.client,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
    String Function()? newId,
  }) : _baseUri = _origin(baseUri, allowLoopbackForTests),
       _timeout = timeout,
       _newId = newId ?? _uuidV4 {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw const GuestSessionException(GuestSessionFailure.unavailable);
    }
  }

  final http.Client client;
  final Uri _baseUri;
  final Duration _timeout;
  final String Function() _newId;

  Future<GuestSessionCredential> create(GuestIssuanceRequest issuance) async {
    final requestId = _uuid(issuance.requestId).toLowerCase();
    final replaySecret = _replaySecret(issuance.replaySecret);
    final response = await _request(
      'POST',
      _sessionPath,
      body: {
        'schemaVersion': 1,
        'requestId': requestId,
        'replaySecret': replaySecret,
      },
    );
    final value = _object(response);
    _keys(value, const {
      'schemaVersion',
      'requestId',
      'guestId',
      'token',
      'expiresAt',
      'hardExpiresAt',
    });
    if (value['schemaVersion'] != 1 ||
        _uuid(value['requestId']).toLowerCase() != requestId) {
      _rejected();
    }
    return GuestSessionCredential(
      guestId: _uuid(value['guestId']),
      token: _guestToken(value['token']),
      expiresAt: _utc(value['expiresAt']),
      hardExpiresAt: _utc(value['hardExpiresAt']),
      claimIdempotencyKey: _uuid(_newId()),
    );
  }

  Future<GuestSessionCredential> refresh(GuestSessionCredential current) async {
    final response = await _request(
      'POST',
      _refreshPath,
      authorization: GuestPaperAuthorization(current.token),
      body: const {'schemaVersion': 1},
    );
    final value = _object(response);
    _keys(value, const {
      'schemaVersion',
      'guestId',
      'expiresAt',
      'hardExpiresAt',
    });
    final guestId = _uuid(value['guestId']);
    final expiresAt = _utc(value['expiresAt']);
    final hardExpiresAt = _utc(value['hardExpiresAt']);
    if (value['schemaVersion'] != 1 ||
        guestId != current.guestId ||
        hardExpiresAt != current.hardExpiresAt ||
        expiresAt.isBefore(current.expiresAt)) {
      _rejected();
    }
    return current.withExpiry(
      expiresAt: expiresAt,
      hardExpiresAt: hardExpiresAt,
    );
  }

  Future<void> claim(
    GuestSessionCredential current,
    String verifiedBearer,
  ) async {
    _bearer(verifiedBearer);
    final response = await _request(
      'POST',
      _claimPath,
      authorization: PrivyPaperAuthorization(verifiedBearer),
      guestClaim: current.token,
      body: {'schemaVersion': 1, 'idempotencyKey': current.claimIdempotencyKey},
    );
    final value = _object(response);
    _keys(value, const {'schemaVersion', 'status', 'guestId', 'claimedAt'});
    if (value['schemaVersion'] != 1 ||
        value['status'] != 'claimed' ||
        _uuid(value['guestId']) != current.guestId) {
      _rejected();
    }
    _utc(value['claimedAt']);
  }

  Future<Object?> _request(
    String method,
    String path, {
    required Map<String, Object?> body,
    PaperAuthorization? authorization,
    String? guestClaim,
  }) async {
    final bytes = utf8.encode(jsonEncode(body));
    if (bytes.length > 1024) _rejected();
    final request = http.Request(method, _baseUri.replace(path: path))
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers['accept'] = 'application/json'
      ..headers['content-type'] = 'application/json'
      ..bodyBytes = bytes;
    if (authorization != null) {
      request.headers['authorization'] = authorization.headerValue;
    }
    if (guestClaim != null) {
      request.headers['x-trimmy-guest'] = _guestToken(guestClaim);
    }
    try {
      final response = await client.send(request).timeout(_timeout);
      if (response.isRedirect ||
          response.statusCode >= 300 && response.statusCode < 400) {
        _rejected();
      }
      if ((response.contentLength ?? 0) > _maxResponseBytes) {
        _rejected();
      }
      _jsonContentType(response.headers['content-type']);
      final content = <int>[];
      await for (final chunk in response.stream.timeout(_timeout)) {
        if (content.length + chunk.length > _maxResponseBytes) _rejected();
        content.addAll(chunk);
      }
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(content, allowMalformed: false));
      } catch (_) {
        _rejected();
      }
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw GuestSessionException(_failure(response.statusCode, decoded));
      }
      return decoded;
    } on TimeoutException {
      throw const GuestSessionException(GuestSessionFailure.timeout);
    } on GuestSessionException {
      rethrow;
    } catch (_) {
      throw const GuestSessionException(GuestSessionFailure.offline);
    }
  }
}

/// Serializes create/refresh/claim so two UI events cannot fork one guest desk.
final class GuestSessionController
    implements
        GuestSessionPort,
        GuestSessionRecoveryPort,
        GuestSessionAccountLifecyclePort {
  GuestSessionController({
    required this.store,
    required this.client,
    DateTime Function()? now,
    String Function()? newIssuanceRequestId,
    String Function()? newIssuanceReplaySecret,
  }) : _now = now ?? DateTime.now,
       _newIssuanceRequestId = newIssuanceRequestId ?? _uuidV4,
       _newIssuanceReplaySecret = newIssuanceReplaySecret ?? _newReplaySecret;

  final GuestCredentialStore store;
  final HttpGuestSessionClient client;
  final DateTime Function() _now;
  final String Function() _newIssuanceRequestId;
  final String Function() _newIssuanceReplaySecret;
  GuestSessionCredential? _cached;
  Future<GuestSessionCredential>? _opening;
  Future<void>? _claiming;
  Future<void>? _restarting;
  bool _claimed = false;

  @override
  Future<String> guestId() async => (await ensureActive()).guestId;

  @override
  Future<PaperAuthorization> paperAuthorization() async =>
      GuestPaperAuthorization((await ensureActive()).token);

  Future<GuestSessionCredential> ensureActive() {
    final active = _opening;
    if (active != null) return active;
    late final Future<GuestSessionCredential> operation;
    operation = _ensureActive().whenComplete(() {
      if (identical(_opening, operation)) _opening = null;
    });
    _opening = operation;
    return operation;
  }

  Future<GuestSessionCredential> _ensureActive() async {
    final claim = _claiming;
    if (claim != null) await claim;
    if (_claimed) {
      throw const GuestSessionException(GuestSessionFailure.revoked);
    }
    var current = _cached ?? await store.read();
    final now = _now().toUtc();
    if (current == null) {
      var issuance = await store.readIssuanceRequest();
      if (issuance == null) {
        issuance = GuestIssuanceRequest(
          requestId: _uuid(_newIssuanceRequestId()).toLowerCase(),
          replaySecret: _replaySecret(_newIssuanceReplaySecret()),
        );
        await store.writeIssuanceRequest(issuance);
      }
      current = await client.create(issuance);
      // One secure-store write replaces the pending proof with the credential.
      // A crash before it leaves the proof retryable; a crash after it restores
      // the credential, so there is no destructive cleanup gap.
      await store.write(current);
      _cached = current;
      return current;
    }
    _cached = current;
    if (!now.isBefore(current.expiresAt) ||
        !now.isBefore(current.hardExpiresAt)) {
      throw const GuestSessionException(GuestSessionFailure.expired);
    }
    if (current.expiresAt.difference(now) <= const Duration(days: 7)) {
      current = await client.refresh(current);
      await store.write(current);
      _cached = current;
    }
    return current;
  }

  @override
  Future<void> startNewGuestDesk({GuestSessionFailure? observedFailure}) {
    final active = _restarting;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _startNewGuestDesk(observedFailure: observedFailure)
        .whenComplete(() {
          if (identical(_restarting, operation)) _restarting = null;
        });
    _restarting = operation;
    return operation;
  }

  Future<void> _startNewGuestDesk({
    GuestSessionFailure? observedFailure,
  }) async {
    final claim = _claiming;
    if (claim != null) await claim;
    if (_claimed) {
      if (observedFailure != GuestSessionFailure.revoked) {
        throw const GuestSessionException(GuestSessionFailure.revoked);
      }
      _claimed = false;
      await ensureActive();
      return;
    }

    // A previous explicit restart may have cleared the expired credential and
    // then lost the create response. Resume its durable issuance proof instead
    // of clearing it or minting another guest.
    final current = _cached ?? await store.read();
    if (current == null) {
      if (await store.readIssuanceRequest() == null) {
        throw const GuestSessionException(GuestSessionFailure.rejected);
      }
      await ensureActive();
      return;
    }

    final now = _now().toUtc();
    final observedTerminal =
        observedFailure == GuestSessionFailure.expired ||
        observedFailure == GuestSessionFailure.revoked;
    if (!observedTerminal &&
        now.isBefore(current.expiresAt) &&
        now.isBefore(current.hardExpiresAt)) {
      throw const GuestSessionException(GuestSessionFailure.rejected);
    }

    // This is the sole path that removes an expired desk credential. The old
    // record remains intact if secure deletion fails. Once deletion succeeds,
    // normal crash-safe creation persists its issuance proof before the call.
    await store.clear();
    if (identical(_cached, current)) _cached = null;
    await ensureActive();
  }

  @override
  void resumeGuestAccessAfterSignOut() {
    // AccountController calls this only after the claimed desk has finished
    // opening as a verified account. A failed or preserved claim leaves this
    // flag false, so its credential remains exactly where it was.
    if (_claimed) _claimed = false;
  }

  @override
  Future<void> claimGuestDesk(String verifiedBearer) {
    final active = _claiming;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _claim(verifiedBearer).whenComplete(() {
      if (identical(_claiming, operation)) _claiming = null;
    });
    _claiming = operation;
    return operation;
  }

  Future<void> _claim(String verifiedBearer) async {
    // If the first paper request is still opening or refreshing the desk, its
    // durable credential must exist before Save your desk can claim it.
    final opening = _opening;
    if (opening != null) await opening;
    final current = _cached ?? await store.read();
    if (current != null) {
      _cached = current;
      await client.claim(current, verifiedBearer);
      await store.clear();
      if (identical(_cached, current)) _cached = null;
    }
    _claimed = true;
  }
}

GuestSessionFailure _failure(int status, Object? value) {
  String? code;
  if (value case {'error': final Map<String, dynamic> error}) {
    if (error['code'] case final String candidate) code = candidate;
  }
  return switch (code) {
    'GUEST_SESSION_EXPIRED' => GuestSessionFailure.expired,
    'GUEST_SESSION_REVOKED' => GuestSessionFailure.revoked,
    'GUEST_SESSION_RATE_LIMITED' => GuestSessionFailure.rateLimited,
    'GUEST_CLAIM_ACCOUNT_EXISTS' => GuestSessionFailure.accountAlreadySaved,
    'GUEST_CLAIM_ALREADY_USED' ||
    'GUEST_CLAIM_IDEMPOTENCY_CONFLICT' => GuestSessionFailure.alreadyClaimed,
    'GUEST_SESSION_UNAVAILABLE' => GuestSessionFailure.unavailable,
    _ =>
      status >= 500
          ? GuestSessionFailure.unavailable
          : GuestSessionFailure.rejected,
  };
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    _rejected();
  }
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    _rejected();
  }
}

GuestIssuanceRequest? _storedIssuanceRequest(Object? value) {
  if (value is! Map<String, dynamic> ||
      !value.containsKey('requestId') && !value.containsKey('replaySecret')) {
    return null;
  }
  if (value.length != 3 ||
      value['schemaVersion'] != 1 ||
      !value.containsKey('requestId') ||
      !value.containsKey('replaySecret')) {
    throw const GuestSessionException(GuestSessionFailure.protectedStorage);
  }
  try {
    return GuestIssuanceRequest(
      requestId: _uuid(value['requestId']).toLowerCase(),
      replaySecret: _replaySecret(value['replaySecret']),
    );
  } catch (_) {
    throw const GuestSessionException(GuestSessionFailure.protectedStorage);
  }
}

String _uuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    _rejected();
  }
  return value;
}

String _guestToken(Object? value) {
  if (value is! String || !RegExp(r'^tg1_[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    _rejected();
  }
  return value;
}

String _replaySecret(Object? value) {
  if (value is! String || !RegExp(r'^gr1_[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    _rejected();
  }
  try {
    final encoded = value.substring(4);
    final bytes = base64Url.decode('$encoded=');
    if (bytes.length != 32 ||
        base64UrlEncode(bytes).replaceAll('=', '') != encoded) {
      _rejected();
    }
  } catch (_) {
    _rejected();
  }
  return value;
}

DateTime _utc(Object? value) {
  if (value is! String) {
    _rejected();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    _rejected();
  }
  return parsed;
}

void _bearer(String value) {
  final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(value);
  if (value.isEmpty ||
      value.length > 8192 ||
      match?.start != 0 ||
      match?.end != value.length) {
    _rejected();
  }
}

void _jsonContentType(String? value) {
  final parts = value?.toLowerCase().split(';').map((part) => part.trim());
  if (parts == null ||
      parts.first != 'application/json' ||
      parts
          .skip(1)
          .any(
            (part) => part != 'charset=utf-8' && part != 'charset="utf-8"',
          )) {
    _rejected();
  }
}

Uri _origin(Uri value, bool allowLoopback) {
  try {
    final loopback = const {
      'localhost',
      '127.0.0.1',
      '::1',
      '[::1]',
    }.contains(value.host.toLowerCase());
    if (!value.hasAuthority ||
        value.host.isEmpty ||
        value.host.endsWith('.') ||
        value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        value.path.isNotEmpty && value.path != '/' ||
        value.port < 1 ||
        value.port > 65535 ||
        value.scheme != 'https' &&
            !(allowLoopback && loopback && value.scheme == 'http')) {
      _rejected();
    }
    return value.replace(path: '');
  } catch (_) {
    throw const GuestSessionException(GuestSessionFailure.unavailable);
  }
}

Never _rejected() =>
    throw const GuestSessionException(GuestSessionFailure.rejected);

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _newReplaySecret() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return 'gr1_${base64UrlEncode(bytes).replaceAll('=', '')}';
}
