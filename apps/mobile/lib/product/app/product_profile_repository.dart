import 'package:flutter/foundation.dart';

import '../onboarding/onboarding_models.dart';

enum ProductProfileCheckpoint {
  firstTrade('first-trade'),
  firstPosition('first-position'),
  streak('streak'),
  saveDesk('save-desk'),
  app('app');

  const ProductProfileCheckpoint(this.wire);
  final String wire;
}

enum ProductLaunchAction {
  paperTradeConfirmed('paper-trade-confirmed'),
  firstPositionCollected('first-position-collected'),
  dayOneSeen('day-one-seen'),
  saveDeskLater('save-desk-later'),
  saveDeskSaved('save-desk-saved'),
  introductionSkipped('introduction-skipped'),
  introductionCompleted('introduction-completed');

  const ProductLaunchAction(this.wire);
  final String wire;
}

enum ProductProfileFailure {
  unavailable,
  offline,
  timeout,
  unauthenticated,
  conflict,
  handleTaken,
  tradeRequired,
  notReady,
  principalChanged,
  rejected,
}

final class ProductProfileException implements Exception {
  const ProductProfileException(this.failure, {this.currentProfile});

  final ProductProfileFailure failure;
  final ProductProfileSnapshot? currentProfile;

  @override
  String toString() => 'ProductProfileException(${failure.name})';
}

@immutable
final class ProductProfileSnapshot {
  const ProductProfileSnapshot({
    required this.revision,
    required this.onboarding,
    required this.launchCheckpoint,
    required this.createdAt,
    required this.updatedAt,
    this.hasConfirmedPaperTrade,
  });

  final int revision;
  final OnboardingProfile onboarding;
  final ProductProfileCheckpoint launchCheckpoint;
  final DateTime createdAt, updatedAt;

  /// Server-confirmed order evidence. Null is reserved for legacy snapshots.
  /// Reaching the app via Skip is never evidence that a trade happened.
  final bool? hasConfirmedPaperTrade;
}

abstract interface class ProductProfileRepository {
  Future<ProductProfileSnapshot?> read();

  Future<ProductProfileSnapshot> write({
    required String mutationId,
    required int baseRevision,
    required OnboardingProfile onboarding,
    required ProductProfileCheckpoint launchCheckpoint,
  });

  Future<ProductProfileSnapshot> advance({
    required String mutationId,
    required int baseRevision,
    required ProductLaunchAction action,
  });
}
