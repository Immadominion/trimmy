import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'support/stock_research_fixtures.dart';

void main() {
  test(
    'frozen real backend buy and sell responses retain raw units and expire as display estimates',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/support/stock_estimates_2026_09_14.json',
                ).readAsStringSync(),
              )
              as Map;
      final buy = StockEstimate.fromJson(fixture['buy']);
      final sell = StockEstimate.fromJson(fixture['sell']);
      expect(buy.output.estimatedAmountRaw, sell.input.amountRaw);
      expect(buy.output.estimatedAmountRaw, '2972350');
      expect(sell.output.estimatedAmountRaw, '9967990');
      for (final estimate in [buy, sell]) {
        expect(
          estimate.needsRefresh(DateTime.parse('2026-09-15T00:00:00Z')),
          isTrue,
        );
        expect(estimate.executable, isFalse);
        expect(estimate.amountUnits, 'raw_token_units');
        expect(estimate.swapFeeBasisPoints, 10);
      }
    },
  );

  test(
    'discovery preserves provenance, undeclared timestamp units and immutable metadata',
    () {
      final data = stockSearchFixture();
      final page = StockSearchPage.fromJson(data);
      final variant = page.results.single.variants.single;
      expect(variant.issuer, 'Backed');
      expect(variant.providerRedemptionTier, 'provider_description_only');
      expect(variant.market!.providerTimestamps['asOf'], 1789400000);
      expect(
        variant.market!.providerTimestamps['lastFetchedAt'],
        1789400000000,
      );
      expect(variant.market!.timestampUnit, 'not_declared');
      expect(page.provenance.providerFreshness, 'not_verified');
      expect(page.provenance.mintVerification, 'not_checked');
      expect(page.provenance.executionEnabled, isFalse);
      expect(page.completeCatalog, isFalse);
      (data['results'] as List).clear();
      expect(page.results.single.assetId, 'apple');
      expect(() => page.results.clear(), throwsUnsupportedError);
      expect(
        () => variant.market!.providerTimestamps.clear(),
        throwsUnsupportedError,
      );
      expect(
        page.provenance.needsRefresh(DateTime.parse('2026-09-14T18:01:00Z')),
        isTrue,
      );
    },
  );

  test(
    'unknown advisory remains visible and flagged siblings are retained',
    () {
      final data = stockSearchFixture();
      final asset = (data['results'] as List).single as Map;
      final advisory = {
        'status': 'future_restriction',
        'providerStatus': 'future_restriction',
        'reason': 'Provider reports a new restriction.',
        'since': '2026-09-14T17:00:00.000Z',
      };
      ((asset['variants'] as List).single as Map)['advisory'] = {...advisory};
      asset['advisories'] = [
        {...advisory, 'mint': researchAaplxMint, 'variantId': 'apple-xstock'},
        {...advisory, 'mint': researchUsdcMint, 'variantId': 'omitted-sibling'},
      ];
      final parsed = StockSearchPage.fromJson(data).results.single;
      expect(
        parsed.variants.single.advisory!.status,
        StockAdvisoryStatus.unknown,
      );
      expect(parsed.variants.single.advisory!.wireStatus, 'future_restriction');
      expect(parsed.advisories.last.variantId, 'omitted-sibling');
      ((asset['advisories'] as List).first as Map)['reason'] =
          'Contradictory flag';
      expect(
        () => StockSearchPage.fromJson(data),
        throwsA(isA<StockResearchException>()),
      );
    },
  );

  test(
    'malformed catalog claims, duplicates, primary mints and dates do not become research data',
    () {
      final cases = <Map<String, Object?>>[
        {...stockSearchFixture(), 'executionEnabled': true},
        {...stockSearchFixture(), 'eligibility': 'approved'},
        {...stockSearchFixture(), 'refreshAfter': '2026-09-15T18:00:00.000Z'},
        {...stockSearchFixture(), 'completeCatalog': true},
        {...stockSearchFixture(), 'observedAt': '2026-02-30T18:00:00.000Z'},
        {...stockSearchFixture(), 'refreshAfter': '2026-09-14T18:00:00.000Z'},
        {...stockSearchFixture(), 'sourceUrl': 'https://secret@example.com'},
      ];
      for (final data in cases) {
        expect(
          () => StockSearchPage.fromJson(data),
          throwsA(isA<StockResearchException>()),
        );
      }
      final duplicate = stockVariantsFixture();
      (duplicate['variants'] as List).add(stockVariantFixture());
      expect(
        () => StockVariantsPage.fromJson(duplicate),
        throwsA(isA<StockResearchException>()),
      );
      final invalidPrimary = stockSearchFixture();
      ((invalidPrimary['results'] as List).single
              as Map)['providerPrimaryVariantMint'] =
          researchUsdcMint;
      expect(
        () => StockSearchPage.fromJson(invalidPrimary),
        throwsA(isA<StockResearchException>()),
      );
    },
  );

  test(
    'exact raw strings survive both directions without implying scaled shares',
    () {
      for (final side in StockEstimateSide.values) {
        final result = StockEstimate.fromJson(stockEstimateFixture(side: side));
        expect(result.request.side, side);
        expect(result.output.estimatedAmountRaw, '18446744073709551615');
        expect(result.output.quotedMinimumAmountRaw, '18446744073709551614');
        expect(result.amountUnits, 'raw_token_units');
        expect(result.executable, isFalse);
        expect(result.walletChecked, isFalse);
        expect(result.networkFees, isNull);
        expect(result.eligibility, 'unverified');
      }
      expect(
        formatRawTokenUnits('18446744073709551615', 8),
        '184467440737.09551615',
      );
      expect(formatRawTokenUnits('1', 8), '0.00000001');
    },
  );

  test(
    'raw floats, leading zeroes, overflow and incoherent thresholds or pair labels are rejected',
    () {
      for (final raw in [
        1.5,
        100,
        '01',
        '0',
        '-1',
        '1e3',
        '18446744073709551616',
        '100000001',
        '100\n',
      ]) {
        final data = stockEstimateFixture();
        (data['input'] as Map)['amountRaw'] = raw;
        expect(
          () => StockEstimate.fromJson(data),
          throwsA(isA<StockResearchException>()),
        );
      }
      final lowMinimum = stockEstimateFixture();
      (lowMinimum['output'] as Map)['quotedMinimumAmountRaw'] = '1';
      expect(
        () => StockEstimate.fromJson(lowMinimum),
        throwsA(isA<StockResearchException>()),
      );
      final falseFreshness = stockEstimateFixture()
        ..['refreshAfter'] = '2026-09-15T18:00:00.000Z';
      expect(
        () => StockEstimate.fromJson(falseFreshness),
        throwsA(isA<StockResearchException>()),
      );
      final wrongDecimals = stockEstimateFixture();
      (wrongDecimals['output'] as Map)['decimals'] = 6;
      expect(
        () => StockEstimate.fromJson(wrongDecimals),
        throwsA(isA<StockResearchException>()),
      );
      final wrongSymbol = stockEstimateFixture();
      (wrongSymbol['output'] as Map)['symbol'] = 'AAPL';
      expect(
        () => StockEstimate.fromJson(wrongSymbol),
        throwsA(isA<StockResearchException>()),
      );
    },
  );

  test(
    'future schema or unmodeled token extensions cannot silently become an estimate',
    () {
      expect(
        () => StockEstimate.fromJson({
          ...stockEstimateFixture(),
          'schemaVersion': 2,
        }),
        throwsA(
          isA<StockResearchException>().having(
            (e) => e.code,
            'code',
            'STOCK_UNSUPPORTED_SCHEMA',
          ),
        ),
      );
      expect(
        () => StockEstimate.fromJson({
          ...stockEstimateFixture(),
          'extensions': [
            {'kind': 'FutureRestriction'},
          ],
        }),
        throwsA(isA<StockResearchException>()),
      );
      final variant = stockVariantFixture()
        ..['extensions'] = ['UnknownTransferPolicy'];
      expect(
        () => StockVariant.fromJson(variant),
        throwsA(isA<StockResearchException>()),
      );
    },
  );
}
