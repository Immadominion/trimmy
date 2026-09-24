import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/raydium_quotes.dart';

import 'support/raydium_quote_fixtures.dart';

Matcher quoteFailure(String value) =>
    isA<StockResearchException>().having((error) => error.code, 'code', value);

Map<String, Object?> objectAt(Map<String, Object?> value, String key) =>
    value[key]! as Map<String, Object?>;

void main() {
  test(
    'parses the pinned buy projection and keeps all quantities as strings',
    () {
      final quote = RaydiumStockQuote.parse(
        raydiumQuoteJson(
          estimatedAmountRaw: '9007199254740993',
          minimumAmountRaw: '9007199254740993',
          feeAmountRaw: '18446744073709551615',
          feeMint: raydiumQuoteAaplxMint,
        ),
        request: raydiumBuyRequest,
      );

      expect(quote.request, raydiumBuyRequest);
      expect(quote.provider, 'raydium-trade-api');
      expect(quote.network, 'solana:mainnet-beta');
      expect(quote.comparisonOnly, isTrue);
      expect(quote.executable, isFalse);
      expect(quote.executionEnabled, isFalse);
      expect(quote.walletChecked, isFalse);
      expect(quote.networkFees, isNull);
      expect(quote.input.symbol, 'USDC');
      expect(quote.input.mint, raydiumQuoteUsdcMint);
      expect(quote.input.decimals, 6);
      expect(quote.input.amountRaw, '10000000');
      expect(quote.output.symbol, 'AAPLx');
      expect(quote.output.mint, raydiumQuoteAaplxMint);
      expect(quote.output.decimals, 8);
      expect(quote.output.estimatedAmountRaw, '9007199254740993');
      expect(quote.route.hops.single.fee.amountRaw, '18446744073709551615');
      expect(quote.route.hops, isA<List<RaydiumQuoteHop>>());
      expect(
        () => quote.route.hops.add(quote.route.hops.single),
        throwsUnsupportedError,
      );
      expect(
        quote.isFreshAt(DateTime.parse('2026-09-14T18:00:09.999Z')),
        isTrue,
      );
      expect(
        quote.isFreshAt(DateTime.parse('2026-09-14T18:00:10.000Z')),
        isFalse,
      );
    },
  );

  test('sell reverses only the pinned AAPLx and USDC direction', () {
    final payload = raydiumQuotePayload(request: raydiumSellRequest);
    objectAt(payload, 'input')['providerActualAmountRaw'] = null;
    final quote = parsedRaydiumQuote(
      request: raydiumSellRequest,
      payload: payload,
    );
    expect(quote.side, RaydiumQuoteSide.sell);
    expect(quote.input.symbol, 'AAPLx');
    expect(quote.input.mint, raydiumQuoteAaplxMint);
    expect(quote.input.decimals, 8);
    expect(quote.output.symbol, 'USDC');
    expect(quote.output.mint, raydiumQuoteUsdcMint);
    expect(quote.output.decimals, 6);
    expect(quote.input.providerActualAmountRaw, isNull);
    expect(quote.route.hops.single.inputMint, raydiumQuoteAaplxMint);
    expect(quote.route.hops.single.outputMint, raydiumQuoteUsdcMint);
  });

  test('request rejects substitute identity and non-canonical raw inputs', () {
    for (final request in [
      const RaydiumQuoteRequest(
        assetId: 'tesla',
        variantMint: raydiumQuoteAaplxMint,
        side: RaydiumQuoteSide.buy,
        amountRaw: '1',
      ),
      const RaydiumQuoteRequest(
        assetId: raydiumQuoteAssetId,
        variantMint: raydiumQuoteUsdcMint,
        side: RaydiumQuoteSide.buy,
        amountRaw: '1',
      ),
      for (final raw in [
        '0',
        '01',
        '-1',
        '1.0',
        '1e7',
        '100000001',
        '18446744073709551616',
      ])
        RaydiumQuoteRequest.appleAaplx(
          side: RaydiumQuoteSide.buy,
          amountRaw: raw,
        ),
    ]) {
      expect(request.validate, throwsA(quoteFailure('MARKET_INPUT_INVALID')));
    }
  });

  test('strict schema enforces binding, direction, route, and freshness', () {
    final cases = <Map<String, Object?>>[];

    final extra = raydiumQuotePayload()..['transaction'] = 'forbidden';
    cases.add(extra);

    final wrongSide = raydiumQuotePayload()..['side'] = 'sell';
    cases.add(wrongSide);

    final wrongInput = raydiumQuotePayload();
    objectAt(wrongInput, 'input')['mint'] = raydiumQuoteAaplxMint;
    cases.add(wrongInput);

    final numericRaw = raydiumQuotePayload();
    objectAt(numericRaw, 'output')['estimatedAmountRaw'] = 2978849;
    cases.add(numericRaw);

    final looseMinimum = raydiumQuotePayload();
    objectAt(looseMinimum, 'output')['quotedMinimumAmountRaw'] = '2900000';
    cases.add(looseMinimum);

    final route = raydiumQuotePayload();
    final hops = objectAt(route, 'route')['hops']! as List<Object?>;
    (hops.single as Map<String, Object?>)['inputMint'] = raydiumQuoteAaplxMint;
    cases.add(route);

    final timestamp = raydiumQuotePayload()
      ..['refreshAfter'] = '2026-09-14T18:00:11.000Z';
    cases.add(timestamp);

    for (final payload in cases) {
      expect(
        () => RaydiumStockQuote.fromJson(payload, request: raydiumBuyRequest),
        throwsA(quoteFailure('RAYDIUM_QUOTE_RESPONSE_INVALID')),
      );
    }
  });

  test('future schema versions fail with a distinct fixed code', () {
    final payload = raydiumQuotePayload()..['schemaVersion'] = 2;
    expect(
      () => RaydiumStockQuote.fromJson(payload, request: raydiumBuyRequest),
      throwsA(quoteFailure('RAYDIUM_QUOTE_UNSUPPORTED_SCHEMA')),
    );
  });
}
