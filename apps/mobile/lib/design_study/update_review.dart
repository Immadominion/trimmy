import 'package:flutter/material.dart';

import 'craft.dart';
import 'update_assignment.dart';

/// Responses are derived from the submitted draft, never from a replay's score.
String updateOfficeReply(String choiceId) {
  final facts = updateChoiceFacts(choiceId).map((fact) => fact.id).toSet();
  final year = facts.contains('current-growth');
  final group = facts.contains('all-customers');
  if (year && group) {
    return 'We corrected the year and the survey group. Your update is filed.';
  }
  if (year) {
    return 'We corrected the year before filing. Your update is on the desk.';
  }
  if (group) {
    return 'We kept the trial group clear. Your update is on the desk.';
  }
  return 'You kept all three facts in view. Your company update is filed.';
}

class UpdateDraft extends StatelessWidget {
  const UpdateDraft({
    super.key,
    required this.choiceId,
    this.filed = false,
    this.animate = false,
    this.firstSaved = false,
  });

  final String choiceId;
  final bool filed, animate, firstSaved;

  @override
  Widget build(BuildContext context) {
    final facts = updateChoiceFacts(choiceId);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: StudyColor.violet, width: 6)),
        boxShadow: [BoxShadow(color: StudyColor.line, offset: Offset(3, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            filed
                ? 'Company update'
                : firstSaved
                ? 'Your first draft'
                : 'Your draft',
            style: display(23),
          ),
          const SizedBox(height: 4),
          const Text(
            'Aster · September 2026',
            style: TextStyle(fontSize: 12, color: StudyColor.muted),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < facts.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}',
                    style: display(17, color: StudyColor.violet),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      facts[i].text,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i != facts.length - 1) const Divider(height: 1),
          ],
          if (filed) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: animate ? .86 : 1, end: 1),
                duration: animate && !MediaQuery.accessibleNavigationOf(context)
                    ? studyDuration(context, 280)
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                builder: (context, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: ShapeDecoration(
                    shape: studyShape(8).copyWith(
                      side: const BorderSide(color: StudyColor.pine, width: 2),
                    ),
                  ),
                  child: Text(
                    'Filed with Ada',
                    style: display(15, color: StudyColor.pine),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class UpdateCorrection extends StatelessWidget {
  const UpdateCorrection({super.key, required this.choiceId});
  final String choiceId;

  @override
  Widget build(BuildContext context) {
    final selected = updateChoiceFacts(choiceId).map((fact) => fact.id).toSet();
    final year = selected.contains('current-growth');
    final group = selected.contains('all-customers');
    final missing = updateFacts
        .take(3)
        .where((fact) => !selected.contains(fact.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          year && group
              ? 'Two claims go beyond the notes.'
              : 'One claim goes beyond the notes.',
          style: display(23),
        ),
        const SizedBox(height: 18),
        if (year)
          _detail(
            'Check the year',
            'The report shows growth from 2024 to 2025. It was published in 2026, but it does not measure user growth in 2026.',
          ),
        if (group)
          _detail(
            'Keep the trial group',
            'Only ten invited beta testers replied. Eight liked Aster and two did not. Other customers were not asked.',
          ),
        const SizedBox(height: 6),
        Text('Bring these facts back', style: display(19)),
        const SizedBox(height: 10),
        for (final fact in missing)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              fact.text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        const Text(
          'The filed version will include the year, profit and trial result. Your first saved draft stays in the Journal, including when you try again.',
          style: TextStyle(color: StudyColor.muted, height: 1.4),
        ),
      ],
    );
  }

  Widget _detail(String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: StudyPanel(
      color: const Color(0xFFFFE9DF),
      border: const Color(0xFFE6BAAA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: display(19)),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(height: 1.4)),
        ],
      ),
    ),
  );
}
