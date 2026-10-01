import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';
import '../../markets/discovery.dart';
import '../../markets/stock_research_controller.dart';
import '../market/market.dart';
import '../market/market_catalog.dart';

/// Why stocks could not load. Kept as a code so the message is written in the
/// reader's language when it is shown.
enum ProductMarketIssue {
  loadMoreFailed,
  catalogFailed,
  noStarterPicks,
  notConfigured,
  busy,
  timeout,
  offline,
  unavailable;

  String message(AppLocalizations l10n) => switch (this) {
    loadMoreFailed => l10n.appMarketLoadMoreFailed,
    catalogFailed => l10n.appMarketCatalogFailed,
    noStarterPicks => l10n.appMarketNoStarterPicks,
    notConfigured => l10n.appMarketNotConfigured,
    busy => l10n.appMarketBusy,
    timeout => l10n.appMarketTimeout,
    offline => l10n.appMarketOffline,
    unavailable => l10n.appMarketUnavailable,
  };
}

/// Keeps the launch picks stable while full-screen search uses the same public
/// market runtime for independent queries.
final class ProductMarketSession extends ChangeNotifier {
  ProductMarketSession(
    this.controller, {
    MarketFactsController? facts,
    this.catalog,
  }) : facts = facts,
       search = facts == null
           ? StockResearchSearchGateway(controller)
           : FactsSearchGateway(
               inner: StockResearchSearchGateway(controller),
               facts: facts,
             ),
       recents = MarketRecentsController() {
    facts?.addListener(_factsChanged);
  }

  final StockResearchController controller;
  final MarketCatalogGateway? catalog;
  List<MarketCompany> _catalogCompanies = const [];
  MarketPageStatus _catalogStatus = MarketPageStatus.loading;
  ProductMarketIssue? _catalogIssue;
  bool _catalogLoading = false;
  int? _nextOffset;
  int _total = 0;
  bool _loadingMore = false;
  ProductMarketIssue? _loadMoreIssue;
  int get total => _total;
  bool get hasMore => _nextOffset != null;
  bool get loadingMore => _loadingMore;
  ProductMarketIssue? get loadMoreIssue => _loadMoreIssue;

  Future<MarketCompany?> findCompany(String assetId) async {
    final known = [
      ...companies,
      ...starterCompanies,
      ...recents.companies,
    ].where((c) => c.assetId == assetId).firstOrNull;
    if (known?.logoUrl?.isNotEmpty == true || catalog == null) return known;
    // A discovery row may arrive before its image. Let held assets refresh
    // that optional metadata instead of keeping the initial letter forever.
    try {
      return await catalog!.find(assetId) ?? known;
    } catch (_) {
      if (known != null) return known;
      rethrow;
    }
  }

  Future<void> loadMore() async {
    final offset = _nextOffset;
    if (_disposed ||
        _catalogLoading ||
        _loadingMore ||
        offset == null ||
        catalog == null) {
      return;
    }
    _loadingMore = true;
    _loadMoreIssue = null;
    notifyListeners();
    try {
      // Filtered provider pages can skip offsets. Always follow its cursor.
      final page = await catalog!.load(offset: offset);
      if (_disposed) return;
      final existing = _catalogCompanies.map((c) => c.assetId).toSet();
      _catalogCompanies = List.unmodifiable([
        ..._catalogCompanies,
        ...page.companies.where((company) => existing.add(company.assetId)),
      ]);
      _total = page.total;
      _nextOffset = page.nextOffset;
      _applyFacts();
    } catch (_) {
      if (!_disposed) {
        _loadMoreIssue = ProductMarketIssue.loadMoreFailed;
      }
    } finally {
      _loadingMore = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Optional company facts: daily change, logo, description and sparkline.
  /// The picks render without them and fill in as each read lands.
  final MarketFactsController? facts;
  final MarketSearchGateway search;
  final MarketRecentsController recents;

  List<MarketCompany> _picks = const [];
  List<MarketCompany> _companies = const [];
  Map<String, StockCardFacts> _starterCards = const {};
  MarketPageStatus _status = MarketPageStatus.loading;
  ProductMarketIssue? _issue;
  bool _loading = false;
  bool _starterCardsLoading = false;
  bool _starterCardsLoaded = false;
  bool _disposed = false;

  List<MarketCompany> get companies =>
      catalog == null ? _companies : _catalogCompanies;
  List<MarketCompany> get starterCompanies => _companies;
  MarketPageStatus get starterStatus => _status;
  ProductMarketIssue? get starterIssue => _issue;
  MarketPageStatus get status => catalog == null ? _status : _catalogStatus;
  ProductMarketIssue? get issue => catalog == null ? _issue : _catalogIssue;

  Future<void> loadCatalog() async {
    if (catalog == null) return loadStarterPicks();
    if (_disposed || _catalogLoading || _loadingMore) return;
    _catalogLoading = true;
    _catalogStatus = MarketPageStatus.loading;
    _catalogIssue = null;
    notifyListeners();
    try {
      final page = await catalog!.load();
      if (_disposed) return;
      _catalogCompanies = page.companies;
      _nextOffset = page.nextOffset;
      _total = page.total;
      _loadMoreIssue = null;
      _catalogStatus = MarketPageStatus.ready;
    } catch (_) {
      if (!_disposed) {
        _catalogStatus = MarketPageStatus.error;
        _catalogIssue = ProductMarketIssue.catalogFailed;
      }
    } finally {
      _catalogLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadStarterPicks() async {
    if (_loading || _loadingMore || _disposed) return;
    _loading = true;
    _status = MarketPageStatus.loading;
    _issue = null;
    notifyListeners();
    try {
      await controller.search('a', limit: 20);
      if (_disposed) return;
      final first = controller.discoveryState.search;
      if ((first.phase == StockResearchReadPhase.error ||
              first.phase == StockResearchReadPhase.offline) &&
          const {
            'STOCK_TIMEOUT',
            'STOCK_NETWORK_ERROR',
            'STOCK_PROVIDER_UNAVAILABLE',
          }.contains(first.errorCode)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (_disposed) return;
        if (controller.state.phase == StockResearchRuntimePhase.active) {
          await controller.search('a', limit: 20);
        }
      }
      if (_disposed) return;
      final state = controller.discoveryState.search;
      final page = state.data;
      if (page == null ||
          state.phase != StockResearchReadPhase.ready &&
              state.phase != StockResearchReadPhase.stale) {
        _status = state.phase == StockResearchReadPhase.offline
            ? MarketPageStatus.offline
            : MarketPageStatus.error;
        _issue = _marketIssue(state.errorCode);
        return;
      }
      const preferred = ['apple', 'tesla', 'meta'];
      final available = page.results
          .where(
            (asset) =>
                asset.variants.isNotEmpty &&
                asset.variants.any(
                  (variant) => variant.market?.priceUsd != null,
                ),
          )
          .toList();
      final picked = <StockDiscoveryAsset>[];
      for (final id in preferred) {
        for (final asset in available) {
          if (asset.assetId == id && !picked.contains(asset)) picked.add(asset);
        }
      }
      for (final asset in available) {
        if (picked.length >= 3) break;
        if (!picked.contains(asset)) picked.add(asset);
      }
      _picks = List.unmodifiable(
        picked
            .take(3)
            .map(
              (asset) => MarketCompany.fromDiscovery(
                asset,
                asOf: DateTime.tryParse(page.provenance.observedAt),
                lists: const {MarketList.starterPicks},
              ),
            ),
      );
      _applyFacts();
      _status = MarketPageStatus.ready;
      unawaited(_loadStarterCards());
      _issue = _companies.isEmpty ? ProductMarketIssue.noStarterPicks : null;
    } catch (_) {
      if (_disposed) return;
      final phase = controller.discoveryState.search.phase;
      _status = phase == StockResearchReadPhase.offline
          ? MarketPageStatus.offline
          : MarketPageStatus.error;
      _issue = _marketIssue(controller.discoveryState.search.errorCode);
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  ProductMarketIssue _marketIssue(String? code) => switch (code) {
    'STOCK_RESEARCH_RUNTIME_DISABLED' => ProductMarketIssue.notConfigured,
    'STOCK_RATE_LIMITED' => ProductMarketIssue.busy,
    'STOCK_TIMEOUT' => ProductMarketIssue.timeout,
    'STOCK_RESEARCH_RUNTIME_OFFLINE' ||
    'STOCK_NETWORK_ERROR' => ProductMarketIssue.offline,
    _ => ProductMarketIssue.unavailable,
  };

  void _applyFacts() {
    final facts = this.facts;
    _companies = List.unmodifiable(
      _picks.map((company) {
        final enriched = facts?.enrich(company) ?? company;
        final card = _starterCards[company.assetId];
        return card == null ? enriched : applyCardFacts(enriched, card);
      }),
    );
  }

  Future<void> _loadStarterCards() async {
    final facts = this.facts;
    if (facts == null ||
        _disposed ||
        _picks.isEmpty ||
        _starterCardsLoading ||
        _starterCardsLoaded) {
      return;
    }
    _starterCardsLoading = true;
    try {
      final page = await facts.cards('a', limit: 20);
      if (_disposed || page == null) return;
      _starterCards = {for (final row in page.results) row.assetId: row};
      _starterCardsLoaded = true;
      _applyFacts();
      notifyListeners();
    } finally {
      _starterCardsLoading = false;
    }
  }

  void _factsChanged() {
    if (_disposed || _picks.isEmpty) return;
    _applyFacts();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    facts?.removeListener(_factsChanged);
    if (search case final FactsSearchGateway gateway) gateway.dispose();
    catalog?.close();
    recents.dispose();
    super.dispose();
  }
}
