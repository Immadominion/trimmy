import 'dart:async';

import 'package:trimmy/product/career/career.dart';

const testReasonMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const testReasonMutation = '11111111-1111-4111-8111-111111111111';
const testOtherReasonMutation = '22222222-2222-4222-8222-222222222222';

final class FakeReasonSharingRepository implements ReasonSharingRepository {
  final privacyReads = <FutureOr<ReasonPrivacy>>[];
  final writes = <ReasonPrivacyWrite>[];
  final sharedQueries = <SharedReasonQuery>[];
  final friendQueries = <SharedReasonQuery>[];
  final ownQueries = <OwnReasonQuery>[];
  FutureOr<ReasonPrivacyReceipt> Function(ReasonPrivacyWrite)? onPut;
  FutureOr<ReasonPage<SharedReason>> Function(SharedReasonQuery)? onShared;
  FutureOr<ReasonPage<SharedReason>> Function(SharedReasonQuery)? onFriends;
  FutureOr<ReasonPage<OwnReason>> Function(OwnReasonQuery)? onOwn;
  var privacyReadCount = 0;

  @override
  Future<ReasonPrivacy> getPrivacy() async {
    privacyReadCount++;
    if (privacyReads.isEmpty) throw StateError('No privacy read queued.');
    return privacyReads.removeAt(0);
  }

  @override
  Future<ReasonPage<SharedReason>> listFriendReasons(
    SharedReasonQuery query,
  ) async {
    friendQueries.add(query);
    final handler = onFriends;
    if (handler == null) {
      return ReasonPage<SharedReason>(
        items: const [],
        limit: query.limit,
        nextCursor: null,
      );
    }
    return handler(query);
  }

  @override
  Future<ReasonPrivacyReceipt> putPrivacy(ReasonPrivacyWrite write) async {
    writes.add(write);
    final handler = onPut;
    if (handler == null) throw StateError('No privacy write queued.');
    return handler(write);
  }

  @override
  Future<ReasonPage<SharedReason>> listSharedReasons(
    SharedReasonQuery query,
  ) async {
    sharedQueries.add(query);
    final handler = onShared;
    if (handler == null) throw StateError('No shared read queued.');
    return handler(query);
  }

  @override
  Future<ReasonPage<OwnReason>> listOwnReasons(OwnReasonQuery query) async {
    ownQueries.add(query);
    final handler = onOwn;
    if (handler == null) {
      return ReasonPage<OwnReason>(
        items: const [],
        limit: query.limit,
        nextCursor: null,
      );
    }
    return handler(query);
  }
}

ReasonPrivacy testPrivacy({
  int revision = 1,
  ReasonVisibility visibility = ReasonVisibility.nobody,
  bool? configured,
  FriendsSharingAvailability friendsSharing =
      FriendsSharingAvailability.unavailable,
}) {
  final isConfigured = configured ?? revision > 1;
  return ReasonPrivacy(
    revision: revision,
    visibility: visibility,
    configured: isConfigured,
    friendsSharing: friendsSharing,
    createdAt: DateTime.utc(2026, 9, 20, 10),
    updatedAt: isConfigured
        ? DateTime.utc(2026, 9, 20, 10, 0, revision)
        : DateTime.utc(2026, 9, 20, 10),
  );
}

ReasonPrivacyReceipt testReceipt(
  ReasonPrivacyWrite write, {
  ReasonPrivacy? privacy,
}) => ReasonPrivacyReceipt(
  mutationId: write.mutationId,
  baseRevision: write.baseRevision,
  visibility: write.visibility,
  privacy:
      privacy ??
      testPrivacy(
        revision: write.baseRevision + 1,
        visibility: write.visibility,
      ),
);

ReasonAuthor testAuthor({
  String handle = 'ada_trade',
  CareerRank rank = CareerRank.analyst,
  bool isViewer = false,
}) => ReasonAuthor(
  handle: handle,
  rank: rank,
  rankLabel: switch (rank) {
    CareerRank.rookie => 'Rookie',
    CareerRank.analyst => 'Analyst',
    CareerRank.trader => 'Trader',
    CareerRank.seniorTrader => 'Senior Trader',
    CareerRank.partner => 'Partner',
    CareerRank.legend => 'Legend',
  },
  isViewer: isViewer,
);

const testReasonStock = ReasonStock(
  assetId: 'apple',
  variantMint: testReasonMint,
  symbol: 'AAPLx',
);

SharedReason testSharedReason({
  required String reasonId,
  String handle = 'ada_trade',
  CareerRank rank = CareerRank.analyst,
  bool isViewer = false,
  String note = 'Margins improved for a second quarter.',
  DateTime? savedAt,
}) => SharedReason(
  reasonId: reasonId,
  author: testAuthor(handle: handle, rank: rank, isViewer: isViewer),
  stock: testReasonStock,
  note: note,
  savedAt: savedAt ?? DateTime.utc(2026, 9, 20, 12),
);

OwnReason testOwnReason({
  required String reasonId,
  required String orderId,
  ReasonDeskCycle deskCycle = ReasonDeskCycle.current,
  DateTime? savedAt,
}) => OwnReason(
  reasonId: reasonId,
  orderId: orderId,
  author: testAuthor(handle: 'mira', rank: CareerRank.rookie, isViewer: true),
  stock: testReasonStock,
  note: 'Bought after the product event.',
  deskCycle: deskCycle,
  savedAt: savedAt ?? DateTime.utc(2026, 9, 20, 11),
);
