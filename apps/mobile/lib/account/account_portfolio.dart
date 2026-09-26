import 'dart:async';

import 'package:flutter/foundation.dart';

import '../practice_sync/protocol.dart';
import 'account_data_models.dart';
import 'http_account_data_client.dart';

typedef AccountPortfolioClock = DateTime Function();
typedef AccountPortfolioTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// The narrow read-only surface required by [AccountPortfolioRepository].
///
/// The HTTP implementation is adapted below. Tests and future transports can
/// implement this interface without gaining any wallet or transaction method.
abstract interface class AccountPortfolioReader {
  String get accountId;
  Future<AccountContextSnapshot> readContext();
  Future<AccountHoldingsSnapshot> readHoldings({int? minimumObservedSlot});
  void cancelPending();
  void close();
}

final class HttpAccountPortfolioReader implements AccountPortfolioReader {
  const HttpAccountPortfolioReader(this._client);

  final HttpAccountDataClient _client;

  @override
  String get accountId => _client.accountId;

  @override
  Future<AccountContextSnapshot> readContext() => _client.readContext();

  @override
  Future<AccountHoldingsSnapshot> readHoldings({int? minimumObservedSlot}) =>
      _client.readHoldings(minimumObservedSlot: minimumObservedSlot);

  @override
  void cancelPending() => _client.cancelPending();

  @override
  void close() => _client.close();
}

enum AccountPortfolioPhase {
  idle,
  loading,
  ready,
  stale,
  offline,
  error,
  cancelled,
  accountChanged,
  closed,
}

enum AccountPortfolioIssue {
  invalidConfiguration,
  invalidRequest,
  unauthenticated,
  accountChanged,
  walletMissing,
  walletAmbiguous,
  walletChanged,
  unavailable,
  notConfigured,
  invalidResponse,
  timeout,
  cancelled,
  busy,
  observationExpired,
  observationInFuture,
  closed,
}

enum _AccountPortfolioFreshness { fresh, expired, invalidClock }

/// Contains one coherent context/holdings pair for the same account and wallet.
final class AccountPortfolioSnapshot {
  const AccountPortfolioSnapshot._({
    required this.accountId,
    required this.context,
    required this.holdings,
    required this.acceptedAt,
    required this.freshUntil,
  });

  final String accountId;
  final AccountContextSnapshot context;
  final AccountHoldingsSnapshot holdings;
  final DateTime acceptedAt;
  final DateTime freshUntil;

  bool isFreshAt(DateTime value) => value.toUtc().isBefore(freshUntil);
}

/// Immutable repository state. A cached state object also stops reporting
/// `ready` when its portfolio reaches [AccountPortfolioSnapshot.freshUntil].
final class AccountPortfolioState {
  const AccountPortfolioState._(
    this._phase,
    this._issue,
    this._clock, {
    required this.accountId,
    required this.context,
    required this.portfolio,
  });

  final AccountPortfolioPhase _phase;
  final AccountPortfolioIssue? _issue;
  final AccountPortfolioClock _clock;

  final String accountId;

  /// The most recent context accepted for this account. It can be newer than a
  /// retained portfolio after a holdings read fails.
  final AccountContextSnapshot? context;

  /// Fresh data when [phase] is `ready`; otherwise explicitly retained data.
  final AccountPortfolioSnapshot? portfolio;

  _AccountPortfolioFreshness get _freshness {
    final value = portfolio;
    if (value == null) return _AccountPortfolioFreshness.expired;
    try {
      final now = _clock().toUtc();
      if (now.year < 1 || now.year > 9999) {
        return _AccountPortfolioFreshness.invalidClock;
      }
      return value.isFreshAt(now)
          ? _AccountPortfolioFreshness.fresh
          : _AccountPortfolioFreshness.expired;
    } catch (_) {
      return _AccountPortfolioFreshness.invalidClock;
    }
  }

  AccountPortfolioPhase get phase {
    if (_phase == AccountPortfolioPhase.ready) {
      return switch (_freshness) {
        _AccountPortfolioFreshness.fresh => AccountPortfolioPhase.ready,
        _AccountPortfolioFreshness.expired => AccountPortfolioPhase.stale,
        _AccountPortfolioFreshness.invalidClock => AccountPortfolioPhase.error,
      };
    }
    return _phase;
  }

  AccountPortfolioIssue? get issue {
    if (_phase != AccountPortfolioPhase.ready) return _issue;
    return switch (_freshness) {
      _AccountPortfolioFreshness.fresh => null,
      _AccountPortfolioFreshness.expired =>
        AccountPortfolioIssue.observationExpired,
      _AccountPortfolioFreshness.invalidClock =>
        AccountPortfolioIssue.invalidConfiguration,
    };
  }

  bool get hasRetainedPortfolio =>
      portfolio != null && phase != AccountPortfolioPhase.ready;

  bool get portfolioIsFresh => phase == AccountPortfolioPhase.ready;
}

final class AccountPortfolioException implements Exception {
  const AccountPortfolioException(this.issue);

  final AccountPortfolioIssue issue;

  @override
  String toString() => 'AccountPortfolioException(${issue.name})';
}

/// Coordinates an account-context read followed by a holdings read.
///
/// One instance owns one reader and one normalized Trimmy account ID. It has no
/// persistence and no write, provisioning, signing, simulation or broadcast
/// capability.
final class AccountPortfolioRepository extends ChangeNotifier {
  factory AccountPortfolioRepository({
    required AccountPortfolioReader reader,
    Duration maximumObservationAge = const Duration(seconds: 45),
    Duration maximumFutureSkew = const Duration(seconds: 5),
    AccountPortfolioClock? clock,
    AccountPortfolioTimerFactory? timerFactory,
  }) {
    final configuredAccountId = reader.accountId;
    String accountId;
    try {
      accountId = normalizePracticeUuid(configuredAccountId);
    } catch (_) {
      throw const AccountPortfolioException(
        AccountPortfolioIssue.invalidConfiguration,
      );
    }
    if (configuredAccountId != accountId ||
        maximumObservationAge <= Duration.zero ||
        maximumFutureSkew.isNegative) {
      throw const AccountPortfolioException(
        AccountPortfolioIssue.invalidConfiguration,
      );
    }
    final resolvedClock = clock ?? DateTime.now;
    return AccountPortfolioRepository._(
      reader,
      accountId,
      maximumObservationAge,
      maximumFutureSkew,
      resolvedClock,
      timerFactory ?? Timer.new,
    );
  }

  factory AccountPortfolioRepository.fromHttp({
    required HttpAccountDataClient client,
    Duration maximumObservationAge = const Duration(seconds: 45),
    Duration maximumFutureSkew = const Duration(seconds: 5),
    AccountPortfolioClock? clock,
    AccountPortfolioTimerFactory? timerFactory,
  }) => AccountPortfolioRepository(
    reader: HttpAccountPortfolioReader(client),
    maximumObservationAge: maximumObservationAge,
    maximumFutureSkew: maximumFutureSkew,
    clock: clock,
    timerFactory: timerFactory,
  );

  AccountPortfolioRepository._(
    this._reader,
    this.accountId,
    this._maximumObservationAge,
    this._maximumFutureSkew,
    this._clock,
    this._timerFactory,
  ) : _state = AccountPortfolioState._(
        AccountPortfolioPhase.idle,
        null,
        _clock,
        accountId: accountId,
        context: null,
        portfolio: null,
      );

  final AccountPortfolioReader _reader;
  final Duration _maximumObservationAge;
  final Duration _maximumFutureSkew;
  final AccountPortfolioClock _clock;
  final AccountPortfolioTimerFactory _timerFactory;

  final String accountId;
  AccountPortfolioState _state;
  Future<void>? _inFlight;
  Future<void>? _queuedRefresh;
  Future<void>? _mutationRefresh;
  int _mutationRevision = 0;
  int? _minimumObservedSlot;
  Timer? _expiryTimer;
  int _generation = 0;
  bool _online = true;
  bool _invalidated = false;
  bool _readerClosed = false;
  bool _disposed = false;

  AccountPortfolioState get state => _state;
  bool get networkAvailable => _online;
  bool get isBusy => _state._phase == AccountPortfolioPhase.loading;

  /// Returns a portfolio only while the current state is both ready and fresh.
  AccountPortfolioSnapshot? get readyPortfolio {
    final current = _state;
    return current.phase == AccountPortfolioPhase.ready
        ? current.portfolio
        : null;
  }

  Future<void> get whenIdle =>
      _mutationRefresh ?? _queuedRefresh ?? _inFlight ?? Future<void>.value();

  /// A confirmed transaction must never reuse a read begun before confirmation.
  /// Later reads retain the chain slot floor, preventing RPC/cache regression.
  Future<void> refreshAfterMutation({int? minimumObservedSlot}) {
    if (minimumObservedSlot != null) {
      try {
        recordConfirmedSlot(minimumObservedSlot);
      } on AccountPortfolioException catch (error) {
        return Future.error(error);
      }
    }
    _mutationRevision++;
    final existing = _mutationRefresh;
    if (existing != null) return existing;
    final previous = _queuedRefresh ?? _inFlight;
    late final Future<void> operation;
    operation =
        (() async {
          if (previous != null) await previous;
          int revision;
          do {
            revision = _mutationRevision;
            await _startRefresh();
          } while (revision != _mutationRevision &&
              !_disposed &&
              !_invalidated);
        })().whenComplete(() {
          if (identical(_mutationRefresh, operation)) _mutationRefresh = null;
        });
    _mutationRefresh = operation;
    return operation;
  }

  /// Records a confirmation even while the app cannot start a network read.
  /// Foreground/reconnect refreshes must still observe that transaction.
  void recordConfirmedSlot(int slot) {
    if (slot < 1 || slot > 9007199254740991) {
      throw const AccountPortfolioException(
        AccountPortfolioIssue.invalidRequest,
      );
    }
    if (_disposed || _invalidated || slot <= (_minimumObservedSlot ?? 0)) {
      return;
    }
    _minimumObservedSlot = slot;
    final portfolio = _state.portfolio;
    if (portfolio != null &&
        !_observesConfirmedSlot(portfolio.holdings) &&
        _state._phase == AccountPortfolioPhase.ready) {
      _publish(
        AccountPortfolioPhase.stale,
        context: _state.context,
        portfolio: portfolio,
        issue: AccountPortfolioIssue.observationExpired,
      );
    }
  }

  bool _observesConfirmedSlot(AccountHoldingsSnapshot holdings) {
    final floor = _minimumObservedSlot;
    return floor == null ||
        [
          holdings.nativeSol.observedSlot,
          holdings.usdc.observedSlot,
          holdings.aaplx.observedSlot,
          ...holdings.stockTokens.map((token) => token.observedSlot),
        ].every((slot) => slot >= floor);
  }

  /// Concurrent refreshes share one context-then-holdings operation. After a
  /// cancellation, a new refresh waits for the cancelled adapter call to retire
  /// before starting another one.
  Future<void> refresh() => _mutationRefresh ?? _startRefresh();

  Future<void> _startRefresh() {
    if (_disposed) {
      return Future<void>.error(
        const AccountPortfolioException(AccountPortfolioIssue.closed),
      );
    }
    if (_invalidated) {
      return Future<void>.error(
        const AccountPortfolioException(AccountPortfolioIssue.accountChanged),
      );
    }
    if (_readerClosed) {
      return Future<void>.error(
        const AccountPortfolioException(AccountPortfolioIssue.closed),
      );
    }
    if (!_online) {
      _publish(
        AccountPortfolioPhase.offline,
        context: _state.context,
        portfolio: _state.portfolio,
        issue: AccountPortfolioIssue.unavailable,
      );
      return Future<void>.value();
    }
    final active = _inFlight;
    if (active != null) {
      if (_state._phase == AccountPortfolioPhase.loading) return active;
      final queued = _queuedRefresh;
      if (queued != null) return queued;
      late final Future<void> restart;
      restart = active
          .then((_) {
            if (identical(_queuedRefresh, restart)) _queuedRefresh = null;
            return _startRefresh();
          })
          .whenComplete(() {
            if (identical(_queuedRefresh, restart)) _queuedRefresh = null;
          });
      _queuedRefresh = restart;
      return restart;
    }

    final generation = ++_generation;
    final previous = _state.portfolio;
    _publish(
      AccountPortfolioPhase.loading,
      context: _state.context,
      portfolio: previous,
    );
    late final Future<void> operation;
    operation = _refresh(generation, previous).whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    _inFlight = operation;
    return operation;
  }

  Future<void> _refresh(
    int generation,
    AccountPortfolioSnapshot? previous,
  ) async {
    AccountContextSnapshot? context = _state.context;
    var retained = previous;
    try {
      context = await _reader.readContext();
      if (!_current(generation)) return;
      if (context.userId != accountId) {
        throw const AccountDataException(AccountDataFailure.accountMismatch);
      }

      final wallet = context.embeddedSolanaWallet;
      switch (wallet.status) {
        case EmbeddedSolanaWalletStatus.missing:
          _publish(
            AccountPortfolioPhase.error,
            context: context,
            portfolio: null,
            issue: AccountPortfolioIssue.walletMissing,
          );
          return;
        case EmbeddedSolanaWalletStatus.ambiguous:
          _publish(
            AccountPortfolioPhase.error,
            context: context,
            portfolio: null,
            issue: AccountPortfolioIssue.walletAmbiguous,
          );
          return;
        case EmbeddedSolanaWalletStatus.candidate:
          break;
      }

      final address = wallet.address!;
      if (retained?.holdings.wallet.address != address) retained = null;
      _publish(
        AccountPortfolioPhase.loading,
        context: context,
        portfolio: retained,
      );

      final holdings = await _reader.readHoldings(
        minimumObservedSlot: _minimumObservedSlot,
      );
      if (!_current(generation)) return;
      if (holdings.userId != accountId) {
        throw const AccountDataException(AccountDataFailure.accountMismatch);
      }
      if (holdings.wallet.address != address) {
        retained = null;
        throw const AccountPortfolioException(
          AccountPortfolioIssue.walletChanged,
        );
      }
      if (!_observesConfirmedSlot(holdings)) {
        throw const AccountPortfolioException(
          AccountPortfolioIssue.observationExpired,
        );
      }

      final acceptedAt = _now();
      final latestAllowed = acceptedAt.add(_maximumFutureSkew);
      if (holdings.observedAt.isAfter(latestAllowed)) {
        throw const AccountPortfolioException(
          AccountPortfolioIssue.observationInFuture,
        );
      }
      DateTime observationDeadline;
      DateTime receiptDeadline;
      try {
        observationDeadline = holdings.observedAt.add(_maximumObservationAge);
        receiptDeadline = acceptedAt.add(_maximumObservationAge);
      } catch (_) {
        throw const AccountPortfolioException(
          AccountPortfolioIssue.invalidResponse,
        );
      }
      final freshUntil = observationDeadline.isBefore(receiptDeadline)
          ? observationDeadline
          : receiptDeadline;
      if (!acceptedAt.isBefore(freshUntil)) {
        throw const AccountPortfolioException(
          AccountPortfolioIssue.observationExpired,
        );
      }
      if (!_current(generation)) return;

      final snapshot = AccountPortfolioSnapshot._(
        accountId: accountId,
        context: context,
        holdings: holdings,
        acceptedAt: acceptedAt,
        freshUntil: freshUntil,
      );
      _publish(
        AccountPortfolioPhase.ready,
        context: context,
        portfolio: snapshot,
      );
    } catch (error) {
      if (!_current(generation)) return;
      _publishFailure(error, context: context, retained: retained);
    }
  }

  void _publishFailure(
    Object error, {
    required AccountContextSnapshot? context,
    required AccountPortfolioSnapshot? retained,
  }) {
    final issue = switch (error) {
      AccountPortfolioException value => value.issue,
      AccountDataException value => _issueForDataFailure(value.failure),
      _ => AccountPortfolioIssue.unavailable,
    };
    if (issue == AccountPortfolioIssue.accountChanged) {
      _invalidated = true;
      _closeReader();
      _publish(
        AccountPortfolioPhase.accountChanged,
        context: null,
        portfolio: null,
        issue: issue,
      );
      return;
    }
    if (issue == AccountPortfolioIssue.closed) {
      _closeReader();
      _publish(
        AccountPortfolioPhase.closed,
        context: null,
        portfolio: null,
        issue: issue,
      );
      return;
    }
    final clearAccountData = issue == AccountPortfolioIssue.unauthenticated;
    final phase = switch (issue) {
      AccountPortfolioIssue.cancelled => AccountPortfolioPhase.cancelled,
      AccountPortfolioIssue.observationExpired => AccountPortfolioPhase.stale,
      AccountPortfolioIssue.unavailable ||
      AccountPortfolioIssue.timeout => AccountPortfolioPhase.offline,
      _ => AccountPortfolioPhase.error,
    };
    _publish(
      phase,
      context: clearAccountData ? null : context,
      portfolio: clearAccountData ? null : retained,
      issue: issue,
    );
  }

  void cancelRefresh() {
    if (_disposed || _invalidated || !isBusy) return;
    ++_generation;
    _cancelReader();
    _publish(
      AccountPortfolioPhase.cancelled,
      context: _state.context,
      portfolio: _state.portfolio,
      issue: AccountPortfolioIssue.cancelled,
    );
  }

  /// A connectivity hint. Coming online never spends quota automatically.
  void setNetworkAvailable(bool available) {
    if (_disposed || _invalidated || _online == available) return;
    _online = available;
    if (!available) {
      if (isBusy) {
        ++_generation;
        _cancelReader();
      }
      _publish(
        AccountPortfolioPhase.offline,
        context: _state.context,
        portfolio: _state.portfolio,
        issue: AccountPortfolioIssue.unavailable,
      );
      return;
    }
    final portfolio = _state.portfolio;
    final now = _safeNow();
    if (now == null) {
      _publish(
        AccountPortfolioPhase.error,
        context: _state.context,
        portfolio: portfolio,
        issue: AccountPortfolioIssue.invalidConfiguration,
      );
      return;
    }
    final isFresh =
        portfolio != null &&
        portfolio.isFreshAt(now) &&
        _observesConfirmedSlot(portfolio.holdings);
    _publish(
      portfolio == null
          ? AccountPortfolioPhase.idle
          : isFresh
          ? AccountPortfolioPhase.ready
          : AccountPortfolioPhase.stale,
      context: _state.context,
      portfolio: portfolio,
      issue: portfolio != null && !isFresh
          ? AccountPortfolioIssue.observationExpired
          : null,
    );
  }

  /// Permanently retires this account-bound repository when the active account
  /// changes. A new account must receive a new reader and repository instance.
  void invalidateForAccountSwitch({required String? activeAccountId}) {
    if (_disposed || _invalidated) return;
    String? normalized;
    try {
      normalized = activeAccountId == null
          ? null
          : normalizePracticeUuid(activeAccountId);
    } catch (_) {
      normalized = null;
    }
    if (normalized == accountId) return;
    _invalidated = true;
    ++_generation;
    _cancelReader();
    _closeReader();
    _publish(
      AccountPortfolioPhase.accountChanged,
      context: null,
      portfolio: null,
      issue: AccountPortfolioIssue.accountChanged,
    );
  }

  bool _current(int generation) =>
      !_disposed && !_invalidated && generation == _generation;

  DateTime _now() =>
      _safeNow() ??
      (throw const AccountPortfolioException(
        AccountPortfolioIssue.invalidConfiguration,
      ));

  DateTime? _safeNow() {
    try {
      final value = _clock().toUtc();
      if (value.year < 1 || value.year > 9999) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  void _publish(
    AccountPortfolioPhase phase, {
    required AccountContextSnapshot? context,
    required AccountPortfolioSnapshot? portfolio,
    AccountPortfolioIssue? issue,
  }) {
    _clearExpiry();
    _state = AccountPortfolioState._(
      phase,
      issue,
      _clock,
      accountId: accountId,
      context: context,
      portfolio: portfolio,
    );
    if (phase == AccountPortfolioPhase.ready && portfolio != null) {
      final schedulingIssue = _scheduleExpiry(portfolio);
      if (schedulingIssue != null) {
        _state = AccountPortfolioState._(
          schedulingIssue == AccountPortfolioIssue.observationExpired
              ? AccountPortfolioPhase.stale
              : AccountPortfolioPhase.error,
          schedulingIssue,
          _clock,
          accountId: accountId,
          context: context,
          portfolio: portfolio,
        );
      }
    }
    if (!_disposed) notifyListeners();
  }

  AccountPortfolioIssue? _scheduleExpiry(AccountPortfolioSnapshot portfolio) {
    if (_disposed || _invalidated || !_online) return null;
    final now = _safeNow();
    if (now == null) return AccountPortfolioIssue.invalidConfiguration;
    final remaining = portfolio.freshUntil.difference(now);
    if (remaining <= Duration.zero) {
      return AccountPortfolioIssue.observationExpired;
    }
    try {
      _expiryTimer = _timerFactory(remaining, () => _expire(portfolio));
    } catch (_) {
      _expiryTimer = null;
      return AccountPortfolioIssue.invalidConfiguration;
    }
    return null;
  }

  void _expire(AccountPortfolioSnapshot portfolio) {
    _expiryTimer = null;
    if (_disposed ||
        _invalidated ||
        !_online ||
        _state._phase != AccountPortfolioPhase.ready ||
        !identical(_state.portfolio, portfolio)) {
      return;
    }
    final now = _safeNow();
    if (now == null) {
      _publish(
        AccountPortfolioPhase.error,
        context: _state.context,
        portfolio: portfolio,
        issue: AccountPortfolioIssue.invalidConfiguration,
      );
      return;
    }
    if (portfolio.isFreshAt(now)) {
      final schedulingIssue = _scheduleExpiry(portfolio);
      if (schedulingIssue != null) {
        _publish(
          schedulingIssue == AccountPortfolioIssue.observationExpired
              ? AccountPortfolioPhase.stale
              : AccountPortfolioPhase.error,
          context: _state.context,
          portfolio: portfolio,
          issue: schedulingIssue,
        );
      }
      return;
    }
    _publish(
      AccountPortfolioPhase.stale,
      context: _state.context,
      portfolio: portfolio,
      issue: AccountPortfolioIssue.observationExpired,
    );
  }

  void _closeReader() {
    if (_readerClosed) return;
    _readerClosed = true;
    try {
      _reader.close();
    } catch (_) {
      // Disposal and account invalidation remain terminal even if an adapter
      // violates its synchronous close contract.
    }
  }

  void _cancelReader() {
    try {
      _reader.cancelPending();
    } catch (_) {
      // Cancellation still invalidates the repository generation even if an
      // adapter violates its synchronous cancellation contract.
    }
  }

  void _clearExpiry() {
    final timer = _expiryTimer;
    _expiryTimer = null;
    if (timer == null) return;
    try {
      timer.cancel();
    } catch (_) {
      // State replacement and disposal remain terminal for a bad timer.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _clearExpiry();
    _cancelReader();
    _closeReader();
    _state = AccountPortfolioState._(
      AccountPortfolioPhase.closed,
      AccountPortfolioIssue.closed,
      _clock,
      accountId: accountId,
      context: null,
      portfolio: null,
    );
    super.dispose();
  }
}

AccountPortfolioIssue _issueForDataFailure(
  AccountDataFailure failure,
) => switch (failure) {
  AccountDataFailure.invalidConfiguration =>
    AccountPortfolioIssue.invalidConfiguration,
  AccountDataFailure.invalidRequest => AccountPortfolioIssue.invalidRequest,
  AccountDataFailure.unauthenticated => AccountPortfolioIssue.unauthenticated,
  AccountDataFailure.accountMismatch => AccountPortfolioIssue.accountChanged,
  AccountDataFailure.walletMissing => AccountPortfolioIssue.walletMissing,
  AccountDataFailure.walletAmbiguous => AccountPortfolioIssue.walletAmbiguous,
  AccountDataFailure.unavailable => AccountPortfolioIssue.unavailable,
  AccountDataFailure.notConfigured => AccountPortfolioIssue.notConfigured,
  AccountDataFailure.invalidResponse => AccountPortfolioIssue.invalidResponse,
  AccountDataFailure.timeout => AccountPortfolioIssue.timeout,
  AccountDataFailure.cancelled => AccountPortfolioIssue.cancelled,
  AccountDataFailure.busy => AccountPortfolioIssue.busy,
  AccountDataFailure.closed => AccountPortfolioIssue.closed,
};
