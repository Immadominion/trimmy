import 'package:flutter/material.dart';

/// Two content-sized sections on one receipt, joined by a perforated seam.
/// Each half cuts its own half-circle, keeping the seam correct as text grows.
class ReviewTradeTicket extends StatelessWidget {
  const ReviewTradeTicket({
    super.key,
    required this.upper,
    required this.lower,
    this.upperColor = const Color(0xFFF2EEFF),
    this.lowerColor = const Color(0xFFEDF7EF),
  });

  final Widget upper, lower;
  final Color upperColor, lowerColor;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipPath(
        clipper: const _TicketHalf(upper: true),
        child: ColoredBox(
          color: upperColor,
          child: Padding(padding: const EdgeInsets.all(24), child: upper),
        ),
      ),
      ClipPath(
        clipper: const _TicketHalf(upper: false),
        child: ColoredBox(
          color: lowerColor,
          child: CustomPaint(
            foregroundPainter: const _Perforation(),
            child: Padding(padding: const EdgeInsets.all(24), child: lower),
          ),
        ),
      ),
    ],
  );
}

class _TicketHalf extends CustomClipper<Path> {
  const _TicketHalf({required this.upper});
  final bool upper;

  @override
  Path getClip(Size size) {
    final outline = RoundedSuperellipseBorder(
      borderRadius: upper
          ? const BorderRadius.vertical(top: Radius.circular(24))
          : const BorderRadius.vertical(bottom: Radius.circular(24)),
    ).getOuterPath(Offset.zero & size);
    final seam = upper ? size.height : 0.0;
    final cutouts = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, seam), radius: 10))
      ..addOval(Rect.fromCircle(center: Offset(size.width, seam), radius: 10));
    return Path.combine(PathOperation.difference, outline, cutouts);
  }

  @override
  bool shouldReclip(_TicketHalf oldClipper) => oldClipper.upper != upper;
}

class _Perforation extends CustomPainter {
  const _Perforation();
  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = const Color(0xFF251B38).withValues(alpha: .16)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (double x = 23; x < size.width - 23; x += 12) {
      canvas.drawLine(
        Offset(x, .5),
        Offset((x + 5).clamp(x, size.width - 23), .5),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(_Perforation oldDelegate) => false;
}
