import 'dart:async';

import 'package:flutter/foundation.dart';

import 'market_facts.dart';
import 'market_research_gateway.dart';
import 'stock_facts.dart';

/// Wraps the discovery search with card facts: daily change and a logo for
/// each result. Discovery still owns identity, variants and prices. When the
/// facts read fails the plain results still show, with their facts missing.
final class FactsSearchGateway extends ChangeNotifier
    implements MarketSearchGateway {
  FactsSearchGateway({required this.inner, required this.facts}) {
    inner.addListener(_innerChanged);
  }

  final MarketSearchGateway inner;
  final MarketFactsController facts;
  final _cards = <String, Map<String, StockCardFacts>>{};
  final _pending = <String>{};
  String? _lastQuery;
  bool _disposed = false;

  @override
  MarketSearchSnapshot get snapshot {
    final base = inner.snapshot;
    final cards = _cards[base.query];
    return MarketSearchSnapshot(
      phase: base.phase,
      query: base.query,
      companies: List.unmodifiable(
        base.companies.map((company) {
          final enriched = facts.enrich(company);
          final card = cards?[company.assetId];
          return card == null ? enriched : applyCardFacts(enriched, card);
        }),
      ),
      message: base.message,
    );
  }

  @override
  Future<void> search(String query) async {
    _lastQuery = query;
    await inner.search(query);
    if (_disposed) return;
    unawaited(_loadCards(query));
  }

  Future<void> _loadCards(String query) async {
    if (query.isEmpty ||
        _cards.containsKey(query) ||
        _pending.contains(query)) {
      return;
    }
    _pending.add(query);
    try {
      final page = await facts.cards(query, limit: 20);
      if (_disposed || page == null) return;
      _cards[query] = {for (final row in page.results) row.assetId: row};
      while (_cards.length > 24) {
        _cards.remove(_cards.keys.first);
      }
      if (query == _lastQuery) notifyListeners();
    } finally {
      _pending.remove(query);
    }
  }

  @override
  void cancel() => inner.cancel();

  void _innerChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    inner.removeListener(_innerChanged);
    super.dispose();
  }
}
