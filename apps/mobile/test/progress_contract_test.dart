import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';
import 'package:trimmy/practice_sync/protocol.dart';

/// Real native transitions generate the backend's compatibility fixtures.
/// Regenerate intentionally with --dart-define=UPDATE_PROGRESS_CONTRACT=true.
void main() {
  test('frozen v3, v4 and v5 fixtures retain exact transport identity', () {
    for (final version in [3, 4, 5]) {
      final contract =
          jsonDecode(
                File(
                  '../../contracts/practice-progress-v$version.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final entry in contract['cases'] as List) {
        final data = entry['progress'] as Map<String, dynamic>;
        final decoded = OfficeProgress.fromJson(data);
        expect(decoded.toJson(), data, reason: entry['name'] as String);
        expect(decoded.wireVersion, version);
        final mutation = PracticeMutation(
          mutationId: '10000000-0000-4000-8000-000000000001',
          baseRevision: 0,
          progress: decoded,
        );
        expect(mutation.progress.toJson(), data);
        expect(
          PracticeMutation.fromJson(mutation.toJson()).toJson(),
          mutation.toJson(),
        );
        expect(
          canonicalProgress(decoded),
          canonicalProgress(mutation.progress),
        );
      }
    }
  });
  test('native progress and server contract fixtures stay compatible', () {
    final cases = <Map<String, Object?>>[];
    void capture(String name, OfficeProgress progress) {
      final json = progress.toJson();
      expect(OfficeProgress.fromJson(json).toJson(), json, reason: name);
      cases.add({'name': name, 'progress': json});
    }

    final now = DateTime.utc(2026, 9, 14, 10, 20, 30, 123, 456);
    var progress = OfficeProgress.empty();
    capture('empty', progress);
    for (final id in OfficeActivityIds.all) {
      progress = progress.startActivity(id);
      capture('$id-brief', progress);
      progress = progress.advance();
      capture('$id-source', progress);
      progress = progress.advance();
      if (id == OfficeActivityIds.checkTheSample) {
        progress = progress.selectAnswerPart('amount', 'all');
        capture('$id-partial', progress);
        progress = progress.selectAnswerPart('group', 'customers');
      } else if (id == OfficeActivityIds.prepareTheUpdate) {
        progress = progress.selectAnswerPart('current-growth', 'included');
        capture('$id-partial', progress);
        progress = progress
            .selectAnswerPart('dated-growth', 'excluded')
            .selectAnswerPart('lower-profit', 'included')
            .selectAnswerPart('trial-result', 'included');
      } else {
        final entry = practiceCatalogById[id]!;
        progress = progress.selectChoice(
          id == OfficeActivityIds.reviewTeamUpdate
              ? 'request-missing-costs'
              : entry.choiceIds.last,
        );
      }
      capture('$id-selected', progress);
      progress = progress.inspectStage(1);
      capture('$id-reinspect-with-selection', progress);
      progress = progress.advance().submitChoice(now);
      final accepted = practiceCatalogById[id]!.acceptedChoiceIds.contains(
        progress.active!.selectedChoiceId,
      );
      capture(accepted ? '$id-accepted' : '$id-correction', progress);
      if (!accepted) progress = progress.acceptCorrection(now);
      capture('$id-completed', progress);
      progress = progress.closeActivity();
      capture('$id-closed', progress);
    }
    progress = progress
        .startActivity(OfficeActivityIds.checkTheDate)
        .advance()
        .advance()
        .selectChoice('add-year')
        .submitChoice(now.add(const Duration(days: 1)));
    capture('correct-replay-preserves-first-mistake', progress);

    for (final time in [
      DateTime.utc(2026, 9, 14),
      DateTime.utc(2024, 2, 29, 23, 59, 59, 999, 999),
      DateTime.utc(99, 1, 1),
      DateTime.utc(-1, 1, 1),
      DateTime.utc(10000, 1, 1),
    ]) {
      final completed = OfficeProgress.empty()
          .startActivity(OfficeActivityIds.checkTheDate)
          .advance()
          .advance()
          .selectChoice('add-year')
          .submitChoice(time);
      capture('timestamp-${time.toIso8601String()}', completed);
    }
    final legacy = OfficeProgress.fromJson({
      'version': 1,
      'active': null,
      'completions': {
        OfficeActivityIds.checkTheDate: {
          'activityId': OfficeActivityIds.checkTheDate,
          'selectedChoiceId': 'add-year',
          'corrected': false,
          'completedAt': null,
          'importedFromLegacy': true,
        },
      },
    });
    capture('legacy-first-completion-exported-as-v6', legacy.upgradeForWrite());

    final file = File('../../contracts/practice-progress-v6.json');
    final contract = {'schemaVersion': 1, 'cases': cases};
    if (const bool.fromEnvironment('UPDATE_PROGRESS_CONTRACT')) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(contract)}\n',
      );
    }
    expect(jsonDecode(file.readAsStringSync()), contract);
  });
}
