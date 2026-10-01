import '../../ui_review/review_feedback.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import '../design/product_theme.dart';
import 'stock_facts.dart';
import 'market_craft.dart';

@immutable
class AssetChartTrade {
  const AssetChartTrade({
    required this.id,
    required this.at,
    required this.price,
    required this.shares,
    required this.buy,
  });
  final String id, shares;
  final DateTime at;
  final double price;
  final bool buy;
}

/// Timestamp-spaced samples, with a restrained curve that cannot overshoot
/// either adjacent price. Touch reads a real sample, never an invented price.
class AssetPriceChart extends StatefulWidget {
  const AssetPriceChart({
    super.key,
    required this.points,
    this.trades = const [],
  });
  final List<StockSparklinePoint> points;
  final List<AssetChartTrade> trades;
  @override
  State<AssetPriceChart> createState() => _AssetPriceChartState();
}

class _AssetPriceChartState extends State<AssetPriceChart> {
  int? _selected;
  AssetChartTrade? _selectedTrade;
  @override
  void didUpdateWidget(covariant AssetPriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.points, widget.points)) {
      _selected = null;
      _selectedTrade = null;
    }
  }

  void _select(double x, double width) {
    final points = widget.points;
    final t = (x / width).clamp(0.0, 1.0);
    final start = points.first.at.millisecondsSinceEpoch;
    final span = points.last.at.millisecondsSinceEpoch - start;
    final target = start + t * span;
    var closest = 0;
    for (var i = 1; i < points.length; i++) {
      if ((points[i].at.millisecondsSinceEpoch - target).abs() <
          (points[closest].at.millisecondsSinceEpoch - target).abs()) {
        closest = i;
      }
    }
    if (_selected != closest) {
      if (ReviewFeedback.shared.haptics) {
        ReviewFeedback.shared.impact(selection: true);
      }
      setState(() {
        _selected = closest;
        _selectedTrade = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.length < 2) return const SizedBox.shrink();
    final l10n = context.l10n;
    final formats = context.formats;
    final selected = _selected == null ? null : points[_selected!];
    final visible = <String, AssetChartTrade>{
      for (final trade in widget.trades)
        if (!trade.at.isBefore(points.first.at) &&
            !trade.at.isAfter(points.last.at) &&
            trade.price.isFinite &&
            trade.price > 0)
          trade.id: trade,
    }.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    final color = points.last.close >= points.first.close
        ? ProductColor.gain
        : ProductColor.loss;
    return Semantics(
      image: true,
      label: l10n.chartPriceLabel(
        shortPrice(points.first.close, formats),
        shortPrice(points.last.close, formats),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 30,
            // One line that shrinks rather than spill out of its 30 points
            // when a translation or large text runs long.
            child: selected == null
                ? _selectedTrade == null
                      ? null
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _tradeSummary(_selectedTrade!, l10n, formats),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${shortPrice(selected.close, formats)}   ${_date(selected.at, formats)}',
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (event) =>
                  _select(event.localPosition.dx, box.maxWidth),
              onLongPressMoveUpdate: (event) =>
                  _select(event.localPosition.dx, box.maxWidth),
              onLongPressEnd: (_) => setState(() => _selected = null),
              child: SizedBox(
                height: 214,
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        key: const ValueKey('asset-chart-paint'),
                        painter: _PricePainter(
                          points,
                          color,
                          _selected,
                          visible,
                        ),
                      ),
                    ),
                    ..._tradeMarkers(visible, box.maxWidth, l10n, formats),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _tradeMarkers(
    List<AssetChartTrade> trades,
    double width,
    AppLocalizations l10n,
    AppFormats formats,
  ) {
    final geometry = _ChartGeometry(widget.points, trades, Size(width, 214));
    // Co-located fills share one accessible hit target instead of overlapping.
    final groups = <List<AssetChartTrade>>[];
    for (final trade in trades) {
      if (groups.isNotEmpty &&
          (geometry.x(trade.at) - geometry.x(groups.last.first.at)).abs() <
              32) {
        groups.last.add(trade);
      } else {
        groups.add([trade]);
      }
    }
    return [
      for (final group in groups)
        Builder(
          builder: (context) {
            final trade = group.last;
            final mixed = group.any((t) => t.buy != trade.buy);
            final label = group
                .map((t) => _tradeLabel(t, l10n, formats))
                .join('. ');
            return Positioned(
              left: (geometry.x(trade.at) - 22).clamp(
                0.0,
                math.max(0.0, width - 44),
              ),
              top: (geometry.y(trade.price) - 22).clamp(0.0, 170.0),
              child: Semantics(
                label: label,
                button: true,
                child: Tooltip(
                  message: label,
                  child: GestureDetector(
                    key: ValueKey('chart-trade-${trade.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (ReviewFeedback.shared.haptics) {
                        ReviewFeedback.shared.impact(selection: true);
                      }
                      setState(() {
                        _selected = null;
                        _selectedTrade = trade;
                      });
                    },
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: group.length > 1 ? 30 : 23,
                          height: 23,
                          alignment: Alignment.center,
                          decoration: ShapeDecoration(
                            color: trade.buy
                                ? const Color(0xFF7460CF)
                                : const Color(0xFFE8E0F8),
                            shape: marketSquircle(9),
                          ),
                          child: Text(
                            group.length > 1
                                ? '${mixed
                                      ? ''
                                      : trade.buy
                                      ? l10n.chartTradeMarkerBuy
                                      : l10n.chartTradeMarkerSell}${group.length}'
                                : trade.buy
                                ? l10n.chartTradeMarkerBuy
                                : l10n.chartTradeMarkerSell,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: trade.buy
                                  ? Colors.white
                                  : const Color(0xFF574681),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
    ];
  }

  /// "30 Sep · 14:05" in the phone's time zone, in [formats]' language.
  String _date(DateTime utc, AppFormats formats) {
    final d = utc.toLocal();
    return '${formats.dayMonth(d)} · ${formats.time24(d)}';
  }

  /// The line shown above the chart for a tapped trade marker.
  String _tradeSummary(
    AssetChartTrade trade,
    AppLocalizations l10n,
    AppFormats formats,
  ) {
    final shares = formats.number(trade.shares);
    final price = shortPrice(trade.price, formats);
    final date = _date(trade.at, formats);
    return trade.buy
        ? l10n.chartTradeBoughtSummary(shares, price, date)
        : l10n.chartTradeSoldSummary(shares, price, date);
  }

  /// A trade marker's screen reader label and tooltip.
  String _tradeLabel(
    AssetChartTrade trade,
    AppLocalizations l10n,
    AppFormats formats,
  ) {
    final count = double.tryParse(trade.shares.replaceAll(',', '')) ?? 0;
    final shares = formats.number(trade.shares);
    final price = shortPrice(trade.price, formats);
    final date = _date(trade.at, formats);
    return trade.buy
        ? l10n.chartTradeBoughtLabel(count, shares, price, date)
        : l10n.chartTradeSoldLabel(count, shares, price, date);
  }
}

class _PricePainter extends CustomPainter {
  _PricePainter(this.points, this.color, this.selected, this.trades);
  final List<StockSparklinePoint> points;
  final Color color;
  final int? selected;
  final List<AssetChartTrade> trades;
  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _ChartGeometry(points, trades, size);
    final coords = points
        .map((p) => Offset(geometry.x(p.at), geometry.y(p.close)))
        .toList();
    final line = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (var i = 1; i < coords.length; i++) {
      final a = coords[i - 1], b = coords[i], mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(line)
      ..lineTo(coords.last.dx, size.height)
      ..lineTo(coords.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .13), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final tip = coords[selected ?? coords.length - 1];
    if (selected != null) {
      canvas.drawLine(
        Offset(tip.dx, 4),
        Offset(tip.dx, size.height),
        Paint()
          ..color = color.withValues(alpha: .18)
          ..strokeWidth = 1,
      );
    }
    canvas.drawCircle(tip, 9, Paint()..color = color.withValues(alpha: .12));
    canvas.drawCircle(tip, 4.5, Paint()..color = Colors.white);
    canvas.drawCircle(tip, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PricePainter old) =>
      old.points != points ||
      old.color != color ||
      old.selected != selected ||
      old.trades != trades;
}

class _ChartGeometry {
  _ChartGeometry(this.points, List<AssetChartTrade> trades, this.size) {
    final values = [
      ...points.map((p) => p.close),
      ...trades.map((t) => t.price),
    ];
    low = values.reduce(math.min);
    high = values.reduce(math.max);
    pad = high == low ? math.max(high.abs() * .01, .01) : (high - low) * .13;
  }
  final List<StockSparklinePoint> points;
  final Size size;
  late final double low, high, pad;
  double x(DateTime at) =>
      (at.millisecondsSinceEpoch - points.first.at.millisecondsSinceEpoch) /
      (points.last.at.millisecondsSinceEpoch -
          points.first.at.millisecondsSinceEpoch) *
      size.width;
  double y(double price) =>
      12 + (high + pad - price) / (high - low + 2 * pad) * (size.height - 32);
}
