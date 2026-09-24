import 'package:flutter/material.dart';
import '../design/product_theme.dart';
import '../market/market_craft.dart';

/// One stock row for both ledgers. Callers supply verified quantities/values;
/// an unavailable onchain valuation is never replaced with a paper price.
class HoldingTile extends StatelessWidget {
  const HoldingTile({
    super.key,
    required this.name,
    required this.quantity,
    required this.value,
    this.logoUrl,
    this.logoAsset,
    this.changePercent,
    this.onTap,
  });
  final String name, quantity, value;
  final String? logoUrl, logoAsset;
  final double? changePercent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final type = Theme.of(context).textTheme;
    final change = changePercent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF7F6FA),
        shape: productSquircle(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                CompanyLogo(
                  name: name,
                  logoUrl: logoUrl,
                  fallbackAsset: logoAsset,
                  color: Colors.white,
                  size: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: type.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(quantity, style: type.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Semantics(
                        label: value == '—' ? 'Value unavailable' : null,
                        child: Text(value, style: type.titleMedium),
                      ),
                      if (change != null)
                        Text(
                          signedPercent(change),
                          style: type.bodySmall?.copyWith(
                            color: change >= 0
                                ? ProductColor.gain
                                : ProductColor.loss,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
