import 'dart:convert';
import 'dart:io';

import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';

/// A copy release is distinct from metadata and saved-progress versions.
/// Bump this only after reviewing the semantic diff and registering its digest.
const practiceCopyRevision = 1;

Map<String, Object?> exportPracticeCopy() {
  final activities = [
    for (final activity in studyActivities)
      <String, Object?>{
        'id': activity.id,
        'title': activity.title,
        'officeDescription': activity.officeDescription,
        'intro': activity.intro,
        'sourceIntro': activity.sourceIntro,
        'sourceTitle': activity.sourceTitle,
        'sourceExplanation': activity.sourceExplanation,
        'draftHeadline': activity.draftHeadline,
        'correctedHeadline': activity.correctedHeadline,
        'correctChoiceId': activity.correctChoiceId,
        'acceptedChoiceIds': activity.effectiveAcceptedChoiceIds,
        'choices': [
          for (final choice in activity.choices)
            {'id': choice.id, 'label': choice.label, 'detail': choice.detail},
        ],
        'challengeTitle': activity.challengeTitle,
        'challengeText': activity.challengeText,
        'correctedFeedback': activity.correctedFeedback,
        'successFeedback': activity.successFeedback,
        'journalEvidence': activity.journalEvidence,
        'evidence': [
          for (final source in activity.evidence)
            {
              'title': source.title,
              'rows': [
                for (final row in source.rows)
                  {'label': row.$1, 'value': row.$2},
              ],
              'explanation': source.explanation,
            },
        ],
        'presentationOrder': activity.presentationOrder,
        'presentedChoiceIds': [
          for (final choice in activity.presentedChoices) choice.id,
        ],
        'branchVariants': {
          for (final entry in activity.branchVariants.entries)
            entry.key: {
              'intro': entry.value.intro,
              'draftHeadline': entry.value.draftHeadline,
              'correctedHeadline': entry.value.correctedHeadline,
              'correctedFeedback': entry.value.correctedFeedback,
              'successFeedback': entry.value.successFeedback,
              'journalEvidence': entry.value.journalEvidence,
              'outcomeTitle': entry.value.outcomeTitle,
              'officeConsequence': entry.value.officeConsequence,
            },
        },
      },
  ];
  return {
    'schemaVersion': 2,
    'contentVersion': practiceCatalogContentVersion,
    'copyRevision': practiceCopyRevision,
    'scope': {
      'source': 'apps/mobile/lib/design_study/activities.dart',
      'type': 'ActivityDefinition',
      'covered': [
        'Authored public fields, including activity-level feedback and Journal evidence.',
        'Choice IDs, labels and details in canonical order.',
        'ActivityEvidence titles, ordered rows and explanations.',
        'ActivityDefinition presentationOrder and presentedChoiceIds; composite composer controls are separate.',
        'Accepted choice IDs and every authored branch consequence keyed by a catalog choice.',
      ],
      'excluded': [
        'Widget-local date, sales, sample and update source, composer and review strings.',
        'Widget-local source tables and chart data, sample response outcomes, and composer part labels and order.',
        'UpdateFact fields except text projected into ActivityDefinition headlines and choices.',
        'Other Journal and Ada narrative generated outside ActivityDefinition.',
        'Layouts, motion, sound, illustrations, fonts and gameplay or saved-progress behavior.',
      ],
    },
    'counts': {
      'activities': studyActivities.length,
      'choices': studyActivities.fold(
        0,
        (sum, activity) => sum + activity.choices.length,
      ),
      'evidence': studyActivities.fold(
        0,
        (sum, activity) => sum + activity.evidence.length,
      ),
      'evidenceRows': studyActivities.fold(
        0,
        (sum, activity) =>
            sum +
            activity.evidence.fold(
              0,
              (rows, source) => rows + source.rows.length,
            ),
      ),
      'branchVariants': studyActivities.fold(
        0,
        (sum, activity) => sum + activity.branchVariants.length,
      ),
    },
    'activities': activities,
  };
}

/// Explicit export delegates SHA-256 and immutable release validation to the
/// Node checker. Normal checks never write or normalize an existing manifest.
Future<void> writePracticeCopy() async {
  final process = await Process.start('node', [
    '../../tool/check-practice-copy.mjs',
    '--write',
  ]);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(jsonEncode(exportPracticeCopy()));
  await process.stdin.close();
  final status = await process.exitCode;
  final message = '${await output}${await errors}';
  if (status != 0) throw StateError(message.trim());
  stdout.write(message);
}

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(exportPracticeCopy()),
    );
  } else if (arguments.length == 1 && arguments.single == '--write') {
    await writePracticeCopy();
  } else {
    throw ArgumentError(
      'Usage: dart run tool/export_practice_copy.dart [--write]',
    );
  }
}
