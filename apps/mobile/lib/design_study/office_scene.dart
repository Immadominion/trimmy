import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'craft.dart';

const _sceneSize = Size(1448, 1086);
const _envelopeRect = Rect.fromLTWH(808, 852, 542, 198);
const _original = 'assets/images/office-scene-v4.webp';

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

final _body = _polygon(const [
  Offset(817, 903),
  Offset(1101, 860),
  Offset(1339, 945),
  Offset(1339, 953),
  Offset(960, 1035),
  Offset(817, 911),
]);
final _flap = _polygon(const [
  Offset(819, 904),
  Offset(1101, 861),
  Offset(1155, 870),
  Offset(1094, 939),
]);
final _deskPatch = _polygon(const [
  Offset(796, 890),
  Offset(1099, 840),
  Offset(1364, 935),
  Offset(1364, 969),
  Offset(958, 1060),
  Offset(795, 931),
]);
final _hand = _polygon(const [
  Offset(1009, 843),
  Offset(1032, 774),
  Offset(1070, 779),
  Offset(1138, 792),
  Offset(1164, 821),
  Offset(1177, 848),
  Offset(1199, 860),
  Offset(1186, 870),
  Offset(1167, 866),
  Offset(1155, 871),
  Offset(1135, 849),
  Offset(1117, 838),
  Offset(1094, 824),
  Offset(1060, 830),
  Offset(1074, 849),
  Offset(1067, 869),
  Offset(1034, 857),
]);

class _PathClipper extends CustomClipper<Path> {
  const _PathClipper(this.path, {this.offset = Offset.zero});
  final Path path;
  final Offset offset;
  @override
  Path getClip(Size size) => path.shift(offset);
  @override
  bool shouldReclip(_PathClipper old) =>
      old.path != path || old.offset != offset;
}

/// The room keeps the original v4 image. Only the cleared desk is composited
/// from the edited plate; original fingers occlude the separate envelope.
class OfficeScene extends StatelessWidget {
  const OfficeScene({
    super.key,
    required this.activityId,
    required this.onOpen,
    this.complete = false,
  });
  final String activityId;
  final VoidCallback? onOpen;
  final bool complete;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: FittedBox(
      fit: BoxFit.cover,
      alignment: const Alignment(.35, 0),
      child: SizedBox.fromSize(
        size: _sceneSize,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                _original,
                fit: BoxFit.fill,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: StudyColor.mint),
              ),
            ),
            Positioned.fill(
              child: ExcludeSemantics(
                child: ClipPath(
                  clipper: _PathClipper(_deskPatch),
                  child: Image.asset(
                    'assets/images/office-desk-v5.webp',
                    fit: BoxFit.fill,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: _envelopeRect,
              child: Semantics(
                button: true,
                enabled: onOpen != null,
                label: complete ? 'See what you learned' : 'Open activity',
                child: Tooltip(
                  message: complete ? 'See what you learned' : 'Open activity',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
                    child: AssignmentHero(
                      activityId: activityId,
                      envelope: true,
                      enabled: !complete,
                      child: StudyEnvelope(complete: complete),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ClipPath(
                    clipper: _PathClipper(_hand),
                    child: Image.asset(
                      _original,
                      fit: BoxFit.fill,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
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

/// Fixed source registration also supplies the opening flap during the flight.
class StudyEnvelope extends StatelessWidget {
  const StudyEnvelope({super.key, this.openness = 0, this.complete = false});
  final double openness;
  final bool complete;

  Widget _texture(Path path) => ClipPath(
    clipper: _PathClipper(path, offset: -_envelopeRect.topLeft),
    child: OverflowBox(
      alignment: Alignment.topLeft,
      maxWidth: _sceneSize.width,
      maxHeight: _sceneSize.height,
      child: Transform.translate(
        offset: -_envelopeRect.topLeft,
        child: Image.asset(
          _original,
          width: _sceneSize.width,
          height: _sceneSize.height,
          fit: BoxFit.fill,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final transform = Matrix4.identity()
      ..setEntry(3, 2, .001)
      ..translateByDouble(11, 52, 0, 1)
      ..rotateZ(-.101)
      ..rotateX(-math.pi * .87 * openness)
      ..rotateZ(.101)
      ..translateByDouble(-11, -52, 0, 1);
    return ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.fromSize(
          size: _envelopeRect.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: CustomPaint(painter: _EnvelopeBase())),
              Positioned.fill(
                child: _texture(
                  Path.combine(PathOperation.difference, _body, _flap),
                ),
              ),
              Positioned.fill(
                child: Transform(transform: transform, child: _texture(_flap)),
              ),
              Positioned(
                left: 300,
                top: 89,
                child: Transform.rotate(
                  angle: -.17,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: ShapeDecoration(
                      color: StudyColor.pine,
                      shape: studyShape(18),
                    ),
                    child: Center(
                      child: CraftGlyph(
                        complete ? 'check' : 'arrow',
                        size: 35,
                        color: StudyColor.paper,
                      ),
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

class _EnvelopeBase extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _body.shift(-_envelopeRect.topLeft);
    canvas.drawShadow(path, const Color(0xAA251E24), 8, false);
    canvas.drawPath(path, Paint()..color = const Color(0xFFE2A820));
    canvas.drawPath(
      _flap.shift(-_envelopeRect.topLeft),
      Paint()..color = const Color(0xFFC88B16),
    );
  }

  @override
  bool shouldRepaint(_EnvelopeBase old) => false;
}

/// Acknowledged navigation drives the flight; no awaited decorative timer.
/// Resumed later steps and Journal replays keep their ordinary route transition.
class AssignmentHero extends StatelessWidget {
  const AssignmentHero({
    super.key,
    required this.activityId,
    required this.child,
    this.envelope = false,
    this.enabled = true,
  });
  final String activityId;
  final Widget child;
  final bool envelope;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!enabled || media.disableAnimations || media.accessibleNavigation) {
      return child;
    }
    return Hero(
      tag: 'assignment-$activityId',
      transitionOnUserGestures: false,
      flightShuttleBuilder: (flightContext, animation, direction, from, to) {
        final destination = direction == HeroFlightDirection.push ? to : from;
        final hero = destination.widget as Hero;
        final target = (destination.findRenderObject()! as RenderBox).size;
        return _AssignmentFlight(
          animation: animation,
          direction: direction,
          paper: hero.child,
          targetSize: target,
        );
      },
      child: child,
    );
  }
}

class _AssignmentFlight extends StatelessWidget {
  const _AssignmentFlight({
    required this.animation,
    required this.direction,
    required this.paper,
    required this.targetSize,
  });
  final Animation<double> animation;
  final HeroFlightDirection direction;
  final Widget paper;
  final Size targetSize;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // The route's own animation runs 0→1 on push and 1→0 on pop.
          final t = animation.value;
          final paperIn = Curves.easeOutCubic.transform(
            ((t - .12) / .7).clamp(0.0, 1.0),
          );
          final envelopeOut = ((t - .45) / .4).clamp(0.0, 1.0);
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: 1 - envelopeOut,
                    child: FractionalTranslation(
                      translation: Offset(0, t * .7),
                      child: StudyEnvelope(openness: (t / .55).clamp(0.0, 1.0)),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: paperIn,
                    child: FractionalTranslation(
                      translation: Offset(0, .24 * (1 - paperIn)),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox.fromSize(
                          size: targetSize,
                          child: paper,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
