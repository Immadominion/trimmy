import 'dart:convert';

import 'validation.dart';

const stockHistoryAssetId = 'apple';
const stockHistoryAaplxMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const stockHistoryRoute = '/v1/markets/stocks/history';

const _maximumWindowSeconds = 31 * 86400;
const _minimumUnixSeconds = 946684800;
const _maximumBodyBytes = 1048576;

enum StockHistoryInterval {
  oneHour('1H', 3600),
  fourHours('4H', 14400),
  oneDay('1D', 86400);

  const StockHistoryInterval(this.wireValue, this.seconds);

  final String wireValue;
  final int seconds;

  static StockHistoryInterval? fromWire(Object? value) {
    for (final interval in values) {
      if (interval.wireValue == value) return interval;
    }
    return null;
  }
}

/// One bounded request for the observed Apple xStock mint history contract.
///
/// The identity remains explicit on the wire and is validated before dispatch;
/// callers cannot silently substitute another company or token mint.
final class StockHistoryRequest {
  const StockHistoryRequest({
    required this.assetId,
    required this.variantMint,
    required this.interval,
    required this.fromUnixSeconds,
    required this.toUnixSeconds,
  });

  const StockHistoryRequest.appleAaplx({
    required this.interval,
    required this.fromUnixSeconds,
    required this.toUnixSeconds,
  }) : assetId = stockHistoryAssetId,
       variantMint = stockHistoryAaplxMint;

  final String assetId;
  final String variantMint;
  final StockHistoryInterval interval;
  final String fromUnixSeconds;
  final String toUnixSeconds;

  Map<String, String> get queryParameters => Map.unmodifiable({
    'assetId': assetId,
    'variantMint': variantMint,
    'interval': interval.wireValue,
    'fromUnixSeconds': fromUnixSeconds,
    'toUnixSeconds': toUnixSeconds,
  });

  ({int from, int to}) validateAt(int nowUnixSeconds) {
    if (assetId != stockHistoryAssetId ||
        variantMint != stockHistoryAaplxMint ||
        !_canonicalUnixSeconds(fromUnixSeconds) ||
        !_canonicalUnixSeconds(toUnixSeconds) ||
        nowUnixSeconds < 0) {
      throw const StockResearchException('STOCK_HISTORY_INPUT_INVALID');
    }
    final from = int.parse(fromUnixSeconds);
    final to = int.parse(toUnixSeconds);
    if (from < _minimumUnixSeconds ||
        from >= to ||
        to - from < interval.seconds ||
        to - from > _maximumWindowSeconds ||
        to > nowUnixSeconds + 60) {
      throw const StockResearchException('STOCK_HISTORY_INPUT_INVALID');
    }
    return (from: from, to: to);
  }

  @override
  bool operator ==(Object other) =>
      other is StockHistoryRequest &&
      other.assetId == assetId &&
      other.variantMint == variantMint &&
      other.interval == interval &&
      other.fromUnixSeconds == fromUnixSeconds &&
      other.toUnixSeconds == toUnixSeconds;

  @override
  int get hashCode => Object.hash(
    assetId,
    variantMint,
    interval,
    fromUnixSeconds,
    toUnixSeconds,
  );
}

final class StockHistoryCandle {
  const StockHistoryCandle._({
    required this.startUnixSeconds,
    required this.openRaw,
    required this.highRaw,
    required this.lowRaw,
    required this.closeRaw,
    required this.volumeRaw,
  });

  final String startUnixSeconds;

  /// Exact provider JSON-number lexemes transported by the API as strings.
  final String openRaw;
  final String highRaw;
  final String lowRaw;
  final String closeRaw;
  final String volumeRaw;
}

final class StockHistoryProvenance {
  const StockHistoryProvenance._({
    required this.sourceUrl,
    required this.requestedAt,
    required this.observedAt,
    required this.refreshAfter,
  });

  final Uri sourceUrl;
  final DateTime requestedAt;
  final DateTime observedAt;
  final DateTime refreshAfter;

  String get providerFreshness => 'not_reported';
  String get providerCandleSource => 'not_exposed';
  bool get cachedUpstreamData => true;
  DateTime? get providerAsOf => null;

  bool isFreshAt(DateTime value) => value.toUtc().isBefore(refreshAfter);
}

/// Strict projection of the API's variant-specific history envelope.
///
/// No OHLCV field is converted to `num` or `double`. The exact provider
/// lexemes remain strings because the upstream documentation does not declare
/// their units or enough semantics for execution use.
final class StockHistoryPage {
  const StockHistoryPage._({
    required this.interval,
    required this.fromUnixSeconds,
    required this.toUnixSeconds,
    required this.candles,
    required this.provenance,
  });

  factory StockHistoryPage.parse(
    String source, {
    required StockHistoryRequest request,
  }) {
    final bounds = request.validateAt(9999999999);
    final decoded = _LosslessJsonParser(source).parse();
    final data = _object(decoded, const {
      'schemaVersion',
      'provider',
      'providerContract',
      'historyKind',
      'canonicalEquityHistory',
      'assetId',
      'variantMint',
      'interval',
      'fromUnixSeconds',
      'toUnixSeconds',
      'candles',
      'dataStatus',
      'numericEncoding',
      'priceUnit',
      'volumeUnit',
      'provenance',
      'executionEnabled',
      'eligibility',
    });
    if (data['schemaVersion'] case _JsonNumber(raw: final raw)) {
      if (raw != '1') {
        throw const StockResearchException('STOCK_UNSUPPORTED_SCHEMA');
      }
    } else {
      _historyInvalid();
    }
    if (data['provider'] != 'tokens-xyz-v1' ||
        data['providerContract'] != 'observed_not_execution_qualified' ||
        data['historyKind'] != 'solana_mint_variant' ||
        data['canonicalEquityHistory'] != false ||
        data['assetId'] != request.assetId ||
        data['variantMint'] != request.variantMint ||
        data['interval'] != request.interval.wireValue ||
        data['fromUnixSeconds'] != request.fromUnixSeconds ||
        data['toUnixSeconds'] != request.toUnixSeconds ||
        data['numericEncoding'] != 'exact_provider_json_number_lexemes' ||
        data['priceUnit'] != 'provider_not_declared' ||
        data['volumeUnit'] != 'provider_not_declared' ||
        data['executionEnabled'] != false ||
        data['eligibility'] != 'unverified') {
      _historyInvalid();
    }

    final rawCandles = data['candles'];
    if (rawCandles is! List<Object?>) _historyInvalid();
    final maximumCandles =
        (bounds.to - bounds.from) ~/ request.interval.seconds + 2;
    if (rawCandles.length > maximumCandles) _historyInvalid();
    final candles = <StockHistoryCandle>[];
    int? previousTime;
    for (final value in rawCandles) {
      final candle = _object(value, const {
        'startUnixSeconds',
        'openRaw',
        'highRaw',
        'lowRaw',
        'closeRaw',
        'volumeRaw',
      });
      final timeRaw = _unixSeconds(candle['startUnixSeconds']);
      final time = int.parse(timeRaw);
      if (time < bounds.from ||
          time > bounds.to ||
          time % request.interval.seconds != 0 ||
          previousTime != null &&
              (time <= previousTime ||
                  (time - previousTime) % request.interval.seconds != 0)) {
        _historyInvalid();
      }
      previousTime = time;
      final open = _decimal(candle['openRaw'], allowZero: false);
      final high = _decimal(candle['highRaw'], allowZero: false);
      final low = _decimal(candle['lowRaw'], allowZero: false);
      final close = _decimal(candle['closeRaw'], allowZero: false);
      final volume = _decimal(candle['volumeRaw'], allowZero: true);
      if (_compareDecimal(high.parts, open.parts) < 0 ||
          _compareDecimal(high.parts, close.parts) < 0 ||
          _compareDecimal(high.parts, low.parts) < 0 ||
          _compareDecimal(low.parts, open.parts) > 0 ||
          _compareDecimal(low.parts, close.parts) > 0) {
        _historyInvalid();
      }
      candles.add(
        StockHistoryCandle._(
          startUnixSeconds: timeRaw,
          openRaw: open.raw,
          highRaw: high.raw,
          lowRaw: low.raw,
          closeRaw: close.raw,
          volumeRaw: volume.raw,
        ),
      );
    }
    final empty = candles.isEmpty;
    if (data['dataStatus'] !=
        (empty ? 'empty_provider_cache_or_no_trades' : 'observed')) {
      _historyInvalid();
    }

    return StockHistoryPage._(
      interval: request.interval,
      fromUnixSeconds: request.fromUnixSeconds,
      toUnixSeconds: request.toUnixSeconds,
      candles: List.unmodifiable(candles),
      provenance: _provenance(data['provenance'], request),
    );
  }

  final StockHistoryInterval interval;
  final String fromUnixSeconds;
  final String toUnixSeconds;
  final List<StockHistoryCandle> candles;
  final StockHistoryProvenance provenance;

  int get schemaVersion => 1;
  String get assetId => stockHistoryAssetId;
  String get variantMint => stockHistoryAaplxMint;
  String get provider => 'tokens-xyz-v1';
  String get providerContract => 'observed_not_execution_qualified';
  String get historyKind => 'solana_mint_variant';
  String get dataStatus =>
      candles.isEmpty ? 'empty_provider_cache_or_no_trades' : 'observed';
  String get numericEncoding => 'exact_provider_json_number_lexemes';
  String get priceUnit => 'provider_not_declared';
  String get volumeUnit => 'provider_not_declared';
  String get eligibility => 'unverified';
  bool get canonicalEquityHistory => false;
  bool get executionEnabled => false;
}

const _serverCodesByStatus = <int, Set<String>>{
  400: {'STOCK_HISTORY_INPUT_INVALID'},
  429: {'STOCK_HISTORY_RATE_LIMITED'},
  502: {'STOCK_HISTORY_PROVIDER_UNAVAILABLE', 'STOCK_HISTORY_RESPONSE_INVALID'},
  503: {'STOCK_HISTORY_UNAVAILABLE', 'STOCK_HISTORY_PROVIDER_AUTH_FAILED'},
  504: {'STOCK_HISTORY_TIMEOUT'},
};

/// Accepts only the public API's fixed error envelope and exact status/code
/// combinations. Provider diagnostics and future fields never enter state.
String parseStockHistoryServerError(String source, int statusCode) {
  try {
    final outer = _object(_LosslessJsonParser(source).parse(), const {'error'});
    final error = _object(outer['error'], const {
      'code',
      'message',
      'requestId',
    });
    final code = error['code'];
    final message = error['message'];
    final requestId = error['requestId'];
    if (code is! String ||
        _serverCodesByStatus[statusCode]?.contains(code) != true ||
        message is! String ||
        message.isEmpty ||
        message.length > 1024 ||
        message.trim() != message ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(message) ||
        requestId is! String ||
        requestId.isEmpty ||
        requestId.length > 128 ||
        requestId.trim() != requestId ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(requestId)) {
      throw const StockResearchException('STOCK_HISTORY_SERVICE_UNAVAILABLE');
    }
    return code;
  } catch (error) {
    if (error is StockResearchException &&
        error.code == 'STOCK_HISTORY_SERVICE_UNAVAILABLE') {
      rethrow;
    }
    throw const StockResearchException('STOCK_HISTORY_SERVICE_UNAVAILABLE');
  }
}

StockHistoryProvenance _provenance(Object? value, StockHistoryRequest request) {
  final data = _object(value, const {
    'sourceUrl',
    'requestedAt',
    'observedAt',
    'providerAsOf',
    'providerFreshness',
    'providerCandleSource',
    'refreshAfter',
    'cachedUpstreamData',
  });
  if (data['providerAsOf'] != null ||
      data['providerFreshness'] != 'not_reported' ||
      data['providerCandleSource'] != 'not_exposed' ||
      data['cachedUpstreamData'] != true) {
    _historyInvalid();
  }
  final requestedAt = _timestamp(data['requestedAt']);
  final observedAt = _timestamp(data['observedAt']);
  final refreshAfter = _timestamp(data['refreshAfter']);
  if (observedAt.isBefore(requestedAt) ||
      observedAt.difference(requestedAt) >= const Duration(minutes: 1) ||
      refreshAfter.difference(observedAt) != const Duration(seconds: 15)) {
    _historyInvalid();
  }
  final sourceUrl = _sourceUrl(data['sourceUrl'], request);
  return StockHistoryProvenance._(
    sourceUrl: sourceUrl,
    requestedAt: requestedAt,
    observedAt: observedAt,
    refreshAfter: refreshAfter,
  );
}

Uri _sourceUrl(Object? value, StockHistoryRequest request) {
  if (value is! String || value.length > 2048 || value.trim() != value) {
    _historyInvalid();
  }
  final expected =
      'https://api.tokens.xyz/v1/assets/apple/ohlcv'
      '?mint=${request.variantMint}&interval=${request.interval.wireValue}'
      '&from=${request.fromUnixSeconds}&to=${request.toUnixSeconds}';
  final uri = Uri.tryParse(value);
  final query = uri?.queryParametersAll;
  if (value != expected ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'api.tokens.xyz' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.path != '/v1/assets/apple/ohlcv' ||
      uri.hasFragment ||
      query == null ||
      query.length != 4 ||
      query['mint']?.length != 1 ||
      query['mint']?.single != request.variantMint ||
      query['interval']?.length != 1 ||
      query['interval']?.single != request.interval.wireValue ||
      query['from']?.length != 1 ||
      query['from']?.single != request.fromUnixSeconds ||
      query['to']?.length != 1 ||
      query['to']?.single != request.toUnixSeconds) {
    _historyInvalid();
  }
  return uri;
}

DateTime _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(value)) {
    _historyInvalid();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    _historyInvalid();
  }
  return parsed;
}

String _unixSeconds(Object? value) {
  if (value is! String || !_canonicalUnixSeconds(value)) _historyInvalid();
  return value;
}

bool _canonicalUnixSeconds(String value) =>
    RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(value);

({String raw, _DecimalParts parts}) _decimal(
  Object? value, {
  required bool allowZero,
}) {
  if (value is! String || value.length > 128) _historyInvalid();
  final match = RegExp(
    r'^(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$',
  ).firstMatch(value);
  if (match == null) _historyInvalid();
  final exponent = int.tryParse(match.group(3) ?? '0');
  if (exponent == null || exponent.abs() > 100) _historyInvalid();
  var digits = '${match.group(1)}${match.group(2) ?? ''}'.replaceFirst(
    RegExp(r'^0+'),
    '',
  );
  final zero = digits.isEmpty;
  if (zero) digits = '0';
  if (zero && !allowZero) _historyInvalid();
  return (
    raw: value,
    parts: _DecimalParts(
      digits,
      zero ? 0 : exponent - (match.group(2)?.length ?? 0),
      zero,
    ),
  );
}

final class _DecimalParts {
  const _DecimalParts(this.digits, this.scale, this.zero);

  final String digits;
  final int scale;
  final bool zero;
}

int _compareDecimal(_DecimalParts left, _DecimalParts right) {
  if (left.zero || right.zero) {
    if (left.zero == right.zero) return 0;
    return left.zero ? -1 : 1;
  }
  final leftMagnitude = left.digits.length + left.scale;
  final rightMagnitude = right.digits.length + right.scale;
  if (leftMagnitude != rightMagnitude) {
    return leftMagnitude < rightMagnitude ? -1 : 1;
  }
  final scale = left.scale < right.scale ? left.scale : right.scale;
  final leftValue = BigInt.parse('${left.digits}${'0' * (left.scale - scale)}');
  final rightValue = BigInt.parse(
    '${right.digits}${'0' * (right.scale - scale)}',
  );
  return leftValue.compareTo(rightValue);
}

Map<String, Object?> _object(Object? value, Set<String> keys) {
  if (value is! Map<String, Object?> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    _historyInvalid();
  }
  return value;
}

Never _historyInvalid() =>
    throw const StockResearchException('STOCK_HISTORY_RESPONSE_INVALID');

final class _JsonNumber {
  const _JsonNumber(this.raw);

  final String raw;
}

/// A bounded decoder which never converts a JSON number token to `double`.
final class _LosslessJsonParser {
  _LosslessJsonParser(this.source) {
    if (source.length > _maximumBodyBytes ||
        utf8.encode(source).length > _maximumBodyBytes) {
      _historyInvalid();
    }
  }

  final String source;
  var _offset = 0;
  var _nodes = 0;

  Object? parse() {
    final result = _value(0);
    _whitespace();
    if (_offset != source.length) _historyInvalid();
    return result;
  }

  Object? _value(int depth) {
    _nodes++;
    if (_nodes > 100000 || depth > 8) _historyInvalid();
    _whitespace();
    final character = _at(_offset);
    if (character == '"') return _string();
    if (character == '[') return _array(depth + 1);
    if (character == '{') return _map(depth + 1);
    for (final literal in const {
      'true': true,
      'false': false,
      'null': null,
    }.entries) {
      if (source.startsWith(literal.key, _offset)) {
        _offset += literal.key.length;
        return literal.value;
      }
    }
    final remainder = source.substring(_offset);
    final match = RegExp(
      r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
    ).firstMatch(remainder);
    if (match == null || match.group(0)!.length > 128) _historyInvalid();
    final raw = match.group(0)!;
    _offset += raw.length;
    return _JsonNumber(raw);
  }

  String _string() {
    final start = _offset++;
    var escaped = false;
    while (_offset < source.length) {
      final character = source[_offset++];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character == r'\') {
        escaped = true;
        continue;
      }
      if (character == '"') {
        Object? decoded;
        try {
          decoded = jsonDecode(source.substring(start, _offset));
        } catch (_) {
          _historyInvalid();
        }
        if (decoded is! String || decoded.length > 4096) _historyInvalid();
        return decoded;
      }
      if (character.codeUnitAt(0) < 32) _historyInvalid();
    }
    _historyInvalid();
  }

  List<Object?> _array(int depth) {
    _offset++;
    _whitespace();
    final result = <Object?>[];
    if (_at(_offset) == ']') {
      _offset++;
      return List.unmodifiable(result);
    }
    while (true) {
      if (result.length >= 20000) _historyInvalid();
      result.add(_value(depth));
      _whitespace();
      if (_at(_offset) == ']') {
        _offset++;
        return List.unmodifiable(result);
      }
      if (_at(_offset) != ',') _historyInvalid();
      _offset++;
    }
  }

  Map<String, Object?> _map(int depth) {
    _offset++;
    _whitespace();
    final result = <String, Object?>{};
    if (_at(_offset) == '}') {
      _offset++;
      return Map.unmodifiable(result);
    }
    while (true) {
      _whitespace();
      if (_at(_offset) != '"') _historyInvalid();
      final key = _string();
      _whitespace();
      if (key.length > 64 || result.containsKey(key) || _at(_offset) != ':') {
        _historyInvalid();
      }
      _offset++;
      if (result.length >= 64) _historyInvalid();
      result[key] = _value(depth);
      _whitespace();
      if (_at(_offset) == '}') {
        _offset++;
        return Map.unmodifiable(result);
      }
      if (_at(_offset) != ',') _historyInvalid();
      _offset++;
    }
  }

  void _whitespace() {
    while (const {' ', '\n', '\r', '\t'}.contains(_at(_offset))) {
      _offset++;
    }
  }

  String? _at(int offset) =>
      offset >= 0 && offset < source.length ? source[offset] : null;
}
