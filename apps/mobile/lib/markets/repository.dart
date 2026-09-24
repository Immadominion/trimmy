// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import 'client.dart';
import 'discovery.dart';
import 'estimate.dart';
import 'validation.dart';

typedef StockResearchClock = DateTime Function();

enum StockResearchPhase {
  idle,
  loading,
  ready,
  stale,
  offline,
  error,
  cancelled,
}

/// Immutable channel state whose freshness cannot outlive its deadline.
final class StockResearchState<T> {
  StockResearchState({
    StockResearchPhase phase = StockResearchPhase.idle,
    StockResearchClock? clock,
    this.requestKey,
    this.data,
    String? errorCode,
    this.refreshAfter,
    this.staleErrorCode = 'STOCK_DATA_STALE',
  }) : _phase = phase,
       _clock = clock ?? DateTime.now,
       _errorCode = errorCode;

  final StockResearchPhase _phase;
  final StockResearchClock _clock;
  final String? _errorCode;
  final Object? requestKey;
  final T? data;

  /// A fixed application code; raw server diagnostics never enter state.
  final String staleErrorCode;
  final DateTime? refreshAfter;

  StockResearchPhase get phase {
    if (_phase != StockResearchPhase.ready || data == null) return _phase;
    final freshness = _freshness();
    if (!freshness.clockValid) return StockResearchPhase.error;
    return freshness.fresh
        ? StockResearchPhase.ready
        : StockResearchPhase.stale;
  }

  String? get errorCode {
    if (_phase != StockResearchPhase.ready || data == null) return _errorCode;
    final freshness = _freshness();
    if (!freshness.clockValid) return 'STOCK_INVALID_CONFIGURATION';
    return freshness.fresh ? _errorCode : staleErrorCode;
  }

  bool get hasRetainedData => data != null && phase != StockResearchPhase.ready;

  bool needsRefresh(DateTime now) {
    try {
      return data != null &&
          (hasRetainedData ||
              refreshAfter != null && !now.toUtc().isBefore(refreshAfter!));
    } catch (_) {
      return true;
    }
  }

  ({bool clockValid, bool fresh}) _freshness() {
    try {
      final now = _clock().toUtc();
      if (now.year < 1 || now.year > 9999) {
        return (clockValid: false, fresh: false);
      }
      final deadline = refreshAfter;
      return (
        clockValid: true,
        fresh: deadline != null && now.isBefore(deadline.toUtc()),
      );
    } catch (_) {
      return (clockValid: false, fresh: false);
    }
  }
}

final class _Channel<T> {
  _Channel(StockResearchClock clock, this.staleErrorCode)
    : state = StockResearchState<T>(
        clock: clock,
        staleErrorCode: staleErrorCode,
      );

  final String staleErrorCode;
  StockResearchState<T> state;
  var generation = 0;
  StockResearchCancellation? cancellation;
}

/// In-memory research state. Searches, variants and estimates have independent
/// cancellation/generations. No automatic retries or persisted financial data.
class StockResearchRepository extends ChangeNotifier {
  StockResearchRepository({
    required StockResearchClient client,
    StockResearchClock? now,
  }) : _client = client,
       _now = now ?? DateTime.now,
       _search = _Channel<StockSearchPage>(
         now ?? DateTime.now,
         'STOCK_TIMEOUT',
       ),
       _variants = _Channel<StockVariantsPage>(
         now ?? DateTime.now,
         'STOCK_TIMEOUT',
       ),
       _estimate = _Channel<StockEstimate>(
         now ?? DateTime.now,
         'MARKET_ESTIMATE_STALE',
       );

  final StockResearchClient _client;
  final StockResearchClock _now;
  final _Channel<StockSearchPage> _search;
  final _Channel<StockVariantsPage> _variants;
  final _Channel<StockEstimate> _estimate;
  bool _disposed = false;
  bool _online = true;

  StockResearchState<StockSearchPage> get searchState => _search.state;
  StockResearchState<StockVariantsPage> get variantsState => _variants.state;
  StockResearchState<StockEstimate> get estimateState => _estimate.state;
  bool get networkAvailable => _online;

  Future<void> search(String query, {int limit = 10}) => _load(
    _search,
    (query, limit),
    (cancellation) =>
        _client.search(query, limit: limit, cancellation: cancellation),
    (page) => page.provenance.refreshAfter,
    'STOCK_TIMEOUT',
  );

  Future<void> loadVariants(String assetId) => _load(
    _variants,
    assetId,
    (cancellation) => _client.variants(assetId, cancellation: cancellation),
    (page) => page.provenance.refreshAfter,
    'STOCK_TIMEOUT',
  );

  Future<void> estimate(StockEstimateRequest request) => _load(
    _estimate,
    request,
    (cancellation) => _client.estimate(request, cancellation: cancellation),
    (result) => result.refreshAfter,
    'MARKET_ESTIMATE_STALE',
  );

  Future<void> _load<T>(
    _Channel<T> channel,
    Object key,
    Future<T> Function(StockResearchCancellation) load,
    String Function(T) refresh,
    String staleCode,
  ) async {
    if (_disposed) {
      throw const StockResearchException('STOCK_REPOSITORY_CLOSED');
    }

    // A broken injected/system clock is configuration failure and must fail
    // before an HTTP call can spend quota.
    _requireClock();
    channel.cancellation?.cancel();
    final generation = ++channel.generation;
    final old = channel.state;
    final retained = old.requestKey == key ? old.data : null;
    final deadline = retained == null ? null : old.refreshAfter;
    if (!_online) {
      channel.state = _state(
        channel,
        StockResearchPhase.offline,
        requestKey: key,
        data: retained,
        refreshAfter: deadline,
        errorCode: 'STOCK_NETWORK_ERROR',
      );
      notifyListeners();
      return;
    }
    final cancellation = StockResearchCancellation();
    channel.cancellation = cancellation;
    channel.state = _state(
      channel,
      StockResearchPhase.loading,
      requestKey: key,
      data: retained,
      refreshAfter: deadline,
    );
    notifyListeners();
    if (_disposed ||
        channel.generation != generation ||
        cancellation.isCancelled) {
      return;
    }
    try {
      final result = await load(cancellation);
      if (_disposed ||
          channel.generation != generation ||
          cancellation.isCancelled) {
        return;
      }
      final refreshAfter = DateTime.parse(refresh(result)).toUtc();
      if (!_requireClock().isBefore(refreshAfter)) {
        throw StockResearchException(staleCode);
      }
      channel.state = _state(
        channel,
        StockResearchPhase.ready,
        requestKey: key,
        data: result,
        refreshAfter: refreshAfter,
      );
    } catch (error) {
      if (_disposed || channel.generation != generation) return;
      final code = error is StockResearchException
          ? error.code
          : 'STOCK_NETWORK_ERROR';
      channel.state = _state(
        channel,
        code == 'STOCK_CANCELLED'
            ? StockResearchPhase.cancelled
            : code == 'STOCK_NETWORK_ERROR'
            ? StockResearchPhase.offline
            : StockResearchPhase.error,
        requestKey: key,
        data: retained,
        refreshAfter: deadline,
        errorCode: code,
      );
    }
    if (_disposed || channel.generation != generation) return;
    channel.cancellation = null;
    notifyListeners();
  }

  StockResearchState<T> _state<T>(
    _Channel<T> channel,
    StockResearchPhase phase, {
    required Object? requestKey,
    required T? data,
    required DateTime? refreshAfter,
    String? errorCode,
  }) => StockResearchState<T>(
    phase: phase,
    clock: _now,
    requestKey: requestKey,
    data: data,
    refreshAfter: refreshAfter,
    errorCode: errorCode,
    staleErrorCode: channel.staleErrorCode,
  );

  void cancelSearch() => _cancel(_search);
  void cancelVariants() => _cancel(_variants);
  void cancelEstimate() => _cancel(_estimate);

  void _cancel<T>(_Channel<T> channel) {
    if (_disposed || channel.state.phase != StockResearchPhase.loading) return;
    ++channel.generation;
    channel.cancellation?.cancel();
    channel.cancellation = null;
    final old = channel.state;
    channel.state = _state(
      channel,
      StockResearchPhase.cancelled,
      requestKey: old.requestKey,
      data: old.data,
      refreshAfter: old.refreshAfter,
      errorCode: 'STOCK_CANCELLED',
    );
    notifyListeners();
  }

  /// Optional foreground/connectivity signal. Reconnection does not retry or
  /// consume provider quota without another explicit request.
  void setNetworkAvailable(bool available) {
    if (_disposed || _online == available) return;
    _online = available;
    if (!available) {
      _markOffline(_search);
      _markOffline(_variants);
      _markOffline(_estimate);
    }
    notifyListeners();
  }

  void _markOffline<T>(_Channel<T> channel) {
    if (channel.state.phase == StockResearchPhase.idle) return;
    ++channel.generation;
    channel.cancellation?.cancel();
    channel.cancellation = null;
    final old = channel.state;
    channel.state = _state(
      channel,
      StockResearchPhase.offline,
      requestKey: old.requestKey,
      data: old.data,
      refreshAfter: old.refreshAfter,
      errorCode: 'STOCK_NETWORK_ERROR',
    );
  }

  DateTime _readClock() {
    try {
      final value = _now().toUtc();
      if (value.year < 1 || value.year > 9999) {
        throw const StockResearchException('STOCK_INVALID_CONFIGURATION');
      }
      return value;
    } on StockResearchException {
      rethrow;
    } catch (_) {
      throw const StockResearchException('STOCK_INVALID_CONFIGURATION');
    }
  }

  DateTime _requireClock() {
    try {
      return _readClock();
    } on StockResearchException {
      _invalidateClock();
      rethrow;
    }
  }

  void _invalidateClock() {
    if (_disposed) return;
    _markClockInvalid(_search);
    _markClockInvalid(_variants);
    _markClockInvalid(_estimate);
    notifyListeners();
  }

  void _markClockInvalid<T>(_Channel<T> channel) {
    ++channel.generation;
    channel.cancellation?.cancel();
    channel.cancellation = null;
    final old = channel.state;
    channel.state = _state(
      channel,
      StockResearchPhase.error,
      requestKey: old.requestKey,
      data: old.data,
      refreshAfter: old.refreshAfter,
      errorCode: 'STOCK_INVALID_CONFIGURATION',
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _search.cancellation?.cancel();
    _variants.cancellation?.cancel();
    _estimate.cancellation?.cancel();
    super.dispose();
  }
}
