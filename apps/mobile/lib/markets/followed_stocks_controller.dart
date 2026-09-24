// ignore_for_file: prefer_initializing_formals
// A private initializing formal would make the named argument `_client`,
// which reads worse at every call site than the assignment below.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'followed_stocks.dart';

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

/// The signed-in account's real followed list.
///
/// The server stores the whole list at a revision, so following or unfollowing
/// one asset rewrites the list from the revision this controller last saw. A
/// stale revision is refused rather than overwritten; the refusal carries the
/// current list, so one retry from that state is enough and the person's tap is
/// not silently lost.
///
/// Nothing here is an approval. A followed asset is a name someone kept.
class FollowedStocksController extends ChangeNotifier {
  FollowedStocksController({
    required HttpFollowedStocksClient client,
    String Function()? mutationId,
  }) : _mutationId = mutationId ?? _newMutationId,
       _client = client;

  final HttpFollowedStocksClient _client;
  final String Function() _mutationId;

  FollowedStocks? _snapshot;
  FollowedStocksFailure? _failure;
  bool _busy = false;
  bool _disposed = false;

  /// Assets currently followed, in the order they were added.
  List<String> get assetIds => _snapshot?.assetIds ?? const <String>[];
  bool get loaded => _snapshot != null;
  bool get busy => _busy;
  FollowedStocksFailure? get failure => _failure;
  int get revision => _snapshot?.revision ?? 0;
  bool get isFull => assetIds.length >= 50;

  bool isFollowing(String assetId) => assetIds.contains(assetId);

  /// Reads the list. Nothing is fetched until something asks.
  Future<void> refresh() => _run(() async => _client.read());

  Future<void> follow(String assetId) {
    if (!FollowedStocks.isStorableId(assetId)) {
      return _fail(FollowedStocksFailure.invalidRequest);
    }
    return _rewrite((current) {
      if (current.contains(assetId)) return null;
      if (current.assetIds.length >= 50) {
        throw const FollowedStocksException(FollowedStocksFailure.limitReached);
      }
      return [...current.assetIds, assetId];
    });
  }

  Future<void> unfollow(String assetId) => _rewrite((current) {
    if (!current.contains(assetId)) return null;
    return [
      for (final id in current.assetIds)
        if (id != assetId) id,
    ];
  });

  /// Applies [change] to the list at the revision last seen. A refusal carries
  /// the current list, so the same change is reapplied to that once.
  Future<void> _rewrite(List<String>? Function(FollowedStocks) change) async {
    if (_busy) return _fail(FollowedStocksFailure.busy);
    var current = _snapshot;
    _busy = true;
    _failure = null;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        current ??= await _client.read();
        final next = change(current);
        if (next == null) {
          // Already in the wanted state; the read still refreshed what is shown.
          _snapshot = current;
          return;
        }
        try {
          _snapshot = await _client.write(
            baseRevision: current.revision,
            assetIds: next,
            mutationId: _mutationId(),
          );
          return;
        } on FollowedStocksException catch (error) {
          if (error.failure != FollowedStocksFailure.revisionConflict ||
              attempt == 1) {
            rethrow;
          }
          // Someone else changed it first. Start again from what is there now.
          current = await _client.read();
          _snapshot = current;
        }
      }
    } on FollowedStocksException catch (error) {
      _failure = error.failure;
    } catch (_) {
      _failure = FollowedStocksFailure.unavailable;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _run(Future<FollowedStocks> Function() work) async {
    if (_busy) return _fail(FollowedStocksFailure.busy);
    _busy = true;
    _failure = null;
    notifyListeners();
    try {
      _snapshot = await work();
    } on FollowedStocksException catch (error) {
      _failure = error.failure;
    } catch (_) {
      _failure = FollowedStocksFailure.unavailable;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _fail(FollowedStocksFailure failure) async {
    _failure = failure;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
