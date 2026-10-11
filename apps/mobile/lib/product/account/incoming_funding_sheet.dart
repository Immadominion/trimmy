import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../account/account_controller.dart';
import '../../account/account_amounts.dart';
import '../../account/incoming_funding_controller.dart';
import '../../account/incoming_funding_models.dart';
import '../design/product_components.dart';
import '../design/product_theme.dart';

/// The external wallet supplies funds; the signed-in Trimmy wallet stays fixed.
class IncomingFundingSheet extends StatefulWidget {
  const IncomingFundingSheet({
    super.key,
    required this.account,
    this.allowNew = true,
  });
  final AccountController account;
  final bool allowNew;
  @override
  State<IncomingFundingSheet> createState() => _IncomingFundingSheetState();
}

class _IncomingFundingSheetState extends State<IncomingFundingSheet>
    with WidgetsBindingObserver {
  IncomingFundingController? _funding;
  final _amount = TextEditingController(), _signature = TextEditingController();
  String _asset = 'USDC';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.account.addListener(_accountChanged);
    try {
      _funding = widget.account.createIncomingFunding(allowNew: widget.allowNew)
        ..addListener(_changed);
      unawaited(_funding!.initialize());
    } on FundingFailure {
      /* Account changed while opening the sheet. */
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _accountChanged() {
    if (_funding?.current == false) _funding?.invalidate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _funding?.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    widget.account.removeListener(_accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    _funding?.removeListener(_changed);
    _funding?.dispose();
    _amount.dispose();
    _signature.dispose();
    super.dispose();
  }

  Widget _address(String title, String address) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodySmall),
              Semantics(
                label: address,
                child: Text(
                  shortenAddress(address),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy $title address',
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () => Clipboard.setData(ClipboardData(text: address)),
        ),
      ],
    ),
  );
  Widget _status(IconData icon, String title, String detail) => Column(
    children: [
      const SizedBox(height: 16),
      Icon(icon, size: 42, color: ProductColor.violet),
      const SizedBox(height: 20),
      Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 10),
      Text(
        detail,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final f = _funding, p = f?.phase, type = Theme.of(context).textTheme;
    final reviewing = p == IncomingFundingPhase.review;
    final editing =
        p == IncomingFundingPhase.details ||
        p == IncomingFundingPhase.preparing;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Transfer from wallet', style: type.titleLarge),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (f == null || p == IncomingFundingPhase.invalidated)
              _status(
                Icons.lock_outline_rounded,
                'Account changed',
                'Close this sheet and open Add money again.',
              )
            else if (p == IncomingFundingPhase.loading ||
                p == IncomingFundingPhase.connecting)
              _status(
                Icons.account_balance_wallet_outlined,
                p == IncomingFundingPhase.loading
                    ? 'Checking your wallet…'
                    : 'Choose your wallet',
                p == IncomingFundingPhase.loading
                    ? ''
                    : 'Return here after connecting.',
              )
            else if (p == IncomingFundingPhase.disconnected && !widget.allowNew)
              _status(
                Icons.info_outline_rounded,
                'Transfer checked',
                'New wallet transfers aren’t available right now.',
              )
            else if (p == IncomingFundingPhase.disconnected) ...[
              _status(
                Icons.account_balance_wallet_outlined,
                'Bring money to your desk',
                'Transfer USDC or SOL from your Solana wallet.',
              ),
              ProductButton(
                label: 'Connect wallet',
                icon: Icons.account_balance_wallet_outlined,
                onPressed: f.busy ? null : () => unawaited(f.connect()),
              ),
            ] else if (editing || reviewing) ...[
              if (editing) ...[
                Row(
                  children: [
                    for (final asset in ['USDC', 'SOL'])
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: asset == 'USDC' ? 8 : 0,
                          ),
                          child: ChoiceChip(
                            label: Center(child: Text(asset)),
                            selected: _asset == asset,
                            showCheckmark: false,
                            side: BorderSide.none,
                            onSelected: f.busy
                                ? null
                                : (_) => setState(() => _asset = asset),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _amount,
                  enabled: !f.busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: type.headlineLarge,
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    suffixText: _asset,
                    filled: true,
                    fillColor: ProductColor.paperRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Text(
                  '${formatRawUnits(f.review!.amountRaw, f.review!.decimals)} ${f.review!.asset}',
                  textAlign: TextAlign.center,
                  style: type.headlineLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Into your Trimmy account',
                  textAlign: TextAlign.center,
                  style: type.bodyMedium,
                ),
                const SizedBox(height: 20),
              ],
              _address('From', f.source!),
              _address('Your Trimmy wallet', f.recipient),
              if (reviewing) ...[
                const SizedBox(height: 12),
                _detail(
                  'Network fee',
                  '${formatRawUnits(f.review!.feeRaw, 9)} SOL',
                ),
                if (f.review!.createsAccount)
                  _detail(
                    'Token account deposit',
                    '${formatRawUnits(f.review!.rentRaw, 9)} SOL',
                  ),
                const SizedBox(height: 8),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Solana network. Keep enough SOL in your source wallet for fees.',
                  style: type.bodySmall,
                ),
              ),
              ProductButton(
                label: reviewing
                    ? 'Continue in wallet'
                    : f.busy
                    ? 'Preparing…'
                    : 'Review transfer',
                onPressed: reviewing
                    ? (f.canConfirm ? () => unawaited(f.confirm()) : null)
                    : (f.canEdit
                          ? () => unawaited(
                              f.prepare(_asset, _amount.text.trim()),
                            )
                          : null),
              ),
              if (reviewing)
                TextButton(onPressed: f.edit, child: const Text('Edit amount')),
            ] else if (p == IncomingFundingPhase.approving)
              _status(
                Icons.open_in_new_rounded,
                'Approve in your wallet',
                'Check the amount and recipient before approving.',
              )
            else if (p == IncomingFundingPhase.pending) ...[
              _status(
                Icons.hourglass_top_rounded,
                'Confirming transfer',
                'Your balance updates automatically after confirmation.',
              ),
              const LinearProgressIndicator(minHeight: 3),
            ] else if (p == IncomingFundingPhase.uncertain) ...[
              _status(
                Icons.info_outline_rounded,
                'Check your wallet',
                f.error == 'PENDING_OTHER_ACCOUNT'
                    ? 'A transfer from another Trimmy account is still unresolved. Return to that account to check it.'
                    : 'This transfer may have been sent. Check your wallet before trying again.',
              ),
              if (f.canAcknowledge) ...[
                TextField(
                  controller: _signature,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Transaction ID (if available)',
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () =>
                      unawaited(f.reconcileSignature(_signature.text.trim())),
                  child: const Text('Check transaction'),
                ),
                const SizedBox(height: 12),
                ProductButton(
                  label: 'I checked my wallet',
                  secondary: true,
                  onPressed: () => unawaited(f.acknowledgeUnknown()),
                ),
              ],
            ] else if (p == IncomingFundingPhase.confirmed) ...[
              _status(
                Icons.check_circle_outline_rounded,
                'Money added',
                'Your transfer is confirmed on Solana.',
              ),
              ProductButton(
                label: 'Done',
                onPressed: () => Navigator.pop(context),
              ),
            ] else if (p == IncomingFundingPhase.failed) ...[
              _status(
                Icons.info_outline_rounded,
                'Transfer didn’t complete',
                'Your wallet may have paid a network fee. Check it before trying again.',
              ),
              ProductButton(label: 'Start a new transfer', onPressed: f.edit),
            ],
            if (p == IncomingFundingPhase.uncertain &&
                f != null &&
                f.error != 'PENDING_OTHER_ACCOUNT')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  f.error == 'INVALID_SIGNATURE' || f.error == 'INVALID_REVIEW'
                      ? 'That transaction doesn’t match this transfer. Check the ID in your wallet.'
                      : f.checkingCandidate
                      ? 'Checking this transaction automatically. You can correct the ID above.'
                      : f.error == 'TRANSFER_UNAVAILABLE' ||
                            f.error == 'UNAVAILABLE'
                      ? 'Connection interrupted. Your transfer has not been resent.'
                      : '',
                  textAlign: TextAlign.center,
                  style: type.bodySmall,
                ),
              ),
            if (f?.signature != null)
              TextButton(
                onPressed: () => unawaited(
                  launchUrl(
                    Uri.https('solscan.io', '/tx/${f!.signature}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                child: const Text('View transaction'),
              ),
            if (f?.error != null &&
                {
                  IncomingFundingPhase.details,
                  IncomingFundingPhase.disconnected,
                  IncomingFundingPhase.review,
                }.contains(p))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error(f!.error!),
                  textAlign: TextAlign.center,
                  style: type.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
  String _error(String code) => switch (code) {
    'INVALID_AMOUNT' =>
      'Enter a valid amount. USDC supports 6 decimals; SOL supports 9.',
    'REVIEW_EXPIRED' => 'That review expired. Review your transfer again.',
    'SOURCE_IS_DESTINATION' =>
      'Choose a different wallet to fund your Trimmy account.',
    'MOBILE_WALLET_NO_WALLET' =>
      'Install a compatible Solana wallet, then connect.',
    'MOBILE_WALLET_CANCELLED' =>
      'Cancelled. You can review a new transfer when ready.',
    'INSUFFICIENT_FUNDS' || 'INSUFFICIENT_BALANCE' =>
      'Your source wallet needs enough funds and SOL for fees.',
    'ACCOUNT_CHANGED' =>
      'Your account changed. Close this sheet and open Add money again.',
    'INVALID_REVIEW' || 'REVIEW_MISMATCH' =>
      'We couldn’t verify this transfer. Please try a new review.',
    _ => 'Couldn’t prepare this transfer. Please try again.',
  };
}
