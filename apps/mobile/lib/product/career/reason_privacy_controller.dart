import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../account/guest_session.dart';
import 'reason_sharing_repository.dart';

typedef ReasonPrivacyMutationIdFactory = String Function();

abstract interface class ReasonPrivacyMutationStore {
  Future<ReasonPrivacyWrite?> read(String principalKey);
  Future<bool> write(String principalKey, ReasonPrivacyWrite command);
  Future<bool> remove(String principalKey);
}

/// Keeps an uncertain privacy write idempotent across app restarts.
final class PreferencesReasonPrivacyMutationStore
    implements ReasonPrivacyMutationStore {
  const PreferencesReasonPrivacyMutationStore(this._preferences);

  static const _prefix = 'trimmy.product.pending-reason-privacy.v1.';
  final SharedPreferences _preferences;

  String _key(String principalKey) => '$_prefix$principalKey';

  @override
  Future<ReasonPrivacyWrite?> read(String principalKey) async {
    await _preferences.reload();
    final encoded = _preferences.getString(_key(principalKey));
    if (encoded == null) return null;
    try {
      return ReasonPrivacyWrite.fromJson(jsonDecode(encoded));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> write(String principalKey, ReasonPrivacyWrite command) =>
      _preferences.setString(_key(principalKey), jsonEncode(command.toJson()));

  @override
  Future<bool> remove(String principalKey) =>
      _preferences.remove(_key(principalKey));
}

final class _MemoryReasonPrivacyMutationStore
    implements ReasonPrivacyMutationStore {
  final _values = <String, ReasonPrivacyWrite>{};

  @override
  Future<ReasonPrivacyWrite?> read(String principalKey) async =>
      _values[principalKey];

  @override
  Future<bool> write(String principalKey, ReasonPrivacyWrite command) async {
    _values[principalKey] = command;
    return true;
  }

  @override
  Future<bool> remove(String principalKey) async {
    _values.remove(principalKey);
    return true;
  }
}

String _newMutationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// What the last completed write proved.
enum ReasonPrivacyNotice {
  /// The server confirmed exactly the chosen value.
  saved,

  /// The server holds a newer choice made elsewhere. It is now shown.
  changedElsewhere,
}

/// Owns one account's server-confirmed reason privacy choice.
///
/// [privacy] only ever holds what the server returned. A choice in flight is
/// [pending] until the server confirms it, and an ambiguous failure keeps the
/// exact command so a retry replays the same mutation ID.
final class ReasonPrivacyController extends ChangeNotifier {
  ReasonPrivacyController({
    ReasonPrivacyMutationIdFactory? mutationId,
    ReasonPrivacyMutationStore? mutationStore,
  }) : _mutationId = mutationId ?? _newMutationId,
       _mutationStore = mutationStore ?? _MemoryReasonPrivacyMutationStore();

  final ReasonPrivacyMutationIdFactory _mutationId;
  final ReasonPrivacyMutationStore _mutationStore;

  ReasonSharingRepository? _repository;
  String? _principalKey;
  ReasonPrivacy? _privacy;
  ReasonPrivacyWrite? _pending;
  ReasonSharingFailure? _failure;
  Duration? _retryAfter;
  GuestSessionFailure? _guestSessionFailure;
  ReasonPrivacyNotice? _notice;
  bool _loading = false;
  bool _saving = false;
  bool _disposed = false;
  int _generation = 0;

  String? get principalKey => _principalKey;

  /// The last server-confirmed choice. Null until the first read succeeds.
  ReasonPrivacy? get privacy => _privacy;

  /// The exact command still waiting for a server answer, if any.
  ReasonPrivacyWrite? get pending => _pending;
  bool get hasPending => _pending != null;
  ReasonSharingFailure? get failure => _failure;
  Duration? get retryAfter => _retryAfter;
  GuestSessionFailure? get guestSessionFailure => _guestSessionFailure;
  ReasonPrivacyNotice? get notice => _notice;
  bool get loading => _loading;
  bool get saving => _saving;
  bool get busy => _loading || _saving;
  bool get bound => _repository != null && _principalKey != null;

  Future<void> bind({
    required String principalKey,
    required ReasonSharingRepository repository,
  }) {
    if (_disposed || principalKey.isEmpty) return Future<void>.value();
    if (_principalKey == principalKey && identical(_repository, repository)) {
      return refresh();
    }
    _generation++;
    _principalKey = principalKey;
    _repository = repository;
    _privacy = null;
    _pending = null;
    _failure = null;
    _retryAfter = null;
    _guestSessionFailure = null;
    _notice = null;
    _loading = false;
    _saving = false;
    notifyListeners();
    return _load(resumePending: true);
  }

  void unbind() {
    if (_disposed) return;
    _generation++;
    _principalKey = null;
    _repository = null;
    _privacy = null;
    _pending = null;
    _failure = null;
    _retryAfter = null;
    _guestSessionFailure = null;
    _notice = null;
    _loading = false;
    _saving = false;
    notifyListeners();
  }

  /// Reads the server choice again. A pending write is kept, not replayed.
  Future<void> refresh() => _load(resumePending: false);

  /// Writes a new choice. Returns true only when the server confirmed it.
  Future<bool> choose(ReasonVisibility visibility) async {
    final repository = _repository;
    final principalKey = _principalKey;
    final current = _privacy;
    if (_disposed ||
        repository == null ||
        principalKey == null ||
        current == null ||
        busy) {
      return false;
    }
    final generation = _generation;
    final inFlight = _pending;
    final ReasonPrivacyWrite command;
    if (inFlight != null &&
        inFlight.baseRevision == current.revision &&
        inFlight.visibility == visibility) {
      command = inFlight;
    } else {
      command = ReasonPrivacyWrite(
        mutationId: _mutationId(),
        baseRevision: current.revision,
        visibility: visibility,
      );
      if (command.mutationId == inFlight?.mutationId) {
        throw const ReasonSharingException(ReasonSharingFailure.invalidInput);
      }
      bool saved;
      try {
        saved = await _mutationStore.write(principalKey, command);
      } catch (_) {
        saved = false;
      }
      if (!_owns(generation, principalKey, repository)) return false;
      if (!saved) {
        _failure = ReasonSharingFailure.unavailable;
        _retryAfter = null;
        _notice = null;
        notifyListeners();
        return false;
      }
      _pending = command;
    }
    return _write(
      command,
      generation: generation,
      principalKey: principalKey,
      repository: repository,
    );
  }

  /// Replays the pending command exactly, or re-reads when nothing is pending.
  Future<bool> retry() async {
    final repository = _repository;
    final principalKey = _principalKey;
    final command = _pending;
    if (_disposed || repository == null || principalKey == null || busy) {
      return false;
    }
    if (command == null) {
      await _load(resumePending: false);
      return _failure == null && _guestSessionFailure == null;
    }
    return _write(
      command,
      generation: _generation,
      principalKey: principalKey,
      repository: repository,
    );
  }

  Future<void> _load({required bool resumePending}) async {
    final repository = _repository;
    final principalKey = _principalKey;
    if (_disposed || repository == null || principalKey == null || busy) {
      return;
    }
    final generation = _generation;
    _loading = true;
    _failure = null;
    _retryAfter = null;
    _guestSessionFailure = null;
    _notice = null;
    notifyListeners();
    ReasonPrivacyWrite? stored;
    try {
      final privacy = await repository.getPrivacy();
      if (!_owns(generation, principalKey, repository)) return;
      _privacy = privacy;
      if (resumePending) {
        try {
          stored = await _mutationStore.read(principalKey);
        } catch (_) {
          stored = null;
        }
        if (!_owns(generation, principalKey, repository)) return;
        if (stored != null && stored.baseRevision > privacy.revision) {
          // A stored command cannot be ahead of the server. Drop it.
          stored = null;
          await _forgetPending(principalKey);
          if (!_owns(generation, principalKey, repository)) return;
        }
        _pending = stored;
      }
    } on GuestSessionException catch (error) {
      if (_owns(generation, principalKey, repository)) {
        _guestSessionFailure = error.failure;
      }
    } on ReasonSharingException catch (error) {
      if (_owns(generation, principalKey, repository)) {
        _failure = error.failure;
        _retryAfter = error.retryAfter;
      }
    } catch (_) {
      if (_owns(generation, principalKey, repository)) {
        _failure = ReasonSharingFailure.unavailable;
      }
    } finally {
      if (_owns(generation, principalKey, repository)) {
        _loading = false;
        notifyListeners();
      }
    }
    if (stored != null && _owns(generation, principalKey, repository)) {
      await _write(
        stored,
        generation: generation,
        principalKey: principalKey,
        repository: repository,
      );
    }
  }

  Future<bool> _write(
    ReasonPrivacyWrite command, {
    required int generation,
    required String principalKey,
    required ReasonSharingRepository repository,
  }) async {
    _saving = true;
    _failure = null;
    _retryAfter = null;
    _guestSessionFailure = null;
    _notice = null;
    notifyListeners();
    try {
      final receipt = await repository.putPrivacy(command);
      if (!_owns(generation, principalKey, repository)) return false;
      if (receipt.mutationId != command.mutationId ||
          receipt.baseRevision != command.baseRevision ||
          receipt.visibility != command.visibility) {
        throw const ReasonSharingException(
          ReasonSharingFailure.invalidResponse,
        );
      }
      _privacy = receipt.privacy;
      await _forgetPending(principalKey);
      if (!_owns(generation, principalKey, repository)) return false;
      _notice = receipt.exact
          ? ReasonPrivacyNotice.saved
          : ReasonPrivacyNotice.changedElsewhere;
      return receipt.exact;
    } on GuestSessionException catch (error) {
      if (_owns(generation, principalKey, repository)) {
        _guestSessionFailure = error.failure;
      }
      return false;
    } on ReasonSharingException catch (error) {
      if (!_owns(generation, principalKey, repository)) return false;
      switch (error.failure) {
        case ReasonSharingFailure.revisionConflict:
          // The server holds a newer choice. The stale command can never
          // succeed, so refresh and show what the server has.
          await _forgetPending(principalKey);
          if (!_owns(generation, principalKey, repository)) return false;
          try {
            final refreshed = await repository.getPrivacy();
            if (!_owns(generation, principalKey, repository)) return false;
            _privacy = refreshed;
            _notice = ReasonPrivacyNotice.changedElsewhere;
          } on GuestSessionException catch (refreshError) {
            if (_owns(generation, principalKey, repository)) {
              _guestSessionFailure = refreshError.failure;
            }
          } on ReasonSharingException catch (refreshError) {
            if (_owns(generation, principalKey, repository)) {
              _failure = refreshError.failure;
              _retryAfter = refreshError.retryAfter;
            }
          } catch (_) {
            if (_owns(generation, principalKey, repository)) {
              _failure = ReasonSharingFailure.unavailable;
            }
          }
        case ReasonSharingFailure.idempotencyConflict:
        case ReasonSharingFailure.accountNotFound:
        case ReasonSharingFailure.revisionExhausted:
        case ReasonSharingFailure.invalidInput:
        case ReasonSharingFailure.rejected:
          // The server answered and refused. Replaying cannot help.
          await _forgetPending(principalKey);
          if (!_owns(generation, principalKey, repository)) return false;
          _failure = error.failure;
        case ReasonSharingFailure.offline:
        case ReasonSharingFailure.timeout:
        case ReasonSharingFailure.unavailable:
        case ReasonSharingFailure.invalidResponse:
        case ReasonSharingFailure.rateLimited:
        case ReasonSharingFailure.accountRequired:
          // The write may or may not have landed. Keep the exact command so
          // the next attempt replays it instead of creating a second one.
          _failure = error.failure;
          _retryAfter = error.retryAfter;
      }
      return false;
    } catch (_) {
      if (_owns(generation, principalKey, repository)) {
        _failure = ReasonSharingFailure.unavailable;
      }
      return false;
    } finally {
      if (_owns(generation, principalKey, repository)) {
        _saving = false;
        notifyListeners();
      }
    }
  }

  Future<void> _forgetPending(String principalKey) async {
    _pending = null;
    try {
      await _mutationStore.remove(principalKey);
    } catch (_) {
      // The server answer is authoritative. A stale stored command is
      // reconciled on the next bind by the server revision check.
    }
  }

  bool _owns(
    int generation,
    String principalKey,
    ReasonSharingRepository repository,
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
    _privacy = null;
    _pending = null;
    super.dispose();
  }
}
