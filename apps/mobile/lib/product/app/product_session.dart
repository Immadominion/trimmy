import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../account/guest_session.dart';
import '../onboarding/onboarding_models.dart';
import 'product_profile_repository.dart';

enum ProductLaunchStep {
  onboarding,
  firstTrade,
  firstPosition,
  dayOne,
  saveDesk,
  app,
}

/// Owns the first-use sequence. Production sessions bind to one server-owned
/// guest or account profile. The v1 local state remains only as an offline
/// development fallback and as input for a later one-time migration.
final class ProductSession extends ChangeNotifier {
  ProductSession._(this._preferences) {
    _restoreLocal();
  }

  static const _profileKey = 'trimmy.product.profile.v1';
  static const _notificationKey = 'trimmy.product.notifications.v1';
  static const _firstTradeKey = 'trimmy.product.first-trade.v1';
  static const _firstPositionKey = 'trimmy.product.first-position.v1';
  static const _dayOneKey = 'trimmy.product.day-one.v1';
  static const _accountGateKey = 'trimmy.product.account-gate.v1';
  static const _introductionExitedKey = 'trimmy.product.introduction-exited.v1';
  static const _remoteCachePrefix = 'trimmy.product.profile-cache.v1.';

  factory ProductSession.fromPreferences(SharedPreferences preferences) =>
      ProductSession._(preferences);

  final SharedPreferences _preferences;
  OnboardingProfile? _profile;
  OnboardingNotificationStatus _notificationStatus =
      OnboardingNotificationStatus.notRequested;
  var _firstTradeComplete = false;
  var _firstPositionCollected = false;
  var _dayOneSeen = false;
  var _accountGateSeen = false;
  var _introductionExited = false;
  // Skip may need two server writes. Keep the note visible through both,
  // including a failed second write, instead of flashing the practice picker.
  var _holdIntroductionForSkip = false;
  String? _loadIssue;

  ProductProfileRepository? _remoteRepository;
  ProductProfileSnapshot? _remoteSnapshot;
  String? _remotePrincipalKey;
  String Function()? _mutationIdFactory;
  _PendingProfileWrite? _pendingWrite;
  _PendingLaunchAction? _pendingLaunch;
  _InFlightProfileWrite? _writeInFlight;
  _InFlightLaunchAction? _launchInFlight;
  final Map<String, Future<void>> _cacheOperations = {};
  ProductProfileFailure? _remoteFailure;
  GuestSessionFailure? _remoteGuestFailure;
  bool _remoteLoading = false;
  int _remoteGeneration = 0;

  OnboardingProfile? get profile => _profile;
  OnboardingNotificationStatus get notificationStatus => _notificationStatus;
  bool get firstTradeComplete => _firstTradeComplete;
  bool get firstPositionCollected => _firstPositionCollected;
  bool get dayOneSeen => _dayOneSeen;
  bool get accountGateSeen => _accountGateSeen;
  String? get loadIssue => _loadIssue;
  bool get remoteLoading => _remoteLoading;
  ProductProfileFailure? get remoteFailure => _remoteFailure;
  GuestSessionFailure? get remoteGuestFailure => _remoteGuestFailure;
  bool get hasRemoteSnapshot => _remoteSnapshot != null;
  String? get remotePrincipalKey => _remotePrincipalKey;

  bool remoteBoundTo(String principalKey) =>
      _remotePrincipalKey == principalKey && _remoteRepository != null;

  bool get remoteProfileUsable =>
      !_remoteLoading &&
      _remoteGuestFailure == null &&
      (_remoteFailure == null || _remoteSnapshot != null);

  ProductLaunchStep get launchStep {
    if (_holdIntroductionForSkip) return ProductLaunchStep.onboarding;
    if (_introductionExited) return ProductLaunchStep.app;
    if (_profile == null) return ProductLaunchStep.onboarding;
    if (!_firstTradeComplete) return ProductLaunchStep.firstTrade;
    if (!_firstPositionCollected) return ProductLaunchStep.firstPosition;
    if (!_dayOneSeen) return ProductLaunchStep.dayOne;
    if (!_accountGateSeen) return ProductLaunchStep.saveDesk;
    return ProductLaunchStep.app;
  }

  /// Authentication is an explicit entry to the saved Home. Creating the
  /// optional profile/checkpoint here does not claim a trade or copy another
  /// principal's progress. The server owns the resulting checkpoint.
  Future<void> enterSignedInApp() async {
    if (!remoteProfileUsable || _remoteRepository == null) {
      throw const ProductProfileException(ProductProfileFailure.notReady);
    }
    if (launchStep != ProductLaunchStep.app) await skipIntroduction();
  }

  Future<void> bindRemote({
    required String principalKey,
    required ProductProfileRepository repository,
    required String Function() mutationIdFactory,
  }) async {
    if (principalKey.isEmpty) {
      throw const ProductProfileException(ProductProfileFailure.rejected);
    }
    if (_remotePrincipalKey == principalKey &&
        identical(_remoteRepository, repository)) {
      return;
    }
    final generation = ++_remoteGeneration;
    _holdIntroductionForSkip = false;
    _remoteRepository = repository;
    _remotePrincipalKey = principalKey;
    _mutationIdFactory = mutationIdFactory;
    _remoteSnapshot = null;
    _pendingWrite = null;
    _pendingLaunch = null;
    _writeInFlight = null;
    _launchInFlight = null;
    _remoteFailure = null;
    _remoteGuestFailure = null;
    _remoteLoading = true;
    _loadIssue = null;
    _clearProductState();
    _notificationStatus = _notificationFor(principalKey);
    notifyListeners();
    await _readRemote(generation, allowCache: true);
  }

  Future<void> retryRemoteRead() async {
    if (_remoteRepository == null || _remotePrincipalKey == null) return;
    final generation = ++_remoteGeneration;
    _remoteLoading = true;
    _remoteFailure = null;
    _remoteGuestFailure = null;
    _loadIssue = null;
    notifyListeners();
    await _readRemote(generation, allowCache: true);
  }

  void unbindRemote({required bool useLocalFallback}) {
    if (_remoteRepository == null &&
        _remotePrincipalKey == null &&
        useLocalFallback) {
      return;
    }
    _remoteGeneration++;
    _holdIntroductionForSkip = false;
    _remoteRepository = null;
    _remoteSnapshot = null;
    _remotePrincipalKey = null;
    _mutationIdFactory = null;
    _pendingWrite = null;
    _pendingLaunch = null;
    _writeInFlight = null;
    _launchInFlight = null;
    _remoteFailure = null;
    _remoteGuestFailure = null;
    _remoteLoading = false;
    if (useLocalFallback) {
      _restoreLocal();
    } else {
      _clearProductState();
      _notificationStatus = OnboardingNotificationStatus.unavailable;
      _loadIssue = null;
    }
    notifyListeners();
  }

  Future<void> _readRemote(int generation, {required bool allowCache}) async {
    final repository = _remoteRepository;
    final principalKey = _remotePrincipalKey;
    if (repository == null || principalKey == null) return;
    final cached = allowCache ? _readCached(principalKey) : null;
    try {
      final snapshot = await repository.read();
      if (!_isCurrentRemote(generation, repository, principalKey)) return;
      if (snapshot == null) {
        await _removeCached(principalKey);
      } else {
        await _cache(snapshot, principalKey);
      }
      if (!_isCurrentRemote(generation, repository, principalKey)) return;
      _remoteSnapshot = snapshot;
      _remoteFailure = null;
      _remoteGuestFailure = null;
      _remoteLoading = false;
      _loadIssue = null;
      _applyRemoteSnapshot(snapshot);
      if (snapshot != null) {
        final pendingWrite = _pendingWrite;
        if (pendingWrite != null &&
            snapshot.revision >= pendingWrite.baseRevision + 1 &&
            snapshot.onboarding == pendingWrite.onboarding &&
            snapshot.launchCheckpoint.index >= pendingWrite.checkpoint.index) {
          _pendingWrite = null;
        }
        final pendingLaunch = _pendingLaunch;
        if (pendingLaunch != null &&
            snapshot.revision >= pendingLaunch.baseRevision + 1 &&
            snapshot.launchCheckpoint.index >= pendingLaunch.checkpoint.index) {
          _pendingLaunch = null;
        }
      }
      notifyListeners();
    } on GuestSessionException catch (error) {
      if (!_isCurrentRemote(generation, repository, principalKey)) return;
      _remoteSnapshot = cached;
      _remoteFailure = null;
      _remoteGuestFailure = error.failure;
      _remoteLoading = false;
      _loadIssue = 'This guest desk needs recovery.';
      _applyRemoteSnapshot(cached);
      notifyListeners();
    } on ProductProfileException catch (error) {
      if (!_isCurrentRemote(generation, repository, principalKey)) return;
      _remoteSnapshot = cached;
      _remoteFailure = error.failure;
      _remoteGuestFailure = null;
      _remoteLoading = false;
      _loadIssue = _readIssue(error.failure);
      _applyRemoteSnapshot(cached);
      notifyListeners();
    } catch (_) {
      if (!_isCurrentRemote(generation, repository, principalKey)) return;
      _remoteSnapshot = cached;
      _remoteFailure = ProductProfileFailure.unavailable;
      _remoteGuestFailure = null;
      _remoteLoading = false;
      _loadIssue = _readIssue(ProductProfileFailure.unavailable);
      _applyRemoteSnapshot(cached);
      notifyListeners();
    }
  }

  bool _isCurrentRemote(
    int generation,
    ProductProfileRepository repository,
    String principalKey,
  ) =>
      generation == _remoteGeneration &&
      identical(repository, _remoteRepository) &&
      principalKey == _remotePrincipalKey;

  /// Starts the real practice flow without inventing questionnaire answers.
  Future<void> beginIntroduction() async {
    if (_holdIntroductionForSkip) {
      _holdIntroductionForSkip = false;
      notifyListeners();
    }
    await _ensureIntroductionProfile();
  }

  Future<void> _ensureIntroductionProfile() async {
    if (_profile != null) return;
    await completeOnboarding(
      OnboardingResult(
        profile: const OnboardingProfile(),
        notificationStatus: _notificationStatus,
      ),
    );
  }

  /// Leaves the entire introduction. Does not record a trade or a reward.
  Future<void> skipIntroduction() =>
      _exitIntroduction(ProductLaunchAction.introductionSkipped);

  /// Finishes after the real paper order; the server verifies the evidence.
  Future<void> finishIntroduction() =>
      _exitIntroduction(ProductLaunchAction.introductionCompleted);

  Future<void> _exitIntroduction(ProductLaunchAction action) async {
    final generation = _remoteGeneration;
    final principalKey = _remotePrincipalKey;
    if (action == ProductLaunchAction.introductionSkipped &&
        launchStep == ProductLaunchStep.onboarding) {
      _holdIntroductionForSkip = true;
    }
    await _ensureIntroductionProfile();
    if (generation != _remoteGeneration ||
        principalKey != _remotePrincipalKey) {
      throw const ProductProfileException(
        ProductProfileFailure.principalChanged,
      );
    }
    if (_remoteRepository != null) {
      await _advanceRemote(action, ProductProfileCheckpoint.app);
      _holdIntroductionForSkip = false;
      notifyListeners();
      return;
    }
    if (action == ProductLaunchAction.introductionCompleted &&
        !_firstTradeComplete) {
      throw StateError('TRADE_REQUIRED');
    }
    await _persistFlag(
      key: _introductionExitedKey,
      current: _introductionExited,
      set: (value) => _introductionExited = value,
    );
    _holdIntroductionForSkip = false;
    notifyListeners();
  }

  Future<void> completeOnboarding(OnboardingResult result) async {
    if (_remoteRepository != null) {
      await _writeRemote(result.profile, ProductProfileCheckpoint.firstTrade);
      _notificationStatus = result.notificationStatus;
      final principalKey = _remotePrincipalKey;
      if (principalKey != null) {
        unawaited(
          _preferences.setString(
            '$_notificationKey.$principalKey',
            result.notificationStatus.name,
          ),
        );
      }
      notifyListeners();
      return;
    }

    final previousProfile = _profile;
    final previousNotification = _notificationStatus;
    _profile = result.profile;
    _notificationStatus = result.notificationStatus;
    _loadIssue = null;
    notifyListeners();
    try {
      final writes = await Future.wait([
        _preferences.setString(
          _profileKey,
          jsonEncode(result.profile.toJson()),
        ),
        _preferences.setString(
          _notificationKey,
          result.notificationStatus.name,
        ),
      ]);
      if (writes.any((saved) => !saved)) throw StateError('PROFILE_NOT_SAVED');
    } catch (_) {
      _profile = previousProfile;
      _notificationStatus = previousNotification;
      _loadIssue = 'Your answers could not be saved. Try once more.';
      notifyListeners();
      rethrow;
    }
  }

  /// Persona is an optional choice after the first trade. Keep the server's
  /// current launch checkpoint instead of replaying onboarding.
  Future<void> choosePersona(TraderPersona persona) async {
    final current = _profile;
    if (current == null) {
      throw const ProductProfileException(ProductProfileFailure.unavailable);
    }
    if (current.persona == persona) return;
    final updated = OnboardingProfile(
      goal: current.goal,
      knowledge: current.knowledge,
      persona: persona,
      dailyGoal: current.dailyGoal,
      handle: current.handle,
    );
    if (_remoteRepository != null) {
      final checkpoint = _remoteSnapshot?.launchCheckpoint;
      if (checkpoint == null) {
        throw const ProductProfileException(ProductProfileFailure.unavailable);
      }
      await _writeRemote(updated, checkpoint);
      return;
    }
    await _preferences.setString(_profileKey, jsonEncode(updated.toJson()));
    _profile = updated;
    notifyListeners();
  }

  Future<void> markFirstTradeComplete() {
    if (_remoteRepository != null) {
      return _advanceRemote(
        ProductLaunchAction.paperTradeConfirmed,
        ProductProfileCheckpoint.firstPosition,
      );
    }
    return _persistFlag(
      key: _firstTradeKey,
      current: _firstTradeComplete,
      set: (value) => _firstTradeComplete = value,
    );
  }

  Future<void> markFirstPositionCollected() {
    if (!_firstTradeComplete) return Future.error(StateError('TRADE_REQUIRED'));
    if (_remoteRepository != null) {
      return _advanceRemote(
        ProductLaunchAction.firstPositionCollected,
        ProductProfileCheckpoint.streak,
      );
    }
    return _persistFlag(
      key: _firstPositionKey,
      current: _firstPositionCollected,
      set: (value) => _firstPositionCollected = value,
    );
  }

  Future<void> markDayOneSeen() {
    if (!_firstPositionCollected) {
      return Future.error(StateError('FIRST_POSITION_REQUIRED'));
    }
    if (_remoteRepository != null) {
      return _advanceRemote(
        ProductLaunchAction.dayOneSeen,
        ProductProfileCheckpoint.saveDesk,
      );
    }
    return _persistFlag(
      key: _dayOneKey,
      current: _dayOneSeen,
      set: (value) => _dayOneSeen = value,
    );
  }

  Future<void> markAccountGateLater() =>
      _markAccountGate(ProductLaunchAction.saveDeskLater);

  Future<void> markAccountGateSaved() =>
      _markAccountGate(ProductLaunchAction.saveDeskSaved);

  Future<void> _markAccountGate(ProductLaunchAction action) {
    if (!_dayOneSeen) return Future.error(StateError('DAY_ONE_REQUIRED'));
    if (_remoteRepository != null) {
      return _advanceRemote(action, ProductProfileCheckpoint.app);
    }
    return _persistFlag(
      key: _accountGateKey,
      current: _accountGateSeen,
      set: (value) => _accountGateSeen = value,
    );
  }

  Future<void> _advanceRemote(
    ProductLaunchAction action,
    ProductProfileCheckpoint desired,
  ) {
    final inFlight = _launchInFlight;
    if (inFlight != null) {
      if (inFlight.action == action && inFlight.checkpoint == desired) {
        return inFlight.future;
      }
      return Future<void>.error(
        const ProductProfileException(ProductProfileFailure.conflict),
      );
    }
    final operation = _advanceRemoteOnce(action, desired);
    final tracked = _InFlightLaunchAction(
      action: action,
      checkpoint: desired,
      future: operation,
    );
    _launchInFlight = tracked;
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_launchInFlight, tracked)) _launchInFlight = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_launchInFlight, tracked)) _launchInFlight = null;
        },
      ),
    );
    return operation;
  }

  Future<void> _advanceRemoteOnce(
    ProductLaunchAction action,
    ProductProfileCheckpoint desired,
  ) async {
    final profile = _profile;
    final current = _remoteSnapshot;
    final repository = _remoteRepository;
    final principalKey = _remotePrincipalKey;
    final mutationIdFactory = _mutationIdFactory;
    if (profile == null ||
        current == null ||
        repository == null ||
        principalKey == null ||
        mutationIdFactory == null ||
        _remoteLoading) {
      throw const ProductProfileException(ProductProfileFailure.unavailable);
    }
    if (current.launchCheckpoint.index >= desired.index) return;
    final exitingIntroduction =
        action == ProductLaunchAction.introductionSkipped ||
        action == ProductLaunchAction.introductionCompleted;
    if (!exitingIntroduction &&
        desired.index != current.launchCheckpoint.index + 1) {
      throw const ProductProfileException(ProductProfileFailure.conflict);
    }
    final pending = _pendingLaunch;
    final command =
        pending != null &&
            pending.baseRevision == current.revision &&
            pending.action == action &&
            pending.checkpoint == desired
        ? pending
        : _PendingLaunchAction(
            mutationId: mutationIdFactory(),
            baseRevision: current.revision,
            action: action,
            checkpoint: desired,
          );
    _pendingLaunch = command;
    final generation = _remoteGeneration;
    _loadIssue = null;
    try {
      final snapshot = await repository.advance(
        mutationId: command.mutationId,
        baseRevision: command.baseRevision,
        action: command.action,
      );
      if (!_isCurrentRemote(generation, repository, principalKey)) {
        throw const ProductProfileException(ProductProfileFailure.unavailable);
      }
      if ((action == ProductLaunchAction.introductionCompleted &&
              snapshot.hasConfirmedPaperTrade != true) ||
          snapshot.onboarding != profile ||
          snapshot.launchCheckpoint != desired ||
          snapshot.revision != command.baseRevision + 1) {
        throw const ProductProfileException(ProductProfileFailure.rejected);
      }
      await _cache(snapshot, principalKey);
      if (!_isCurrentRemote(generation, repository, principalKey)) {
        throw const ProductProfileException(ProductProfileFailure.unavailable);
      }
      _pendingLaunch = null;
      _remoteSnapshot = snapshot;
      _remoteFailure = null;
      _remoteGuestFailure = null;
      _loadIssue = null;
      _applyRemoteSnapshot(snapshot);
      notifyListeners();
    } on GuestSessionException catch (error) {
      if (!_isCurrentRemote(generation, repository, principalKey)) rethrow;
      _remoteFailure = null;
      _remoteGuestFailure = error.failure;
      _loadIssue = 'This guest desk needs recovery.';
      notifyListeners();
      rethrow;
    } on ProductProfileException catch (error) {
      if (!_isCurrentRemote(generation, repository, principalKey)) rethrow;
      _remoteGuestFailure = null;
      final latest = error.currentProfile;
      if (latest != null) {
        await _cache(latest, principalKey);
        if (!_isCurrentRemote(generation, repository, principalKey)) rethrow;
        _remoteSnapshot = latest;
        _applyRemoteSnapshot(latest);
      }
      if (error.failure != ProductProfileFailure.offline &&
          error.failure != ProductProfileFailure.timeout &&
          error.failure != ProductProfileFailure.unavailable) {
        _pendingLaunch = null;
      }
      if (latest != null &&
          (action != ProductLaunchAction.introductionCompleted ||
              latest.hasConfirmedPaperTrade == true) &&
          latest.onboarding == profile &&
          latest.launchCheckpoint.index >= desired.index) {
        _remoteFailure = null;
        _loadIssue = null;
        notifyListeners();
        return;
      }
      _remoteFailure = error.failure;
      _loadIssue = _writeIssue(error.failure);
      notifyListeners();
      rethrow;
    } catch (_) {
      if (_isCurrentRemote(generation, repository, principalKey)) {
        _remoteFailure = ProductProfileFailure.unavailable;
        _remoteGuestFailure = null;
        _loadIssue = _writeIssue(ProductProfileFailure.unavailable);
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> _writeRemote(
    OnboardingProfile onboarding,
    ProductProfileCheckpoint checkpoint,
  ) {
    final inFlight = _writeInFlight;
    if (inFlight != null) {
      if (inFlight.onboarding == onboarding &&
          inFlight.checkpoint == checkpoint) {
        return inFlight.future;
      }
      return Future<void>.error(
        const ProductProfileException(ProductProfileFailure.conflict),
      );
    }
    final operation = _writeRemoteOnce(onboarding, checkpoint);
    final tracked = _InFlightProfileWrite(
      onboarding: onboarding,
      checkpoint: checkpoint,
      future: operation,
    );
    _writeInFlight = tracked;
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_writeInFlight, tracked)) _writeInFlight = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_writeInFlight, tracked)) _writeInFlight = null;
        },
      ),
    );
    return operation;
  }

  Future<void> _writeRemoteOnce(
    OnboardingProfile onboarding,
    ProductProfileCheckpoint checkpoint,
  ) async {
    final repository = _remoteRepository;
    final principalKey = _remotePrincipalKey;
    final mutationIdFactory = _mutationIdFactory;
    if (repository == null ||
        principalKey == null ||
        mutationIdFactory == null ||
        _remoteLoading) {
      throw const ProductProfileException(ProductProfileFailure.unavailable);
    }
    final baseRevision = _remoteSnapshot?.revision ?? 0;
    final pending = _pendingWrite;
    final command =
        pending != null &&
            pending.baseRevision == baseRevision &&
            pending.onboarding == onboarding &&
            pending.checkpoint == checkpoint
        ? pending
        : _PendingProfileWrite(
            mutationId: mutationIdFactory(),
            baseRevision: baseRevision,
            onboarding: onboarding,
            checkpoint: checkpoint,
          );
    _pendingWrite = command;
    final generation = _remoteGeneration;
    _loadIssue = null;
    try {
      final snapshot = await repository.write(
        mutationId: command.mutationId,
        baseRevision: command.baseRevision,
        onboarding: command.onboarding,
        launchCheckpoint: command.checkpoint,
      );
      if (!_isCurrentRemote(generation, repository, principalKey)) {
        throw const ProductProfileException(ProductProfileFailure.unavailable);
      }
      if (snapshot.onboarding != onboarding ||
          snapshot.launchCheckpoint != checkpoint ||
          snapshot.revision != baseRevision + 1) {
        throw const ProductProfileException(ProductProfileFailure.rejected);
      }
      await _cache(snapshot, principalKey);
      if (!_isCurrentRemote(generation, repository, principalKey)) {
        throw const ProductProfileException(ProductProfileFailure.unavailable);
      }
      _pendingWrite = null;
      _remoteSnapshot = snapshot;
      _remoteFailure = null;
      _remoteGuestFailure = null;
      _loadIssue = null;
      _applyRemoteSnapshot(snapshot);
      notifyListeners();
    } on GuestSessionException catch (error) {
      if (!_isCurrentRemote(generation, repository, principalKey)) rethrow;
      _remoteFailure = null;
      _remoteGuestFailure = error.failure;
      _loadIssue = 'This guest desk needs recovery.';
      notifyListeners();
      rethrow;
    } on ProductProfileException catch (error) {
      if (!_isCurrentRemote(generation, repository, principalKey)) rethrow;
      _remoteGuestFailure = null;
      final current = error.currentProfile;
      if (current != null) {
        await _cache(current, principalKey);
        if (!_isCurrentRemote(generation, repository, principalKey)) rethrow;
        _remoteSnapshot = current;
        _applyRemoteSnapshot(current);
      }
      if (error.failure != ProductProfileFailure.offline &&
          error.failure != ProductProfileFailure.timeout &&
          error.failure != ProductProfileFailure.unavailable) {
        _pendingWrite = null;
      }
      if (current != null &&
          current.onboarding == onboarding &&
          current.launchCheckpoint.index >= checkpoint.index) {
        _remoteFailure = null;
        _loadIssue = null;
        notifyListeners();
        return;
      }
      _remoteFailure = error.failure;
      _loadIssue = _writeIssue(error.failure);
      notifyListeners();
      rethrow;
    } catch (_) {
      if (_isCurrentRemote(generation, repository, principalKey)) {
        _remoteFailure = ProductProfileFailure.unavailable;
        _remoteGuestFailure = null;
        _loadIssue = _writeIssue(ProductProfileFailure.unavailable);
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> _persistFlag({
    required String key,
    required bool current,
    required ValueChanged<bool> set,
  }) async {
    if (current) return;
    set(true);
    _loadIssue = null;
    notifyListeners();
    try {
      if (!await _preferences.setBool(key, true)) throw StateError('NOT_SAVED');
    } catch (_) {
      set(false);
      _loadIssue = 'That step could not be saved. Try again.';
      notifyListeners();
      rethrow;
    }
  }

  void _applyRemoteSnapshot(ProductProfileSnapshot? snapshot) {
    _clearProductState();
    if (snapshot == null) return;
    _profile = snapshot.onboarding;
    final checkpoint = snapshot.launchCheckpoint.index;
    _firstTradeComplete =
        snapshot.hasConfirmedPaperTrade ??
        checkpoint >= ProductProfileCheckpoint.firstPosition.index;
    _introductionExited =
        snapshot.launchCheckpoint == ProductProfileCheckpoint.app;
    // Older checkpoints represent the old tutorial's acknowledgements. The
    // new Skip action goes directly to app and must not manufacture those.
    final legacyProgress =
        snapshot.hasConfirmedPaperTrade == null ||
        snapshot.launchCheckpoint != ProductProfileCheckpoint.app;
    _firstPositionCollected =
        legacyProgress && checkpoint >= ProductProfileCheckpoint.streak.index;
    _dayOneSeen =
        legacyProgress && checkpoint >= ProductProfileCheckpoint.saveDesk.index;
    _accountGateSeen =
        legacyProgress && checkpoint >= ProductProfileCheckpoint.app.index;
  }

  void _clearProductState() {
    _profile = null;
    _firstTradeComplete = false;
    _firstPositionCollected = false;
    _dayOneSeen = false;
    _accountGateSeen = false;
    _introductionExited = false;
  }

  void _restoreLocal() {
    _clearProductState();
    _notificationStatus = OnboardingNotificationStatus.notRequested;
    _loadIssue = null;
    try {
      final raw = _preferences.getString(_profileKey);
      if (raw != null) _profile = _decodeProfile(raw);
      final status = _preferences.getString(_notificationKey);
      _notificationStatus = OnboardingNotificationStatus.values.firstWhere(
        (value) => value.name == status,
        orElse: () => OnboardingNotificationStatus.notRequested,
      );
      _firstTradeComplete = _preferences.getBool(_firstTradeKey) == true;
      _firstPositionCollected = _preferences.getBool(_firstPositionKey) == true;
      _dayOneSeen = _preferences.getBool(_dayOneKey) == true;
      _accountGateSeen = _preferences.getBool(_accountGateKey) == true;
      _introductionExited =
          _preferences.getBool(_introductionExitedKey) == true;
      if (_accountGateSeen) {
        _firstPositionCollected = true;
        _dayOneSeen = true;
      }
      if (!_firstTradeComplete) {
        _firstPositionCollected = false;
        _dayOneSeen = false;
        _accountGateSeen = false;
      } else if (!_firstPositionCollected) {
        _dayOneSeen = false;
        _accountGateSeen = false;
      } else if (!_dayOneSeen) {
        _accountGateSeen = false;
      }
      if (_profile == null) _clearProductState();
    } catch (_) {
      _clearProductState();
      _loadIssue = 'Your Trimmy setup could not be opened. Start it again.';
    }
  }

  OnboardingNotificationStatus _notificationFor(String principalKey) {
    final stored = _preferences.getString('$_notificationKey.$principalKey');
    return OnboardingNotificationStatus.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => OnboardingNotificationStatus.unavailable,
    );
  }

  Future<void> _cache(ProductProfileSnapshot snapshot, String principalKey) =>
      _serializeCache(principalKey, () async {
        await _preferences.setString(
          '$_remoteCachePrefix$principalKey',
          jsonEncode({
            'version': 2,
            'revision': snapshot.revision,
            'hasConfirmedPaperTrade': snapshot.hasConfirmedPaperTrade,
            'onboarding': snapshot.onboarding.toJson(),
            'launchCheckpoint': snapshot.launchCheckpoint.wire,
            'createdAt': snapshot.createdAt.toIso8601String(),
            'updatedAt': snapshot.updatedAt.toIso8601String(),
          }),
        );
      });

  Future<void> _removeCached(String principalKey) =>
      _serializeCache(principalKey, () async {
        await _preferences.remove('$_remoteCachePrefix$principalKey');
      });

  Future<void> _serializeCache(
    String principalKey,
    Future<void> Function() operation,
  ) {
    final previous = _cacheOperations[principalKey] ?? Future<void>.value();
    Future<void> safeOperation() async {
      try {
        await operation();
      } catch (_) {
        // The server remains authoritative. This cache is disposable, but its
        // mutations stay ordered so an older completion cannot win locally.
      }
    }

    final current = previous.then<void>(
      (_) => safeOperation(),
      onError: (Object _, StackTrace _) => safeOperation(),
    );
    late final Future<void> tracked;
    tracked = current.whenComplete(() {
      if (identical(_cacheOperations[principalKey], tracked)) {
        _cacheOperations.remove(principalKey);
      }
    });
    _cacheOperations[principalKey] = tracked;
    return tracked;
  }

  ProductProfileSnapshot? _readCached(String principalKey) {
    final raw = _preferences.getString('$_remoteCachePrefix$principalKey');
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          (value['version'] != 1 && value['version'] != 2) ||
          value.length != (value['version'] == 2 ? 7 : 6) ||
          (value['version'] == 2 &&
              value['hasConfirmedPaperTrade'] != null &&
              value['hasConfirmedPaperTrade'] is! bool) ||
          value['revision'] is! int ||
          (value['revision'] as int) < 1 ||
          (value['revision'] as int) > 9007199254740991 ||
          value['onboarding'] is! Map<String, dynamic> ||
          value['launchCheckpoint'] is! String ||
          value['createdAt'] is! String ||
          value['updatedAt'] is! String) {
        throw const FormatException('CACHE_INVALID');
      }
      final checkpoint = ProductProfileCheckpoint.values.firstWhere(
        (item) => item.wire == value['launchCheckpoint'],
        orElse: () => throw const FormatException('CACHE_INVALID'),
      );
      final createdAt = _cachedTime(value['createdAt'] as String);
      final updatedAt = _cachedTime(value['updatedAt'] as String);
      if (updatedAt.isBefore(createdAt)) {
        throw const FormatException('CACHE_INVALID');
      }
      return ProductProfileSnapshot(
        revision: value['revision'] as int,
        onboarding: _decodeProfile(jsonEncode(value['onboarding'])),
        launchCheckpoint: checkpoint,
        createdAt: createdAt,
        updatedAt: updatedAt,
        hasConfirmedPaperTrade: value['hasConfirmedPaperTrade'] as bool?,
      );
    } catch (_) {
      unawaited(_removeCached(principalKey));
      return null;
    }
  }

  static DateTime _cachedTime(String value) {
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
    ).hasMatch(value)) {
      throw const FormatException('CACHE_INVALID');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
      throw const FormatException('CACHE_INVALID');
    }
    return parsed;
  }

  static String _readIssue(ProductProfileFailure failure) => switch (failure) {
    ProductProfileFailure.offline =>
      'Your profile is offline. Check your connection and try again.',
    ProductProfileFailure.timeout =>
      'Your profile took too long to open. Try again.',
    ProductProfileFailure.unauthenticated =>
      'Your profile needs a fresh session. Try again.',
    _ => 'Your profile is unavailable. Try again.',
  };

  static String _writeIssue(ProductProfileFailure failure) => switch (failure) {
    ProductProfileFailure.handleTaken =>
      'That floor name is taken. Choose another one.',
    ProductProfileFailure.tradeRequired =>
      'Your confirmed trade must reach the desk before this step can continue.',
    ProductProfileFailure.notReady =>
      'Trimmy is still confirming that moment. Try again.',
    ProductProfileFailure.principalChanged =>
      'Your desk identity changed. Open it again and retry.',
    ProductProfileFailure.conflict =>
      'Your profile changed on another device. Try again.',
    ProductProfileFailure.offline =>
      'You are offline. Reconnect and try again.',
    ProductProfileFailure.timeout => 'That took too long. Try again.',
    ProductProfileFailure.unauthenticated =>
      'Your session changed. Open your profile again.',
    _ => 'That step was not saved. Try again.',
  };

  static OnboardingProfile _decodeProfile(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value.length != 6 ||
        !value.keys.toSet().containsAll(const {
          'version',
          'goal',
          'knowledge',
          'persona',
          'dailyGoal',
          'handle',
        }) ||
        (value['version'] != 1 &&
            value['version'] != OnboardingProfile.schemaVersion)) {
      throw const FormatException('PROFILE_INVALID');
    }
    T? parse<T extends Enum>(
      List<T> values,
      String key,
      String Function(T) id,
    ) {
      final wire = value[key];
      if (wire == null && value['version'] == 2) return null;
      if (wire is! String) throw const FormatException('PROFILE_INVALID');
      return values.firstWhere(
        (item) => id(item) == wire,
        orElse: () => throw const FormatException('PROFILE_INVALID'),
      );
    }

    final handle = value['handle'];
    if ((handle == null && value['version'] != 2) ||
        (handle != null &&
            (handle is! String ||
                !RegExp(r'^[a-z][a-z0-9_]{2,17}$').hasMatch(handle)))) {
      throw const FormatException('PROFILE_INVALID');
    }
    return OnboardingProfile(
      goal: parse(OnboardingGoal.values, 'goal', (item) => item.id),
      knowledge: parse(TradingKnowledge.values, 'knowledge', (item) => item.id),
      persona: parse(TraderPersona.values, 'persona', (item) => item.id),
      dailyGoal: parse(
        OnboardingDailyGoal.values,
        'dailyGoal',
        (item) => item.id,
      ),
      handle: handle as String?,
    );
  }
}

@immutable
final class _PendingProfileWrite {
  const _PendingProfileWrite({
    required this.mutationId,
    required this.baseRevision,
    required this.onboarding,
    required this.checkpoint,
  });

  final String mutationId;
  final int baseRevision;
  final OnboardingProfile onboarding;
  final ProductProfileCheckpoint checkpoint;
}

@immutable
final class _PendingLaunchAction {
  const _PendingLaunchAction({
    required this.mutationId,
    required this.baseRevision,
    required this.action,
    required this.checkpoint,
  });

  final String mutationId;
  final int baseRevision;
  final ProductLaunchAction action;
  final ProductProfileCheckpoint checkpoint;
}

@immutable
final class _InFlightProfileWrite {
  const _InFlightProfileWrite({
    required this.onboarding,
    required this.checkpoint,
    required this.future,
  });

  final OnboardingProfile onboarding;
  final ProductProfileCheckpoint checkpoint;
  final Future<void> future;
}

@immutable
final class _InFlightLaunchAction {
  const _InFlightLaunchAction({
    required this.action,
    required this.checkpoint,
    required this.future,
  });

  final ProductLaunchAction action;
  final ProductProfileCheckpoint checkpoint;
  final Future<void> future;
}
