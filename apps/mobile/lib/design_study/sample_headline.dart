import 'package:flutter/material.dart';

import 'craft.dart';

/// A composed claim, rather than a list of complete multiple-choice answers.
/// The parent supplies acknowledged selections; this view keeps no draft state.
class SampleHeadline extends StatelessWidget {
  const SampleHeadline({
    super.key,
    required this.parts,
    required this.onSelect,
  });

  final Map<String, String> parts;
  final void Function(String part, String value)? onSelect;

  String get _amount => switch (parts['amount']) {
    'eight-of-ten' => '8 of 10',
    'all' => 'All',
    _ => '___',
  };
  String get _group => switch (parts['group']) {
    'testers' => 'beta testers',
    'customers' => 'customers',
    _ => '___',
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: StudyColor.pink, width: 6)),
          boxShadow: [BoxShadow(color: StudyColor.line, offset: Offset(3, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your headline',
              style: TextStyle(fontSize: 12, color: StudyColor.muted),
            ),
            const SizedBox(height: 14),
            Semantics(
              liveRegion: true,
              label:
                  'Your headline: ${parts.containsKey('amount') ? _amount : 'choose how many'}, ${parts.containsKey('group') ? _group : 'choose the group'}, liked Aster.',
              child: ExcludeSemantics(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _amount,
                        style: TextStyle(
                          color: parts.containsKey('amount')
                              ? StudyColor.pine
                              : StudyColor.muted,
                          decoration: TextDecoration.underline,
                          decorationColor: StudyColor.yellow,
                        ),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: _group,
                        style: TextStyle(
                          color: parts.containsKey('group')
                              ? StudyColor.pine
                              : StudyColor.muted,
                          decoration: TextDecoration.underline,
                          decorationColor: StudyColor.pink,
                        ),
                      ),
                      const TextSpan(text: ' liked Aster.'),
                    ],
                  ),
                  style: display(28),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Choose both parts, then submit.',
              style: TextStyle(fontSize: 13, color: StudyColor.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      _choices(context, 'How many?', 'amount', const [
        ('eight-of-ten', '8 of 10'),
        ('all', 'All'),
      ]),
      const SizedBox(height: 22),
      _choices(context, 'Who was asked?', 'group', const [
        ('testers', 'beta testers'),
        ('customers', 'customers'),
      ]),
    ],
  );

  Widget _choices(
    BuildContext context,
    String heading,
    String part,
    List<(String, String)> options,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(heading, style: display(18)),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(15) > 22;
          Widget option((String, String) item) {
            final selected = parts[part] == item.$1;
            return CraftButton(
              key: ValueKey('sample-$part-${item.$1}'),
              label: item.$2,
              compact: true,
              selected: selected,
              outlined: true,
              fill: selected ? StudyColor.mint : Colors.white,
              ink: selected ? StudyColor.pine : StudyColor.ink,
              base: selected ? StudyColor.pine : StudyColor.line,
              onPressed: onSelect == null
                  ? null
                  : () => onSelect!(part, item.$1),
            );
          }

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                option(options.first),
                const SizedBox(height: 10),
                option(options.last),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: option(options.first)),
              const SizedBox(width: 10),
              Expanded(child: option(options.last)),
            ],
          );
        },
      ),
    ],
  );
}
