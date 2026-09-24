import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_study/craft.dart';
import 'history_models.dart';
import 'stock_research_controller.dart';
import 'validation.dart';

enum StockHistoryPeriod {
  day('1 day', 1, StockHistoryInterval.oneHour),
  week('1 week', 7, StockHistoryInterval.fourHours),
  month('1 month', 30, StockHistoryInterval.oneDay);

  const StockHistoryPeriod(this.label, this.days, this.interval);
  final String label;
  final int days;
  final StockHistoryInterval interval;

  StockHistoryRequest requestAt(DateTime now) {
    final seconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final end = seconds ~/ interval.seconds * interval.seconds;
    return StockHistoryRequest.appleAaplx(
      interval: interval,
      fromUnixSeconds: '${end - days * 86400}',
      toUnixSeconds: '$end',
    );
  }
}

/// A deliberately relative chart: this provider contract does not declare a
/// currency unit. Derived percentages are display approximations, never quotes.
final class StockHistoryPlot {
  StockHistoryPlot._(this.points, this.intervalSeconds);
  final List<({int time, double change})> points;
  final int intervalSeconds;

  static StockHistoryPlot? fromPage(StockHistoryPage page) {
    if (page.candles.length < 2) return null;
    final first = double.tryParse(page.candles.first.closeRaw);
    if (first == null || !first.isFinite || first <= 0) return null;
    final points = <({int time, double change})>[];
    for (final candle in page.candles) {
      final value = double.tryParse(candle.closeRaw);
      if (value == null || !value.isFinite || value <= 0) return null;
      final change = (value / first - 1) * 100;
      if (!change.isFinite) return null;
      points.add((time: int.parse(candle.startUnixSeconds), change: change));
    }
    return StockHistoryPlot._(List.unmodifiable(points), page.interval.seconds);
  }

  bool get hasGaps {
    for (var index = 1; index < points.length; index++) {
      if (points[index].time - points[index - 1].time > intervalSeconds) {
        return true;
      }
    }
    return false;
  }

  String changeLabel(int index) {
    final change = points[index].change;
    if (change == 0) return '0.00%';
    if (change.abs() < .01) return '${change < 0 ? '-' : '+'}<0.01%';
    return '${change > 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
  }
}

/// The Apple xStock detail view is opened by an explicit user action. Opening
/// that view requests a week once; lifecycle changes never trigger a refresh.
class StockHistoryPanel extends StatefulWidget {
  const StockHistoryPanel({super.key, required this.controller, this.now});
  final StockResearchController controller;
  final DateTime Function()? now;

  @override
  State<StockHistoryPanel> createState() => _StockHistoryPanelState();
}

class _StockHistoryPanelState extends State<StockHistoryPanel> {
  StockHistoryPeriod _period = StockHistoryPeriod.week;
  StockHistoryRequest? _request;
  String? _refused;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    // Avoid notifying a listening ancestor during its build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(_period);
    });
  }

  @override
  void didUpdateWidget(covariant StockHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
    _generation++;
    _request = null;
    _refused = null;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load(StockHistoryPeriod period) async {
    final generation = ++_generation;
    try {
      final request = period.requestAt((widget.now ?? DateTime.now)());
      setState(() {
        _period = period;
        _request = request;
        _refused = null;
      });
      await widget.controller.loadTokensHistory(request);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _refused = _issue(
          error is StockResearchException ? error.code : null,
        ),
      );
    }
  }

  static String _issue(String? code) => switch (code) {
    'STOCK_RESEARCH_RUNTIME_OFFLINE' =>
      'You are offline. Try again when you are connected.',
    'STOCK_HISTORY_RATE_LIMITED' =>
      'Please wait a moment before checking again.',
    'STOCK_HISTORY_TIMEOUT' => 'The history took too long to load. Try again.',
    'STOCK_RESEARCH_RUNTIME_BACKGROUND' =>
      'The check paused while the app was away.',
    'STOCK_HISTORY_UNAVAILABLE' || 'STOCK_RESEARCH_RUNTIME_DISABLED' =>
      'Price history is not available right now.',
    _ => 'We could not load this history. Try again.',
  };

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.tokensHistoryState;
    final matching = state.requestKey == _request && _request != null;
    final page = matching ? state.data : null;
    final loading = matching && state.phase == StockResearchReadPhase.loading;
    final active =
        widget.controller.state.phase == StockResearchRuntimePhase.active;
    final phase = matching ? state.phase : StockResearchReadPhase.idle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Token movement', style: display(23)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final period in StockHistoryPeriod.values)
              ChoiceChip(
                key: ValueKey('stock-history-${period.name}'),
                label: Text(period.label),
                selected: period == _period,
                onSelected: active ? (_) => _load(period) : null,
                selectedColor: StudyColor.mint,
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (loading)
          const LinearProgressIndicator(
            key: ValueKey('stock-history-loading'),
            color: StudyColor.pine,
            minHeight: 3,
          ),
        if (_refused != null) _status(_refused!, 'stock-history-refused'),
        if (phase == StockResearchReadPhase.error)
          _status(_issue(state.errorCode), 'stock-history-error'),
        if (phase == StockResearchReadPhase.stale)
          _status(
            'This is an older reading. Refresh for the latest available history.',
            'stock-history-stale',
          ),
        if (phase == StockResearchReadPhase.offline)
          _status(
            'You are offline. These are the last readings.',
            'stock-history-offline',
          ),
        if (phase == StockResearchReadPhase.background ||
            phase == StockResearchReadPhase.cancelled)
          _status(
            'The check paused. Tap refresh to try again.',
            'stock-history-paused',
          ),
        if (page != null) ...[
          if (page.candles.isEmpty)
            _status(
              'No readings for this period yet. Try a longer period.',
              'stock-history-empty',
            )
          else if (page.candles.length == 1)
            _status(
              'Only one reading is available. Try a longer period to see movement.',
              'stock-history-single',
            )
          else
            StockHistoryChart(key: ValueKey(_request), page: page),
          const SizedBox(height: 12),
          Text(
            'Checked ${_dateTime(page.provenance.observedAt)} UTC',
            style: const TextStyle(fontSize: 12, color: StudyColor.muted),
          ),
        ] else if (!loading &&
            _refused == null &&
            phase == StockResearchReadPhase.idle)
          const Text('Choose a period to see the token’s history.'),
        const SizedBox(height: 10),
        const Text(
          'Relative change in AAPLx token readings, not Apple shares. Tokens.xyz does not specify a currency.',
          style: TextStyle(fontSize: 12, color: StudyColor.muted),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('stock-history-refresh'),
            onPressed: active && !loading ? () => _load(_period) : null,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh history'),
          ),
        ),
      ],
    );
  }

  Widget _status(String text, String key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Semantics(liveRegion: true, child: Text(text, key: ValueKey(key))),
  );
}

String _dateTime(DateTime date) =>
    '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

class StockHistoryChart extends StatefulWidget {
  const StockHistoryChart({super.key, required this.page});
  final StockHistoryPage page;

  @override
  State<StockHistoryChart> createState() => _StockHistoryChartState();
}

class _StockHistoryChartState extends State<StockHistoryChart> {
  int? _selected;

  @override
  void didUpdateWidget(covariant StockHistoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.page, widget.page)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final plot = StockHistoryPlot.fromPage(widget.page);
    if (plot == null) {
      return const Text(
        'These readings cannot be compared reliably.',
        key: ValueKey('stock-history-unplottable'),
      );
    }
    final index = (_selected ?? plot.points.length - 1).clamp(
      0,
      plot.points.length - 1,
    );
    final selected = plot.points[index];
    final at = DateTime.fromMillisecondsSinceEpoch(
      selected.time * 1000,
      isUtc: true,
    );
    final label = plot.changeLabel(index);
    void selectAt(double x, double width) {
      final fraction = ((x - 8) / (width - 16)).clamp(0.0, 1.0);
      final time =
          plot.points.first.time +
          (plot.points.last.time - plot.points.first.time) * fraction;
      var nearest = 0;
      for (var candidate = 1; candidate < plot.points.length; candidate++) {
        if ((plot.points[candidate].time - time).abs() <
            (plot.points[nearest].time - time).abs()) {
          nearest = candidate;
        }
      }
      setState(() => _selected = nearest);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          label,
          key: const ValueKey('stock-history-change'),
          style: display(
            34,
            color: selected.change < 0 ? StudyColor.ink : StudyColor.pine,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_dateTime(at)} UTC · From the first reading',
          style: const TextStyle(fontSize: 12, color: StudyColor.muted),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => Semantics(
            label: 'AAPLx relative history',
            value: '$label at ${_dateTime(at)} UTC',
            increasedValue: index < plot.points.length - 1
                ? '${plot.changeLabel(index + 1)} at ${_dateTime(DateTime.fromMillisecondsSinceEpoch(plot.points[index + 1].time * 1000, isUtc: true))} UTC'
                : null,
            decreasedValue: index > 0
                ? '${plot.changeLabel(index - 1)} at ${_dateTime(DateTime.fromMillisecondsSinceEpoch(plot.points[index - 1].time * 1000, isUtc: true))} UTC'
                : null,
            onIncrease: index < plot.points.length - 1
                ? () => setState(() => _selected = index + 1)
                : null,
            onDecrease: index > 0
                ? () => setState(() => _selected = index - 1)
                : null,
            child: GestureDetector(
              key: const ValueKey('stock-history-chart'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (event) =>
                  selectAt(event.localPosition.dx, constraints.maxWidth),
              onHorizontalDragUpdate: (event) =>
                  selectAt(event.localPosition.dx, constraints.maxWidth),
              child: SizedBox(
                height: 170,
                width: double.infinity,
                child: CustomPaint(painter: _HistoryPainter(plot, index)),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _dateTime(
                  DateTime.fromMillisecondsSinceEpoch(
                    plot.points.first.time * 1000,
                    isUtc: true,
                  ),
                ),
                style: const TextStyle(fontSize: 11, color: StudyColor.muted),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _dateTime(
                  DateTime.fromMillisecondsSinceEpoch(
                    plot.points.last.time * 1000,
                    isUtc: true,
                  ),
                ),
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11, color: StudyColor.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          plot.hasGaps
              ? 'Gaps mean the provider returned no reading. Drag to explore.'
              : 'Drag across the chart to explore.',
          style: const TextStyle(fontSize: 12, color: StudyColor.muted),
        ),
      ],
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter(this.plot, this.selected);
  final StockHistoryPlot plot;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    var low = plot.points.map((point) => point.change).reduce(math.min);
    var high = plot.points.map((point) => point.change).reduce(math.max);
    if ((high - low).abs() < .001) {
      low -= .5;
      high += .5;
    }
    Offset offset(int index) => Offset(
      8 +
          (plot.points[index].time - plot.points.first.time) /
              (plot.points.last.time - plot.points.first.time) *
              (size.width - 16),
      12 +
          (1 - (plot.points[index].change - low) / (high - low)) *
              (size.height - 24),
    );
    final grid = Paint()
      ..color = StudyColor.line
      ..strokeWidth = 1;
    for (var row = 0; row < 3; row++) {
      final y = 12 + row * (size.height - 24) / 2;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), grid);
    }
    final path = Path()..moveTo(offset(0).dx, offset(0).dy);
    for (var index = 1; index < plot.points.length; index++) {
      final point = offset(index);
      if (plot.points[index].time - plot.points[index - 1].time >
          plot.intervalSeconds) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = StudyColor.pine
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    for (var index = 0; index < plot.points.length; index++) {
      canvas.drawCircle(offset(index), 2, Paint()..color = StudyColor.pine);
    }
    final point = offset(selected);
    canvas.drawLine(
      Offset(point.dx, 5),
      Offset(point.dx, size.height - 5),
      Paint()
        ..color = StudyColor.violet.withValues(alpha: .3)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(point, 7, Paint()..color = StudyColor.paper);
    canvas.drawCircle(point, 4, Paint()..color = StudyColor.violet);
  }

  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) =>
      oldDelegate.plot != plot || oldDelegate.selected != selected;
}
