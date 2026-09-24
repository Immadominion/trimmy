import 'package:flutter/material.dart';

import 'activities.dart';
import 'craft.dart';

/// Evidence stays available offline and uses the same authored figures as the
/// filed note. All sources are rendered for assistive technology and review.
class NumberEvidence extends StatelessWidget {
  const NumberEvidence({super.key, required this.activity});
  final ActivityDefinition activity;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final source in activity.evidence) ...[
        Container(
          key: ValueKey('evidence-${activity.id}-${source.title}'),
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: StudyColor.violet, width: 7)),
            boxShadow: [
              BoxShadow(color: Color(0xFFDFE1DB), offset: Offset(3, 5)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(source.title, style: display(23)),
              const SizedBox(height: 16),
              for (final row in source.rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final name = Text(
                        row.$1,
                        style: const TextStyle(fontSize: 15),
                      );
                      final value = SelectableText(
                        row.$2,
                        style: display(22, color: StudyColor.pine),
                      );
                      if (constraints.maxWidth < 260 ||
                          MediaQuery.textScalerOf(context).scale(15) > 21) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [name, const SizedBox(height: 6), value],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: name),
                          const SizedBox(width: 20),
                          value,
                        ],
                      );
                    },
                  ),
                ),
              const Divider(height: 28),
              Text(
                source.explanation,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    ],
  );
}
