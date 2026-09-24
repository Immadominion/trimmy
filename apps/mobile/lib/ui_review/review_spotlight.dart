import 'package:flutter/material.dart';

import 'ui_review_app.dart';

/// Paints a guide over the existing layout. Targets are never cloned, so input,
/// keyboard focus and accessibility remain attached to the real controls.
class ReviewSpotlight extends StatelessWidget {
  const ReviewSpotlight({
    super.key,
    required this.enabled,
    required this.targets,
    required this.child,
    required this.scrollController,
    required this.viewportKey,
    this.fixedTargets = const [],
  });

  final bool enabled;
  final List<GlobalKey> targets, fixedTargets;
  final Widget child;
  final ScrollController scrollController;
  final GlobalKey viewportKey;

  @override
  Widget build(BuildContext context) {
    final canvasKey = GlobalKey();
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: canvasKey,
                  painter: _SpotlightPainter(
                    canvasKey: canvasKey,
                    targets: targets,
                    fixedTargets: fixedTargets,
                    viewportKey: viewportKey,
                    scrollController: scrollController,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({
    required this.canvasKey,
    required this.targets,
    required this.fixedTargets,
    required this.viewportKey,
    required ScrollController scrollController,
  }) : super(repaint: scrollController);

  final GlobalKey canvasKey, viewportKey;
  final List<GlobalKey> targets, fixedTargets;

  Rect? _rect(GlobalKey key, RenderBox canvas) {
    final target = key.currentContext?.findRenderObject();
    if (target is! RenderBox || !target.hasSize || !target.attached) {
      return null;
    }
    return canvas.globalToLocal(target.localToGlobal(Offset.zero)) &
        target.size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final box = canvasKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    var mask = Path()..addRect(Offset.zero & size);
    final viewport = _rect(viewportKey, box) ?? (Offset.zero & size);
    for (final key in [...targets, ...fixedTargets]) {
      final rect = _rect(key, box);
      if (rect == null) continue;
      final cutout = rect
          .inflate(fixedTargets.contains(key) ? 0 : 6)
          .intersect(
            fixedTargets.contains(key) ? (Offset.zero & size) : viewport,
          );
      if (cutout.isEmpty) continue;
      mask = Path.combine(
        PathOperation.difference,
        mask,
        RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(
            fixedTargets.contains(key) ? 22 : 24,
          ),
        ).getOuterPath(cutout),
      );
    }
    canvas.drawPath(
      mask,
      Paint()..color = UiReviewColor.ink.withValues(alpha: .48),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) => true;
}

/// Repeating forward/back cue while guidance is visible. Reduced motion holds still.
class ReviewGuideCue extends StatefulWidget {
  const ReviewGuideCue({super.key, required this.text});
  final String text;
  @override
  State<ReviewGuideCue> createState() => _ReviewGuideCueState();
}

class _ReviewGuideCueState extends State<ReviewGuideCue>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (uiReviewDuration(context, 1) == Duration.zero) {
      _motion.stop();
      _motion.value = 0;
    } else if (!_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              widget.text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: UiReviewColor.violet,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        AnimatedBuilder(
          animation: _motion,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              0,
              Curves.easeInOutSine.transform(_motion.value) * 7,
            ),
            child: child,
          ),
          child: const ExcludeSemantics(
            child: CustomPaint(size: Size(42, 36), painter: _GuideArrow()),
          ),
        ),
      ],
    ),
  );
}

class _GuideArrow extends CustomPainter {
  const _GuideArrow();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = UiReviewColor.violet
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(4, 5)
        ..cubicTo(28, 1, 33, 14, 27, 30)
        ..moveTo(19, 21)
        ..lineTo(27, 30)
        ..lineTo(37, 24),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_GuideArrow oldDelegate) => false;
}
