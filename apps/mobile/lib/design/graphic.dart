import 'package:flutter/material.dart';
import 'theme.dart';

/// Original UI drawings with the same clear planes and strong edges as the cast.
enum TrimmySymbol { office, portfolio, journal, spark, flame, check, arrow }

class GraphicIcon extends StatelessWidget {
  const GraphicIcon(
    this.symbol, {
    super.key,
    this.size = 26,
    this.color = TrimmyColors.ink,
  });
  final TrimmySymbol symbol;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _GraphicPainter(symbol, color)),
    ),
  );
}

class _GraphicPainter extends CustomPainter {
  const _GraphicPainter(this.symbol, this.color);
  final TrimmySymbol symbol;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;
    switch (symbol) {
      case TrimmySymbol.office:
        canvas.drawPath(
          Path()
            ..moveTo(6, 28)
            ..lineTo(6, 5)
            ..lineTo(25, 3)
            ..lineTo(25, 28)
            ..close(),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(13, 28)
            ..lineTo(13, 21)
            ..lineTo(19, 21)
            ..lineTo(19, 28),
          stroke,
        );
        for (final x in [12.0, 20.0]) {
          for (final y in [10.0, 16.0]) {
            canvas.drawCircle(Offset(x, y), 1.7, fill);
          }
        }
      case TrimmySymbol.portfolio:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 10, 24, 18),
            const Radius.circular(4),
          ),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(11, 10)
            ..lineTo(11, 5)
            ..lineTo(21, 5)
            ..lineTo(21, 10)
            ..moveTo(4, 17)
            ..lineTo(28, 17),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(13, 15, 6, 5),
            const Radius.circular(1),
          ),
          fill,
        );
      case TrimmySymbol.journal:
        canvas.drawPath(
          Path()
            ..moveTo(6, 4)
            ..lineTo(27, 4)
            ..lineTo(27, 28)
            ..lineTo(6, 28)
            ..close()
            ..moveTo(11, 4)
            ..lineTo(11, 28),
          stroke,
        );
        canvas.drawLine(const Offset(16, 11), const Offset(22, 11), stroke);
        canvas.drawLine(const Offset(16, 17), const Offset(21, 17), stroke);
        canvas.drawLine(const Offset(3, 10), const Offset(7, 10), stroke);
        canvas.drawLine(const Offset(3, 22), const Offset(7, 22), stroke);
      case TrimmySymbol.spark:
        canvas.drawPath(
          Path()
            ..moveTo(17, 2)
            ..lineTo(20, 11)
            ..lineTo(29, 13)
            ..lineTo(22, 18)
            ..lineTo(23, 28)
            ..lineTo(15, 22)
            ..lineTo(6, 28)
            ..lineTo(8, 18)
            ..lineTo(2, 12)
            ..lineTo(12, 11)
            ..close(),
          fill,
        );
      case TrimmySymbol.flame:
        canvas.drawPath(
          Path()
            ..moveTo(18, 2)
            ..cubicTo(21, 10, 29, 14, 27, 22)
            ..cubicTo(26, 30, 8, 32, 5, 23)
            ..cubicTo(2, 16, 10, 12, 11, 7)
            ..lineTo(15, 13)
            ..close(),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(17, 16)
            ..cubicTo(16, 20, 11, 22, 14, 25)
            ..cubicTo(21, 28, 22, 22, 17, 16),
          Paint()..color = TrimmyColors.paper,
        );
      case TrimmySymbol.check:
        canvas.drawPath(
          Path()
            ..moveTo(6, 16)
            ..lineTo(13, 23)
            ..lineTo(27, 8),
          stroke..strokeWidth = 3.3,
        );
      case TrimmySymbol.arrow:
        canvas.drawPath(
          Path()
            ..moveTo(5, 16)
            ..lineTo(27, 16)
            ..moveTo(19, 8)
            ..lineTo(27, 16)
            ..lineTo(19, 24),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_GraphicPainter oldDelegate) =>
      oldDelegate.symbol != symbol || oldDelegate.color != color;
}

class TactileButton extends StatefulWidget {
  const TactileButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.yellow = false,
    this.reducedMotion = false,
    this.trailing = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool yellow, reducedMotion, trailing;
  @override
  State<TactileButton> createState() => _TactileButtonState();
}

class _TactileButtonState extends State<TactileButton> {
  bool pressed = false;
  void _press(bool value) {
    if (mounted && widget.onPressed != null) setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final noMotion =
        widget.reducedMotion || MediaQuery.disableAnimationsOf(context);
    final foreground = widget.yellow ? TrimmyColors.ink : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Listener(
        onPointerDown: (_) => _press(true),
        onPointerUp: (_) => _press(false),
        onPointerCancel: (_) => _press(false),
        child: AnimatedContainer(
          duration: noMotion
              ? Duration.zero
              : const Duration(milliseconds: 100),
          transform: Matrix4.translationValues(
            0,
            pressed && !noMotion ? 3 : 0,
            0,
          ),
          decoration: ShapeDecoration(
            shape: squircle(18),
            shadows: widget.onPressed == null
                ? []
                : [
                    BoxShadow(
                      color: widget.yellow
                          ? const Color(0xFFC18A06)
                          : const Color(0xFF003D2C),
                      offset: Offset(0, pressed ? 1 : 4),
                    ),
                  ],
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.yellow
                  ? TrimmyColors.yellow
                  : TrimmyColors.pine,
              foregroundColor: foreground,
              minimumSize: const Size(double.infinity, 56),
            ),
            onPressed: widget.onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (widget.trailing) ...[
                  const SizedBox(width: 12),
                  GraphicIcon(TrimmySymbol.arrow, size: 21, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
