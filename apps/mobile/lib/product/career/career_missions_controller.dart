import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../account/guest_session.dart';
import 'career_repository.dart';

/// Keeps the server-authored mission board bound to one paper principal.
///
/// Mission completion remains server-owned. Late reads and promotion receipts
/// from a previous identity are discarded after bind or unbind changes the
/// generation.
final class CareerMissionsController extends ChangeNotifier {
  CareerRepository? _repository;
  String? _principalKey;
  CareerMissionBoard? _board;
  CareerPromotionReceipt? _lastPromotion;
  CareerFailure? _failure;
  GuestSessionFailure? _guestSessionFailure;
  bool _loading = false;
  bool _promoting = false;
  bool _stale = false;
  bool _refreshQueued = false;
  bool _disposed = false;
  int _generation = 0;
  Future<CareerPromotionReceipt?>? _activePromotion;
  String? _activePromotionMutationId;
  CareerRank? _activePromotionTarget;

  String? get principalKey => _principalKey;
  CareerMissionBoard? get board => _board;
  CareerPromotionReceipt? get lastPromotion => _lastPromotion;
  CareerFailure? get failure => _failure;
  GuestSessionFailure? get guestSessionFailure => _guestSessionFailure;
  bool get loading => _loading;
  bool get promoting => _promoting;
  bool get stale => _stale;
  bool get hasConfirmedBoard => _board != null;

  Future<void> bind({
    required String principalKey,
    required CareerRepository repository,
  }) async {
    if (_disposed || principalKey.isEmpty) return;
    if (_principalKey == principalKey && identical(_repository, repository)) {
      await refresh();
      return;
    }
    _generation++;
    _principalKey = principalKey;
    _repository = repository;
    _board = null;
    _lastPromotion = null;
    _failure = null;
    _guestSessionFailure = null;
    _loading = false;
    _promoting = false;
    _stale = false;
    _refreshQueued = false;
    _activePromotion = null;
    _activePromotionMutationId = null;
    _activePromotionTarget = null;
    notifyListeners();
    await refresh();
  }

  void unbind() {
    if (_disposed) return;
    _generation++;
    _principalKey = null;
    _repository = null;
    _board = null;
    _lastPromotion = null;
    _failure = null;
    _guestSessionFailure = null;
    _loading = false;
    _promoting = false;
    _stale = false;
    _refreshQueued = false;
    _activePromotion = null;
    _activePromotionMutationId = null;
    _activePromotionTarget = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    final repository = _repository;
    final principalKey = _principalKey;
    if (_disposed || repository == null || principalKey == null) return;
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    final generation = _generation;
    _loading = true;
    notifyListeners();
    try {
      final board = await repository.getMissions();
      if (!_owns(generation, principalKey, repository)) return;
      _board = board;
      _failure = null;
      _guestSessionFailure = null;
      _stale = false;
    } on GuestSessionException catch (error) {
      if (!_owns(generation, principalKey, repository)) return;
      _failure = null;
      _guestSessionFailure = error.failure;
      _stale = _board != null;
    } on CareerException catch (error) {
      if (!_owns(generation, principalKey, repository)) return;
      _failure = error.failure;
      _guestSessionFailure = null;
      _stale = _board != null;
    } catch (_) {
      if (!_owns(generation, principalKey, repository)) return;
      _failure = CareerFailure.unavailable;
      _guestSessionFailure = null;
      _stale = _board != null;
    } finally {
      if (_owns(generation, principalKey, repository)) {
        _loading = false;
        final again = _refreshQueued;
        _refreshQueued = false;
        notifyListeners();
        if (again) unawaited(refresh());
      }
    }
  }

  Future<CareerPromotionReceipt?> promote(CareerPromotionCommand command) {
    final repository = _repository;
    final principalKey = _principalKey;
    if (_disposed || repository == null || principalKey == null) {
      return Future<CareerPromotionReceipt?>.value();
    }
    final active = _activePromotion;
    if (active != null) {
      if (_activePromotionMutationId == command.mutationId &&
          _activePromotionTarget == command.targetRank) {
        return active;
      }
      _failure = CareerFailure.invalidInput;
      _guestSessionFailure = null;
      notifyListeners();
      return Future<CareerPromotionReceipt?>.value();
    }

    final generation = _generation;
    _activePromotionMutationId = command.mutationId;
    _activePromotionTarget = command.targetRank;
    final completer = Completer<CareerPromotionReceipt?>();
    final future = completer.future;
    // Publish the in-flight operation before _performPromotion can notify a
    // synchronous listener. A listener that re-enters promote must observe and
    // share this exact future instead of starting a second repository write.
    _activePromotion = future;
    unawaited(
      _completePromotion(
        completer: completer,
        generation: generation,
        principalKey: principalKey,
        repository: repository,
        command: command,
      ),
    );
    return future;
  }

  Future<void> _completePromotion({
    required Completer<CareerPromotionReceipt?> completer,
    required int generation,
    required String principalKey,
    required CareerRepository repository,
    required CareerPromotionCommand command,
  }) async {
    try {
      completer.complete(
        await _performPromotion(
          generation: generation,
          principalKey: principalKey,
          repository: repository,
          command: command,
        ),
      );
    } catch (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
  }

  Future<CareerPromotionReceipt?> _performPromotion({
    required int generation,
    required String principalKey,
    required CareerRepository repository,
    required CareerPromotionCommand command,
  }) async {
    _promoting = true;
    _failure = null;
    _guestSessionFailure = null;
    notifyListeners();
    try {
      final receipt = await repository.promote(command);
      if (!_owns(generation, principalKey, repository)) return null;
      _lastPromotion = receipt;
      _failure = null;
      _guestSessionFailure = null;
      await refresh();
      if (!_owns(generation, principalKey, repository)) return null;
      return receipt;
    } on GuestSessionException catch (error) {
      if (!_owns(generation, principalKey, repository)) return null;
      _failure = null;
      _guestSessionFailure = error.failure;
      return null;
    } on CareerException catch (error) {
      if (!_owns(generation, principalKey, repository)) return null;
      _failure = error.failure;
      _guestSessionFailure = null;
      return null;
    } catch (_) {
      if (!_owns(generation, principalKey, repository)) return null;
      _failure = CareerFailure.unavailable;
      _guestSessionFailure = null;
      return null;
    } finally {
      if (_owns(generation, principalKey, repository)) {
        _promoting = false;
        // Keep the public operation installed while listeners observe the
        // completion transition. Re-entry during this notification must still
        // share the same idempotent Future rather than start another write.
        notifyListeners();
        _activePromotion = null;
        _activePromotionMutationId = null;
        _activePromotionTarget = null;
      }
    }
  }

  bool _owns(
    int generation,
    String principalKey,
    CareerRepository repository,
  ) =>
      !_disposed &&
      generation == _generation &&
      _principalKey == principalKey &&
      identical(_repository, repository);

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _repository = null;
    _principalKey = null;
    _board = null;
    _lastPromotion = null;
    _activePromotion = null;
    _activePromotionMutationId = null;
    _activePromotionTarget = null;
    super.dispose();
  }
}
