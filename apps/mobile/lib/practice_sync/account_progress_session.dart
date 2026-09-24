import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../design_study/progress.dart';
import 'coordinator.dart';
import 'durable_state.dart';
import 'protocol.dart';

/// One persisted record contains progress and its pending network mutation.
/// Preferences acknowledge writes but are not a power-loss-safe financial store.
class PreferencesPracticeSyncStore implements PracticeSyncStore {
  PreferencesPracticeSyncStore(this.preferences);

  final SharedPreferences preferences;

  @override
  Future<String?> read(String key) async {
    await preferences.reload();
    return preferences.getString(key);
  }

  @override
  Future<bool> write(String key, String value) =>
      preferences.setString(key, value);
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

/// Connects the existing activity repository to one verified account's queue.
/// Create a new session on account switch and close the previous session.
/// Guest progress is imported only when explicitly supplied to [open].
class AccountProgressSession {
  AccountProgressSession._(this.coordinator, DateTime Function()? clock) {
    progressRepository = OfficeProgressRepository(
      read: (key) => key == OfficeProgressRepository.saveKey
          ? jsonEncode(coordinator.localProgress.toJson())
          : null,
      write: (key, value) async {
        _requireOpen();
        if (key != OfficeProgressRepository.saveKey) {
          throw PracticeSyncException('PRACTICE_LOCAL_SAVE_FAILED');
        }
        final json = jsonDecode(value) as Map<String, dynamic>;
        await coordinator.saveLocal(
          OfficeProgress.fromJson(json),
          expectedLocal: progressRepository.state,
        );
        return true;
      },
      clock: clock,
    );
  }

  static Future<AccountProgressSession> open({
    required String accountId,
    required PracticeSyncStore store,
    required PracticeTransport transport,
    OfficeProgress? initialProgress,
    DateTime Function()? clock,
    String Function()? mutationId,
  }) async {
    final coordinator = PracticeSyncCoordinator(
      accountId: accountId,
      store: store,
      transport: transport,
      mutationId: mutationId ?? _newMutationId,
    );
    await coordinator.load(initialProgress: initialProgress);
    if (coordinator.state == null || coordinator.loadIssue != null) {
      throw PracticeSyncException('PRACTICE_LOCAL_UNAVAILABLE');
    }
    return AccountProgressSession._(coordinator, clock);
  }

  final PracticeSyncCoordinator coordinator;
  late final OfficeProgressRepository progressRepository;
  bool _closed = false;
  Future<void>? _syncing;

  /// Call on sign-in, foreground, a connectivity recovery, or explicit retry.
  /// Network failure never turns a successful local activity write into failure.
  Future<void> synchronize() {
    _requireOpen();
    return _syncing ??= _synchronize().whenComplete(() => _syncing = null);
  }

  Future<void> _synchronize() async {
    try {
      await coordinator.synchronize();
    } finally {
      // This joins the existing repository's write queue, so restored progress
      // cannot race a locally acknowledged activity transition.
      if (!_closed) await progressRepository.retryLoad();
    }
  }

  Future<void> resolveConflict(OfficeProgress reconciled) async {
    _requireOpen();
    await coordinator.resolveConflict(
      reconciled,
      expectedLocal: progressRepository.state,
    );
    if (!_closed) await progressRepository.retryLoad();
  }

  /// Import is explicit and only available before this account has local work.
  /// Existing account drafts and first completions never become an implicit merge.
  Future<void> importProgress(OfficeProgress progress) async {
    _requireOpen();
    final expected = progressRepository.state;
    if (canonicalProgressContent(expected) !=
            canonicalProgressContent(OfficeProgress.empty()) ||
        coordinator.state!.conflict != null ||
        coordinator.state!.pending != null) {
      throw const PracticeSyncException('PRACTICE_IMPORT_NOT_EMPTY');
    }
    await coordinator.saveLocal(progress, expectedLocal: expected);
    if (!_closed) await progressRepository.retryLoad();
  }

  /// A new session for this same account waits for accepted writes and network
  /// receipts to settle before reopening its one durable record.
  Future<void> get whenIdle async {
    try {
      await _syncing;
    } catch (_) {
      // Unknown network outcomes already retain their durable retry intent.
    }
    await progressRepository.whenIdle;
    // Import and reconciliation persist directly through the coordinator and
    // do not enter the activity repository's queue. Join them after activity
    // writes so every previously accepted operation has finished using disk.
    await coordinator.whenIdle;
  }

  /// An already-sent request may finish only in this account's scoped record.
  /// Closing never erases its pending receipt or another account's local data.
  void close() => _closed = true;

  void _requireOpen() {
    if (_closed) throw PracticeSyncException('PRACTICE_SESSION_CLOSED');
  }
}
