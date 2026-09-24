import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/desk/desk_models.dart';
import 'package:trimmy/product/desk/desk_portfolio_projection.dart';
import 'package:trimmy/product/market/market.dart';

const _mintA = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const _mintB = 'So11111111111111111111111111111111111111112';

void main() {
  test('complete valuation produces the only Desk total', () {
    final projection = projectDeskPortfolio(
      portfolio: _portfolio(),
      pendingReceipt: null,
      now: DateTime.utc(2026, 9, 20, 12, 0, 30),
      assetName: (_) => 'Apple',
    );

    expect(projection.valueState, DeskPaperValueState.complete);
    expect(projection.paperValue, '9,650');
    expect(projection.holdings.map((holding) => holding.valuePaper), [
      '150',
      '500',
    ]);
  });

  test(
    'pending receipt replaces only its exact mint and is not double counted',
    () {
      final projection = projectDeskPortfolio(
        portfolio: _portfolio(),
        pendingReceipt: _receipt(),
        now: DateTime.utc(2026, 9, 20, 12, 0, 30),
        assetName: (_) => 'Apple',
      );

      expect(projection.valueState, DeskPaperValueState.partial);
      expect(projection.paperValue, '9,250');
      expect(projection.holdings, hasLength(2));
      expect(
        projection.holdings
            .singleWhere((holding) => holding.variantMint == _mintA)
            .valuePaper,
        isNull,
      );
      expect(
        projection.holdings
            .singleWhere((holding) => holding.variantMint == _mintB)
            .valuePaper,
        '500',
      );
    },
  );

  test('expired marks retain holdings but expose cash only', () {
    final projection = projectDeskPortfolio(
      portfolio: _portfolio(),
      pendingReceipt: null,
      now: DateTime.utc(2026, 9, 20, 12, 1),
      assetName: (_) => null,
    );

    expect(projection.valueState, DeskPaperValueState.unavailable);
    expect(projection.paperValue, '9,000');
    expect(
      projection.holdings.every((holding) => holding.valuePaper == null),
      isTrue,
    );
  });
}

PaperPortfolioSnapshot _portfolio() {
  final positions = [
    _position(mint: _mintA, symbol: 'AAPLx', quantity: '1', cost: '100'),
    _position(mint: _mintB, symbol: 'AAPLon', quantity: '2', cost: '400'),
  ];
  final acceptedAt = DateTime.utc(2026, 9, 20, 12);
  final expiresAt = DateTime.utc(2026, 9, 20, 12, 1);
  final valuation = PaperPortfolioValuation(
    sourceIncluded: true,
    status: PaperPortfolioValuationStatus.complete,
    portfolioRevision: 1,
    openPositionCount: 2,
    pricedPositionCount: 2,
    cashPaper: '9000',
    knownValuePaper: '9650',
    totalPaper: '9650',
    positions: [
      PaperPositionValuation.priced(
        key: const PaperPositionKey(assetId: 'apple', variantMint: _mintA),
        pricePaper: '150',
        marketValuePaper: '150',
        unrealizedGainPaper: '50',
        observedAt: acceptedAt,
        acceptedAt: acceptedAt,
        expiresAt: expiresAt,
      ),
      PaperPositionValuation.priced(
        key: const PaperPositionKey(assetId: 'apple', variantMint: _mintB),
        pricePaper: '250',
        marketValuePaper: '500',
        unrealizedGainPaper: '100',
        observedAt: acceptedAt,
        acceptedAt: acceptedAt,
        expiresAt: expiresAt,
      ),
    ],
  );
  return PaperPortfolioSnapshot(
    revision: 1,
    startingCashPaper: '10000',
    cashPaper: '9000',
    positions: positions,
    recentOrders: const [],
    valuation: valuation,
    openedAt: acceptedAt,
    updatedAt: acceptedAt,
  );
}

PaperPortfolioPosition _position({
  required String mint,
  required String symbol,
  required String quantity,
  required String cost,
}) => PaperPortfolioPosition(
  assetId: 'apple',
  variantMint: mint,
  symbol: symbol,
  quantity: quantity,
  costBasisPaper: cost,
  averageCostPaper: '100',
  realizedGainPaper: '0',
  lockedGainPaper: '0',
  updatedAt: DateTime.utc(2026, 9, 20, 12),
);

PaperOrderReceipt _receipt() => PaperOrderReceipt(
  orderId: '44444444-4444-4444-8444-444444444444',
  accountRevision: 2,
  assetId: 'apple',
  variantMint: _mintA,
  symbol: 'AAPLx',
  side: PaperOrderSide.buy,
  filledShares: '0.5',
  filledPaper: '250',
  cashAfterPaper: '8750',
  positionShares: '1.5',
  positionCostBasisPaper: '350',
  positionValuePaper: '375',
  trimsEarned: 0,
  confirmedAt: DateTime.utc(2026, 9, 20, 12, 0, 20),
);
