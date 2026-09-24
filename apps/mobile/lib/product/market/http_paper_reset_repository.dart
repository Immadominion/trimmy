import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../account/guest_session.dart';
import 'paper_reset.dart';

const _resetPath = '/v1/account/paper/reset';
const _maximumResponseBytes = 32768;

typedef PaperResetAuthorizationProvider = Future<PaperAuthorization> Function();

/// Executes only an idempotent, explicitly confirmed paper reset request.
/// It retains no credential and follows no redirect.
final class HttpPaperResetRepository implements PaperResetRepository {
  HttpPaperResetRepository({
    required http.Client transport,
    required Uri baseUri,
    required PaperResetAuthorizationProvider authorizationProvider,
    this.onGuestSessionFailure,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) : _client = transport,
       _baseUri = _origin(baseUri, allowLoopbackForTests),
       _authorization = authorizationProvider,
       _timeout = timeout {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw const PaperResetException(PaperResetFailure.unavailable);
    }
  }

  final http.Client _client;
  final Uri _baseUri;
  final PaperResetAuthorizationProvider _authorization;
  final void Function(GuestSessionFailure)? onGuestSessionFailure;
  final Duration _timeout;
  bool _closed = false;

  @override
  Future<PaperResetResult> reset(PaperResetRequest input) async {
    if (_closed) {
      throw const PaperResetException(PaperResetFailure.unavailable);
    }
    var timedOut = false;
    final abort = Completer<void>();
    StreamIterator<List<int>>? iterator;

    Future<PaperResetResult> perform() async {
      PaperAuthorization authorization;
      try {
        authorization = await _authorization();
      } on GuestSessionException catch (error) {
        if (_terminal(error.failure)) {
          onGuestSessionFailure?.call(error.failure);
          rethrow;
        }
        throw const PaperResetException(PaperResetFailure.accountRequired);
      } catch (_) {
        throw const PaperResetException(PaperResetFailure.accountRequired);
      }
      if (timedOut || _closed) {
        throw const PaperResetException(PaperResetFailure.timeout);
      }

      final encoded = utf8.encode(jsonEncode(input.toJson()));
      final request =
          http.AbortableRequest(
              'POST',
              _baseUri.replace(path: _resetPath),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['accept'] = 'application/json'
            ..headers['content-type'] = 'application/json'
            ..headers['authorization'] = _authorizationHeader(authorization)
            ..bodyBytes = encoded;
      try {
        final response = await _client.send(request);
        if (timedOut || _closed) {
          await response.stream.listen(null).cancel();
          throw const PaperResetException(PaperResetFailure.timeout);
        }
        if (response.isRedirect ||
            response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.listen(null).cancel();
          throw const PaperResetException(PaperResetFailure.unavailable);
        }
        if ((response.contentLength ?? 0) > _maximumResponseBytes) {
          await response.stream.listen(null).cancel();
          throw const PaperResetException(PaperResetFailure.unavailable);
        }
        _jsonContentType(response.headers['content-type']);
        final bytes = <int>[];
        iterator = StreamIterator(response.stream);
        while (await iterator!.moveNext()) {
          if (timedOut || _closed) {
            throw const PaperResetException(PaperResetFailure.timeout);
          }
          final chunk = iterator!.current;
          if (bytes.length + chunk.length > _maximumResponseBytes) {
            throw const PaperResetException(PaperResetFailure.unavailable);
          }
          bytes.addAll(chunk);
        }
        iterator = null;
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        } catch (_) {
          throw const PaperResetException(PaperResetFailure.unavailable);
        }
        if (response.statusCode != 200) {
          final guestFailure = _terminalGuestFailure(
            response.statusCode,
            decoded,
          );
          if (guestFailure != null) {
            onGuestSessionFailure?.call(guestFailure);
            throw GuestSessionException(guestFailure);
          }
          throw PaperResetException(_failure(response.statusCode, decoded));
        }
        try {
          return _result(decoded, input);
        } on PaperResetException {
          // A committed reset can still be followed by an invalid response.
          // Retain this UUID so the next attempt is an exact replay.
          throw const PaperResetException(PaperResetFailure.unavailable);
        }
      } on GuestSessionException {
        rethrow;
      } on PaperResetException {
        rethrow;
      } catch (_) {
        if (timedOut) {
          throw const PaperResetException(PaperResetFailure.timeout);
        }
        throw const PaperResetException(PaperResetFailure.offline);
      }
    }

    try {
      return await perform().timeout(
        _timeout,
        onTimeout: () {
          timedOut = true;
          if (!abort.isCompleted) abort.complete();
          final currentIterator = iterator;
          if (currentIterator != null) {
            unawaited(currentIterator.cancel().catchError((Object _) {}));
          }
          throw const PaperResetException(PaperResetFailure.timeout);
        },
      );
    } finally {
      final currentIterator = iterator;
      if (currentIterator != null) {
        await currentIterator.cancel().catchError((Object _) {});
      }
    }
  }

  void close() => _closed = true;
}

PaperResetResult _result(Object? input, PaperResetRequest request) {
  final value = _object(input, const {
    'schemaVersion',
    'mode',
    'unit',
    'reset',
    'portfolioAtReset',
  });
  if (value['schemaVersion'] != 1 || value['mode'] != 'paper') _reject();
  final unit = _object(value['unit'], const {'kind', 'scaleDigits'});
  if (unit['kind'] != 'paper' || unit['scaleDigits'] != 6) _reject();

  final reset = _object(value['reset'], const {
    'mutationId',
    'previousRevision',
    'revision',
    'resetAt',
  });
  final receipt = PaperResetReceipt(
    mutationId: _uuid(reset['mutationId']),
    previousRevision: _revision(reset['previousRevision']),
    revision: _revision(reset['revision']),
    resetAt: _utc(reset['resetAt']),
  );

  final portfolio = _object(value['portfolioAtReset'], const {
    'revision',
    'startingCashPaperMicros',
    'cashPaperMicros',
    'positions',
    'recentOrders',
  });
  if (_emptyList(portfolio['positions']).isNotEmpty ||
      _emptyList(portfolio['recentOrders']).isNotEmpty) {
    _reject();
  }
  return PaperResetResult(
    request: request,
    receipt: receipt,
    portfolio: PaperResetPortfolio(
      revision: _revision(portfolio['revision']),
      startingCashPaper: _fromMicros(
        _micros(portfolio['startingCashPaperMicros']),
      ),
      cashPaper: _fromMicros(_micros(portfolio['cashPaperMicros'])),
    ),
  );
}

PaperResetFailure _failure(int status, Object? value) {
  final code = _problemCode(value);
  if (code == null) return PaperResetFailure.unavailable;
  return switch ((status, code)) {
    (409, 'PAPER_PORTFOLIO_CHANGED') => PaperResetFailure.staleRevision,
    (409, 'PAPER_RESET_NOT_NEEDED') => PaperResetFailure.notNeeded,
    (409, 'PAPER_IDEMPOTENCY_CONFLICT') => PaperResetFailure.conflict,
    (409, 'PAPER_REVISION_EXHAUSTED') => PaperResetFailure.revisionExhausted,
    (401, 'PAPER_TRADING_UNAUTHENTICATED') => PaperResetFailure.accountRequired,
    (403, 'PAPER_ACCOUNT_UNAVAILABLE') => PaperResetFailure.accountRequired,
    (404, 'PAPER_ACCOUNT_NOT_FOUND') => PaperResetFailure.accountRequired,
    (429, 'GUEST_SESSION_RATE_LIMITED') => PaperResetFailure.rateLimited,
    (503, 'PAPER_RESET_UNAVAILABLE') => PaperResetFailure.unavailable,
    (400, 'PAPER_INPUT_INVALID') => PaperResetFailure.rejected,
    _ =>
      status == 429
          ? PaperResetFailure.rateLimited
          : PaperResetFailure.unavailable,
  };
}

GuestSessionFailure? _terminalGuestFailure(int status, Object? value) {
  if (status != 401 && status != 403) return null;
  final code = _problemCode(value);
  return switch (code) {
    'GUEST_SESSION_EXPIRED' => GuestSessionFailure.expired,
    'GUEST_SESSION_REVOKED' => GuestSessionFailure.revoked,
    _ => null,
  };
}

String? _problemCode(Object? value) {
  if (value is! Map<String, dynamic> ||
      value.length != 1 ||
      !value.containsKey('error')) {
    return null;
  }
  final error = value['error'];
  if (error is! Map<String, dynamic> ||
      error.length != 3 ||
      !error.keys.toSet().containsAll(const {'code', 'message', 'requestId'})) {
    return null;
  }
  final code = error['code'];
  final message = error['message'];
  final requestId = error['requestId'];
  if (code is! String ||
      !RegExp(r'^[A-Z][A-Z0-9_]{2,99}$').hasMatch(code) ||
      !_problemText(message, 500) ||
      !_problemText(requestId, 128)) {
    return null;
  }
  return code;
}

bool _problemText(Object? value, int maximum) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= maximum &&
    value.trim() == value &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

bool _terminal(GuestSessionFailure failure) =>
    failure == GuestSessionFailure.expired ||
    failure == GuestSessionFailure.revoked;

String _authorizationHeader(PaperAuthorization value) => switch (value) {
  PrivyPaperAuthorization(:final token) => 'Bearer ${_bearer(token)}',
  GuestPaperAuthorization(:final token) => 'Guest ${_guest(token)}',
};

Map<String, dynamic> _object(Object? input, Set<String> keys) {
  if (input is! Map<String, dynamic> ||
      input.length != keys.length ||
      !input.keys.toSet().containsAll(keys)) {
    _reject();
  }
  return input;
}

List<Object?> _emptyList(Object? input) {
  if (input is! List<Object?>) _reject();
  return input;
}

String _text(Object? input, int maximum) {
  if (input is! String ||
      input.isEmpty ||
      input.length > maximum ||
      input.trim() != input ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(input)) {
    _reject();
  }
  return input;
}

String _uuid(Object? input) {
  final value = _text(input, 36).toLowerCase();
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value)) {
    _reject();
  }
  return value;
}

int _revision(Object? input) {
  if (input is! int || input < 0 || input > 9007199254740991) _reject();
  return input;
}

BigInt _micros(Object? input) {
  final value = _text(input, 15);
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,14})$').hasMatch(value)) _reject();
  return BigInt.parse(value);
}

String _fromMicros(BigInt value) {
  final whole = value ~/ BigInt.from(1000000);
  final fraction = (value % BigInt.from(1000000))
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

DateTime _utc(Object? input) {
  final value = _text(input, 24);
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  ).hasMatch(value)) {
    _reject();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    _reject();
  }
  return parsed;
}

String _bearer(String value) {
  final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(value);
  if (value.isEmpty ||
      value.length > 8192 ||
      match?.start != 0 ||
      match?.end != value.length) {
    throw const PaperResetException(PaperResetFailure.accountRequired);
  }
  return value;
}

String _guest(String value) {
  if (!RegExp(r'^tg1_[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    throw const PaperResetException(PaperResetFailure.accountRequired);
  }
  return value;
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
    throw const PaperResetException(PaperResetFailure.unavailable);
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
    final valid =
        value.hasAuthority &&
        value.host.isNotEmpty &&
        !value.host.endsWith('.') &&
        value.userInfo.isEmpty &&
        !value.hasFragment &&
        !value.hasQuery &&
        (value.path.isEmpty || value.path == '/') &&
        (value.scheme == 'https' || allowLoopback && loopback);
    if (!valid) _reject();
    return value.replace(path: '');
  } on PaperResetException {
    rethrow;
  } catch (_) {
    throw const PaperResetException(PaperResetFailure.unavailable);
  }
}

Never _reject() => throw const PaperResetException(PaperResetFailure.rejected);
