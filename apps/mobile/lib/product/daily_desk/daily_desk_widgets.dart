import 'dart:async';
import 'package:flutter/material.dart';
import '../design/product_theme.dart';
import '../design/product_success_mark.dart';
import '../../ui_review/review_animated_splash.dart';
import 'daily_desk.dart';

class DailyDeskEntry extends StatelessWidget {
  const DailyDeskEntry({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final DailyDeskController controller;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final shift = controller.shift;
      if (shift?.complete == true) return const SizedBox.shrink();
      if (shift == null) {
        return Container(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.all(20),
          decoration: ShapeDecoration(
            color: const Color(0xFFF7F5FB),
            shape: productSquircle(26),
          ),
          child: controller.loading
              ? const Center(child: TrimmyLiquidMark(size: 38))
              : Row(
                  children: [
                    const Expanded(
                      child: Text('Today’s desk is taking a moment.'),
                    ),
                    TextButton(
                      onPressed: controller.refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Material(
            color: const Color(0xFFF2EDF9),
            shape: productSquircle(28),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Today at your desk',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF6A55A6)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            shift.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Step inside',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: const Color(0xFF6850B0),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: Color(0xFF6850B0),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ExcludeSemantics(
                      child: _DeskFloat(
                        child: Image.asset(
                          shift.portrait,
                          width: 80,
                          height: 96,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (controller.error != null)
            TextButton(
              onPressed: controller.refresh,
              child: const Text('Refresh today’s story'),
            ),
        ],
      );
    },
  );
}

/// The week is the main Career surface. Progress details live in the header sheet.
class DailyDeskJourney extends StatelessWidget {
  const DailyDeskJourney({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final DailyDeskController controller;
  final VoidCallback onOpen;
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final shift = controller.shift;
      if (shift == null) {
        return Center(
          child: controller.loading
              ? const TrimmyLiquidMark(size: 62)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Your week couldn’t load.'),
                    TextButton(
                      onPressed: controller.refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
        );
      }
      final today = DateTime.parse('${shift.date}T12:00:00Z');
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final sunday = monday.add(const Duration(days: 6));
      final range = monday.month == sunday.month
          ? '${monday.day}–${sunday.day} ${_months[sunday.month - 1]}'
          : '${monday.day} ${_months[monday.month - 1]} – ${sunday.day} ${_months[sunday.month - 1]}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(range, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Expanded(child: Text('Showing your saved week.')),
                  TextButton(
                    onPressed: controller.refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
                final height = (630.0 * scale.clamp(1.0, 2.0)).clamp(
                  constraints.maxHeight,
                  double.infinity,
                );
                return SingleChildScrollView(
                  key: const PageStorageKey('career-working-week'),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: SizedBox(
                    height: height.toDouble(),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final points = [
                          for (var i = 0; i < 7; i++)
                            Offset(i.isEven ? .22 : .78, (i + .5) / 7),
                        ];
                        return Stack(
                          key: const ValueKey('daily-week-map'),
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _WorkingWeekPath(points),
                              ),
                            ),
                            for (var i = 0; i < 7; i++)
                              _day(
                                context,
                                box,
                                points[i],
                                monday.add(Duration(days: i)),
                                shift,
                                i,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
            child: FilledButton(
              key: const ValueKey('career-current-day'),
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: ProductColor.violet,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 17,
                ),
                shape: productSquircle(24),
              ),
              child: Text(
                shift.complete ? 'Review today' : 'Open today’s desk',
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _day(
    BuildContext context,
    BoxConstraints box,
    Offset p,
    DateTime day,
    DailyShift shift,
    int index,
  ) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final date = day.toIso8601String().substring(0, 10);
    final active = date == shift.date,
        done = shift.history.contains(date),
        left = index.isEven;
    final center = Offset(p.dx * box.maxWidth, p.dy * box.maxHeight);
    final labelWidth = box.maxWidth * .51;
    final labelX = left ? center.dx + 47 : center.dx - 47 - labelWidth;
    return Positioned(
      left: 0,
      right: 0,
      top: center.dy - box.maxHeight / 14,
      height: box.maxHeight / 7,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: center.dx - 34,
            top: box.maxHeight / 14 - 32,
            child: Semantics(
              label:
                  '${weekdays[index]} ${day.day}, ${done
                      ? 'completed'
                      : active
                      ? 'today'
                      : day.isBefore(DateTime.parse(shift.date))
                      ? 'not played'
                      : 'upcoming'}',
              button: active,
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: active ? onOpen : null,
                  child: _DeskFloat(
                    enabled: active && !done,
                    child: Container(
                      width: 68,
                      height: 64,
                      padding: const EdgeInsets.fromLTRB(3, 2, 3, 7),
                      decoration: ShapeDecoration(
                        color: done
                            ? const Color(0xFF8ECBA7)
                            : active
                            ? const Color(0xFF9478D8)
                            : const Color(0xFFE7E2EF),
                        shape: productSquircle(23),
                      ),
                      child: Container(
                        decoration: ShapeDecoration(
                          color: done
                              ? const Color(0xFFE4F4E9)
                              : active
                              ? const Color(0xFFE2D7FC)
                              : const Color(0xFFFAF9FC),
                          shape: productSquircle(20),
                        ),
                        child: done
                            ? const ProductSuccessMark(size: 38)
                            : active
                            ? Padding(
                                padding: const EdgeInsets.all(3),
                                child: Image.asset(
                                  shift.portrait,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Center(
                                child: Text(
                                  '${day.day}',
                                  textScaler: TextScaler.noScaling,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFAAA0B9),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: labelX,
            width: labelWidth,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: left ? Alignment.centerLeft : Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: left
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Text(
                    active ? 'Today' : weekdays[index],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active ? ProductColor.violet : ProductColor.muted,
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(height: 5),
                    Text(
                      shift.title,
                      textAlign: left ? TextAlign.left : TextAlign.right,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ] else if (done)
                    Text(
                      'Filed',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: ProductColor.gain),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkingWeekPath extends CustomPainter {
  const _WorkingWeekPath(this.points);
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    final p = points
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 1; i < p.length; i++) {
      final middle = (p[i - 1].dy + p[i].dy) / 2;
      path.cubicTo(p[i - 1].dx, middle, p[i].dx, middle, p[i].dx, p[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFF6F2FC)
        ..strokeWidth = 23
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFEDE5F8)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_WorkingWeekPath old) => false;
}

/// Gentle breathing motion runs only while visible and respects reduced motion.
class _DeskFloat extends StatefulWidget {
  const _DeskFloat({required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<_DeskFloat> createState() => _DeskFloatState();
}

class _DeskFloatState extends State<_DeskFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _DeskFloat old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.enabled &&
        TickerMode.valuesOf(context).enabled &&
        productDuration(context, 1) != Duration.zero) {
      if (!_motion.isAnimating) _motion.repeat(reverse: true);
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: widget.child,
    builder: (context, child) => Transform.translate(
      offset: Offset(0, -3 * Curves.easeInOut.transform(_motion.value)),
      child: child,
    ),
  );
}

class DailyDeskScreen extends StatefulWidget {
  const DailyDeskScreen({
    super.key,
    required this.controller,
    required this.onCompleted,
  });
  final DailyDeskController controller;
  final Future<void> Function() onCompleted;
  @override
  State<DailyDeskScreen> createState() => _DailyDeskScreenState();
}

class _DailyDeskScreenState extends State<DailyDeskScreen> {
  late DailyShift _shift = widget.controller.shift!;
  late DeskChoice? _choice = _shift.result;
  bool _saving = false;
  String? _error;
  Future<void> _clockOut() async {
    if (_saving || _choice == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final next = await widget.controller.complete(_shift, _choice!.id);
      await widget.onCompleted();
      if (!mounted) return;
      if (next.date != _shift.date) {
        setState(() {
          _shift = next;
          _choice = next.result;
          _error = 'A new day is ready.';
        });
      } else {
        setState(() => _shift = next);
      }
    } on DailyDeskException catch (e) {
      if (e.code == 'DAY_CHANGED' || e.code == 'SHIFT_ALREADY_COMPLETE') {
        await widget.controller.refresh();
        if (mounted && widget.controller.shift != null) {
          setState(() {
            _shift = widget.controller.shift!;
            _choice = _shift.result;
            _error = e.code == 'DAY_CHANGED'
                ? 'A new day is ready.'
                : 'Today was already saved.';
          });
        }
      } else {
        if (mounted) setState(() => _error = 'Couldn’t clock out. Try again.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t clock out. Try again.');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 22, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Leave desk story',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _shift.complete ? 'Day saved' : 'Desk story · fictional',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned(
                          bottom: 10,
                          child: Container(
                            width: 160,
                            height: 62,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF3EDF9),
                              borderRadius: BorderRadius.all(
                                Radius.elliptical(80, 31),
                              ),
                            ),
                          ),
                        ),
                        _DeskFloat(
                          enabled: !_shift.complete,
                          child: Image.asset(
                            _shift.portrait,
                            height: 148,
                            width: 165,
                            fit: BoxFit.contain,
                          ),
                        ),
                        if (_shift.complete)
                          const Positioned(
                            right: 45,
                            bottom: 4,
                            child: ProductSuccessMark(size: 45),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _shift.complete ? 'See you tomorrow.' : _shift.title,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 14),
                  if (_choice == null) ...[
                    Text(
                      _shift.body,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'What’s your call?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (final choice in _shift.choices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: const Color(0xFFF6F3FB),
                          shape: productSquircle(23),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('daily-choice-${choice.id}'),
                            onTap: () => setState(() => _choice = choice),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 20,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      choice.label,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 19,
                                    color: Color(0xFF7867B1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ] else ...[
                    if (_shift.complete) ...[
                      Text(
                        '+10 Trims · Day recorded',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: ProductColor.gain),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      'You chose: ${_choice!.label}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _choice!.outcome,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: ShapeDecoration(
                        color: const Color(0xFFF3EFFA),
                        shape: productSquircle(25),
                      ),
                      child: Text(
                        _choice!.takeaway,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(height: 1.4),
                      ),
                    ),
                    if (!_shift.complete)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _choice = null),
                        child: const Text('Think it over'),
                      ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: const TextStyle(color: ProductColor.loss),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_choice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ProductColor.violet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    shape: productSquircle(24),
                  ),
                  onPressed: _saving
                      ? null
                      : _shift.complete
                      ? () => Navigator.of(context).pop(true)
                      : _clockOut,
                  child: Text(
                    _saving
                        ? 'Saving…'
                        : _shift.complete
                        ? 'Back to my desk'
                        : 'Clock out',
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
