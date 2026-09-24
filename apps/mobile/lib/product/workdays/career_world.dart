import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../ui_review/review_feedback.dart';
import '../../ui_review/review_animated_splash.dart';
import '../design/product_theme.dart';
import '../design/product_success_mark.dart';
import 'workdays.dart';

const careerScenery = [
  'exchange',
  'bull',
  'ticker',
  'coffee',
  'desk',
  'bell',
  'newspaper',
  'skyscraper',
  'taxi',
  'street-sign',
  'briefcase',
  'calculator',
  'reports',
  'plant',
  'clock',
  'headset',
  'pencil',
  'safe',
  'balance',
  'chart-board',
  'conference',
  'subway',
  'fountain',
  'folders',
  'magnifier',
  'mailbox',
  'lobby',
  'trophy',
  'bridge',
  'rooftop',
];
const _positions = [
  .27,
  .68,
  .51,
  .77,
  .32,
  .61,
  .24,
  .71,
  .45,
  .26,
  .73,
  .49,
  .76,
  .34,
  .59,
  .23,
  .66,
  .42,
  .74,
  .28,
];
double _x(int index) =>
    _positions[(index % _positions.length + _positions.length) %
        _positions.length];

class CareerWorld extends StatefulWidget {
  const CareerWorld({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final WorkdayController controller;
  final ValueChanged<String> onOpen;
  @override
  State<CareerWorld> createState() => _CareerWorldState();
}

class _CareerWorldState extends State<CareerWorld> {
  final _scroll = ScrollController();
  bool _positioned = false;
  @override
  void initState() {
    super.initState();
    unawaited(ReviewFeedback.shared.prepareWork());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _open(WorkAssignment? assignment) {
    final journey = widget.controller.journey!;
    ReviewFeedback.shared.workCue(WorkSound.paper);
    if (assignment != null && journey.unlocked(assignment)) {
      widget.onOpen(assignment.id);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: false,
      shape: productSquircle(30),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 16, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      assignment?.title ?? 'The next neighbourhood',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                assignment?.brief ?? 'More assignments are on the way.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (assignment != null)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(
                    'Complete day ${assignment.ordinal - 1} to open this desk.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final journey = widget.controller.journey;
      if (journey == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TrimmyLiquidMark(size: 52),
                const SizedBox(height: 16),
                Text(
                  widget.controller.loading
                      ? 'Opening your week…'
                      : 'Your assignments couldn’t load.',
                ),
                if (!widget.controller.loading)
                  TextButton(
                    onPressed: widget.controller.refresh,
                    child: const Text('Try again'),
                  ),
              ],
            ),
          ),
        );
      }
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
      final rowHeight = 300.0 + (scale - 1) * 80;
      if (!_positioned) {
        _positioned = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.jumpTo(
              math.max(
                0,
                ((journey.current?.ordinal ?? 1) - 1) * rowHeight - 24,
              ),
            );
          }
        });
      }
      return RefreshIndicator(
        onRefresh: widget.controller.refresh,
        child: ListView.builder(
          key: const PageStorageKey('career-world'),
          controller: _scroll,
          scrollCacheExtent: ScrollCacheExtent.pixels(rowHeight),
          padding: const EdgeInsets.only(bottom: 22),
          itemBuilder: (context, index) {
            final assignment = index < journey.assignments.length
                ? journey.assignments[index]
                : null;
            final active =
                assignment != null && assignment.id == journey.current?.id;
            final done = assignment?.complete ?? false;
            return SizedBox(
              height: rowHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final nodeX = (width * _x(index)).clamp(82.0, width - 82.0);
                  final labelWidth = math.min(190.0, width - 32);
                  final labelLeft = (nodeX - labelWidth / 2).clamp(
                    16.0,
                    width - labelWidth - 16,
                  );
                  final artLeft = nodeX < width / 2 ? width - 151.0 : 8.0;
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _StreetPainter(
                            index: index,
                            rowHeight: rowHeight,
                            complete: done,
                          ),
                        ),
                      ),
                      if (index % 5 == 0)
                        Positioned(
                          top: 8,
                          left: 24,
                          right: 24,
                          child: Text(
                            assignment?.district ??
                                (index == 20
                                    ? 'Beyond the first month'
                                    : 'The city keeps growing'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: ProductColor.muted),
                          ),
                        ),
                      Positioned(
                        left: artLeft,
                        top: 55,
                        width: 144,
                        height: 144,
                        child: ExcludeSemantics(
                          child: Image.asset(
                            'assets/images/career_world/${assignment?.art ?? careerScenery[index % careerScenery.length]}.png',
                            fit: BoxFit.contain,
                            cacheWidth: 380,
                          ),
                        ),
                      ),
                      if (index.isEven)
                        Positioned(
                          left: artLeft + 43,
                          top: 204,
                          width: 64,
                          height: 64,
                          child: ExcludeSemantics(
                            child: Image.asset(
                              'assets/images/career_world/${careerScenery[(index * 7 + 3) % careerScenery.length]}.png',
                              fit: BoxFit.contain,
                              cacheWidth: 180,
                            ),
                          ),
                        ),
                      Positioned(
                        left: nodeX - 42,
                        top: 91,
                        child: _DayNode(
                          number: index + 1,
                          active: active,
                          done: done,
                          released: assignment != null,
                          onTap: () => _open(assignment),
                        ),
                      ),
                      Positioned(
                        left: labelLeft,
                        top: 190,
                        width: labelWidth,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .95),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 6,
                              ),
                              child: Column(
                                children: [
                                  if (active)
                                    Text(
                                      assignment.step == 0
                                          ? 'START HERE'
                                          : 'CONTINUE',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: ProductColor.violet,
                                            letterSpacing: 1,
                                          ),
                                    ),
                                  Text(
                                    assignment?.title ?? 'Coming later',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: assignment == null
                                              ? ProductColor.muted
                                              : ProductColor.ink,
                                        ),
                                  ),
                                  if (done)
                                    const Text(
                                      'Filed',
                                      style: TextStyle(
                                        color: ProductColor.gain,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      );
    },
  );
}

class _DayNode extends StatefulWidget {
  const _DayNode({
    required this.number,
    required this.active,
    required this.done,
    required this.released,
    required this.onTap,
  });
  final int number;
  final bool active, done, released;
  final VoidCallback onTap;
  @override
  State<_DayNode> createState() => _DayNodeState();
}

class _DayNodeState extends State<_DayNode>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate();
  }

  @override
  void didUpdateWidget(covariant _DayNode old) {
    super.didUpdateWidget(old);
    _animate();
  }

  void _animate() {
    if (widget.active &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context)) {
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
    builder: (context, child) => Transform.translate(
      offset: Offset(
        0,
        widget.active ? -5 * Curves.easeInOut.transform(_motion.value) : 0,
      ),
      child: child,
    ),
    child: Semantics(
      button: true,
      label:
          'Day ${widget.number}, ${widget.done
              ? 'filed'
              : widget.active
              ? 'current assignment'
              : widget.released
              ? 'locked'
              : 'coming later'}',
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.done
                ? const Color(0xFFDDEFE5)
                : widget.active
                ? const Color(0xFF9682EE)
                : const Color(0xFFF2F0F7),
            borderRadius: BorderRadius.circular(31),
            boxShadow: [
              BoxShadow(
                color: widget.done
                    ? const Color(0xFFB4D4C2)
                    : widget.active
                    ? const Color(0xFF7160C1)
                    : const Color(0xFFE2DEEC),
                offset: const Offset(0, 6),
              ),
              if (widget.active)
                const BoxShadow(
                  color: Color(0x257867E8),
                  blurRadius: 25,
                  spreadRadius: 6,
                ),
            ],
          ),
          child: widget.done
              ? const ProductSuccessMark(size: 38)
              : widget.active
              ? Text(
                  '${widget.number}',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  widget.released
                      ? Icons.lock_outline_rounded
                      : Icons.more_horiz_rounded,
                  color: const Color(0xFFACA4BC),
                  size: 26,
                ),
        ),
      ),
    ),
  );
}

class _StreetPainter extends CustomPainter {
  const _StreetPainter({
    required this.index,
    required this.rowHeight,
    required this.complete,
  });
  final int index;
  final double rowHeight;
  final bool complete;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    double node(int i) => (size.width * _x(i)).clamp(82.0, size.width - 82.0);
    final center = Offset(node(index), 133);
    final prev = Offset(node(index - 1), 133 - rowHeight),
        next = Offset(node(index + 1), 133 + rowHeight);
    // Each segment shares its endpoints/tangents with its neighbour, but its
    // horizontal distance and bend length vary with the district.
    final bend = .32 + (index % 3) * .055;
    final priorBend = .32 + ((index - 1) % 3) * .055;
    Path segment(Offset from, Offset to, double curve) => Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
        from.dx,
        from.dy + rowHeight * curve,
        to.dx,
        to.dy - rowHeight * (1 - curve),
        to.dx,
        to.dy,
      );
    final segments = [
      segment(prev, center, priorBend),
      segment(center, next, bend),
    ];
    final path = Path()
      ..addPath(segments[0], Offset.zero)
      ..addPath(segments[1], Offset.zero);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFF5F2FB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 46
        ..strokeCap = StrokeCap.round,
    );
    for (final metric in segments.expand(
      (segment) => segment.computeMetrics(),
    )) {
      for (double distance = 0; distance < metric.length; distance += 18) {
        final point = metric.getTangentForOffset(distance)?.position;
        if (point != null) {
          canvas.drawCircle(
            point,
            2.3,
            Paint()
              ..color = complete
                  ? const Color(0xFFBDDCCB)
                  : const Color(0xFFDED4F1),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_StreetPainter old) =>
      old.index != index ||
      old.rowHeight != rowHeight ||
      old.complete != complete;
}

class WorkdayEntry extends StatelessWidget {
  const WorkdayEntry({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final WorkdayController controller;
  final ValueChanged<String> onOpen;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final current = controller.journey?.current;
      if (current == null) {
        if (controller.loading || controller.journey != null) {
          return const SizedBox.shrink();
        }
        return TextButton(
          onPressed: controller.refresh,
          child: const Text('Reload your assignment'),
        );
      }
      return Material(
        color: const Color(0xFFF4F0FC),
        shape: productSquircle(27),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onOpen(current.id),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/career_world/${current.art}.png',
                  width: 74,
                  height: 74,
                  cacheWidth: 200,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DAY ${current.ordinal} · ${current.speaker.toUpperCase()}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: ProductColor.violet,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        current.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        current.step == 0
                            ? 'Your next assignment'
                            : 'Continue your assignment',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: ProductColor.violet,
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
