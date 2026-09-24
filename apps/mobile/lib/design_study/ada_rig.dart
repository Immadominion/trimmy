import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'ada_rig_data.dart';

/// Semantic reactions only. Artwork cannot submit answers or award progress.
enum AdaBeat { listening, reading, thinking, correction, complete }

/// Continuous controls, independent of the artwork's path geometry.
@immutable
class AdaRigPose {
  const AdaRigPose({
    this.headRotation = 0,
    this.headY = 0,
    this.gaze = Offset.zero,
    this.eyeOpen = 1,
    this.gestureRotation = 0,
  });

  final double headRotation;
  final double headY;
  final Offset gaze;
  final double eyeOpen;
  final double gestureRotation;

  static AdaRigPose forBeat(AdaBeat beat) => switch (beat) {
    AdaBeat.listening => const AdaRigPose(),
    AdaBeat.reading => const AdaRigPose(
      headRotation: .032,
      headY: .8,
      gaze: Offset(-.45, 1),
    ),
    AdaBeat.thinking => const AdaRigPose(
      headRotation: -.025,
      headY: -.4,
      gaze: Offset(.6, -.8),
    ),
    AdaBeat.correction => const AdaRigPose(
      headRotation: .018,
      gaze: Offset(-.25, 0),
      gestureRotation: -.045,
    ),
    AdaBeat.complete => const AdaRigPose(gaze: Offset(-.2, 0)),
  };

  static double _ease(double t, double start, double end) {
    final x = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  /// Gaze leads the head; one blink/nod follows, then every control holds.
  static AdaRigPose reaction(AdaRigPose from, AdaBeat beat, double time) {
    final target = forBeat(beat);
    if (time >= 1) return target;
    final head = _ease(time, 0, .68);
    final eyes = _ease(time, 0, .30);
    final gesture = _ease(time, 0, .60);
    final blink = _ease(time, .49, .55) - _ease(time, .58, .68);
    final nod = beat == AdaBeat.complete
        ? _ease(time, .12, .30) - _ease(time, .34, .68)
        : 0.0;
    final offer = beat == AdaBeat.correction
        ? _ease(time, 0, .16) - _ease(time, .20, .60)
        : 0.0;
    return AdaRigPose(
      headRotation:
          _mix(from.headRotation, target.headRotation, head) + nod * .04,
      headY: _mix(from.headY, target.headY, head) + nod * 1.8,
      gaze: Offset.lerp(from.gaze, target.gaze, eyes)!,
      eyeOpen: _mix(from.eyeOpen, 1, eyes) * (1 - blink),
      gestureRotation:
          _mix(from.gestureRotation, target.gestureRotation, gesture) +
          offer * .055,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdaRigPose &&
      other.headRotation == headRotation &&
      other.headY == headY &&
      other.gaze == gaze &&
      other.eyeOpen == eyeOpen &&
      other.gestureRotation == gestureRotation;

  @override
  int get hashCode =>
      Object.hash(headRotation, headY, gaze, eyeOpen, gestureRotation);
}

Path _path(List<dynamic> commands, {double Function(double, double)? mapY}) {
  final result = Path();
  for (final raw in commands) {
    final command = raw as List<dynamic>;
    double n(int index) => (command[index] as num).toDouble();
    double y(int xIndex, int yIndex) =>
        mapY?.call(n(xIndex), n(yIndex)) ?? n(yIndex);
    switch (command[0]) {
      case 'M':
        result.moveTo(n(1), y(1, 2));
      case 'L':
        result.lineTo(n(1), y(1, 2));
      case 'C':
        result.cubicTo(n(1), y(1, 2), n(3), y(3, 4), n(5), y(5, 6));
      case 'Z':
        result.close();
      default:
        throw FormatException('Unsupported Ada path command ${command[0]}');
    }
  }
  return result;
}

Path _partPath(Map<String, dynamic> data) {
  var result = _path(data['maskPath'] as List<dynamic>);
  for (final excluded in data['excludePaths'] as List<dynamic>? ?? []) {
    result = Path.combine(
      PathOperation.difference,
      result,
      _path(excluded as List<dynamic>),
    );
  }
  return result;
}

Offset _point(List<dynamic> v) =>
    Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());

Rect _rect(List<dynamic> v) => Rect.fromLTWH(
  (v[0] as num).toDouble(),
  (v[1] as num).toDouble(),
  (v[2] as num).toDouble(),
  (v[3] as num).toDouble(),
);

Color _color(String v) => Color(int.parse('ff${v.substring(1)}', radix: 16));

class _Part {
  _Part(Map<String, dynamic> data)
    : id = data['id'] as String,
      parent = data['parentId'] as String?,
      path = _partPath(data),
      pivot = _point(data['pivot'] as List<dynamic>),
      color = data['fill'] == null ? null : _color(data['fill'] as String),
      opacity = (data['opacity'] as num?)?.toDouble() ?? 1 {
    final patch = data['texturePatch'] as Map<String, dynamic>?;
    if (patch != null) {
      source = _rect(patch['sourceRect'] as List<dynamic>);
      destination = _rect(patch['destinationRect'] as List<dynamic>);
    } else if (data['sourceRect'] != null) {
      source = _rect(data['sourceRect'] as List<dynamic>);
      final offset = _point(data['destinationOffset'] as List<dynamic>);
      destination = offset & source!.size;
    }
  }

  final String id;
  final String? parent;
  final Path path;
  final Offset pivot;
  final Color? color;
  final double opacity;
  Rect? source;
  Rect? destination;
}

class _Eye {
  _Eye(Map<String, dynamic> data)
    : aperture = _path(data['aperturePath'] as List<dynamic>),
      apertureCommands = data['aperturePath'] as List<dynamic>,
      upperCommands = data['upperLidPath'] as List<dynamic>,
      repair = _Part({
        'id': 'eye-repair',
        'parentId': 'head',
        'pivot': [0, 0],
        'fill': data['repair']['fallbackFill'],
        ...data['repair'] as Map<String, dynamic>,
      }),
      upper = _path(data['upperLidPath'] as List<dynamic>),
      closedBow = (data['blink']['closedBow'] as num?)?.toDouble() ?? 3,
      irisCenter = _point(data['iris']['center'] as List<dynamic>),
      irisRadius = _point([data['iris']['radiusX'], data['iris']['radiusY']]),
      gazeLimit = _point(data['iris']['maxGazeOffset'] as List<dynamic>),
      white = _color(data['whiteFill'] as String),
      ink = _color(data['iris']['fill'] as String),
      lidInk = _color(data['lidStroke'] as String),
      lidWidth = (data['lidStrokeWidth'] as num).toDouble();

  final Path aperture;
  final List<dynamic> apertureCommands;
  final List<dynamic> upperCommands;
  final _Part repair;
  final Path upper;
  final double closedBow;
  final Offset irisCenter;
  final Offset irisRadius;
  final Offset gazeLimit;
  final Color white;
  final Color ink;
  final Color lidInk;
  final double lidWidth;

  Path atOpenness(List<dynamic> commands, double open) {
    final first = upperCommands.first as List<dynamic>;
    final last = upperCommands.last as List<dynamic>;
    final a = _point(first.sublist(1));
    final b = _point(last.sublist(last.length - 2));
    return _path(
      commands,
      mapY: (x, y) {
        final t = ((x - a.dx) / (b.dx - a.dx)).clamp(0.0, 1.0);
        final closed = a.dy + (b.dy - a.dy) * t + closedBow * 4 * t * (1 - t);
        return closed + (y - closed) * open;
      },
    );
  }
}

class _Drawing {
  _Drawing(Map<String, dynamic> data)
    : parts = [
        for (final part in data['parts'] as List<dynamic>)
          _Part(part as Map<String, dynamic>),
      ],
      eyes = [
        for (final eye in data['eyes'] as List<dynamic>)
          _Eye(eye as Map<String, dynamic>),
      ];

  final List<_Part> parts;
  final List<_Eye> eyes;
  _Part get head => parts.firstWhere((part) => part.id == 'head');
}

/// Source-backed cutout parts with native, independently controlled eyes/head.
/// Body masks are compiled once; the small lid paths morph around a fixed iris.
class AdaRigPainter extends CustomPainter {
  AdaRigPainter({required this.image, required this.pose, required this.beat});

  final ui.Image image;
  final AdaRigPose pose;
  final AdaBeat beat;

  static final Map<String, _Drawing> _drawings = {
    for (final entry in adaRigData.entries)
      entry.key: _Drawing(entry.value as Map<String, dynamic>),
  };

  void _transform(Canvas canvas, _Part part, _Drawing drawing) {
    if (part.parent == 'head') _headTransform(canvas, drawing.head.pivot);
    if (part.id == 'head') _headTransform(canvas, part.pivot);
    if (part.id == 'forearm') {
      canvas.translate(part.pivot.dx, part.pivot.dy);
      canvas.rotate(pose.gestureRotation.clamp(-math.pi / 30, math.pi / 30));
      canvas.translate(-part.pivot.dx, -part.pivot.dy);
    }
  }

  void _headTransform(Canvas canvas, Offset pivot) {
    canvas.translate(pivot.dx, pivot.dy + pose.headY);
    canvas.rotate(pose.headRotation.clamp(-math.pi / 60, math.pi / 60));
    canvas.translate(-pivot.dx, -pivot.dy);
  }

  void _drawPart(Canvas canvas, _Part part) {
    canvas.save();
    canvas.clipPath(part.path);
    if (part.color != null) {
      canvas.drawPath(
        part.path,
        Paint()..color = part.color!.withValues(alpha: part.opacity),
      );
    }
    if (part.source != null) {
      canvas.drawImageRect(
        image,
        part.source!,
        part.destination!,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.restore();
  }

  void _drawEye(Canvas canvas, _Eye eye) {
    _drawPart(canvas, eye.repair);
    final open = pose.eyeOpen.clamp(0.0, 1.0);
    if (open > .001) {
      canvas.save();
      final aperture = open == 1
          ? eye.aperture
          : eye.atOpenness(eye.apertureCommands, open);
      canvas.clipPath(aperture);
      canvas.drawPath(aperture, Paint()..color = eye.white);
      final gaze = Offset(
        pose.gaze.dx.clamp(-1.0, 1.0) * eye.gazeLimit.dx,
        pose.gaze.dy.clamp(-1.0, 1.0) * eye.gazeLimit.dy,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: eye.irisCenter + gaze,
          width: eye.irisRadius.dx * 2,
          height: eye.irisRadius.dy * 2,
        ),
        Paint()..color = eye.ink,
      );
      canvas.restore();
    }
    canvas.drawPath(
      open == 1 ? eye.upper : eye.atOpenness(eye.upperCommands, open),
      Paint()
        ..color = eye.lidInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = eye.lidWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final drawing =
        _drawings[beat == AdaBeat.correction ? 'correction' : 'listening'] ??
        _drawings['listening']!;
    canvas.save();
    canvas.scale(size.width / 480, size.height / 512);
    canvas.translate(32, 0);
    for (final part in drawing.parts) {
      canvas.save();
      _transform(canvas, part, drawing);
      _drawPart(canvas, part);
      canvas.restore();
    }
    canvas.save();
    _headTransform(canvas, drawing.head.pivot);
    for (final eye in drawing.eyes) {
      _drawEye(canvas, eye);
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(AdaRigPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.pose != pose ||
      oldDelegate.beat != beat;
}
