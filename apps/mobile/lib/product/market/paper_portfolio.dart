import 'package:flutter/foundation.dart';

import 'paper_order_repository.dart';

@immutable
final class PaperPositionKey {
  const PaperPositionKey({required this.assetId, required this.variantMint});

  final String assetId;
  final String variantMint;

  @override
  bool operator ==(Object other) =>
      other is PaperPositionKey &&
      other.assetId == assetId &&
      other.variantMint == variantMint;

  @override
  int get hashCode => Object.hash(assetId, variantMint);
}

enum PaperPositionValuationStatus { priced, unavailable }

@immutable
final class PaperPositionValuation {
  const PaperPositionValuation.priced({
    required this.key,
    required this.pricePaper,
    required this.marketValuePaper,
    required this.unrealizedGainPaper,
    required this.observedAt,
    required this.acceptedAt,
    required this.expiresAt,
  }) : status = PaperPositionValuationStatus.priced;

  const PaperPositionValuation.unavailable({required this.key})
    : status = PaperPositionValuationStatus.unavailable,
      pricePaper = null,
      marketValuePaper = null,
      unrealizedGainPaper = null,
      observedAt = null,
      acceptedAt = null,
      expiresAt = null;

  final PaperPositionKey key;
  final PaperPositionValuationStatus status;
  final String? pricePaper;
  final String? marketValuePaper;
  final String? unrealizedGainPaper;
  final DateTime? observedAt;
  final DateTime? acceptedAt;
  final DateTime? expiresAt;

  bool isCurrentAt(DateTime now) =>
      status == PaperPositionValuationStatus.priced &&
      expiresAt != null &&
      now.toUtc().isBefore(expiresAt!);
}

enum PaperPortfolioValuationStatus { complete, partial, unavailable }

/// Server-valued paper positions. A value is addressable only by the exact
/// asset and issuer mint pair. [currentAt] removes prices at their strict
/// expiry boundary before callers can use an aggregate or position value.
@immutable
final class PaperPortfolioValuation {
  PaperPortfolioValuation({
    required this.sourceIncluded,
    required this.status,
    required this.portfolioRevision,
    required this.openPositionCount,
    required this.pricedPositionCount,
    required this.cashPaper,
    required this.knownValuePaper,
    required this.totalPaper,
    required Iterable<PaperPositionValuation> positions,
  }) : positions = List.unmodifiable(positions),
       _byPosition = Map.unmodifiable({
         for (final position in positions) position.key: position,
       });

  factory PaperPortfolioValuation.notIncluded({
    required int portfolioRevision,
    required String cashPaper,
    required Iterable<PaperPortfolioPosition> openPositions,
  }) {
    final rows = [
      for (final position in openPositions)
        PaperPositionValuation.unavailable(key: position.key),
    ];
    return PaperPortfolioValuation(
      sourceIncluded: false,
      status: rows.isEmpty
          ? PaperPortfolioValuationStatus.complete
          : PaperPortfolioValuationStatus.unavailable,
      portfolioRevision: portfolioRevision,
      openPositionCount: rows.length,
      pricedPositionCount: 0,
      cashPaper: cashPaper,
      knownValuePaper: cashPaper,
      totalPaper: rows.isEmpty ? cashPaper : null,
      positions: rows,
    );
  }

  final bool sourceIncluded;
  final PaperPortfolioValuationStatus status;
  final int portfolioRevision;
  final int openPositionCount;
  final int pricedPositionCount;
  final String cashPaper;
  final String knownValuePaper;
  final String? totalPaper;
  final List<PaperPositionValuation> positions;
  final Map<PaperPositionKey, PaperPositionValuation> _byPosition;

  PaperPositionValuation? positionFor(String assetId, String variantMint) =>
      _byPosition[PaperPositionKey(assetId: assetId, variantMint: variantMint)];

  DateTime? nextExpiryAfter(DateTime now) {
    DateTime? next;
    for (final position in positions) {
      final expiresAt = position.expiresAt;
      if (expiresAt == null || !now.toUtc().isBefore(expiresAt)) continue;
      if (next == null || expiresAt.isBefore(next)) next = expiresAt;
    }
    return next;
  }

  PaperPortfolioValuation currentAt(DateTime now) {
    final currentRows = <PaperPositionValuation>[];
    var priced = 0;
    var knownMicros = _toPaperMicros(cashPaper);
    for (final position in positions) {
      if (position.isCurrentAt(now)) {
        currentRows.add(position);
        priced++;
        knownMicros += _toPaperMicros(position.marketValuePaper!);
      } else {
        currentRows.add(PaperPositionValuation.unavailable(key: position.key));
      }
    }
    final currentStatus = openPositionCount == 0 || priced == openPositionCount
        ? PaperPortfolioValuationStatus.complete
        : priced == 0
        ? PaperPortfolioValuationStatus.unavailable
        : PaperPortfolioValuationStatus.partial;
    final known = _fromPaperMicros(knownMicros);
    return PaperPortfolioValuation(
      sourceIncluded: sourceIncluded,
      status: currentStatus,
      portfolioRevision: portfolioRevision,
      openPositionCount: openPositionCount,
      pricedPositionCount: priced,
      cashPaper: cashPaper,
      knownValuePaper: known,
      totalPaper: currentStatus == PaperPortfolioValuationStatus.complete
          ? known
          : null,
      positions: currentRows,
    );
  }
}

@immutable
final class PaperPortfolioPosition {
  const PaperPortfolioPosition({
    required this.assetId,
    required this.variantMint,
    required this.symbol,
    required this.quantity,
    required this.costBasisPaper,
    required this.averageCostPaper,
    required this.realizedGainPaper,
    required this.lockedGainPaper,
    required this.updatedAt,
  });

  final String assetId;
  final String variantMint;
  final String symbol;
  final String quantity;
  final String costBasisPaper;
  final String averageCostPaper;
  final String realizedGainPaper;
  final String lockedGainPaper;
  final DateTime updatedAt;

  PaperPositionKey get key =>
      PaperPositionKey(assetId: assetId, variantMint: variantMint);
}

@immutable
final class PaperPortfolioOrder {
  const PaperPortfolioOrder({
    required this.orderId,
    required this.assetId,
    required this.variantMint,
    required this.symbol,
    required this.action,
    required this.pricePaper,
    required this.quantity,
    required this.cashAfterPaper,
    required this.committedAt,
  });

  final String orderId;
  final String assetId;
  final String variantMint;
  final String symbol;
  final String action;
  final String pricePaper;
  final String quantity;
  final String cashAfterPaper;
  final DateTime committedAt;
}

/// A server-owned paper desk. Decimal strings preserve ledger precision.
@immutable
final class PaperPortfolioSnapshot {
  PaperPortfolioSnapshot({
    required this.revision,
    required this.startingCashPaper,
    required this.cashPaper,
    required Iterable<PaperPortfolioPosition> positions,
    required Iterable<PaperPortfolioOrder> recentOrders,
    required this.valuation,
    required this.openedAt,
    required this.updatedAt,
  }) : positions = List.unmodifiable(positions),
       recentOrders = List.unmodifiable(recentOrders);

  final int revision;
  final String startingCashPaper;
  final String cashPaper;
  final List<PaperPortfolioPosition> positions;
  final List<PaperPortfolioOrder> recentOrders;
  final PaperPortfolioValuation valuation;
  final DateTime? openedAt;
  final DateTime? updatedAt;

  bool get hasTraded => recentOrders.isNotEmpty || revision > 0;

  PaperPortfolioSnapshot withValuation(PaperPortfolioValuation value) =>
      PaperPortfolioSnapshot(
        revision: revision,
        startingCashPaper: startingCashPaper,
        cashPaper: cashPaper,
        positions: positions,
        recentOrders: recentOrders,
        valuation: value,
        openedAt: openedAt,
        updatedAt: updatedAt,
      );

  PaperPortfolioPosition? positionFor(String assetId, {String? variantMint}) {
    final matches = positions.where(
      (position) =>
          position.assetId == assetId &&
          (variantMint == null || position.variantMint == variantMint),
    );
    if (variantMint != null) return matches.firstOrNull;

    // An asset can have several tokenized issuers. Without the mint, returning
    // one arbitrarily could show or sell the wrong position.
    final iterator = matches.iterator;
    if (!iterator.moveNext()) return null;
    final only = iterator.current;
    return iterator.moveNext() ? null : only;
  }

  PaperPortfolioOrder? latestOrderFor(String assetId) {
    for (final order in recentOrders) {
      if (order.assetId == assetId) return order;
    }
    return null;
  }
}

@immutable
final class PaperPortfolioBinding {
  const PaperPortfolioBinding._(this.principalKey, this.generation);

  final String principalKey;
  final int generation;
}

/// Keeps cached reads, network reads, and pending order receipts bound to the
/// principal that created them. A temporary suspension invalidates delayed
/// callbacks while retaining state for a claim that resolves to the same UUID.
final class PaperPortfolioSession {
  int _generation = 0;
  String? _principalKey;
  PaperPortfolioSnapshot? _snapshot;
  PaperOrderReceipt? _pendingReceipt;
  final Set<String> _acceptedOrderIds = <String>{};

  String? get principalKey => _principalKey;
  PaperPortfolioSnapshot? get snapshot => _snapshot;
  PaperOrderReceipt? get pendingReceipt => _pendingReceipt;

  PaperPortfolioBinding bind(String principalKey) {
    if (principalKey.isEmpty) throw ArgumentError.value(principalKey);
    _generation++;
    if (_principalKey != principalKey) {
      _snapshot = null;
      _pendingReceipt = null;
      _acceptedOrderIds.clear();
    }
    _principalKey = principalKey;
    return PaperPortfolioBinding._(principalKey, _generation);
  }

  /// Invalidates in-flight work without discarding same-principal state.
  void suspend() {
    _generation++;
  }

  void unbind() {
    _generation++;
    _principalKey = null;
    _snapshot = null;
    _pendingReceipt = null;
    _acceptedOrderIds.clear();
  }

  bool isCurrent(PaperPortfolioBinding? binding) =>
      binding != null &&
      binding.generation == _generation &&
      binding.principalKey == _principalKey;

  bool acceptSnapshot(
    PaperPortfolioBinding? binding,
    PaperPortfolioSnapshot snapshot,
  ) {
    if (!isCurrent(binding)) return false;
    final current = _snapshot;
    if (current != null && snapshot.revision < current.revision) return false;
    _snapshot = snapshot;
    final pending = _pendingReceipt;
    if (pending != null && snapshot.revision >= pending.accountRevision) {
      _pendingReceipt = null;
    }
    return true;
  }

  bool acceptReceipt(
    PaperPortfolioBinding? binding,
    PaperOrderReceipt receipt,
  ) {
    if (!isCurrent(binding) || _acceptedOrderIds.contains(receipt.orderId)) {
      return false;
    }
    final snapshot = _snapshot;
    if (snapshot != null && snapshot.revision >= receipt.accountRevision) {
      _acceptedOrderIds.add(receipt.orderId);
      return false;
    }
    final pending = _pendingReceipt;
    if (pending != null && receipt.accountRevision <= pending.accountRevision) {
      _acceptedOrderIds.add(receipt.orderId);
      return false;
    }
    _acceptedOrderIds.add(receipt.orderId);
    _pendingReceipt = receipt;
    return true;
  }

  /// Replaces the current cycle with the server-confirmed cash-only reset
  /// snapshot. Older reads and order receipts cannot repopulate the old cycle.
  bool acceptResetSnapshot(
    PaperPortfolioBinding? binding,
    PaperPortfolioSnapshot snapshot, {
    required int previousRevision,
  }) {
    if (!isCurrent(binding) ||
        snapshot.revision != previousRevision + 1 ||
        snapshot.startingCashPaper != snapshot.cashPaper ||
        snapshot.positions.isNotEmpty ||
        snapshot.recentOrders.isNotEmpty) {
      return false;
    }
    final current = _snapshot;
    if (current != null && snapshot.revision < current.revision) return false;
    _snapshot = snapshot;
    _pendingReceipt = null;
    _acceptedOrderIds.clear();
    return true;
  }
}

abstract interface class PaperPortfolioRepository {
  Future<PaperPortfolioSnapshot> read();
}

BigInt _toPaperMicros(String value) {
  final negative = value.startsWith('-');
  final absolute = negative ? value.substring(1) : value;
  final parts = absolute.split('.');
  final micros =
      BigInt.parse(parts[0]) * BigInt.from(1000000) +
      BigInt.parse(
        (parts.length == 1 ? '' : parts[1]).padRight(6, '0').padLeft(1, '0'),
      );
  return negative ? -micros : micros;
}

String _fromPaperMicros(BigInt value) {
  final negative = value.isNegative;
  final absolute = value.abs();
  final whole = absolute ~/ BigInt.from(1000000);
  final fraction = (absolute % BigInt.from(1000000))
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
}
