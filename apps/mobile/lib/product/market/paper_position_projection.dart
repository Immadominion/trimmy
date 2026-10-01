import '../../core/paper_decimal.dart';
import 'market_models.dart';
import 'paper_order_repository.dart';
import 'paper_portfolio.dart';
import 'order_amount_math.dart';

MarketPosition confirmedMarketPosition({
  required PaperPortfolioSnapshot portfolio,
  required PaperPortfolioPosition position,
  required DateTime now,
}) {
  final valuation = portfolio.valuation
      .currentAt(now.toUtc())
      .positionFor(position.assetId, position.variantMint);
  final priced = valuation?.status == PaperPositionValuationStatus.priced;
  final costBasisMicros = paperMicros(position.costBasisPaper);
  return MarketPosition(
    shares: position.quantity,
    exactValuePaper: priced ? valuation!.marketValuePaper : null,
    exactAverageCostPaper: position.averageCostPaper,
    valuePaper: priced ? _wholePaper(valuation!.marketValuePaper!) : null,
    averageCostPaper: _averageWholePaper(
      costBasisMicros,
      paperMicros(position.quantity),
    ),
    gainPercent: priced
        ? _gainPercent(costBasisMicros, valuation!.unrealizedGainPaper!)
        : null,
  );
}

MarketPosition pendingMarketPosition(PaperOrderReceipt receipt) =>
    MarketPosition(
      shares: receipt.positionShares,
      exactAverageCostPaper: receipt.positionShares == '0'
          ? '0'
          : OrderAmountMath.decimal(
              paperMicros(receipt.positionCostBasisPaper) *
                  BigInt.from(1000000) ~/
                  paperMicros(receipt.positionShares),
            ),
      valuePaper: null,
      averageCostPaper: _averageWholePaper(
        paperMicros(receipt.positionCostBasisPaper),
        paperMicros(receipt.positionShares),
      ),
      gainPercent: null,
    );

int _wholePaper(String value) {
  final micros = paperMicros(value);
  return ((micros + BigInt.from(500000)) ~/ BigInt.from(1000000)).toInt();
}

int _averageWholePaper(BigInt costBasisMicros, BigInt quantityMicros) {
  if (quantityMicros == BigInt.zero) return 0;
  return ((costBasisMicros + quantityMicros ~/ BigInt.two) ~/ quantityMicros)
      .toInt();
}

double? _gainPercent(BigInt costBasisMicros, String gain) {
  if (costBasisMicros == BigInt.zero) return null;
  return paperMicros(gain).toDouble() / costBasisMicros.toDouble() * 100;
}
