import 'dart:convert';

import 'validation.dart' show StockResearchException;

const raydiumStockQuoteRoute = '/v1/markets/stocks/quotes/raydium';
const raydiumQuoteAssetId = 'apple';
const raydiumQuoteAaplxMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const raydiumQuoteUsdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

const _maximumInputRaw = '100000000';
const _maximumU64 = '18446744073709551615';
const _zeroAddress = '11111111111111111111111111111111';

enum RaydiumQuoteSide { buy, sell }

/// A fixed Apple/AAPLx base-in quote request.
///
/// Identity remains explicit on the wire, but validation prevents a caller
/// from silently substituting another stock, mint, or non-canonical amount.
final class RaydiumQuoteRequest {
  const RaydiumQuoteRequest({
    required this.assetId,
    required this.variantMint,
    required this.side,
    required this.amountRaw,
  });

  const RaydiumQuoteRequest.appleAaplx({
    required this.side,
    required this.amountRaw,
  }) : assetId = raydiumQuoteAssetId,
       variantMint = raydiumQuoteAaplxMint;

  final String assetId;
  final String variantMint;
  final RaydiumQuoteSide side;
  final String amountRaw;

  void validate() {
    if (assetId != raydiumQuoteAssetId ||
        variantMint != raydiumQuoteAaplxMint ||
        !_isCanonicalRaw(amountRaw, positive: true) ||
        BigInt.parse(amountRaw) > BigInt.parse(_maximumInputRaw)) {
      throw const StockResearchException('MARKET_INPUT_INVALID');
    }
  }

  Map<String, String> get queryParameters => Map.unmodifiable({
    'assetId': assetId,
    'variantMint': variantMint,
    'side': side.name,
    'amountRaw': amountRaw,
  });

  @override
  bool operator ==(Object other) =>
      other is RaydiumQuoteRequest &&
      other.assetId == assetId &&
      other.variantMint == variantMint &&
      other.side == side &&
      other.amountRaw == amountRaw;

  @override
  int get hashCode => Object.hash(assetId, variantMint, side, amountRaw);
}

final class RaydiumQuoteInput {
  const RaydiumQuoteInput._({
    required this.symbol,
    required this.mint,
    required this.decimals,
    required this.amountRaw,
    required this.providerActualAmountRaw,
  });

  final String symbol;
  final String mint;
  final int decimals;
  final String amountRaw;
  final String? providerActualAmountRaw;
}

final class RaydiumQuoteOutput {
  const RaydiumQuoteOutput._({
    required this.symbol,
    required this.mint,
    required this.decimals,
    required this.estimatedAmountRaw,
    required this.quotedMinimumAmountRaw,
  });

  final String symbol;
  final String mint;
  final int decimals;
  final String estimatedAmountRaw;
  final String quotedMinimumAmountRaw;
}

final class RaydiumQuoteFee {
  const RaydiumQuoteFee._({
    required this.amountRaw,
    required this.mint,
    required this.providerRateRaw,
  });

  final String amountRaw;
  final String mint;
  final int providerRateRaw;

  String get rateUnit => 'provider_integer_unverified';
}

final class RaydiumQuoteHop {
  const RaydiumQuoteHop._({
    required this.poolId,
    required this.inputMint,
    required this.outputMint,
    required this.fee,
  });

  final String poolId;
  final String inputMint;
  final String outputMint;
  final RaydiumQuoteFee fee;
}

final class RaydiumQuoteRoute {
  const RaydiumQuoteRoute._({required this.hopCount, required this.hops});

  final int hopCount;
  final List<RaydiumQuoteHop> hops;
}

/// Strict, read-only projection returned by Trimmy's Raydium quote endpoint.
///
/// Token quantities remain canonical raw integer strings. This object cannot
/// hold a wallet, transaction, signature, simulation, or broadcast payload.
final class RaydiumStockQuote {
  const RaydiumStockQuote._({
    required this.request,
    required this.input,
    required this.output,
    required this.priceImpactPct,
    required this.route,
    required this.requestedAt,
    required this.receivedAt,
    required this.refreshAfter,
  });

  factory RaydiumStockQuote.parse(
    String source, {
    required RaydiumQuoteRequest request,
  }) {
    request.validate();
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      _invalid();
    }
    return RaydiumStockQuote.fromJson(decoded, request: request);
  }

  factory RaydiumStockQuote.fromJson(
    Object? value, {
    required RaydiumQuoteRequest request,
  }) {
    request.validate();
    final data = _object(value, const {
      'schemaVersion',
      'kind',
      'comparisonOnly',
      'network',
      'provider',
      'providerResponseVersion',
      'providerEndpoint',
      'quoteMode',
      'transactionVersionRequested',
      'assetId',
      'variantMint',
      'side',
      'executionEnabled',
      'executable',
      'eligibility',
      'walletChecked',
      'networkFees',
      'amountUnits',
      'input',
      'output',
      'slippageBps',
      'priceImpactPct',
      'referralAmountRaw',
      'route',
      'requestedAt',
      'receivedAt',
      'refreshAfter',
      'providerExpiresAt',
    });
    final schemaVersion = data['schemaVersion'];
    if (schemaVersion is! int) _invalid();
    if (schemaVersion != 1) {
      throw const StockResearchException('RAYDIUM_QUOTE_UNSUPPORTED_SCHEMA');
    }
    if (data['kind'] != 'indicative' ||
        data['comparisonOnly'] != true ||
        data['network'] != 'solana:mainnet-beta' ||
        data['provider'] != 'raydium-trade-api' ||
        data['providerResponseVersion'] != 'V1' ||
        data['providerEndpoint'] != 'compute/swap-base-in' ||
        data['quoteMode'] != 'BaseIn' ||
        data['transactionVersionRequested'] != 'V0' ||
        data['assetId'] != request.assetId ||
        data['variantMint'] != request.variantMint ||
        data['side'] != request.side.name ||
        data['executionEnabled'] != false ||
        data['executable'] != false ||
        data['eligibility'] != 'unverified' ||
        data['walletChecked'] != false ||
        data['networkFees'] != null ||
        data['amountUnits'] != 'raw_token_units' ||
        data['slippageBps'] != 50 ||
        data['referralAmountRaw'] != '0' ||
        data['providerExpiresAt'] != null) {
      _invalid();
    }

    final buying = request.side == RaydiumQuoteSide.buy;
    final expectedInputMint = buying
        ? raydiumQuoteUsdcMint
        : raydiumQuoteAaplxMint;
    final expectedOutputMint = buying
        ? raydiumQuoteAaplxMint
        : raydiumQuoteUsdcMint;
    final input = _input(
      data['input'],
      expectedMint: expectedInputMint,
      expectedSymbol: buying ? 'USDC' : 'AAPLx',
      expectedDecimals: buying ? 6 : 8,
      request: request,
    );
    final output = _output(
      data['output'],
      expectedMint: expectedOutputMint,
      expectedSymbol: buying ? 'AAPLx' : 'USDC',
      expectedDecimals: buying ? 8 : 6,
    );
    final estimated = BigInt.parse(output.estimatedAmountRaw);
    final minimum = BigInt.parse(output.quotedMinimumAmountRaw);
    if (minimum > estimated ||
        minimum < estimated * BigInt.from(9950) ~/ BigInt.from(10000)) {
      _invalid();
    }

    final priceImpact = data['priceImpactPct'];
    if (priceImpact is! num ||
        !priceImpact.isFinite ||
        priceImpact < 0 ||
        priceImpact > 100) {
      _invalid();
    }
    final route = _route(
      data['route'],
      expectedInputMint: expectedInputMint,
      expectedOutputMint: expectedOutputMint,
      requestedInputRaw: request.amountRaw,
    );
    final requestedAt = _timestamp(data['requestedAt']);
    final receivedAt = _timestamp(data['receivedAt']);
    final refreshAfter = _timestamp(data['refreshAfter']);
    if (receivedAt.isBefore(requestedAt) ||
        !receivedAt.isBefore(refreshAfter) ||
        refreshAfter.difference(requestedAt) != const Duration(seconds: 10)) {
      _invalid();
    }
    return RaydiumStockQuote._(
      request: request,
      input: input,
      output: output,
      priceImpactPct: priceImpact,
      route: route,
      requestedAt: requestedAt,
      receivedAt: receivedAt,
      refreshAfter: refreshAfter,
    );
  }

  final RaydiumQuoteRequest request;
  final RaydiumQuoteInput input;
  final RaydiumQuoteOutput output;
  final num priceImpactPct;
  final RaydiumQuoteRoute route;
  final DateTime requestedAt;
  final DateTime receivedAt;
  final DateTime refreshAfter;

  int get schemaVersion => 1;
  String get kind => 'indicative';
  bool get comparisonOnly => true;
  String get network => 'solana:mainnet-beta';
  String get provider => 'raydium-trade-api';
  String get providerResponseVersion => 'V1';
  String get providerEndpoint => 'compute/swap-base-in';
  String get quoteMode => 'BaseIn';
  String get transactionVersionRequested => 'V0';
  String get assetId => raydiumQuoteAssetId;
  String get variantMint => raydiumQuoteAaplxMint;
  RaydiumQuoteSide get side => request.side;
  bool get executionEnabled => false;
  bool get executable => false;
  String get eligibility => 'unverified';
  bool get walletChecked => false;
  Object? get networkFees => null;
  String get amountUnits => 'raw_token_units';
  int get slippageBps => 50;
  String get referralAmountRaw => '0';
  DateTime? get providerExpiresAt => null;

  bool isFreshAt(DateTime now) => now.toUtc().isBefore(refreshAfter);
}

const _serverCodesByStatus = <int, Set<String>>{
  400: {'MARKET_INPUT_INVALID'},
  429: {'MARKET_RATE_LIMITED'},
  502: {
    'MARKET_PROVIDER_AUTH_FAILED',
    'MARKET_PROVIDER_UNAVAILABLE',
    'MARKET_RESPONSE_INVALID',
  },
  503: {'MARKET_UNAVAILABLE'},
  504: {'MARKET_TIMEOUT', 'MARKET_ESTIMATE_STALE'},
};

/// Parses only the fixed public error envelope and this route's exact
/// status/code combinations. Server and provider diagnostics are discarded.
String parseRaydiumQuoteServerError(String source, int statusCode) {
  try {
    final outer = _object(jsonDecode(source), const {'error'});
    final error = _object(outer['error'], const {
      'code',
      'message',
      'requestId',
    });
    final code = error['code'];
    if (code is! String ||
        _serverCodesByStatus[statusCode]?.contains(code) != true ||
        !_safeServerText(error['message'], 1024) ||
        !_safeServerText(error['requestId'], 128)) {
      throw const StockResearchException('RAYDIUM_QUOTE_SERVICE_UNAVAILABLE');
    }
    return code;
  } catch (error) {
    if (error is StockResearchException &&
        error.code == 'RAYDIUM_QUOTE_SERVICE_UNAVAILABLE') {
      rethrow;
    }
    throw const StockResearchException('RAYDIUM_QUOTE_SERVICE_UNAVAILABLE');
  }
}

RaydiumQuoteInput _input(
  Object? value, {
  required String expectedMint,
  required String expectedSymbol,
  required int expectedDecimals,
  required RaydiumQuoteRequest request,
}) {
  final data = _object(value, const {
    'symbol',
    'mint',
    'decimals',
    'amountRaw',
    'providerActualAmountRaw',
  });
  final amountRaw = _raw(data['amountRaw'], positive: true);
  final actual = data['providerActualAmountRaw'] == null
      ? null
      : _raw(data['providerActualAmountRaw'], positive: true);
  if (data['symbol'] != expectedSymbol ||
      data['mint'] != expectedMint ||
      data['decimals'] != expectedDecimals ||
      amountRaw != request.amountRaw ||
      actual != null && BigInt.parse(actual) > BigInt.parse(amountRaw)) {
    _invalid();
  }
  return RaydiumQuoteInput._(
    symbol: expectedSymbol,
    mint: expectedMint,
    decimals: expectedDecimals,
    amountRaw: amountRaw,
    providerActualAmountRaw: actual,
  );
}

RaydiumQuoteOutput _output(
  Object? value, {
  required String expectedMint,
  required String expectedSymbol,
  required int expectedDecimals,
}) {
  final data = _object(value, const {
    'symbol',
    'mint',
    'decimals',
    'estimatedAmountRaw',
    'quotedMinimumAmountRaw',
  });
  if (data['symbol'] != expectedSymbol ||
      data['mint'] != expectedMint ||
      data['decimals'] != expectedDecimals) {
    _invalid();
  }
  return RaydiumQuoteOutput._(
    symbol: expectedSymbol,
    mint: expectedMint,
    decimals: expectedDecimals,
    estimatedAmountRaw: _raw(data['estimatedAmountRaw'], positive: true),
    quotedMinimumAmountRaw: _raw(
      data['quotedMinimumAmountRaw'],
      positive: true,
    ),
  );
}

RaydiumQuoteRoute _route(
  Object? value, {
  required String expectedInputMint,
  required String expectedOutputMint,
  required String requestedInputRaw,
}) {
  final data = _object(value, const {'hopCount', 'hops'});
  final values = data['hops'];
  if (values is! List || values.isEmpty || values.length > 4) _invalid();
  if (data['hopCount'] is! int || data['hopCount'] != values.length) {
    _invalid();
  }
  final hops = <RaydiumQuoteHop>[];
  final poolIds = <String>{};
  final visitedMints = <String>{expectedInputMint};
  var nextInputMint = expectedInputMint;
  for (var index = 0; index < values.length; index++) {
    final hop = _object(values[index], const {
      'poolId',
      'inputMint',
      'outputMint',
      'fee',
    });
    final poolId = _solanaAddress(hop['poolId']);
    final inputMint = _solanaAddress(hop['inputMint']);
    final outputMint = _solanaAddress(hop['outputMint']);
    final feeData = _object(hop['fee'], const {
      'amountRaw',
      'mint',
      'providerRateRaw',
      'rateUnit',
    });
    final feeAmount = _raw(feeData['amountRaw'], positive: false);
    final feeMint = _solanaAddress(feeData['mint']);
    final providerRate = feeData['providerRateRaw'];
    if (!poolIds.add(poolId) ||
        inputMint != nextInputMint ||
        inputMint == outputMint ||
        !visitedMints.add(outputMint) ||
        feeMint != inputMint && feeMint != outputMint ||
        providerRate is! int ||
        providerRate < 0 ||
        providerRate > 10000 ||
        feeData['rateUnit'] != 'provider_integer_unverified' ||
        index == 0 &&
            feeMint == inputMint &&
            BigInt.parse(feeAmount) > BigInt.parse(requestedInputRaw)) {
      _invalid();
    }
    hops.add(
      RaydiumQuoteHop._(
        poolId: poolId,
        inputMint: inputMint,
        outputMint: outputMint,
        fee: RaydiumQuoteFee._(
          amountRaw: feeAmount,
          mint: feeMint,
          providerRateRaw: providerRate,
        ),
      ),
    );
    nextInputMint = outputMint;
  }
  if (nextInputMint != expectedOutputMint) _invalid();
  return RaydiumQuoteRoute._(
    hopCount: hops.length,
    hops: List.unmodifiable(hops),
  );
}

Map<String, Object?> _object(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.keys.any((key) => key is! String) ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    _invalid();
  }
  return Map<String, Object?>.from(value);
}

String _raw(Object? value, {required bool positive}) {
  if (value is! String || !_isCanonicalRaw(value, positive: positive)) {
    _invalid();
  }
  return value;
}

bool _isCanonicalRaw(String value, {required bool positive}) {
  final expression = positive
      ? r'^[1-9][0-9]{0,19}$'
      : r'^(?:0|[1-9][0-9]{0,19})$';
  return RegExp(expression).hasMatch(value) &&
      BigInt.parse(value) <= BigInt.parse(_maximumU64);
}

DateTime _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(value)) {
    _invalid();
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    _invalid();
  }
  return parsed;
}

String _solanaAddress(Object? value) {
  if (value is! String || value == _zeroAddress || value.length > 44) {
    _invalid();
  }
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  var number = BigInt.zero;
  var leadingZeroes = 0;
  for (var index = 0; index < value.length; index++) {
    final digit = alphabet.indexOf(value[index]);
    if (digit < 0) _invalid();
    number = number * BigInt.from(58) + BigInt.from(digit);
    if (index == leadingZeroes && value[index] == '1') leadingZeroes++;
  }
  if ((number.bitLength + 7) ~/ 8 + leadingZeroes != 32) _invalid();
  return value;
}

bool _safeServerText(Object? value, int maximumLength) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= maximumLength &&
    value.trim() == value &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

Never _invalid() {
  throw const StockResearchException('RAYDIUM_QUOTE_RESPONSE_INVALID');
}
