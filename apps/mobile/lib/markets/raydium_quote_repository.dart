import 'dart:async';

import 'package:flutter/foundation.dart';

import 'raydium_quote_client.dart';
import 'raydium_quote_models.dart';
import 'validation.dart' show StockResearchException;

typedef RaydiumQuoteClock = DateTime Function();
typedef RaydiumQuoteTimerFactory =
    Timer Function(Duration delay, void Function() callback);

enum RaydiumQuotePhase {
  idle,
  loading,
  ready,
  stale,
  offline,
  error,
  cancelled,
  closed,
}

enum _QuoteFreshness { fresh, stale, invalidClock }

/// Immutable quote state whose readiness is recomputed when it is observed.
/// A delayed platform timer therefore cannot make an expired quote look ready.
final class RaydiumQuoteState {
  const RaydiumQuoteState._(
    this._phase,
    this._errorCode,
    this._clock, {
    required this.request,
    required this.data,
  });

  final RaydiumQuotePhase _phase;
  final String? _errorCode;
  final RaydiumQuoteClock _clock;
  final RaydiumQuoteRequest? request;
  final RaydiumStockQuote? data;

  _QuoteFreshness get _freshness {
    final quote = data;
    if (quote == null) return _QuoteFreshness.stale;
    try {
      final now = _clock().toUtc();
      if (now.year < 1 || now.year > 9999) {
        return _QuoteFreshness.invalidClock;
      }
      return quote.isFreshAt(now)
          ? _QuoteFreshness.fresh
          : _QuoteFreshness.stale;
    } catch (_) {
      return _QuoteFreshness.invalidClock;
    }
  }

  RaydiumQuotePhase get phase {
    if (_phase != RaydiumQuotePhase.ready) return _phase;
    return switch (_freshness) {
      _QuoteFreshness.fresh => RaydiumQuotePhase.ready,
      _QuoteFreshness.stale => RaydiumQuotePhase.stale,
      _QuoteFreshness.invalidClock => RaydiumQuotePhase.error,
    };
  }

  String? get errorCode {
    if (_phase != RaydiumQuotePhase.ready) return _errorCode;
    return switch (_freshness) {
      _QuoteFreshness.fresh => null,
      _QuoteFreshness.stale => 'MARKET_ESTIMATE_STALE',
      _QuoteFreshness.invalidClock => 'RAYDIUM_QUOTE_CLOCK_INVALID',
    };
  }

  DateTime? get refreshAfter => data?.refreshAfter;
  bool get hasRetainedData => data != null && phase != RaydiumQuotePhase.ready;
  bool get isFresh => data != null && _freshness == _QuoteFreshness.fresh;
}

final class _QuoteFlight {
  _QuoteFlight(this.request, this.generation)
    : cancellation = RaydiumQuoteCancellation();

  final RaydiumQuoteRequest request;
  final int generation;
  final RaydiumQuoteCancellation cancellation;
  final completion = Completer<void>();
}

final class _QueuedQuoteLoad {
  _QueuedQuoteLoad(this.request);

  final RaydiumQuoteRequest request;
  final completion = Completer<void>();
}

/// One-entry, in-memory coordinator for indicative Raydium quote reads.
///
/// Identical concurrent reads share a future. A changed request cancels and
/// waits for the active adapter call before dispatching, so only one HTTP read
/// spends quota at a time. Connectivity and expiry never trigger a read.
final class RaydiumQuoteRepository extends ChangeNotifier {
  RaydiumQuoteRepository({
    required this._client,
    RaydiumQuoteClock? clock,
    RaydiumQuoteTimerFactory? timerFactory,
  }) : _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new,
       _state = RaydiumQuoteState._(
         RaydiumQuotePhase.idle,
         null,
         clock ?? DateTime.now,
         request: null,
         data: null,
       );

  final RaydiumQuoteClient _client;
  final RaydiumQuoteClock _clock;
  final RaydiumQuoteTimerFactory _timerFactory;

  RaydiumQuoteState _state;
  RaydiumStockQuote? _retainedQuote;
  RaydiumQuoteRequest? _retainedRequest;
  _QuoteFlight? _flight;
  _QueuedQuoteLoad? _queued;
  Timer? _expiryTimer;
  var _generation = 0;
  var _online = true;
  var _closed = false;
  var _disposed = false;
  var _schedulingExpiry = false;

  RaydiumQuoteState get state => _state;
  bool get networkAvailable => _online;
  bool get isBusy => _flight != null || _queued != null;
  Future<void> get whenIdle =>
      _queued?.completion.future ??
      _flight?.completion.future ??
      Future<void>.value();

  Future<void> load(RaydiumQuoteRequest request) {
    if (_closed || _disposed) {
      return Future<void>.error(
        const StockResearchException('RAYDIUM_QUOTE_REPOSITORY_CLOSED'),
      );
    }
    try {
      request.validate();
    } on StockResearchException catch (error) {
      return Future<void>.error(error);
    } catch (_) {
      return Future<void>.error(
        const StockResearchException('MARKET_INPUT_INVALID'),
      );
    }
    if (_safeNow() == null) {
      _invalidateClock();
      return Future<void>.error(
        const StockResearchException('RAYDIUM_QUOTE_CLOCK_INVALID'),
      );
    }
    if (!_online) {
      _publish(
        RaydiumQuotePhase.offline,
        request: request,
        data: _retainedFor(request),
        errorCode: 'RAYDIUM_QUOTE_NETWORK_ERROR',
      );
      return Future<void>.value();
    }

    final active = _flight;
    if (active != null) {
      final queued = _queued;
      if (queued == null &&
          active.request == request &&
          _state._phase == RaydiumQuotePhase.loading) {
        return active.completion.future;
      }
      if (queued?.request == request) return queued!.completion.future;

      ++_generation;
      active.cancellation.cancel();
      if (queued != null && !queued.completion.isCompleted) {
        queued.completion.complete();
      }
      final replacement = _QueuedQuoteLoad(request);
      _queued = replacement;
      _publish(
        RaydiumQuotePhase.loading,
        request: request,
        data: _retainedFor(request),
      );
      return replacement.completion.future;
    }
    return _start(request);
  }

  Future<void> _start(RaydiumQuoteRequest request) {
    final flight = _QuoteFlight(request, ++_generation);
    _flight = flight;
    _publish(
      RaydiumQuotePhase.loading,
      request: request,
      data: _retainedFor(request),
    );
    unawaited(_run(flight));
    return flight.completion.future;
  }

  Future<void> _run(_QuoteFlight flight) async {
    try {
      if (!_isCurrent(flight)) return;
      final quote = await _client.quote(
        flight.request,
        cancellation: flight.cancellation,
      );
      if (!_isCurrent(flight)) return;
      if (quote.request != flight.request) {
        throw const StockResearchException('RAYDIUM_QUOTE_RESPONSE_INVALID');
      }
      final now = _safeNow();
      if (now == null) {
        _invalidateClock();
        return;
      }
      if (quote.receivedAt.isAfter(now.add(const Duration(seconds: 60)))) {
        throw const StockResearchException('RAYDIUM_QUOTE_RESPONSE_INVALID');
      }
      _retainedRequest = flight.request;
      _retainedQuote = quote;
      final fresh = quote.isFreshAt(now);
      _publish(
        fresh ? RaydiumQuotePhase.ready : RaydiumQuotePhase.stale,
        request: flight.request,
        data: quote,
        errorCode: fresh ? null : 'MARKET_ESTIMATE_STALE',
      );
    } catch (error) {
      if (!_isCurrent(flight)) return;
      final code = error is StockResearchException
          ? error.code
          : 'RAYDIUM_QUOTE_NETWORK_ERROR';
      final phase = switch (code) {
        'RAYDIUM_QUOTE_CANCELLED' => RaydiumQuotePhase.cancelled,
        'RAYDIUM_QUOTE_NETWORK_ERROR' => RaydiumQuotePhase.offline,
        'MARKET_ESTIMATE_STALE' => RaydiumQuotePhase.stale,
        _ => RaydiumQuotePhase.error,
      };
      _publish(
        phase,
        request: flight.request,
        data: _retainedFor(flight.request),
        errorCode: code,
      );
    } finally {
      if (!flight.completion.isCompleted) flight.completion.complete();
      if (identical(_flight, flight)) {
        _flight = null;
        _drainQueue();
      }
    }
  }

  void _drainQueue() {
    final queued = _queued;
    _queued = null;
    if (queued == null || queued.completion.isCompleted) return;
    if (_closed || _disposed || !_online) {
      queued.completion.complete();
      return;
    }
    final operation = _start(queued.request);
    queued.completion.complete(operation);
  }

  bool _isCurrent(_QuoteFlight flight) =>
      !_closed &&
      !_disposed &&
      _online &&
      identical(_flight, flight) &&
      flight.generation == _generation &&
      !flight.cancellation.isCancelled;

  RaydiumStockQuote? _retainedFor(RaydiumQuoteRequest request) =>
      _retainedRequest == request ? _retainedQuote : null;

  void cancel() {
    if (_closed || _disposed || _state._phase != RaydiumQuotePhase.loading) {
      return;
    }
    ++_generation;
    _flight?.cancellation.cancel();
    final queued = _queued;
    _queued = null;
    if (queued != null && !queued.completion.isCompleted) {
      queued.completion.complete();
    }
    final request = _state.request;
    _publish(
      RaydiumQuotePhase.cancelled,
      request: request,
      data: request == null ? null : _retainedFor(request),
      errorCode: 'RAYDIUM_QUOTE_CANCELLED',
    );
  }

  /// A connectivity hint. Reconnection only reclassifies retained data; the
  /// caller must explicitly load again before another HTTP request is made.
  void setNetworkAvailable(bool available) {
    if (_closed || _disposed || _online == available) return;
    _online = available;
    if (!available) {
      ++_generation;
      _flight?.cancellation.cancel();
      final queued = _queued;
      _queued = null;
      if (queued != null && !queued.completion.isCompleted) {
        queued.completion.complete();
      }
      final request = _state.request;
      _publish(
        RaydiumQuotePhase.offline,
        request: request,
        data: request == null ? null : _retainedFor(request),
        errorCode: 'RAYDIUM_QUOTE_NETWORK_ERROR',
      );
      return;
    }

    final request = _state.request;
    final data = request == null ? null : _retainedFor(request);
    final now = _safeNow();
    if (now == null) {
      _invalidateClock();
      return;
    }
    final fresh = data?.isFreshAt(now) ?? false;
    _publish(
      data == null
          ? RaydiumQuotePhase.idle
          : fresh
          ? RaydiumQuotePhase.ready
          : RaydiumQuotePhase.stale,
      request: request,
      data: data,
      errorCode: data != null && !fresh ? 'MARKET_ESTIMATE_STALE' : null,
    );
  }

  void close() => _close(notify: true);

  void _close({required bool notify}) {
    if (_closed) return;
    _closed = true;
    ++_generation;
    _clearExpiry();
    final flight = _flight;
    _flight = null;
    flight?.cancellation.cancel();
    if (flight != null && !flight.completion.isCompleted) {
      flight.completion.complete();
    }
    final queued = _queued;
    _queued = null;
    if (queued != null && !queued.completion.isCompleted) {
      queued.completion.complete();
    }
    _retainedRequest = null;
    _retainedQuote = null;
    _state = RaydiumQuoteState._(
      RaydiumQuotePhase.closed,
      'RAYDIUM_QUOTE_REPOSITORY_CLOSED',
      _clock,
      request: null,
      data: null,
    );
    if (notify && !_disposed) notifyListeners();
  }

  void _publish(
    RaydiumQuotePhase phase, {
    required RaydiumQuoteRequest? request,
    required RaydiumStockQuote? data,
    String? errorCode,
  }) {
    _clearExpiry();
    _state = RaydiumQuoteState._(
      phase,
      errorCode,
      _clock,
      request: request,
      data: data,
    );
    if (phase == RaydiumQuotePhase.ready && data != null) {
      final schedulingFailure = _scheduleExpiry(data);
      if (schedulingFailure != null) {
        _state = RaydiumQuoteState._(
          schedulingFailure == 'MARKET_ESTIMATE_STALE'
              ? RaydiumQuotePhase.stale
              : RaydiumQuotePhase.error,
          schedulingFailure,
          _clock,
          request: request,
          data: data,
        );
      }
    }
    if (!_disposed) notifyListeners();
  }

  String? _scheduleExpiry(RaydiumStockQuote quote) {
    if (_closed || _disposed || !_online) return null;
    final now = _safeNow();
    if (now == null) return 'RAYDIUM_QUOTE_CLOCK_INVALID';
    final remaining = quote.refreshAfter.difference(now);
    if (remaining <= Duration.zero) return 'MARKET_ESTIMATE_STALE';
    var firedSynchronously = false;
    try {
      _schedulingExpiry = true;
      final timer = _timerFactory(remaining, () {
        if (_schedulingExpiry) {
          firedSynchronously = true;
          return;
        }
        _expire(quote);
      });
      _schedulingExpiry = false;
      bool active;
      try {
        active = timer.isActive;
      } catch (_) {
        active = false;
      }
      if (firedSynchronously || !active) {
        try {
          timer.cancel();
        } catch (_) {
          // The invalid adapter is discarded below.
        }
        return 'RAYDIUM_QUOTE_TIMER_INVALID';
      }
      _expiryTimer = timer;
    } catch (_) {
      _schedulingExpiry = false;
      _expiryTimer = null;
      return 'RAYDIUM_QUOTE_TIMER_INVALID';
    }
    return null;
  }

  void _expire(RaydiumStockQuote quote) {
    _expiryTimer = null;
    if (_closed ||
        _disposed ||
        !_online ||
        _state._phase != RaydiumQuotePhase.ready ||
        !identical(_state.data, quote)) {
      return;
    }
    final now = _safeNow();
    if (now == null) {
      _publish(
        RaydiumQuotePhase.error,
        request: _state.request,
        data: quote,
        errorCode: 'RAYDIUM_QUOTE_CLOCK_INVALID',
      );
      return;
    }
    if (quote.isFreshAt(now)) {
      final schedulingFailure = _scheduleExpiry(quote);
      if (schedulingFailure != null) {
        _publish(
          schedulingFailure == 'MARKET_ESTIMATE_STALE'
              ? RaydiumQuotePhase.stale
              : RaydiumQuotePhase.error,
          request: _state.request,
          data: quote,
          errorCode: schedulingFailure,
        );
      }
      return;
    }
    _publish(
      RaydiumQuotePhase.stale,
      request: _state.request,
      data: quote,
      errorCode: 'MARKET_ESTIMATE_STALE',
    );
  }

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
      // Close and state replacement stay terminal if an injected timer fails.
    }
  }

  void _invalidateClock() {
    if (_closed || _disposed) return;
    ++_generation;
    _clearExpiry();
    final flight = _flight;
    _flight = null;
    flight?.cancellation.cancel();
    if (flight != null && !flight.completion.isCompleted) {
      flight.completion.complete();
    }
    final queued = _queued;
    _queued = null;
    if (queued != null && !queued.completion.isCompleted) {
      queued.completion.complete();
    }
    final request = _state.request;
    _publish(
      RaydiumQuotePhase.error,
      request: request,
      data: request == null ? null : _retainedFor(request),
      errorCode: 'RAYDIUM_QUOTE_CLOCK_INVALID',
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _close(notify: false);
    _disposed = true;
    super.dispose();
  }
}
