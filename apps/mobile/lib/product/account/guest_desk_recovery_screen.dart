import 'package:flutter/material.dart';

import '../../account/guest_session.dart';
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
  String? _error;

  bool get _expired => widget.failure == GuestSessionFailure.expired;

  Future<void> _startNew() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onStartNew();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _expired
              ? 'Couldn’t start again. Your expired desk is still preserved.'
              : 'Couldn’t start again. Your old desk is still preserved.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ProductStatePage(
    artwork: ProductStateArtwork(
      key: ValueKey(_confirming),
      file: _confirming ? 'folders.png' : 'safe.png',
    ),
    title: _confirming
        ? 'Start fresh?'
        : _expired
        ? 'Guest session expired'
        : 'Guest session ended',
    message: _confirming
        ? 'This removes this phone’s access to your old desk. You can’t undo it.'
        : _expired
        ? 'Your guest records are preserved. This desk can no longer trade or be saved to an account.'
        : 'Your guest records are preserved, but this phone can no longer open the desk.',
    details: ProductCard(
      color: _confirming ? const Color(0xFFFFF4F5) : ProductColor.paperRaised,
      child: Text(
        _confirming
            ? 'Your balance, positions and history won’t move to the new desk.'
            : 'Sign in to open your saved account. Your guest desk stays untouched.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
    actions: [
      if (_confirming) ...[
        ProductButton(
          key: const ValueKey('guest-recovery-confirm-start-new'),
          label: _busy ? 'Opening…' : 'Start a new desk',
          onPressed: _busy ? null : _startNew,
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('guest-recovery-keep-desk'),
          onPressed: _busy
              ? null
              : () => setState(() {
                  _confirming = false;
                  _error = null;
                }),
          child: const Text('Keep this desk'),
        ),
      ] else ...[
        ProductButton(
          key: const ValueKey('guest-recovery-sign-in'),
          label: 'Sign in',
          onPressed: widget.onSignIn,
        ),
        if (widget.onSignIn == null) ...[
          const SizedBox(height: 8),
          Text(
            'Sign-in is unavailable right now.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('guest-recovery-start-new'),
          onPressed: () => setState(() {
            _confirming = true;
            _error = null;
          }),
          child: const Text('Start a new guest desk'),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            _error!,
            key: const ValueKey('guest-recovery-error'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: ProductColor.loss),
          ),
        ),
      ],
    ],
  );
}
