import 'package:flutter/foundation.dart';

import 'reason_sharing_repository.dart';

const ownReasonHistoryMaximumPages = 100;

/// The server still had another page after the bounded complete-history read.
///
/// Callers must surface this instead of treating the collected prefix as the
/// viewer's complete history.
final class OwnReasonHistoryIncompleteException implements Exception {
  const OwnReasonHistoryIncompleteException(this.maximumPages);

  final int maximumPages;

  @override
  String toString() =>
      'OwnReasonHistoryIncompleteException(maximumPages: $maximumPages)';
}

/// The viewer's own reason history, held in memory for one session only.
///
/// The server sends every read as `no-store`. This cache lives only as long
/// as the bound principal and is dropped on unbind, reset or a new reason.
final class OwnReasonHistory extends ChangeNotifier {
  OwnReasonHistory(
    this._repository, {
    this.maximumPages = ownReasonHistoryMaximumPages,
  }) {
    if (maximumPages < 1 || maximumPages > ownReasonHistoryMaximumPages) {
      throw RangeError.range(
        maximumPages,
        1,
        ownReasonHistoryMaximumPages,
        'maximumPages',
      );
    }
  }

  final ReasonSharingRepository _repository;
  final int maximumPages;
  final Map<String, Future<List<OwnReason>>> _byStock = {};
  final Map<String, int> _stockRevisions = {};
  int _revisionClock = 0;
  int _clearedAtRevision = 0;

  /// The viewer's reasons on one exact stock version, newest first.
  Future<List<OwnReason>> forStock({
    required String assetId,
    required String variantMint,
  }) {
    final key = _key(assetId, variantMint);
    final cached = _byStock[key];
    if (cached != null) return cached;
    late final Future<List<OwnReason>> read;
    read = _read(assetId: assetId, variantMint: variantMint).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (identical(_byStock[key], read)) _byStock.remove(key);
      return Future<List<OwnReason>>.error(error, stackTrace);
    });
    _byStock[key] = read;
    return read;
  }

  void invalidate({required String assetId, required String variantMint}) {
    final key = _key(assetId, variantMint);
    _byStock.remove(key);
    _stockRevisions[key] = ++_revisionClock;
    notifyListeners();
  }

  void clear({bool notify = true}) {
    _byStock.clear();
    _stockRevisions.clear();
    _clearedAtRevision = ++_revisionClock;
    if (notify) notifyListeners();
  }

  /// Changes only when this exact stock is invalidated or all history clears.
  int revisionForStock({required String assetId, required String variantMint}) {
    final stockRevision = _stockRevisions[_key(assetId, variantMint)] ?? 0;
    return stockRevision > _clearedAtRevision
        ? stockRevision
        : _clearedAtRevision;
  }

  Future<List<OwnReason>> _read({
    required String assetId,
    required String variantMint,
  }) async {
    final items = <OwnReason>[];
    String? cursor;
    for (var page = 0; page < maximumPages; page++) {
      final result = await _repository.listOwnReasons(
        OwnReasonQuery(
          assetId: assetId,
          variantMint: variantMint,
          limit: reasonPageMaximumLimit,
          cursor: cursor,
        ),
      );
      items.addAll(result.items);
      cursor = result.nextCursor;
      if (cursor == null) return List<OwnReason>.unmodifiable(items);
    }
    throw OwnReasonHistoryIncompleteException(maximumPages);
  }

  static String _key(String assetId, String variantMint) =>
      '$assetId:$variantMint';
}
