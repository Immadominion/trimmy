import 'package:flutter/material.dart';

import 'paper_format.dart';
import 'product_theme.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = ProductColor.paperRaised,
    this.radius = 26,
    this.borderColor = Colors.transparent,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color, borderColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = productSquircle(radius).copyWith(
      side: borderColor == Colors.transparent
          ? BorderSide.none
          : BorderSide(color: borderColor, width: 1.25),
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Trimmy's raised action has a visible underside, a restrained press and a
/// full-width phone target. It is the one deliberately toy-like control.
class ProductButton extends StatefulWidget {
  const ProductButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secondary = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool secondary, compact;

  @override
  State<ProductButton> createState() => _ProductButtonState();
}

class _ProductButtonState extends State<ProductButton> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final face = !enabled
        ? ProductColor.line
        : widget.secondary
        ? ProductColor.paperRaised
        : ProductColor.violet;
    final underside = !enabled
        ? const Color(0xFFDEDAE7)
        : widget.secondary
        ? const Color(0xFFE3DFEC)
        : ProductColor.violetDark;
    final ink = !enabled
        ? ProductColor.muted
        : widget.secondary
        ? ProductColor.ink
        : Colors.white;
    final radius = widget.compact ? 17.0 : 21.0;
    final shape = productSquircle(radius);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      child: Stack(
        // Pass the parent's horizontal constraint to the face. Stack's
        // default loose fit lets the InkWell shrink to the label while the
        // positioned underside still paints at full width, leaving most of a
        // visible button unable to receive a tap on a physical phone.
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            top: 6,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: underside,
                shape: productSquircle(radius),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AnimatedContainer(
              duration: productDuration(context, _pressed ? 70 : 150),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(
                0,
                _pressed && enabled ? 5 : 0,
                0,
              ),
              child: Material(
                color: face,
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onPressed,
                  onHighlightChanged: (value) =>
                      setState(() => _pressed = value),
                  customBorder: shape,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: widget.compact ? 48 : 58,
                      minWidth: widget.compact ? 48 : 96,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.compact ? 15 : 20,
                        vertical: 13,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, size: 20, color: ink),
                            const SizedBox(width: 9),
                          ],
                          Flexible(
                            child: Text(
                              widget.label,
                              textAlign: TextAlign.center,
                              style: Theme.of(
                                context,
                              ).textTheme.labelLarge?.copyWith(color: ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The paper mark is intentionally unlike a currency symbol. It reads as a
/// folded sheet before a number and never appears beside money.
class PaperMark extends StatelessWidget {
  const PaperMark({super.key, this.size = 24, this.color = ProductColor.ink});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'paper',
    image: true,
    child: ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, size),
        painter: _PaperMarkPainter(color),
      ),
    ),
  );
}

class _PaperMarkPainter extends CustomPainter {
  const _PaperMarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .18, size.height * .08)
      ..lineTo(size.width * .67, size.height * .08)
      ..lineTo(size.width * .84, size.height * .27)
      ..lineTo(size.width * .84, size.height * .9)
      ..lineTo(size.width * .18, size.height * .9)
      ..close();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .12,
          size.height * .13,
          size.width * .66,
          size.height * .8,
        ),
        Radius.circular(size.width * .08),
      ),
      Paint()..color = ProductColor.yellow,
    );
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .67, size.height * .08)
        ..lineTo(size.width * .67, size.height * .3)
        ..lineTo(size.width * .84, size.height * .27),
      Paint()
        ..color = ProductColor.paper
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .075
        ..strokeJoin = StrokeJoin.round,
    );
    final line = Paint()
      ..color = ProductColor.paper
      ..strokeWidth = size.width * .07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * .34, size.height * .48),
      Offset(size.width * .69, size.height * .48),
      line,
    );
    canvas.drawLine(
      Offset(size.width * .34, size.height * .66),
      Offset(size.width * .61, size.height * .66),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class PaperAmount extends StatelessWidget {
  const PaperAmount(
    this.amount, {
    super.key,
    this.style,
    this.markSize,
    this.alignment = MainAxisAlignment.start,
  });

  final String amount;
  final TextStyle? style;
  final double? markSize;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final display = formatPaperForDisplay(amount);
    return Semantics(
      label: '$display paper',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignment,
          children: [
            PaperMark(size: markSize ?? (style?.fontSize ?? 24) * .78),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                display,
                style: (style ?? Theme.of(context).textTheme.headlineLarge)
                    ?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
