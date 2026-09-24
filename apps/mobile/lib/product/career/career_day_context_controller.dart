import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../account/guest_session.dart';
import '../../core/device_time_zone.dart';
import 'career_repository.dart';

typedef CareerDayContextMutationIdFactory = String Function();

Duration careerDayRefreshDelay({
  required DateTime now,
  required DateTime? nextDayAt,
}) {
  const fallback = Duration(minutes: 15);
  if (nextDayAt == null) return fallback;
  final target = nextDayAt.add(const Duration(seconds: 2));
  return target.isAfter(now) ? target.difference(now) : fallback;
}

abstract interface class CareerDayContextMutationStore {
  Future<CareerDayContextWrite?> read(String principalKey);
  Future<bool> write(String principalKey, CareerDayContextWrite command);
  Future<bool> remove(String principalKey);
}

/// Keeps an uncertain initial time-zone write idempotent across app restarts.
final class PreferencesCareerDayContextMutationStore
    implements CareerDayContextMutationStore {
  const PreferencesCareerDayContextMutationStore(this._preferences);

  static const _prefix = 'trimmy.product.pending-day-context.v1.';
  final SharedPreferences _preferences;

  String _key(String principalKey) => '$_prefix$principalKey';

  @override
  Future<CareerDayContextWrite?> read(String principalKey) async {
    await _preferences.reload();
    final encoded = _preferences.getString(_key(principalKey));
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 4 ||
          decoded['schemaVersion'] != 1 ||
          !decoded.containsKey('mutationId') ||
          !decoded.containsKey('baseRevision') ||
          !decoded.containsKey('timeZone')) {
        return null;
      }
      final mutationId = decoded['mutationId'];
      final baseRevision = decoded['baseRevision'];
      final timeZone = decoded['timeZone'];
      if (mutationId is! String ||
          baseRevision is! int ||
          timeZone is! String) {
        return null;
      }
      return CareerDayContextWrite(
        mutationId: mutationId,
        baseRevision: baseRevision,
        timeZone: timeZone,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> write(String principalKey, CareerDayContextWrite command) =>
      _preferences.setString(
        _key(principalKey),
        jsonEncode({
          'schemaVersion': 1,
          'mutationId': command.mutationId,
          'baseRevision': command.baseRevision,
          'timeZone': command.timeZone,
        }),
      );

  @override
  Future<bool> remove(String principalKey) =>
      _preferences.remove(_key(principalKey));
}

final class _MemoryCareerDayContextMutationStore
    implements CareerDayContextMutationStore {
  final _values = <String, CareerDayContextWrite>{};

  @override
  Future<CareerDayContextWrite?> read(String principalKey) async =>
      _values[principalKey];

  @override
  Future<bool> write(String principalKey, CareerDayContextWrite command) async {
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

/// Synchronizes one account's server-owned Career calendar with the device.
///
/// The automatic write is deliberately one-way: it configures a fresh server
/// record, but never changes a record that is already configured. An ambiguous
/// write keeps its mutation ID so a later synchronization retries safely.
final class CareerDayContextController extends ChangeNotifier {
  CareerDayContextController({
    DeviceTimeZoneProvider deviceTimeZone =
        const MethodChannelDeviceTimeZoneProvider(),
    CareerDayContextMutationIdFactory? mutationId,
    CareerDayContextMutationStore? mutationStore,
  }) : _deviceTimeZoneProvider = deviceTimeZone,
       _mutationId = mutationId ?? _newMutationId,
       _mutationStore = mutationStore ?? _MemoryCareerDayContextMutationStore();

  final DeviceTimeZoneProvider _deviceTimeZoneProvider;
  final CareerDayContextMutationIdFactory _mutationId;
  final CareerDayContextMutationStore _mutationStore;
  final Map<String, CareerDayContextWrite> _pendingMutationByPrincipal =
      <String, CareerDayContextWrite>{};

  CareerRepository? _repository;
  String? _principalKey;
  CareerDayContext? _context;
  String? _deviceTimeZone;
  CareerFailure? _failure;
  GuestSessionFailure? _guestSessionFailure;
  Future<bool>? _synchronizing;
  bool _loading = false;
  bool _disposed = false;
  int _generation = 0;

  String? get principalKey => _principalKey;
  CareerDayContext? get context => _context;
  String? get deviceTimeZone => _deviceTimeZone;
  CareerFailure? get failure => _failure;
  GuestSessionFailure? get guestSessionFailure => _guestSessionFailure;
  bool get loading => _loading;
  bool get stale => _context != null && _failure != null;

  /// Returns true only when this call confirms the initial time zone write.
  Future<bool> bind({
    required String principalKey,
    required CareerRepository repository,
  }) {
    if (_disposed || principalKey.isEmpty) return Future<bool>.value(false);
    if (_principalKey == principalKey && identical(_repository, repository)) {
      return synchronize();
    }
    _generation++;
    _principalKey = principalKey;
    _repository = repository;
    _context = null;
    _deviceTimeZone = null;
    _failure = null;
    _guestSessionFailure = null;
    _synchronizing = null;
    _loading = false;
    notifyListeners();
    return synchronize();
  }

  void unbind() {
    if (_disposed) return;
    _generation++;
    _principalKey = null;
    _repository = null;
    _context = null;
    _deviceTimeZone = null;
    _failure = null;
    _guestSessionFailure = null;
    _synchronizing = null;
    _loading = false;
    notifyListeners();
  }

  /// Reads the authoritative day context and performs at most one write.
  Future<bool> synchronize() {
    final active = _synchronizing;
    if (active != null) return active;
    final repository = _repository;
    final principalKey = _principalKey;
    if (_disposed || repository == null || principalKey == null) {
      return Future<bool>.value(false);
    }
    final generation = _generation;
    final completer = Completer<bool>();
    final future = completer.future;
    // Publish the operation before the implementation can synchronously notify
    // a listener. Re-entry must share this exact Future and network cycle.
    _synchronizing = future;
    unawaited(
      _completeSynchronization(
        completer: completer,
        future: future,
        generation: generation,
        principalKey: principalKey,
        repository: repository,
      ),
    );
    return future;
  }

  Future<void> _completeSynchronization({
    required Completer<bool> completer,
    required Future<bool> future,
    required int generation,
    required String principalKey,
    required CareerRepository repository,
  }) async {
    try {
      completer.complete(
        await _performSynchronization(
          generation: generation,
          principalKey: principalKey,
          repository: repository,
        ),
      );
    } catch (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    } finally {
      if (identical(_synchronizing, future)) _synchronizing = null;
    }
  }

  Future<bool> _performSynchronization({
    required int generation,
    required String principalKey,
    required CareerRepository repository,
  }) async {
    _loading = true;
    _failure = null;
    _guestSessionFailure = null;
    notifyListeners();
    try {
      final dayContext = await repository.getDayContext();
      if (!_owns(generation, principalKey, repository)) return false;
      _context = dayContext;
      _failure = null;
      _guestSessionFailure = null;

      String? deviceTimeZone;
      try {
        deviceTimeZone = await _deviceTimeZoneProvider.currentIanaTimeZoneId();
      } catch (_) {
        deviceTimeZone = null;
      }
      if (!_owns(generation, principalKey, repository)) return false;
      _deviceTimeZone =
          deviceTimeZone != null &&
              MethodChannelDeviceTimeZoneProvider.isIanaTimeZoneId(
                deviceTimeZone,
              )
          ? deviceTimeZone
          : null;

      if (dayContext.configured) {
        _pendingMutationByPrincipal.remove(principalKey);
        try {
          await _mutationStore.remove(principalKey);
        } catch (_) {
          // A stale local mutation is harmless because configured server state
          // always wins. A later read will retry this principal's cleanup.
        }
        return false;
      }
      if (_deviceTimeZone == null) return false;

      final write = await _pendingMutation(
        generation: generation,
        principalKey: principalKey,
        repository: repository,
        baseRevision: dayContext.revision,
        timeZone: _deviceTimeZone!,
      );
      if (write == null || !_owns(generation, principalKey, repository)) {
        return false;
      }
      CareerDayContextReceipt receipt;
      try {
        receipt = await repository.putDayContext(write);
      } on CareerException catch (error) {
        if (error.failure != CareerFailure.dayContextRevisionConflict) rethrow;
        final reconciled = await repository.getDayContext();
        if (!_owns(generation, principalKey, repository)) return false;
        _context = reconciled;
        if (!reconciled.configured) {
          _failure = CareerFailure.dayContextRevisionConflict;
          _guestSessionFailure = null;
          return false;
        }
        _pendingMutationByPrincipal.remove(principalKey);
        try {
          await _mutationStore.remove(principalKey);
        } catch (_) {
          // A configured server response remains authoritative. Cleanup will
          // be retried on the next synchronization for this principal.
        }
        if (!_owns(generation, principalKey, repository)) return false;
        _failure = null;
        _guestSessionFailure = null;
        return true;
      }
      if (!_owns(generation, principalKey, repository)) return false;
      if (receipt.mutationId != write.mutationId ||
          receipt.baseRevision != write.baseRevision ||
          receipt.timeZone != write.timeZone ||
          !receipt.dayContext.configured ||
          receipt.dayContext.timeZone != write.timeZone ||
          receipt.dayContext.revision != write.baseRevision + 1) {
        throw const CareerException(CareerFailure.invalidResponse);
      }
      _context = receipt.dayContext;
      _pendingMutationByPrincipal.remove(principalKey);
      try {
        await _mutationStore.remove(principalKey);
      } catch (_) {
        // The server receipt is authoritative. A later configured GET will
        // retry cleanup without ever replaying this write.
      }
      if (!_owns(generation, principalKey, repository)) return false;
      _failure = null;
      _guestSessionFailure = null;
      try {
        final refreshed = await repository.getDayContext();
        if (!_owns(generation, principalKey, repository)) return false;
        if (!refreshed.configured ||
            refreshed.timeZone != write.timeZone ||
            refreshed.revision < receipt.dayContext.revision) {
          throw const CareerException(CareerFailure.invalidResponse);
        }
        _context = refreshed;
      } on GuestSessionException catch (error) {
        if (_owns(generation, principalKey, repository)) {
          _failure = null;
          _guestSessionFailure = error.failure;
        }
        return true;
      } on CareerException catch (error) {
        if (_owns(generation, principalKey, repository)) {
          _failure = error.failure;
          _guestSessionFailure = null;
        }
        return true;
      } catch (_) {
        if (_owns(generation, principalKey, repository)) {
          _failure = CareerFailure.unavailable;
          _guestSessionFailure = null;
        }
        return true;
      }
      return true;
    } on GuestSessionException catch (error) {
      if (_owns(generation, principalKey, repository)) {
        _failure = null;
        _guestSessionFailure = error.failure;
      }
      return false;
    } on CareerException catch (error) {
      if (_owns(generation, principalKey, repository)) {
        _failure = error.failure;
        _guestSessionFailure = null;
      }
      return false;
    } catch (_) {
      if (_owns(generation, principalKey, repository)) {
        _failure = CareerFailure.unavailable;
        _guestSessionFailure = null;
      }
      return false;
    } finally {
      if (_owns(generation, principalKey, repository)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<CareerDayContextWrite?> _pendingMutation({
    required int generation,
    required String principalKey,
    required CareerRepository repository,
    required int baseRevision,
    required String timeZone,
  }) async {
    final inMemory = _pendingMutationByPrincipal[principalKey];
    if (inMemory != null &&
        inMemory.baseRevision == baseRevision &&
        inMemory.timeZone == timeZone) {
      return inMemory;
    }
    _pendingMutationByPrincipal.remove(principalKey);

    CareerDayContextWrite? stored;
    try {
      stored = await _mutationStore.read(principalKey);
    } catch (_) {
      throw const CareerException(CareerFailure.unavailable);
    }
    if (!_owns(generation, principalKey, repository)) return null;

    if (stored != null &&
        stored.baseRevision == baseRevision &&
        stored.timeZone == timeZone) {
      _pendingMutationByPrincipal[principalKey] = stored;
      return stored;
    }
    final command = CareerDayContextWrite(
      mutationId: _mutationId(),
      baseRevision: baseRevision,
      timeZone: timeZone,
    );
    if (stored?.mutationId == command.mutationId ||
        inMemory?.mutationId == command.mutationId) {
      throw const CareerException(CareerFailure.invalidInput);
    }
    bool saved;
    try {
      saved = await _mutationStore.write(principalKey, command);
    } catch (_) {
      throw const CareerException(CareerFailure.unavailable);
    }
    if (!_owns(generation, principalKey, repository)) return null;
    if (!saved) throw const CareerException(CareerFailure.unavailable);
    _pendingMutationByPrincipal[principalKey] = command;
    return command;
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
    _context = null;
    _deviceTimeZone = null;
    _synchronizing = null;
    super.dispose();
  }
}
