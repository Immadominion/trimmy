import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'craft.dart';

/// Three fictional sources, with local inspection state and no saved choices.
class UpdateEvidenceFolder extends StatefulWidget {
  const UpdateEvidenceFolder({super.key, this.reduceMotion = false});

  final bool reduceMotion;

  @override
  State<UpdateEvidenceFolder> createState() => _UpdateEvidenceFolderState();
}

class _UpdateEvidenceFolderState extends State<UpdateEvidenceFolder>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['Growth', 'Profit', 'Trial'];
  var _selected = 0;
  var _immediate = false;
  late final _arrival = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  void _updateMotion() {
    final media = MediaQuery.of(context);
    _immediate =
        widget.reduceMotion ||
        media.disableAnimations ||
        media.accessibleNavigation;
    if (_immediate) _arrival.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(UpdateEvidenceFolder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateMotion();
  }

  void _open(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    if (_immediate) {
      _arrival.value = 1;
    } else {
      _arrival.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 340.0;
          final minimum =
              84 * math.max(1, MediaQuery.textScalerOf(context).scale(15) / 15);
          final columns = ((width + 8) / (minimum + 8)).floor().clamp(1, 3);
          final tabWidth = (width - (columns - 1) * 8) / columns;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                SizedBox(
                  width: tabWidth,
                  child: Semantics(
                    selected: _selected == i,
                    child: TextButton(
                      key: ValueKey('update-tab-${_tabs[i].toLowerCase()}'),
                      onPressed: () => _open(i),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        foregroundColor: _selected == i
                            ? Colors.white
                            : StudyColor.ink,
                        backgroundColor: _selected == i
                            ? StudyColor.violet
                            : StudyColor.line,
                        shape: studyShape(12),
                        animationDuration: _immediate
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                      ),
                      child: Text(
                        _tabs[i],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
      AnimatedBuilder(
        animation: _arrival,
        builder: (context, child) => Transform.translate(
          key: const ValueKey('update-source-arrival'),
          offset: Offset(
            0,
            6 * (1 - Curves.easeOutCubic.transform(_arrival.value)),
          ),
          child: child,
        ),
        child: Container(
          key: ValueKey('update-source-${_tabs[_selected].toLowerCase()}'),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: StudyColor.violet, width: 4)),
            boxShadow: [
              BoxShadow(color: StudyColor.line, offset: Offset(3, 4)),
            ],
          ),
          child: switch (_selected) {
            0 => _growth(),
            1 => _profit(context),
            _ => _trial(),
          },
        ),
      ),
    ],
  );

  Widget _heading(String title, String date) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(header: true, child: Text(title, style: display(22))),
      const SizedBox(height: 6),
      Text(
        date,
        style: const TextStyle(
          fontSize: 13,
          height: 1.4,
          color: StudyColor.muted,
        ),
      ),
      const SizedBox(height: 18),
    ],
  );

  Widget _growth() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading('Aster user report', 'Published February 2026'),
      _pair('Year', 'Users', muted: true),
      _pair('2024', '100,000'),
      _pair('2025', '180,000', emphasis: true),
      const SizedBox(height: 16),
      Text(
        '80% growth, from 2024 to 2025.',
        style: display(18, color: StudyColor.deep),
      ),
      const SizedBox(height: 10),
      const Text(
        'The report does not measure growth in 2026.',
        style: TextStyle(fontSize: 14, height: 1.5),
      ),
    ],
  );

  Widget _profit(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(14) > 22;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Aster sales and costs', '2024 and 2025 · Simplified USD'),
        if (large) ...[
          Text('2024', style: display(18)),
          _pair('Sales', r'$1,000'),
          _pair('Costs', r'$600'),
          _pair('Profit', r'$400', emphasis: true),
          const SizedBox(height: 20),
          Text('2025', style: display(18)),
          _pair('Sales', r'$1,500'),
          _pair('Costs', r'$1,300'),
          _pair('Profit', r'$200', emphasis: true),
        ] else
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.15),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              _profitRow('', '2024', '2025', heading: true),
              _profitRow('Sales', r'$1,000', r'$1,500'),
              _profitRow('Costs', r'$600', r'$1,300'),
              _profitRow('Profit', r'$400', r'$200', emphasis: true),
            ],
          ),
        const SizedBox(height: 16),
        Text(
          r'Profit fell from $400 to $200.',
          style: display(18, color: StudyColor.deep),
        ),
        const SizedBox(height: 10),
        const Text(
          'Profit is sales minus costs.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
      ],
    );
  }

  TableRow _profitRow(
    String name,
    String before,
    String after, {
    bool heading = false,
    bool emphasis = false,
  }) => TableRow(
    decoration: emphasis
        ? const BoxDecoration(
            border: Border(top: BorderSide(color: StudyColor.ink, width: 2)),
          )
        : null,
    children: [
      for (var i = 0; i < 3; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
          child: Text(
            [name, before, after][i],
            textAlign: i == 0 ? TextAlign.start : TextAlign.end,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              fontWeight: emphasis || heading
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: heading ? StudyColor.muted : StudyColor.ink,
            ),
          ),
        ),
    ],
  );

  Widget _trial() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading('Aster product trial', 'September 2026'),
      Text('10 invited beta testers', style: display(18)),
      const SizedBox(height: 12),
      _pair('Replies', '10'),
      _pair('Liked Aster', '8'),
      _pair('Not for me', '2'),
      const SizedBox(height: 16),
      const Text(
        'All ten invited testers replied. Other customers were not asked.',
        style: TextStyle(fontSize: 14, height: 1.5),
      ),
    ],
  );

  Widget _pair(
    String label,
    String value, {
    bool muted = false,
    bool emphasis = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: emphasis ? StudyColor.yellow : StudyColor.line,
          width: emphasis ? 3 : 1,
        ),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: muted ? StudyColor.muted : StudyColor.ink,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
              fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
              color: muted ? StudyColor.muted : StudyColor.ink,
            ),
          ),
        ),
      ],
    ),
  );
}
