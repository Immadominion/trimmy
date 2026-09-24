import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';
import 'package:trimmy/design_study/update_assignment.dart';

const first = OfficeActivityIds.checkTheDate;
const second = OfficeActivityIds.salesAndProfit;
final firstTime = DateTime.utc(2026, 9, 13, 10);

class MemoryStore {
  final values = <String, String>{};
  final writes = <MapEntry<String, String>>[];
  bool failNext = false;
  bool throwNext = false;
  bool failRead = false;
  Completer<bool>? gate;

  String? read(String key) {
    if (failRead) throw StateError('Unavailable storage');
    return values[key];
  }

  Future<bool> write(String key, String value) async {
    writes.add(MapEntry(key, value));
    final pendingGate = gate;
    gate = null;
    if (pendingGate != null && !await pendingGate.future) return false;
    if (throwNext) {
      throwNext = false;
      throw StateError('Unavailable storage');
    }
    if (failNext) {
      failNext = false;
      return false;
    }
    values[key] = value;
    return true;
  }

  OfficeProgressRepository repository({DateTime Function()? clock}) =>
      OfficeProgressRepository(
        read: read,
        write: write,
        clock: clock ?? () => firstTime,
      );
}

Future<void> choose(
  OfficeProgressRepository repository,
  String choice, {
  String activity = first,
}) async {
  await repository.startActivity(activity);
  await repository.advance();
  await repository.advance();
  await repository.selectChoice(choice);
}

Map<String, dynamic> decode(String value) =>
    jsonDecode(value) as Map<String, dynamic>;

Map<String, Object?> legacy({
  bool corrected = false,
  bool includeTime = true,
}) => {
  'version': 1,
  'completed': true,
  'neededCorrection': corrected,
  if (includeTime) 'completedAt': firstTime.toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fresh progress unlocks only the first activity and never writes on read',
    () {
      final store = MemoryStore();
      final repository = store.repository();
      expect(repository.loadIssue, isNull);
      expect(repository.state.active, isNull);
      expect(repository.state.completions, isEmpty);
      expect(repository.state.isUnlocked(first), isTrue);
      expect(repository.state.isUnlocked(second), isFalse);
      expect(repository.state.isUnlocked('unknown'), isFalse);
      expect(store.writes, isEmpty);
    },
  );

  test(
    'pure transitions reject unknown activities and a locked second activity',
    () {
      final state = OfficeProgress.empty();
      expect(() => state.startActivity('unknown'), throwsArgumentError);
      expect(() => state.startActivity(second), throwsStateError);
      expect(() => state.advance(), throwsStateError);
    },
  );

  test(
    'every pre-submission stage resumes and source reinspection preserves selection',
    () async {
      final store = MemoryStore();
      var repository = store.repository();
      await repository.startActivity(first);
      expect(store.repository().state.active!.stage, 0);
      await repository.advance();
      expect(store.repository().state.active!.stage, 1);
      await repository.advance();
      expect(store.repository().state.active!.stage, 2);
      await repository.selectChoice('keep-headline');
      repository = store.repository();
      await repository.inspectStage(1);
      await repository.inspectStage(0);
      await repository.inspectStage(1);
      await repository.inspectStage(2);
      expect(repository.state.active!.selectedChoiceId, 'keep-headline');
      expect(repository.state.active!.corrected, isFalse);
      expect(repository.state.completions, isEmpty);
    },
  );

  test('inspection cannot skip the source, submit, or invent an outcome', () {
    final start = OfficeProgress.empty().startActivity(first);
    expect(() => start.inspectStage(2), throwsStateError);
    expect(() => start.inspectStage(-1), throwsStateError);
    expect(() => start.inspectStage(4), throwsStateError);
    expect(() => start.selectChoice('add-year'), throwsStateError);
    final decision = start.advance().advance();
    expect(() => decision.inspectStage(4), throwsStateError);
    expect(() => decision.advance(), throwsStateError);
    expect(() => decision.submitChoice(firstTime), throwsStateError);
    expect(() => decision.selectChoice('check-costs'), throwsArgumentError);
    expect(() => decision.acceptCorrection(firstTime), throwsStateError);
  });

  test(
    'leaving an unfinished activity preserves its exact resume state',
    () async {
      final store = MemoryStore();
      final repository = store.repository();
      await choose(repository, 'keep-headline');
      final before = store.values[OfficeProgressRepository.saveKey];
      final writeCount = store.writes.length;
      await repository.closeActivity();
      await repository.startActivity(first);
      expect(store.writes, hasLength(writeCount));
      expect(store.values[OfficeProgressRepository.saveKey], before);
      expect(
        store.repository().state.active!.selectedChoiceId,
        'keep-headline',
      );
    },
  );

  test(
    'correct choice saves outcome and first completion in the same write',
    () async {
      final store = MemoryStore();
      final repository = store.repository();
      await choose(repository, 'add-year');
      await repository.submitChoice();
      final restored = store.repository().state;
      expect(restored.active!.stage, 4);
      expect(restored.active!.corrected, isFalse);
      final completion = restored.completions[first]!;
      expect(completion.activityId, first);
      expect(completion.selectedChoiceId, 'add-year');
      expect(completion.corrected, isFalse);
      expect(completion.completedAt, firstTime);
      expect(completion.importedFromLegacy, isFalse);
      expect(restored.isUnlocked(second), isTrue);
      final submittedWrite = decode(store.writes.last.value);
      expect((submittedWrite['active'] as Map)['stage'], 4);
      expect((submittedWrite['completions'] as Map).containsKey(first), isTrue);
    },
  );

  test(
    'incorrect decision resumes correction without prematurely unlocking',
    () async {
      final store = MemoryStore();
      var repository = store.repository();
      await choose(repository, 'keep-headline');
      await repository.submitChoice();
      repository = store.repository();
      expect(repository.state.active!.stage, 3);
      expect(repository.state.active!.selectedChoiceId, 'keep-headline');
      expect(repository.state.active!.corrected, isTrue);
      expect(repository.state.completions, isEmpty);
      expect(repository.state.isUnlocked(second), isFalse);
      await expectLater(repository.inspectStage(1), throwsStateError);
      await repository.acceptCorrection();
      expect(repository.state.active!.stage, 4);
      final completion = store.repository().state.completions[first]!;
      expect(completion.selectedChoiceId, 'keep-headline');
      expect(completion.corrected, isTrue);
      expect(completion.completedAt, firstTime);
    },
  );

  test(
    'the second activity saves independently with its own stable choice IDs',
    () async {
      final store = MemoryStore();
      final repository = store.repository();
      await choose(repository, 'add-year');
      await repository.submitChoice();
      await repository.closeActivity();
      await choose(repository, 'sales-mean-profit', activity: second);
      await repository.submitChoice();
      expect(repository.state.completions.keys, [first]);
      await repository.acceptCorrection();
      expect(store.repository().state.completions.keys, [first, second]);
      expect(
        repository.state.completions[second]!.selectedChoiceId,
        'sales-mean-profit',
      );
      await repository.closeActivity();
      expect(store.repository().state.active, isNull);
    },
  );

  test('a different unfinished activity cannot be overwritten', () async {
    final repository = MemoryStore().repository();
    await choose(repository, 'add-year');
    await repository.submitChoice();
    // A finished active outcome may be replaced by the next unlocked activity.
    await repository.startActivity(second);
    await expectLater(repository.startActivity(first), throwsStateError);
    expect(repository.state.active!.activityId, second);
  });

  test(
    'replay and duplicate submissions preserve first choice, correction and time',
    () async {
      final store = MemoryStore();
      var now = firstTime;
      final repository = store.repository(clock: () => now);
      await choose(repository, 'keep-headline');
      await repository.submitChoice();
      await repository.acceptCorrection();
      final firstRecord = jsonEncode(
        repository.state.completions[first]!.toJson(),
      );
      final writeCount = store.writes.length;
      await repository.acceptCorrection();
      await repository.submitChoice();
      expect(store.writes, hasLength(writeCount));
      await repository.closeActivity();
      now = firstTime.add(const Duration(days: 4));
      await choose(repository, 'add-year');
      await repository.submitChoice();
      expect(repository.state.active!.corrected, isFalse);
      expect(
        jsonEncode(repository.state.completions[first]!.toJson()),
        firstRecord,
      );
      expect(
        jsonEncode(store.repository().state.completions[first]!.toJson()),
        firstRecord,
      );
      expect(
        () => repository.state.completions.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'false save acknowledgments keep decision and unlock state unchanged; retry succeeds',
    () async {
      final store = MemoryStore();
      final repository = store.repository();
      await choose(repository, 'add-year');
      store.failNext = true;
      await expectLater(
        repository.submitChoice(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.stage, 2);
      expect(repository.state.completions, isEmpty);
      expect(repository.state.isUnlocked(second), isFalse);
      expect(store.repository().state.active!.stage, 2);
      await repository.submitChoice();
      expect(repository.state.active!.stage, 4);
      expect(repository.state.isUnlocked(second), isTrue);
    },
  );

  test(
    'thrown correction save failures preserve correction screen and can be retried',
    () async {
      final store = MemoryStore();
      final repository = store.repository();
      await choose(repository, 'keep-headline');
      await repository.submitChoice();
      store.throwNext = true;
      await expectLater(
        repository.acceptCorrection(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.stage, 3);
      expect(repository.state.completions, isEmpty);
      await repository.acceptCorrection();
      expect(repository.state.active!.stage, 4);
    },
  );

  test(
    'writes are serial and UI state stays unchanged until acknowledgment',
    () async {
      final store = MemoryStore();
      final gate = Completer<bool>();
      store.gate = gate;
      final repository = store.repository();
      final starting = repository.startActivity(first);
      final advancing = repository.advance();
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, hasLength(1));
      expect(repository.state.active, isNull);
      gate.complete(true);
      await Future.wait([starting, advancing]);
      expect(store.writes, hasLength(2));
      expect((decode(store.writes[0].value)['active'] as Map)['stage'], 0);
      expect((decode(store.writes[1].value)['active'] as Map)['stage'], 1);
      expect(repository.state.active!.stage, 1);
    },
  );

  test(
    'queued transitions cannot run from a failed save and the queue recovers',
    () async {
      final store = MemoryStore();
      final gate = Completer<bool>();
      store.gate = gate;
      final repository = store.repository();
      final starting = expectLater(
        repository.startActivity(first),
        throwsA(isA<ProgressSaveException>()),
      );
      final advancing = expectLater(repository.advance(), throwsStateError);
      gate.complete(false);
      await Future.wait([starting, advancing]);
      expect(repository.state.active, isNull);
      expect(store.writes, hasLength(1));
      await repository.startActivity(first);
      await repository.advance();
      expect(repository.state.active!.stage, 1);
    },
  );

  test(
    'legacy migration preserves correction and time without touching legacy data',
    () async {
      final store = MemoryStore();
      final original = jsonEncode(legacy(corrected: true));
      store.values[OfficeProgressRepository.legacyKey] = original;
      final repository = store.repository();
      final migrated = repository.state.completions[first]!;
      expect(migrated.corrected, isTrue);
      expect(migrated.selectedChoiceId, 'keep-headline');
      expect(migrated.completedAt, firstTime);
      expect(migrated.importedFromLegacy, isTrue);
      expect(repository.state.isUnlocked(second), isTrue);
      expect(store.writes, isEmpty);
      await repository.startActivity(second);
      expect(store.values[OfficeProgressRepository.legacyKey], original);
      expect(
        store.writes.every(
          (entry) => entry.key == OfficeProgressRepository.saveKey,
        ),
        isTrue,
      );
      expect(
        store.repository().state.completions[first]!.completedAt,
        firstTime,
      );
    },
  );

  test(
    'legacy missing time stays unknown through migration and replay',
    () async {
      final store = MemoryStore();
      store.values[OfficeProgressRepository.legacyKey] = jsonEncode(
        legacy(includeTime: false),
      );
      final repository = store.repository();
      expect(repository.state.completions[first]!.completedAt, isNull);
      await choose(repository, 'keep-headline');
      await repository.submitChoice();
      await repository.acceptCorrection();
      final completion = store.repository().state.completions[first]!;
      expect(completion.completedAt, isNull);
      expect(completion.selectedChoiceId, 'add-year');
      expect(completion.corrected, isFalse);
    },
  );

  test('legacy false completion never awards progress', () {
    final store = MemoryStore();
    store.values[OfficeProgressRepository.legacyKey] = jsonEncode({
      'version': 1,
      'completed': false,
    });
    final repository = store.repository();
    expect(repository.loadIssue, isNull);
    expect(repository.state.completions, isEmpty);
    expect(repository.state.isUnlocked(second), isFalse);
  });

  test(
    'an existing current record takes precedence over a legacy completion',
    () {
      final store = MemoryStore();
      store.values[OfficeProgressRepository.legacyKey] = jsonEncode(legacy());
      store.values[OfficeProgressRepository.saveKey] = jsonEncode(
        OfficeProgress.empty().toJson(),
      );
      expect(store.repository().state.completions, isEmpty);
    },
  );

  test(
    'corrupt current data cannot fall back to legacy or be overwritten',
    () async {
      final store = MemoryStore();
      store.values[OfficeProgressRepository.legacyKey] = jsonEncode(legacy());
      store.values[OfficeProgressRepository.saveKey] = '{broken';
      final repository = store.repository();
      expect(repository.loadIssue!.kind, ProgressLoadIssueKind.corruptData);
      await expectLater(
        repository.startActivity(first),
        throwsA(isA<ProgressProtectedException>()),
      );
      expect(store.values[OfficeProgressRepository.saveKey], '{broken');
      expect(store.writes, isEmpty);
    },
  );

  test(
    'future current and legacy versions stay protected until an explicit reload',
    () async {
      for (final key in [
        OfficeProgressRepository.saveKey,
        OfficeProgressRepository.legacyKey,
      ]) {
        final store = MemoryStore();
        final version = key == OfficeProgressRepository.saveKey ? 7 : 2;
        store.values[key] = '{"version":$version,"unrecognized":"preserve me"}';
        final repository = store.repository();
        expect(
          repository.loadIssue!.kind,
          ProgressLoadIssueKind.unsupportedVersion,
        );
        await expectLater(
          repository.startActivity(first),
          throwsA(isA<ProgressProtectedException>()),
        );
        expect(store.writes, isEmpty);
        store.values.remove(key);
        await repository.retryLoad();
        expect(repository.loadIssue, isNull);
        await repository.startActivity(first);
        expect(repository.state.active!.stage, 0);
      }
    },
  );

  test(
    'read failures surface and recover without deleting saved data',
    () async {
      final store = MemoryStore()..failRead = true;
      final repository = store.repository();
      expect(
        repository.loadIssue!.kind,
        ProgressLoadIssueKind.storageReadFailed,
      );
      await expectLater(
        repository.startActivity(first),
        throwsA(isA<ProgressProtectedException>()),
      );
      store.failRead = false;
      store.values[OfficeProgressRepository.legacyKey] = jsonEncode(legacy());
      await repository.retryLoad();
      expect(repository.loadIssue, isNull);
      expect(repository.state.isUnlocked(second), isTrue);
      expect(store.writes, isEmpty);
    },
  );

  test(
    'malformed records and impossible states are protected without writes',
    () async {
      final decision = OfficeProgress.empty()
          .startActivity(first)
          .advance()
          .advance();
      final valid = decision.selectChoice('add-year').submitChoice(firstTime);
      final mutations = <void Function(Map<String, dynamic>)>[
        (data) => data['version'] = 1.0,
        (data) => data['extra'] = 'unknown',
        (data) => data['completions'] = [],
        (data) => data['active']['stage'] = '4',
        (data) => data['active']['stage'] = 2.5,
        (data) => data['active']['stage'] = 5,
        (data) => data['active']['selectedChoiceId'] = null,
        (data) => data['active']['selectedChoiceId'] = 'check-costs',
        (data) => data['active']['corrected'] = true,
        (data) => data['active']['activityId'] = second,
        (data) => data['completions'] = {},
        (data) => data['completions'][first]['corrected'] = true,
        (data) => data['completions'][first]['completedAt'] = null,
        (data) => data['completions'][first]['completedAt'] =
            '2026-02-31T10:00:00.000Z',
        (data) =>
            data['completions'][first]['completedAt'] = '2026-09-13T10:00:00',
        (data) => data['completions'][first]['activityId'] = second,
        (data) => data['completions'][first]['selectedChoiceId'] = 0,
      ];
      for (var index = 0; index < mutations.length; index++) {
        final data = decode(jsonEncode(valid.toJson()));
        mutations[index](data);
        final raw = jsonEncode(data);
        final store = MemoryStore();
        store.values[OfficeProgressRepository.saveKey] = raw;
        final repository = store.repository();
        expect(repository.loadIssue, isNotNull, reason: 'Mutation $index');
        await expectLater(
          repository.closeActivity(),
          throwsA(isA<ProgressProtectedException>()),
        );
        expect(store.values[OfficeProgressRepository.saveKey], raw);
        expect(store.writes, isEmpty);
      }
    },
  );

  test('oversized saves and malformed legacy records are protected', () {
    final malformed = [
      'x' * 32769,
      'null',
      '[]',
      '{"version":1,"completed":"true"}',
      '{"version":1,"completed":true,"neededCorrection":"false"}',
      '{"version":1,"completed":true,"completedAt":"yesterday"}',
    ];
    for (final raw in malformed) {
      final store = MemoryStore();
      store.values[OfficeProgressRepository.legacyKey] = raw;
      expect(
        store.repository().loadIssue!.kind,
        ProgressLoadIssueKind.corruptData,
      );
      expect(store.writes, isEmpty);
    }
  });

  test(
    'SharedPreferences adapter restores data and writes only the new key',
    () async {
      final original = jsonEncode(legacy(corrected: true));
      SharedPreferences.setMockInitialValues({
        OfficeProgressRepository.legacyKey: original,
      });
      final preferences = await SharedPreferences.getInstance();
      final repository = OfficeProgressRepository.fromPreferences(preferences);
      await repository.startActivity(second);
      expect(
        preferences.getString(OfficeProgressRepository.legacyKey),
        original,
      );
      expect(
        decode(
          preferences.getString(OfficeProgressRepository.saveKey)!,
        )['version'],
        6,
      );
      final restored = OfficeProgressRepository.fromPreferences(preferences);
      expect(restored.state.active!.activityId, second);
      expect(restored.state.completions[first]!.corrected, isTrue);
    },
  );
  test(
    'failed selection and close writes keep the last acknowledged state',
    () async {
      final store = MemoryStore();
      final repository = store.repository();
      await choose(repository, 'keep-headline');
      store.failNext = true;
      await expectLater(
        repository.selectChoice('add-year'),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.selectedChoiceId, 'keep-headline');
      await repository.selectChoice('add-year');
      await repository.submitChoice();
      store.failNext = true;
      await expectLater(
        repository.closeActivity(),
        throwsA(isA<ProgressSaveException>()),
      );
      expect(repository.state.active!.stage, 4);
      expect(repository.state.completions, hasLength(1));
      await repository.closeActivity();
      expect(repository.state.active, isNull);
      expect(repository.state.completions, hasLength(1));
    },
  );

  test(
    'retry refresh failure remains protected and does not mutate saved data',
    () async {
      final store = MemoryStore();
      store.values[OfficeProgressRepository.saveKey] = '{broken';
      var refreshFails = true;
      final repository = OfficeProgressRepository(
        read: store.read,
        write: store.write,
        refresh: () async {
          if (refreshFails) throw StateError('Storage unavailable');
        },
      );
      await repository.retryLoad();
      expect(
        repository.loadIssue!.kind,
        ProgressLoadIssueKind.storageReadFailed,
      );
      expect(store.values[OfficeProgressRepository.saveKey], '{broken');
      expect(store.writes, isEmpty);
      refreshFails = false;
      store.values[OfficeProgressRepository.saveKey] = jsonEncode(
        OfficeProgress.empty().toJson(),
      );
      await repository.retryLoad();
      expect(repository.loadIssue, isNull);
      expect(store.writes, isEmpty);
    },
  );

  test(
    'SharedPreferences retry refreshes its cache to see an externally repaired record',
    () async {
      SharedPreferences.setMockInitialValues({
        OfficeProgressRepository.saveKey: '{broken',
      });
      final preferences = await SharedPreferences.getInstance();
      final repository = OfficeProgressRepository.fromPreferences(preferences);
      expect(repository.loadIssue!.kind, ProgressLoadIssueKind.corruptData);
      SharedPreferences.setMockInitialValues({
        OfficeProgressRepository.saveKey: jsonEncode(
          OfficeProgress.empty().toJson(),
        ),
      });
      // The original preferences object still contains its earlier cached value.
      expect(
        preferences.getString(OfficeProgressRepository.saveKey),
        '{broken',
      );
      await repository.retryLoad();
      expect(repository.loadIssue, isNull);
      await repository.startActivity(first);
      expect(repository.state.active!.stage, 0);
    },
  );
  test(
    'authored activities and progress agree on every stable choice and its outcome',
    () {
      expect(
        studyActivities.map((activity) => activity.id),
        OfficeActivityIds.all,
      );
      var unlocked = OfficeProgress.empty();
      for (final activity in studyActivities) {
        final usesParts = activity.id == OfficeActivityIds.checkTheSample;
        final usesFacts = activity.id == OfficeActivityIds.prepareTheUpdate;
        final choiceCount = practiceCatalogById[activity.id]!.choiceIds.length;
        OfficeProgress select(OfficeProgress state, String choiceId) {
          if (usesFacts) {
            for (final fact in updateChoiceFacts(choiceId)) {
              state = state.selectAnswerPart(fact.id, 'included');
            }
            return state;
          }
          if (!usesParts) return state.selectChoice(choiceId);
          final amount = choiceId.startsWith('eight-of-ten-')
              ? 'eight-of-ten'
              : 'all';
          final group = choiceId.endsWith('-testers') ? 'testers' : 'customers';
          return state
              .selectAnswerPart('amount', amount)
              .selectAnswerPart('group', group);
        }

        expect(activity.choices, hasLength(choiceCount));
        expect(
          activity.choices.map((choice) => choice.id).toSet(),
          hasLength(choiceCount),
        );
        expect(
          activity.choices.where(
            (choice) => choice.id == activity.correctChoiceId,
          ),
          hasLength(1),
        );
        for (final choice in activity.choices) {
          final decision = unlocked
              .startActivity(activity.id)
              .advance()
              .advance();
          final outcome = select(decision, choice.id).submitChoice(firstTime);
          final isCorrect = activity.effectiveAcceptedChoiceIds.contains(
            choice.id,
          );
          expect(
            outcome.active!.stage,
            isCorrect ? 4 : 3,
            reason: '${activity.id}/${choice.id}',
          );
          final completed = isCorrect
              ? outcome
              : outcome.acceptCorrection(firstTime);
          final restored = OfficeProgress.fromJson(
            decode(jsonEncode(completed.toJson())),
          );
          final record = restored.completions[activity.id]!;
          expect(record.selectedChoiceId, choice.id);
          expect(record.corrected, !isCorrect);
        }
        final decision = unlocked
            .startActivity(activity.id)
            .advance()
            .advance();
        unlocked = select(
          decision,
          activity.correctChoiceId,
        ).submitChoice(firstTime).closeActivity();
      }
    },
  );
}
