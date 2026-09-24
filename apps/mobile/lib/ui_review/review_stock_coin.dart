import 'package:flutter/material.dart';

/// Front-facing variant of Welcome's provider-token coin: same image, molded
/// rim and highlight, with no orbit transform, translation or lens shader.
class ReviewStockCoin extends StatelessWidget {
  const ReviewStockCoin({super.key, required this.symbol, required this.size});
  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (symbol) {
      'NVDA' => const Color(0xFF83BA00),
      'MSFT' => const Color(0xFFEEB949),
      'TSLA' => const Color(0xFFE14B50),
      'META' => const Color(0xFF508DDF),
      _ => const Color(0xFFB4B7C0),
    };
    final dark = Color.lerp(color, const Color(0xFF291D38), .42)!;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .047),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, .65)!, color, dark],
        ),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/ui_review/wall-street-orbit/token-${symbol}x.webp',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              excludeFromSemantics: true,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x22FFFFFF),
                    Color(0x00FFFFFF),
                    Color(0x28261937),
                  ],
                  stops: [0, .45, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
