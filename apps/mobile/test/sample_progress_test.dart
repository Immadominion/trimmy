import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/progress.dart';

import 'progress_test.dart'
    show MemoryStore, choose, decode, first, firstTime, second;

const sample = OfficeActivityIds.checkTheSample;

OfficeProgress unlockedSample() => OfficeProgress.empty()
    .startActivity(first)
    .advance()
    .advance()
    .selectChoice('add-year')
    .submitChoice(firstTime)
    .closeActivity()
    .startActivity(second)
    .advance()
    .advance()
    .selectChoice('check-costs')
    .submitChoice(firstTime)
    .closeActivity();

OfficeProgress sampleDecision() =>
    unlockedSample().startActivity(sample).advance().advance();

MemoryStore storeState(OfficeProgress state) =>
    MemoryStore()
      ..values[OfficeProgressRepository.saveKey] = jsonEncode(state.toJson());

OfficeProgress roundTrip(OfficeProgress state) =>
    OfficeProgress.fromJson(decode(jsonEncode(state.toJson())));

Map<String, dynamic> versionOne(OfficeProgress state) {
  final data = decode(jsonEncode(state.toJson()));
  data['version'] = 1;
  if (data['active'] != null) {
    (data['active'] as Map<String, dynamic>).remove('answerParts');
  }
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sample activity unlocks only after the second completion is saved',
    () async {
      final store = MemoryStore();
      final repository = store.repository();
      expect(repository.state.isUnlocked(sample), isFalse);
      await expectLater(repository.startActivity(sample), throwsStateError);
      await choose(repository, 'add-year');
      await repository.submitChoice();
      await repository.closeActivity();
      expect(repository.state.isUnlocked(sample), isFalse);
      await choose(repository, 'sales-mean-profit', activity: second);
      await repository.submitChoice();
      expect(repository.state.isUnlocked(sample), isFalse);
      store.failNext = true;
      await expectLater(
        repository.acceptCorrection(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(store.repository().state.isUnlocked(sample), isFalse);
      await repository.acceptCorrection();
      expect(store.repository().state.isUnlocked(sample), isTrue);
      await repository.startActivity(sample);
      expect(repository.state.active!.stage, 0);
      expect(repository.state.active!.answerParts, isEmpty);
    },
  );

  test(
    'parts validate the activity, stage, keys and values without a choice bypass',
    () {
      final decision = sampleDecision();
      expect(
        () => decision.selectChoice('eight-of-ten-testers'),
        throwsStateError,
      );
      expect(
        () => decision.selectAnswerPart('unknown', 'all'),
        throwsArgumentError,
      );
      expect(
        () => decision.selectAnswerPart('amount', 'testers'),
        throwsArgumentError,
      );
      expect(
        () => decision.selectAnswerPart('group', 'all'),
        throwsArgumentError,
      );
      expect(
        () => decision.selectAnswerPart('group', 'Testers'),
        throwsArgumentError,
      );
      expect(
        () => decision.inspectStage(1).selectAnswerPart('amount', 'all'),
        throwsStateError,
      );
      expect(
        () => OfficeProgress.empty()
            .startActivity(first)
            .advance()
            .advance()
            .selectAnswerPart('amount', 'all'),
        throwsStateError,
      );
      final submitted = decision
          .selectAnswerPart('amount', 'all')
          .selectAnswerPart('group', 'testers')
          .submitChoice(firstTime);
      expect(
        () => submitted.selectAnswerPart('amount', 'eight-of-ten'),
        throwsStateError,
      );
    },
  );

  test(
    'either partial answer survives inspection, closing and a restart',
    () async {
      for (final part in ['amount', 'group']) {
        final value = part == 'amount' ? 'eight-of-ten' : 'testers';
        final store = storeState(sampleDecision());
        var repository = store.repository();
        await repository.selectAnswerPart(part, value);
        expect(repository.state.active!.selectedChoiceId, isNull);
        await expectLater(repository.submitChoice(), throwsStateError);
        await repository.inspectStage(1);
        await repository.inspectStage(0);
        await repository.closeActivity();
        repository = store.repository();
        expect(repository.loadIssue, isNull);
        expect(repository.state.active!.stage, 0);
        expect(repository.state.active!.answerParts, {part: value});
        expect(repository.state.active!.selectedChoiceId, isNull);
        await repository.inspectStage(1);
        await repository.inspectStage(2);
        final remaining = part == 'amount' ? 'group' : 'amount';
        final remainingValue = part == 'amount' ? 'testers' : 'eight-of-ten';
        await repository.selectAnswerPart(remaining, remainingValue);
        expect(
          repository.state.active!.selectedChoiceId,
          'eight-of-ten-testers',
        );
      }
    },
  );

  test(
    'answer maps and prior snapshots remain immutable when either part changes',
    () {
      final partial = sampleDecision().selectAnswerPart('amount', 'all');
      final full = partial.selectAnswerPart('group', 'testers');
      final changed = full.selectAnswerPart('amount', 'eight-of-ten');
      expect(
        () => full.active!.answerParts['amount'] = 'all',
        throwsUnsupportedError,
      );
      expect(() => full.active!.answerParts.clear(), throwsUnsupportedError);
      expect(partial.active!.answerParts, {'amount': 'all'});
      expect(partial.active!.selectedChoiceId, isNull);
      expect(full.active!.selectedChoiceId, 'all-testers');
      expect(changed.active!.selectedChoiceId, 'eight-of-ten-testers');
      expect(roundTrip(changed).active!.answerParts, {
        'amount': 'eight-of-ten',
        'group': 'testers',
      });
    },
  );

  test(
    'all four combinations retain their original answer through correction and completion',
    () {
      for (final amount in ['eight-of-ten', 'all']) {
        for (final group in ['testers', 'customers']) {
          final correct = amount == 'eight-of-ten' && group == 'testers';
          final expectedChoice = '$amount-$group';
          final parts = {'amount': amount, 'group': group};
          final selected = sampleDecision()
              .selectAnswerPart('group', group)
              .selectAnswerPart('amount', amount);
          expect(selected.active!.selectedChoiceId, expectedChoice);
          var submitted = roundTrip(selected.submitChoice(firstTime));
          expect(submitted.active!.stage, correct ? 4 : 3);
          expect(submitted.active!.answerParts, parts);
          expect(submitted.completions.containsKey(sample), correct);
          if (!correct) {
            submitted = roundTrip(submitted.acceptCorrection(firstTime));
          }
          expect(submitted.active!.stage, 4);
          expect(submitted.active!.answerParts, parts);
          final completed = submitted.completions[sample]!;
          expect(completed.selectedChoiceId, expectedChoice);
          expect(completed.corrected, !correct);
          expect(completed.completedAt, firstTime);
          expect(submitted.closeActivity().active, isNull);
        }
      }
    },
  );

  test(
    'version one records migrate in memory without changing any existing evidence',
    () {
      final firstDecision = OfficeProgress.empty()
          .startActivity(first)
          .advance()
          .advance()
          .selectChoice('keep-headline');
      final snapshots = [
        OfficeProgress.empty(),
        firstDecision.inspectStage(1).inspectStage(0),
        firstDecision.inspectStage(1),
        firstDecision,
        firstDecision.submitChoice(firstTime),
        firstDecision.submitChoice(firstTime).acceptCorrection(firstTime),
        unlockedSample(),
        unlockedSample().startActivity(second),
      ];
      for (final original in snapshots) {
        final raw = jsonEncode(versionOne(original));
        final store = MemoryStore()
          ..values[OfficeProgressRepository.saveKey] = raw;
        final restored = store.repository();
        expect(restored.loadIssue, isNull);
        expect(restored.state.toJson(), {...original.toJson(), 'version': 3});
        expect(restored.state.active?.answerParts ?? {}, isEmpty);
        expect(store.values[OfficeProgressRepository.saveKey], raw);
        expect(store.writes, isEmpty);
      }
    },
  );

  test(
    'the next acknowledged transition writes version six to the existing storage key',
    () async {
      final raw = jsonEncode(versionOne(unlockedSample()));
      final store = MemoryStore()
        ..values[OfficeProgressRepository.saveKey] = raw;
      final repository = store.repository();
      store.failNext = true;
      await expectLater(
        repository.startActivity(sample),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(store.values[OfficeProgressRepository.saveKey], raw);
      expect(repository.state.active, isNull);
      await repository.startActivity(sample);
      expect(store.values.keys, [OfficeProgressRepository.saveKey]);
      final saved = decode(store.values[OfficeProgressRepository.saveKey]!);
      expect(saved['version'], 6);
      expect(saved['active']['answerParts'], isEmpty);
      expect(store.repository().state.completions.keys, [first, second]);
    },
  );

  test(
    'version one cannot claim knowledge of a sample task or answer map',
    () async {
      final states = [
        versionOne(sampleDecision()),
        versionOne(
          sampleDecision()
              .selectAnswerPart('amount', 'eight-of-ten')
              .selectAnswerPart('group', 'testers')
              .submitChoice(firstTime)
              .closeActivity(),
        ),
        versionOne(OfficeProgress.empty().startActivity(first))
          ..['active']['answerParts'] = <String, String>{},
      ];
      for (final data in states) {
        final raw = jsonEncode(data);
        final store = MemoryStore()
          ..values[OfficeProgressRepository.saveKey] = raw;
        final repository = store.repository();
        expect(repository.loadIssue!.kind, ProgressLoadIssueKind.corruptData);
        await expectLater(
          repository.closeActivity(),
          throwsA(isA<ProgressProtectedException>()),
        );
        expect(store.writes, isEmpty);
        expect(store.values[OfficeProgressRepository.saveKey], raw);
      }
    },
  );

  test(
    'failed part writes preserve the last acknowledged partial answer and can be retried',
    () async {
      final store = storeState(sampleDecision());
      final repository = store.repository();
      await repository.selectAnswerPart('amount', 'eight-of-ten');
      final before = store.values[OfficeProgressRepository.saveKey];
      store.failNext = true;
      await expectLater(
        repository.selectAnswerPart('group', 'testers'),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.answerParts, {'amount': 'eight-of-ten'});
      expect(repository.state.active!.selectedChoiceId, isNull);
      expect(store.values[OfficeProgressRepository.saveKey], before);
      await expectLater(repository.submitChoice(), throwsStateError);
      await repository.selectAnswerPart('group', 'testers');
      store.throwNext = true;
      await expectLater(
        repository.selectAnswerPart('amount', 'all'),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(
        store.repository().state.active!.selectedChoiceId,
        'eight-of-ten-testers',
      );
      await repository.selectAnswerPart('amount', 'all');
      expect(store.repository().state.active!.selectedChoiceId, 'all-testers');
    },
  );

  test(
    'rapid independent selections serialize and combined state appears only after both acknowledgments',
    () async {
      final store = storeState(sampleDecision());
      final repository = store.repository();
      final gate = Completer<bool>();
      store.gate = gate;
      final amount = repository.selectAnswerPart('amount', 'eight-of-ten');
      final group = repository.selectAnswerPart('group', 'testers');
      final submit = repository.submitChoice();
      await Future<void>.delayed(Duration.zero);
      expect(repository.state.active!.answerParts, isEmpty);
      expect(repository.state.active!.selectedChoiceId, isNull);
      expect(store.writes, hasLength(1));
      gate.complete(true);
      final partial = await amount;
      expect(partial.active!.answerParts, {'amount': 'eight-of-ten'});
      expect(partial.active!.selectedChoiceId, isNull);
      final combined = await group;
      expect(combined.active!.selectedChoiceId, 'eight-of-ten-testers');
      expect(combined.active!.stage, 2);
      await submit;
      expect(repository.state.active!.stage, 4);
      expect(
        store.writes.map((write) => decode(write.value)['active']['stage']),
        [2, 2, 4],
      );
    },
  );

  test(
    'failed sample completion cannot award progress and retry preserves both answer parts',
    () async {
      final state = sampleDecision()
          .selectAnswerPart('amount', 'eight-of-ten')
          .selectAnswerPart('group', 'testers');
      final store = storeState(state);
      final repository = store.repository();
      store.failNext = true;
      await expectLater(
        repository.submitChoice(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.stage, 2);
      expect(repository.state.active!.answerParts, state.active!.answerParts);
      expect(store.repository().state.completions.keys, [first, second]);
      await repository.submitChoice();
      expect(store.repository().state.active!.stage, 4);
      expect(repository.state.completions.keys, [first, second, sample]);
    },
  );

  test(
    'failed sample correction saves leave the original headline available for retry',
    () async {
      final state = sampleDecision()
          .selectAnswerPart('amount', 'all')
          .selectAnswerPart('group', 'customers');
      final store = storeState(state);
      final repository = store.repository();
      store.failNext = true;
      await expectLater(
        repository.submitChoice(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.stage, 2);
      await repository.submitChoice();
      expect(store.repository().state.active!.stage, 3);
      store.throwNext = true;
      await expectLater(
        repository.acceptCorrection(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.stage, 3);
      expect(store.repository().state.completions.containsKey(sample), isFalse);
      expect(repository.state.active!.answerParts, state.active!.answerParts);
      await repository.acceptCorrection();
      expect(
        store.repository().state.completions[sample]!.selectedChoiceId,
        'all-customers',
      );
    },
  );

  test(
    'duplicate part taps and outcome acknowledgments do not create extra writes',
    () async {
      final store = storeState(sampleDecision());
      final repository = store.repository();
      await repository.selectAnswerPart('amount', 'eight-of-ten');
      await repository.selectAnswerPart('amount', 'eight-of-ten');
      expect(store.writes, hasLength(1));
      await repository.selectAnswerPart('group', 'testers');
      await repository.selectAnswerPart('group', 'testers');
      expect(store.writes, hasLength(2));
      await repository.submitChoice();
      await repository.submitChoice();
      expect(store.writes, hasLength(3));
      expect(repository.state.completions, hasLength(3));
    },
  );

  test(
    'replay starts a fresh headline while preserving first completion identity',
    () async {
      final state = sampleDecision()
          .selectAnswerPart('amount', 'all')
          .selectAnswerPart('group', 'customers')
          .submitChoice(firstTime)
          .acceptCorrection(firstTime)
          .closeActivity();
      final store = storeState(state);
      final repository = store.repository(
        clock: () => firstTime.add(const Duration(days: 1)),
      );
      final original = repository.state.completions[sample]!;
      await repository.startActivity(sample);
      expect(repository.state.active!.answerParts, isEmpty);
      expect(repository.state.active!.selectedChoiceId, isNull);
      await repository.advance();
      await repository.advance();
      await repository.selectAnswerPart('amount', 'eight-of-ten');
      await repository.selectAnswerPart('group', 'testers');
      await repository.submitChoice();
      expect(repository.state.active!.corrected, isFalse);
      expect(identical(repository.state.completions[sample], original), isTrue);
      expect(
        store.repository().state.completions[sample]!.toJson(),
        original.toJson(),
      );
    },
  );

  test(
    'malformed part maps and contradictory combined choices remain protected',
    () async {
      final valid = sampleDecision()
          .selectAnswerPart('amount', 'eight-of-ten')
          .selectAnswerPart('group', 'testers');
      final mutations = <void Function(Map<String, dynamic>)>[
        (data) => (data['active'] as Map).remove('answerParts'),
        (data) => data['active']['answerParts'] = null,
        (data) => data['active']['answerParts'] = [],
        (data) => data['active']['answerParts'] = 'eight-of-ten-testers',
        (data) => data['active']['answerParts']['extra'] = 'testers',
        (data) => data['active']['answerParts']['amount'] = 8,
        (data) => data['active']['answerParts']['amount'] = null,
        (data) => data['active']['answerParts']['amount'] = ['eight-of-ten'],
        (data) =>
            data['active']['answerParts']['amount'] = 'eight-of-ten-testers',
        (data) => data['active']['answerParts']['group'] = 'Testers',
        (data) => data['active']['answerParts'] = {},
        (data) => data['active']['answerParts'] = {'amount': 'eight-of-ten'},
        (data) => data['active']['answerParts']['amount'] = 'all',
        (data) => data['active']['selectedChoiceId'] = null,
        (data) => data['active']['selectedChoiceId'] = 'all-testers',
        (data) => data['active']['corrected'] = true,
        (data) => data['active']['stage'] = 3,
        (data) => data['active']['stage'] = 4,
        (data) => data['completions'].remove(second),
        (data) => data['completions'].remove(first),
      ];
      for (var index = 0; index < mutations.length; index++) {
        final data = decode(jsonEncode(valid.toJson()));
        mutations[index](data);
        final raw = jsonEncode(data);
        final store = MemoryStore()
          ..values[OfficeProgressRepository.saveKey] = raw;
        final repository = store.repository();
        expect(
          repository.loadIssue!.kind,
          ProgressLoadIssueKind.corruptData,
          reason: 'Mutation $index',
        );
        await expectLater(
          repository.selectAnswerPart('group', 'testers'),
          throwsA(isA<ProgressProtectedException>()),
        );
        expect(store.values[OfficeProgressRepository.saveKey], raw);
        expect(store.writes, isEmpty);
      }
    },
  );

  test(
    'older tasks reject answer parts and sample completion rejects a missing prerequisite',
    () {
      final old = OfficeProgress.empty().startActivity(first);
      final olderWithParts = decode(jsonEncode(old.toJson()));
      olderWithParts['active']['answerParts'] = {'group': 'testers'};
      expect(
        () => OfficeProgress.fromJson(olderWithParts),
        throwsFormatException,
      );
      final completed = sampleDecision()
          .selectAnswerPart('amount', 'eight-of-ten')
          .selectAnswerPart('group', 'testers')
          .submitChoice(firstTime)
          .closeActivity();
      final withoutPrerequisite = decode(jsonEncode(completed.toJson()));
      withoutPrerequisite['completions'].remove(second);
      expect(
        () => OfficeProgress.fromJson(withoutPrerequisite),
        throwsFormatException,
      );
    },
  );
}
