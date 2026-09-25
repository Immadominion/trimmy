import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/discovery.dart';
import 'package:trimmy/product/market/market_facts.dart';
import 'package:trimmy/product/market/market_models.dart';
import 'package:trimmy/product/market/stock_facts.dart';

import 'stock_facts_models_test.dart' as fixtures;
import 'product/market/market_variant_test_support.dart';
import 'product/market/market_test_support.dart' show testMint;

final class _FakeRepository implements StockFactsRepository {
  _FakeRepository(this.handler);
  final Future<StockFacts> Function(String assetId) handler;
  int calls = 0;

  @override
  Future<StockCardsPage> cards(String query, {int limit = 10}) async =>
      StockCardsPage.fromJson(fixtures.cardsPage());

  @override
  Future<StockFacts> facts(String assetId) {
    calls++;
    return handler(assetId);
  }
}

StockDiscoveryAsset asset() => StockDiscoveryAsset.fromJson({
  'assetId': 'apple',
  'name': 'Apple',
  'symbol': 'AAPL',
  'category': 'equity',
  'providerPrimaryVariantMint': null,
  'variants': <Object?>[],
  'advisories': <Object?>[],
});

void main() {
  test('every enrichment copy preserves the chosen issuer mint', () async {
    final company = twoVariantCompany().withVariant(testMint);
    expect(company.asset.providerPrimaryVariantMint, otherIssuerMint);
    final controller = MarketFactsController(
      repository: _FakeRepository(
        (_) async => StockFacts.fromJson(fixtures.facts()),
      ),
    );
    addTearDown(controller.dispose);
    final copies = [
      MarketFactsController.applyBrandColor(company),
      applyCardFacts(company, StockCardFacts.fromJson(fixtures.card())),
      applyStockFacts(company, StockFacts.fromJson(fixtures.facts())),
      controller.enrich(company),
    ];
    await controller.load('apple');
    copies.add(controller.enrich(company));
    for (final copy in copies) {
      expect(copy.preferredVariantMint, testMint);
      expect(copy.primaryVariant?.mint, testMint);
      expect(copy.asset, same(company.asset));
    }
  });

  test(
    'facts are loaded once, shared while in flight and applied to a company',
    () async {
      var now = DateTime.utc(2026, 9, 20, 15, 0, 30);
      final repository = _FakeRepository(
        (_) async => StockFacts.fromJson(fixtures.facts()),
      );
      final controller = MarketFactsController(
        repository: repository,
        now: () => now,
      );
      final first = controller.load('apple');
      final second = controller.load('apple');
      expect(controller.phase('apple'), MarketFactsPhase.loading);
      expect(await first, isNotNull);
      expect(await second, isNotNull);
      expect(repository.calls, 1);
      expect(controller.phase('apple'), MarketFactsPhase.ready);
      final company = controller.enrich(MarketCompany.fromDiscovery(asset()));
      expect(company.description, 'Apple designs phones and computers.');
      expect(company.dayChangePercent, isNull);
      expect(company.weekTrend, [331.2, 333.0]);
      expect(company.logoUrl, 'https://api.tokens.xyz/logos/xstocks/AAPLx.png');
      expect(company.brandColor, marketCardColor('apple'));
      await controller.load('apple');
      expect(repository.calls, 1, reason: 'fresh facts are not reloaded');
      now = DateTime.utc(2026, 9, 20, 15, 2);
      await controller.load('apple');
      expect(repository.calls, 2, reason: 'expired facts reload');
    },
  );

  test('a failure keeps the old facts and waits before trying again', () async {
    var now = DateTime.utc(2026, 9, 20, 15, 0, 30);
    var fail = false;
    final repository = _FakeRepository((_) async {
      if (fail) throw const StockFactsException(StockFactsFailure.unavailable);
      return StockFacts.fromJson(fixtures.facts());
    });
    final controller = MarketFactsController(
      repository: repository,
      now: () => now,
    );
    await controller.load('apple');
    fail = true;
    now = DateTime.utc(2026, 9, 20, 15, 2);
    final kept = await controller.load('apple');
    expect(kept?.description, 'Apple designs phones and computers.');
    expect(repository.calls, 2);
    expect(controller.phase('apple'), MarketFactsPhase.ready);
    await controller.load('apple');
    expect(repository.calls, 2, reason: 'held after a failure');
    now = now.add(const Duration(seconds: 31));
    await controller.load('apple');
    expect(repository.calls, 3);
    final fresh = MarketFactsController(repository: repository, now: () => now);
    expect(await fresh.load('tesla'), isNull);
    expect(fresh.phase('tesla'), MarketFactsPhase.failed);
    expect(
      fresh.enrich(MarketCompany.fromDiscovery(asset())).description,
      isNull,
    );
  });

  test(
    'card facts apply change and logo without touching identity or price',
    () {
      final company = MarketCompany.fromDiscovery(asset());
      final card = StockCardFacts.fromJson(fixtures.card());
      final applied = applyCardFacts(company, card);
      expect(applied.asset, same(company.asset));
      expect(applied.priceUsd, company.priceUsd);
      expect(applied.dayChangePercent, isNull);
      expect(applied.logoUrl, 'https://api.tokens.xyz/logos/xstocks/AAPLx.png');
      expect(applied.description, isNull);
      final other = StockCardFacts.fromJson(
        fixtures.card({'assetId': 'tesla'}),
      );
      expect(applyCardFacts(company, other), same(company));
    },
  );

  test('card colours are deterministic and drawn from the paper palette', () {
    expect(marketCardColor('apple'), marketCardColor('apple'));
    expect(marketCardPalette, contains(marketCardColor('tesla')));
    expect(marketCardColor('apple'), isA<Color>());
  });
}
