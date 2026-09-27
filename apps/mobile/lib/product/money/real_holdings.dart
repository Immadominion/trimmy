import 'package:flutter/material.dart';
import '../../account/account_controller.dart';
import '../../account/account_amounts.dart';
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

String? realSolBalance(AccountController? account) {
  final holdings = realWalletHoldings(account);
  return holdings == null
      ? null
      : formatRawUnits(holdings.nativeSol.amountRaw, 9);
}

/// USD cash is USDC. The card shows SOL separately for fees, without inventing
/// a SOL exchange rate or treating raw stock-token units as verified shares.
String? realCashBalance(AccountController? account) {
  final h = realWalletHoldings(account);
  if (h == null) return null;
  final raw = BigInt.tryParse(h.usdc.amountRaw);
  if (raw == null) return null;
  final cents = raw ~/ BigInt.from(10000);
  final whole = (cents ~/ BigInt.from(100)).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '\$$whole.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
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
  final VoidCallback? onExplore;
  @override
  Widget build(BuildContext context) {
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
                  ? 'Checking your wallet…'
                  : 'Your wallet starts here',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton(onPressed: onAddMoney, child: const Text('Add money')),
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
              'No stocks yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text('Your first stock starts here.'),
            TextButton(
              onPressed: onExplore ?? onApple,
              child: const Text('Explore stocks'),
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
            // The wallet's display amount already counts shares. Without it,
            // shares are plain token units.
            quantity:
                '${holding.displayAmount == null ? formatRawUnits(holding.amountRaw, holding.decimals) : liveGroupedDecimal(holding.displayAmount!)} ${holding.symbol}',
            // A market share price must not be multiplied by raw token units:
            // token-to-share resolution and valuation are separate facts.
            value: '—',
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
