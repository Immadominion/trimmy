import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';

void main() {
  test('generated Dart metadata matches every canonical JSON field', () {
    final source =
        jsonDecode(
              File('../../content/practice-catalog.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(practiceCatalogSchemaVersion, source['schemaVersion']);
    expect(practiceCatalogContentVersion, source['contentVersion']);
    expect(practiceCatalogPayloadVersion, source['payloadVersion']);
    final entries = source['activities'] as List<dynamic>;
    expect(practiceCatalogActivityIds, entries.map((entry) => entry['id']));
    for (final dynamic entry in entries) {
      final generated = practiceCatalogById[entry['id']]!;
      expect(generated.id, entry['id']);
      expect(generated.floor, entry['floor']);
      expect(generated.title, entry['title']);
      expect(generated.correctChoiceId, entry['correctChoiceId']);
      expect(generated.acceptedChoiceIds, entry['acceptedChoiceIds']);
      expect(generated.choiceIds, entry['choiceIds']);
      expect(generated.introducedIn, entry['introducedIn']);
      expect(generated.prerequisiteId, entry['prerequisiteId']);
    }
    for (final dynamic floor in source['floors'] as List<dynamic>) {
      expect(practiceCatalogFloors[floor['number']], floor['title']);
    }
    expect(
      () => practiceCatalogActivityIds.add('changed'),
      throwsUnsupportedError,
    );
    expect(
      () => practiceCatalogById['check-the-date']!.choiceIds.add('changed'),
      throwsUnsupportedError,
    );
    expect(
      () => practiceCatalogById['review-team-update']!.acceptedChoiceIds.add(
        'changed',
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'authored native activity IDs and answers agree with generated metadata',
    () {
      for (final activity in studyActivities) {
        final metadata = practiceCatalogById[activity.id];
        expect(metadata, isNotNull, reason: activity.id);
        expect(metadata!.title, activity.title);
        expect(metadata.correctChoiceId, activity.correctChoiceId);
        expect(metadata.acceptedChoiceIds, activity.effectiveAcceptedChoiceIds);
        expect(metadata.choiceIds, activity.choices.map((choice) => choice.id));
      }
    },
  );
}
