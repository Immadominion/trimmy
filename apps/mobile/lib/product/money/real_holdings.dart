import 'package:flutter/material.dart';
import '../../account/account_controller.dart';
import '../../account/account_amounts.dart';
import '../design/product_theme.dart';
import '../desk/holding_tile.dart';
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
  });
  final AccountController? account;
  final VoidCallback onAddMoney;
  final VoidCallback? onApple;
  final String? appleLogoUrl;
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
    if (h.aaplx.amountRaw == '0') {
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
            TextButton(onPressed: onApple, child: const Text('Explore stocks')),
          ],
        ),
      );
    }
    return HoldingTile(
      name: 'Apple',
      logoUrl: appleLogoUrl,
      logoAsset: 'assets/images/ui_review/wall-street-orbit/token-AAPLx.webp',
      quantity: '${formatRawUnits(h.aaplx.amountRaw, 8)} AAPLx',
      // The holdings API intentionally leaves the scaled share amount
      // unresolved. Do not multiply raw units by a market share price.
      value: '—',
      onTap: onApple,
    );
  }
}
