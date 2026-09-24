import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'review_components.dart';
import 'review_feedback.dart';
import 'ui_review_app.dart';

/// A paper object placed on a quiet, lightly ruled surface. The words remain
/// Flutter text so the note can scale for accessibility and localization.
class ReviewWelcomeNotePage extends StatefulWidget {
  const ReviewWelcomeNotePage({
    super.key,
    required this.onSkip,
    required this.onContinue,
  });

  final VoidCallback onSkip, onContinue;

  @override
  State<ReviewWelcomeNotePage> createState() => _ReviewWelcomeNotePageState();
}

class _ReviewWelcomeNotePageState extends State<ReviewWelcomeNotePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..addListener(_onFrame);
  bool _started = false;
  bool _reducedMotion = false;
  bool _landed = false;

  void _onFrame() {
    if (_landed || _reducedMotion || _drop.value < .62) return;
    _landed = true;
    ReviewFeedback.shared.impact();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _reducedMotion = media.disableAnimations || media.accessibleNavigation;
    if (_reducedMotion) {
      _drop.value = 1;
    } else if (!_started) {
      _started = true;
      _drop.forward();
    }
  }

  @override
  void dispose() {
    _drop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: CustomPaint(
      painter: const _PaperSurfacePainter(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Skip introduction',
                  onPressed: widget.onSkip,
                  icon: const Icon(Icons.close_rounded, size: 29),
                  color: UiReviewColor.ink,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 390),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: AnimatedBuilder(
                              animation: _drop,
                              builder: (context, _) =>
                                  _PinnedNote(progress: _drop.value),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  ReviewFeedback.shared.press();
                  widget.onContinue();
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4D36B6),
                  minimumSize: const Size.fromHeight(58),
                  textStyle: const TextStyle(
                    fontFamily: reviewDisplay,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PinnedNote extends StatelessWidget {
  const _PinnedNote({required this.progress});

  final double progress;

  double _ease(double start, double end, Curve curve) =>
      curve.transform(((progress - start) / (end - start)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final fall = _ease(0, .62, Curves.easeInCubic);
    final settle = _ease(.62, .86, Curves.easeOutCubic);
    final noteY = progress < .62 ? -122 + 129 * fall : 7 * (1 - settle);
    final noteAngle = progress < .62 ? -.12 + .15 * fall : .03 - .055 * settle;
    final pinFall = _ease(.49, .82, Curves.easeInCubic);
    final pinSettle = _ease(.82, 1, Curves.easeOutCubic);
    final pinY = progress < .82 ? -58 + 62 * pinFall : 4 * (1 - pinSettle);
    final arrowIn = _ease(.66, 1, Curves.easeOutCubic);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 139, left: 9, right: 9),
          child: Transform.translate(
            offset: Offset(0, noteY),
            child: Transform.rotate(
              angle: noteAngle,
              alignment: Alignment.topCenter,
              child: Opacity(
                opacity: _ease(0, .17, Curves.easeIn),
                child: const _NoteCard(),
              ),
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 0,
          child: Transform.translate(
            offset: Offset(-12 * (1 - arrowIn), -14 * (1 - arrowIn)),
            child: Opacity(
              opacity: arrowIn,
              child: Transform.rotate(
                angle: 322,
                child: ExcludeSemantics(
                  child: Image.asset(
                    'assets/images/ui_review/curly-arrow.png',
                    width: 136,
                    height: 136,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 47,
          top: 119,
          child: Transform.translate(
            offset: Offset(0, pinY),
            child: Transform.rotate(
              angle: .26 - .14 * (1 - pinFall),
              child: Opacity(
                opacity: _ease(.45, .63, Curves.easeIn),
                child: ExcludeSemantics(
                  child: Image.asset(
                    'assets/images/ui_review/ruby-pin-1.png',
                    width: 44,
                    height: 46,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard();

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 340),
    child: Material(
      color: Colors.white,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0xFFECEAF1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 308),
          child: Material(
            color: const Color(0xFFF1EDFF),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(23, 23, 23, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '01',
                    style: TextStyle(
                      color: Color(0xFF75639E),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Text(
                    'Welcome to\nthe floor.',
                    style: TextStyle(
                      fontFamily: reviewDisplay,
                      color: UiReviewColor.ink,
                      fontSize: 31,
                      height: 1.04,
                      letterSpacing: -1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Your first day starts with practice.\n\nPick a company. It’s free.',
                    style: TextStyle(
                      color: UiReviewColor.ink,
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PaperSurfacePainter extends CustomPainter {
  const _PaperSurfacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..strokeWidth = .65
      ..color = const Color(0xFFEBEAF0).withValues(alpha: .5);
    for (var y = 110.0; y < size.height - 45; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
    final random = math.Random(2309);
    final grain = Paint()
      ..color = const Color(0xFF9F99A6).withValues(alpha: .08);
    final count = (size.width * size.height / 2600).round();
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        .25 + random.nextDouble() * .25,
        grain,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperSurfacePainter oldDelegate) => false;
}
