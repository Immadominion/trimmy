import 'package:flutter/material.dart';

import 'craft.dart';
import 'update_assignment.dart';

/// Controlled, acknowledged selections. This widget never commits a draft or
/// evaluates correctness; every pinned claim receives the same treatment.
class UpdateComposer extends StatelessWidget {
  const UpdateComposer({
    super.key,
    required this.parts,
    required this.onSelect,
  });

  final Map<String, String> parts;
  final void Function(String factId, String value)? onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = updateFacts
        .where((fact) => parts[fact.id] == 'included')
        .toList(growable: false);
    // Loose notes have a stable mixed order; pinned sentences retain authored
    // order so persistence and the completed update remain deterministic.
    final available =
        const [
              'current-growth',
              'trial-result',
              'lower-profit',
              'dated-growth',
              'all-customers',
            ]
            .map((id) => updateFacts.firstWhere((fact) => fact.id == id))
            .where((fact) => parts[fact.id] != 'included');
    final media = MediaQuery.of(context);
    final immediate = media.disableAnimations || media.accessibleNavigation;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: StudyColor.violet, width: 5)),
            boxShadow: [
              BoxShadow(color: StudyColor.line, offset: Offset(3, 5)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Aster', style: display(16)),
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                child: Text(
                  '${selected.length} of 3 facts pinned',
                  key: const ValueKey('update-pin-count'),
                  style: const TextStyle(fontSize: 14, color: StudyColor.muted),
                ),
              ),
              const SizedBox(height: 10),
              for (var position = 0; position < 3; position++)
                _PinnedLine(
                  key: ValueKey('update-position-$position'),
                  position: position + 1,
                  fact: position < selected.length ? selected[position] : null,
                  immediate: immediate,
                  onRemove: onSelect == null || position >= selected.length
                      ? null
                      : () => onSelect!(selected[position].id, 'excluded'),
                ),
              if (selected.length < 3)
                _EmptyPositions(first: selected.length + 1),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text('On your desk', style: display(18)),
        const SizedBox(height: 6),
        Text(
          selected.length >= 3
              ? 'Three facts pinned. Unpin one to swap it.'
              : 'Pin three facts supported by the folder.',
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: StudyColor.muted,
          ),
        ),
        const SizedBox(height: 14),
        for (final fact in available) ...[
          _DeskFact(
            fact: fact,
            onPin: onSelect == null || selected.length >= 3
                ? null
                : () => onSelect!(fact.id, 'included'),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PinnedLine extends StatefulWidget {
  const _PinnedLine({
    super.key,
    required this.position,
    required this.fact,
    required this.immediate,
    required this.onRemove,
  });

  final int position;
  final UpdateFact? fact;
  final bool immediate;
  final VoidCallback? onRemove;

  @override
  State<_PinnedLine> createState() => _PinnedLineState();
}

class _PinnedLineState extends State<_PinnedLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arrival;

  @override
  void initState() {
    super.initState();
    _arrival = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(_PinnedLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.immediate || widget.fact == null) {
      _arrival.value = 1;
    } else if (widget.fact?.id != oldWidget.fact?.id) {
      _arrival.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fact = widget.fact;
    if (fact == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _arrival,
      builder: (context, child) => Transform.translate(
        key: ValueKey('update-position-motion-${widget.position}'),
        offset: Offset(
          0,
          5 * (1 - Curves.easeOutCubic.transform(_arrival.value)),
        ),
        child: child,
      ),
      child: Semantics(
        button: true,
        enabled: widget.onRemove != null,
        label: 'Unpin fact. ${fact.text} Source: ${fact.sourceLabel}.',
        onTap: widget.onRemove,
        child: ExcludeSemantics(
          child: TextButton(
            key: ValueKey('update-fact-${fact.id}'),
            onPressed: widget.onRemove,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 64),
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor: StudyColor.ink,
              alignment: Alignment.centerLeft,
              shape: studyShape(8),
              animationDuration: widget.immediate
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${widget.position}.',
                    style: display(16, color: StudyColor.violet),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fact.text,
                        key: ValueKey('update-pinned-${fact.id}'),
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        fact.sourceLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: StudyColor.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 23,
                    color: StudyColor.violet,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPositions extends StatelessWidget {
  const _EmptyPositions({required this.first});
  final int first;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('update-empty-positions'),
    constraints: const BoxConstraints(minHeight: 48),
    alignment: Alignment.centerLeft,
    child: Row(
      children: [
        for (var position = first; position <= 3; position++)
          Expanded(
            child: Semantics(
              label: 'Position $position empty',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Row(
                    children: [
                      Text(
                        '$position.',
                        style: display(16, color: StudyColor.muted),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: Divider(color: StudyColor.line)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _DeskFact extends StatelessWidget {
  const _DeskFact({required this.fact, required this.onPin});
  final UpdateFact fact;
  final VoidCallback? onPin;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPin != null,
    label: 'Pin fact. ${fact.text} Source: ${fact.sourceLabel}.',
    onTap: onPin,
    child: ExcludeSemantics(
      child: OutlinedButton(
        key: ValueKey('update-fact-${fact.id}'),
        onPressed: onPin,
        style: OutlinedButton.styleFrom(
          animationDuration: studyDuration(context, 220),
          minimumSize: const Size(48, 72),
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          foregroundColor: StudyColor.ink,
          backgroundColor: StudyColor.paper,
          side: const BorderSide(color: StudyColor.line),
          shape: studyShape(10),
          alignment: Alignment.centerLeft,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fact.text,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    fact.sourceLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: StudyColor.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.push_pin_outlined,
                size: 23,
                color: onPin == null ? StudyColor.muted : StudyColor.violet,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
