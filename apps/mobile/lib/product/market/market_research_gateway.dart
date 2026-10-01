import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';
import '../../markets/discovery.dart';
import '../../markets/stock_research_controller.dart';
import 'market_models.dart';

enum MarketSearchPhase { idle, loading, ready, stale, offline, paused, error }

/// What a search screen tells the player about the last search, as a code so
/// the words follow the app's language when they are shown.
enum MarketSearchNotice {
  stale,
  offline,
  paused,
  rateLimited,
  timeout,
  disabled,
  unavailable;

  String message(AppLocalizations l10n) => switch (this) {
    MarketSearchNotice.stale => l10n.marketSearchStale,
    MarketSearchNotice.offline => l10n.marketSearchOffline,
    MarketSearchNotice.paused => l10n.marketSearchPaused,
    MarketSearchNotice.rateLimited => l10n.marketSearchRateLimited,
    MarketSearchNotice.timeout => l10n.marketSearchTimeout,
    MarketSearchNotice.disabled => l10n.marketSearchDisabled,
    MarketSearchNotice.unavailable => l10n.marketSearchUnavailable,
  };
}

@immutable
final class MarketSearchSnapshot {
  const MarketSearchSnapshot({
    required this.phase,
    required this.query,
    required this.companies,
    this.notice,
  });

  const MarketSearchSnapshot.idle()
    : phase = MarketSearchPhase.idle,
      query = '',
      companies = const <MarketCompany>[],
      notice = null;

  final MarketSearchPhase phase;
  final String query;
  final List<MarketCompany> companies;
  final MarketSearchNotice? notice;

  /// [notice] in the reader's language. Screens use this.
  String? noticeText(AppLocalizations l10n) => notice?.message(l10n);

  /// [notice] in English, for callers that have not moved to [noticeText].
  String? get message => notice?.message(englishLocalizations);
}

abstract interface class MarketSearchGateway implements Listenable {
  MarketSearchSnapshot get snapshot;
  Future<void> search(String query);
  void cancel();
}

/// A presentation adapter over the existing read-only market controller.
///
/// It owns no controller lifecycle and adds no trading authority. Search
/// results keep their [StockDiscoveryAsset] identity and provider variants.
final class StockResearchSearchGateway implements MarketSearchGateway {
  const StockResearchSearchGateway(this.controller);

  final StockResearchController controller;

  @override
  MarketSearchSnapshot get snapshot {
    final state = controller.discoveryState.search;
    final page = state.data;
    return MarketSearchSnapshot(
      phase: switch (state.phase) {
        StockResearchReadPhase.idle ||
        StockResearchReadPhase.disabled => MarketSearchPhase.idle,
        StockResearchReadPhase.loading => MarketSearchPhase.loading,
        StockResearchReadPhase.ready => MarketSearchPhase.ready,
        StockResearchReadPhase.stale => MarketSearchPhase.stale,
        StockResearchReadPhase.offline => MarketSearchPhase.offline,
        StockResearchReadPhase.background ||
        StockResearchReadPhase.cancelled ||
        StockResearchReadPhase.closed => MarketSearchPhase.paused,
        StockResearchReadPhase.error => MarketSearchPhase.error,
      },
      query:
          page?.query ??
          (state.requestKey is (String, int)
              ? (state.requestKey! as (String, int)).$1
              : ''),
      companies: List.unmodifiable(
        page?.results.map(MarketCompany.fromDiscovery) ?? const [],
      ),
      notice: _notice(state.phase, state.errorCode),
    );
  }

  static MarketSearchNotice? _notice(
    StockResearchReadPhase phase,
    String? code,
  ) {
    if (phase == StockResearchReadPhase.stale) {
      return MarketSearchNotice.stale;
    }
    if (phase == StockResearchReadPhase.offline) {
      return MarketSearchNotice.offline;
    }
    if (phase == StockResearchReadPhase.background ||
        phase == StockResearchReadPhase.cancelled) {
      return MarketSearchNotice.paused;
    }
    if (phase != StockResearchReadPhase.error &&
        phase != StockResearchReadPhase.disabled &&
        phase != StockResearchReadPhase.closed) {
      return null;
    }
    return switch (code) {
      'STOCK_RATE_LIMITED' => MarketSearchNotice.rateLimited,
      'STOCK_TIMEOUT' => MarketSearchNotice.timeout,
      'STOCK_RESEARCH_RUNTIME_OFFLINE' ||
      'STOCK_NETWORK_ERROR' => MarketSearchNotice.offline,
      'STOCK_RESEARCH_RUNTIME_DISABLED' => MarketSearchNotice.disabled,
      _ => MarketSearchNotice.unavailable,
    };
  }

  @override
  Future<void> search(String query) => controller.search(query, limit: 20);

  @override
  void cancel() {
    // The existing controller exposes only cancelAll(), which would also stop
    // a chart or quote owned by another route. A cleared search is ignored by
    // the search page, and a later query supersedes it safely.
  }

  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      controller.removeListener(listener);
}
