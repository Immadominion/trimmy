import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../account/guest_session.dart';
import 'paper_order_repository.dart';
import 'paper_portfolio.dart';

const _portfolioPath = '/v1/account/paper/portfolio';
const _maxPortfolioBytes = 131072;
const _portfolioV2MediaType = 'application/vnd.trimmy.paper-portfolio.v2+json';

typedef PortfolioAuthorizationProvider = Future<PaperAuthorization> Function();

/// Reads the durable paper ledger for either a guest desk or a saved account.
/// It accepts only the paper response contract and never retains a credential.
final class HttpPaperPortfolioRepository implements PaperPortfolioRepository {
  HttpPaperPortfolioRepository({
    required http.Client transport,
    required Uri baseUri,
    required PortfolioAuthorizationProvider authorizationProvider,
    this.onGuestSessionFailure,
    Duration timeout = const Duration(seconds: 10),
    this.now = DateTime.now,
    bool allowLoopbackForTests = false,
  }) : _client = transport,
       _baseUri = _origin(baseUri, allowLoopbackForTests),
       _authorization = authorizationProvider,
       _timeout = timeout {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw const PaperOrderException(PaperOrderFailure.unavailable);
    }
  }

  final http.Client _client;
  final Uri _baseUri;
  final PortfolioAuthorizationProvider _authorization;
  final void Function(GuestSessionFailure)? onGuestSessionFailure;
  final Duration _timeout;
  final DateTime Function() now;
  bool _closed = false;

  @override
  Future<PaperPortfolioSnapshot> read() async {
    if (_closed) {
      throw const PaperOrderException(PaperOrderFailure.unavailable);
    }
    var timedOut = false;
    final abort = Completer<void>();
    StreamIterator<List<int>>? iterator;

    Future<PaperPortfolioSnapshot> perform() async {
      PaperAuthorization authorization;
      try {
        authorization = await _authorization();
      } on GuestSessionException catch (error) {
        if (_isTerminalGuestFailure(error.failure)) {
          onGuestSessionFailure?.call(error.failure);
          rethrow;
        }
        throw const PaperOrderException(PaperOrderFailure.accountRequired);
      } catch (_) {
        throw const PaperOrderException(PaperOrderFailure.accountRequired);
      }
      if (timedOut || _closed) {
        throw const PaperOrderException(PaperOrderFailure.timeout);
      }
      final request =
          http.AbortableRequest(
              'GET',
              _baseUri.replace(path: _portfolioPath),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['accept'] = _portfolioV2MediaType
            ..headers['authorization'] = _authorizationHeader(authorization);
      try {
        final response = await _client.send(request);
        if (timedOut || _closed) {
          await response.stream.listen(null).cancel();
          throw const PaperOrderException(PaperOrderFailure.timeout);
        }
        if (response.isRedirect ||
            response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.listen(null).cancel();
          throw const PaperOrderException(PaperOrderFailure.rejected);
        }
        if ((response.contentLength ?? 0) > _maxPortfolioBytes) {
          await response.stream.listen(null).cancel();
          throw const PaperOrderException(PaperOrderFailure.rejected);
        }
        final responseMediaType = _jsonContentType(
          response.headers['content-type'],
        );
        final bytes = <int>[];
        iterator = StreamIterator(response.stream);
        while (await iterator!.moveNext()) {
          if (timedOut || _closed) {
            throw const PaperOrderException(PaperOrderFailure.timeout);
          }
          final chunk = iterator!.current;
          if (bytes.length + chunk.length > _maxPortfolioBytes) {
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
            onGuestSessionFailure?.call(terminalGuest);
            throw GuestSessionException(terminalGuest);
          }
          throw PaperOrderException(_failure(response.statusCode, decoded));
        }
        return _portfolio(decoded, now().toUtc(), responseMediaType);
      } on GuestSessionException {
        rethrow;
      } on PaperOrderException {
        rethrow;
      } catch (_) {
        if (timedOut) {
          throw const PaperOrderException(PaperOrderFailure.timeout);
        }
        throw const PaperOrderException(PaperOrderFailure.offline);
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

  void close() => _closed = true;
}

PaperPortfolioSnapshot _portfolio(
  Object? input,
  DateTime now,
  String mediaType,
) {
  final value = _object(input);
  _keys(value, const {
    'schemaVersion',
    'mode',
    'unit',
    'revision',
    'startingCashPaperMicros',
    'cashPaperMicros',
    'openedAt',
    'updatedAt',
    'positions',
    'recentOrders',
    'valuation',
  });
  final unit = _object(value['unit']);
  _keys(unit, const {'kind', 'scaleDigits'});
  final schemaVersion = value['schemaVersion'];
  final revision = value['revision'];
  if ((schemaVersion != 1 && schemaVersion != 2) ||
      value['mode'] != 'paper' ||
      unit['kind'] != 'paper' ||
      unit['scaleDigits'] != 6 ||
      revision is! int ||
      revision < 0 ||
      revision > 9007199254740991) {
    _rejected();
  }
  if (schemaVersion == 1
      ? mediaType != 'application/json'
      : mediaType != _portfolioV2MediaType) {
    _rejected();
  }
  final positions = _list(
    value['positions'],
    1000,
  ).map(_position).toList(growable: false);
  if (positions
          .map((item) => '${item.assetId}\u0000${item.variantMint}')
          .toSet()
          .length !=
      positions.length) {
    _rejected();
  }
  final orders = _list(
    value['recentOrders'],
    100,
  ).map(_order).toList(growable: false);
  for (var index = 1; index < orders.length; index++) {
    if (orders[index].committedAt.isAfter(orders[index - 1].committedAt)) {
      _rejected();
    }
  }
  final openedAt = _nullableUtc(value['openedAt']);
  final updatedAt = _nullableUtc(value['updatedAt']);
  if ((openedAt == null) != (updatedAt == null) ||
      openedAt != null && updatedAt!.isBefore(openedAt)) {
    _rejected();
  }
  final startingCashMicros = _micros(value['startingCashPaperMicros']);
  final cashMicros = _micros(value['cashPaperMicros']);
  final cashPaper = _fromMicros(cashMicros);
  final openPositions = positions
      .where((position) => position.quantity != '0')
      .toList(growable: false);
  final valuation = schemaVersion == 1
      ? _legacyValuation(
          value['valuation'],
          revision: revision,
          cashPaper: cashPaper,
          openPositions: openPositions,
        )
      : _valuation(
          value['valuation'],
          now: now,
          revision: revision,
          cashMicros: cashMicros,
          openPositions: openPositions,
        );
  return PaperPortfolioSnapshot(
    revision: revision,
    startingCashPaper: _fromMicros(startingCashMicros),
    cashPaper: cashPaper,
    positions: positions,
    recentOrders: orders,
    valuation: valuation.currentAt(now),
    openedAt: openedAt,
    updatedAt: updatedAt,
  );
}

PaperPortfolioValuation _legacyValuation(
  Object? input, {
  required int revision,
  required String cashPaper,
  required List<PaperPortfolioPosition> openPositions,
}) {
  final value = _object(input);
  _keys(value, const {'status', 'note'});
  if (value['status'] != 'not_included') _rejected();
  _text(value['note'], 500);
  return PaperPortfolioValuation.notIncluded(
    portfolioRevision: revision,
    cashPaper: cashPaper,
    openPositions: openPositions,
  );
}

PaperPortfolioValuation _valuation(
  Object? input, {
  required DateTime now,
  required int revision,
  required BigInt cashMicros,
  required List<PaperPortfolioPosition> openPositions,
}) {
  final value = _object(input);
  _keys(value, const {
    'status',
    'portfolioRevision',
    'openPositionCount',
    'pricedPositionCount',
    'cashPaperMicros',
    'knownValuePaperMicros',
    'totalPaperMicros',
    'positions',
  });
  final portfolioRevision = value['portfolioRevision'];
  final openPositionCount = value['openPositionCount'];
  final pricedPositionCount = value['pricedPositionCount'];
  if (portfolioRevision != revision ||
      openPositionCount is! int ||
      openPositionCount != openPositions.length ||
      pricedPositionCount is! int ||
      pricedPositionCount < 0 ||
      pricedPositionCount > openPositionCount ||
      _micros(value['cashPaperMicros']) != cashMicros) {
    _rejected();
  }
  final rows = _list(value['positions'], 1000);
  if (rows.length != openPositions.length) _rejected();
  final parsedRows = <PaperPositionValuation>[];
  var parsedPriced = 0;
  var knownMicros = cashMicros;
  for (var index = 0; index < rows.length; index++) {
    final row = _object(rows[index]);
    _keys(row, const {
      'assetId',
      'variantMint',
      'status',
      'pricePaperMicros',
      'marketValuePaperMicros',
      'unrealizedGainPaperMicros',
      'observedAt',
      'acceptedAt',
      'expiresAt',
    });
    final expected = openPositions[index];
    final key = PaperPositionKey(
      assetId: _assetId(row['assetId']),
      variantMint: _mint(row['variantMint']),
    );
    if (key != expected.key) _rejected();
    switch (row['status']) {
      case 'priced':
        final priceMicros = _micros(row['pricePaperMicros'], positive: true);
        final marketValueMicros = _derivedMicros(row['marketValuePaperMicros']);
        final unrealizedMicros = _signedDerivedMicros(
          row['unrealizedGainPaperMicros'],
        );
        final observedAt = _utc(row['observedAt']);
        final acceptedAt = _utc(row['acceptedAt']);
        final expiresAt = _utc(row['expiresAt']);
        if (acceptedAt.isAfter(now.add(const Duration(seconds: 5))) ||
            observedAt.isBefore(
              acceptedAt.subtract(const Duration(seconds: 10)),
            ) ||
            observedAt.isAfter(acceptedAt.add(const Duration(seconds: 5))) ||
            !expiresAt.isAfter(acceptedAt) ||
            expiresAt.isAfter(acceptedAt.add(const Duration(seconds: 60)))) {
          _rejected();
        }
        final quantityMicros = _decimalMicros(expected.quantity);
        final expectedMarket =
            quantityMicros * priceMicros ~/ BigInt.from(1000000);
        if (marketValueMicros != expectedMarket ||
            unrealizedMicros !=
                marketValueMicros - _decimalMicros(expected.costBasisPaper)) {
          _rejected();
        }
        parsedRows.add(
          PaperPositionValuation.priced(
            key: key,
            pricePaper: _fromMicros(priceMicros),
            marketValuePaper: _fromMicros(marketValueMicros),
            unrealizedGainPaper: _fromMicros(unrealizedMicros),
            observedAt: observedAt,
            acceptedAt: acceptedAt,
            expiresAt: expiresAt,
          ),
        );
        parsedPriced++;
        knownMicros += marketValueMicros;
        continue;
      case 'unavailable':
        for (final field in const [
          'pricePaperMicros',
          'marketValuePaperMicros',
          'unrealizedGainPaperMicros',
          'observedAt',
          'acceptedAt',
          'expiresAt',
        ]) {
          if (row[field] != null) _rejected();
        }
        parsedRows.add(PaperPositionValuation.unavailable(key: key));
        continue;
      default:
        _rejected();
    }
  }
  if (parsedPriced != pricedPositionCount ||
      _derivedMicros(value['knownValuePaperMicros']) != knownMicros) {
    _rejected();
  }
  final status = switch (value['status']) {
    'complete' => PaperPortfolioValuationStatus.complete,
    'partial' => PaperPortfolioValuationStatus.partial,
    'unavailable' => PaperPortfolioValuationStatus.unavailable,
    _ => _rejected(),
  };
  final expectedStatus =
      openPositionCount == 0 || pricedPositionCount == openPositionCount
      ? PaperPortfolioValuationStatus.complete
      : pricedPositionCount == 0
      ? PaperPortfolioValuationStatus.unavailable
      : PaperPortfolioValuationStatus.partial;
  if (status != expectedStatus) _rejected();
  final totalValue = value['totalPaperMicros'];
  final totalMicros = totalValue == null ? null : _derivedMicros(totalValue);
  if (status == PaperPortfolioValuationStatus.complete
      ? totalMicros != knownMicros
      : totalMicros != null) {
    _rejected();
  }
  return PaperPortfolioValuation(
    sourceIncluded: true,
    status: status,
    portfolioRevision: revision,
    openPositionCount: openPositionCount,
    pricedPositionCount: pricedPositionCount,
    cashPaper: _fromMicros(cashMicros),
    knownValuePaper: _fromMicros(knownMicros),
    totalPaper: totalMicros == null ? null : _fromMicros(totalMicros),
    positions: parsedRows,
  );
}

PaperPortfolioPosition _position(Object? input) {
  final value = _object(input);
  _keys(value, const {
    'assetId',
    'variantMint',
    'symbol',
    'quantityMicros',
    'costBasisPaperMicros',
    'averageCostPricePaperMicros',
    'realizedGainPaperMicros',
    'lockedGainPaperMicros',
    'updatedAt',
  });
  return PaperPortfolioPosition(
    assetId: _assetId(value['assetId']),
    variantMint: _mint(value['variantMint']),
    symbol: _symbol(value['symbol']),
    quantity: _fromMicros(_micros(value['quantityMicros'])),
    costBasisPaper: _fromMicros(_micros(value['costBasisPaperMicros'])),
    averageCostPaper: _fromMicros(
      _micros(value['averageCostPricePaperMicros']),
    ),
    realizedGainPaper: _fromMicros(
      _signedMicros(value['realizedGainPaperMicros']),
    ),
    lockedGainPaper: _fromMicros(_micros(value['lockedGainPaperMicros'])),
    updatedAt: _utc(value['updatedAt']),
  );
}

PaperPortfolioOrder _order(Object? input) {
  final value = _object(input);
  _keys(value, const {
    'id',
    'previewId',
    'accountRevision',
    'action',
    'assetId',
    'variantMint',
    'symbol',
    'pricePaperMicros',
    'quantityMicros',
    'cashDebitPaperMicros',
    'cashCreditPaperMicros',
    'cashAfterPaperMicros',
    'positionQuantityAfterMicros',
    'positionCostBasisAfterPaperMicros',
    'realizedGainDeltaPaperMicros',
    'lockedGainDeltaPaperMicros',
    'source',
    'committedAt',
  });
  _uuid(value['previewId']);
  final revision = value['accountRevision'];
  if (revision is! int || revision < 1 || revision > 9007199254740991) {
    _rejected();
  }
  final action = _text(value['action'], 8);
  if (action != 'buy' && action != 'sell' && action != 'trim') _rejected();
  for (final key in const [
    'cashDebitPaperMicros',
    'cashCreditPaperMicros',
    'positionQuantityAfterMicros',
    'positionCostBasisAfterPaperMicros',
    'lockedGainDeltaPaperMicros',
  ]) {
    _micros(value[key]);
  }
  _signedMicros(value['realizedGainDeltaPaperMicros']);
  _source(value['source']);
  return PaperPortfolioOrder(
    orderId: _uuid(value['id']),
    assetId: _assetId(value['assetId']),
    variantMint: _mint(value['variantMint']),
    symbol: _symbol(value['symbol']),
    action: action,
    pricePaper: _fromMicros(_micros(value['pricePaperMicros'], positive: true)),
    quantity: _fromMicros(_micros(value['quantityMicros'], positive: true)),
    cashAfterPaper: _fromMicros(_micros(value['cashAfterPaperMicros'])),
    committedAt: _utc(value['committedAt']),
  );
}

void _source(Object? input) {
  final value = _object(input);
  _keys(value, const {
    'provider',
    'providerReference',
    'marketSource',
    'metricsSource',
    'providerTimestamps',
    'observedAt',
    'acceptedAt',
  });
  if (value['provider'] != 'tokens-xyz-v1' ||
      !_text(value['providerReference'], 300).startsWith('/v1/assets/')) {
    _rejected();
  }
  for (final key in const ['marketSource', 'metricsSource']) {
    if (value[key] != null) _text(value[key], 80);
  }
  final stamps = _object(value['providerTimestamps']);
  _keys(stamps, const {'asOf', 'lastFetchedAt', 'lastTradeAt', 'unit'});
  if (stamps['unit'] != 'not_declared') _rejected();
  for (final key in const ['asOf', 'lastFetchedAt', 'lastTradeAt']) {
    final stamp = stamps[key];
    if (stamp != null &&
        (stamp is! String ||
            !RegExp(r'^(?:0|[1-9][0-9]{0,15})$').hasMatch(stamp))) {
      _rejected();
    }
  }
  _utc(value['observedAt']);
  _utc(value['acceptedAt']);
}

PaperOrderFailure _failure(int status, Object? input) {
  if (status == 401 || status == 403) return PaperOrderFailure.accountRequired;
  if (status == 408 || status == 504) return PaperOrderFailure.timeout;
  String? code;
  if (input case {'error': final Map<String, dynamic> error}) {
    if (error['code'] case final String value) code = value;
  }
  return switch (code) {
    'GUEST_SESSION_RATE_LIMITED' => PaperOrderFailure.unavailable,
    'GUEST_SESSION_EXPIRED' ||
    'GUEST_SESSION_REVOKED' ||
    'GUEST_SESSION_UNAUTHENTICATED' ||
    'PAPER_TRADING_UNAUTHENTICATED' => PaperOrderFailure.accountRequired,
    'PAPER_TRADING_UNAVAILABLE' => PaperOrderFailure.unavailable,
    _ =>
      status >= 500
          ? PaperOrderFailure.unavailable
          : PaperOrderFailure.rejected,
  };
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
    throw const PaperOrderException(PaperOrderFailure.unavailable);
  }
  return uri.replace(path: '');
}

String _authorizationHeader(PaperAuthorization value) {
  final header = value.headerValue;
  if (header.length > 4096 ||
      !(header.startsWith('Bearer ') || header.startsWith('Guest '))) {
    throw const PaperOrderException(PaperOrderFailure.accountRequired);
  }
  final credential = header.substring(header.indexOf(' ') + 1);
  if (credential.isEmpty || RegExp(r'[\x00-\x20\x7f]').hasMatch(credential)) {
    throw const PaperOrderException(PaperOrderFailure.accountRequired);
  }
  return header;
}

String _jsonContentType(String? value) {
  final mediaType = value?.split(';').first.trim().toLowerCase();
  if (mediaType != 'application/json' && mediaType != _portfolioV2MediaType) {
    throw const PaperOrderException(PaperOrderFailure.rejected);
  }
  return mediaType!;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) _rejected();
  return value;
}

List<Object?> _list(Object? value, int maximum) {
  if (value is! List<Object?> || value.length > maximum) _rejected();
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    _rejected();
  }
}

Never _rejected() =>
    throw const PaperOrderException(PaperOrderFailure.rejected);

String _text(Object? value, int maximum) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximum ||
      value.trim() != value ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    _rejected();
  }
  return value;
}

String _uuid(Object? value) {
  final text = _text(value, 36).toLowerCase();
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(text)) {
    _rejected();
  }
  return text;
}

String _assetId(Object? value) {
  final text = _text(value, 100);
  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(text)) {
    _rejected();
  }
  return text;
}

String _mint(Object? value) {
  final text = _text(value, 44);
  if (!RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(text)) {
    _rejected();
  }
  return text;
}

String _symbol(Object? value) {
  return _text(value, 30);
}

BigInt _micros(Object? value, {bool positive = false}) {
  if (value is! String ||
      !RegExp(r'^(?:0|[1-9][0-9]{0,14})$').hasMatch(value)) {
    _rejected();
  }
  final parsed = BigInt.parse(value);
  if (positive && parsed == BigInt.zero) _rejected();
  return parsed;
}

BigInt _signedMicros(Object? value) {
  if (value is! String ||
      !RegExp(r'^(?:0|-?[1-9][0-9]{0,14})$').hasMatch(value)) {
    _rejected();
  }
  return BigInt.parse(value);
}

BigInt _derivedMicros(Object? value) {
  if (value is! String ||
      !RegExp(r'^(?:0|[1-9][0-9]{0,29})$').hasMatch(value)) {
    _rejected();
  }
  return BigInt.parse(value);
}

BigInt _signedDerivedMicros(Object? value) {
  if (value is! String ||
      !RegExp(r'^(?:0|-?[1-9][0-9]{0,29})$').hasMatch(value)) {
    _rejected();
  }
  return BigInt.parse(value);
}

BigInt _decimalMicros(String value) {
  final negative = value.startsWith('-');
  final absolute = negative ? value.substring(1) : value;
  final parts = absolute.split('.');
  final parsed =
      BigInt.parse(parts[0]) * BigInt.from(1000000) +
      BigInt.parse(
        (parts.length == 1 ? '' : parts[1]).padRight(6, '0').padLeft(1, '0'),
      );
  return negative ? -parsed : parsed;
}

DateTime _utc(Object? value) {
  final text = _text(value, 24);
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  ).hasMatch(text)) {
    _rejected();
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != text) {
    _rejected();
  }
  return parsed;
}

DateTime? _nullableUtc(Object? value) => value == null ? null : _utc(value);

String _fromMicros(BigInt value) {
  final negative = value.isNegative;
  final absolute = value.abs();
  final whole = absolute ~/ BigInt.from(1000000);
  final fraction = (absolute % BigInt.from(1000000))
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
}
