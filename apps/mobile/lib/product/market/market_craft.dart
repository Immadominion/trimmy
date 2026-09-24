import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../design/paper_format.dart';
import '../design/product_theme.dart';

abstract final class MarketPalette {
  static const paper = Color(0xFFFFFFFF);
  static const white = Color(0xFFFFFFFF);
  static const ink = ProductColor.ink;
  static const pine = Color(0xFF006344);
  static const deepPine = Color(0xFF003F35);
  static const mint = Color(0xFFE0EFE5);
  static const yellow = Color(0xFFF3BB2C);
  static const pink = Color(0xFFEF4B77);
  static const violet = ProductColor.violet;
  static const line = ProductColor.line;
  static const muted = ProductColor.muted;
  static const loss = Color(0xFF9F3045);
  static const softLoss = Color(0xFFFFE9DF);
}

RoundedSuperellipseBorder marketSquircle([double radius = 24]) =>
    RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));

String signedPercent(double value) {
  if (value == 0) return '0.00%';
  if (value.abs() < .01) return '${value < 0 ? '-' : '+'}<0.01%';
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(2)}%';
}

String shortPrice(double? value) {
  if (value == null || !value.isFinite) return 'Price unavailable';
  return '\$${value.toStringAsFixed(value >= 100 ? 2 : 3)}';
}

class MarketPrimaryButton extends StatelessWidget {
  const MarketPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.color = MarketPalette.violet,
    this.foreground = Colors.white,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onPressed != null && !busy,
    label: busy ? '$label in progress' : label,
    onTap: onPressed != null && !busy ? onPressed : null,
    child: ExcludeSemantics(
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: foreground,
            disabledBackgroundColor: MarketPalette.line,
            disabledForegroundColor: MarketPalette.muted,
            shape: marketSquircle(19),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : Text(label, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}

class PaperMark extends StatelessWidget {
  const PaperMark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'paper',
    image: true,
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PaperMarkPainter()),
      ),
    ),
  );
}

class PaperAmount extends StatelessWidget {
  const PaperAmount(
    this.amount, {
    super.key,
    this.style,
    this.alignment = MainAxisAlignment.start,
  });

  final String amount;
  final TextStyle? style;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final display = formatPaperForDisplay(amount);
    final effective = style ?? Theme.of(context).textTheme.titleLarge;
    final markSize = math.max(20, (effective?.fontSize ?? 20) * .92).toDouble();
    return Semantics(
      container: true,
      label: '$display paper',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignment,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PaperMark(size: markSize),
            SizedBox(width: markSize * .32),
            Flexible(child: Text(display, style: effective)),
          ],
        ),
      ),
    );
  }
}

class DirectionLabel extends StatelessWidget {
  const DirectionLabel(this.value, {super.key, this.textStyle});
  final double? value;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final change = value;
    if (change == null || !change.isFinite) {
      return Text(
        'Change unavailable',
        style: textStyle?.copyWith(color: MarketPalette.muted),
      );
    }
    final icon = change > 0
        ? Icons.arrow_upward_rounded
        : change < 0
        ? Icons.arrow_downward_rounded
        : Icons.remove_rounded;
    final color = change < 0 ? MarketPalette.loss : MarketPalette.pine;
    final label = signedPercent(change);
    return Semantics(
      label:
          '${change < 0
              ? 'Down'
              : change > 0
              ? 'Up'
              : 'Unchanged'} $label',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                style: (textStyle ?? const TextStyle()).copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
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

class CompanyLogo extends StatelessWidget {
  const CompanyLogo({
    super.key,
    required this.name,
    required this.logoUrl,
    required this.color,
    this.size = 48,
    this.fallbackAsset,
  });

  final String name;
  final String? fallbackAsset;
  final String? logoUrl;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = Center(
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: TextStyle(
          color: MarketPalette.ink,
          fontSize: size * .38,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    final fallback = fallbackAsset == null
        ? initial
        : Image.asset(
            fallbackAsset!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => initial,
          );
    return Semantics(
      label: '$name logo',
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .047),
        decoration: ShapeDecoration(
          shape: marketSquircle(size * .32),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(color, Colors.white, .7)!,
              color,
              Color.lerp(color, const Color(0xFF291D38), .35)!,
            ],
          ),
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: marketSquircle(size * .29)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Colors.white,
                child: logoUrl == null
                    ? fallback
                    : Image.network(
                        logoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => fallback,
                      ),
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0x26FFFFFF),
                        Color(0x00FFFFFF),
                        Color(0x30261937),
                      ],
                      stops: [0, .45, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MarketPanel extends StatelessWidget {
  const MarketPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = MarketPalette.white,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: color, shape: marketSquircle(24)),
    child: Padding(padding: padding, child: child),
  );
}

class _PaperMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final body = Path()
      ..moveTo(size.width * .18, size.height * .08)
      ..lineTo(size.width * .70, size.height * .08)
      ..lineTo(size.width * .90, size.height * .28)
      ..lineTo(size.width * .90, size.height * .88)
      ..quadraticBezierTo(
        size.width * .90,
        size.height,
        size.width * .78,
        size.height,
      )
      ..lineTo(size.width * .18, size.height)
      ..quadraticBezierTo(
        size.width * .06,
        size.height,
        size.width * .06,
        size.height * .88,
      )
      ..lineTo(size.width * .06, size.height * .20)
      ..quadraticBezierTo(
        size.width * .06,
        size.height * .08,
        size.width * .18,
        size.height * .08,
      )
      ..close();
    canvas.drawPath(body, Paint()..color = MarketPalette.pink);
    final fold = Path()
      ..moveTo(size.width * .70, size.height * .08)
      ..lineTo(size.width * .70, size.height * .28)
      ..lineTo(size.width * .90, size.height * .28)
      ..close();
    canvas.drawPath(fold, Paint()..color = MarketPalette.yellow);
    final line = Paint()
      ..color = MarketPalette.ink
      ..strokeWidth = math.max(1.3, size.width * .07)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * .24, size.height * .48),
      Offset(size.width * .70, size.height * .48),
      line,
    );
    canvas.drawLine(
      Offset(size.width * .24, size.height * .68),
      Offset(size.width * .58, size.height * .68),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MiniTrend extends StatelessWidget {
  const MiniTrend({
    super.key,
    required this.points,
    this.color,
    this.size = const Size(64, 34),
  });

  final List<double> points;
  final Color? color;
  final Size size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: size,
      painter: _MiniTrendPainter(points, color ?? MarketPalette.ink),
    ),
  );
}

class _MiniTrendPainter extends CustomPainter {
  _MiniTrendPainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || points.any((point) => !point.isFinite)) {
      canvas.drawLine(
        Offset(2, size.height * .62),
        Offset(size.width - 2, size.height * .62),
        Paint()
          ..color = color.withValues(alpha: .35)
          ..strokeWidth = 2,
      );
      return;
    }
    var low = points.reduce(math.min);
    var high = points.reduce(math.max);
    if ((high - low).abs() < .0001) {
      low -= 1;
      high += 1;
    }
    Offset point(int index) => Offset(
      2 + index / (points.length - 1) * (size.width - 4),
      3 + (1 - (points[index] - low) / (high - low)) * (size.height - 6),
    );
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var index = 1; index < points.length; index++) {
      final next = point(index);
      path.lineTo(next.dx, next.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniTrendPainter oldDelegate) =>
      !listEquals(oldDelegate.points, points) || oldDelegate.color != color;
}

String cashtag(String symbol) => symbol.startsWith(r'$') ? symbol : '\$$symbol';
String compactDollars(double value) {
  for (final unit in const [(1e12, 'T'), (1e9, 'B'), (1e6, 'M'), (1e3, 'K')]) {
    if (value.abs() >= unit.$1) {
      return '\$${(value / unit.$1).toStringAsFixed(2)}${unit.$2}';
    }
  }
  return '\$${value.toStringAsFixed(2)}';
}

/// Icons8 Plumpy artwork with a short native response when selected.
class MarketActionIcon extends StatelessWidget {
  const MarketActionIcon(this.name, {super.key, this.selected = false});
  final String name;
  final bool selected;
  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: selected ? 1.13 : 1,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    curve: Curves.easeOutBack,
    child: Image.asset(
      'assets/images/ui_review/icons8/asset-$name.png',
      width: 25,
      height: 25,
      color: selected ? MarketPalette.violet : null,
      excludeFromSemantics: true,
    ),
  );
}
