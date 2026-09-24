import 'package:flutter/foundation.dart';

@immutable
class DeskHolding {
  const DeskHolding({
    required this.assetId,
    required this.variantMint,
    required this.name,
    required this.symbol,
    required this.quantity,
    required this.valuePaper,
    required this.changePercent,
    this.logoUrl,
    this.lastBoughtAt,
  });

  final String assetId, variantMint, name, symbol, quantity;
  final String? valuePaper, logoUrl;
  final DateTime? lastBoughtAt;
  final double? changePercent;
}

enum DeskPaperValueState { complete, partial, unavailable }

@immutable
class DeskSnapshot {
  const DeskSnapshot({
    required this.handle,
    required this.paperValue,
    required this.wallStreetLine,
    this.rank,
    this.streak,
    this.trims,
    this.paperChange,
    this.paperChangePercent,
    this.salMessage,
    this.mission,
    this.missionProgress,
    this.paperValueState = DeskPaperValueState.complete,
    this.holdings = const [],
    this.chart = const [],
  });

  factory DeskSnapshot.newRookie({
    required String handle,
    String wallStreetLine = 'Stocks trade here 24/7. Wall Street opens later.',
    String? rank,
    int? streak,
    int? trims,
  }) => DeskSnapshot(
    handle: handle,
    paperValue: '10,000',
    wallStreetLine: wallStreetLine,
    rank: rank,
    streak: streak,
    trims: trims,
  );

  final String handle, paperValue, wallStreetLine;
  final String? rank, paperChange, salMessage, mission;
  final int? streak, trims;
  final double? paperChangePercent, missionProgress;
  final DeskPaperValueState paperValueState;
  bool get paperValueIsComplete =>
      paperValueState == DeskPaperValueState.complete;
  final List<DeskHolding> holdings;
  final List<double> chart;
}
