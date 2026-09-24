import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps the headline on the desk while its attached source is pulled over it.
///
/// Keep this widget at the same tree location/key when [sourceOpen] changes.
/// Both children are real document widgets, including their selectable text.
/// The source travels from below the headline and leaves a 12px paper edge;
/// returning to the headline reverses that same movement. Only the active
/// document participates in input and semantics. Motion never commits a choice.
class StudyDocumentDesk extends StatefulWidget {
  const StudyDocumentDesk({
    super.key,
    required this.sourceOpen,
    required this.headline,
    required this.source,
  });

  final bool sourceOpen;
  final Widget headline;
  final Widget source;

  @override
  State<StudyDocumentDesk> createState() => _StudyDocumentDeskState();
}

class _StudyDocumentDeskState extends State<StudyDocumentDesk>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.sourceOpen ? 1 : 0,
  );
  bool _immediate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _immediate = media.disableAnimations || media.accessibleNavigation;
    if (_immediate) _travel.value = widget.sourceOpen ? 1 : 0;
  }

  @override
  void didUpdateWidget(StudyDocumentDesk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sourceOpen == oldWidget.sourceOpen) return;
    final target = widget.sourceOpen ? 1.0 : 0.0;
    if (_immediate) {
      _travel.value = target;
    } else {
      // animateTo starts from the current position if the reader reverses early.
      _travel.animateTo(target, curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    clipper: const _DeskClipper(),
    child: AnimatedBuilder(
      animation: _travel,
      builder: (context, _) => _DocumentStack(
        progress: _travel.value,
        children: [
          IgnorePointer(
            ignoring: widget.sourceOpen,
            child: ExcludeFocus(
              excluding: widget.sourceOpen,
              child: ExcludeSemantics(
                excluding: widget.sourceOpen,
                child: widget.headline,
              ),
            ),
          ),
          IgnorePointer(
            ignoring: !widget.sourceOpen,
            child: ExcludeFocus(
              excluding: !widget.sourceOpen,
              child: ExcludeSemantics(
                excluding: !widget.sourceOpen,
                child: widget.source,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The headline has a small authored paper rotation. Preserve its upper/left
/// corners while still hiding the source below the desk before it is opened.
class _DeskClipper extends CustomClipper<Rect> {
  const _DeskClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-6, -6, size.width, size.height);

  @override
  bool shouldReclip(_DeskClipper oldClipper) => false;
}

class _PaperParentData extends ContainerBoxParentData<RenderBox> {}

class _DocumentStack extends MultiChildRenderObjectWidget {
  const _DocumentStack({required this.progress, required super.children});
  final double progress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDocumentStack(progress);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDocumentStack renderObject,
  ) {
    renderObject.progress = progress;
  }
}

/// Measures both papers at their final readable widths; only their offsets and
/// the desk height interpolate. Text never stretches or changes font size.
class _RenderDocumentStack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PaperParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PaperParentData> {
  _RenderDocumentStack(this._progress);

  static const _edge = 12.0;
  static const _shadow = 6.0;
  double _progress;

  set progress(double value) {
    if (_progress == value) return;
    _progress = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PaperParentData) {
      child.parentData = _PaperParentData();
    }
  }

  double _width(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth
      : constraints.constrainWidth(360);

  BoxConstraints _paperConstraints(double width, {required bool source}) =>
      BoxConstraints.tightFor(
        width: (width - _shadow - (source ? _edge : 0)).clamp(0, width),
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = _width(constraints);
    final headline = firstChild!;
    final source = childAfter(headline)!;
    final headlineSize = headline.getDryLayout(
      _paperConstraints(width, source: false),
    );
    final sourceSize = source.getDryLayout(
      _paperConstraints(width, source: true),
    );
    return constraints.constrain(
      Size(
        width,
        lerpDouble(headlineSize.height, sourceSize.height + _edge, _progress)! +
            _shadow,
      ),
    );
  }

  @override
  void performLayout() {
    final width = _width(constraints);
    final headline = firstChild!;
    final source = childAfter(headline)!;
    headline.layout(
      _paperConstraints(width, source: false),
      parentUsesSize: true,
    );
    source.layout(_paperConstraints(width, source: true), parentUsesSize: true);
    size = constraints.constrain(
      Size(
        width,
        lerpDouble(
              headline.size.height,
              source.size.height + _edge,
              _progress,
            )! +
            _shadow,
      ),
    );
    (headline.parentData! as _PaperParentData).offset = Offset.zero;
    (source.parentData! as _PaperParentData).offset = Offset(
      _edge,
      lerpDouble(headline.size.height + 16, _edge, _progress)!,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final headline = firstChild!;
    context.paintChild(headline, offset);
    if (_progress > 0) {
      final source = childAfter(headline)!;
      context.paintChild(
        source,
        offset + (source.parentData! as _PaperParentData).offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = (child.parentData! as _PaperParentData).offset;
    transform.multiply(Matrix4.translationValues(offset.dx, offset.dy, 0));
  }
}
