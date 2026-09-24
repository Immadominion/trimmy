import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A soft, glossy seal, with the rounded volume of the Trimmy mark.
class ProductSuccessMark extends StatelessWidget {
  const ProductSuccessMark({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Completed',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SuccessPainter()),
    ),
  );
}

class _SuccessPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final path = Path();
    for (var i = 0; i <= 160; i++) {
      final angle = i / 160 * math.pi * 2;
      final radius = size.shortestSide * (.43 + .025 * math.cos(angle * 8));
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path.shift(Offset(0, size.height * .025)),
      Paint()..color = const Color(0xFF198756),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9AECB3), Color(0xFF43BC7B), Color(0xFF239C62)],
          stops: [0, .5, 1],
        ).createShader(Offset.zero & size),
    );
    final check = Path()
      ..moveTo(size.width * .29, size.height * .51)
      ..lineTo(size.width * .44, size.height * .65)
      ..lineTo(size.width * .72, size.height * .35);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .085
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SuccessPainter oldDelegate) => false;
}
