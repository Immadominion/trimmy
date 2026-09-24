import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/market.dart';

import 'market_test_support.dart';

const _mint = 'So11111111111111111111111111111111111111112';

void main() {
  test('a different primary discovery price cannot affect the holding', () {
    final discovery = testCompany(price: 9999);
    final portfolio = _portfolio();

    expect(discovery.primaryVariant?.mint, isNot(_mint));
    expect(discovery.priceUsd, 9999);

    final position = confirmedMarketPosition(
      portfolio: portfolio,
      position: portfolio.positions.single,
      now: DateTime.utc(2026, 9, 20, 12, 0, 30),
    );

    expect(position.valuePaper, 500);
    expect(position.averageCostPaper, 200);
    expect(position.gainPercent, 25);
  });

  test('expired server valuation cannot become a current holding value', () {
    final portfolio = _portfolio();

    final position = confirmedMarketPosition(
      portfolio: portfolio,
      position: portfolio.positions.single,
      now: DateTime.utc(2026, 9, 20, 12, 1),
    );

    expect(position.valuePaper, isNull);
    expect(position.gainPercent, isNull);
  });

  test('pending receipt does not claim a current position value', () {
    final position = pendingMarketPosition(_receipt());

    expect(position.shares, '1.5');
    expect(position.valuePaper, isNull);
    expect(position.averageCostPaper, 233);
    expect(position.gainPercent, isNull);
  });
}

PaperPortfolioSnapshot _portfolio() {
  final position = PaperPortfolioPosition(
    assetId: 'apple',
    variantMint: _mint,
    symbol: 'AAPLon',
    quantity: '2',
    costBasisPaper: '400',
    averageCostPaper: '200',
    realizedGainPaper: '0',
    lockedGainPaper: '0',
    updatedAt: DateTime.utc(2026, 9, 20, 12),
  );
  final acceptedAt = DateTime.utc(2026, 9, 20, 12);
  return PaperPortfolioSnapshot(
    revision: 1,
    startingCashPaper: '10000',
    cashPaper: '9000',
    positions: [position],
    recentOrders: const [],
    valuation: PaperPortfolioValuation(
      sourceIncluded: true,
      status: PaperPortfolioValuationStatus.complete,
      portfolioRevision: 1,
      openPositionCount: 1,
      pricedPositionCount: 1,
      cashPaper: '9000',
      knownValuePaper: '9500',
      totalPaper: '9500',
      positions: [
        PaperPositionValuation.priced(
          key: const PaperPositionKey(assetId: 'apple', variantMint: _mint),
          pricePaper: '250',
          marketValuePaper: '500',
          unrealizedGainPaper: '100',
          observedAt: acceptedAt,
          acceptedAt: acceptedAt,
          expiresAt: DateTime.utc(2026, 9, 20, 12, 1),
        ),
      ],
    ),
    openedAt: acceptedAt,
    updatedAt: acceptedAt,
  );
}

PaperOrderReceipt _receipt() => PaperOrderReceipt(
  orderId: '44444444-4444-4444-8444-444444444444',
  accountRevision: 2,
  assetId: 'apple',
  variantMint: _mint,
  symbol: 'AAPLon',
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
