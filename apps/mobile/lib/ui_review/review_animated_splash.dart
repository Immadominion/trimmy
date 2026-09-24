import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui_review_app.dart';

/// Trimmy's first authored motion beat.
///
/// The native launch screen supplies the same warm-paper first frame while the
/// Flutter engine starts. This screen then performs one finite soft-body beat,
/// resolves the programmatic wordmark, waits for [ready] when supplied, and
/// hands off to the product. It never loops.
class ReviewColdLaunchPage extends StatefulWidget {
  const ReviewColdLaunchPage({
    super.key,
    required this.onContinue,
    this.ready,
    this.autoAdvance = true,
  });

  final VoidCallback onContinue;
  final Future<void>? ready;
  final bool autoAdvance;

  @override
  State<ReviewColdLaunchPage> createState() => _ReviewColdLaunchPageState();
}

class _ReviewColdLaunchPageState extends State<ReviewColdLaunchPage>
    with SingleTickerProviderStateMixin {
  static const _fullDuration = Duration(milliseconds: 1900);
  static const _reducedDuration = Duration(milliseconds: 1050);

  late final AnimationController _controller;
  bool _started = false;
  bool _finishing = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _fullDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;

    final media = MediaQuery.of(context);
    _reducedMotion = media.disableAnimations || media.accessibleNavigation;
    _controller.duration = _reducedMotion ? _reducedDuration : _fullDuration;
    _started = true;
    unawaited(_play());
  }

  Future<void> _play() async {
    await _controller.forward();
    if (widget.autoAdvance) await _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      await widget.ready;
    } catch (_) {
      // Startup work owns its own error surface. The splash must not trap the
      // person indefinitely after the visual beat has settled.
    }
    if (mounted) widget.onContinue();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: UiReviewColor.paper,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: UiReviewColor.paper,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: UiReviewColor.paper,
    ),
    child: Scaffold(
      backgroundColor: UiReviewColor.paper,
      body: Semantics(
        label: 'Trimmy is opening',
        image: true,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -.08),
                radius: 1.05,
                colors: [Colors.white, Colors.white],
              ),
            ),
            child: Center(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = _controller.value;
                    return _SplashLockup(
                      progress: t,
                      reducedMotion: _reducedMotion,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SplashLockup extends StatelessWidget {
  const _SplashLockup({
    required this.progress,
    required this.reducedMotion,
    this.showWordmark = true,
  });
  final bool showWordmark;

  final double progress;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final logoOpacity = reducedMotion
        ? _interval(progress, 0, .42, Curves.easeOutCubic)
        : 1.0;
    final wordProgress = _interval(
      progress,
      reducedMotion ? .18 : .40,
      reducedMotion ? .58 : .70,
      Curves.easeOutCubic,
    );

    final scaleX = reducedMotion
        ? 1.0
        : _motionValue(progress, const [
            _MotionKey(0, 1, Curves.easeInOutCubic),
            _MotionKey(.10, 1.065, Curves.easeOutCubic),
            _MotionKey(.27, .965, _MotionCurve.elasticOut),
            _MotionKey(.45, 1.045, Curves.easeOutCubic),
            _MotionKey(.63, .982, Curves.easeOutCubic),
            _MotionKey(.78, 1.008, Curves.easeOutCubic),
            _MotionKey(.82, 1, Curves.easeOutCubic),
            _MotionKey(1, 1),
          ]);
    final scaleY = reducedMotion
        ? 1.0
        : _motionValue(progress, const [
            _MotionKey(0, 1, Curves.easeInOutCubic),
            _MotionKey(.10, .885, Curves.easeOutCubic),
            _MotionKey(.27, 1.085, _MotionCurve.elasticOut),
            _MotionKey(.45, .985, Curves.easeOutCubic),
            _MotionKey(.63, 1.025, Curves.easeOutCubic),
            _MotionKey(.78, .995, Curves.easeOutCubic),
            _MotionKey(.82, 1, Curves.easeOutCubic),
            _MotionKey(1, 1),
          ]);
    final lift = reducedMotion
        ? 0.0
        : _motionValue(progress, const [
            _MotionKey(0, 0, Curves.easeInOutCubic),
            _MotionKey(.10, 6, Curves.easeOutCubic),
            _MotionKey(.27, -5, _MotionCurve.elasticOut),
            _MotionKey(.45, -13, Curves.easeOutCubic),
            _MotionKey(.63, 3, Curves.easeOutCubic),
            _MotionKey(.78, -1, Curves.easeOutCubic),
            _MotionKey(.82, 0, Curves.easeOutCubic),
            _MotionKey(1, 0),
          ]);
    final rotation = reducedMotion
        ? 0.0
        : _motionValue(progress, const [
            _MotionKey(0, 0, Curves.easeInOutCubic),
            _MotionKey(.10, -.008, Curves.easeOutCubic),
            _MotionKey(.27, .012, Curves.easeOutCubic),
            _MotionKey(.45, -.032, Curves.easeOutCubic),
            _MotionKey(.63, .017, Curves.easeOutCubic),
            _MotionKey(.78, -.005, Curves.easeOutCubic),
            _MotionKey(.82, 0, Curves.easeOutCubic),
            _MotionKey(1, 0),
          ]);
    final perspectiveTilt = reducedMotion
        ? 0.0
        : math.sin(
                _interval(progress, .26, .70, Curves.easeInOutCubic) * math.pi,
              ) *
              -.075;
    final shadowScale = reducedMotion
        ? 1.0
        : _motionValue(progress, const [
            _MotionKey(0, 1, Curves.easeOutCubic),
            _MotionKey(.10, 1.08, Curves.easeOutCubic),
            _MotionKey(.27, .84, Curves.easeOutCubic),
            _MotionKey(.45, .74, Curves.easeOutCubic),
            _MotionKey(.63, 1.04, Curves.easeOutCubic),
            _MotionKey(.82, 1, Curves.easeOutCubic),
            _MotionKey(1, 1),
          ]);

    return SizedBox(
      width: 270,
      height: showWordmark ? 264 : 190,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 190,
            height: 176,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  bottom: 9,
                  child: Transform.scale(
                    scaleX: shadowScale,
                    child: Container(
                      width: 112,
                      height: 17,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: [
                          BoxShadow(
                            color: UiReviewColor.ink.withValues(
                              alpha: reducedMotion
                                  ? .11
                                  : .08 + .05 * (1 - lift.abs() / 10),
                            ),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: logoOpacity,
                  child: Transform.translate(
                    offset: Offset(0, lift),
                    child: Transform(
                      alignment: const Alignment(-.72, .78),
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, .0012)
                        ..rotateY(perspectiveTilt)
                        ..rotateZ(rotation)
                        ..scaleByDouble(scaleX, scaleY, 1, 1),
                      child: Stack(
                        children: [
                          Image.asset(
                            'assets/images/ui_review/trimmy-mark.png',
                            width: 168,
                            height: 168,
                            filterQuality: FilterQuality.high,
                          ),
                          if (!reducedMotion)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _SpecularWinkPainter(progress),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showWordmark)
            Transform.translate(
              offset: Offset(0, 8 * (1 - wordProgress)),
              child: Opacity(
                opacity: wordProgress,
                child: Text(
                  'trimmy',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: 'Bricolage Grotesque',
                    fontSize: 42,
                    height: .92,
                    letterSpacing: 4.2 + (-2.1 - 4.2) * wordProgress,
                    fontWeight: FontWeight.w800,
                    color: UiReviewColor.ink,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpecularWinkPainter extends CustomPainter {
  const _SpecularWinkPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final openness = _motionValue(progress, const [
      _MotionKey(0, 0),
      _MotionKey(.29, 0),
      _MotionKey(.38, 1, Curves.easeOutCubic),
      _MotionKey(.48, .04, Curves.easeInOutCubic),
      _MotionKey(.58, 1, Curves.easeOutCubic),
      _MotionKey(.72, 0, Curves.easeInCubic),
      _MotionKey(1, 0),
    ]);
    if (openness <= .01) return;

    final path = Path()
      ..moveTo(size.width * .31, size.height * .245)
      ..cubicTo(
        size.width * .37,
        size.height * .19,
        size.width * .48,
        size.height * .18,
        size.width * .56,
        size.height * .205,
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.3 + 4.7 * openness
      ..color = Colors.white.withValues(alpha: .16 + .54 * openness)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SpecularWinkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _MotionKey {
  const _MotionKey(this.time, this.value, [this.curve = Curves.linear]);

  final double time;
  final double value;
  final Curve curve;
}

abstract final class _MotionCurve {
  static const elasticOut = Cubic(.18, .86, .28, 1.16);
}

double _motionValue(double progress, List<_MotionKey> keys) {
  if (progress <= keys.first.time) return keys.first.value;
  if (progress >= keys.last.time) return keys.last.value;

  for (var i = 0; i < keys.length - 1; i++) {
    final start = keys[i];
    final end = keys[i + 1];
    if (progress > end.time) continue;
    final local = ((progress - start.time) / (end.time - start.time)).clamp(
      0.0,
      1.0,
    );
    final eased = start.curve.transform(local);
    return start.value + (end.value - start.value) * eased;
  }
  return keys.last.value;
}

double _interval(double value, double begin, double end, Curve curve) {
  if (value <= begin) return 0;
  if (value >= end) return 1;
  return curve.transform((value - begin) / (end - begin));
}

/// The splash's soft-body beat, with a settled pause between breaths.
/// Reduced motion uses the settled logo and creates no repeating ticker.
class TrimmyLiquidMark extends StatefulWidget {
  const TrimmyLiquidMark({super.key, this.size = 104, this.animate = true});
  final double size;
  final bool animate;
  @override
  State<TrimmyLiquidMark> createState() => _TrimmyLiquidMarkState();
}

class _TrimmyLiquidMarkState extends State<TrimmyLiquidMark>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  bool _reduced = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TrimmyLiquidMark old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    _reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    if (widget.animate && !_reduced) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Trimmy',
    child: ExcludeSemantics(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: FittedBox(
          fit: BoxFit.contain,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _SplashLockup(
              progress: widget.animate && !_reduced
                  ? (_controller.value / .6).clamp(0, 1)
                  : 1,
              reducedMotion: _reduced || !widget.animate,
              showWordmark: false,
            ),
          ),
        ),
      ),
    ),
  );
}
