import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'career_repository.dart';

const _maxSafeInteger = 9007199254740991;
const reasonPageDefaultLimit = 20;
const reasonPageMaximumLimit = 50;

/// Who may read a person's saved trade reasons. The server stores all three
/// values. Friends sharing publishes nothing until a friendship graph exists.
enum ReasonVisibility {
  nobody('nobody', 'Nobody'),
  everyone('everyone', 'Everyone'),
  friends('friends', 'Friends');

  const ReasonVisibility(this.wire, this.label);

  final String wire;
  final String label;
}

enum ReasonDeskCycle { current, historical }

enum FriendsSharingAvailability { unavailable, available }

enum ReasonSharingFailure {
  invalidInput,
  invalidResponse,
  unavailable,
  offline,
  timeout,
  accountRequired,
  accountNotFound,
  revisionConflict,
  idempotencyConflict,
  revisionExhausted,
  rateLimited,
  rejected,
}

final class ReasonSharingException implements Exception {
  const ReasonSharingException(this.failure, {this.retryAfter});

  final ReasonSharingFailure failure;

  /// The exact server retry delay for a limited request, when it sent one.
  final Duration? retryAfter;

  /// The request may have reached the server without a readable answer.
  bool get ambiguous =>
      failure == ReasonSharingFailure.offline ||
      failure == ReasonSharingFailure.timeout ||
      failure == ReasonSharingFailure.unavailable ||
      failure == ReasonSharingFailure.invalidResponse;

  @override
  String toString() => 'ReasonSharingException(${failure.name})';
}

@immutable
final class ReasonPrivacy {
  const ReasonPrivacy({
    required this.revision,
    required this.visibility,
    required this.configured,
    required this.createdAt,
    required this.updatedAt,
    this.friendsSharing = FriendsSharingAvailability.unavailable,
  });

  final int revision;
  final ReasonVisibility visibility;
  final bool configured;
  final DateTime createdAt;
  final DateTime updatedAt;
  final FriendsSharingAvailability friendsSharing;

  bool get friendsSharingAvailable =>
      friendsSharing == FriendsSharingAvailability.available;
}

/// One idempotent, revision-checked privacy choice.
@immutable
final class ReasonPrivacyWrite {
  factory ReasonPrivacyWrite({
    required String mutationId,
    required int baseRevision,
    required ReasonVisibility visibility,
  }) {
    if (!isReasonSharingUuid(mutationId) ||
        baseRevision < 1 ||
        baseRevision > _maxSafeInteger) {
      throw const ReasonSharingException(ReasonSharingFailure.invalidInput);
    }
    return ReasonPrivacyWrite._(
      mutationId: mutationId.toLowerCase(),
      baseRevision: baseRevision,
      visibility: visibility,
    );
  }

  const ReasonPrivacyWrite._({
    required this.mutationId,
    required this.baseRevision,
    required this.visibility,
  });

  final String mutationId;
  final int baseRevision;
  final ReasonVisibility visibility;

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'mutationId': mutationId,
    'baseRevision': baseRevision,
    'visibility': visibility.wire,
  };

  /// Restores a stored command. Returns null for anything but an exact shape.
  static ReasonPrivacyWrite? fromJson(Object? input) {
    if (input is! Map<String, dynamic> ||
        input.length != 4 ||
        input['schemaVersion'] != 1) {
      return null;
    }
    final mutationId = input['mutationId'];
    final baseRevision = input['baseRevision'];
    final visibility = input['visibility'];
    if (mutationId is! String ||
        baseRevision is! int ||
        visibility is! String) {
      return null;
    }
    final parsed = ReasonVisibility.values
        .where((value) => value.wire == visibility)
        .firstOrNull;
    if (parsed == null) return null;
    try {
      return ReasonPrivacyWrite(
        mutationId: mutationId,
        baseRevision: baseRevision,
        visibility: parsed,
      );
    } on ReasonSharingException {
      return null;
    }
  }
}

/// The server's answer to one exact write. The HTTP contract does not echo
/// the mutation, so the repository binds it after validating the resource.
@immutable
final class ReasonPrivacyReceipt {
  const ReasonPrivacyReceipt({
    required this.mutationId,
    required this.baseRevision,
    required this.visibility,
    required this.privacy,
  });

  final String mutationId;
  final int baseRevision;
  final ReasonVisibility visibility;
  final ReasonPrivacy privacy;

  /// True when the returned resource is exactly this write's result. A replay
  /// after a later change returns the newer resource instead.
  bool get exact =>
      privacy.revision == baseRevision + 1 && privacy.visibility == visibility;
}

@immutable
final class ReasonAuthor {
  const ReasonAuthor({
    required this.handle,
    required this.rank,
    required this.rankLabel,
    required this.isViewer,
    this.socialId,
    this.persona,
  });

  final String handle;
  final CareerRank rank;
  final String rankLabel;
  final bool isViewer;

  /// Present only on the friends projection. Self and public-everyone rows
  /// retain their smaller rolling-compatible author shape.
  final String? socialId;
  final String? persona;
}

@immutable
final class ReasonStock {
  const ReasonStock({
    required this.assetId,
    required this.variantMint,
    required this.symbol,
  });

  final String assetId;
  final String variantMint;
  final String symbol;
}

/// The public projection of one reason. It carries no order identity, size,
/// cost, price, performance or money claim.
@immutable
final class SharedReason {
  const SharedReason({
    required this.reasonId,
    required this.author,
    required this.stock,
    required this.note,
    required this.savedAt,
  });

  final String reasonId;
  final ReasonAuthor author;
  final ReasonStock stock;
  final String note;
  final DateTime savedAt;
}

/// One entry of the caller's own immutable reason history.
@immutable
final class OwnReason {
  const OwnReason({
    required this.reasonId,
    required this.orderId,
    required this.author,
    required this.stock,
    required this.note,
    required this.deskCycle,
    required this.savedAt,
  });

  final String reasonId;
  final String orderId;
  final ReasonAuthor author;
  final ReasonStock stock;
  final String note;
  final ReasonDeskCycle deskCycle;
  final DateTime savedAt;
}

@immutable
final class ReasonPage<T> {
  factory ReasonPage({
    required Iterable<T> items,
    required int limit,
    required String? nextCursor,
  }) => ReasonPage._(
    items: List<T>.unmodifiable(items),
    limit: limit,
    nextCursor: nextCursor,
  );

  const ReasonPage._({
    required this.items,
    required this.limit,
    required this.nextCursor,
  });

  final List<T> items;
  final int limit;

  /// An opaque continuation bound to the same scope and stock, or null when
  /// this page is the last one.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// A read of the caller's own history, optionally narrowed to one stock.
@immutable
final class OwnReasonQuery {
  factory OwnReasonQuery({
    String? assetId,
    String? variantMint,
    int limit = reasonPageDefaultLimit,
    String? cursor,
  }) {
    if ((assetId == null) != (variantMint == null) ||
        assetId != null && !isReasonSharingAssetId(assetId) ||
        variantMint != null && !isReasonSharingMint(variantMint) ||
        limit < 1 ||
        limit > reasonPageMaximumLimit ||
        cursor != null && !isReasonSharingCursor(cursor)) {
      throw const ReasonSharingException(ReasonSharingFailure.invalidInput);
    }
    return OwnReasonQuery._(
      assetId: assetId,
      variantMint: variantMint,
      limit: limit,
      cursor: cursor,
    );
  }

  const OwnReasonQuery._({
    required this.assetId,
    required this.variantMint,
    required this.limit,
    required this.cursor,
  });

  final String? assetId;
  final String? variantMint;
  final int limit;
  final String? cursor;
}

/// A read of everyone's shared reasons on exactly one stock version.
@immutable
final class SharedReasonQuery {
  factory SharedReasonQuery({
    required String assetId,
    required String variantMint,
    int limit = reasonPageDefaultLimit,
    String? cursor,
  }) {
    if (!isReasonSharingAssetId(assetId) ||
        !isReasonSharingMint(variantMint) ||
        limit < 1 ||
        limit > reasonPageMaximumLimit ||
        cursor != null && !isReasonSharingCursor(cursor)) {
      throw const ReasonSharingException(ReasonSharingFailure.invalidInput);
    }
    return SharedReasonQuery._(
      assetId: assetId,
      variantMint: variantMint,
      limit: limit,
      cursor: cursor,
    );
  }

  const SharedReasonQuery._({
    required this.assetId,
    required this.variantMint,
    required this.limit,
    required this.cursor,
  });

  final String assetId;
  final String variantMint;
  final int limit;
  final String? cursor;
}

abstract interface class ReasonSharingRepository {
  Future<ReasonPrivacy> getPrivacy();
  Future<ReasonPrivacyReceipt> putPrivacy(ReasonPrivacyWrite write);
  Future<ReasonPage<OwnReason>> listOwnReasons(OwnReasonQuery query);
  Future<ReasonPage<SharedReason>> listSharedReasons(SharedReasonQuery query);
  Future<ReasonPage<SharedReason>> listFriendReasons(SharedReasonQuery query);
}

/// The decoded continuation cursor. The server binds every cursor to one
/// scope, one exact stock filter, and the last row's saved time and public ID.
@immutable
final class ReasonCursor {
  const ReasonCursor({
    required this.scope,
    required this.assetId,
    required this.variantMint,
    required this.savedAt,
    required this.reasonId,
    this.principalSocialId,
  });

  final String scope;
  final String? assetId;
  final String? variantMint;
  final DateTime savedAt;
  final String reasonId;
  final String? principalSocialId;

  /// Returns null unless the cursor is canonical base64url JSON in the exact
  /// server layout. Friends cursors also bind the caller's public social ID.
  static ReasonCursor? decode(String value) {
    if (!isReasonSharingCursor(value)) return null;
    List<int> bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(value));
    } on FormatException {
      return null;
    }
    if (bytes.length > 384 ||
        base64Url.encode(bytes).replaceAll('=', '') != value) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException {
      return null;
    }
    if (decoded is! List) {
      return null;
    }
    final bool friendsCursor;
    final Object? principalSocialId;
    final Object? scope;
    final Object? assetId;
    final Object? variantMint;
    final Object? savedAt;
    final Object? reasonId;
    if (decoded.length == 6 && decoded[0] == 1) {
      friendsCursor = false;
      principalSocialId = null;
      scope = decoded[1];
      assetId = decoded[2];
      variantMint = decoded[3];
      savedAt = decoded[4];
      reasonId = decoded[5];
    } else if (decoded.length == 8 &&
        decoded[0] == 2 &&
        decoded[1] == 'career-reasons') {
      friendsCursor = true;
      principalSocialId = decoded[2];
      scope = decoded[3];
      assetId = decoded[4];
      variantMint = decoded[5];
      savedAt = decoded[6];
      reasonId = decoded[7];
    } else {
      return null;
    }
    if (scope is! String ||
        (friendsCursor
            ? scope != 'friends'
            : scope != 'self' && scope != 'everyone') ||
        (friendsCursor &&
            (principalSocialId is! String ||
                !isReasonSharingUuid(principalSocialId) ||
                principalSocialId != principalSocialId.toLowerCase())) ||
        (assetId == null) != (variantMint == null) ||
        assetId != null &&
            (assetId is! String || !isReasonSharingAssetId(assetId)) ||
        variantMint != null &&
            (variantMint is! String || !isReasonSharingMint(variantMint)) ||
        (scope == 'everyone' || scope == 'friends') && assetId == null ||
        savedAt is! String ||
        reasonId is! String ||
        !isReasonSharingUuid(reasonId) ||
        reasonId != reasonId.toLowerCase()) {
      return null;
    }
    final parsedSavedAt = parseReasonSharingTimestamp(savedAt);
    if (parsedSavedAt == null) return null;
    return ReasonCursor(
      scope: scope,
      assetId: assetId as String?,
      variantMint: variantMint as String?,
      savedAt: parsedSavedAt,
      reasonId: reasonId,
      principalSocialId: principalSocialId as String?,
    );
  }
}

bool isReasonSharingUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

bool isReasonSharingAssetId(String value) =>
    value.length <= 100 &&
    RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value);

bool isReasonSharingMint(String value) =>
    RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(value);

bool isReasonSharingCursor(String value) =>
    value.isNotEmpty &&
    value.length <= 512 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

/// Parses only the exact millisecond UTC form the server writes.
DateTime? parseReasonSharingTimestamp(String value) {
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  ).hasMatch(value)) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    return null;
  }
  return parsed;
}
