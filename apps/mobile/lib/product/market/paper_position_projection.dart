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
  final costBasisMicros = _micros(position.costBasisPaper);
  return MarketPosition(
    shares: position.quantity,
    exactValuePaper: priced ? valuation!.marketValuePaper : null,
    exactAverageCostPaper: position.averageCostPaper,
    valuePaper: priced ? _wholePaper(valuation!.marketValuePaper!) : null,
    averageCostPaper: _averageWholePaper(
      costBasisMicros,
      _micros(position.quantity),
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
              _micros(receipt.positionCostBasisPaper) *
                  BigInt.from(1000000) ~/
                  _micros(receipt.positionShares),
            ),
      valuePaper: null,
      averageCostPaper: _averageWholePaper(
        _micros(receipt.positionCostBasisPaper),
        _micros(receipt.positionShares),
      ),
      gainPercent: null,
    );

int _wholePaper(String value) {
  final micros = _micros(value);
  return ((micros + BigInt.from(500000)) ~/ BigInt.from(1000000)).toInt();
}

int _averageWholePaper(BigInt costBasisMicros, BigInt quantityMicros) {
  if (quantityMicros == BigInt.zero) return 0;
  return ((costBasisMicros + quantityMicros ~/ BigInt.two) ~/ quantityMicros)
      .toInt();
}

double? _gainPercent(BigInt costBasisMicros, String gain) {
  if (costBasisMicros == BigInt.zero) return null;
  return _signedMicros(gain).toDouble() / costBasisMicros.toDouble() * 100;
}

BigInt _micros(String value) {
  final parts = value.split('.');
  return BigInt.parse(parts.first) * BigInt.from(1000000) +
      BigInt.parse(
        (parts.length == 1 ? '' : parts[1]).padRight(6, '0').padLeft(1, '0'),
      );
}

BigInt _signedMicros(String value) {
  final negative = value.startsWith('-');
  final parsed = _micros(negative ? value.substring(1) : value);
  return negative ? -parsed : parsed;
}
