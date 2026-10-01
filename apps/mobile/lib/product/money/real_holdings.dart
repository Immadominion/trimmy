import 'package:flutter/material.dart';
import '../../core/paper_decimal.dart';
import '../../account/account_controller.dart';
import '../../account/account_amounts.dart';
import '../../l10n/l10n.dart';
import '../design/product_theme.dart';
import '../desk/holding_tile.dart';
import '../market/live_trading.dart';
import '../../account/account_data_models.dart';

AccountHoldingsSnapshot? realWalletHoldings(AccountController? account) {
  final state = account?.portfolioState;
  final holdings = state?.portfolio?.holdings;
  return holdings != null &&
          holdings.wallet.address ==
              state?.context?.embeddedSolanaWallet.address
      ? holdings
      : null;
}

/// Shares for [mint]: the wallet's own display amount over its raw amount.
/// Without a matching holding, shares are plain token units.
LiveShareScale liveShareScale(
  AccountController? account,
  String mint,
  int decimals,
) {
  final holding = realWalletHoldings(account)?.holdingForMint(mint);
  if (holding == null || holding.decimals != decimals) {
    return LiveShareScale.plain(decimals);
  }
  return LiveShareScale.fromDisplay(
    decimals: decimals,
    amountRaw: holding.amountRaw,
    displayAmount: holding.displayAmount,
  );
}

/// The wallet's SOL, exact, written for [formats]' language (English when
/// left out).
String? realSolBalance(AccountController? account, [AppFormats? formats]) {
  final holdings = realWalletHoldings(account);
  final sol = holdings == null
      ? null
      : formatRawUnits(holdings.nativeSol.amountRaw, 9);
  return sol == null ? null : (formats ?? AppFormats.english).number(sol);
}

/// USD cash is USDC. The card shows SOL separately for fees, without inventing
/// a SOL exchange rate or treating raw stock-token units as verified shares.
String? realCashBalance(AccountController? account, [AppFormats? formats]) {
  final h = realWalletHoldings(account);
  if (h == null) return null;
  final raw = BigInt.tryParse(h.usdc.amountRaw);
  if (raw == null) return null;
  return _dollars(raw ~/ BigInt.from(10000), formats);
}

/// Exact cents as a dollar amount: "$1,234.56" in English, "US$ 1.234,56"
/// or "1 234,56 $US" elsewhere. Only the writing changes, never the cents.
String _dollars(BigInt cents, [AppFormats? formats]) {
  final whole = groupThousands((cents ~/ BigInt.from(100)).toString());
  final figure =
      '$whole.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
  return (formats ?? AppFormats.english).usd(figure);
}

/// What a held token is worth: its shares (the wallet's display amount, which
/// already applies any share multiplier) times that token's trusted price per
/// share (holding_prices.dart). Never raw token units. Display only: a sale is
/// still quoted before signing.
double? realHoldingValue(WalletStockBalance holding, double? price) {
  final shares = holding.displayAmount == null
      ? null
      : double.tryParse(holding.displayAmount!);
  if (price == null || !price.isFinite || price <= 0) return null;
  if (shares == null || !shares.isFinite || shares < 0) return null;
  return shares * price;
}

String realUsd(double value, [AppFormats? formats]) =>
    _dollars(BigInt.from((value * 100).round()), formats);

/// Cash plus every stock's value, once each stock has a price. Until then the
/// card shows cash alone rather than a partial total. Amounts read in
/// [formats]' language (English when left out).
({String total, String cash, String stocks})? realTotalBalance(
  AccountController? account,
  double? Function(WalletStockBalance holding) priceFor, [
  AppFormats? formats,
]) {
  final h = realWalletHoldings(account);
  final cashRaw = h == null ? null : BigInt.tryParse(h.usdc.amountRaw);
  if (h == null || cashRaw == null || h.stockTokens.isEmpty) return null;
  var stocks = 0.0;
  for (final holding in h.stockTokens) {
    final value = realHoldingValue(holding, priceFor(holding));
    if (value == null) return null;
    stocks += value;
  }
  final cash = cashRaw ~/ BigInt.from(10000);
  final stockCents = BigInt.from((stocks * 100).round());
  return (
    total: _dollars(cash + stockCents, formats),
    cash: _dollars(cash, formats),
    stocks: _dollars(stockCents, formats),
  );
}

/// Shares the wallet holds, with the token symbol, in [formats]' language.
/// The wallet's display amount already counts shares. Without it, shares
/// are plain token units.
String _quantity(WalletStockBalance holding, AppFormats formats) {
  final shares = holding.displayAmount == null
      ? formatRawUnits(holding.amountRaw, holding.decimals)
      : liveGroupedDecimal(holding.displayAmount!);
  return '${shares == null ? shares : formats.number(shares)} ${holding.symbol}';
}

class RealHoldings extends StatelessWidget {
  const RealHoldings({
    super.key,
    required this.account,
    required this.onAddMoney,
    this.onApple,
    this.appleLogoUrl,
    this.onAsset,
    this.logoForAsset,
    this.nameForAsset,
    this.priceForHolding,
    this.onExplore,
  });
  final AccountController? account;
  final VoidCallback onAddMoney;
  final VoidCallback? onApple;
  final String? appleLogoUrl;
  final void Function(WalletStockBalance holding)? onAsset;
  final String? Function(WalletStockBalance holding)? logoForAsset;

  /// The trading capabilities' token name, which tells two issuers' tokens
  /// of one company apart. The wallet's own name is the fallback.
  final String? Function(WalletStockBalance holding)? nameForAsset;

  /// That token's trusted price per share, or null when none is known.
  final double? Function(WalletStockBalance holding)? priceForHolding;
  final VoidCallback? onExplore;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n, formats = context.formats;
    final state = account?.portfolioState;
    final h = state?.portfolio?.holdings;
    final coherent =
        h != null &&
        h.wallet.address == state?.context?.embeddedSolanaWallet.address;
    if (!coherent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state?.context?.embeddedSolanaWallet.isCandidate == true
                  ? l10n.holdingsCheckingWallet
                  : l10n.holdingsWalletStarts,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton(onPressed: onAddMoney, child: Text(l10n.commonAddMoney)),
          ],
        ),
      );
    }
    if (h.stockTokens.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: ShapeDecoration(
          color: ProductColor.paperRaised,
          shape: productSquircle(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.holdingsEmptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.holdingsEmptyBody),
            TextButton(
              onPressed: onExplore ?? onApple,
              child: Text(l10n.holdingsExplore),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final holding in h.stockTokens)
          HoldingTile(
            key: ValueKey('real-holding-${holding.mint}'),
            name: nameForAsset?.call(holding) ?? holding.name,
            logoUrl:
                logoForAsset?.call(holding) ??
                (holding.assetId == 'apple' ? appleLogoUrl : null),
            logoAsset: holding.assetId == 'apple'
                ? 'assets/images/ui_review/wall-street-orbit/token-AAPLx.webp'
                : null,
            quantity: _quantity(holding, formats),
            // Shares times this token's own per-share price; never raw units.
            value: switch (realHoldingValue(
              holding,
              priceForHolding?.call(holding),
            )) {
              final double worth => realUsd(worth, formats),
              null => '–',
            },
            onTap: onAsset != null
                ? () => onAsset!(holding)
                : holding.assetId == 'apple'
                ? onApple
                : null,
          ),
      ],
    );
  }
}
