import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/stock_history.dart';

import 'support/stock_history_fixtures.dart';

Matcher historyCode(String value) =>
    isA<StockResearchException>().having((error) => error.code, 'code', value);

void main() {
  test(
    'exact decimal lexemes and honest variant provenance survive parsing',
    () {
      final page = parsedStockHistory();
      final first = page.candles.first;
      expect(first.openRaw, '1.2300');
      expect(first.highRaw, '1.24e0');
      expect(first.closeRaw, '1.2300000000000000000000000000000000001');
      expect(first.volumeRaw, '90071992547409931234567890.00100');
      expect(page.candles.last.openRaw, '1e-80');
      expect(page.candles.last.volumeRaw, '0.000');
      expect(page.assetId, 'apple');
      expect(page.variantMint, stockHistoryAaplxMint);
      expect(page.providerContract, 'observed_not_execution_qualified');
      expect(page.historyKind, 'solana_mint_variant');
      expect(page.canonicalEquityHistory, isFalse);
      expect(page.priceUnit, 'provider_not_declared');
      expect(page.volumeUnit, 'provider_not_declared');
      expect(page.provenance.providerFreshness, 'not_reported');
      expect(page.provenance.providerCandleSource, 'not_exposed');
      expect(page.provenance.providerAsOf, isNull);
      expect(page.executionEnabled, isFalse);
      expect(page.eligibility, 'unverified');
      expect(() => page.candles.clear(), throwsUnsupportedError);
    },
  );

  test('request binds identity, canonical seconds, and a bounded window', () {
    expect(stockHistoryRequest.queryParameters, {
      'assetId': 'apple',
      'variantMint': stockHistoryAaplxMint,
      'interval': '1H',
      'fromUnixSeconds': stockHistoryFrom,
      'toUnixSeconds': stockHistoryTo,
    });
    final invalid = [
      const StockHistoryRequest(
        assetId: 'tesla',
        variantMint: stockHistoryAaplxMint,
        interval: StockHistoryInterval.oneHour,
        fromUnixSeconds: stockHistoryFrom,
        toUnixSeconds: stockHistoryTo,
      ),
      const StockHistoryRequest(
        assetId: stockHistoryAssetId,
        variantMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
        interval: StockHistoryInterval.oneHour,
        fromUnixSeconds: stockHistoryFrom,
        toUnixSeconds: stockHistoryTo,
      ),
      const StockHistoryRequest.appleAaplx(
        interval: StockHistoryInterval.oneHour,
        fromUnixSeconds: '01789344000',
        toUnixSeconds: stockHistoryTo,
      ),
      const StockHistoryRequest.appleAaplx(
        interval: StockHistoryInterval.oneHour,
        fromUnixSeconds: stockHistoryFrom,
        toUnixSeconds: '1792026001',
      ),
    ];
    for (final request in invalid) {
      expect(
        () => request.validateAt(1789408800),
        throwsA(historyCode('STOCK_HISTORY_INPUT_INVALID')),
      );
    }
  });

  test(
    'extra, duplicate, numeric, and mismatched response fields fail closed',
    () {
      final extra = stockHistoryFixture()..['futureField'] = true;
      final numericProviderValue = stockHistoryFixture();
      ((numericProviderValue['candles'] as List).first as Map)['openRaw'] =
          1.23;
      final wrongSource = stockHistoryFixture();
      (wrongSource['provenance'] as Map)['sourceUrl'] =
          'https://api.tokens.xyz/v1/assets/apple/ohlcv'
          '?mint=$stockHistoryAaplxMint&interval=4H'
          '&from=$stockHistoryFrom&to=$stockHistoryTo';
      final falseExecution = stockHistoryFixture()..['executionEnabled'] = true;
      for (final fixture in [
        extra,
        numericProviderValue,
        wrongSource,
        falseExecution,
      ]) {
        expect(
          () => StockHistoryPage.parse(
            jsonEncode(fixture),
            request: stockHistoryRequest,
          ),
          throwsA(historyCode('STOCK_HISTORY_RESPONSE_INVALID')),
        );
      }

      final duplicate = stockHistoryJson().replaceFirst(
        '{',
        '{"provider":"tokens-xyz-v1",',
      );
      expect(
        () => StockHistoryPage.parse(duplicate, request: stockHistoryRequest),
        throwsA(historyCode('STOCK_HISTORY_RESPONSE_INVALID')),
      );
      final futureSchema = stockHistoryJson().replaceFirst(
        '"schemaVersion":1',
        '"schemaVersion":1.0',
      );
      expect(
        () =>
            StockHistoryPage.parse(futureSchema, request: stockHistoryRequest),
        throwsA(historyCode('STOCK_UNSUPPORTED_SCHEMA')),
      );
    },
  );

  test(
    'ordering, alignment, range, decimal, and OHLC invariants fail closed',
    () {
      final cases = <List<Map<String, Object?>>>[
        [
          stockHistoryCandleFixture(startUnixSeconds: '1789347600'),
          stockHistoryCandleFixture(startUnixSeconds: stockHistoryFrom),
        ],
        [stockHistoryCandleFixture(startUnixSeconds: '1789344001')],
        [stockHistoryCandleFixture(startUnixSeconds: '1789354800')],
        [stockHistoryCandleFixture(highRaw: '1.2299')],
        [stockHistoryCandleFixture(lowRaw: '1.2301')],
        [stockHistoryCandleFixture(openRaw: '0')],
        [stockHistoryCandleFixture(volumeRaw: '-1')],
        [stockHistoryCandleFixture(volumeRaw: '01')],
        [stockHistoryCandleFixture(volumeRaw: '1e101')],
      ];
      for (final candles in cases) {
        expect(
          () => StockHistoryPage.parse(
            stockHistoryJson(candles: candles),
            request: stockHistoryRequest,
          ),
          throwsA(historyCode('STOCK_HISTORY_RESPONSE_INVALID')),
        );
      }
    },
  );

  test('freshness and empty-provider ambiguity are exact contract fields', () {
    final empty = StockHistoryPage.parse(
      stockHistoryJson(candles: const []),
      request: stockHistoryRequest,
    );
    expect(empty.dataStatus, 'empty_provider_cache_or_no_trades');
    expect(
      empty.provenance.isFreshAt(DateTime.parse('2026-09-14T18:00:15Z')),
      isTrue,
    );
    expect(
      empty.provenance.isFreshAt(DateTime.parse('2026-09-14T18:00:16Z')),
      isFalse,
    );
    for (final value in [
      stockHistoryJson(refreshAfter: '2026-09-14T18:00:15.999Z'),
      stockHistoryJson(observedAt: '2026-09-14T17:59:59.999Z'),
      stockHistoryJson(requestedAt: '2026-02-30T18:00:00.000Z'),
    ]) {
      expect(
        () => StockHistoryPage.parse(value, request: stockHistoryRequest),
        throwsA(historyCode('STOCK_HISTORY_RESPONSE_INVALID')),
      );
    }
  });

  test('server errors require the route status matrix and exact envelope', () {
    const matrix = <int, Set<String>>{
      400: {'STOCK_HISTORY_INPUT_INVALID'},
      429: {'STOCK_HISTORY_RATE_LIMITED'},
      502: {
        'STOCK_HISTORY_PROVIDER_UNAVAILABLE',
        'STOCK_HISTORY_RESPONSE_INVALID',
      },
      503: {'STOCK_HISTORY_UNAVAILABLE', 'STOCK_HISTORY_PROVIDER_AUTH_FAILED'},
      504: {'STOCK_HISTORY_TIMEOUT'},
    };
    for (final entry in matrix.entries) {
      for (final code in entry.value) {
        expect(
          parseStockHistoryServerError(
            jsonEncode({
              'error': {
                'code': code,
                'message': 'Safe public message.',
                'requestId': 'request-id',
              },
            }),
            entry.key,
          ),
          code,
        );
      }
    }
    for (final value in [
      (502, 'STOCK_HISTORY_TIMEOUT'),
      (504, 'STOCK_HISTORY_PROVIDER_UNAVAILABLE'),
    ]) {
      expect(
        () => parseStockHistoryServerError(
          jsonEncode({
            'error': {
              'code': value.$2,
              'message': 'Safe public message.',
              'requestId': 'request-id',
            },
          }),
          value.$1,
        ),
        throwsA(historyCode('STOCK_HISTORY_SERVICE_UNAVAILABLE')),
      );
    }
  });
}
