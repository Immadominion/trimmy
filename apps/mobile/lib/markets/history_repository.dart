import 'dart:async';

import 'package:flutter/foundation.dart';

import 'client.dart' show StockResearchCancellation;
import 'history_client.dart';
import 'history_models.dart';
import 'validation.dart';

typedef StockHistoryClock = DateTime Function();
typedef StockHistoryTimerFactory =
    Timer Function(Duration delay, void Function() callback);

enum StockHistoryPhase {
  idle,
  loading,
  ready,
  stale,
  offline,
  error,
  cancelled,
  closed,
}

/// Immutable read state. A captured ready state also reports `stale` once its
/// deadline passes, even before a delayed platform timer gets CPU time.
final class StockHistoryState {
  const StockHistoryState._(
    this._phase,
    this._errorCode,
    this._clock, {
    required this.request,
    required this.data,
  });

  final StockHistoryPhase _phase;
  final String? _errorCode;
  final StockHistoryClock _clock;
  final StockHistoryRequest? request;
  final StockHistoryPage? data;

  StockHistoryPhase get phase {
    final page = data;
    if (_phase == StockHistoryPhase.ready && page != null) {
      final freshness = _freshness(page);
      if (!freshness.clockValid) return StockHistoryPhase.error;
      if (!freshness.fresh) return StockHistoryPhase.stale;
    }
    return _phase;
  }

  String? get errorCode {
    final page = data;
    if (_phase == StockHistoryPhase.ready && page != null) {
      final freshness = _freshness(page);
      if (!freshness.clockValid) {
        return 'STOCK_HISTORY_INVALID_CONFIGURATION';
      }
      if (!freshness.fresh) return 'STOCK_HISTORY_STALE';
    }
    return _errorCode;
  }

  DateTime? get refreshAfter => data?.provenance.refreshAfter;
  bool get hasRetainedData => data != null && phase != StockHistoryPhase.ready;
  bool get isFresh {
    final page = data;
    return page != null && _freshness(page).fresh;
  }

  ({bool clockValid, bool fresh}) _freshness(StockHistoryPage page) {
    try {
      final now = _clock().toUtc();
      if (now.year < 1 || now.year > 9999) {
        return (clockValid: false, fresh: false);
      }
      return (clockValid: true, fresh: page.provenance.isFreshAt(now));
    } catch (_) {
      return (clockValid: false, fresh: false);
    }
  }
}

final class _HistoryFlight {
  _HistoryFlight(this.request, this.generation)
    : cancellation = StockResearchCancellation();

  final StockHistoryRequest request;
  final int generation;
  final StockResearchCancellation cancellation;
  final completion = Completer<void>();
}

final class _QueuedHistoryLoad {
  _QueuedHistoryLoad(this.request);

  final StockHistoryRequest request;
  final completion = Completer<void>();
}

/// One-entry, in-memory history coordinator.
///
/// Identical concurrent reads share a future. A new window cancels and waits
/// for the old adapter call before dispatching, so at most one HTTP read can
/// spend quota at a time. Reconnection and expiry never fetch automatically.
final class StockHistoryRepository extends ChangeNotifier {
  StockHistoryRepository({
    required this._client,
    StockHistoryClock? clock,
    StockHistoryTimerFactory? timerFactory,
  }) : _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new,
       _state = StockHistoryState._(
         StockHistoryPhase.idle,
         null,
         clock ?? DateTime.now,
         request: null,
         data: null,
       );

  final StockHistoryClient _client;
  final StockHistoryClock _clock;
  final StockHistoryTimerFactory _timerFactory;

  StockHistoryState _state;
  StockHistoryPage? _retainedPage;
  StockHistoryRequest? _retainedRequest;
  _HistoryFlight? _flight;
  _QueuedHistoryLoad? _queued;
  Timer? _expiryTimer;
  var _generation = 0;
  var _online = true;
  var _closed = false;
  var _disposed = false;
  var _schedulingExpiry = false;

  StockHistoryState get state => _state;
  bool get networkAvailable => _online;
  bool get isBusy => _flight != null || _queued != null;
  Future<void> get whenIdle =>
      _queued?.completion.future ??
      _flight?.completion.future ??
      Future<void>.value();

  Future<void> load(StockHistoryRequest request) {
    if (_closed || _disposed) {
      return Future<void>.error(
        const StockResearchException('STOCK_HISTORY_REPOSITORY_CLOSED'),
      );
    }
    try {
      request.validateAt(_nowUnixSeconds());
    } on StockResearchException catch (error) {
      if (error.code == 'STOCK_HISTORY_INVALID_CONFIGURATION') {
        _invalidateClock();
      }
      return Future<void>.error(error);
    } catch (_) {
      _invalidateClock();
      return Future<void>.error(
        const StockResearchException('STOCK_HISTORY_INVALID_CONFIGURATION'),
      );
    }
    if (!_online) {
      _publish(
        StockHistoryPhase.offline,
        request: request,
        data: _retainedFor(request),
        errorCode: 'STOCK_HISTORY_NETWORK_ERROR',
      );
      return Future<void>.value();
    }

    final active = _flight;
    if (active != null) {
      final queued = _queued;
      if (queued == null &&
          active.request == request &&
          _state._phase == StockHistoryPhase.loading) {
        return active.completion.future;
      }
      if (queued?.request == request) return queued!.completion.future;

      ++_generation;
      active.cancellation.cancel();
      if (queued != null && !queued.completion.isCompleted) {
        queued.completion.complete();
      }
      final replacement = _QueuedHistoryLoad(request);
      _queued = replacement;
      _publish(
        StockHistoryPhase.loading,
        request: request,
        data: _retainedFor(request),
      );
      return replacement.completion.future;
    }
    return _start(request);
  }

  Future<void> _start(StockHistoryRequest request) {
    final flight = _HistoryFlight(request, ++_generation);
    _flight = flight;
    _publish(
      StockHistoryPhase.loading,
      request: request,
      data: _retainedFor(request),
    );
    unawaited(_run(flight));
    return flight.completion.future;
  }

  Future<void> _run(_HistoryFlight flight) async {
    try {
      if (!_isCurrent(flight)) return;
      final page = await _client.history(
        flight.request,
        cancellation: flight.cancellation,
      );
      if (!_isCurrent(flight)) return;
      final receivedAt = _now();
      if (page.assetId != flight.request.assetId ||
          page.variantMint != flight.request.variantMint ||
          page.interval != flight.request.interval ||
          page.fromUnixSeconds != flight.request.fromUnixSeconds ||
          page.toUnixSeconds != flight.request.toUnixSeconds ||
          page.provenance.observedAt.isAfter(
            receivedAt.add(const Duration(seconds: 60)),
          )) {
        throw const StockResearchException('STOCK_HISTORY_RESPONSE_INVALID');
      }
      _retainedRequest = flight.request;
      _retainedPage = page;
      final phase = page.provenance.isFreshAt(receivedAt)
          ? StockHistoryPhase.ready
          : StockHistoryPhase.stale;
      _publish(
        phase,
        request: flight.request,
        data: page,
        errorCode: phase == StockHistoryPhase.stale
            ? 'STOCK_HISTORY_STALE'
            : null,
      );
    } catch (error) {
      if (!_isCurrent(flight)) return;
      final code = error is StockResearchException
          ? error.code
          : 'STOCK_HISTORY_NETWORK_ERROR';
      if (code == 'STOCK_HISTORY_INVALID_CONFIGURATION') {
        _invalidateClock();
        return;
      }
      final phase = switch (code) {
        'STOCK_HISTORY_CANCELLED' => StockHistoryPhase.cancelled,
        'STOCK_HISTORY_NETWORK_ERROR' => StockHistoryPhase.offline,
        _ => StockHistoryPhase.error,
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

  bool _isCurrent(_HistoryFlight flight) =>
      !_closed &&
      !_disposed &&
      _online &&
      identical(_flight, flight) &&
      flight.generation == _generation &&
      !flight.cancellation.isCancelled;

  StockHistoryPage? _retainedFor(StockHistoryRequest request) =>
      _retainedRequest == request ? _retainedPage : null;

  void cancel() {
    if (_closed || _disposed || _state._phase != StockHistoryPhase.loading) {
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
      StockHistoryPhase.cancelled,
      request: request,
      data: request == null ? null : _retainedFor(request),
      errorCode: 'STOCK_HISTORY_CANCELLED',
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
        StockHistoryPhase.offline,
        request: request,
        data: request == null ? null : _retainedFor(request),
        errorCode: 'STOCK_HISTORY_NETWORK_ERROR',
      );
      return;
    }

    final request = _state.request;
    final data = request == null ? null : _retainedFor(request);
    bool fresh;
    try {
      fresh = data?.provenance.isFreshAt(_now()) ?? false;
    } on StockResearchException catch (error) {
      if (error.code == 'STOCK_HISTORY_INVALID_CONFIGURATION') {
        _invalidateClock();
      } else {
        _publish(
          StockHistoryPhase.error,
          request: request,
          data: data,
          errorCode: error.code,
        );
      }
      return;
    }
    _publish(
      data == null
          ? StockHistoryPhase.idle
          : fresh
          ? StockHistoryPhase.ready
          : StockHistoryPhase.stale,
      request: request,
      data: data,
      errorCode: data != null && !fresh ? 'STOCK_HISTORY_STALE' : null,
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
    _retainedPage = null;
    _state = StockHistoryState._(
      StockHistoryPhase.closed,
      'STOCK_HISTORY_REPOSITORY_CLOSED',
      _clock,
      request: null,
      data: null,
    );
    if (notify && !_disposed) notifyListeners();
  }

  void _publish(
    StockHistoryPhase phase, {
    required StockHistoryRequest? request,
    required StockHistoryPage? data,
    String? errorCode,
  }) {
    _clearExpiry();
    _state = StockHistoryState._(
      phase,
      errorCode,
      _clock,
      request: request,
      data: data,
    );
    if (phase == StockHistoryPhase.ready && data != null) {
      final schedulingFailure = _scheduleExpiry(data);
      if (schedulingFailure != null) {
        _state = StockHistoryState._(
          schedulingFailure == 'STOCK_HISTORY_STALE'
              ? StockHistoryPhase.stale
              : StockHistoryPhase.error,
          schedulingFailure,
          _clock,
          request: request,
          data: data,
        );
      }
    }
    if (!_disposed) notifyListeners();
  }

  String? _scheduleExpiry(StockHistoryPage page) {
    if (_closed || _disposed || !_online) return null;
    Duration remaining;
    try {
      remaining = page.provenance.refreshAfter.difference(_now());
    } on StockResearchException catch (error) {
      return error.code;
    }
    if (remaining <= Duration.zero) {
      return 'STOCK_HISTORY_STALE';
    }
    var firedSynchronously = false;
    try {
      _schedulingExpiry = true;
      final timer = _timerFactory(remaining, () {
        if (_schedulingExpiry) {
          firedSynchronously = true;
          return;
        }
        _expire(page);
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
        return 'STOCK_HISTORY_TIMER_INVALID';
      }
      _expiryTimer = timer;
    } catch (_) {
      _schedulingExpiry = false;
      return 'STOCK_HISTORY_TIMER_INVALID';
    }
    return null;
  }

  void _expire(StockHistoryPage page) {
    _expiryTimer = null;
    if (_closed ||
        _disposed ||
        !_online ||
        _state._phase != StockHistoryPhase.ready ||
        !identical(_state.data, page)) {
      return;
    }
    bool fresh;
    try {
      fresh = page.provenance.isFreshAt(_now());
    } on StockResearchException catch (error) {
      _publish(
        StockHistoryPhase.error,
        request: _state.request,
        data: page,
        errorCode: error.code,
      );
      return;
    }
    if (fresh) {
      final schedulingFailure = _scheduleExpiry(page);
      if (schedulingFailure != null) {
        _publish(
          schedulingFailure == 'STOCK_HISTORY_STALE'
              ? StockHistoryPhase.stale
              : StockHistoryPhase.error,
          request: _state.request,
          data: page,
          errorCode: schedulingFailure,
        );
      }
      return;
    }
    _publish(
      StockHistoryPhase.stale,
      request: _state.request,
      data: page,
      errorCode: 'STOCK_HISTORY_STALE',
    );
  }

  DateTime _now() {
    try {
      final value = _clock().toUtc();
      if (value.year < 1 || value.year > 9999) {
        throw const StockResearchException(
          'STOCK_HISTORY_INVALID_CONFIGURATION',
        );
      }
      return value;
    } on StockResearchException {
      rethrow;
    } catch (_) {
      throw const StockResearchException('STOCK_HISTORY_INVALID_CONFIGURATION');
    }
  }

  int _nowUnixSeconds() => _now().millisecondsSinceEpoch ~/ 1000;

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
      StockHistoryPhase.error,
      request: request,
      data: request == null ? null : _retainedFor(request),
      errorCode: 'STOCK_HISTORY_INVALID_CONFIGURATION',
    );
  }

  void _clearExpiry() {
    final timer = _expiryTimer;
    _expiryTimer = null;
    if (timer == null) return;
    try {
      timer.cancel();
    } catch (_) {
      // State replacement and shutdown stay terminal for a broken adapter.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _close(notify: false);
    _disposed = true;
    super.dispose();
  }
}
