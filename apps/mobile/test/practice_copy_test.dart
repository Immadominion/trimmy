import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';

import '../tool/export_practice_copy.dart';

void main() {
  test(
    'released semantic copy matches actual authored definitions and declared choice order',
    () async {
      if (const bool.fromEnvironment('UPDATE_PRACTICE_COPY')) {
        await writePracticeCopy();
      }
      final file = File('../../content/practice-copy.json');
      final released =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final hash = released.remove('sha256');
      expect(hash, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(
        released,
        exportPracticeCopy(),
        reason:
            'Authored copy changed. Review the semantic diff, issue a copy revision, '
            'register its digest, then explicitly export; do not rewrite first-answer meaning under an old release.',
      );
      expect(
        studyActivities.map((activity) => activity.id),
        practiceCatalogActivityIds,
      );
      for (final activity in studyActivities) {
        final registry = practiceCatalogById[activity.id]!;
        expect(activity.title, registry.title);
        expect(activity.correctChoiceId, registry.correctChoiceId);
        expect(activity.effectiveAcceptedChoiceIds, registry.acceptedChoiceIds);
        expect(activity.choices.map((choice) => choice.id), registry.choiceIds);
        expect(
          activity.presentedChoices.map((choice) => choice.id).toSet(),
          registry.choiceIds.toSet(),
        );
      }
    },
  );
}
