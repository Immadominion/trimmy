import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/cast_portrait.dart';
import '../design/product_theme.dart';
import 'onboarding_models.dart';
import '../../ui_review/review_animated_splash.dart';

class TrimmyMark extends StatelessWidget {
  const TrimmyMark({super.key, this.size = 82});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Trimmy',
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: TrimmyLiquidMark(size: size, animate: false),
      ),
    ),
  );
}

class SalPortrait extends StatelessWidget {
  const SalPortrait({super.key, this.size = 76});

  final double size;

  @override
  Widget build(BuildContext context) => CastPortrait(
    member: ProductCastMember.sal,
    size: size,
    semanticLabel: 'Sal, your floor boss',
  );
}

class PersonaPortrait extends StatelessWidget {
  const PersonaPortrait(this.persona, {super.key, this.size = 72});

  final TraderPersona persona;
  final double size;

  @override
  Widget build(BuildContext context) => CastPortrait(
    member: switch (persona) {
      TraderPersona.wolf => ProductCastMember.wolf,
      TraderPersona.oracle => ProductCastMember.oracle,
      TraderPersona.shark => ProductCastMember.shark,
    },
    size: size,
    semanticLabel: '${persona.label} trader portrait',
    imageScale: 1.04,
  );
}

class PermissionPreview extends StatelessWidget {
  const PermissionPreview({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Preview of the phone notification permission',
    child: ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1.45,
        child: CustomPaint(painter: const _PermissionPainter()),
      ),
    ),
  );
}

class _PermissionPainter extends CustomPainter {
  const _PermissionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width / 320, size.height / 220);
    final dx = (size.width - 320 * unit) / 2;
    final dy = (size.height - 220 * unit) / 2;
    canvas
      ..translate(dx, dy)
      ..scale(unit);
    final phone = RRect.fromRectAndRadius(
      const Rect.fromLTWH(70, 4, 180, 212),
      const Radius.circular(26),
    );
    canvas.drawRRect(phone, Paint()..color = ProductColor.ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(76, 10, 168, 200),
        const Radius.circular(21),
      ),
      Paint()..color = const Color(0xFFECE8DE),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(88, 54, 144, 104),
        const Radius.circular(18),
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      const Offset(160, 78),
      13,
      Paint()..color = ProductColor.yellow,
    );
    canvas.drawRect(
      const Rect.fromLTWH(157, 69, 6, 18),
      Paint()..color = ProductColor.ink,
    );
    final line = Paint()..color = const Color(0xFFD9D5D0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(112, 101, 96, 7),
        const Radius.circular(4),
      ),
      line,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(125, 116, 70, 6),
        const Radius.circular(3),
      ),
      line,
    );
    canvas.drawLine(
      const Offset(88, 137),
      const Offset(232, 137),
      Paint()..color = const Color(0xFFE7E3DD),
    );
    canvas.drawCircle(
      const Offset(196, 147),
      4,
      Paint()..color = ProductColor.pine,
    );
    canvas.drawPath(
      Path()
        ..moveTo(259, 102)
        ..quadraticBezierTo(292, 116, 267, 146)
        ..lineTo(274, 128)
        ..moveTo(267, 146)
        ..lineTo(250, 137),
      Paint()
        ..color = const Color(0xFFE84F79)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
