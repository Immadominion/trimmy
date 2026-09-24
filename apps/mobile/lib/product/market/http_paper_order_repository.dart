import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../practice_sync/http_transport.dart';
import '../../account/guest_session.dart';
import '../career/http_career_repository.dart';
import 'paper_order_repository.dart';

const _previewPath = '/v1/account/paper/orders/preview';
const _commitPath = '/v1/account/paper/orders/commit';
const _maxResponseBytes = 65536;

typedef PaperAccessTokenProvider = Future<PracticeAccessToken> Function();
typedef PaperAuthorizationProvider = Future<PaperAuthorization> Function();
typedef PaperRequestIdFactory = String Function();

/// Authenticated transport for the server-owned paper ledger.
///
/// It never stores a bearer and never turns a market read into a fill. A quote
/// is the server's accepted preview, and a receipt exists only after commit.
final class HttpPaperOrderRepository implements PaperOrderRepository {
  factory HttpPaperOrderRepository({
    required http.Client client,
    required Uri baseUri,
    PaperAccessTokenProvider? accessToken,
    PaperAuthorizationProvider? authorization,
    PaperRequestIdFactory? requestId,
    void Function(GuestSessionFailure)? onGuestSessionFailure,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) {
    if ((accessToken == null) == (authorization == null) ||
        !_validOrigin(baseUri, allowLoopbackForTests) ||
        timeout <= Duration.zero ||
        timeout > const Duration(seconds: 30)) {
      throw const PaperOrderException(PaperOrderFailure.unavailable);
    }
    final authorizationProvider =
        authorization ??
        () async => PrivyPaperAuthorization((await accessToken!()).token);
    return HttpPaperOrderRepository._(
      client,
      baseUri.replace(path: ''),
      authorizationProvider,
      requestId ?? paperUuidV4,
      onGuestSessionFailure,
      timeout,
      HttpCareerRepository(
        client: client,
        baseUri: baseUri,
        authorizationProvider: authorizationProvider,
        onGuestSessionFailure: onGuestSessionFailure,
        timeout: timeout,
        allowLoopbackForTests: allowLoopbackForTests,
      ),
    );
  }

  HttpPaperOrderRepository._(
    this._client,
    this._baseUri,
    this._authorization,
    this._requestId,
    this._onGuestSessionFailure,
    this._timeout,
    this.career,
  );

  final http.Client _client;
  final Uri _baseUri;
  final PaperAuthorizationProvider _authorization;
  final PaperRequestIdFactory _requestId;
  final void Function(GuestSessionFailure)? _onGuestSessionFailure;
  final Duration _timeout;
  final HttpCareerRepository career;
  final Map<String, PaperOrderIntent> _openQuotes = {};
  bool _closed = false;

  @override
  Future<PaperOrderQuote> quote(PaperOrderIntent intent) async {
    final amount = switch (intent.quantityUnit) {
      PaperQuantityUnit.paper => {
        'kind': 'paper_amount',
        'paperMicros': _toMicros(intent.quantity, maximumDecimals: 2),
      },
      PaperQuantityUnit.shares => {
        'kind': 'share_quantity',
        'quantityMicros': _toMicros(intent.quantity, maximumDecimals: 6),
      },
    };
    final response = await _request(_previewPath, {
      'schemaVersion': 1,
      'requestId': _requestId(),
      'action': intent.side == PaperOrderSide.buy ? 'buy' : 'sell',
      'assetId': intent.assetId,
      'variantMint': intent.variantMint,
      'amount': amount,
    });
    final envelope = _paperEnvelope(response, payload: 'preview');
    final preview = _object(envelope['preview']);
    final quoteId = _uuid(preview['id']);
    if (_text(preview['assetId']) != intent.assetId ||
        _text(preview['variantMint']) != intent.variantMint ||
        _text(preview['action']) !=
            (intent.side == PaperOrderSide.buy ? 'buy' : 'sell') ||
        _text(preview['state']) != 'open' ||
        preview['committedAt'] != null) {
      throw const PaperOrderException(PaperOrderFailure.rejected);
    }
    final debit = _fixed(preview['cashDebitPaperMicros'], allowZero: true);
    final credit = _fixed(preview['cashCreditPaperMicros'], allowZero: true);
    final total = intent.side == PaperOrderSide.buy ? debit : credit;
    final quote = PaperOrderQuote(
      quoteId: quoteId,
      intent: intent,
      unitPricePaper: _fromMicros(_fixed(preview['pricePaperMicros'])),
      estimatedShares: _fromMicros(_fixed(preview['quantityMicros'])),
      feePaper: _fromMicros(
        _fixed(_object(envelope['fees'])['paperMicros'], allowZero: true),
      ),
      totalPaper: _fromMicros(total),
      expiresAt: _utc(preview['expiresAt']),
    );
    _openQuotes[quoteId] = intent;
    return quote;
  }

  @override
  Future<PaperOrderReceipt> submit(PaperOrderSubmission submission) async {
    final intent = _openQuotes[submission.quoteId];
    if (intent == null) {
      throw const PaperOrderException(PaperOrderFailure.rejected);
    }
    final response = await _request(_commitPath, {
      'schemaVersion': 1,
      'previewId': _uuid(submission.quoteId),
      'idempotencyKey': _uuid(submission.clientOrderId),
    });
    final envelope = _paperEnvelope(response, payload: 'order');
    final order = _object(envelope['order']);
    final orderId = _uuid(order['id']);
    if (_uuid(order['previewId']) != submission.quoteId ||
        _text(order['assetId']) != intent.assetId ||
        _text(order['variantMint']) != intent.variantMint ||
        _text(order['action']) !=
            (intent.side == PaperOrderSide.buy ? 'buy' : 'sell')) {
      throw const PaperOrderException(PaperOrderFailure.rejected);
    }
    final quantity = _fixed(order['quantityMicros']);
    final price = _fixed(order['pricePaperMicros']);
    final accountRevision = order['accountRevision'];
    if (accountRevision is! int ||
        accountRevision < 1 ||
        accountRevision > 9007199254740991) {
      throw const PaperOrderException(PaperOrderFailure.rejected);
    }
    final symbol = _text(order['symbol']);
    final positionQuantity = _fixed(
      order['positionQuantityAfterMicros'],
      allowZero: true,
    );
    final positionCostBasis = _fixed(
      order['positionCostBasisAfterPaperMicros'],
      allowZero: true,
    );
    final filledPaper = intent.side == PaperOrderSide.buy
        ? _fixed(order['cashDebitPaperMicros'])
        : _fixed(order['cashCreditPaperMicros']);
    final reward = _object(envelope['reward']);
    final trims = reward['trimsAwarded'];
    // The current paper-order contract never awards Trims for the trade
    // itself. Career actions, such as a saved written reason, return their own
    // separately confirmed reward receipt. Reject a widened order response so
    // the report cannot present points that were never earned.
    if (trims is! int || trims != 0) {
      throw const PaperOrderException(PaperOrderFailure.rejected);
    }
    final receipt = PaperOrderReceipt(
      orderId: orderId,
      accountRevision: accountRevision,
      assetId: intent.assetId,
      variantMint: intent.variantMint,
      symbol: symbol,
      side: intent.side,
      filledShares: _fromMicros(quantity),
      filledPaper: _fromMicros(filledPaper),
      unitPricePaper: _fromMicros(price),
      cashAfterPaper: _fromMicros(
        _fixed(order['cashAfterPaperMicros'], allowZero: true),
      ),
      positionShares: _fromMicros(positionQuantity),
      positionCostBasisPaper: _fromMicros(positionCostBasis),
      positionValuePaper: _fromMicros(
        positionQuantity * price ~/ BigInt.from(1000000),
      ),
      trimsEarned: trims,
      confirmedAt: _utc(order['committedAt']),
    );
    _openQuotes.remove(submission.quoteId);
    return receipt;
  }

  @override
  Future<PaperReasonReceipt> saveReason(PaperOrderReason reason) =>
      career.saveTradeReason(reason);

  /// Quotes belong to one portfolio revision and cannot survive a reset.
  void invalidateOpenQuotes() => _openQuotes.clear();

  void close() {
    _closed = true;
    _openQuotes.clear();
    career.close();
  }

  Future<Object?> _request(String path, Map<String, Object?> body) async {
    if (_closed) {
      throw const PaperOrderException(PaperOrderFailure.unavailable);
    }
    var expired = false;
    final abort = Completer<void>();
    StreamIterator<List<int>>? iterator;

    Future<Object?> perform() async {
      PaperAuthorization access;
      try {
        access = await _authorization();
      } on GuestSessionException catch (error) {
        if (_isTerminalGuestFailure(error.failure)) {
          _onGuestSessionFailure?.call(error.failure);
          rethrow;
        }
        throw const PaperOrderException(PaperOrderFailure.accountRequired);
      } catch (_) {
        throw const PaperOrderException(PaperOrderFailure.accountRequired);
      }
      if (expired || _closed) {
        throw const PaperOrderException(PaperOrderFailure.timeout);
      }
      switch (access) {
        case PrivyPaperAuthorization(:final token):
          _bearer(token);
        case GuestPaperAuthorization(:final token):
          _guest(token);
      }
      final encoded = utf8.encode(jsonEncode(body));
      if (encoded.length > 4096) {
        throw const PaperOrderException(PaperOrderFailure.rejected);
      }
      final request =
          http.AbortableRequest(
              'POST',
              _baseUri.replace(path: path),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['accept'] = 'application/json'
            ..headers['content-type'] = 'application/json'
            ..headers['authorization'] = access.headerValue
            ..bodyBytes = encoded;
      try {
        final response = await _client.send(request);
        if (expired || _closed) {
          await response.stream.listen(null).cancel();
          throw const PaperOrderException(PaperOrderFailure.timeout);
        }
        if (response.isRedirect ||
            response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.listen(null).cancel();
          throw const PaperOrderException(PaperOrderFailure.rejected);
        }
        if ((response.contentLength ?? 0) > _maxResponseBytes) {
          await response.stream.listen(null).cancel();
          throw const PaperOrderException(PaperOrderFailure.rejected);
        }
        _jsonContentType(response.headers['content-type']);
        final bytes = <int>[];
        iterator = StreamIterator(response.stream);
        while (await iterator!.moveNext()) {
          if (expired || _closed) {
            throw const PaperOrderException(PaperOrderFailure.timeout);
          }
          final chunk = iterator!.current;
          if (bytes.length + chunk.length > _maxResponseBytes) {
            throw const PaperOrderException(PaperOrderFailure.rejected);
          }
          bytes.addAll(chunk);
        }
        iterator = null;
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        } catch (_) {
          throw const PaperOrderException(PaperOrderFailure.rejected);
        }
        if (response.statusCode != 200) {
          final terminalGuest = _terminalGuestFailure(decoded);
          if (terminalGuest != null) {
            _onGuestSessionFailure?.call(terminalGuest);
            throw GuestSessionException(terminalGuest);
          }
          throw PaperOrderException(_failure(response.statusCode, decoded));
        }
        return decoded;
      } on GuestSessionException {
        rethrow;
      } on PaperOrderException {
        rethrow;
      } catch (_) {
        if (expired) {
          throw const PaperOrderException(PaperOrderFailure.timeout);
        }
        throw const PaperOrderException(PaperOrderFailure.offline);
      }
    }

    try {
      return await perform().timeout(
        _timeout,
        onTimeout: () {
          expired = true;
          if (!abort.isCompleted) abort.complete();
          final bodyIterator = iterator;
          if (bodyIterator != null) {
            unawaited(bodyIterator.cancel().catchError((Object _) {}));
          }
          throw const PaperOrderException(PaperOrderFailure.timeout);
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

PaperOrderFailure _failure(int status, Object? value) {
  if (status == 401 || status == 403) return PaperOrderFailure.accountRequired;
  if (status == 408 || status == 504) return PaperOrderFailure.timeout;
  String? code;
  if (value case {'error': final Map<String, dynamic> error}) {
    final candidate = error['code'];
    if (candidate is String) code = candidate;
  }
  return switch (code) {
    'PAPER_CASH_INSUFFICIENT' => PaperOrderFailure.insufficientPaper,
    'PAPER_POSITION_INSUFFICIENT' => PaperOrderFailure.insufficientShares,
    'PAPER_PREVIEW_EXPIRED' => PaperOrderFailure.quoteExpired,
    'PAPER_PORTFOLIO_CHANGED' ||
    'PAPER_PRICE_EXPIRED' => PaperOrderFailure.priceChanged,
    'PAPER_PREVIEW_ALREADY_COMMITTED' ||
    'PAPER_IDEMPOTENCY_CONFLICT' => PaperOrderFailure.duplicate,
    'PAPER_INPUT_INVALID' ||
    'PAPER_ORDER_TOO_SMALL' => PaperOrderFailure.invalidAmount,
    'PAPER_TRADING_UNAUTHENTICATED' => PaperOrderFailure.accountRequired,
    'PAPER_PRICE_UNAVAILABLE' ||
    'PAPER_ASSET_UNAVAILABLE' ||
    'PAPER_TRADING_UNAVAILABLE' => PaperOrderFailure.unavailable,
    _ =>
      status >= 500
          ? PaperOrderFailure.unavailable
          : PaperOrderFailure.rejected,
  };
}

GuestSessionFailure? _terminalGuestFailure(Object? value) {
  String? code;
  if (value case {'error': final Map<String, dynamic> error}) {
    if (error['code'] case final String candidate) code = candidate;
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

Map<String, dynamic> _paperEnvelope(Object? value, {required String payload}) {
  final envelope = _object(value);
  if (envelope['schemaVersion'] != 1 || envelope['mode'] != 'paper') {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  final unit = _object(envelope['unit']);
  final execution = _object(envelope['execution']);
  if (unit['kind'] != 'paper' ||
      unit['scaleDigits'] != 6 ||
      execution['walletUsed'] != false ||
      execution['transactionBuilt'] != false ||
      execution['transactionSigned'] != false ||
      execution['transactionBroadcast'] != false ||
      envelope[payload] is! Map<String, dynamic>) {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  return envelope;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  return value;
}

String _text(Object? value) {
  if (value is! String || value.isEmpty || value.length > 300) {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  return value;
}

String _uuid(Object? value) {
  final text = _text(value).toLowerCase();
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(text)) {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  return text;
}

BigInt _fixed(Object? value, {bool allowZero = false}) {
  final text = _text(value);
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,14})$').hasMatch(text)) {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  final parsed = BigInt.parse(text);
  if (!allowZero && parsed == BigInt.zero) {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  return parsed;
}

DateTime _utc(Object? value) {
  final text = _text(value);
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != text) {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  return parsed;
}

String _toMicros(String value, {required int maximumDecimals}) {
  final parts = value.split('.');
  if (parts.length > 2 ||
      parts.first.isEmpty ||
      !RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(parts.first)) {
    throw const PaperOrderException(PaperOrderFailure.invalidAmount);
  }
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > maximumDecimals ||
      fraction.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(fraction)) {
    throw const PaperOrderException(PaperOrderFailure.invalidAmount);
  }
  final padded = fraction.padRight(6, '0');
  final micros =
      BigInt.parse(parts.first) * BigInt.from(1000000) +
      BigInt.parse(padded.isEmpty ? '0' : padded);
  if (micros <= BigInt.zero || micros > BigInt.parse('999999999999999')) {
    throw const PaperOrderException(PaperOrderFailure.invalidAmount);
  }
  return micros.toString();
}

String _fromMicros(BigInt value) {
  if (value < BigInt.zero) {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  final whole = value ~/ BigInt.from(1000000);
  final remainder = (value % BigInt.from(1000000)).toString().padLeft(6, '0');
  final fraction = remainder.replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole.toString() : '$whole.$fraction';
}

void _bearer(String value) {
  final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(value);
  if (value.isEmpty ||
      value.length > 8192 ||
      match?.start != 0 ||
      match?.end != value.length) {
    throw const PaperOrderException(PaperOrderFailure.accountRequired);
  }
}

void _guest(String value) {
  if (!RegExp(r'^tg1_[A-Za-z0-9_-]{43}$').hasMatch(value)) {
    throw const PaperOrderException(PaperOrderFailure.accountRequired);
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
    throw const PaperOrderException(PaperOrderFailure.rejected);
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

String paperUuidV4() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
