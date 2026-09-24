import '../market/paper_order_repository.dart';
import '../market/paper_portfolio.dart';
import 'desk_models.dart';

typedef DeskAssetName = String? Function(String assetId);

final class DeskPortfolioProjection {
  const DeskPortfolioProjection({
    required this.paperValue,
    required this.valueState,
    required this.holdings,
  });

  final String paperValue;
  final DeskPaperValueState valueState;
  final List<DeskHolding> holdings;
}

/// Projects only server-confirmed, unexpired values into the Desk. Discovery
/// prices are deliberately absent from this interface.
DeskPortfolioProjection projectDeskPortfolio({
  required PaperPortfolioSnapshot? portfolio,
  required PaperOrderReceipt? pendingReceipt,
  required DateTime now,
  required DeskAssetName assetName,
  DeskAssetName? assetLogo,
}) {
  final valuation = portfolio?.valuation.currentAt(now.toUtc());
  final holdings = <DeskHolding>[
    for (final position in portfolio?.positions ?? const [])
      if (_positive(position.quantity))
        _holding(
          position,
          valuation?.positionFor(position.assetId, position.variantMint),
          assetName,
          assetLogo,
          _lastBuy(portfolio, position),
        ),
  ];
  if (pendingReceipt != null) {
    holdings.removeWhere(
      (holding) =>
          holding.assetId == pendingReceipt.assetId &&
          holding.variantMint == pendingReceipt.variantMint,
    );
    if (_positive(pendingReceipt.positionShares)) {
      holdings.add(
        DeskHolding(
          assetId: pendingReceipt.assetId,
          variantMint: pendingReceipt.variantMint,
          name: assetName(pendingReceipt.assetId) ?? pendingReceipt.assetId,
          symbol: pendingReceipt.symbol,
          logoUrl: assetLogo?.call(pendingReceipt.assetId),
          lastBoughtAt: now,
          quantity: pendingReceipt.positionShares,
          valuePaper: null,
          changePercent: null,
        ),
      );
    }
  }
  holdings.sort(
    (a, b) => (b.lastBoughtAt ?? DateTime(1970)).compareTo(
      a.lastBoughtAt ?? DateTime(1970),
    ),
  );
  final pricedCount = holdings
      .where((holding) => holding.valuePaper != null)
      .length;
  final valueState = holdings.isEmpty || pricedCount == holdings.length
      ? DeskPaperValueState.complete
      : pricedCount == 0
      ? DeskPaperValueState.unavailable
      : DeskPaperValueState.partial;
  final cash =
      pendingReceipt?.cashAfterPaper ?? portfolio?.cashPaper ?? '10000';
  return DeskPortfolioProjection(
    paperValue: _sumPaperValues([
      cash,
      for (final holding in holdings) ?holding.valuePaper,
    ]),
    valueState: valueState,
    holdings: List.unmodifiable(holdings),
  );
}

DeskHolding _holding(
  PaperPortfolioPosition position,
  PaperPositionValuation? valuation,
  DeskAssetName assetName,
  DeskAssetName? assetLogo,
  DateTime? lastBoughtAt,
) {
  final priced = valuation?.status == PaperPositionValuationStatus.priced;
  return DeskHolding(
    assetId: position.assetId,
    variantMint: position.variantMint,
    name: assetName(position.assetId) ?? position.symbol,
    symbol: position.symbol,
    logoUrl: assetLogo?.call(position.assetId),
    lastBoughtAt: lastBoughtAt,
    quantity: position.quantity,
    valuePaper: priced ? valuation!.marketValuePaper : null,
    changePercent: priced ? _gainPercent(position, valuation!) : null,
  );
}

double? _gainPercent(
  PaperPortfolioPosition position,
  PaperPositionValuation valuation,
) {
  final costBasis = double.tryParse(position.costBasisPaper);
  final gain = double.tryParse(valuation.unrealizedGainPaper ?? '');
  if (costBasis == null || costBasis <= 0 || gain == null) return null;
  return gain / costBasis * 100;
}

bool _positive(String value) =>
    (_paperMicros(value) ?? BigInt.zero) > BigInt.zero;

String _sumPaperValues(Iterable<String> values) {
  var total = BigInt.zero;
  for (final value in values) {
    final parsed = _paperMicros(value);
    if (parsed != null) total += parsed;
  }
  return _paperFromMicros(total);
}

BigInt? _paperMicros(String value) {
  if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,6})?$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('.');
  final fraction = (parts.length == 2 ? parts[1] : '').padRight(6, '0');
  return BigInt.parse(parts.first) * BigInt.from(1000000) +
      BigInt.parse(fraction.isEmpty ? '0' : fraction);
}

String _paperFromMicros(BigInt value) {
  final whole = value ~/ BigInt.from(1000000);
  final remainder = (value % BigInt.from(1000000))
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  final digits = whole.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$digits${remainder.isEmpty ? '' : '.$remainder'}';
}

DateTime? _lastBuy(
  PaperPortfolioSnapshot? portfolio,
  PaperPortfolioPosition position,
) {
  DateTime? latest;
  for (final order in portfolio?.recentOrders ?? <PaperPortfolioOrder>[]) {
    if (order.action == 'buy' &&
        order.assetId == position.assetId &&
        order.variantMint == position.variantMint &&
        (latest == null || order.committedAt.isAfter(latest))) {
      latest = order.committedAt;
    }
  }
  return latest ?? position.updatedAt;
}
