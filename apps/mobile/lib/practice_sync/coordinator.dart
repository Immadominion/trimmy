import 'dart:async';

import '../design_study/progress.dart';
import 'durable_state.dart';
import 'protocol.dart';

/// One immutable account per coordinator. Network work never holds the local
/// persistence queue, so practice can continue while an upload is in flight.
class PracticeSyncCoordinator {
  factory PracticeSyncCoordinator({
    required String accountId,
    required PracticeSyncStore store,
    required PracticeTransport transport,
    required String Function() mutationId,
  }) => PracticeSyncCoordinator._(
    normalizePracticeAccountId(accountId),
    store,
    transport,
    mutationId,
  );

  PracticeSyncCoordinator._(
    this.accountId,
    this._store,
    this._transport,
    this._mutationId,
  ) {
    _assertTransportAccount();
  }

  final String accountId;
  final PracticeSyncStore _store;
  final PracticeTransport _transport;
  final String Function() _mutationId;
  PracticeSyncState? _state;
  PracticeSyncLoadIssue? _loadIssue;
  Future<void> _localQueue = Future<void>.value();
  Future<void>? _loading;
  Future<void>? _syncing;

  static String storageKeyFor(String accountId) =>
      'trimmy.practice-sync.v1.${normalizePracticeAccountId(accountId)}';
  String get storageKey => storageKeyFor(accountId);
  PracticeSyncState? get state => _state;
  PracticeSyncLoadIssue? get loadIssue => _loadIssue;
  OfficeProgress get localProgress => _usable.local;

  /// Joins accepted local persistence, including import and reconciliation.
  /// Session retirement must wait for these writes before reopening the record.
  Future<void> get whenIdle => _localQueue;

  void _assertTransportAccount() {
    if (normalizePracticeAccountId(_transport.accountId) != accountId) {
      throw const PracticeSyncException('PRACTICE_ACCOUNT_MISMATCH');
    }
  }

  PracticeSyncState get _usable {
    if (_state == null || _loadIssue != null) {
      throw const PracticeSyncException('PRACTICE_LOCAL_UNAVAILABLE');
    }
    return _state!;
  }

  Future<T> _locked<T>(FutureOr<T> Function() operation) {
    final next = _localQueue.then((_) => operation());
    _localQueue = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  /// Existing records always win over optional explicit guest import. Once
  /// initialized, reloading is a no-op and cannot race an in-flight RPC.
  Future<void> load({OfficeProgress? initialProgress}) {
    if (_state != null) return Future<void>.value();
    if (_loading != null) return _loading!;
    late final Future<void> operation;
    operation =
        _locked(() async {
          String? raw;
          try {
            raw = await _store.read(storageKey);
          } catch (_) {
            _loadIssue = PracticeSyncLoadIssue.storageReadFailed;
            return;
          }
          if (raw != null) {
            try {
              _state = PracticeSyncState.decode(raw, accountId: accountId);
              _loadIssue = null;
            } on PracticeSyncException catch (error) {
              _loadIssue = switch (error.code) {
                'PRACTICE_SYNC_STATE_UNSUPPORTED' =>
                  PracticeSyncLoadIssue.unsupportedVersion,
                'PRACTICE_SYNC_ACCOUNT_MISMATCH' =>
                  PracticeSyncLoadIssue.accountMismatch,
                _ => PracticeSyncLoadIssue.corruptState,
              };
            }
            return;
          }
          final initial = PracticeSyncState(
            accountId: accountId,
            local: initialProgress?.upgradeForWrite() ?? OfficeProgress.empty(),
            base: null,
            pending: null,
            conflict: null,
          );
          try {
            await _persist(initial);
            _loadIssue = null;
          } catch (_) {
            _loadIssue = PracticeSyncLoadIssue.storageWriteFailed;
          }
        }).whenComplete(() {
          if (identical(_loading, operation)) _loading = null;
        });
    _loading = operation;
    return operation;
  }

  Future<void> _persist(PracticeSyncState next) async {
    final raw = next.encode();
    if (_state?.encode() == raw) return;
    try {
      if (!await _store.write(storageKey, raw)) {
        throw const PracticeSyncException('PRACTICE_LOCAL_SAVE_FAILED');
      }
    } catch (_) {
      throw const PracticeSyncException('PRACTICE_LOCAL_SAVE_FAILED');
    }
    _state = next;
  }

  /// [expectedLocal] guards transitions computed from a repository snapshot
  /// while a remote restore may still be waiting for its disk acknowledgment.
  Future<void> saveLocal(
    OfficeProgress next, {
    OfficeProgress? expectedLocal,
  }) => _locked(() async {
    final current = _usable;
    _requireExpectedLocal(current.local, expectedLocal);
    assertPracticeHistoryPreserved(current.local, next);
    await _persist(
      PracticeSyncState(
        accountId: accountId,
        local: next.upgradeForWrite(),
        base: current.base,
        pending: current.pending,
        conflict: current.conflict,
      ),
    );
  });

  /// Reconciliation is explicit. Contradictory first answers cannot be merged
  /// into one history, and remain protected for a future archive experience.
  Future<void> resolveConflict(
    OfficeProgress reconciled, {
    OfficeProgress? expectedLocal,
  }) => _locked(() async {
    final current = _usable;
    _requireExpectedLocal(current.local, expectedLocal);
    final remote = current.conflict;
    if (remote == null || current.pending != null) {
      throw const PracticeSyncException('PRACTICE_NO_CONFLICT');
    }
    assertPracticeHistoryPreserved(current.local, reconciled);
    if (remote.progress case final remoteProgress?) {
      assertPracticeHistoryPreserved(remoteProgress, reconciled);
    }
    await _persist(
      PracticeSyncState(
        accountId: accountId,
        local: reconciled.upgradeForWrite(),
        base: remote,
        pending: null,
        conflict: null,
      ),
    );
  });

  void _requireExpectedLocal(OfficeProgress current, OfficeProgress? expected) {
    if (expected != null && !_sameProgress(current, expected)) {
      throw const PracticeSyncException('PRACTICE_LOCAL_CHANGED');
    }
  }

  /// Concurrent calls coalesce. Each cycle sends at most one logical PUT; a
  /// subsequent cycle fetches again before preparing another mutation.
  Future<void> synchronize() {
    if (_syncing != null) return _syncing!;
    late final Future<void> operation;
    operation = _synchronize().whenComplete(() {
      if (identical(_syncing, operation)) _syncing = null;
    });
    _syncing = operation;
    return operation;
  }

  Future<void> _synchronize() async {
    _assertTransportAccount();
    var pending = await _locked(() {
      final current = _usable;
      if (current.conflict != null) {
        throw const PracticeSyncException('PRACTICE_CONFLICT');
      }
      return current.pending;
    });
    if (pending == null) {
      final remote = await _transport.getProgress();
      pending = await _locked(() => _observeRemote(remote));
    }
    if (pending == null) return;
    final sent = pending;
    _assertTransportAccount();
    PracticeSnapshot acknowledged;
    try {
      acknowledged = await _transport.putProgress(sent);
    } on PracticeRevisionConflict catch (error) {
      await _locked(() async {
        final current = _usable;
        _requirePending(current, sent);
        await _persist(
          PracticeSyncState(
            accountId: accountId,
            local: current.local,
            base: current.base,
            pending: null,
            conflict: error.currentSnapshot,
          ),
        );
      });
      rethrow;
    }
    if (acknowledged.revision != sent.baseRevision + 1 ||
        acknowledged.progress == null ||
        canonicalProgress(acknowledged.progress!) !=
            canonicalProgress(sent.progress)) {
      throw const PracticeSyncException('PRACTICE_ACK_MISMATCH');
    }
    await _locked(() async {
      final current = _usable;
      _requirePending(current, sent);
      // An old receipt acknowledges only its uploaded version. The current
      // local draft can already be newer and must survive this write.
      await _persist(
        PracticeSyncState(
          accountId: accountId,
          local: current.local,
          base: acknowledged,
          pending: null,
          conflict: null,
        ),
      );
    });
  }

  void _requirePending(PracticeSyncState current, PracticeMutation sent) {
    if (current.pending?.mutationId != sent.mutationId ||
        current.pending?.baseRevision != sent.baseRevision ||
        canonicalProgress(current.pending!.progress) !=
            canonicalProgress(sent.progress)) {
      throw const PracticeSyncException('PRACTICE_PENDING_CHANGED');
    }
  }

  bool _sameProgress(OfficeProgress local, OfficeProgress? remote) =>
      remote != null && samePracticeProgress(local, remote);

  Future<PracticeMutation?> _observeRemote(PracticeSnapshot remote) async {
    final current = _usable;
    if (current.pending != null || current.conflict != null) {
      throw const PracticeSyncException('PRACTICE_SYNC_STATE_CHANGED');
    }
    final baseline = current.base;
    final local = current.local;
    final localEmpty = _sameProgress(local, OfficeProgress.empty());
    final remoteUnchanged =
        baseline != null &&
        remote.revision == baseline.revision &&
        remote.updatedAt == baseline.updatedAt &&
        (remote.progress == null
            ? baseline.progress == null
            : baseline.progress != null &&
                  canonicalProgress(remote.progress!) ==
                      canonicalProgress(baseline.progress!));
    // A server revision is immutable. Even a clean local copy cannot authorize
    // replacing a known revision with different content or a different time.
    final regressed =
        baseline != null &&
        (remote.revision < baseline.revision ||
            (remote.revision == baseline.revision && !remoteUnchanged));

    if (!regressed &&
        (_sameProgress(local, remote.progress) ||
            (localEmpty && remote.progress == null))) {
      await _persist(
        PracticeSyncState(
          accountId: accountId,
          local: local,
          base: remote,
          pending: null,
          conflict: null,
        ),
      );
      return null;
    }
    if (!regressed &&
        remote.progress != null &&
        (localEmpty || _sameProgress(local, baseline?.progress))) {
      try {
        assertPracticeHistoryPreserved(local, remote.progress!);
      } on PracticeSyncException {
        await _conflict(current, remote);
        return null;
      }
      await _persist(
        PracticeSyncState(
          accountId: accountId,
          local: remote.progress!,
          base: remote,
          pending: null,
          conflict: null,
        ),
      );
      return null;
    }
    if (!regressed &&
        (remoteUnchanged ||
            (baseline?.progress != null &&
                remote.progress != null &&
                _sameProgress(baseline!.progress!, remote.progress)) ||
            (baseline == null && remote.revision == 0))) {
      final mutation = PracticeMutation(
        mutationId: _mutationId(),
        baseRevision: remote.revision,
        progress: local.upgradeForWrite(),
      );
      await _persist(
        PracticeSyncState(
          accountId: accountId,
          local: mutation.progress,
          base: remote,
          pending: mutation,
          conflict: null,
        ),
      );
      return mutation;
    }
    await _conflict(current, remote);
    return null;
  }

  Future<void> _conflict(
    PracticeSyncState current,
    PracticeSnapshot remote,
  ) async {
    await _persist(
      PracticeSyncState(
        accountId: accountId,
        local: current.local,
        base: current.base,
        pending: null,
        conflict: remote,
      ),
    );
    throw const PracticeSyncException('PRACTICE_CONFLICT');
  }
}
