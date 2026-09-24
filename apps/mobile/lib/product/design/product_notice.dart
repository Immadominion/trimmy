import 'package:flutter/material.dart';
import '../market/market_craft.dart';

/// Shared transient feedback; keeps auth/retry actions inside the soft surface.
void showProductNotice(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      content: ProductNotice(
        message: message,
        action: action,
        onDismiss: messenger.hideCurrentSnackBar,
      ),
    ),
  );
}

/// A quiet, dismissible status surface. The owner controls lifetime so closing
/// a message never discards an order or its retry/idempotency state.
class ProductNotice extends StatelessWidget {
  const ProductNotice({
    super.key,
    required this.message,
    required this.onDismiss,
    this.action,
  });
  final String message;
  final VoidCallback onDismiss;
  final SnackBarAction? action;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(15, 5, 3, 5),
      decoration: ShapeDecoration(
        color: const Color(0xFFF6F1FB),
        shape: marketSquircle(20),
        shadows: const [
          BoxShadow(
            color: Color(0x087460CF),
            offset: Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: MarketPalette.violet,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: Color(0xFF514371),
                  ),
                ),
                ?action,
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss message',
            onPressed: onDismiss,
            icon: const Icon(
              Icons.close_rounded,
              size: 19,
              color: MarketPalette.violet,
            ),
          ),
        ],
      ),
    ),
  );
}
