import 'package:flutter/material.dart';

import '../../account/guest_session.dart';
import '../../l10n/l10n.dart';
import '../design/product_state_page.dart';
import '../design/product_components.dart';
import '../design/product_theme.dart';

/// Terminal recovery for a guest credential that can no longer authorize its
/// paper ledger. The destructive action is deliberately two steps deep.
class GuestDeskRecoveryScreen extends StatefulWidget {
  const GuestDeskRecoveryScreen({
    super.key,
    required this.onStartNew,
    this.onSignIn,
    this.failure = GuestSessionFailure.expired,
  });

  final VoidCallback? onSignIn;
  final Future<void> Function() onStartNew;
  final GuestSessionFailure failure;

  @override
  State<GuestDeskRecoveryScreen> createState() =>
      _GuestDeskRecoveryScreenState();
}

class _GuestDeskRecoveryScreenState extends State<GuestDeskRecoveryScreen> {
  var _confirming = false;
  var _busy = false;
  var _failed = false;

  bool get _expired => widget.failure == GuestSessionFailure.expired;

  Future<void> _startNew() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.onStartNew();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ProductStatePage(
      artwork: ProductStateArtwork(
        key: ValueKey(_confirming),
        file: _confirming ? 'folders.png' : 'safe.png',
      ),
      title: _confirming
          ? l10n.guestDeskStartFreshTitle
          : _expired
          ? l10n.guestDeskExpiredTitle
          : l10n.guestDeskEndedTitle,
      message: _confirming
          ? l10n.guestDeskStartFreshMessage
          : _expired
          ? l10n.guestDeskExpiredMessage
          : l10n.guestDeskEndedMessage,
      details: ProductCard(
        color: _confirming ? const Color(0xFFFFF4F5) : ProductColor.paperRaised,
        child: Text(
          _confirming
              ? l10n.guestDeskStartFreshDetail
              : l10n.guestDeskSignInDetail,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      actions: [
        if (_confirming) ...[
          ProductButton(
            key: const ValueKey('guest-recovery-confirm-start-new'),
            label: _busy
                ? l10n.guestDeskOpening
                : l10n.guestDeskStartNewConfirm,
            onPressed: _busy ? null : _startNew,
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('guest-recovery-keep-desk'),
            onPressed: _busy
                ? null
                : () => setState(() {
                    _confirming = false;
                    _failed = false;
                  }),
            child: Text(l10n.guestDeskKeep, textAlign: TextAlign.center),
          ),
        ] else ...[
          ProductButton(
            key: const ValueKey('guest-recovery-sign-in'),
            label: l10n.commonSignIn,
            onPressed: widget.onSignIn,
          ),
          if (widget.onSignIn == null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.signInUnavailable,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('guest-recovery-start-new'),
            onPressed: () => setState(() {
              _confirming = true;
              _failed = false;
            }),
            child: Text(
              l10n.guestDeskStartNewGuest,
              textAlign: TextAlign.center,
            ),
          ),
        ],
        if (_failed) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _expired
                  ? l10n.guestDeskStartAgainFailedExpired
                  : l10n.guestDeskStartAgainFailed,
              key: const ValueKey('guest-recovery-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: ProductColor.loss),
            ),
          ),
        ],
      ],
    );
  }
}
