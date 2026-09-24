import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/core/audio/practice_audio.dart';
import 'package:trimmy/features/journey/journey_catalog.dart';
import 'package:trimmy/features/journey/journey_progress.dart';
import 'package:trimmy/features/practice/practice_controller.dart';

import 'practice_test.dart' show MemoryPracticeStore, saved;

Future<void> reachReflection(PracticeController controller, String id) async {
  await controller.startJourney(id);
  await controller.advanceJourney();
  for (var i = 0; i < 3; i++) {
    await controller.answerJourney(i);
    await controller.advanceJourney();
  }
}

Future<void> finish(
  PracticeController controller,
  String id, [
  String reflection = 'Keep the evidence separate from the story.',
]) async {
  await reachReflection(controller, id);
  await controller.updateJourneyReflection(reflection);
  await controller.completeJourney();
}

Future<PracticeController> reopen(
  MemoryPracticeStore store,
  DateTime Function() clock,
) => PracticeController.load(
  store: store,
  audio: SilentPracticeAudio(),
  clock: clock,
);

Map<String, Object?> journeyState({
  Object? session,
  List<Object?> completions = const [],
  Map<String, Object?> activity = const {},
}) => saved(
  values: {
    'version': 2,
    'journey': {
      'session': session,
      'completions': completions,
      'activityByChapter': activity,
    },
  },
);

Map<String, Object?> completionRecord(
  String id, {
  String reflection = 'A useful note.',
}) => {
  'chapterId': id,
  'reflection': reflection,
  'completedAt': '2026-09-13T10:00:00.000Z',
};

void main() {
  test(
    'Unicode note limits match Flutter text-field character counts',
    () async {
      final store = MemoryPracticeStore();
      final controller = PracticeController(store: store);
      final note = '👩🏾‍💻' * 500;
      await controller.saveBrief(choice: 1, note: note);
      await controller.saveDraft(handle: '@friend', message: note);
      await reachReflection(controller, 'first-floor');
      await controller.updateJourneyReflection(note);
      final restored = await reopen(store, () => DateTime(2026, 9, 13));
      expect(restored.journalNote, note);
      expect(restored.drafts.single.message, note);
      expect(restored.activeSession!.reflection, note);
      expect(restored.storageWarning, isNull);
      expect(
        () => restored.updateJourneyReflection('$note👩🏾‍💻'),
        throwsArgumentError,
      );
      await restored.completeJourney();
      final completed = await reopen(store, () => DateTime(2026, 9, 13));
      expect(completed.chapterCompletions['first-floor']!.reflection, note);
      await controller.close();
      await restored.close();
      await completed.close();
    },
  );

  test(
    'calendar date and write flush use the same injected state as the UI',
    () async {
      final store = MemoryPracticeStore();
      final controller = PracticeController(
        store: store,
        clock: () => DateTime(2026, 9, 13, 23, 59, 58),
      );
      expect(controller.currentLocalDate, DateTime(2026, 9, 13));
      expect(controller.currentLocalDate.isUtc, isFalse);
      controller.setTab(2);
      await controller.flushPendingWrites();
      expect(jsonDecode(store.value!)['tab'], 2);
      // Flushing is non-destructive: the controller remains usable afterwards.
      await controller.startJourney();
      expect(controller.activeSession, isNotNull);
      await controller.close();
    },
  );

  test('catalog provides three complete, distinct five-step sessions', () {
    expect(journeyChapters.map((chapter) => chapter.id).toSet(), hasLength(3));
    for (final chapter in journeyChapters) {
      expect(chapter.steps, hasLength(5));
      expect(chapter.steps.map((step) => step.id).toSet(), hasLength(5));
      expect(chapter.steps.first.kind, JourneyStepKind.intro);
      expect(chapter.steps.last.kind, JourneyStepKind.reflection);
      for (final decision in chapter.steps.skip(1).take(3)) {
        expect(decision.kind, JourneyStepKind.decision);
        expect(decision.choices, hasLength(3));
        expect(decision.question, isNotEmpty);
        for (final choice in decision.choices) {
          expect(choice.label, isNotEmpty);
          expect(choice.feedback, isNotEmpty);
        }
      }
    }
    expect(journeyChapterById('first-floor'), same(firstFloorChapter));
    expect(journeyChapterById('unknown'), isNull);
  });

  test(
    'chapter prerequisites and active-session ownership prevent lost progress',
    () async {
      final controller = PracticeController(store: MemoryPracticeStore());
      expect(controller.nextChapter, same(firstFloorChapter));
      expect(controller.isChapterUnlocked('unknown'), isFalse);
      expect(controller.isChapterUnlocked('read-the-room'), isFalse);
      expect(() => controller.startJourney('unknown'), throwsArgumentError);
      expect(() => controller.startJourney('read-the-room'), throwsStateError);
      await finish(controller, 'first-floor');
      expect(controller.isChapterUnlocked('read-the-room'), isTrue);
      expect(controller.nextChapter, same(readTheRoomChapter));
      await controller.startJourney('read-the-room');
      await controller.advanceJourney();
      await controller.startJourney('read-the-room');
      expect(controller.activeSession!.stepIndex, 1);
      expect(() => controller.startJourney('first-floor'), throwsStateError);
      await controller.resetJourneySession();
      expect(controller.activeSession, isNull);
      expect(controller.completedChapterIds, {'first-floor'});
      await controller.close();
    },
  );

  test('completion cannot skip decisions or the reflection', () async {
    final controller = PracticeController(store: MemoryPracticeStore());
    await controller.completeJourney();
    expect(controller.learningPoints, 0);
    await controller.startJourney();
    expect(() => controller.answerJourney(0), throwsStateError);
    expect(
      () => controller.updateJourneyReflection('Too early'),
      throwsStateError,
    );
    expect(() => controller.completeJourney(), throwsStateError);
    await controller.advanceJourney();
    expect(controller.canAdvanceJourney, isFalse);
    expect(() => controller.advanceJourney(), throwsStateError);
    expect(() => controller.answerJourney(3), throwsRangeError);
    for (var i = 0; i < 3; i++) {
      await controller.answerJourney(i);
      expect(controller.journeyFeedback, isNotEmpty);
      await controller.advanceJourney();
    }
    expect(controller.currentJourneyStep!.kind, JourneyStepKind.reflection);
    expect(() => controller.advanceJourney(), throwsStateError);
    await controller.updateJourneyReflection('   ');
    expect(controller.canAdvanceJourney, isFalse);
    expect(() => controller.completeJourney(), throwsStateError);
    expect(
      () => controller.updateJourneyReflection('x' * 501),
      throwsArgumentError,
    );
    await controller.updateJourneyReflection('  A question worth keeping.  ');
    expect(controller.canAdvanceJourney, isTrue);
    await controller.completeJourney();
    expect(
      controller.chapterCompletions['first-floor']!.reflection,
      'A question worth keeping.',
    );
    expect(controller.activeSession, isNull);
    expect(controller.learningPoints, 30);
    await controller.close();
  });

  test('an interrupted answer resumes the same step and feedback', () async {
    final store = MemoryPracticeStore();
    DateTime clock() => DateTime(2026, 9, 13, 12);
    final first = PracticeController(store: store, clock: clock);
    await first.startJourney();
    await first.advanceJourney();
    await first.answerJourney(0);
    await first.advanceJourney();
    await first.answerJourney(1);
    final feedback = first.journeyFeedback;
    await first.close();
    final restored = await reopen(store, clock);
    expect(restored.currentJourneyStep!.id, 'fees');
    expect(restored.activeSession!.stepIndex, 2);
    expect(restored.activeSession!.answers, {'business-model': 0, 'fees': 1});
    expect(restored.journeyFeedback, feedback);
    expect(restored.canAdvanceJourney, isTrue);
    expect(restored.completedChapterIds, isEmpty);
    expect(restored.activityDates, isEmpty);
    expect(
      () => restored.activeSession!.answers.clear(),
      throwsUnsupportedError,
    );
    await restored.close();
  });

  test(
    'unfinished reflection restores without prematurely awarding completion',
    () async {
      final store = MemoryPracticeStore();
      DateTime clock() => DateTime(2026, 9, 13, 12);
      final first = PracticeController(store: store, clock: clock);
      await reachReflection(first, 'first-floor');
      await first.updateJourneyReflection('  A thought still in progress');
      await first.close();
      final restored = await reopen(store, clock);
      expect(restored.activeSession!.stepIndex, 4);
      expect(
        restored.activeSession!.reflection,
        '  A thought still in progress',
      );
      expect(restored.learningPoints, 0);
      expect(restored.activeToday, isFalse);
      await restored.completeJourney();
      expect(restored.learningPoints, 30);
      final complete = await reopen(store, clock);
      expect(complete.activeSession, isNull);
      expect(complete.completedChapterIds, {'first-floor'});
      expect(complete.activeToday, isTrue);
      await restored.close();
      await complete.close();
    },
  );

  test(
    'schema 1 migrates without inventing learning points or dropping old content',
    () async {
      final original = jsonEncode(
        saved(
          values: {
            'soundEnabled': true,
            'reduceMotion': true,
            'hasMetOffice': true,
            'selectedChoice': 2,
            'journalNote': 'My earlier note.',
            'drafts': [
              {
                'handle': '@friend',
                'message': 'An old offer.',
                'createdAt': '2026-09-12T10:00:00.000Z',
              },
            ],
          },
        ),
      );
      final store = MemoryPracticeStore()..value = original;
      final controller = await reopen(store, () => DateTime(2026, 9, 13));
      expect(store.value, original);
      expect(controller.storageWarning, isNull);
      expect(controller.soundEnabled, isTrue);
      expect(controller.reduceMotion, isTrue);
      expect(controller.briefCompleted, isTrue);
      expect(controller.journalNote, 'My earlier note.');
      expect(controller.drafts.single.message, 'An old offer.');
      expect(controller.completedChapterIds, isEmpty);
      expect(controller.learningPoints, 0);
      expect(controller.currentStreak, 0);
      await controller.startJourney();
      expect(jsonDecode(store.value!)['version'], 2);
      expect(jsonDecode(store.value!)['journalNote'], 'My earlier note.');
      await controller.close();
    },
  );

  test(
    'multiple new chapters on one local date earn distinct points but one day',
    () async {
      final controller = PracticeController(
        store: MemoryPracticeStore(),
        clock: () => DateTime(2026, 9, 13, 12),
      );
      await finish(controller, 'first-floor');
      await finish(controller, 'read-the-room');
      expect(controller.learningPoints, 60);
      expect(controller.activityDates, ['2026-09-13']);
      expect(controller.currentStreak, 1);
      expect(controller.longestStreak, 1);
      expect(controller.activeToday, isTrue);
      expect(controller.nextChapter, same(longViewChapter));
      await finish(controller, 'the-long-view');
      expect(controller.nextChapter, isNull);
      expect(controller.learningPoints, 90);
      expect(controller.activityDates, hasLength(1));
      await controller.close();
    },
  );

  test(
    'local midnight counts a new day without requiring 24 elapsed hours',
    () async {
      var now = DateTime(2026, 9, 13, 23, 59);
      final controller = PracticeController(
        store: MemoryPracticeStore(),
        clock: () => now,
      );
      await finish(controller, 'first-floor');
      now = DateTime(2026, 9, 14, 0, 1);
      expect(controller.activeToday, isFalse);
      expect(controller.currentStreak, 1); // Yesterday is still a live streak.
      await finish(controller, 'read-the-room');
      expect(controller.activityDates, ['2026-09-13', '2026-09-14']);
      expect(controller.currentStreak, 2);
      expect(controller.longestStreak, 2);
      now = DateTime(2026, 9, 16, 12);
      expect(controller.currentStreak, 0);
      await finish(controller, 'the-long-view');
      expect(controller.currentStreak, 1);
      expect(controller.longestStreak, 2);
      await controller.close();
    },
  );

  test(
    'replaying or duplicate completion never farms points or activity dates',
    () async {
      var now = DateTime(2026, 9, 13, 12);
      final controller = PracticeController(
        store: MemoryPracticeStore(),
        clock: () => now,
      );
      await finish(controller, 'first-floor', 'Original thought.');
      final originalTime =
          controller.chapterCompletions['first-floor']!.completedAt;
      await controller.completeJourney();
      now = DateTime(2026, 9, 14, 12);
      await finish(controller, 'first-floor', 'A more considered reflection.');
      await controller.completeJourney();
      expect(controller.learningPoints, 30);
      expect(controller.activityDates, ['2026-09-13']);
      expect(controller.activeToday, isFalse);
      expect(
        controller.chapterCompletions['first-floor']!.completedAt,
        originalTime,
      );
      expect(
        controller.chapterCompletions['first-floor']!.reflection,
        'A more considered reflection.',
      );
      await controller.close();
    },
  );

  test(
    'clock rollback preserves completion while refusing an earlier day credit',
    () async {
      var now = DateTime(2026, 9, 14, 12);
      final store = MemoryPracticeStore();
      final controller = PracticeController(store: store, clock: () => now);
      await finish(controller, 'first-floor');
      now = DateTime(2026, 9, 13, 12);
      expect(controller.clockWarning, isNotNull);
      expect(controller.currentStreak, 0);
      await finish(controller, 'read-the-room');
      expect(controller.learningPoints, 60);
      expect(controller.activityDates, ['2026-09-14']);
      final restored = await reopen(store, () => now);
      expect(restored.clockWarning, isNotNull);
      expect(restored.learningPoints, 60);
      now = DateTime(2026, 9, 15, 12);
      expect(restored.clockWarning, isNull);
      await finish(restored, 'read-the-room');
      expect(restored.activityDates, ['2026-09-14']);
      await finish(restored, 'the-long-view');
      expect(restored.currentStreak, 2);
      await controller.close();
      await restored.close();
    },
  );

  test(
    'malformed future-step answers roll back to the earliest unanswered step',
    () async {
      final store = MemoryPracticeStore()
        ..value = jsonEncode(
          journeyState(
            session: {
              'chapterId': 'first-floor',
              'stepIndex': 4,
              'answers': {
                'business-model': 99,
                'fees': 1,
                'diversification': 2,
                'invented': 0,
              },
              'reflection': 'This alone cannot complete a chapter.',
            },
          ),
        );
      final controller = await reopen(store, () => DateTime(2026, 9, 13));
      expect(controller.storageWarning, isNotNull);
      expect(controller.activeSession!.stepIndex, 1);
      expect(controller.activeSession!.answers, isEmpty);
      expect(controller.canAdvanceJourney, isFalse);
      expect(() => controller.completeJourney(), throwsStateError);
      expect(controller.learningPoints, 0);
      await controller.close();
    },
  );

  test(
    'invalid and duplicate completion/date records cannot inflate progression',
    () async {
      final store = MemoryPracticeStore()
        ..value = jsonEncode(
          journeyState(
            completions: [
              completionRecord('first-floor'),
              completionRecord('first-floor'),
              completionRecord('the-long-view'),
              completionRecord('unknown'),
            ],
            activity: {
              'first-floor': '2026-02-31',
              'the-long-view': '2026-09-13',
              'invented': '2099-09-13',
            },
            session: {
              'chapterId': 'the-long-view',
              'stepIndex': 0,
              'answers': {},
              'reflection': '',
            },
          ),
        );
      final controller = await reopen(store, () => DateTime(2026, 9, 13));
      expect(controller.storageWarning, isNotNull);
      expect(controller.learningPoints, 30);
      expect(controller.completedChapterIds, {'first-floor'});
      expect(controller.isChapterUnlocked('the-long-view'), isFalse);
      expect(controller.activityDates, isEmpty);
      expect(controller.activeSession, isNull);
      expect(parseDateKey('2026-02-31'), isNull);
      expect(
        parseDateKey(
          '2026-09-13',
        )!.difference(parseDateKey('2026-09-12')!).inDays,
        1,
      );
      await controller.close();
    },
  );

  test(
    'storage failure keeps resumable session state and the next write retries',
    () async {
      final store = MemoryPracticeStore();
      final controller = PracticeController(store: store);
      await controller.startJourney();
      await controller.advanceJourney();
      store.failuresRemaining = 1;
      await controller.answerJourney(0);
      expect(controller.storageWarning, isNotNull);
      expect(controller.journeyFeedback, isNotEmpty);
      await controller.advanceJourney();
      expect(controller.storageWarning, isNull);
      final restored = await reopen(store, () => DateTime(2026, 9, 13));
      expect(restored.activeSession!.stepIndex, 2);
      expect(restored.activeSession!.answers['business-model'], 0);
      await controller.close();
      await restored.close();
    },
  );

  test(
    'clear practice also clears journey history while keeping preferences',
    () async {
      final store = MemoryPracticeStore();
      final controller = PracticeController(store: store);
      await controller.setSound(true);
      await controller.setReduceMotion(true);
      await finish(controller, 'first-floor');
      await controller.startJourney('read-the-room');
      await controller.clearPractice();
      expect(controller.completedChapterIds, isEmpty);
      expect(controller.activityDates, isEmpty);
      expect(controller.learningPoints, 0);
      expect(controller.activeSession, isNull);
      expect(controller.soundEnabled, isTrue);
      expect(controller.reduceMotion, isTrue);
      final restored = await reopen(store, () => DateTime(2026, 9, 13));
      expect(restored.learningPoints, 0);
      expect(restored.activeSession, isNull);
      expect(restored.soundEnabled, isTrue);
      await controller.close();
      await restored.close();
    },
  );
}
