import 'package:flutter/material.dart';
import 'product_theme.dart';

/// A compact money-mode entry with the same raised edge as our choice cards.
class ProductMoneyTag extends StatelessWidget {
  const ProductMoneyTag({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    decoration: ShapeDecoration(
      color: const Color(0xFFA4CAB8),
      shape: productSquircle(16),
    ),
    padding: const EdgeInsets.fromLTRB(1.5, 1.5, 1.5, 3),
    child: Material(
      color: ProductColor.mint,
      shape: productSquircle(14.5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Use real money',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ProductColor.pineDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 16,
                  color: ProductColor.pineDark,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
