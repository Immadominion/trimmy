import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/discovery.dart';
import 'package:trimmy/product/market/market_facts.dart';
import 'package:trimmy/product/market/market_facts_gateway.dart';
import 'package:trimmy/product/market/market_models.dart';
import 'package:trimmy/product/market/market_research_gateway.dart';
import 'package:trimmy/product/market/stock_facts.dart';

import 'stock_facts_models_test.dart' as fixtures;

final class _FakeInner extends ChangeNotifier implements MarketSearchGateway {
  MarketSearchSnapshot _snapshot = const MarketSearchSnapshot.idle();
  final searches = <String>[];

  @override
  MarketSearchSnapshot get snapshot => _snapshot;

  @override
  Future<void> search(String query) async {
    searches.add(query);
    _snapshot = MarketSearchSnapshot(
      phase: MarketSearchPhase.ready,
      query: query,
      companies: [
        MarketCompany.fromDiscovery(_asset('apple')),
        MarketCompany.fromDiscovery(_asset('tesla')),
      ],
    );
    notifyListeners();
  }

  @override
  void cancel() {}
}

final class _FakeFacts implements StockFactsRepository {
  _FakeFacts({this.fail = false});
  bool fail;
  final cardCalls = <String>[];
  final gate = Completer<void>();

  @override
  Future<StockCardsPage> cards(String query, {int limit = 10}) async {
    cardCalls.add(query);
    await gate.future;
    if (fail) throw const StockFactsException(StockFactsFailure.unavailable);
    return StockCardsPage.fromJson(fixtures.cardsPage([fixtures.card()]));
  }

  @override
  Future<StockFacts> facts(String assetId) async =>
      throw const StockFactsException(StockFactsFailure.unavailable);
}

StockDiscoveryAsset _asset(String id) => StockDiscoveryAsset.fromJson({
  'assetId': id,
  'name': id,
  'symbol': id.toUpperCase(),
  'category': 'equity',
  'providerPrimaryVariantMint': null,
  'variants': <Object?>[],
  'advisories': <Object?>[],
});

void main() {
  test(
    'search results show first, then gain change and logo when the cards land',
    () async {
      final inner = _FakeInner();
      final repository = _FakeFacts();
      final gateway = FactsSearchGateway(
        inner: inner,
        facts: MarketFactsController(repository: repository),
      );
      var notified = 0;
      gateway.addListener(() => notified++);
      await gateway.search('apple');
      expect(repository.cardCalls, ['apple']);
      var snapshot = gateway.snapshot;
      expect(snapshot.companies.map((c) => c.assetId), ['apple', 'tesla']);
      expect(snapshot.companies.first.dayChangePercent, isNull);
      expect(snapshot.companies.first.brandColor, marketCardColor('apple'));
      final before = notified;
      repository.gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(notified, greaterThan(before));
      snapshot = gateway.snapshot;
      expect(snapshot.companies.first.dayChangePercent, isNull);
      expect(
        snapshot.companies.first.logoUrl,
        'https://api.tokens.xyz/logos/xstocks/AAPLx.png',
      );
      expect(
        snapshot.companies.last.dayChangePercent,
        isNull,
        reason: 'no card for tesla',
      );
      await gateway.search('apple');
      expect(repository.cardCalls, [
        'apple',
      ], reason: 'cards are remembered per query');
      gateway.dispose();
    },
  );

  test('a failed cards read leaves the plain results untouched', () async {
    final inner = _FakeInner();
    final repository = _FakeFacts(fail: true);
    final gateway = FactsSearchGateway(
      inner: inner,
      facts: MarketFactsController(repository: repository),
    );
    await gateway.search('apple');
    repository.gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.snapshot.companies.first.dayChangePercent, isNull);
    expect(gateway.snapshot.companies.length, 2);
    gateway.dispose();
  });
}
