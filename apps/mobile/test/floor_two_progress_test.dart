import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';
import 'package:trimmy/account/reconciliation.dart';
import 'package:trimmy/practice_sync/durable_state.dart';
import 'package:trimmy/design_study/progress.dart';

OfficeProgress firstFloorV3() {
  final fixture =
      jsonDecode(
            File(
              '../../contracts/practice-progress-v3.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = fixture['cases'] as List;
  return OfficeProgress.fromJson(
    cases.firstWhere(
          (entry) => entry['name'] == 'prepare-the-update-closed',
        )['progress']
        as Map<String, dynamic>,
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 15, 11, 12, 13, 456, 789);
  final floorTwo = practiceCatalogActivityIds.where(
    (id) => practiceCatalogById[id]!.floor == 2,
  );

  test(
    'v3 reads preserve bytes and first notes; only acknowledged work writes v6',
    () async {
      final old = firstFloorV3();
      var raw = jsonEncode(old.toJson());
      final original = raw;
      var allowWrite = false;
      final repository = OfficeProgressRepository(
        read: (_) => raw,
        write: (_, value) async {
          if (!allowWrite) return false;
          raw = value;
          return true;
        },
      );
      expect(repository.loadIssue, isNull);
      expect(repository.state.wireVersion, 3);
      await repository.retryLoad();
      expect(raw, original);
      expect(
        repository.state.isUnlocked(OfficeActivityIds.compareCompanyValue),
        isTrue,
      );
      await expectLater(
        repository.startActivity(OfficeActivityIds.compareCompanyValue),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(raw, original);
      expect(repository.state.wireVersion, 3);
      expect(repository.state.active, isNull);
      allowWrite = true;
      await repository.startActivity(OfficeActivityIds.compareCompanyValue);
      expect(jsonDecode(raw)['version'], 6);
      expect(
        repository.state.toJson()['completions'],
        old.toJson()['completions'],
      );
    },
  );

  test(
    'each floor two task gates its successor and resumes correction before saving',
    () {
      var progress = firstFloorV3();
      final firstNotes = progress.toJson()['completions'];
      for (final id in floorTwo) {
        final entry = practiceCatalogById[id]!;
        expect(progress.isUnlocked(id), isTrue);
        final successorIndex = practiceCatalogActivityIds.indexOf(id) + 1;
        final successor = successorIndex < practiceCatalogActivityIds.length
            ? practiceCatalogActivityIds[successorIndex]
            : null;
        if (successor != null) {
          expect(progress.isUnlocked(successor), isFalse);
          expect(() => progress.startActivity(successor), throwsStateError);
        }
        progress = progress.startActivity(id).advance().advance();
        expect(
          () => progress.selectAnswerPart('amount', 'all'),
          throwsStateError,
        );
        final wrong = entry.choiceIds.last;
        progress = progress.selectChoice(wrong).inspectStage(1);
        progress = OfficeProgress.fromJson(
          jsonDecode(jsonEncode(progress.toJson())),
        );
        expect(progress.active!.selectedChoiceId, wrong);
        expect(progress.active!.answerParts, isEmpty);
        progress = progress.advance().submitChoice(now);
        expect(progress.active!.stage, 3);
        expect(progress.completions.containsKey(id), isFalse);
        if (successor != null) expect(progress.isUnlocked(successor), isFalse);
        progress = OfficeProgress.fromJson(
          progress.toJson(),
        ).acceptCorrection(now);
        final first = progress.completions[id]!;
        expect(first.selectedChoiceId, wrong);
        expect(first.corrected, isTrue);
        expect(first.completedAt, now);
        progress = progress
            .closeActivity()
            .startActivity(id)
            .advance()
            .advance()
            .selectChoice(entry.correctChoiceId)
            .submitChoice(now.add(const Duration(days: 1)));
        expect(progress.active!.corrected, isFalse);
        expect(progress.completions[id]!.toJson(), first.toJson());
        progress = progress.closeActivity();
      }
      expect({
        for (final id in (firstNotes as Map).keys)
          id: progress.completions[id]!.toJson(),
      }, firstNotes);
    },
  );

  test(
    'compatible floor two conflicts reconcile either draft without replacing first notes',
    () {
      final firstFloor = firstFloorV3();
      final local = firstFloor
          .startActivity(OfficeActivityIds.checkTheDate)
          .advance();
      final remote = firstFloor
          .startActivity(OfficeActivityIds.compareCompanyValue)
          .advance()
          .advance()
          .selectChoice('compare-total-value')
          .submitChoice(now)
          .closeActivity()
          .startActivity(OfficeActivityIds.countTheFees)
          .advance();
      for (final useRemote in [false, true]) {
        final merged = reconcilePracticeDrafts(
          local: local,
          remote: remote,
          useRemoteDraft: useRemote,
        );
        expect(merged, isNotNull);
        expect(merged!.wireVersion, 6);
        assertPracticeHistoryPreserved(local, merged);
        assertPracticeHistoryPreserved(remote, merged);
        expect(
          merged.active!.toJson(),
          (useRemote ? remote : local).active!.toJson(),
        );
      }
      final otherFirst = firstFloor
          .startActivity(OfficeActivityIds.compareCompanyValue)
          .advance()
          .advance()
          .selectChoice('lower-price-means-smaller')
          .submitChoice(now)
          .acceptCorrection(now)
          .closeActivity();
      for (final useRemote in [false, true]) {
        expect(
          reconcilePracticeDrafts(
            local: remote,
            remote: otherFirst,
            useRemoteDraft: useRemote,
          ),
          isNull,
        );
      }
    },
  );

  test(
    'v4 rejects new activities in historical schemas and malformed crossfields',
    () {
      final chosen = firstFloorV3()
          .startActivity(OfficeActivityIds.compareCompanyValue)
          .advance()
          .advance()
          .selectChoice('compare-total-value');
      final data = chosen.toJson();
      final active = chosen.active!.toJson();
      for (final malformed in <Map<String, dynamic>>[
        {...data, 'version': 3},
        {...data, 'version': 7},
        {
          ...data,
          'active': {
            ...active,
            'answerParts': {'amount': 'all'},
          },
        },
        {
          ...data,
          'active': {...active, 'selectedChoiceId': 'nine-dollars-invested'},
        },
        {
          ...data,
          'active': {...active, 'stage': 3, 'corrected': true},
        },
        {
          ...data,
          'active': {...active, 'stage': 4},
        },
        {
          ...data,
          'completions': {...chosen.toJson()['completions'] as Map}
            ..remove(OfficeActivityIds.prepareTheUpdate),
        },
      ]) {
        expect(() => OfficeProgress.fromJson(malformed), throwsFormatException);
      }
      final completed = chosen.submitChoice(now).closeActivity().toJson();
      expect(
        () => OfficeProgress.fromJson({...completed, 'version': 3}),
        throwsFormatException,
      );
      final records = {...completed['completions'] as Map};
      records[OfficeActivityIds.compareCompanyValue] = {
        ...records[OfficeActivityIds.compareCompanyValue] as Map,
        'importedFromLegacy': true,
        'completedAt': null,
      };
      expect(
        () => OfficeProgress.fromJson({...completed, 'completions': records}),
        throwsFormatException,
      );
    },
  );
}
