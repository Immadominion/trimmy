import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../account/guest_session.dart';
import '../onboarding/onboarding_models.dart';
import 'product_profile_repository.dart';

const _profilePath = '/v1/product/profile';
const _launchPath = '/v1/product/launch';
const _maximumResponseBytes = 16384;

typedef ProductProfileAuthorizationProvider =
    Future<PaperAuthorization> Function();

final class HttpProductProfileRepository implements ProductProfileRepository {
  HttpProductProfileRepository({
    required http.Client transport,
    required Uri baseUri,
    required ProductProfileAuthorizationProvider authorizationProvider,
    this.onGuestSessionFailure,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) : _client = transport,
       _baseUri = _origin(baseUri, allowLoopbackForTests),
       _authorization = authorizationProvider,
       _timeout = timeout {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw const ProductProfileException(ProductProfileFailure.unavailable);
    }
  }

  final http.Client _client;
  final Uri _baseUri;
  final ProductProfileAuthorizationProvider _authorization;
  final void Function(GuestSessionFailure)? onGuestSessionFailure;
  final Duration _timeout;
  bool _closed = false;

  @override
  Future<ProductProfileSnapshot?> read() async {
    final response = await _request('GET');
    if (response.statusCode != 200) {
      _throwFailure(response.statusCode, response.body);
    }
    final envelope = _object(response.body);
    _keys(envelope, const {'schemaVersion', 'profile'});
    if (envelope['schemaVersion'] != 1 && envelope['schemaVersion'] != 2) {
      _rejected();
    }
    final profile = envelope['profile'];
    return profile == null
        ? null
        : _profile(profile, requireEvidence: envelope['schemaVersion'] == 2);
  }

  @override
  Future<ProductProfileSnapshot> write({
    required String mutationId,
    required int baseRevision,
    required OnboardingProfile onboarding,
    required ProductProfileCheckpoint launchCheckpoint,
  }) async {
    if (!_uuid(mutationId) ||
        baseRevision < 0 ||
        baseRevision > 9007199254740991) {
      throw const ProductProfileException(ProductProfileFailure.rejected);
    }
    final response = await _request(
      'PUT',
      body: jsonEncode({
        'schemaVersion': 2,
        'mutationId': mutationId.toLowerCase(),
        'baseRevision': baseRevision,
        'onboarding': {
          'goal': onboarding.goal?.id,
          'knowledge': onboarding.knowledge?.id,
          'persona': onboarding.persona?.id,
          'dailyGoal': onboarding.dailyGoal?.id,
          'handle': onboarding.handle,
        },
        'launchCheckpoint': launchCheckpoint.wire,
      }),
    );
    if (response.statusCode != 200) {
      _throwFailure(response.statusCode, response.body);
    }
    final envelope = _object(response.body);
    _keys(envelope, const {'schemaVersion', 'profile'});
    if ((envelope['schemaVersion'] != 1 && envelope['schemaVersion'] != 2) ||
        envelope['profile'] == null) {
      _rejected();
    }
    return _profile(
      envelope['profile'],
      requireEvidence: envelope['schemaVersion'] == 2,
    );
  }

  @override
  Future<ProductProfileSnapshot> advance({
    required String mutationId,
    required int baseRevision,
    required ProductLaunchAction action,
  }) async {
    if (!_uuid(mutationId) ||
        baseRevision < 1 ||
        baseRevision > 9007199254740990) {
      throw const ProductProfileException(ProductProfileFailure.rejected);
    }
    final response = await _request(
      'POST',
      path: _launchPath,
      body: jsonEncode({
        'schemaVersion': 2,
        'mutationId': mutationId.toLowerCase(),
        'baseRevision': baseRevision,
        'action': action.wire,
      }),
    );
    if (response.statusCode != 200) {
      _throwFailure(response.statusCode, response.body);
    }
    final envelope = _object(response.body);
    _keys(envelope, const {'schemaVersion', 'profile'});
    if ((envelope['schemaVersion'] != 1 && envelope['schemaVersion'] != 2) ||
        envelope['profile'] == null) {
      _rejected();
    }
    return _profile(
      envelope['profile'],
      requireEvidence: envelope['schemaVersion'] == 2,
    );
  }

  Future<_Response> _request(
    String method, {
    String path = _profilePath,
    String? body,
  }) async {
    if (_closed) {
      throw const ProductProfileException(ProductProfileFailure.unavailable);
    }
    var timedOut = false;
    final abort = Completer<void>();
    StreamIterator<List<int>>? iterator;

    Future<_Response> perform() async {
      PaperAuthorization authorization;
      try {
        authorization = await _authorization();
      } on GuestSessionException catch (error) {
        if (_terminalGuestFailure(error.failure)) {
          onGuestSessionFailure?.call(error.failure);
          rethrow;
        }
        throw const ProductProfileException(
          ProductProfileFailure.unauthenticated,
        );
      } catch (_) {
        throw const ProductProfileException(
          ProductProfileFailure.unauthenticated,
        );
      }
      if (_closed || timedOut) {
        throw const ProductProfileException(ProductProfileFailure.timeout);
      }
      final request =
          http.AbortableRequest(
              method,
              _baseUri.replace(path: path),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['accept'] =
                'application/vnd.trimmy.product-profile.v2+json'
            ..headers['authorization'] = _authorizationHeader(authorization);
      if (body != null) {
        request
          ..headers['content-type'] = 'application/json; charset=utf-8'
          ..body = body;
      }
      try {
        final response = await _client.send(request);
        if (_closed || timedOut) {
          await response.stream.listen(null).cancel();
          throw const ProductProfileException(ProductProfileFailure.timeout);
        }
        if (response.isRedirect ||
            response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.listen(null).cancel();
          throw const ProductProfileException(ProductProfileFailure.rejected);
        }
        if ((response.contentLength ?? 0) > _maximumResponseBytes) {
          await response.stream.listen(null).cancel();
          throw const ProductProfileException(ProductProfileFailure.rejected);
        }
        _jsonContentType(response.headers['content-type']);
        final bytes = <int>[];
        iterator = StreamIterator(response.stream);
        while (await iterator!.moveNext()) {
          if (_closed || timedOut) {
            throw const ProductProfileException(ProductProfileFailure.timeout);
          }
          final chunk = iterator!.current;
          if (bytes.length + chunk.length > _maximumResponseBytes) {
            throw const ProductProfileException(ProductProfileFailure.rejected);
          }
          bytes.addAll(chunk);
        }
        iterator = null;
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        } catch (_) {
          throw const ProductProfileException(ProductProfileFailure.rejected);
        }
        return _Response(response.statusCode, decoded);
      } on GuestSessionException {
        rethrow;
      } on ProductProfileException {
        rethrow;
      } catch (_) {
        if (timedOut) {
          throw const ProductProfileException(ProductProfileFailure.timeout);
        }
        throw const ProductProfileException(ProductProfileFailure.offline);
      }
    }

    try {
      return await perform().timeout(
        _timeout,
        onTimeout: () {
          timedOut = true;
          if (!abort.isCompleted) abort.complete();
          final current = iterator;
          if (current != null) {
            unawaited(current.cancel().catchError((Object _) {}));
          }
          throw const ProductProfileException(ProductProfileFailure.timeout);
        },
      );
    } finally {
      final current = iterator;
      if (current != null) {
        await current.cancel().catchError((Object _) {});
      }
    }
  }

  Never _throwFailure(int status, Object? input) {
    final error = _failure(status, input);
    if (error is GuestSessionException) {
      onGuestSessionFailure?.call(error.failure);
    }
    throw error;
  }

  void close() => _closed = true;
}

final class _Response {
  const _Response(this.statusCode, this.body);
  final int statusCode;
  final Object? body;
}

ProductProfileSnapshot _profile(Object? input, {bool requireEvidence = false}) {
  final value = _object(input);
  final hasEvidence = value.containsKey('hasConfirmedPaperTrade');
  if ((requireEvidence && !hasEvidence) ||
      (hasEvidence && value['hasConfirmedPaperTrade'] is! bool)) {
    _rejected();
  }
  _keys(value, {
    if (hasEvidence) 'hasConfirmedPaperTrade',
    'revision',
    'onboarding',
    'launchCheckpoint',
    'createdAt',
    'updatedAt',
  });
  final revision = value['revision'];
  if (revision is! int || revision < 1 || revision > 9007199254740991) {
    _rejected();
  }
  final onboarding = _onboarding(
    value['onboarding'],
    allowPartial: hasEvidence,
  );
  final checkpoint = _enum(
    ProductProfileCheckpoint.values,
    value['launchCheckpoint'],
    (item) => item.wire,
  );
  final createdAt = _utc(value['createdAt']);
  final updatedAt = _utc(value['updatedAt']);
  if (updatedAt.isBefore(createdAt)) _rejected();
  return ProductProfileSnapshot(
    revision: revision,
    onboarding: onboarding,
    launchCheckpoint: checkpoint,
    createdAt: createdAt,
    updatedAt: updatedAt,
    hasConfirmedPaperTrade: value['hasConfirmedPaperTrade'] as bool?,
  );
}

OnboardingProfile _onboarding(Object? input, {required bool allowPartial}) {
  final value = _object(input);
  _keys(value, const {'goal', 'knowledge', 'persona', 'dailyGoal', 'handle'});
  if (!allowPartial && value.values.any((field) => field == null)) _rejected();
  final handle = value['handle'];
  if (handle != null &&
      (handle is! String ||
          !RegExp(r'^[a-z][a-z0-9_]{2,17}$').hasMatch(handle))) {
    _rejected();
  }
  return OnboardingProfile(
    goal: _optionalEnum(
      OnboardingGoal.values,
      value['goal'],
      (item) => item.id,
    ),
    knowledge: _optionalEnum(
      TradingKnowledge.values,
      value['knowledge'],
      (item) => item.id,
    ),
    persona: _optionalEnum(
      TraderPersona.values,
      value['persona'],
      (item) => item.id,
    ),
    dailyGoal: _optionalEnum(
      OnboardingDailyGoal.values,
      value['dailyGoal'],
      (item) => item.id,
    ),
    handle: handle as String?,
  );
}

Exception _failure(int status, Object? input) {
  String? code;
  ProductProfileSnapshot? current;
  if (input case {'error': final Map<String, dynamic> error}) {
    if (error['code'] case final String value) code = value;
    if (error['currentProfile'] != null) {
      try {
        current = _profile(error['currentProfile']);
      } catch (_) {
        current = null;
      }
    }
  }
  if (code == 'GUEST_SESSION_EXPIRED') {
    return const GuestSessionException(GuestSessionFailure.expired);
  }
  if (code == 'GUEST_SESSION_REVOKED') {
    return const GuestSessionException(GuestSessionFailure.revoked);
  }
  final failure = switch (code) {
    'PRODUCT_PROFILE_HANDLE_TAKEN' => ProductProfileFailure.handleTaken,
    'PRODUCT_PROFILE_PAPER_TRADE_REQUIRED' =>
      ProductProfileFailure.tradeRequired,
    'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED' =>
      ProductProfileFailure.notReady,
    'PRODUCT_PROFILE_PRINCIPAL_CONFLICT' =>
      ProductProfileFailure.principalChanged,
    'PRODUCT_PROFILE_REVISION_CONFLICT' ||
    'PRODUCT_PROFILE_CHECKPOINT_CONFLICT' ||
    'PRODUCT_PROFILE_IDEMPOTENCY_CONFLICT' ||
    'PRODUCT_PROFILE_MISSING' => ProductProfileFailure.conflict,
    'PRODUCT_PROFILE_UNAUTHENTICATED' => ProductProfileFailure.unauthenticated,
    'PRODUCT_PROFILE_UNAVAILABLE' ||
    'GUEST_SESSION_RATE_LIMITED' => ProductProfileFailure.unavailable,
    _ when status == 401 || status == 403 =>
      ProductProfileFailure.unauthenticated,
    _ when status == 408 || status == 504 => ProductProfileFailure.timeout,
    _ when status >= 500 => ProductProfileFailure.unavailable,
    _ => ProductProfileFailure.rejected,
  };
  return ProductProfileException(failure, currentProfile: current);
}

T? _optionalEnum<T>(Iterable<T> values, Object? wire, String Function(T) id) =>
    wire == null ? null : _enum<T>(values, wire, id);

T _enum<T>(Iterable<T> values, Object? wire, String Function(T) id) {
  if (wire is! String) _rejected();
  for (final value in values) {
    if (id(value) == wire) return value;
  }
  _rejected();
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) _rejected();
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    _rejected();
  }
}

Never _rejected() =>
    throw const ProductProfileException(ProductProfileFailure.rejected);

bool _terminalGuestFailure(GuestSessionFailure failure) =>
    failure == GuestSessionFailure.expired ||
    failure == GuestSessionFailure.revoked;

DateTime _utc(Object? input) {
  if (input is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
      ).hasMatch(input)) {
    _rejected();
  }
  final parsed = DateTime.tryParse(input);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != input) {
    _rejected();
  }
  return parsed;
}

bool _uuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

String _authorizationHeader(PaperAuthorization value) {
  final header = value.headerValue;
  if (header.length > 4096 ||
      !(header.startsWith('Bearer ') || header.startsWith('Guest '))) {
    throw const ProductProfileException(ProductProfileFailure.unauthenticated);
  }
  final credential = header.substring(header.indexOf(' ') + 1);
  if (credential.isEmpty || RegExp(r'[\x00-\x20\x7f]').hasMatch(credential)) {
    throw const ProductProfileException(ProductProfileFailure.unauthenticated);
  }
  return header;
}

void _jsonContentType(String? value) {
  final mediaType = value?.split(';').first.trim().toLowerCase();
  if (mediaType != 'application/json' &&
      mediaType != 'application/vnd.trimmy.product-profile.v2+json') {
    _rejected();
  }
}

Uri _origin(Uri uri, bool allowLoopbackForTests) {
  final loopback =
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1');
  if (!uri.hasScheme ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.path != '' && uri.path != '/' ||
      uri.scheme != 'https' && !(allowLoopbackForTests && loopback)) {
    throw const ProductProfileException(ProductProfileFailure.unavailable);
  }
  return uri.replace(path: '');
}
