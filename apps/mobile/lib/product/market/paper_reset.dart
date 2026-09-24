import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'paper_portfolio.dart';

const paperResetConfirmation = 'reset my paper desk';
const _maximumSafeInteger = 9007199254740991;

enum PaperResetFailure {
  staleRevision,
  notNeeded,
  offline,
  timeout,
  unavailable,
  accountRequired,
  rateLimited,
  conflict,
  revisionExhausted,
  rejected,
  protectedStorage,
}

final class PaperResetException implements Exception {
  const PaperResetException(this.failure);

  final PaperResetFailure failure;

  @override
  String toString() => 'PaperResetException(${failure.name})';
}

@immutable
final class PaperResetRequest {
  factory PaperResetRequest({
    required String mutationId,
    required int baseRevision,
    String confirmation = paperResetConfirmation,
  }) {
    final normalizedMutationId = _uuid(mutationId);
    if (baseRevision < 0 ||
        baseRevision > _maximumSafeInteger ||
        confirmation != paperResetConfirmation) {
      _reject();
    }
    return PaperResetRequest._(
      mutationId: normalizedMutationId,
      baseRevision: baseRevision,
    );
  }

  const PaperResetRequest._({
    required this.mutationId,
    required this.baseRevision,
  });

  final String mutationId;
  final int baseRevision;

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'mutationId': mutationId,
    'baseRevision': baseRevision,
    'confirm': paperResetConfirmation,
  };

  static PaperResetRequest fromJson(Object? input) {
    final value = _object(input, const {
      'schemaVersion',
      'mutationId',
      'baseRevision',
      'confirm',
    });
    if (value['schemaVersion'] != 1) _reject();
    return PaperResetRequest(
      mutationId: _text(value['mutationId'], 36),
      baseRevision: _safeInteger(value['baseRevision']),
      confirmation: _text(value['confirm'], paperResetConfirmation.length),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaperResetRequest &&
      other.mutationId == mutationId &&
      other.baseRevision == baseRevision;

  @override
  int get hashCode => Object.hash(mutationId, baseRevision);
}

@immutable
final class PaperResetReceipt {
  const PaperResetReceipt({
    required this.mutationId,
    required this.previousRevision,
    required this.revision,
    required this.resetAt,
  });

  final String mutationId;
  final int previousRevision;
  final int revision;
  final DateTime resetAt;
}

@immutable
final class PaperResetPortfolio {
  const PaperResetPortfolio({
    required this.revision,
    required this.startingCashPaper,
    required this.cashPaper,
  });

  final int revision;
  final String startingCashPaper;
  final String cashPaper;

  PaperPortfolioSnapshot toSnapshot() => PaperPortfolioSnapshot(
    revision: revision,
    startingCashPaper: startingCashPaper,
    cashPaper: cashPaper,
    positions: const [],
    recentOrders: const [],
    valuation: PaperPortfolioValuation.notIncluded(
      portfolioRevision: revision,
      cashPaper: cashPaper,
      openPositions: const [],
    ),
    openedAt: null,
    updatedAt: null,
  );
}

@immutable
final class PaperResetResult {
  factory PaperResetResult({
    required PaperResetRequest request,
    required PaperResetReceipt receipt,
    required PaperResetPortfolio portfolio,
  }) {
    if (receipt.mutationId != request.mutationId ||
        receipt.previousRevision != request.baseRevision ||
        receipt.previousRevision >= _maximumSafeInteger ||
        receipt.revision != receipt.previousRevision + 1 ||
        !receipt.resetAt.isUtc ||
        portfolio.revision != receipt.revision ||
        portfolio.startingCashPaper != '10000' ||
        portfolio.cashPaper != '10000') {
      _reject();
    }
    return PaperResetResult._(
      request: request,
      receipt: receipt,
      portfolio: portfolio,
    );
  }

  const PaperResetResult._({
    required this.request,
    required this.receipt,
    required this.portfolio,
  });

  final PaperResetRequest request;
  final PaperResetReceipt receipt;
  final PaperResetPortfolio portfolio;
}

abstract interface class PaperResetRepository {
  Future<PaperResetResult> reset(PaperResetRequest request);
}

abstract interface class PaperResetMutationStore {
  Future<PaperResetRequest?> read(String principalKey);
  Future<void> write(String principalKey, PaperResetRequest request);
  Future<void> clear(String principalKey, PaperResetRequest request);
}

/// Persists only an idempotency UUID and its exact public reset payload.
/// Credentials and authorization material never enter SharedPreferences.
final class PreferencesPaperResetMutationStore
    implements PaperResetMutationStore {
  PreferencesPaperResetMutationStore(this._preferences);

  static const _prefix = 'trimmy.paper.reset-pending.v1.';
  final SharedPreferences _preferences;

  @override
  Future<PaperResetRequest?> read(String principalKey) async {
    final key = _key(principalKey);
    try {
      final raw = _preferences.getString(key);
      if (raw == null) return null;
      return PaperResetRequest.fromJson(jsonDecode(raw));
    } catch (_) {
      throw const PaperResetException(PaperResetFailure.protectedStorage);
    }
  }

  @override
  Future<void> write(String principalKey, PaperResetRequest request) async {
    final key = _key(principalKey);
    try {
      final existing = await read(principalKey);
      if (existing != null && existing != request) {
        throw const PaperResetException(PaperResetFailure.protectedStorage);
      }
      if (existing == request) return;
      final written = await _preferences.setString(
        key,
        jsonEncode(request.toJson()),
      );
      if (!written) {
        throw const PaperResetException(PaperResetFailure.protectedStorage);
      }
    } on PaperResetException {
      rethrow;
    } catch (_) {
      throw const PaperResetException(PaperResetFailure.protectedStorage);
    }
  }

  @override
  Future<void> clear(String principalKey, PaperResetRequest request) async {
    final key = _key(principalKey);
    try {
      final existing = await read(principalKey);
      if (existing == null) return;
      if (existing != request) {
        throw const PaperResetException(PaperResetFailure.protectedStorage);
      }
      final removed = await _preferences.remove(key);
      if (!removed) {
        throw const PaperResetException(PaperResetFailure.protectedStorage);
      }
    } on PaperResetException {
      rethrow;
    } catch (_) {
      throw const PaperResetException(PaperResetFailure.protectedStorage);
    }
  }

  static String _key(String principalKey) => '$_prefix${_uuid(principalKey)}';
}

enum PaperResetPhase {
  idle,
  pending,
  submitting,
  succeeded,
  stale,
  notNeeded,
  failed,
}

@immutable
final class PaperResetState {
  const PaperResetState({
    required this.phase,
    this.pending,
    this.result,
    this.failure,
  });

  const PaperResetState.idle() : this(phase: PaperResetPhase.idle);

  final PaperResetPhase phase;
  final PaperResetRequest? pending;
  final PaperResetResult? result;
  final PaperResetFailure? failure;

  bool get busy => phase == PaperResetPhase.submitting;
  bool get hasPendingMutation => pending != null;
}

/// Owns one principal's exact reset mutation. Ambiguous failures retain the
/// request, so every retry and restart replays the same UUID and base revision.
final class PaperResetController extends ChangeNotifier {
  factory PaperResetController({
    required String principalKey,
    required PaperResetRepository repository,
    required PaperResetMutationStore store,
    required String Function() mutationId,
  }) => PaperResetController._(principalKey, repository, store, mutationId);

  PaperResetController._(
    this.principalKey,
    this._repository,
    this._store,
    this._mutationId,
  );

  final String principalKey;
  final PaperResetRepository _repository;
  final PaperResetMutationStore _store;
  final String Function() _mutationId;
  PaperResetState _state = const PaperResetState.idle();
  Future<PaperResetResult>? _inFlight;
  bool _disposed = false;

  PaperResetState get state => _state;

  Future<void> initialize() async {
    if (_disposed || _state.phase != PaperResetPhase.idle) return;
    try {
      final pending = await _store.read(principalKey);
      if (_disposed) return;
      if (pending != null) {
        _setState(
          PaperResetState(phase: PaperResetPhase.pending, pending: pending),
        );
      }
    } on PaperResetException catch (error) {
      if (!_disposed) {
        _setState(
          PaperResetState(
            phase: PaperResetPhase.failed,
            failure: error.failure,
          ),
        );
      }
      rethrow;
    }
  }

  Future<PaperResetResult> submit({required int baseRevision}) {
    final active = _inFlight;
    if (active != null) return active;
    late final Future<PaperResetResult> tracked;
    tracked = _submit(baseRevision: baseRevision).whenComplete(() {
      if (identical(_inFlight, tracked)) _inFlight = null;
    });
    _inFlight = tracked;
    return tracked;
  }

  Future<PaperResetResult> resumePending() {
    final pending = _state.pending;
    if (pending == null) {
      throw const PaperResetException(PaperResetFailure.rejected);
    }
    return submit(baseRevision: pending.baseRevision);
  }

  Future<PaperResetResult> _submit({required int baseRevision}) async {
    if (_disposed) {
      throw const PaperResetException(PaperResetFailure.unavailable);
    }
    PaperResetRequest? request = _state.pending;
    try {
      request ??= PaperResetRequest(
        mutationId: _mutationId(),
        baseRevision: baseRevision,
      );
      await _store.write(principalKey, request);
      if (_disposed) {
        throw const PaperResetException(PaperResetFailure.unavailable);
      }
      _setState(
        PaperResetState(phase: PaperResetPhase.submitting, pending: request),
      );
      final result = await _repository.reset(request);
      if (result.request != request) _reject();
      if (!_disposed) {
        _setState(
          PaperResetState(
            phase: PaperResetPhase.succeeded,
            pending: request,
            result: result,
          ),
        );
      }
      return result;
    } on PaperResetException catch (error) {
      final resolvedRequest = request;
      final discard = _definitiveFailure(error.failure);
      if (discard && resolvedRequest != null) {
        try {
          await _store.clear(principalKey, resolvedRequest);
        } on PaperResetException catch (storageError) {
          if (!_disposed) {
            _setState(
              PaperResetState(
                phase: PaperResetPhase.failed,
                pending: resolvedRequest,
                failure: storageError.failure,
              ),
            );
          }
          rethrow;
        } catch (_) {
          const storageError = PaperResetException(
            PaperResetFailure.protectedStorage,
          );
          if (!_disposed) {
            _setState(
              PaperResetState(
                phase: PaperResetPhase.failed,
                pending: resolvedRequest,
                failure: storageError.failure,
              ),
            );
          }
          throw storageError;
        }
      }
      if (!_disposed) {
        _setState(
          PaperResetState(
            phase: switch (error.failure) {
              PaperResetFailure.staleRevision => PaperResetPhase.stale,
              PaperResetFailure.notNeeded => PaperResetPhase.notNeeded,
              _ => PaperResetPhase.failed,
            },
            pending: discard ? null : resolvedRequest,
            failure: error.failure,
          ),
        );
      }
      rethrow;
    } catch (_) {
      final failure = const PaperResetException(PaperResetFailure.unavailable);
      if (!_disposed) {
        _setState(
          PaperResetState(
            phase: PaperResetPhase.failed,
            pending: request,
            failure: failure.failure,
          ),
        );
      }
      throw failure;
    }
  }

  bool _definitiveFailure(PaperResetFailure failure) => switch (failure) {
    PaperResetFailure.staleRevision ||
    PaperResetFailure.notNeeded ||
    PaperResetFailure.conflict ||
    PaperResetFailure.revisionExhausted ||
    PaperResetFailure.rejected => true,
    _ => false,
  };

  /// Clears the durable replay only after the caller has persisted its reset
  /// revision floor. Until this acknowledgement, restart replays the same UUID.
  Future<bool> acknowledgeApplied(PaperResetResult result) async {
    if (_disposed) {
      throw const PaperResetException(PaperResetFailure.unavailable);
    }
    final pending = _state.pending;
    if (pending == null) {
      if (_state.phase == PaperResetPhase.succeeded &&
          identical(_state.result, result)) {
        return true;
      }
      _reject();
    }
    if (pending != result.request || !identical(_state.result, result)) {
      _reject();
    }
    try {
      await _store.clear(principalKey, pending);
    } on PaperResetException catch (error) {
      if (!_disposed) {
        _setState(
          PaperResetState(
            phase: PaperResetPhase.succeeded,
            pending: pending,
            result: result,
            failure: error.failure,
          ),
        );
      }
      return false;
    }
    if (!_disposed) {
      _setState(
        PaperResetState(phase: PaperResetPhase.succeeded, result: result),
      );
    }
    return true;
  }

  void _setState(PaperResetState value) {
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

Map<String, dynamic> _object(Object? input, Set<String> keys) {
  if (input is! Map<String, dynamic> ||
      input.length != keys.length ||
      !input.keys.toSet().containsAll(keys)) {
    _reject();
  }
  return input;
}

String _text(Object? input, int maximum) {
  if (input is! String ||
      input.isEmpty ||
      input.length > maximum ||
      input.trim() != input ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(input)) {
    _reject();
  }
  return input;
}

String _uuid(Object? input) {
  final value = _text(input, 36).toLowerCase();
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(value)) {
    _reject();
  }
  return value;
}

int _safeInteger(Object? input) {
  if (input is! int || input < 0 || input > _maximumSafeInteger) _reject();
  return input;
}

Never _reject() => throw const PaperResetException(PaperResetFailure.rejected);
