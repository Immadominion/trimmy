import 'package:flutter/foundation.dart';

import '../career/career_repository.dart';

enum PaperOrderSide { buy, sell }

enum PaperQuantityUnit { paper, shares }

enum PaperOrderFailure {
  invalidAmount,
  insufficientPaper,
  insufficientShares,
  quoteExpired,
  priceChanged,
  unavailable,
  offline,
  timeout,
  rejected,
  accountRequired,
  duplicate,
}

final class PaperOrderException implements Exception {
  const PaperOrderException(this.failure);
  final PaperOrderFailure failure;

  @override
  String toString() => 'PaperOrderException(${failure.name})';
}

bool _safeId(String value) =>
    value.isNotEmpty &&
    value.length <= 160 &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]*$').hasMatch(value);

bool _decimal(String value, {required int decimals}) {
  if (value.isEmpty || value.length > 30) return false;
  final expression = decimals == 0
      ? r'^(?:0|[1-9][0-9]*)$'
      : '^(?:0|[1-9][0-9]*)(?:\\.[0-9]{1,$decimals})?\$';
  if (!RegExp(expression).hasMatch(value)) return false;
  final parsed = num.tryParse(value);
  return parsed != null && parsed.isFinite && parsed > 0;
}

@immutable
final class PaperOrderIntent {
  factory PaperOrderIntent({
    required String assetId,
    required String variantMint,
    required PaperOrderSide side,
    required PaperQuantityUnit quantityUnit,
    required String quantity,
  }) {
    if (!_safeId(assetId) ||
        variantMint.length < 32 ||
        variantMint.length > 44 ||
        !_decimal(
          quantity,
          decimals: quantityUnit == PaperQuantityUnit.paper ? 2 : 6,
        )) {
      throw const PaperOrderException(PaperOrderFailure.invalidAmount);
    }
    return PaperOrderIntent._(
      assetId: assetId,
      variantMint: variantMint,
      side: side,
      quantityUnit: quantityUnit,
      quantity: quantity,
    );
  }

  const PaperOrderIntent._({
    required this.assetId,
    required this.variantMint,
    required this.side,
    required this.quantityUnit,
    required this.quantity,
  });

  final String assetId;
  final String variantMint;
  final PaperOrderSide side;
  final PaperQuantityUnit quantityUnit;
  final String quantity;

  @override
  bool operator ==(Object other) =>
      other is PaperOrderIntent &&
      other.assetId == assetId &&
      other.variantMint == variantMint &&
      other.side == side &&
      other.quantityUnit == quantityUnit &&
      other.quantity == quantity;

  @override
  int get hashCode =>
      Object.hash(assetId, variantMint, side, quantityUnit, quantity);
}

@immutable
final class PaperOrderQuote {
  factory PaperOrderQuote({
    required String quoteId,
    required PaperOrderIntent intent,
    required String unitPricePaper,
    required String estimatedShares,
    required String feePaper,
    required String totalPaper,
    required DateTime expiresAt,
  }) {
    if (!_safeId(quoteId) ||
        !_decimal(unitPricePaper, decimals: 6) ||
        !_decimal(estimatedShares, decimals: 6) ||
        !_nonNegativeDecimal(feePaper, decimals: 6) ||
        !_decimal(totalPaper, decimals: 6) ||
        !expiresAt.isUtc) {
      throw const PaperOrderException(PaperOrderFailure.rejected);
    }
    return PaperOrderQuote._(
      quoteId: quoteId,
      intent: intent,
      unitPricePaper: unitPricePaper,
      estimatedShares: estimatedShares,
      feePaper: feePaper,
      totalPaper: totalPaper,
      expiresAt: expiresAt,
    );
  }

  const PaperOrderQuote._({
    required this.quoteId,
    required this.intent,
    required this.unitPricePaper,
    required this.estimatedShares,
    required this.feePaper,
    required this.totalPaper,
    required this.expiresAt,
  });

  final String quoteId;
  final PaperOrderIntent intent;
  final String unitPricePaper;
  final String estimatedShares;
  final String feePaper;
  final String totalPaper;
  final DateTime expiresAt;
}

bool _nonNegativeDecimal(String value, {required int decimals}) {
  if (value.isEmpty || value.length > 30) return false;
  final expression = '^(?:0|[1-9][0-9]*)(?:\\.[0-9]{1,$decimals})?\$';
  if (!RegExp(expression).hasMatch(value)) return false;
  final parsed = num.tryParse(value);
  return parsed != null && parsed.isFinite && parsed >= 0;
}

@immutable
final class PaperOrderSubmission {
  factory PaperOrderSubmission({
    required String quoteId,
    required String clientOrderId,
  }) {
    if (!_safeId(quoteId) || !_safeId(clientOrderId)) {
      throw const PaperOrderException(PaperOrderFailure.rejected);
    }
    return PaperOrderSubmission._(
      quoteId: quoteId,
      clientOrderId: clientOrderId,
    );
  }

  const PaperOrderSubmission._({
    required this.quoteId,
    required this.clientOrderId,
  });

  final String quoteId;
  final String clientOrderId;
}

@immutable
final class PaperOrderReceipt {
  factory PaperOrderReceipt({
    required String orderId,
    required int accountRevision,
    required String assetId,
    required String variantMint,
    required String symbol,
    required PaperOrderSide side,
    required String filledShares,
    required String filledPaper,
    required String cashAfterPaper,
    required String positionShares,
    required String positionCostBasisPaper,
    required String positionValuePaper,
    required int trimsEarned,
    required DateTime confirmedAt,
    String? unitPricePaper,
    String? missionProgress,
  }) {
    if (!_safeId(orderId) ||
        accountRevision < 1 ||
        accountRevision > 9007199254740991 ||
        !_safeId(assetId) ||
        !RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(variantMint) ||
        symbol.isEmpty ||
        symbol.length > 30 ||
        symbol.trim() != symbol ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(symbol) ||
        !_decimal(filledShares, decimals: 6) ||
        !_decimal(filledPaper, decimals: 6) ||
        (unitPricePaper != null && !_decimal(unitPricePaper, decimals: 6)) ||
        !_nonNegativeDecimal(cashAfterPaper, decimals: 6) ||
        !_nonNegativeDecimal(positionShares, decimals: 6) ||
        !_nonNegativeDecimal(positionCostBasisPaper, decimals: 6) ||
        !_nonNegativeDecimal(positionValuePaper, decimals: 6) ||
        trimsEarned < 0 ||
        trimsEarned > 100000 ||
        !confirmedAt.isUtc ||
        (missionProgress != null &&
            (missionProgress.trim() != missionProgress ||
                missionProgress.isEmpty ||
                missionProgress.length > 120))) {
      throw const PaperOrderException(PaperOrderFailure.rejected);
    }
    return PaperOrderReceipt._(
      orderId: orderId,
      accountRevision: accountRevision,
      assetId: assetId,
      variantMint: variantMint,
      symbol: symbol,
      side: side,
      filledShares: filledShares,
      filledPaper: filledPaper,
      cashAfterPaper: cashAfterPaper,
      positionShares: positionShares,
      positionCostBasisPaper: positionCostBasisPaper,
      positionValuePaper: positionValuePaper,
      trimsEarned: trimsEarned,
      confirmedAt: confirmedAt,
      unitPricePaper: unitPricePaper,
      missionProgress: missionProgress,
    );
  }

  const PaperOrderReceipt._({
    required this.orderId,
    required this.accountRevision,
    required this.assetId,
    required this.variantMint,
    required this.symbol,
    required this.side,
    required this.filledShares,
    required this.filledPaper,
    required this.cashAfterPaper,
    required this.positionShares,
    required this.positionCostBasisPaper,
    required this.positionValuePaper,
    required this.trimsEarned,
    required this.confirmedAt,
    required this.unitPricePaper,
    required this.missionProgress,
  });

  final String orderId;
  final int accountRevision;
  final String assetId;
  final String variantMint;
  final String symbol;
  final PaperOrderSide side;
  final String filledShares;
  final String filledPaper;
  final String cashAfterPaper;
  final String positionShares;
  final String positionCostBasisPaper;
  final String positionValuePaper;
  final int trimsEarned;
  final DateTime confirmedAt;
  final String? unitPricePaper;
  final String? missionProgress;
}

typedef PaperOrderReason = CareerTradeReason;
typedef PaperReasonReceipt = CareerTradeReasonReceipt;

/// The mobile UI cannot mint a successful trade. A server-backed
/// implementation must return a quote, then a durable receipt. Only that
/// receipt unlocks the report screen.
abstract interface class PaperOrderRepository {
  Future<PaperOrderQuote> quote(PaperOrderIntent intent);
  Future<PaperOrderReceipt> submit(PaperOrderSubmission submission);
  Future<PaperReasonReceipt> saveReason(PaperOrderReason reason);
}
