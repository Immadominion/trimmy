import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_study/craft.dart';
import 'account_controller.dart';
import 'account_data_models.dart';
import 'wallet_setup.dart';

/// The real wallet setup/address path in Portfolio. Address data comes from
/// verified server context, never an SDK creation response or practice save.
class WalletSetupPanel extends StatefulWidget {
  const WalletSetupPanel({super.key, required this.controller});
  final AccountController controller;
  @override
  State<WalletSetupPanel> createState() => _WalletSetupPanelState();
}

class _WalletSetupPanelState extends State<WalletSetupPanel> {
  WalletSetupOutcome? _outcome;
  String? _outcomeAccount;
  bool _showAddress = false;
  String? _copiedAddress;

  Future<void> _setUp() async {
    final account = widget.controller.accountId;
    setState(() {
      _outcome = null;
      _outcomeAccount = account;
    });
    final outcome = await widget.controller.setUpWallet();
    if (!mounted || widget.controller.accountId != account) return;
    setState(() {
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (!controller.isServerVerified) return const SizedBox.shrink();
      final wallet = controller.portfolioState?.context?.embeddedSolanaWallet;
      final outcome = _outcomeAccount == controller.accountId ? _outcome : null;
      if (wallet?.isCandidate == true) {
        final address = wallet!.address!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton.icon(
              key: const ValueKey('portfolio-wallet-address'),
              onPressed: () => setState(() {
                _showAddress = !_showAddress;
                _copiedAddress = null;
              }),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(
                _showAddress ? 'Hide wallet address' : 'View wallet address',
              ),
            ),
            if (_showAddress)
              StudyPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Your Solana wallet', style: display(19)),
                    const SizedBox(height: 8),
                    SelectableText(
                      address,
                      key: const ValueKey('portfolio-full-address'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final account = controller.accountId;
                        try {
                          await Clipboard.setData(ClipboardData(text: address));
                          if (mounted &&
                              controller.accountId == account &&
                              controller
                                      .portfolioState
                                      ?.context
                                      ?.embeddedSolanaWallet
                                      .address ==
                                  address) {
                            setState(() => _copiedAddress = address);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not copy. Select the address to copy it.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: Icon(
                        _copiedAddress == address
                            ? Icons.check_rounded
                            : Icons.copy_rounded,
                      ),
                      label: Text(
                        _copiedAddress == address ? 'Copied' : 'Copy address',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      }
      if (wallet?.status != EmbeddedSolanaWalletStatus.missing ||
          (!controller.canSetUpWallet && !controller.walletSetupBusy)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: StudyPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('A wallet of your own', style: display(22)),
              const SizedBox(height: 8),
              const Text(
                'Create a Solana wallet linked to this account. It starts empty and stays with your sign-in.',
              ),
              const SizedBox(height: 16),
              CraftButton(
                key: const ValueKey('portfolio-create-wallet'),
                label: controller.walletSetupBusy
                    ? 'Setting up…'
                    : outcome == WalletSetupOutcome.awaitingServer
                    ? 'Check wallet setup'
                    : 'Create wallet',
                onPressed: controller.canSetUpWallet ? _setUp : null,
              ),
              if (outcome != null && outcome != WalletSetupOutcome.ready) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(switch (outcome) {
                    WalletSetupOutcome.awaitingServer =>
                      'Setup has not been confirmed yet. Check again to recover an existing wallet before creating one.',
                    WalletSetupOutcome.accountChanged =>
                      'Your account changed. Sign in again to continue.',
                    _ =>
                      'Wallet setup could not finish. Try again when you are online.',
                  }),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
