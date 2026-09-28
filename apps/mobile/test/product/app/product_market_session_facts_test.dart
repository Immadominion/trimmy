import 'dart:async';
import 'package:trimmy/product/market/market_catalog.dart';
import '../market/market_test_support.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'package:trimmy/product/app/product_market_session.dart';
import 'package:trimmy/product/market/market.dart';

import '../../stock_facts_models_test.dart' as facts_fixtures;
import '../../support/stock_research_fixtures.dart';

final class _Discovery implements StockResearchClient {
  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) async =>
      StockSearchPage.fromJson(stockSearchFixture(query: query, limit: limit));

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('unused');

  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('unused');
}

final class _UnusedHistory implements StockHistoryClient {
  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('unused');
}

final class _UnusedRaydium implements RaydiumQuoteClient {
  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) async => throw StateError('unused');
}

final class _Facts implements StockFactsRepository {
  _Facts({this.failCards = false});

  final bool failCards;
  int cardCalls = 0;
  int detailCalls = 0;

  @override
  Future<StockCardsPage> cards(String query, {int limit = 10}) async {
    cardCalls++;
    if (failCards) {
      throw const StockFactsException(StockFactsFailure.unavailable);
    }
    final payload = facts_fixtures.cardsPage()
      ..['query'] = query
      ..['limit'] = limit;
    return StockCardsPage.fromJson(payload);
  }

  @override
  Future<StockFacts> facts(String assetId) async {
    detailCalls++;
    return StockFacts.fromJson(facts_fixtures.facts());
  }
}

final class _HeldTimer implements Timer {
  var _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

({
  StockResearchController research,
  MarketFactsController facts,
  ProductMarketSession session,
})
_runtime(_Facts repository, {MarketCatalogGateway? catalog}) {
  final research = StockResearchController.withClients(
    researchClient: _Discovery(),
    historyClient: _UnusedHistory(),
    raydiumClient: _UnusedRaydium(),
    clock: () => DateTime.parse('2026-09-14T18:00:02.000Z'),
    timerFactory: (delay, callback) => _HeldTimer(),
  );
  final facts = MarketFactsController(repository: repository);
  return (
    research: research,
    facts: facts,
    session: ProductMarketSession(research, facts: facts, catalog: catalog),
  );
}

void main() {
  test(
    'held company refreshes a missing image without losing discovery offline',
    () async {
      final catalog = _Catalog();
      final runtime = _runtime(_Facts(), catalog: catalog);
      addTearDown(runtime.session.dispose);
      addTearDown(runtime.facts.dispose);
      addTearDown(runtime.research.dispose);
      await runtime.session.loadCatalog();
      catalog.found = MarketCompany(
        asset: testCompany(assetId: 'nvidia').asset,
        logoUrl: 'https://example.test/nvidia.png',
      );
      expect(
        (await runtime.session.findCompany('nvidia'))?.logoUrl,
        'https://example.test/nvidia.png',
      );
      catalog.fail = true;
      expect((await runtime.session.findCompany('nvidia'))?.assetId, 'nvidia');
    },
  );

  test(
    'catalog paginates, retains rows on failure, and leaves intro picks separate',
    () async {
      final catalog = _Catalog();
      final runtime = _runtime(_Facts(), catalog: catalog);
      addTearDown(runtime.session.dispose);
      addTearDown(runtime.facts.dispose);
      addTearDown(runtime.research.dispose);
      await runtime.session.loadStarterPicks();
      await runtime.session.loadCatalog();
      expect(runtime.session.starterCompanies.single.assetId, 'apple');
      expect(runtime.session.companies.single.assetId, 'nvidia');
      catalog.fail = true;
      await runtime.session.loadMore();
      expect(runtime.session.companies.length, 1);
      expect(runtime.session.hasMore, true);
      expect(runtime.session.loadMoreMessage, isNotNull);
      catalog.fail = false;
      await runtime.session.loadMore();
      expect(runtime.session.companies.map((c) => c.assetId), [
        'nvidia',
        'tesla',
      ]);
      expect(runtime.session.hasMore, false);
      expect(runtime.session.loadMoreMessage, isNull);
      await runtime.session.loadCatalog();
      expect(runtime.session.companies.length, 1);
    },
  );

  test(
    'loading more reads several pages at once and keeps their order',
    () async {
      final catalog = _Catalog(total: 200);
      final runtime = _runtime(_Facts(), catalog: catalog);
      addTearDown(runtime.session.dispose);
      addTearDown(runtime.facts.dispose);
      addTearDown(runtime.research.dispose);
      await runtime.session.loadCatalog();
      catalog.failing.add(80);
      await runtime.session.loadMore();
      expect(catalog.offsets, [0, 20, 40, 60, 80]);
      expect(runtime.session.companies.map((c) => c.assetId), [
        'company-0',
        'company-20',
        'company-40',
        'company-60',
      ]);
      expect(runtime.session.loadMoreMessage, isNotNull);
      catalog.failing.clear();
      await runtime.session.loadMore();
      await runtime.session.loadMore();
      await runtime.session.loadMore();
      expect(runtime.session.companies.length, 10);
      expect(runtime.session.companies.last.assetId, 'company-180');
      expect(runtime.session.hasMore, false);
      expect(runtime.session.loadMoreMessage, isNull);
      expect(catalog.offsets.where((offset) => offset >= 200), isEmpty);
    },
  );

  test('starter picks use one cards read and never preload full facts', () async {
    final repository = _Facts();
    final runtime = _runtime(repository);
    addTearDown(runtime.session.dispose);
    addTearDown(runtime.facts.dispose);
    addTearDown(runtime.research.dispose);

    await runtime.session.loadStarterPicks();
    await Future<void>.delayed(Duration.zero);

    expect(runtime.session.status, MarketPageStatus.ready);
    expect(runtime.session.companies, isNotEmpty);
    expect(repository.cardCalls, 1);
    expect(repository.detailCalls, 0);
    final apple = runtime.session.companies.firstWhere(
      (company) => company.assetId == 'apple',
    );
    expect(
      apple.dayChangePercent,
      closeTo(-0.26, 1e-9),
      reason:
          'Compare the token price with its token change, not the underlying stock session',
    );
    expect(apple.logoUrl, 'https://api.tokens.xyz/logos/xstocks/AAPLx.png');

    await runtime.session.loadStarterPicks();
    await Future<void>.delayed(Duration.zero);
    expect(repository.cardCalls, 1, reason: 'successful card facts are cached');
    expect(repository.detailCalls, 0);
  });

  test('a card facts failure leaves discovery picks usable', () async {
    final repository = _Facts(failCards: true);
    final runtime = _runtime(repository);
    addTearDown(runtime.session.dispose);
    addTearDown(runtime.facts.dispose);
    addTearDown(runtime.research.dispose);

    await runtime.session.loadStarterPicks();
    await Future<void>.delayed(Duration.zero);

    expect(runtime.session.status, MarketPageStatus.ready);
    expect(runtime.session.companies, isNotEmpty);
    expect(repository.cardCalls, 1);
    expect(repository.detailCalls, 0);
    expect(
      runtime.session.companies
          .firstWhere((company) => company.assetId == 'apple')
          .priceUsd,
      isNotNull,
    );
  });
}

final class _Catalog implements MarketCatalogGateway {
  _Catalog({this.total = 22});

  final int total;
  bool fail = false;
  final failing = <int>{};
  final offsets = <int>[];
  MarketCompany? found;
  @override
  Future<MarketCatalogPage> load({int offset = 0}) async {
    offsets.add(offset);
    if (fail || failing.contains(offset)) throw StateError('offline');
    if (total == 22) {
      return MarketCatalogPage(
        [
          testCompany(assetId: 'nvidia'),
          if (offset > 0) testCompany(assetId: 'tesla'),
        ],
        22,
        offset == 0 ? 20 : null,
      );
    }
    final next = offset + 20;
    return MarketCatalogPage(
      [testCompany(assetId: 'company-$offset')],
      total,
      next < total ? next : null,
    );
  }

  @override
  void close() {}
  @override
  Future<MarketCompany?> find(String assetId) async {
    if (fail) throw StateError('offline');
    return found;
  }
}
