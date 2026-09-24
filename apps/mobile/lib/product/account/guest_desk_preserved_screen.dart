import 'package:flutter/material.dart';

import '../design/product_components.dart';
import '../design/product_motion_icon.dart';
import '../design/product_state_page.dart';
import '../design/product_success_mark.dart';
import '../design/product_theme.dart';

/// Existing accounts keep their own desk; guest trades are never merged here.
class GuestDeskPreservedScreen extends StatelessWidget {
  const GuestDeskPreservedScreen({
    super.key,
    required this.onContinue,
    this.expired = false,
  });

  final VoidCallback onContinue;
  final bool expired;

  @override
  Widget build(BuildContext context) => ProductStatePage(
    artwork: const SizedBox(
      width: 184,
      height: 184,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ProductStateArtwork(file: 'desk.png', size: 184),
          Positioned(right: 0, bottom: 0, child: ProductSuccessMark(size: 40)),
        ],
      ),
    ),
    title: 'Welcome back',
    message: 'Your saved trades and progress are ready.',
    details: ProductCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ProductMotionIcon(file: 'settings-lock.png', size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              expired
                  ? 'Your expired guest desk is preserved separately. It can no longer trade or merge.'
                  : 'Your guest trades stay separate. Sign out to return to that desk.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: ProductColor.muted),
            ),
          ),
        ],
      ),
    ),
    actions: [
      ProductButton(
        key: const ValueKey('open-saved-desk'),
        label: 'Go to my desk',
        onPressed: onContinue,
      ),
    ],
  );
}
