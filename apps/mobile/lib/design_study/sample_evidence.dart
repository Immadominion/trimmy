import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'craft.dart';

/// Fictional source evidence. Opening a response changes no saved activity data.
///
/// Use inside the mission's scrollable body; the paper sizes to its content and
/// the response grid reflows with available width and the user's text scale.
class SampleEvidence extends StatefulWidget {
  const SampleEvidence({super.key, this.reduceMotion = false});

  final bool reduceMotion;

  @override
  State<SampleEvidence> createState() => _SampleEvidenceState();
}

class _SampleEvidenceState extends State<SampleEvidence> {
  int? _opened;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final immediate =
        widget.reduceMotion ||
        media.disableAnimations ||
        media.accessibleNavigation;
    final opened = _opened;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.white),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Aster product trial', style: display(23)),
            const SizedBox(height: 4),
            const Text(
              'September 2026',
              style: TextStyle(fontSize: 13, color: StudyColor.muted),
            ),
            const SizedBox(height: 10),
            const Text(
              '10 invited beta testers / 10 replies',
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: StudyColor.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap a reply to read it.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: StudyColor.muted,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : 308.0;
                const gap = 8.0;
                final minimum =
                    48 * math.max(1, media.textScaler.scale(14) / 14);
                final columns = ((width + gap) / (minimum + gap)).floor().clamp(
                  1,
                  5,
                );
                final cellWidth = (width - (columns - 1) * gap) / columns;
                return Wrap(
                  key: const ValueKey('sample-response-grid'),
                  spacing: gap,
                  runSpacing: 12,
                  children: [
                    for (var index = 1; index <= 10; index++)
                      SizedBox(
                        width: cellWidth,
                        child: _ResponseSlip(
                          key: ValueKey('sample-slip-$index'),
                          number: index,
                          selected: opened == index,
                          immediate: immediate,
                          onOpen: () => setState(() {
                            _opened = _opened == index ? null : index;
                          }),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (opened != null) ...[
              const SizedBox(height: 18),
              Semantics(
                container: true,
                liveRegion: true,
                child: Container(
                  key: const ValueKey('sample-opened-response'),
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    color: StudyColor.paper,
                    border: Border(
                      top: BorderSide(color: StudyColor.ink, width: 2),
                      bottom: BorderSide(color: StudyColor.line),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tester ${_number(opened)} · ${_response(opened)}',
                        style: display(18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Invited beta tester\nAster product trial · September 2026',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: StudyColor.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '8 of 10 liked Aster.',
                  style: display(17, color: StudyColor.deep),
                ),
                const Text(
                  '2 said “Not for me.”',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1, color: StudyColor.line),
            const SizedBox(height: 14),
            const Text(
              'All ten invited testers replied. Other customers were not asked.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: StudyColor.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _number(int value) => value.toString().padLeft(2, '0');
String _response(int value) => value <= 8 ? 'Liked it' : 'Not for me';

class _ResponseSlip extends StatefulWidget {
  const _ResponseSlip({
    super.key,
    required this.number,
    required this.selected,
    required this.immediate,
    required this.onOpen,
  });

  final int number;
  final bool selected;
  final bool immediate;
  final VoidCallback onOpen;

  @override
  State<_ResponseSlip> createState() => _ResponseSlipState();
}

class _ResponseSlipState extends State<_ResponseSlip>
    with SingleTickerProviderStateMixin {
  late final _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.selected ? 1 : 0,
  );
  final _focus = FocusNode();
  bool _showFocus = false;

  @override
  void didUpdateWidget(_ResponseSlip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == oldWidget.selected &&
        widget.immediate == oldWidget.immediate) {
      return;
    }
    final target = widget.selected ? 1.0 : 0.0;
    if (widget.immediate) {
      _lift.value = target;
    } else {
      _lift.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _open() {
    _focus.requestFocus();
    widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final liked = widget.number <= 8;
    final fill = widget.selected
        ? StudyColor.pine
        : liked
        ? StudyColor.mint
        : StudyColor.paper;
    final ink = widget.selected ? Colors.white : StudyColor.ink;
    final shape = studyShape(10).copyWith(
      side: BorderSide(
        color: _showFocus ? StudyColor.yellow : StudyColor.line,
        width: _showFocus ? 3 : 1,
      ),
    );
    return Semantics(
      key: ValueKey('sample-response-${_number(widget.number)}'),
      button: true,
      selected: widget.selected,
      label:
          'Tester ${_number(widget.number)}. ${_response(widget.number)}. Invited beta tester.',
      hint: widget.selected ? 'Close response slip' : 'Open response slip',
      onTap: _open,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          focusNode: _focus,
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: (value) => setState(() => _showFocus = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _open();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _open,
            child: AnimatedBuilder(
              animation: _lift,
              builder: (context, child) => Transform.translate(
                key: ValueKey('sample-lift-${_number(widget.number)}'),
                offset: Offset(0, -4 * _lift.value),
                child: child,
              ),
              child: Container(
                constraints: BoxConstraints(
                  minHeight:
                      80 + MediaQuery.textScalerOf(context).scale(12) * 2,
                  minWidth: 48,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                decoration: ShapeDecoration(
                  color: fill,
                  shape: shape,
                  shadows: [
                    BoxShadow(
                      color: widget.selected
                          ? StudyColor.deep
                          : StudyColor.line,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _number(widget.number),
                      style: display(16, color: ink),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 18,
                      width: 18,
                      child: liked
                          ? CraftGlyph('check', size: 18, color: ink)
                          : Center(
                              child: Container(
                                height: 3,
                                width: 12,
                                color: ink,
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      liked ? 'Liked' : 'Not for me',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: ink,
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
}
