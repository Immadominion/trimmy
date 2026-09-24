import 'package:flutter/material.dart';
import 'product_theme.dart';
import 'product_motion_icon.dart';

/// Shared, quiet empty-state treatment. The box is Icons8 Plumpy, matching
/// navigation and actions; no decorative borders or simulated content.
class ProductEmptyState extends StatelessWidget {
  const ProductEmptyState({
    super.key,
    required this.title,
    this.message,
    this.action,
  });
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ProductMotionIcon(file: 'state-empty.png', size: 60),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ProductColor.muted, height: 1.4),
          ),
        ],
        ?action,
      ],
    ),
  );
}
