import 'package:flutter/foundation.dart';

enum CareerRank { rookie, analyst, trader, seniorTrader, partner, legend }

enum CareerStreakStatus { notStarted, active, atRisk, grace }

enum CareerMissionId { firstPaperBuy, writeAReason, holdThroughRedDay }

enum CareerMissionStatus { locked, ready, complete }

enum CareerMissionKind { action, promotion }

enum CareerFailure {
  invalidInput,
  invalidResponse,
  unavailable,
  offline,
  timeout,
  accountRequired,
  profileRequired,
  orderNotFound,
  buyOrderRequired,
  positionRequired,
  reasonExists,
  idempotencyConflict,
  dayContextRevisionConflict,
  timeZoneChangeTooSoon,
  revisionExhausted,
  rateLimited,
  rejected,
}

final class CareerException implements Exception {
  const CareerException(this.failure);

  final CareerFailure failure;

  @override
  String toString() => 'CareerException(${failure.name})';
}

@immutable
final class CareerTrims {
  const CareerTrims({
    required this.total,
    required this.today,
    required this.thisWeek,
  });

  final int total;
  final int today;
  final int thisWeek;
}

@immutable
final class CareerRankProgress {
  const CareerRankProgress({
    required this.id,
    required this.label,
    required this.paperLimit,
    required this.threshold,
  });

  final CareerRank id;
  final String label;
  final String paperLimit;
  final int threshold;
}

@immutable
final class CareerNextRank {
  const CareerNextRank({
    required this.id,
    required this.label,
    required this.threshold,
    required this.trimsRemaining,
    required this.promotionRequired,
  });

  final CareerRank id;
  final String label;
  final int threshold;
  final int trimsRemaining;
  final bool promotionRequired;
}

@immutable
final class CareerStreak {
  const CareerStreak({
    required this.days,
    required this.status,
    required this.lastActiveDate,
  });

  final int days;
  final CareerStreakStatus status;

  /// The server-owned Career calendar date in `YYYY-MM-DD` form.
  final String? lastActiveDate;
}

@immutable
final class CareerFirstConfirmedBuy {
  const CareerFirstConfirmedBuy({
    required this.orderId,
    required this.assetId,
    required this.variantMint,
    required this.symbol,
    required this.quantityMicros,
    required this.confirmedAt,
  });

  final String orderId;
  final String assetId;
  final String variantMint;
  final String symbol;

  /// The exact filled share quantity in millionths, as returned by the server.
  final String quantityMicros;
  final DateTime confirmedAt;

  /// The exact filled share quantity without trailing fractional zeroes.
  String get displayQuantity {
    final micros = BigInt.parse(quantityMicros);
    final whole = micros ~/ BigInt.from(1000000);
    final fraction = (micros % BigInt.from(1000000))
        .toString()
        .padLeft(6, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '$whole${fraction.isEmpty ? '' : '.$fraction'}';
  }
}

@immutable
final class CareerSummary {
  const CareerSummary({
    required this.revision,
    required this.trims,
    required this.rank,
    required this.nextRank,
    required this.streak,
    required this.careerStarted,
    required this.firstConfirmedBuy,
    required this.serverDate,
    required this.updatedAt,
  });

  final int revision;
  final CareerTrims trims;
  final CareerRankProgress rank;
  final CareerNextRank? nextRank;
  final CareerStreak streak;
  final bool careerStarted;
  final CareerFirstConfirmedBuy? firstConfirmedBuy;

  /// The server-owned Career calendar date in `YYYY-MM-DD` form.
  final String serverDate;
  final DateTime? updatedAt;
}

/// The server-owned calendar context used for Career day and week boundaries.
///
/// An unconfigured account remains on UTC until the client can provide a
/// valid named device time zone. Once configured, the client only reads this
/// value and never changes it automatically.
@immutable
final class CareerDayContext {
  const CareerDayContext({
    required this.revision,
    required this.timeZone,
    required this.configured,
    required this.serverDate,
    required this.nextDayAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final int revision;
  final String timeZone;
  final bool configured;
  final String serverDate;
  final DateTime nextDayAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// One idempotent request to configure or explicitly change a Career time
/// zone. Automatic device synchronization only creates this command while the
/// server context is still unconfigured.
@immutable
final class CareerDayContextWrite {
  factory CareerDayContextWrite({
    required String mutationId,
    required int baseRevision,
    required String timeZone,
  }) {
    if (!_uuid(mutationId) ||
        baseRevision < 1 ||
        baseRevision > 9007199254740991 ||
        !_careerTimeZone(timeZone)) {
      throw const CareerException(CareerFailure.invalidInput);
    }
    return CareerDayContextWrite._(
      mutationId: mutationId.toLowerCase(),
      baseRevision: baseRevision,
      timeZone: timeZone,
    );
  }

  const CareerDayContextWrite._({
    required this.mutationId,
    required this.baseRevision,
    required this.timeZone,
  });

  final String mutationId;
  final int baseRevision;
  final String timeZone;
}

/// A response bound to the exact write that produced it. The HTTP contract
/// does not echo the mutation ID, so the repository supplies the immutable
/// command identity only after validating the returned context.
@immutable
final class CareerDayContextReceipt {
  const CareerDayContextReceipt({
    required this.mutationId,
    required this.baseRevision,
    required this.timeZone,
    required this.dayContext,
  });

  final String mutationId;
  final int baseRevision;
  final String timeZone;
  final CareerDayContext dayContext;

  bool get changed => dayContext.revision == baseRevision + 1;
}

@immutable
final class CareerTradeReason {
  factory CareerTradeReason({
    required String mutationId,
    required String orderId,
    required String note,
  }) {
    final normalized = note.trim();
    if (!_uuid(mutationId) ||
        !_uuid(orderId) ||
        normalized.isEmpty ||
        normalized.runes.length > 180 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(normalized)) {
      throw const CareerException(CareerFailure.invalidInput);
    }
    return CareerTradeReason._(
      mutationId: mutationId.toLowerCase(),
      orderId: orderId.toLowerCase(),
      note: normalized,
    );
  }

  const CareerTradeReason._({
    required this.mutationId,
    required this.orderId,
    required this.note,
  });

  final String mutationId;
  final String orderId;
  final String note;
}

@immutable
final class CareerTradeReasonReceipt {
  const CareerTradeReasonReceipt({
    required this.orderId,
    required this.assetId,
    required this.variantMint,
    required this.note,
    required this.trimsAwarded,
    required this.dailyAwardNumber,
    required this.savedAt,
  });

  final String orderId;
  final String assetId;
  final String variantMint;
  final String note;
  final int trimsAwarded;
  final int? dailyAwardNumber;
  final DateTime savedAt;
}

@immutable
final class CareerMission {
  const CareerMission({
    required this.id,
    required this.chapterRank,
    required this.order,
    required this.kind,
    required this.title,
    required this.instruction,
    required this.trimsReward,
    required this.promotesToRank,
    required this.status,
    required this.completedAt,
  });

  final CareerMissionId id;
  final CareerRank chapterRank;
  final int order;
  final CareerMissionKind kind;
  final String title;
  final String instruction;
  final int trimsReward;
  final CareerRank? promotesToRank;
  final CareerMissionStatus status;
  final DateTime? completedAt;
}

@immutable
final class CareerMissionBoard {
  factory CareerMissionBoard({
    required int revision,
    required CareerRank currentRank,
    required Iterable<CareerMission> missions,
  }) => CareerMissionBoard._(
    revision: revision,
    currentRank: currentRank,
    missions: List<CareerMission>.unmodifiable(missions),
  );

  const CareerMissionBoard._({
    required this.revision,
    required this.currentRank,
    required this.missions,
  });

  final int revision;
  final CareerRank currentRank;
  final List<CareerMission> missions;
}

@immutable
final class CareerPromotionCommand {
  factory CareerPromotionCommand({
    required String mutationId,
    required CareerRank targetRank,
  }) {
    if (!_uuid(mutationId) || targetRank == CareerRank.rookie) {
      throw const CareerException(CareerFailure.invalidInput);
    }
    return CareerPromotionCommand._(
      mutationId: mutationId.toLowerCase(),
      targetRank: targetRank,
    );
  }

  const CareerPromotionCommand._({
    required this.mutationId,
    required this.targetRank,
  });

  final String mutationId;
  final CareerRank targetRank;
}

@immutable
final class CareerPromotionReceipt {
  const CareerPromotionReceipt({
    required this.mutationId,
    required this.fromRank,
    required this.toRank,
    required this.careerRevision,
    required this.trimsAwarded,
    required this.promotedAt,
  });

  final String mutationId;
  final CareerRank fromRank;
  final CareerRank toRank;
  final int careerRevision;
  final int trimsAwarded;
  final DateTime promotedAt;
}

/// Returns the server-authored promotion mission only when the mission board
/// and Career summary independently agree that the next rank can be claimed.
///
/// The client never infers mission completion from Trims. A completed
/// promotion mission is the server evidence, while [promotionRequired] and a
/// zero [CareerNextRank.trimsRemaining] prove that the rank threshold has also
/// been reached.
CareerMission? eligibleCareerPromotion({
  required CareerSummary summary,
  required CareerMissionBoard board,
}) {
  final next = summary.nextRank;
  if (next == null ||
      !next.promotionRequired ||
      next.trimsRemaining != 0 ||
      board.revision != summary.revision ||
      board.currentRank != summary.rank.id) {
    return null;
  }
  final matches = board.missions.where(
    (mission) =>
        mission.kind == CareerMissionKind.promotion &&
        mission.chapterRank == summary.rank.id &&
        mission.promotesToRank == next.id &&
        mission.status == CareerMissionStatus.complete,
  );
  return matches.length == 1 ? matches.single : null;
}

abstract interface class CareerRepository {
  Future<CareerSummary> getSummary();
  Future<CareerDayContext> getDayContext();
  Future<CareerDayContextReceipt> putDayContext(CareerDayContextWrite write);
  Future<CareerMissionBoard> getMissions();
  Future<CareerTradeReasonReceipt> saveTradeReason(CareerTradeReason reason);
  Future<CareerPromotionReceipt> promote(CareerPromotionCommand command);
}

bool _uuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

bool _careerTimeZone(String value) {
  if (value == 'UTC') return true;
  if (value.isEmpty || value.length > 255 || value != value.trim()) {
    return false;
  }
  final segments = value.split('/');
  if (segments.length < 2) return false;
  return segments.every(
    (segment) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$').hasMatch(segment),
  );
}
