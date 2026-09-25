import 'dart:async';

import 'package:flutter/material.dart';

import 'market_models.dart';
import 'stock_facts.dart';

/// Six soft card colours, chosen by asset id so cards differ without
/// pretending to know a brand. Decoration, not a fact about the company.
const marketCardPalette = <Color>[
  Color(0xFFE7E0FA),
  Color(0xFFDDEFE5),
  Color(0xFFFFF1C2),
  Color(0xFFFFE2D6),
  Color(0xFFDCEBFA),
  Color(0xFFF8E1E8),
];

Color marketCardColor(String assetId) {
  var hash = 0;
  for (final unit in assetId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return marketCardPalette[hash % marketCardPalette.length];
}

/// Copies a company with card facts applied. Identity, variants and the
/// provider price always stay with the discovery asset.
MarketCompany applyCardFacts(MarketCompany company, StockCardFacts facts) {
  if (facts.assetId != company.assetId) return company;
  return MarketCompany(
    asset: company.asset,
    preferredVariantMint: company.preferredVariantMint,
    logoUrl: facts.logoUrl ?? company.logoUrl,
    description: company.description,
    sector: company.sector,
    priceUsd: company.priceUsd,
    dayChangePercent: facts.primaryVariant?.mint == company.primaryVariant?.mint
        ? facts.primaryVariant?.changePercent24h ?? company.dayChangePercent
        : company.dayChangePercent,
    asOf: company.asOf,
    weekTrend: company.weekTrend,
    floorHolders: company.floorHolders,
    friendFaces: company.friendFaces,
    lists: company.lists,
    brandColor: marketCardColor(company.assetId),
  );
}

/// Copies a company with full facts applied: description and sparkline too.
MarketCompany applyStockFacts(MarketCompany company, StockFacts facts) {
  if (facts.assetId != company.assetId) return company;
  return MarketCompany(
    asset: company.asset,
    preferredVariantMint: company.preferredVariantMint,
    logoUrl: facts.imageUrl ?? company.logoUrl,
    description: facts.description ?? company.description,
    sector: company.sector,
    priceUsd: company.priceUsd,
    dayChangePercent: company.dayChangePercent,
    asOf: company.asOf,
    weekTrend: facts.sparkline.length >= 2 ? facts.closes : company.weekTrend,
    floorHolders: company.floorHolders,
    friendFaces: company.friendFaces,
    lists: company.lists,
    brandColor: marketCardColor(company.assetId),
  );
}

enum MarketFactsPhase { idle, loading, ready, failed }

/// Loads and remembers company facts for the session. Facts expire at the
/// server's refresh time; a failed read waits before it is tried again. The
/// controller never blocks trading and never invents a fact while loading.
final class MarketFactsController extends ChangeNotifier {
  MarketFactsController({
    required this.repository,
    DateTime Function()? now,
    this.failureHold = const Duration(seconds: 30),
    this.maxEntries = 96,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final StockFactsRepository repository;
  final DateTime Function() _now;
  final Duration failureHold;
  final int maxEntries;
  final _facts = <String, StockFacts>{};
  final _failedUntil = <String, DateTime>{};
  final _inFlight = <String, Future<StockFacts?>>{};
  bool _disposed = false;

  StockFacts? peek(String assetId) {
    final facts = _facts[assetId];
    if (facts == null) return null;
    if (!_now().isBefore(facts.refreshAfter)) return facts;
    return facts;
  }

  MarketFactsPhase phase(String assetId) {
    if (_inFlight.containsKey(assetId)) return MarketFactsPhase.loading;
    if (_facts.containsKey(assetId)) return MarketFactsPhase.ready;
    final failedUntil = _failedUntil[assetId];
    if (failedUntil != null && _now().isBefore(failedUntil)) {
      return MarketFactsPhase.failed;
    }
    return MarketFactsPhase.idle;
  }

  /// Returns cached facts when fresh, otherwise loads them once. Concurrent
  /// callers share one request. A failure is remembered briefly and returns
  /// null; the caller keeps showing what it already had.
  Future<StockFacts?> load(String assetId, {bool force = false}) {
    if (_disposed) return Future.value(null);
    final cached = _facts[assetId];
    if (!force && cached != null && _now().isBefore(cached.refreshAfter)) {
      return Future.value(cached);
    }
    final failedUntil = _failedUntil[assetId];
    if (!force && failedUntil != null && _now().isBefore(failedUntil)) {
      return Future.value(cached);
    }
    final pending = _inFlight[assetId];
    if (pending != null) return pending;
    final request = _fetch(assetId, cached);
    _inFlight[assetId] = request;
    notifyListeners();
    return request;
  }

  Future<StockFacts?> _fetch(String assetId, StockFacts? previous) async {
    try {
      final facts = await repository.facts(assetId);
      if (_disposed) return facts;
      _failedUntil.remove(assetId);
      _facts[assetId] = facts;
      _trim();
      return facts;
    } on StockFactsException catch (error) {
      if (_disposed) return previous;
      final hold = error.retryAfter ?? failureHold;
      _failedUntil[assetId] = _now().add(hold);
      return previous;
    } catch (_) {
      if (_disposed) return previous;
      _failedUntil[assetId] = _now().add(failureHold);
      return previous;
    } finally {
      _inFlight.remove(assetId);
      if (!_disposed) notifyListeners();
    }
  }

  /// One card search; the server does the caching. Failures return null so
  /// the plain discovery list still renders.
  Future<StockCardsPage?> cards(String query, {int limit = 10}) async {
    if (_disposed) return null;
    try {
      return await repository.cards(query, limit: limit);
    } on StockFactsException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Applies every fact this controller knows to a list of companies.
  List<MarketCompany> enrichAll(Iterable<MarketCompany> companies) =>
      List.unmodifiable(companies.map(enrich));

  MarketCompany enrich(MarketCompany company) {
    final facts = _facts[company.assetId];
    return facts == null
        ? company.brandColor == marketCardPalette.first
              ? applyBrandColor(company)
              : company
        : applyStockFacts(company, facts);
  }

  static MarketCompany applyBrandColor(MarketCompany company) => MarketCompany(
    asset: company.asset,
    preferredVariantMint: company.preferredVariantMint,
    logoUrl: company.logoUrl,
    description: company.description,
    sector: company.sector,
    priceUsd: company.priceUsd,
    dayChangePercent: company.dayChangePercent,
    asOf: company.asOf,
    weekTrend: company.weekTrend,
    floorHolders: company.floorHolders,
    friendFaces: company.friendFaces,
    lists: company.lists,
    brandColor: marketCardColor(company.assetId),
  );

  void _trim() {
    while (_facts.length > maxEntries) {
      _facts.remove(_facts.keys.first);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _facts.clear();
    _failedUntil.clear();
    _inFlight.clear();
    super.dispose();
  }
}
