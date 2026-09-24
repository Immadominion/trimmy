import 'package:flutter/material.dart';

import 'product_theme.dart';

enum ProductCastMember { sal, wolf, oracle, shark }

extension ProductCastMemberDetails on ProductCastMember {
  String get assetPath =>
      'assets/images/cast/${name.toLowerCase()}-neutral-v2.png';

  String get semanticName => switch (this) {
    ProductCastMember.sal => 'Sal, your floor boss',
    ProductCastMember.wolf => 'The Wolf trader portrait',
    ProductCastMember.oracle => 'The Oracle trader portrait',
    ProductCastMember.shark => 'The Shark trader portrait',
  };

  Color get backgroundColor => switch (this) {
    ProductCastMember.sal => ProductColor.yellow,
    ProductCastMember.wolf => const Color(0xFFFFD76A),
    ProductCastMember.oracle => ProductColor.mint,
    ProductCastMember.shark => const Color(0xFFE7DDFF),
  };
}

/// A consistently framed production portrait for the named Trimmy cast member.
class CastPortrait extends StatelessWidget {
  const CastPortrait({
    super.key,
    required this.member,
    required this.size,
    this.semanticLabel,
    this.backgroundColor,
    this.radius,
    this.borderWidth = 0,
    this.imageScale = 1,
  });

  final ProductCastMember member;
  final double size;
  final String? semanticLabel;
  final Color? backgroundColor;
  final double? radius;
  final double borderWidth;
  final double imageScale;

  @override
  Widget build(BuildContext context) {
    final portraitRadius = radius ?? size * .31;
    final outerShape = productSquircle(portraitRadius).copyWith(
      side: borderWidth <= 0
          ? BorderSide.none
          : BorderSide(color: ProductColor.ink, width: borderWidth),
    );
    final innerShape = productSquircle(
      (portraitRadius - borderWidth).clamp(0, portraitRadius),
    );

    return Semantics(
      image: true,
      label: semanticLabel ?? member.semanticName,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: backgroundColor ?? member.backgroundColor,
              shape: outerShape,
            ),
            child: Padding(
              padding: EdgeInsets.all(borderWidth),
              child: ClipPath(
                clipper: ShapeBorderClipper(shape: innerShape),
                child: ColoredBox(
                  color: backgroundColor ?? member.backgroundColor,
                  child: Transform.scale(
                    scale: imageScale,
                    alignment: Alignment.topCenter,
                    child: Image.asset(
                      member.assetPath,
                      key: ValueKey('cast-portrait-${member.name}'),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
