import 'dart:math';

import 'package:flutter/foundation.dart';

import 'http_relationships_client.dart';
import 'relationship.dart';
import 'relationship_mutation_store.dart';

const relationshipPageLimit = 20;

typedef RelationshipMutationIdFactory = String Function();

enum RelationshipNotice { friendRemoved, blocked, unblocked, reasonReported }

String _newRelationshipMutationId() {
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

/// Owns one verified account's relationship lists and durable safety writes.
///
/// Confirmed list data stays in memory. Commands that may have committed are
/// journaled before dispatch and replayed byte for byte after restart.
final class RelationshipsController extends ChangeNotifier {
  factory RelationshipsController({
    required HttpRelationshipsClient client,
    RelationshipMutationStore? mutationStore,
    RelationshipMutationIdFactory? mutationId,
  }) => RelationshipsController._(
    client,
    mutationStore ?? MemoryRelationshipMutationStore(),
    mutationId ?? _newRelationshipMutationId,
  );

  RelationshipsController._(
    this._client,
    this._mutationStore,
    this._mutationId,
  );

  final HttpRelationshipsClient _client;
  final RelationshipMutationStore _mutationStore;
  final RelationshipMutationIdFactory _mutationId;

  List<FriendRecord> _friends = const [];
  List<BlockedProfile> _blocks = const [];
  final Set<String> _reportedReasonIds = {};
  final Set<String> _pendingMutationIds = {};
  String? _friendsCursor;
  String? _blocksCursor;
  bool _friendsLoaded = false;
  bool _blocksLoaded = false;
  bool _busy = false;
  bool _disposed = false;
  RelationshipFailure? _failure;
  RelationshipNotice? _notice;

  String get accountId => _client.accountId;
  List<FriendRecord> get friends => _friends;
  List<BlockedProfile> get blocks => _blocks;
  bool get friendsLoaded => _friendsLoaded;
  bool get blocksLoaded => _blocksLoaded;
  bool get hasMoreFriends => _friendsCursor != null;
  bool get hasMoreBlocks => _blocksCursor != null;
  bool get busy => _busy;
  RelationshipFailure? get failure => _failure;
  RelationshipNotice? get notice => _notice;

  bool hasReported(String reasonId) => _reportedReasonIds.contains(reasonId);
  bool mutationPending(String mutationId) =>
      _pendingMutationIds.contains(mutationId);

  void clearNotice() {
    if (_notice == null || _disposed) return;
    _notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close();
    _friends = const [];
    _blocks = const [];
    _reportedReasonIds.clear();
    _pendingMutationIds.clear();
    _friendsCursor = null;
    _blocksCursor = null;
    _friendsLoaded = false;
    _blocksLoaded = false;
    _failure = null;
    _notice = null;
    super.dispose();
  }

  Future<bool> refreshFriends() => _run(() async {
    final page = await _client.listFriends(limit: relationshipPageLimit);
    _applyFriends(page, append: false, requestedCursor: null);
  });

  Future<bool> loadMoreFriends() async {
    final cursor = _friendsCursor;
    if (_friendsLoaded && cursor == null) return true;
    return _run(() async {
      final page = await _client.listFriends(
        limit: relationshipPageLimit,
        cursor: _friendsLoaded ? cursor : null,
      );
      _applyFriends(
        page,
        append: _friendsLoaded,
        requestedCursor: _friendsLoaded ? cursor : null,
      );
    });
  }

  Future<bool> refreshBlocks() => _run(() async {
    final page = await _client.listBlocks(limit: relationshipPageLimit);
    _applyBlocks(page, append: false, requestedCursor: null);
  });

  Future<bool> loadMoreBlocks() async {
    final cursor = _blocksCursor;
    if (_blocksLoaded && cursor == null) return true;
    return _run(() async {
      final page = await _client.listBlocks(
        limit: relationshipPageLimit,
        cursor: _blocksLoaded ? cursor : null,
      );
      _applyBlocks(
        page,
        append: _blocksLoaded,
        requestedCursor: _blocksLoaded ? cursor : null,
      );
    });
  }

  Future<bool> removeFriend(FriendRecord friend) => _run(() async {
    await _execute(
      FriendRemoveCommand(
        friendshipId: friend.friendshipId,
        mutationId: _mutationId(),
        expectedRevision: friend.revision,
      ),
    );
  });

  /// Reads the exact caller-owned block snapshot before creating a command.
  /// A stale cross-device intent therefore conflicts instead of overwriting a
  /// later choice.
  Future<bool> setBlocked({
    required String socialId,
    required bool blocked,
    String? knownHandle,
  }) => _run(() async {
    final state = await _client.getBlock(socialId);
    if (state.blocked == blocked) {
      _applyKnownBlockState(state, knownHandle: knownHandle);
      return;
    }
    await _execute(
      BlockCommand(
        socialId: socialId,
        mutationId: _mutationId(),
        baseRevision: state.revision,
        blocked: blocked,
      ),
      knownHandle: knownHandle,
    );
  });

  Future<bool> reportReason({
    required String reasonId,
    required ReasonReportCategory category,
  }) => _run(() async {
    if (_reportedReasonIds.contains(reasonId)) return;
    await _execute(
      ReasonReportCommand(
        mutationId: _mutationId(),
        reasonId: reasonId,
        category: category,
      ),
    );
  });

  /// Replays commands whose commit could not be determined in an earlier
  /// process. It never changes their mutation IDs, targets or revisions.
  Future<bool> resumePendingMutations() => _run(() async {
    final commands = await _mutationStore.read(accountId);
    _pendingMutationIds.addAll(commands.map((command) => command.mutationId));
    _notify();
    for (final command in commands) {
      await _execute(command, alreadyStored: true);
    }
  });

  Future<void> _execute(
    RelationshipMutationCommand command, {
    bool alreadyStored = false,
    String? knownHandle,
  }) async {
    if (!alreadyStored) {
      final stored = await _mutationStore.write(accountId, command);
      if (!stored) {
        throw const RelationshipException(RelationshipFailure.unavailable);
      }
    }
    _pendingMutationIds.add(command.mutationId);
    _notify();

    Object receipt;
    try {
      receipt = switch (command) {
        FriendRemoveCommand value => await _client.removeFriend(value),
        BlockCommand value => await _client.putBlock(value),
        ReasonReportCommand value => await _client.reportReason(value),
      };
    } on RelationshipException catch (error) {
      if (!error.ambiguous) {
        final removed = await _mutationStore.remove(accountId, command);
        if (!removed) {
          throw const RelationshipException(RelationshipFailure.unavailable);
        }
        _pendingMutationIds.remove(command.mutationId);
      }
      rethrow;
    }

    final removed = await _mutationStore.remove(accountId, command);
    if (!removed) {
      throw const RelationshipException(RelationshipFailure.unavailable);
    }
    _pendingMutationIds.remove(command.mutationId);
    // Disposal is the account/session boundary. The receipt may have arrived
    // before disposal while durable journal cleanup completed afterward; do
    // not let that old operation repopulate state which dispose just cleared.
    if (_disposed) return;
    switch ((command, receipt)) {
      case (FriendRemoveCommand value, FriendRemoveReceipt result):
        if (value.mutationId != result.mutationId) {
          invalidRelationshipResponse();
        }
        _friends = List.unmodifiable(
          _friends.where((row) => row.friendshipId != result.friendshipId),
        );
        _notice = RelationshipNotice.friendRemoved;
      case (BlockCommand value, BlockReceipt result):
        if (value.mutationId != result.mutationId) {
          invalidRelationshipResponse();
        }
        _applyBlockReceipt(result, knownHandle: knownHandle);
        _notice = result.block.blocked
            ? RelationshipNotice.blocked
            : RelationshipNotice.unblocked;
      case (ReasonReportCommand value, ReasonReportReceipt result):
        if (value.reasonId != result.reasonId) invalidRelationshipResponse();
        _reportedReasonIds.add(result.reasonId);
        _notice = RelationshipNotice.reasonReported;
      default:
        invalidRelationshipResponse();
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_disposed || _busy) return false;
    _busy = true;
    _failure = null;
    _notice = null;
    _notify();
    var succeeded = false;
    try {
      await action();
      succeeded = true;
    } on RelationshipException catch (error) {
      _failure = error.failure;
    } catch (_) {
      _failure = RelationshipFailure.unavailable;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
    return succeeded;
  }

  void _applyFriends(
    FriendPage page, {
    required bool append,
    required String? requestedCursor,
  }) {
    if (_disposed) return;
    if (requestedCursor != null && page.nextCursor == requestedCursor) {
      invalidRelationshipResponse();
    }
    final rows = append ? <FriendRecord>[..._friends] : <FriendRecord>[];
    final friendshipIds = rows.map((row) => row.friendshipId).toSet();
    final socialIds = rows.map((row) => row.person.socialId).toSet();
    for (final row in page.friends) {
      if (!friendshipIds.add(row.friendshipId) ||
          !socialIds.add(row.person.socialId)) {
        invalidRelationshipResponse();
      }
      rows.add(row);
    }
    if (!_friendsOrdered(rows)) invalidRelationshipResponse();
    _friends = List.unmodifiable(rows);
    _friendsCursor = page.nextCursor;
    _friendsLoaded = true;
  }

  void _applyBlocks(
    BlockPage page, {
    required bool append,
    required String? requestedCursor,
  }) {
    if (_disposed) return;
    if (requestedCursor != null && page.nextCursor == requestedCursor) {
      invalidRelationshipResponse();
    }
    final rows = append ? <BlockedProfile>[..._blocks] : <BlockedProfile>[];
    final socialIds = rows.map((row) => row.socialId).toSet();
    for (final row in page.blocks) {
      if (!socialIds.add(row.socialId)) invalidRelationshipResponse();
      rows.add(row);
    }
    if (!_blocksOrdered(rows)) invalidRelationshipResponse();
    _blocks = List.unmodifiable(rows);
    _blocksCursor = page.nextCursor;
    _blocksLoaded = true;
  }

  bool _friendsOrdered(List<FriendRecord> rows) {
    for (var index = 1; index < rows.length; index++) {
      final left = rows[index - 1];
      final right = rows[index];
      final time = left.connectedAt.compareTo(right.connectedAt);
      if (time < 0 ||
          time == 0 && left.friendshipId.compareTo(right.friendshipId) <= 0) {
        return false;
      }
    }
    return true;
  }

  bool _blocksOrdered(List<BlockedProfile> rows) {
    for (var index = 1; index < rows.length; index++) {
      final left = rows[index - 1];
      final right = rows[index];
      final time = left.updatedAt.compareTo(right.updatedAt);
      if (time < 0 ||
          time == 0 && left.socialId.compareTo(right.socialId) <= 0) {
        return false;
      }
    }
    return true;
  }

  void _applyKnownBlockState(BlockState state, {String? knownHandle}) {
    if (state.blocked) {
      final updatedAt = state.updatedAt;
      if (updatedAt == null || state.revision < 1) {
        invalidRelationshipResponse();
      }
      _friends = List.unmodifiable(
        _friends.where((row) => row.person.socialId != state.socialId),
      );
      _upsertBlock(
        BlockedProfile(
          socialId: state.socialId,
          handle: _knownHandle(state.socialId, knownHandle),
          revision: state.revision,
          updatedAt: updatedAt,
        ),
      );
    } else {
      _blocks = List.unmodifiable(
        _blocks.where((row) => row.socialId != state.socialId),
      );
    }
  }

  void _applyBlockReceipt(BlockReceipt receipt, {String? knownHandle}) {
    final snapshot = receipt.block;
    if (snapshot.blocked) {
      _friends = List.unmodifiable(
        _friends.where((row) => row.person.socialId != snapshot.socialId),
      );
      _upsertBlock(
        BlockedProfile(
          socialId: snapshot.socialId,
          handle: _knownHandle(snapshot.socialId, knownHandle),
          revision: snapshot.revision,
          updatedAt: snapshot.updatedAt,
        ),
      );
    } else {
      _blocks = List.unmodifiable(
        _blocks.where((row) => row.socialId != snapshot.socialId),
      );
    }
  }

  String? _knownHandle(String socialId, String? supplied) {
    if (supplied != null) return supplied;
    for (final row in _blocks) {
      if (row.socialId == socialId) return row.handle;
    }
    for (final row in _friends) {
      if (row.person.socialId == socialId) return row.person.handle;
    }
    return null;
  }

  void _upsertBlock(BlockedProfile block) {
    final rows =
        <BlockedProfile>[
          for (final row in _blocks)
            if (row.socialId != block.socialId) row,
          block,
        ]..sort((left, right) {
          final time = right.updatedAt.compareTo(left.updatedAt);
          return time != 0 ? time : right.socialId.compareTo(left.socialId);
        });
    _blocks = List.unmodifiable(rows);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
