import 'package:flutter/foundation.dart';

import '../../markets/discovery.dart';
import '../../markets/stock_research_controller.dart';
import 'market_models.dart';

enum MarketSearchPhase { idle, loading, ready, stale, offline, paused, error }

@immutable
final class MarketSearchSnapshot {
  const MarketSearchSnapshot({
    required this.phase,
    required this.query,
    required this.companies,
    this.message,
  });

  const MarketSearchSnapshot.idle()
    : phase = MarketSearchPhase.idle,
      query = '',
      companies = const <MarketCompany>[],
      message = null;

  final MarketSearchPhase phase;
  final String query;
  final List<MarketCompany> companies;
  final String? message;
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
      message: _message(state.phase, state.errorCode),
    );
  }

  static String? _message(StockResearchReadPhase phase, String? code) {
    if (phase == StockResearchReadPhase.stale) {
      return 'These results are old. Search again for a newer list.';
    }
    if (phase == StockResearchReadPhase.offline) {
      return 'You are offline. Check your connection and try again.';
    }
    if (phase == StockResearchReadPhase.background ||
        phase == StockResearchReadPhase.cancelled) {
      return 'The search paused. Try again.';
    }
    if (phase != StockResearchReadPhase.error &&
        phase != StockResearchReadPhase.disabled &&
        phase != StockResearchReadPhase.closed) {
      return null;
    }
    return switch (code) {
      'STOCK_RATE_LIMITED' => 'Too many searches. Wait a moment and try again.',
      'STOCK_TIMEOUT' => 'The search took too long. Try again.',
      'STOCK_RESEARCH_RUNTIME_OFFLINE' || 'STOCK_NETWORK_ERROR' =>
        'You are offline. Check your connection and try again.',
      'STOCK_RESEARCH_RUNTIME_DISABLED' =>
        'Company search is not available in this build.',
      _ => 'Company search is unavailable. Try again.',
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
