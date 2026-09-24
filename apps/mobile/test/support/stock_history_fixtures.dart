import 'dart:convert';

import 'package:trimmy/markets/stock_history.dart';

const stockHistoryFrom = '1789344000';
const stockHistoryTo = '1789351200';

const stockHistoryRequest = StockHistoryRequest.appleAaplx(
  interval: StockHistoryInterval.oneHour,
  fromUnixSeconds: stockHistoryFrom,
  toUnixSeconds: stockHistoryTo,
);

Map<String, Object?> stockHistoryCandleFixture({
  String startUnixSeconds = stockHistoryFrom,
  String openRaw = '1.2300',
  String highRaw = '1.24e0',
  String lowRaw = '1.22000',
  String closeRaw = '1.2300000000000000000000000000000000001',
  String volumeRaw = '90071992547409931234567890.00100',
}) => {
  'startUnixSeconds': startUnixSeconds,
  'openRaw': openRaw,
  'highRaw': highRaw,
  'lowRaw': lowRaw,
  'closeRaw': closeRaw,
  'volumeRaw': volumeRaw,
};

Map<String, Object?> stockHistoryFixture({
  StockHistoryRequest request = stockHistoryRequest,
  List<Map<String, Object?>>? candles,
  String requestedAt = '2026-09-14T18:00:00.000Z',
  String observedAt = '2026-09-14T18:00:01.000Z',
  String refreshAfter = '2026-09-14T18:00:16.000Z',
}) {
  final values =
      candles ??
      [
        stockHistoryCandleFixture(),
        stockHistoryCandleFixture(
          startUnixSeconds: '1789347600',
          openRaw: '1e-80',
          highRaw: '2e-80',
          lowRaw: '0.5e-80',
          closeRaw: '1.5e-80',
          volumeRaw: '0.000',
        ),
      ];
  return {
    'schemaVersion': 1,
    'provider': 'tokens-xyz-v1',
    'providerContract': 'observed_not_execution_qualified',
    'historyKind': 'solana_mint_variant',
    'canonicalEquityHistory': false,
    'assetId': request.assetId,
    'variantMint': request.variantMint,
    'interval': request.interval.wireValue,
    'fromUnixSeconds': request.fromUnixSeconds,
    'toUnixSeconds': request.toUnixSeconds,
    'candles': values,
    'dataStatus': values.isEmpty
        ? 'empty_provider_cache_or_no_trades'
        : 'observed',
    'numericEncoding': 'exact_provider_json_number_lexemes',
    'priceUnit': 'provider_not_declared',
    'volumeUnit': 'provider_not_declared',
    'provenance': {
      'sourceUrl':
          'https://api.tokens.xyz/v1/assets/apple/ohlcv'
          '?mint=${request.variantMint}&interval=${request.interval.wireValue}'
          '&from=${request.fromUnixSeconds}&to=${request.toUnixSeconds}',
      'requestedAt': requestedAt,
      'observedAt': observedAt,
      'providerAsOf': null,
      'providerFreshness': 'not_reported',
      'providerCandleSource': 'not_exposed',
      'refreshAfter': refreshAfter,
      'cachedUpstreamData': true,
    },
    'executionEnabled': false,
    'eligibility': 'unverified',
  };
}

String stockHistoryJson({
  StockHistoryRequest request = stockHistoryRequest,
  List<Map<String, Object?>>? candles,
  String requestedAt = '2026-09-14T18:00:00.000Z',
  String observedAt = '2026-09-14T18:00:01.000Z',
  String refreshAfter = '2026-09-14T18:00:16.000Z',
}) => jsonEncode(
  stockHistoryFixture(
    request: request,
    candles: candles,
    requestedAt: requestedAt,
    observedAt: observedAt,
    refreshAfter: refreshAfter,
  ),
);

StockHistoryPage parsedStockHistory({
  StockHistoryRequest request = stockHistoryRequest,
  List<Map<String, Object?>>? candles,
  String requestedAt = '2026-09-14T18:00:00.000Z',
  String observedAt = '2026-09-14T18:00:01.000Z',
  String refreshAfter = '2026-09-14T18:00:16.000Z',
}) => StockHistoryPage.parse(
  stockHistoryJson(
    request: request,
    candles: candles,
    requestedAt: requestedAt,
    observedAt: observedAt,
    refreshAfter: refreshAfter,
  ),
  request: request,
);
