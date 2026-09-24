import 'package:flutter/material.dart';

import '../design_study/craft.dart';
import 'wallet_possession_controller.dart';
import 'wallet_possession_models.dart';

/// Account tools, reached through Settings. Merely opening this panel makes no
/// provider request. Preparing a check and signing its message are two actions.
class WalletPossessionPanel extends StatelessWidget {
  const WalletPossessionPanel({super.key, required this.controller});
  final WalletPossessionController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final phase = controller.phase;
      final challenge = controller.challenge;
      final receipt = controller.receipt;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Check your wallet', style: display(24)),
          const SizedBox(height: 10),
          const Text(
            'Sign a message to show that you control the wallet linked to your '
            'account. This does not approve a payment or trade.',
          ),
          const SizedBox(height: 18),
          if (phase == WalletPossessionPhase.preparing)
            Semantics(
              liveRegion: true,
              child: const Text('Preparing your message…'),
            ),
          if (challenge != null &&
              const {
                WalletPossessionPhase.reviewing,
                WalletPossessionPhase.signing,
                WalletPossessionPhase.submitting,
              }.contains(phase)) ...[
            Text(
              'Your Solana wallet',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            SelectableText(challenge.walletAddress),
            const SizedBox(height: 8),
            Text('Sign before ${_time(challenge.expiresAt)}.'),
            const SizedBox(height: 6),
            ExpansionTile(
              key: ValueKey('wallet-message-${challenge.challengeId}'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Read the full message'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SelectableText(challenge.message),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CraftButton(
              key: const ValueKey('wallet-proof-sign'),
              label: switch (phase) {
                WalletPossessionPhase.signing => 'Signing message…',
                WalletPossessionPhase.submitting => 'Checking signature…',
                _ => 'Sign message',
              },
              onPressed: controller.canSign ? controller.confirm : null,
            ),
          ],
          if (phase == WalletPossessionPhase.verified && receipt != null) ...[
            Semantics(
              liveRegion: true,
              child: Text('Wallet checked', style: display(20)),
            ),
            const SizedBox(height: 8),
            SelectableText(receipt.walletAddress),
            const SizedBox(height: 8),
            Text(
              'This wallet signed your message at ${_time(receipt.verifiedAt)}.',
            ),
          ],
          if (phase == WalletPossessionPhase.expired)
            Semantics(
              liveRegion: true,
              child: const Text(
                'This message expired. Start again for a new one.',
              ),
            ),
          if (phase == WalletPossessionPhase.cancelled)
            Semantics(
              liveRegion: true,
              child: const Text(
                'Check stopped. You can start again when you are ready.',
              ),
            ),
          if (phase == WalletPossessionPhase.error)
            Semantics(
              liveRegion: true,
              child: Text(_failureText(controller.failure)),
            ),
          if (phase == WalletPossessionPhase.closed)
            const Text('Sign into your account to check its wallet.'),
          if (const {
            WalletPossessionPhase.idle,
            WalletPossessionPhase.verified,
            WalletPossessionPhase.expired,
            WalletPossessionPhase.cancelled,
            WalletPossessionPhase.error,
          }.contains(phase)) ...[
            const SizedBox(height: 14),
            CraftButton(
              key: const ValueKey('wallet-proof-prepare'),
              label: phase == WalletPossessionPhase.idle
                  ? 'Prepare message'
                  : 'Start a new check',
              onPressed: controller.canStart ? controller.prepare : null,
            ),
          ],
          if (controller.isBusy || phase == WalletPossessionPhase.reviewing)
            TextButton(
              key: const ValueKey('wallet-proof-cancel'),
              onPressed: controller.cancel,
              child: const Text('Cancel check'),
            ),
        ],
      );
    },
  );
}

String _time(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _failureText(WalletPossessionFailure? failure) => switch (failure) {
  WalletPossessionFailure.walletMissing =>
    'There is no Solana wallet linked to this account yet.',
  WalletPossessionFailure.walletAmbiguous =>
    'More than one wallet is linked. This check needs one wallet.',
  WalletPossessionFailure.accountMismatch ||
  WalletPossessionFailure.walletMismatch ||
  WalletPossessionFailure.unauthenticated =>
    'Your account or wallet changed. Sign in again before starting a new check.',
  WalletPossessionFailure.challengeExpired ||
  WalletPossessionFailure.challengeNotFound =>
    'This message is no longer available. Start again for a new one.',
  WalletPossessionFailure.rateLimited =>
    'Wait a moment before starting another check.',
  WalletPossessionFailure.notConfigured =>
    'Wallet checks are not available in this build yet.',
  WalletPossessionFailure.signatureRejected ||
  WalletPossessionFailure.invalidSignature =>
    'The signature could not be checked. You can start again.',
  WalletPossessionFailure.cancelled => 'Signing was cancelled.',
  WalletPossessionFailure.timeout =>
    'The check took too long. Check your connection and try again.',
  _ => 'The wallet check could not finish. You can try again.',
};
