import 'dart:math';

import 'package:flutter/foundation.dart';

import 'http_invitations_client.dart';
import 'invitation.dart';
import 'invitation_create_store.dart';

const defaultInvitationWindow = Duration(days: 7);
const invitationPageLimit = 20;

typedef InvitationMutationIdFactory = String Function();
typedef InvitationClock = DateTime Function();

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

/// Holds the signed-in account's bounded invitation pages.
///
/// The server owns X lookup and recipient proof. This controller sends a typed
/// handle for addressing and never stores a numeric X subject.
class InvitationsController extends ChangeNotifier {
  InvitationsController({
    required HttpInvitationsClient client,
    InvitationMutationIdFactory? mutationId,
    InvitationCreateMutationStore? createMutationStore,
    InvitationClock? clock,
  }) : this._(
         client,
         mutationId ?? _newMutationId,
         createMutationStore ?? MemoryInvitationCreateMutationStore(),
         clock ?? DateTime.now,
       );

  InvitationsController._(
    this._client,
    this._mutationId,
    this._createMutationStore,
    this._clock,
  );

  final HttpInvitationsClient _client;
  final InvitationMutationIdFactory _mutationId;
  final InvitationCreateMutationStore _createMutationStore;
  final InvitationClock _clock;

  List<InvitationRecord> _open = const [];
  List<InvitationRecord> _history = const [];
  String? _openCursor;
  String? _historyCursor;
  IncomingInvitationsStatus? _incomingInvitations;
  bool _openLoaded = false;
  bool _historyLoaded = false;
  bool _busy = false;
  bool _disposed = false;
  InvitationFailure? _failure;
  InvitationCreateCommand? _pendingCreate;

  /// Kept as the open-list name used by existing entry points.
  List<InvitationRecord> get invitations => _open;
  List<InvitationRecord> get openInvitations => _open;
  List<InvitationRecord> get historyInvitations => _history;
  bool get busy => _busy;
  bool get loaded => _openLoaded;
  bool get openLoaded => _openLoaded;
  bool get historyLoaded => _historyLoaded;
  bool get hasMoreOpen => _openCursor != null;
  bool get hasMoreHistory => _historyCursor != null;
  IncomingInvitationsStatus? get incomingInvitations => _incomingInvitations;
  InvitationFailure? get failure => _failure;

  List<InvitationRecord> get sent =>
      _open.where((row) => row.isSender).toList(growable: false);
  List<InvitationRecord> get received =>
      _open.where((row) => !row.isSender).toList(growable: false);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close();
    _open = const [];
    _history = const [];
    _openCursor = null;
    _historyCursor = null;
    _incomingInvitations = null;
    _openLoaded = false;
    _historyLoaded = false;
    _failure = null;
    _pendingCreate = null;
    super.dispose();
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_disposed || _busy) return false;
    _busy = true;
    _failure = null;
    _notify();
    var ok = false;
    try {
      await action();
      ok = true;
    } on InvitationException catch (error) {
      _failure = error.failure;
    } catch (_) {
      _failure = InvitationFailure.unavailable;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
    return ok;
  }

  Future<void> refresh() async {
    await refreshBox(InvitationBox.open);
  }

  Future<void> refreshHistory() async {
    await refreshBox(InvitationBox.history);
  }

  Future<void> refreshBox(InvitationBox box) async {
    await _run(() async {
      final page = await _client.list(box: box, limit: invitationPageLimit);
      if (_disposed) return;
      _applyPage(page, append: false, requestedCursor: null);
    });
  }

  Future<void> loadMoreOpen() async {
    await loadMore(InvitationBox.open);
  }

  Future<void> loadMoreHistory() async {
    await loadMore(InvitationBox.history);
  }

  Future<void> loadMore(InvitationBox box) async {
    final loaded = box == InvitationBox.open ? _openLoaded : _historyLoaded;
    final cursor = box == InvitationBox.open ? _openCursor : _historyCursor;
    if (loaded && cursor == null) return;
    await _run(() async {
      final page = await _client.list(
        box: box,
        limit: invitationPageLimit,
        cursor: loaded ? cursor : null,
      );
      if (_disposed) return;
      _applyPage(page, append: loaded, requestedCursor: loaded ? cursor : null);
    });
  }

  Future<void> create({Duration window = defaultInvitationWindow}) async {
    await _run(() async {
      final command = await _createCommand(window: window, allowNew: true);
      if (command == null) return;
      await _sendCreate(command);
    });
  }

  /// Resolves a create whose response was lost before the previous process
  /// could prove whether it committed. It never invents a new invitation.
  Future<void> resumePendingCreate() async {
    await _run(() async {
      final command = await _createCommand(
        window: defaultInvitationWindow,
        allowNew: false,
      );
      if (command == null) return;
      await _sendCreate(command);
    });
  }

  Future<InvitationCreateCommand?> _createCommand({
    required Duration window,
    required bool allowNew,
  }) async {
    if (window <= Duration.zero || window > const Duration(days: 30)) {
      throw const InvitationException(InvitationFailure.invalidRequest);
    }
    var command = _pendingCreate;
    command ??= await _createMutationStore.read(_client.accountId);
    if (_disposed) return null;
    final now = _clock().toUtc();
    if (command != null || !allowNew) {
      _pendingCreate = command;
      return command;
    }
    final rawExpiry = now.add(window);
    final expiry = DateTime.utc(
      rawExpiry.year,
      rawExpiry.month,
      rawExpiry.day,
      rawExpiry.hour,
      rawExpiry.minute,
      rawExpiry.second,
      rawExpiry.millisecond,
    );
    command = InvitationCreateCommand(
      mutationId: _mutationId(),
      expiresAt: expiry,
    );
    final stored = await _createMutationStore.write(_client.accountId, command);
    if (!stored) {
      throw const InvitationException(InvitationFailure.unavailable);
    }
    _pendingCreate = command;
    return command;
  }

  Future<void> _sendCreate(InvitationCreateCommand command) async {
    try {
      final created = await _client.create(
        mutationId: command.mutationId,
        expiresAt: command.expiresAt,
      );
      if (_disposed) return;
      final removed = await _createMutationStore.remove(
        _client.accountId,
        command,
      );
      if (!removed) {
        throw const InvitationException(InvitationFailure.unavailable);
      }
      if (_disposed) return;
      _pendingCreate = null;
      _open = List.unmodifiable([
        for (final row in _open)
          if (row.id != created.id) row,
      ]);
      _history = List.unmodifiable([
        for (final row in _history)
          if (row.id != created.id) row,
      ]);
      if (created.state.isTerminal) {
        _history = _insertOrdered(_history, created);
      } else {
        _open = _insertOrdered(_open, created);
        _openLoaded = true;
      }
    } on InvitationException catch (error) {
      if (!_ambiguousCreateFailure(error.failure)) {
        final removed = await _createMutationStore.remove(
          _client.accountId,
          command,
        );
        if (removed) _pendingCreate = null;
      }
      rethrow;
    }
  }

  bool _ambiguousCreateFailure(InvitationFailure failure) => switch (failure) {
    InvitationFailure.timeout ||
    InvitationFailure.unavailable ||
    InvitationFailure.invalidResponse ||
    InvitationFailure.closed => true,
    _ => false,
  };

  /// Addresses a draft by handle. The server performs the X lookup.
  Future<void> addressByHandle(InvitationRecord record, String handle) async {
    await _run(() async {
      var entered = handle.trim();
      if (entered.startsWith('@')) entered = entered.substring(1);
      final updated = await _client.act(
        invitationId: record.id,
        action: InvitationAction.address,
        expectedVersion: record.version,
        xHandle: entered,
      );
      _replace(updated);
    });
  }

  Future<void> act(InvitationRecord record, InvitationAction action) async {
    await _run(() async {
      if (action == InvitationAction.address) {
        throw const InvitationException(InvitationFailure.invalidRequest);
      }
      try {
        final updated = await _client.act(
          invitationId: record.id,
          action: action,
          expectedVersion: record.version,
        );
        _replace(updated);
      } on InvitationException catch (error) {
        if (error.failure == InvitationFailure.versionConflict ||
            error.failure == InvitationFailure.expired ||
            error.failure == InvitationFailure.invalidTransition) {
          await _reloadOpen();
        }
        rethrow;
      }
    });
  }

  Future<void> _reloadOpen() async {
    try {
      final page = await _client.list(
        box: InvitationBox.open,
        limit: invitationPageLimit,
      );
      if (_disposed) return;
      _applyPage(page, append: false, requestedCursor: null);
    } on InvitationException {
      // Keep the action failure that the caller is about to see.
    }
  }

  void _applyPage(
    InvitationPage page, {
    required bool append,
    required String? requestedCursor,
  }) {
    if (_disposed) return;
    if (requestedCursor != null && page.nextCursor == requestedCursor) {
      throw const InvitationException(InvitationFailure.invalidResponse);
    }
    final current = page.box == InvitationBox.open ? _open : _history;
    final next = append ? <InvitationRecord>[...current] : <InvitationRecord>[];
    final ids = next.map((row) => row.id).toSet();
    for (final record in page.invitations) {
      if (!ids.add(record.id)) {
        throw const InvitationException(InvitationFailure.invalidResponse);
      }
      next.add(record);
    }
    if (append && !_isOrdered(next)) {
      throw const InvitationException(InvitationFailure.invalidResponse);
    }
    _incomingInvitations = page.incomingInvitations;
    if (page.incomingInvitations == IncomingInvitationsStatus.xLinkRequired) {
      _open = List.unmodifiable(_open.where((row) => row.isSender));
    }
    if (page.box == InvitationBox.open) {
      _open = List.unmodifiable(next);
      _openCursor = page.nextCursor;
      _openLoaded = true;
    } else {
      _history = List.unmodifiable(next);
      _historyCursor = page.nextCursor;
      _historyLoaded = true;
    }
  }

  void _replace(InvitationRecord updated) {
    if (_disposed) return;
    _open = List.unmodifiable([
      for (final row in _open)
        if (row.id != updated.id) row,
    ]);
    _history = List.unmodifiable([
      for (final row in _history)
        if (row.id != updated.id) row,
    ]);
    if (updated.state.isTerminal) {
      if (_historyLoaded) _history = _insertOrdered(_history, updated);
    } else {
      _open = _insertOrdered(_open, updated);
      _openLoaded = true;
    }
  }

  List<InvitationRecord> _insertOrdered(
    List<InvitationRecord> records,
    InvitationRecord inserted,
  ) {
    final next = <InvitationRecord>[...records, inserted]..sort(_compare);
    return List.unmodifiable(next);
  }

  int _compare(InvitationRecord left, InvitationRecord right) {
    final time = right.createdAt.compareTo(left.createdAt);
    return time != 0 ? time : right.id.compareTo(left.id);
  }

  bool _isOrdered(List<InvitationRecord> records) {
    for (var index = 1; index < records.length; index++) {
      if (_compare(records[index - 1], records[index]) > 0) return false;
    }
    return true;
  }
}
