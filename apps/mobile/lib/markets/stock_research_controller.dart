// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'client.dart';
import 'config.dart';
import 'discovery.dart';
import 'estimate.dart';
import 'history_client.dart';
import 'history_models.dart';
import 'history_repository.dart';
import 'raydium_quote_client.dart';
import 'raydium_quote_models.dart';
import 'raydium_quote_repository.dart';
import 'repository.dart';
import 'validation.dart';

typedef StockResearchRuntimeClock = DateTime Function();
typedef StockResearchRuntimeTimerFactory =
    Timer Function(Duration delay, void Function() callback);
typedef StockResearchHttpClientFactory = http.Client Function();

enum StockResearchRuntimePhase {
  disabled,
  active,
  background,
  offline,
  invalidConfiguration,
  closed,
}

enum StockResearchReadPhase {
  disabled,
  idle,
  loading,
  ready,
  stale,
  background,
  offline,
  error,
  cancelled,
  closed,
}

/// The complete authority surface of this runtime.
///
/// The negative capabilities are explicit so later composition cannot mistake
/// an indicative venue response for a transaction-ready result.
final class StockResearchRuntimeCapabilities {
  const StockResearchRuntimeCapabilities._();

  bool get publicReads => true;
  bool get walletAccess => false;
  bool get transactionConstruction => false;
  bool get simulation => false;
  bool get signing => false;
  bool get broadcast => false;
  bool get execution => false;
}

const stockResearchRuntimeCapabilities = StockResearchRuntimeCapabilities._();

/// Immutable, normalized state for one read channel.
///
/// A captured ready state checks its deadline when read. This keeps a quote or
/// history page from remaining visually ready if a platform timer is delayed.
final class StockResearchReadState<T> {
  const StockResearchReadState._({
    required StockResearchReadPhase phase,
    required StockResearchRuntimeClock clock,
    this.requestKey,
    this.data,
    this.refreshAfter,
    String? errorCode,
  }) : _phase = phase,
       _clock = clock,
       _errorCode = errorCode;

  final StockResearchReadPhase _phase;
  final StockResearchRuntimeClock _clock;
  final Object? requestKey;
  final T? data;
  final DateTime? refreshAfter;
  final String? _errorCode;

  StockResearchReadPhase get phase {
    if (_phase != StockResearchReadPhase.ready || data == null) return _phase;
    final freshness = _freshness();
    if (!freshness.clockValid) return StockResearchReadPhase.error;
    return freshness.fresh
        ? StockResearchReadPhase.ready
        : StockResearchReadPhase.stale;
  }

  String? get errorCode {
    if (_phase != StockResearchReadPhase.ready || data == null) {
      return _errorCode;
    }
    final freshness = _freshness();
    if (!freshness.clockValid) {
      return 'STOCK_RESEARCH_RUNTIME_CLOCK_INVALID';
    }
    return freshness.fresh ? _errorCode : 'STOCK_RESEARCH_DATA_STALE';
  }

  bool get isFresh => phase == StockResearchReadPhase.ready;
  bool get hasRetainedData =>
      data != null && phase != StockResearchReadPhase.ready;

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

final class StockDiscoveryRuntimeState {
  const StockDiscoveryRuntimeState._({
    required this.search,
    required this.variants,
  });

  final StockResearchReadState<StockSearchPage> search;
  final StockResearchReadState<StockVariantsPage> variants;
}

/// One immutable view of all independent public market readers.
final class StockResearchRuntimeState {
  const StockResearchRuntimeState._({
    required this.phase,
    required this.errorCode,
    required this.discovery,
    required this.jupiterEstimate,
    required this.tokensHistory,
    required this.raydiumComparison,
  });

  final StockResearchRuntimePhase phase;
  final String? errorCode;
  final StockDiscoveryRuntimeState discovery;
  final StockResearchReadState<StockEstimate> jupiterEstimate;
  final StockResearchReadState<StockHistoryPage> tokensHistory;
  final StockResearchReadState<RaydiumStockQuote> raydiumComparison;
}

final class _RuntimeFlight {
  _RuntimeFlight(this.key, this.interruption);

  final Object key;
  final Completer<void> interruption;
  late final Future<void> future;

  void interrupt() {
    if (!interruption.isCompleted) interruption.complete();
  }
}

final class _RuntimeChannel {
  _RuntimeFlight? flight;
}

/// Application-owned lifecycle for public stock research.
///
/// Discovery, Jupiter, Tokens history and Raydium remain independent. This
/// controller does not rank venues, choose a route, retry, or fetch in the
/// background. Every provider read begins at one of the explicit load methods.
final class StockResearchController extends ChangeNotifier {
  StockResearchController._disabled({required this.apiOrigin})
    : _research = null,
      _history = null,
      _raydium = null,
      _clock = DateTime.now,
      _timerFactory = Timer.new,
      _disposeTransports = null,
      _enabled = false;

  StockResearchController._configured({
    required StockResearchRepository research,
    required StockHistoryRepository history,
    required RaydiumQuoteRepository raydium,
    required StockResearchRuntimeClock clock,
    required StockResearchRuntimeTimerFactory timerFactory,
    required this.apiOrigin,
    void Function()? disposeTransports,
  }) : _research = research,
       _history = history,
       _raydium = raydium,
       _clock = clock,
       _timerFactory = timerFactory,
       _disposeTransports = disposeTransports,
       _enabled = true {
    research.addListener(_repositoryChanged);
    history.addListener(_repositoryChanged);
    raydium.addListener(_repositoryChanged);
  }

  /// Builds the production HTTP runtime. Empty configuration returns a
  /// disabled controller without constructing an HTTP client.
  factory StockResearchController.create({
    required StockResearchConfig config,
    StockResearchHttpClientFactory? httpClientFactory,
    StockResearchRuntimeClock? clock,
    StockResearchRuntimeTimerFactory? timerFactory,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) {
    final origin = config.apiUri;
    if (origin == null) {
      return StockResearchController._disabled(apiOrigin: null);
    }
    final runtimeClock = clock ?? DateTime.now;
    final runtimeTimers = timerFactory ?? Timer.new;
    final transport = (httpClientFactory ?? http.Client.new)();
    try {
      final researchClient = HttpStockResearchClient(
        client: transport,
        baseUri: origin,
        timeout: timeout,
        allowLoopbackForTests: allowLoopbackForTests,
      );
      final historyClient = HttpStockHistoryClient(
        client: transport,
        baseUri: origin,
        timeout: timeout,
        allowLoopbackForTests: allowLoopbackForTests,
        now: runtimeClock,
      );
      final raydiumClient = HttpRaydiumQuoteClient(
        client: transport,
        baseUri: origin,
        timeout: timeout,
        allowLoopbackForTests: allowLoopbackForTests,
      );
      return StockResearchController._configured(
        research: StockResearchRepository(
          client: researchClient,
          now: runtimeClock,
        ),
        history: StockHistoryRepository(
          client: historyClient,
          clock: runtimeClock,
          timerFactory: runtimeTimers,
        ),
        raydium: RaydiumQuoteRepository(
          client: raydiumClient,
          clock: runtimeClock,
          timerFactory: runtimeTimers,
        ),
        clock: runtimeClock,
        timerFactory: runtimeTimers,
        apiOrigin: origin,
        disposeTransports: () {
          researchClient.close();
          historyClient.close();
          raydiumClient.close();
          transport.close();
        },
      );
    } catch (_) {
      transport.close();
      rethrow;
    }
  }

  /// Dependency-injected construction for deterministic application tests.
  /// The controller owns and disposes the three repositories.
  factory StockResearchController.withClients({
    required StockResearchClient researchClient,
    required StockHistoryClient historyClient,
    required RaydiumQuoteClient raydiumClient,
    StockResearchRuntimeClock? clock,
    StockResearchRuntimeTimerFactory? timerFactory,
  }) {
    final runtimeClock = clock ?? DateTime.now;
    final runtimeTimers = timerFactory ?? Timer.new;
    return StockResearchController._configured(
      research: StockResearchRepository(
        client: researchClient,
        now: runtimeClock,
      ),
      history: StockHistoryRepository(
        client: historyClient,
        clock: runtimeClock,
        timerFactory: runtimeTimers,
      ),
      raydium: RaydiumQuoteRepository(
        client: raydiumClient,
        clock: runtimeClock,
        timerFactory: runtimeTimers,
      ),
      clock: runtimeClock,
      timerFactory: runtimeTimers,
      apiOrigin: null,
    );
  }

  final StockResearchRepository? _research;
  final StockHistoryRepository? _history;
  final RaydiumQuoteRepository? _raydium;
  final StockResearchRuntimeClock _clock;
  final StockResearchRuntimeTimerFactory _timerFactory;
  final void Function()? _disposeTransports;
  final bool _enabled;

  final Uri? apiOrigin;
  final _search = _RuntimeChannel();
  final _variants = _RuntimeChannel();
  final _jupiter = _RuntimeChannel();
  final _historyRead = _RuntimeChannel();
  final _raydiumRead = _RuntimeChannel();

  Timer? _expiryTimer;
  bool _foreground = true;
  bool _networkAvailable = true;
  bool _closed = false;
  bool _disposed = false;
  bool _schedulingExpiry = false;
  String? _configurationError;

  StockResearchRuntimeCapabilities get capabilities =>
      stockResearchRuntimeCapabilities;
  bool get enabled => _enabled;
  bool get isForeground => _foreground;
  bool get networkAvailable => _networkAvailable;

  StockResearchRuntimeState get state {
    final lifecycle = _lifecycle();
    return StockResearchRuntimeState._(
      phase: lifecycle.phase,
      errorCode: lifecycle.errorCode,
      discovery: StockDiscoveryRuntimeState._(
        search: _mapResearch(_research?.searchState, lifecycle),
        variants: _mapResearch(_research?.variantsState, lifecycle),
      ),
      jupiterEstimate: _mapResearch(_research?.estimateState, lifecycle),
      tokensHistory: _mapHistory(_history?.state, lifecycle),
      raydiumComparison: _mapRaydium(_raydium?.state, lifecycle),
    );
  }

  StockDiscoveryRuntimeState get discoveryState => state.discovery;
  StockResearchReadState<StockEstimate> get jupiterEstimateState =>
      state.jupiterEstimate;
  StockResearchReadState<StockHistoryPage> get tokensHistoryState =>
      state.tokensHistory;
  StockResearchReadState<RaydiumStockQuote> get raydiumComparisonState =>
      state.raydiumComparison;

  Future<void> search(String query, {int limit = 10}) => _read(_search, (
    query,
    limit,
  ), () => _research!.search(query, limit: limit));

  Future<void> loadVariants(String assetId) =>
      _read(_variants, assetId, () => _research!.loadVariants(assetId));

  Future<void> loadJupiterEstimate(StockEstimateRequest request) =>
      _read(_jupiter, request, () => _research!.estimate(request));

  Future<void> loadTokensHistory(StockHistoryRequest request) =>
      _read(_historyRead, request, () => _history!.load(request));

  Future<void> loadRaydiumComparison(RaydiumQuoteRequest request) =>
      _read(_raydiumRead, request, () => _raydium!.load(request));

  Future<void> _read(
    _RuntimeChannel channel,
    Object key,
    Future<void> Function() start,
  ) {
    final failure = _readFailure();
    if (failure != null) return Future<void>.error(failure);

    final current = channel.flight;
    if (current != null && current.key == key) return current.future;
    current?.interrupt();

    final interruption = Completer<void>();
    final flight = _RuntimeFlight(key, interruption);
    channel.flight = flight;
    final operation = Future<void>.sync(start);
    flight.future = Future.any<void>([operation, interruption.future])
        .whenComplete(() {
          if (identical(channel.flight, flight)) channel.flight = null;
        });
    return flight.future;
  }

  StockResearchException? _readFailure() {
    if (_closed || _disposed) {
      return const StockResearchException('STOCK_RESEARCH_RUNTIME_CLOSED');
    }
    if (!_enabled) {
      return const StockResearchException('STOCK_RESEARCH_RUNTIME_DISABLED');
    }
    if (!_foreground) {
      return const StockResearchException('STOCK_RESEARCH_RUNTIME_BACKGROUND');
    }
    if (!_networkAvailable) {
      return const StockResearchException('STOCK_RESEARCH_RUNTIME_OFFLINE');
    }
    final existingConfigurationError = _configurationError;
    if (existingConfigurationError != null) {
      _cancelOperations();
      notifyListeners();
      return StockResearchException(existingConfigurationError);
    }
    if (_safeNow() == null) {
      _configurationError = 'STOCK_RESEARCH_RUNTIME_CLOCK_INVALID';
      _cancelOperations();
      notifyListeners();
      return const StockResearchException(
        'STOCK_RESEARCH_RUNTIME_CLOCK_INVALID',
      );
    }
    return null;
  }

  /// Cancels active work when the app leaves the foreground. Returning to the
  /// foreground never consumes provider quota by itself.
  void setForeground(bool foreground) {
    if (_closed || _disposed || _foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _clearExpiry();
      _interruptFlights();
      _research?.cancelSearch();
      _research?.cancelVariants();
      _research?.cancelEstimate();
      _history?.cancel();
      _raydium?.cancel();
    } else {
      _rescheduleExpiry();
    }
    notifyListeners();
  }

  /// Applies connectivity to every reader. Reconnection only reclassifies
  /// retained data; another explicit load is required to perform HTTP.
  void setNetworkAvailable(bool available) {
    if (_closed || _disposed || _networkAvailable == available) return;
    _networkAvailable = available;
    if (!available) {
      _clearExpiry();
      _interruptFlights();
    }
    _research?.setNetworkAvailable(available);
    _history?.setNetworkAvailable(available);
    _raydium?.setNetworkAvailable(available);
    if (available && _foreground) _rescheduleExpiry();
    notifyListeners();
  }

  void cancelAll() {
    if (_closed || _disposed || !_enabled) return;
    _interruptFlights();
    _research?.cancelSearch();
    _research?.cancelVariants();
    _research?.cancelEstimate();
    _history?.cancel();
    _raydium?.cancel();
  }

  void close() => _shutdown(notify: true);

  void _repositoryChanged() {
    if (_closed || _disposed) return;
    _rescheduleExpiry();
    notifyListeners();
  }

  void _rescheduleExpiry() {
    _clearExpiry();
    if (!_enabled ||
        _closed ||
        _disposed ||
        !_foreground ||
        !_networkAvailable ||
        _configurationError != null) {
      return;
    }
    final now = _safeNow();
    if (now == null) {
      _configurationError = 'STOCK_RESEARCH_RUNTIME_CLOCK_INVALID';
      _cancelOperations();
      return;
    }
    final deadlines =
        <DateTime?>[
            _research?.searchState.refreshAfter,
            _research?.variantsState.refreshAfter,
            _research?.estimateState.refreshAfter,
            _history?.state.refreshAfter,
            _raydium?.state.refreshAfter,
          ].whereType<DateTime>().where((value) => value.isAfter(now)).toList()
          ..sort();
    if (deadlines.isEmpty) return;
    var firedSynchronously = false;
    try {
      _schedulingExpiry = true;
      final timer = _timerFactory(deadlines.first.difference(now), () {
        if (_schedulingExpiry) {
          firedSynchronously = true;
          return;
        }
        _expiryTimer = null;
        if (_closed || _disposed || !_foreground || !_networkAvailable) return;
        notifyListeners();
        _rescheduleExpiry();
      });
      _schedulingExpiry = false;
      if (firedSynchronously) {
        try {
          timer.cancel();
        } catch (_) {
          // The invalid timer is discarded below.
        }
        _configurationError = 'STOCK_RESEARCH_RUNTIME_TIMER_INVALID';
        _cancelOperations();
        return;
      }
      bool active;
      try {
        active = timer.isActive;
      } catch (_) {
        active = false;
      }
      if (!active) {
        try {
          timer.cancel();
        } catch (_) {
          // The invalid timer is discarded below.
        }
        _configurationError = 'STOCK_RESEARCH_RUNTIME_TIMER_INVALID';
        _cancelOperations();
        return;
      }
      _expiryTimer = timer;
    } catch (_) {
      _schedulingExpiry = false;
      _configurationError = 'STOCK_RESEARCH_RUNTIME_TIMER_INVALID';
      _cancelOperations();
    }
  }

  void _cancelOperations() {
    _clearExpiry();
    _interruptFlights();
    _research?.cancelSearch();
    _research?.cancelVariants();
    _research?.cancelEstimate();
    _history?.cancel();
    _raydium?.cancel();
  }

  void _interruptFlights() {
    for (final channel in [
      _search,
      _variants,
      _jupiter,
      _historyRead,
      _raydiumRead,
    ]) {
      channel.flight?.interrupt();
      channel.flight = null;
    }
  }

  ({StockResearchRuntimePhase phase, String? errorCode}) _lifecycle() {
    if (_closed || _disposed) {
      return (
        phase: StockResearchRuntimePhase.closed,
        errorCode: 'STOCK_RESEARCH_RUNTIME_CLOSED',
      );
    }
    if (!_enabled) {
      return (
        phase: StockResearchRuntimePhase.disabled,
        errorCode: 'STOCK_RESEARCH_RUNTIME_DISABLED',
      );
    }
    final configurationError = _configurationError;
    if (configurationError != null || _safeNow() == null) {
      return (
        phase: StockResearchRuntimePhase.invalidConfiguration,
        errorCode: configurationError ?? 'STOCK_RESEARCH_RUNTIME_CLOCK_INVALID',
      );
    }
    if (!_foreground) {
      return (
        phase: StockResearchRuntimePhase.background,
        errorCode: 'STOCK_RESEARCH_RUNTIME_BACKGROUND',
      );
    }
    if (!_networkAvailable) {
      return (
        phase: StockResearchRuntimePhase.offline,
        errorCode: 'STOCK_RESEARCH_RUNTIME_OFFLINE',
      );
    }
    return (phase: StockResearchRuntimePhase.active, errorCode: null);
  }

  StockResearchReadState<T> _mapResearch<T>(
    StockResearchState<T>? source,
    ({StockResearchRuntimePhase phase, String? errorCode}) lifecycle,
  ) {
    final overlay = _overlay(lifecycle);
    if (overlay != null || source == null) {
      return StockResearchReadState<T>._(
        phase: overlay ?? StockResearchReadPhase.disabled,
        clock: _clock,
        requestKey: source?.requestKey,
        data: source?.data,
        refreshAfter: source?.refreshAfter,
        errorCode: lifecycle.errorCode,
      );
    }
    return StockResearchReadState<T>._(
      phase: switch (source.phase) {
        StockResearchPhase.idle => StockResearchReadPhase.idle,
        StockResearchPhase.loading => StockResearchReadPhase.loading,
        StockResearchPhase.ready => StockResearchReadPhase.ready,
        StockResearchPhase.stale => StockResearchReadPhase.stale,
        StockResearchPhase.offline => StockResearchReadPhase.offline,
        StockResearchPhase.error => StockResearchReadPhase.error,
        StockResearchPhase.cancelled => StockResearchReadPhase.cancelled,
      },
      clock: _clock,
      requestKey: source.requestKey,
      data: source.data,
      refreshAfter: source.refreshAfter,
      errorCode: source.errorCode,
    );
  }

  StockResearchReadState<StockHistoryPage> _mapHistory(
    StockHistoryState? source,
    ({StockResearchRuntimePhase phase, String? errorCode}) lifecycle,
  ) {
    final overlay = _overlay(lifecycle);
    if (overlay != null || source == null) {
      return StockResearchReadState<StockHistoryPage>._(
        phase: overlay ?? StockResearchReadPhase.disabled,
        clock: _clock,
        requestKey: source?.request,
        data: source?.data,
        refreshAfter: source?.refreshAfter,
        errorCode: lifecycle.errorCode,
      );
    }
    return StockResearchReadState<StockHistoryPage>._(
      phase: switch (source.phase) {
        StockHistoryPhase.idle => StockResearchReadPhase.idle,
        StockHistoryPhase.loading => StockResearchReadPhase.loading,
        StockHistoryPhase.ready => StockResearchReadPhase.ready,
        StockHistoryPhase.stale => StockResearchReadPhase.stale,
        StockHistoryPhase.offline => StockResearchReadPhase.offline,
        StockHistoryPhase.error => StockResearchReadPhase.error,
        StockHistoryPhase.cancelled => StockResearchReadPhase.cancelled,
        StockHistoryPhase.closed => StockResearchReadPhase.closed,
      },
      clock: _clock,
      requestKey: source.request,
      data: source.data,
      refreshAfter: source.refreshAfter,
      errorCode: source.errorCode,
    );
  }

  StockResearchReadState<RaydiumStockQuote> _mapRaydium(
    RaydiumQuoteState? source,
    ({StockResearchRuntimePhase phase, String? errorCode}) lifecycle,
  ) {
    final overlay = _overlay(lifecycle);
    if (overlay != null || source == null) {
      return StockResearchReadState<RaydiumStockQuote>._(
        phase: overlay ?? StockResearchReadPhase.disabled,
        clock: _clock,
        requestKey: source?.request,
        data: source?.data,
        refreshAfter: source?.refreshAfter,
        errorCode: lifecycle.errorCode,
      );
    }
    return StockResearchReadState<RaydiumStockQuote>._(
      phase: switch (source.phase) {
        RaydiumQuotePhase.idle => StockResearchReadPhase.idle,
        RaydiumQuotePhase.loading => StockResearchReadPhase.loading,
        RaydiumQuotePhase.ready => StockResearchReadPhase.ready,
        RaydiumQuotePhase.stale => StockResearchReadPhase.stale,
        RaydiumQuotePhase.offline => StockResearchReadPhase.offline,
        RaydiumQuotePhase.error => StockResearchReadPhase.error,
        RaydiumQuotePhase.cancelled => StockResearchReadPhase.cancelled,
        RaydiumQuotePhase.closed => StockResearchReadPhase.closed,
      },
      clock: _clock,
      requestKey: source.request,
      data: source.data,
      refreshAfter: source.refreshAfter,
      errorCode: source.errorCode,
    );
  }

  StockResearchReadPhase? _overlay(
    ({StockResearchRuntimePhase phase, String? errorCode}) lifecycle,
  ) => switch (lifecycle.phase) {
    StockResearchRuntimePhase.disabled => StockResearchReadPhase.disabled,
    StockResearchRuntimePhase.background => StockResearchReadPhase.background,
    StockResearchRuntimePhase.offline => StockResearchReadPhase.offline,
    StockResearchRuntimePhase.invalidConfiguration =>
      StockResearchReadPhase.error,
    StockResearchRuntimePhase.closed => StockResearchReadPhase.closed,
    StockResearchRuntimePhase.active => null,
  };

  DateTime? _safeNow() {
    try {
      final value = _clock().toUtc();
      if (value.year < 1 || value.year > 9999) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  void _clearExpiry() {
    final timer = _expiryTimer;
    _expiryTimer = null;
    if (timer == null) return;
    try {
      timer.cancel();
    } catch (_) {
      // Resource shutdown remains terminal if an injected timer misbehaves.
    }
  }

  void _shutdown({required bool notify}) {
    if (_closed) return;
    _closed = true;
    _clearExpiry();
    _interruptFlights();
    final research = _research;
    final history = _history;
    final raydium = _raydium;
    research?.removeListener(_repositoryChanged);
    history?.removeListener(_repositoryChanged);
    raydium?.removeListener(_repositoryChanged);
    research?.dispose();
    history?.dispose();
    raydium?.dispose();
    try {
      _disposeTransports?.call();
    } catch (_) {
      // A transport adapter cannot make controller shutdown nonterminal.
    }
    if (notify && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _shutdown(notify: false);
    _disposed = true;
    super.dispose();
  }
}
