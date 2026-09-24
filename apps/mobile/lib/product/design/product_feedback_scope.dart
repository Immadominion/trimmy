import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import '../../ui_review/review_feedback.dart';

/// Adds quiet feedback to enabled tap controls across routes and sheets.
/// It observes pointers without joining the gesture arena: scrolling, long
/// presses, cancelled gestures and disabled controls remain silent. Explicit
/// game cues win over the generic tap cue for the same interaction.
class ProductFeedbackScope extends StatefulWidget {
  const ProductFeedbackScope({super.key, required this.child, this.feedback});
  final Widget child;
  final ReviewFeedback? feedback;
  @override
  State<ProductFeedbackScope> createState() => _ProductFeedbackScopeState();
}

class _ProductFeedbackScopeState extends State<ProductFeedbackScope> {
  ReviewFeedback get _feedback => widget.feedback ?? ReviewFeedback.shared;
  final _taps =
      <int, ({Offset start, Timer timeout, Object target, int revision})>{};

  @override
  void initState() {
    super.initState();
    unawaited(_feedback.prepareTap());
    unawaited(_feedback.prepareWork());
  }

  @override
  void dispose() {
    for (final tap in _taps.values) {
      tap.timeout.cancel();
    }
    _taps.clear();
    super.dispose();
  }

  Object? _control(PointerEvent event) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderSemanticsAnnotations &&
          target.properties.enabled != false &&
          target.properties.onTap != null) {
        return target;
      }
      if (target is RenderSemanticsGestureHandler && target.onTap != null) {
        return target;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.buttons != kPrimaryButton) return;
      final target = _control(event);
      if (target != null) {
        _taps[event.pointer] = (
          start: event.position,
          timeout: Timer(kLongPressTimeout, () => _taps.remove(event.pointer)),
          target: target,
          revision: _feedback.cueRevision,
        );
      }
    },
    onPointerMove: (event) {
      final tap = _taps[event.pointer];
      if (tap != null && (event.position - tap.start).distance > kTouchSlop) {
        _taps.remove(event.pointer)?.timeout.cancel();
      }
    },
    onPointerCancel: (event) => _taps.remove(event.pointer)?.timeout.cancel(),
    onPointerUp: (event) {
      final tap = _taps.remove(event.pointer);
      tap?.timeout.cancel();
      if (tap == null ||
          (event.position - tap.start).distance > kTouchSlop ||
          _control(event) != tap.target) {
        return;
      }
      // Gesture callbacks run after pointer dispatch. Let an explicit save,
      // selection or success cue run first, then fill only silent actions.
      scheduleMicrotask(() {
        if (mounted && _feedback.cueRevision == tap.revision) {
          _feedback.press(selection: true);
        }
      });
    },
    child: widget.child,
  );
}
