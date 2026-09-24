import 'package:flutter/material.dart';

abstract final class StudyColor {
  static const paper = Color(0xFFFAF9F6);
  static const ink = Color(0xFF202627);
  static const pine = Color(0xFF006344);
  static const deep = Color(0xFF003F35);
  static const mint = Color(0xFFE0EFE5);
  static const yellow = Color(0xFFF3BB2C);
  static const pink = Color(0xFFEF4B77);
  static const violet = Color(0xFF7460CF);
  static const line = Color(0xFFD8DDD7);
  static const muted = Color(0xFF636D67);
}

RoundedSuperellipseBorder studyShape([double radius = 22]) =>
    RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));

TextStyle display(
  double size, {
  Color? color,
  FontWeight weight = FontWeight.w700,
}) => TextStyle(
  fontFamily: 'Rubik',
  fontSize: size,
  fontWeight: weight,
  height: 1.12,
  letterSpacing: -.6,
  color: color ?? StudyColor.ink,
);

Duration studyDuration(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// Raised face, visible underside, native focus and selection semantics.
class CraftButton extends StatefulWidget {
  const CraftButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.fill = StudyColor.pine,
    this.ink = Colors.white,
    this.base = StudyColor.deep,
    this.glyph,
    this.detail,
    this.selected = false,
    this.outlined = false,
    this.compact = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Color fill, ink, base;
  final String? glyph;
  final String? detail;
  final bool selected, outlined, compact;
  @override
  State<CraftButton> createState() => _CraftButtonState();
}

class _CraftButtonState extends State<CraftButton> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final fill = !enabled ? StudyColor.line : widget.fill;
    final ink = !enabled ? StudyColor.muted : widget.ink;
    final base = !enabled ? const Color(0xFFC4CCC5) : widget.base;
    final border = widget.outlined
        ? BorderSide(color: base, width: 2)
        : BorderSide.none;
    final shape = studyShape(widget.compact ? 16 : 20).copyWith(side: border);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      child: Stack(
        children: [
          Positioned.fill(
            top: 6,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: base,
                shape: studyShape(widget.compact ? 16 : 20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AnimatedContainer(
              duration: studyDuration(context, pressed ? 65 : 130),
              curve: Curves.easeOut,
              transform: Matrix4.translationValues(
                0,
                pressed && enabled ? 5 : 0,
                0,
              ),
              child: Material(
                color: fill,
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: shape,
                  onHighlightChanged: (value) =>
                      setState(() => pressed = value),
                  onTap: widget.onPressed,
                  splashColor: ink.withValues(alpha: .06),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: widget.compact ? 48 : 58,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.compact ? 14 : 18,
                        vertical: 13,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.glyph != null) ...[
                            CraftGlyph(widget.glyph!, size: 24, color: ink),
                            const SizedBox(width: 10),
                          ],
                          if (widget.detail != null) ...[
                            Container(
                              width: 24,
                              height: 24,
                              decoration: ShapeDecoration(
                                color: widget.selected ? ink : fill,
                                shape: studyShape(8).copyWith(
                                  side: BorderSide(color: base, width: 2),
                                ),
                              ),
                              child: widget.selected
                                  ? const CraftGlyph(
                                      'check',
                                      size: 20,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 14),
                          ],
                          Flexible(
                            fit: widget.detail != null
                                ? FlexFit.tight
                                : FlexFit.loose,
                            child: Column(
                              crossAxisAlignment: widget.detail != null
                                  ? CrossAxisAlignment.start
                                  : CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.label,
                                  textAlign: widget.detail != null
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  style: display(
                                    widget.compact ? 15 : 17,
                                    color: ink,
                                  ),
                                ),
                                if (widget.detail != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.detail!,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: StudyColor.muted,
                                    ),
                                  ),
                                ],
                              ],
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

class CraftGlyph extends StatelessWidget {
  const CraftGlyph(this.kind, {super.key, this.size = 30, this.color});
  final String kind;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(kind, color),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.kind, this.color);
  final String kind;
  final Color? color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32);
    final p = Paint()..color = color ?? StudyColor.pine;
    final cutout = color == Colors.white ? StudyColor.pine : StudyColor.paper;
    void rectangle(
      double x,
      double y,
      double w,
      double h, {
      Color? fill,
      double r = 2,
    }) {
      p.color = fill ?? color ?? StudyColor.pine;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
        p,
      );
    }

    switch (kind) {
      case 'office':
        rectangle(6, 7, 20, 23, fill: color ?? StudyColor.pine, r: 3);
        rectangle(12, 2, 8, 8, fill: color ?? StudyColor.yellow);
        for (final x in [10.0, 18.0]) {
          for (final y in [11.0, 17.0]) {
            rectangle(x, y, 4, 4, fill: cutout, r: .7);
          }
        }
        rectangle(13, 23, 6, 7, fill: StudyColor.yellow, r: 1);
      case 'portfolio':
        rectangle(10, 3, 12, 11, fill: color ?? StudyColor.deep, r: 4);
        rectangle(13, 6, 6, 7, fill: cutout, r: 1);
        rectangle(2, 11, 28, 19, fill: color ?? StudyColor.yellow, r: 5);
        rectangle(2, 18, 28, 3, fill: StudyColor.deep, r: 0);
        rectangle(13, 16, 6, 8, fill: cutout, r: 2);
      case 'journal':
      case 'report':
        rectangle(6, 2, 22, 28, fill: color ?? StudyColor.violet, r: 4);
        rectangle(5, 2, 4, 28, fill: StudyColor.deep, r: 1);
        for (final y in [9.0, 15.0, 21.0]) {
          rectangle(12, y, y == 21 ? 8 : 11, 3, fill: cutout, r: 1);
        }
      case 'check':
        p
          ..color = color ?? StudyColor.pine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(
          Path()
            ..moveTo(6, 16)
            ..lineTo(13, 23)
            ..lineTo(27, 8),
          p,
        );
      case 'arrow':
        p
          ..color = color ?? StudyColor.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(
          Path()
            ..moveTo(6, 16)
            ..lineTo(26, 16)
            ..moveTo(18, 8)
            ..lineTo(26, 16)
            ..lineTo(18, 24),
          p,
        );
      case 'play':
        p.color = color ?? StudyColor.ink;
        canvas.drawPath(
          Path()
            ..moveTo(10, 5)
            ..quadraticBezierTo(7, 4, 7, 8)
            ..lineTo(7, 25)
            ..quadraticBezierTo(7, 28, 10, 26)
            ..lineTo(26, 18)
            ..quadraticBezierTo(29, 16, 26, 14)
            ..close(),
          p,
        );
      case 'bell':
        p.color = color ?? StudyColor.yellow;
        canvas.drawPath(
          Path()
            ..moveTo(4, 24)
            ..lineTo(7, 19)
            ..lineTo(8, 11)
            ..quadraticBezierTo(8, 4, 16, 4)
            ..quadraticBezierTo(24, 4, 24, 11)
            ..lineTo(25, 19)
            ..lineTo(28, 24)
            ..close(),
          p,
        );
        rectangle(12, 27, 8, 3, fill: StudyColor.deep);
      case 'envelope':
        rectangle(2, 7, 28, 21, fill: color ?? StudyColor.yellow, r: 4);
        p
          ..color = StudyColor.deep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(
          Path()
            ..moveTo(3, 9)
            ..lineTo(16, 19)
            ..lineTo(29, 9),
          p,
        );
      default:
        p.color = color ?? StudyColor.yellow;
        canvas.drawCircle(const Offset(16, 16), 13, p);
        p
          ..color = StudyColor.deep
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        canvas.drawPath(
          Path()
            ..moveTo(16, 8)
            ..lineTo(16, 17)
            ..lineTo(22, 20),
          p,
        );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

class StudyPanel extends StatelessWidget {
  const StudyPanel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
    this.border = StudyColor.line,
  });
  final Widget child;
  final Color color, border;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: ShapeDecoration(
      color: color,
      shape: studyShape().copyWith(side: BorderSide(color: border, width: 1.5)),
    ),
    child: child,
  );
}
