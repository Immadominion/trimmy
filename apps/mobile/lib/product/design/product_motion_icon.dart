import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Icons8 artwork with a finite greeting on entry; hidden tabs and reduced
/// motion display the still frame. GIF artwork is only mounted while playing.
class ProductMotionIcon extends StatefulWidget {
  const ProductMotionIcon({
    super.key,
    required this.file,
    this.animatedFile,
    this.size = 28,
    this.active = true,
  });
  final String file;
  final String? animatedFile;
  final double size;
  final bool active;
  @override
  State<ProductMotionIcon> createState() => _ProductMotionIconState();
}

class _ProductMotionIconState extends State<ProductMotionIcon>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool _enabled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ProductMotionIcon old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final enabled =
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    if (enabled && !_enabled) _motion.forward(from: 0);
    if (!enabled) _motion.stop();
    _enabled = enabled;
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _motion,
      builder: (context, _) {
        final playing = _enabled && _motion.isAnimating;
        final pulse = playing ? math.sin(_motion.value * math.pi) : 0.0;
        final file = playing ? widget.animatedFile ?? widget.file : widget.file;
        return Transform.translate(
          offset: Offset(0, -2 * pulse),
          child: Transform.rotate(
            angle: widget.animatedFile != null
                ? 0
                : math.sin(_motion.value * math.pi * 4) * pulse * .07,
            child: Transform.scale(
              scale: 1 + .06 * pulse,
              child: Image.asset(
                'assets/images/ui_review/icons8/$file',
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        );
      },
    ),
  );
}
