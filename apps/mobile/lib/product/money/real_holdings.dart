import 'package:flutter/material.dart';
import '../../account/account_controller.dart';
import '../../account/account_amounts.dart';
import '../design/product_theme.dart';

/// Cash is USDC only. SOL and stock units are not invented dollar valuations.
String? realCashBalance(AccountController? account) {
  final s = account?.portfolioState;
  final h = s?.portfolio?.holdings;
  if (h == null ||
      h.wallet.address != s?.context?.embeddedSolanaWallet.address) {
    return null;
  }
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
  });
  final AccountController? account;
  final VoidCallback onAddMoney;
  final VoidCallback? onApple;
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
    Widget row(String name, String units, {VoidCallback? tap}) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: ShapeDecoration(
        color: const Color(0xFFF3F7F5),
        shape: productSquircle(23),
      ),
      child: ListTile(
        onTap: tap,
        title: Text(name),
        trailing: Text(units, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('USDC', '${formatRawUnits(h.usdc.amountRaw, 6)}'),
        row('SOL', '${formatRawUnits(h.nativeSol.amountRaw, 9)}'),
        if (h.aaplx.amountRaw != '0')
          row(
            'AAPLx',
            '${formatRawUnits(h.aaplx.amountRaw, 8)} units',
            tap: onApple,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Solana · supported assets',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
