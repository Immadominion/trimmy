import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/design_study/update_assignment.dart';

import 'progress_test.dart' show MemoryStore, decode, firstTime;
import 'sample_progress_test.dart'
    show
        roundTrip,
        sample,
        sampleDecision,
        storeState,
        unlockedSample,
        versionOne;

const update = OfficeActivityIds.prepareTheUpdate;

OfficeProgress unlockedUpdate() => sampleDecision()
    .selectAnswerPart('amount', 'eight-of-ten')
    .selectAnswerPart('group', 'testers')
    .submitChoice(firstTime)
    .closeActivity();

OfficeProgress updateDecision() =>
    unlockedUpdate().startActivity(update).advance().advance();

OfficeProgress selectUpdate(OfficeProgress state, String choiceId) {
  for (final fact in updateChoiceFacts(choiceId)) {
    state = state.selectAnswerPart(fact.id, 'included');
  }
  return state;
}

Map<String, dynamic> versionTwo(OfficeProgress state) =>
    decode(jsonEncode(state.toJson()))..['version'] = 2;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'five authored facts yield ten immutable canonical three-fact choices',
    () {
      expect(updateFacts.map((fact) => fact.id), [
        'dated-growth',
        'lower-profit',
        'trial-result',
        'current-growth',
        'all-customers',
      ]);
      expect(updateFacts.map((fact) => fact.text), [
        'In 2025, users grew 80%.',
        r'In 2025, profit fell from $400 to $200.',
        '8 of 10 beta testers liked Aster.',
        'In 2026, users grew 80%.',
        'Everyone who uses Aster likes it.',
      ]);
      expect(updateChoiceIds.toSet(), hasLength(10));
      final generated = <String>{};
      for (var a = 0; a < updateFacts.length; a++) {
        for (var b = a + 1; b < updateFacts.length; b++) {
          for (var c = b + 1; c < updateFacts.length; c++) {
            final expected = [
              updateFacts[a].id,
              updateFacts[b].id,
              updateFacts[c].id,
            ];
            // Deliberately insert in reverse order: storage identity is authored.
            final parts = {for (final id in expected.reversed) id: 'included'};
            final choice = updateChoiceId(parts)!;
            generated.add(choice);
            expect(choice, expected.join('+'));
            expect(updateChoiceFacts(choice).map((fact) => fact.id), expected);
            expect(
              () => updateChoiceFacts(choice).clear(),
              throwsUnsupportedError,
            );
          }
        }
      }
      expect(generated, updateChoiceIds.toSet());
      expect(updateChoiceIds.first, updateCorrectChoiceId);
      expect(() => updateFacts.clear(), throwsUnsupportedError);
      expect(() => updateChoiceIds.clear(), throwsUnsupportedError);
    },
  );

  test(
    'pure choice helpers reject incomplete, malformed and noncanonical input',
    () {
      expect(updateChoiceId({}), isNull);
      expect(updateChoiceId({'dated-growth': 'included'}), isNull);
      expect(
        updateChoiceId({
          'dated-growth': 'included',
          'trial-result': 'included',
        }),
        isNull,
      );
      expect(
        updateChoiceId({for (final fact in updateFacts) fact.id: 'included'}),
        isNull,
      );
      expect(updateChoiceId({'unknown': 'included'}), isNull);
      expect(updateChoiceId({'dated-growth': 'yes'}), isNull);
      expect(
        updateChoiceId({
          'trial-result': 'included',
          'current-growth': 'excluded',
          'lower-profit': 'included',
          'all-customers': 'excluded',
          'dated-growth': 'included',
        }),
        updateCorrectChoiceId,
      );
      for (final invalid in [
        '',
        'dated-growth',
        'dated-growth+lower-profit',
        'trial-result+lower-profit+dated-growth',
        'dated-growth+dated-growth+lower-profit',
        'dated-growth+lower-profit+unknown',
      ]) {
        expect(() => updateChoiceFacts(invalid), throwsArgumentError);
      }
    },
  );

  test(
    'the fourth assignment waits for the third acknowledged completion',
    () async {
      final store = storeState(
        sampleDecision()
            .selectAnswerPart('amount', 'eight-of-ten')
            .selectAnswerPart('group', 'testers'),
      );
      final repository = store.repository();
      expect(repository.state.isUnlocked(update), isFalse);
      await expectLater(repository.startActivity(update), throwsStateError);
      store.failNext = true;
      await expectLater(
        repository.submitChoice(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.isUnlocked(update), isFalse);
      await repository.submitChoice();
      expect(store.repository().state.isUnlocked(update), isTrue);
      await repository.startActivity(update);
      expect(store.repository().state.active!.activityId, update);
      expect(repository.state.active!.stage, 0);
      expect(repository.state.active!.answerParts, isEmpty);
    },
  );

  test(
    'answer edits validate stage and values and a fourth inclusion cannot bypass the limit',
    () {
      final decision = updateDecision();
      expect(
        () => decision.selectChoice(updateCorrectChoiceId),
        throwsStateError,
      );
      expect(
        () => decision.selectAnswerPart('amount', 'included'),
        throwsArgumentError,
      );
      expect(
        () => decision.selectAnswerPart('dated-growth', 'true'),
        throwsArgumentError,
      );
      expect(
        () => decision.selectAnswerPart('dated-growth', 'Included'),
        throwsArgumentError,
      );
      expect(
        () => decision
            .inspectStage(1)
            .selectAnswerPart('dated-growth', 'included'),
        throwsStateError,
      );
      final full = selectUpdate(decision, updateCorrectChoiceId);
      expect(
        () => full.selectAnswerPart('current-growth', 'included'),
        throwsStateError,
      );
      expect(
        identical(full.selectAnswerPart('dated-growth', 'included'), full),
        isTrue,
      );
      final partial = full.selectAnswerPart('lower-profit', 'excluded');
      expect(partial.active!.selectedChoiceId, isNull);
      expect(() => partial.submitChoice(firstTime), throwsStateError);
      final replaced = partial.selectAnswerPart('current-growth', 'included');
      expect(
        replaced.active!.selectedChoiceId,
        'dated-growth+trial-result+current-growth',
      );
      expect(full.active!.answerParts['lower-profit'], 'included');
      expect(
        () => replaced.active!.answerParts.clear(),
        throwsUnsupportedError,
      );
      final submitted = full.submitChoice(firstTime);
      expect(
        () => submitted.selectAnswerPart('dated-growth', 'excluded'),
        throwsStateError,
      );
    },
  );

  test(
    'partial includes and exclusions survive source inspection and repository restart',
    () async {
      final store = storeState(updateDecision());
      var repository = store.repository();
      await repository.selectAnswerPart('trial-result', 'included');
      await repository.selectAnswerPart('current-growth', 'excluded');
      await repository.selectAnswerPart('dated-growth', 'included');
      await repository.inspectStage(1);
      await repository.inspectStage(0);
      await repository.closeActivity();
      repository = store.repository();
      expect(repository.loadIssue, isNull);
      expect(repository.state.active!.stage, 0);
      expect(repository.state.active!.answerParts, {
        'trial-result': 'included',
        'current-growth': 'excluded',
        'dated-growth': 'included',
      });
      expect(repository.state.active!.selectedChoiceId, isNull);
      await repository.inspectStage(1);
      await repository.inspectStage(2);
      await repository.selectAnswerPart('lower-profit', 'included');
      expect(
        store.repository().state.active!.selectedChoiceId,
        updateCorrectChoiceId,
      );
      expect(repository.state.completions, hasLength(3));
    },
  );

  test(
    'every valid combination round trips with the original included facts',
    () {
      for (final choice in updateChoiceIds) {
        final correct = choice == updateCorrectChoiceId;
        var result = selectUpdate(
          updateDecision(),
          choice,
        ).submitChoice(firstTime);
        result = roundTrip(result);
        expect(result.active!.stage, correct ? 4 : 3, reason: choice);
        expect(result.completions.containsKey(update), correct);
        final submittedParts = result.active!.answerParts;
        if (!correct) result = roundTrip(result.acceptCorrection(firstTime));
        expect(result.active!.answerParts, submittedParts);
        expect(result.active!.selectedChoiceId, choice);
        final first = result.completions[update]!;
        expect(first.selectedChoiceId, choice);
        expect(first.corrected, !correct);
        expect(first.completedAt, firstTime);
        expect(first.importedFromLegacy, isFalse);
      }
    },
  );

  test(
    'version one and two reads preserve saved bytes and prior answer evidence',
    () {
      final partialSample = sampleDecision().selectAnswerPart(
        'amount',
        'eight-of-ten',
      );
      final correctedSample = sampleDecision()
          .selectAnswerPart('amount', 'all')
          .selectAnswerPart('group', 'customers')
          .submitChoice(firstTime)
          .acceptCorrection(firstTime);
      final snapshots = [
        (versionOne(OfficeProgress.empty()), OfficeProgress.empty()),
        (versionOne(unlockedSample()), unlockedSample()),
        (versionTwo(partialSample), partialSample),
        (versionTwo(correctedSample), correctedSample),
        (versionTwo(unlockedUpdate()), unlockedUpdate()),
      ];
      for (final (data, expected) in snapshots) {
        final raw = jsonEncode(data);
        final store = MemoryStore()
          ..values[OfficeProgressRepository.saveKey] = raw;
        final repository = store.repository();
        expect(repository.loadIssue, isNull);
        expect(repository.state.toJson(), {...expected.toJson(), 'version': 3});
        expect(store.values[OfficeProgressRepository.saveKey], raw);
        expect(store.writes, isEmpty);
      }
    },
  );

  test(
    'version two upgrades only on the next successful write and never replaces previous completions',
    () async {
      final original = unlockedUpdate();
      final raw = jsonEncode(versionTwo(original));
      final store = MemoryStore()
        ..values[OfficeProgressRepository.saveKey] = raw;
      final repository = store.repository();
      store.failNext = true;
      await expectLater(
        repository.startActivity(update),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(store.values[OfficeProgressRepository.saveKey], raw);
      expect(repository.state.active, isNull);
      await repository.startActivity(update);
      final saved = decode(store.values[OfficeProgressRepository.saveKey]!);
      expect(saved['version'], 6);
      expect(saved['active']['answerParts'], isEmpty);
      expect(store.values.keys, [OfficeProgressRepository.saveKey]);
      expect(saved['completions'], original.toJson()['completions']);
    },
  );

  test(
    'older payloads cannot contain the fourth assignment or its completion',
    () async {
      final complete = selectUpdate(
        updateDecision(),
        updateCorrectChoiceId,
      ).submitChoice(firstTime).closeActivity();
      for (final version in [1, 2]) {
        for (final state in [updateDecision(), complete]) {
          final data = version == 1 ? versionOne(state) : versionTwo(state);
          final raw = jsonEncode(data);
          final store = MemoryStore()
            ..values[OfficeProgressRepository.saveKey] = raw;
          final repository = store.repository();
          expect(repository.loadIssue!.kind, ProgressLoadIssueKind.corruptData);
          await expectLater(
            repository.closeActivity(),
            throwsA(isA<ProgressProtectedException>()),
          );
          expect(store.values[OfficeProgressRepository.saveKey], raw);
          expect(store.writes, isEmpty);
        }
      }
    },
  );

  test(
    'failed inclusion and exclusion keep the previous acknowledged draft and recover',
    () async {
      final store = storeState(
        updateDecision()
            .selectAnswerPart('dated-growth', 'included')
            .selectAnswerPart('lower-profit', 'included'),
      );
      final repository = store.repository();
      final before = repository.state.active!.answerParts;
      store.failNext = true;
      await expectLater(
        repository.selectAnswerPart('trial-result', 'included'),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.answerParts, before);
      expect(repository.state.active!.selectedChoiceId, isNull);
      await expectLater(repository.submitChoice(), throwsStateError);
      await repository.selectAnswerPart('trial-result', 'included');
      store.throwNext = true;
      await expectLater(
        repository.selectAnswerPart('dated-growth', 'excluded'),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(
        store.repository().state.active!.selectedChoiceId,
        updateCorrectChoiceId,
      );
      await repository.selectAnswerPart('dated-growth', 'excluded');
      expect(store.repository().state.active!.selectedChoiceId, isNull);
    },
  );

  test(
    'held writes serialize three facts before submission and reject a queued fourth include',
    () async {
      final store = storeState(updateDecision());
      final repository = store.repository();
      final gate = Completer<bool>();
      store.gate = gate;
      final one = repository.selectAnswerPart('trial-result', 'included');
      final two = repository.selectAnswerPart('dated-growth', 'included');
      final three = repository.selectAnswerPart('lower-profit', 'included');
      final fourth = expectLater(
        repository.selectAnswerPart('current-growth', 'included'),
        throwsStateError,
      );
      final submit = repository.submitChoice();
      await Future<void>.delayed(Duration.zero);
      expect(repository.state.active!.answerParts, isEmpty);
      expect(repository.state.completions, hasLength(3));
      expect(store.writes, hasLength(1));
      gate.complete(true);
      expect((await one).active!.selectedChoiceId, isNull);
      expect((await two).active!.selectedChoiceId, isNull);
      expect((await three).active!.selectedChoiceId, updateCorrectChoiceId);
      await fourth;
      await submit;
      expect(store.writes, hasLength(4));
      expect(store.repository().state.active!.stage, 4);
      expect(repository.state.completions, hasLength(4));
    },
  );

  test(
    'failed submit and correction acknowledgments never file an update early',
    () async {
      final wrong = updateChoiceIds.last;
      final store = storeState(selectUpdate(updateDecision(), wrong));
      final repository = store.repository();
      store.failNext = true;
      await expectLater(
        repository.submitChoice(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.stage, 2);
      expect(repository.state.completions, hasLength(3));
      await repository.submitChoice();
      store.throwNext = true;
      await expectLater(
        repository.acceptCorrection(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(store.repository().state.active!.stage, 3);
      expect(store.repository().state.completions, hasLength(3));
      await repository.acceptCorrection();
      expect(
        store.repository().state.completions[update]!.selectedChoiceId,
        wrong,
      );
      expect(store.repository().state.active!.stage, 4);
    },
  );

  test(
    'correct replay starts with an empty draft and preserves first update identity',
    () async {
      final state = selectUpdate(
        updateDecision(),
        updateChoiceIds.last,
      ).submitChoice(firstTime).acceptCorrection(firstTime).closeActivity();
      final store = storeState(state);
      final repository = store.repository(
        clock: () => firstTime.add(const Duration(days: 1)),
      );
      final first = repository.state.completions[update]!;
      final prior = repository.state.toJson()['completions'];
      await repository.startActivity(update);
      expect(repository.state.active!.answerParts, isEmpty);
      await repository.advance();
      await repository.advance();
      for (final fact in updateChoiceFacts(updateCorrectChoiceId).reversed) {
        await repository.selectAnswerPart(fact.id, 'included');
      }
      await repository.submitChoice();
      expect(repository.state.active!.corrected, isFalse);
      expect(identical(repository.state.completions[update], first), isTrue);
      expect(store.repository().state.toJson()['completions'], prior);
    },
  );

  test(
    'malformed parts, ordering and contradictory records are protected from writes',
    () async {
      final valid = selectUpdate(updateDecision(), updateCorrectChoiceId);
      final mutations = <void Function(Map<String, dynamic>)>[
        (data) => data['active'].remove('answerParts'),
        (data) => data['active']['answerParts'] = null,
        (data) => data['active']['answerParts'] = [],
        (data) => data['active']['answerParts']['dated-growth'] = true,
        (data) => data['active']['answerParts']['dated-growth'] = 'Included',
        (data) => data['active']['answerParts']['dated-growth'] = 'excluded',
        (data) => data['active']['answerParts']['amount'] = 'included',
        (data) => data['active']['answerParts']['current-growth'] = 'included',
        (data) => data['active']['selectedChoiceId'] = null,
        (data) => data['active']['selectedChoiceId'] = updateChoiceIds.last,
        (data) => data['active']['selectedChoiceId'] =
            'trial-result+lower-profit+dated-growth',
        (data) => data['active']['selectedChoiceId'] =
            'dated-growth+dated-growth+lower-profit',
        (data) => data['active']['stage'] = 3,
        (data) => data['active']['stage'] = 4,
        (data) => data['completions'].remove(sample),
      ];
      for (var i = 0; i < mutations.length; i++) {
        final data = decode(jsonEncode(valid.toJson()));
        mutations[i](data);
        final raw = jsonEncode(data);
        final store = MemoryStore()
          ..values[OfficeProgressRepository.saveKey] = raw;
        final repository = store.repository();
        expect(
          repository.loadIssue!.kind,
          ProgressLoadIssueKind.corruptData,
          reason: 'Mutation $i',
        );
        await expectLater(
          repository.selectAnswerPart('current-growth', 'excluded'),
          throwsA(isA<ProgressProtectedException>()),
        );
        expect(store.values[OfficeProgressRepository.saveKey], raw);
        expect(store.writes, isEmpty);
      }
      final completed = valid.submitChoice(firstTime).closeActivity();
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (data) => data['completions'].remove(sample),
        (data) => data['completions'][update]['selectedChoiceId'] =
            'trial-result+lower-profit+dated-growth',
        (data) => data['completions'][update]['importedFromLegacy'] = true,
        (data) => data['completions'][update]['corrected'] = true,
      ]) {
        final data = decode(jsonEncode(completed.toJson()));
        mutation(data);
        expect(() => OfficeProgress.fromJson(data), throwsFormatException);
      }
    },
  );
}
