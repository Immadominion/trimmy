import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/core/audio/practice_audio.dart';
import 'package:trimmy/features/practice/practice_controller.dart';

class MemoryPracticeStore implements PracticeStore {
  String? value;
  bool failReads = false;
  int failuresRemaining = 0;
  int activeWrites = 0;
  int maximumActiveWrites = 0;
  Completer<void>? nextWriteGate;
  final snapshots = <String>[];

  @override
  Future<String?> read() async {
    if (failReads) throw StateError('Storage unavailable');
    return value;
  }

  @override
  Future<void> write(String value) async {
    activeWrites++;
    if (activeWrites > maximumActiveWrites) maximumActiveWrites = activeWrites;
    final gate = nextWriteGate;
    nextWriteGate = null;
    snapshots.add(value);
    try {
      if (gate != null) await gate.future;
      if (failuresRemaining > 0) {
        failuresRemaining--;
        throw StateError('Disk full');
      }
      this.value = value;
    } finally {
      activeWrites--;
    }
  }
}

class RecordingPracticeAudio implements PracticeAudio {
  bool enabled = false;
  int closes = 0;
  final cues = <String>[];
  @override
  void setEnabled(bool value) => enabled = value;
  @override
  void cue(String filename) => cues.add(filename);
  @override
  Future<void> close() async => closes++;
}

Map<String, Object?> saved({Map<String, Object?> values = const {}}) => {
  'version': 1,
  'tab': 0,
  'soundEnabled': false,
  'reduceMotion': false,
  'hasMetOffice': false,
  'selectedChoice': null,
  'journalNote': '',
  'drafts': <Object?>[],
  ...values,
};

Future<PracticeController> restore(MemoryPracticeStore store) =>
    PracticeController.load(store: store, audio: SilentPracticeAudio());

void main() {
  test('a fresh controller is silent and incomplete', () async {
    final controller = await restore(MemoryPracticeStore());
    expect(controller.tab, 0);
    expect(controller.soundEnabled, isFalse);
    expect(controller.reduceMotion, isFalse);
    expect(controller.hasMetOffice, isFalse);
    expect(controller.briefCompleted, isFalse);
    expect(controller.selectedChoice, isNull);
    expect(controller.journalNote, isEmpty);
    expect(controller.drafts, isEmpty);
    expect(controller.storageWarning, isNull);
    await controller.close();
  });

  test('restores the persisted practice flow and settings', () async {
    final store = MemoryPracticeStore();
    final first = PracticeController(store: store);
    await first.setSound(true);
    await first.setReduceMotion(true);
    await first.meetOffice();
    await first.saveBrief(choice: 2, note: '  Understand the business.  ');
    await first.saveDraft(handle: 'trimmyhq', message: '  Bring a question.  ');
    first.setTab(2);
    await first.close();

    final restored = await restore(store);
    expect(restored.tab, 2);
    expect(restored.soundEnabled, isTrue);
    expect(restored.reduceMotion, isTrue);
    expect(restored.hasMetOffice, isTrue);
    expect(restored.briefCompleted, isTrue);
    expect(restored.selectedChoice, 2);
    expect(restored.journalNote, 'Understand the business.');
    expect(restored.drafts.single.handle, '@trimmyhq');
    expect(restored.drafts.single.message, 'Bring a question.');
    expect(restored.drafts.single.createdAt.isUtc, isTrue);
    expect(restored.storageWarning, isNull);
    expect(jsonDecode(store.value!)['version'], 2);
    await restored.close();
  });

  test(
    'malformed JSON is recoverable and the next edit saves clean data',
    () async {
      final store = MemoryPracticeStore()..value = '{broken';
      final controller = await restore(store);
      expect(controller.storageWarning, isNotNull);
      expect(
        store.value,
        '{broken',
      ); // Reading does not silently rewrite storage.
      await controller.saveBrief(choice: 0, note: 'A fresh start.');
      expect(controller.storageWarning, isNull);
      final result = await restore(store);
      expect(result.journalNote, 'A fresh start.');
      await controller.close();
      await result.close();
    },
  );

  test(
    'valid settings survive corrupt progress fields and draft values',
    () async {
      final store = MemoryPracticeStore()
        ..value = jsonEncode(
          saved(
            values: {
              'tab': 99,
              'soundEnabled': true,
              'reduceMotion': 'yes',
              'selectedChoice': 8,
              'journalNote': 'Do not attach this to a different choice.',
              'drafts': [
                {'handle': '@bad!'},
                {
                  'handle': '@valid_user',
                  'message': 'A valid draft',
                  'createdAt': '2026-09-13T10:00:00.000Z',
                },
                {
                  'handle': '@invalid_date',
                  'message': 'Hello',
                  'createdAt': 'yesterday',
                },
              ],
            },
          ),
        );
      final controller = await restore(store);
      expect(controller.tab, 0);
      expect(controller.soundEnabled, isTrue);
      expect(controller.reduceMotion, isFalse);
      expect(controller.selectedChoice, isNull);
      expect(controller.journalNote, isEmpty);
      expect(controller.briefCompleted, isFalse);
      expect(controller.drafts.single.handle, '@valid_user');
      expect(controller.storageWarning, isNotNull);
      await controller.close();
    },
  );

  test('future saves are preserved through edits and clear', () async {
    final original = jsonEncode({
      'version': 9,
      'unknownFutureStructure': ['keep', 'all', 'of', 'this'],
    });
    final store = MemoryPracticeStore()..value = original;
    final controller = await restore(store);
    expect(controller.storageWarning, contains('newer app'));
    await controller.setSound(true);
    await controller.saveBrief(choice: 1, note: 'Only this session.');
    await controller.saveDraft(handle: '@friend', message: 'Hello.');
    await controller.clearPractice();
    await controller.close();
    expect(store.value, original);
    expect(store.snapshots, isEmpty);
    expect(controller.storageWarning, contains('newer app'));
    expect(controller.soundEnabled, isTrue);
  });

  test(
    'failed reads protect unread data while allowing session progress',
    () async {
      final store = MemoryPracticeStore()
        ..value = '{"version":10}'
        ..failReads = true;
      final controller = await restore(store);
      await controller.meetOffice();
      expect(controller.hasMetOffice, isTrue);
      expect(controller.storageWarning, contains('could not be read'));
      expect(store.snapshots, isEmpty);
      await controller.close();
      store.failReads = false;
      final reopened = await restore(store);
      expect(reopened.storageWarning, contains('newer app'));
      await reopened.close();
    },
  );

  test(
    'rejects invalid handles, messages and brief values before mutation',
    () async {
      final store = MemoryPracticeStore();
      final controller = PracticeController(store: store);
      for (final handle in ['', '@', 'has space', 'not-valid', 'a' * 16]) {
        expect(
          () => controller.saveDraft(handle: handle, message: 'Hello'),
          throwsArgumentError,
        );
      }
      for (final message in ['   ', 'a' * 501]) {
        expect(
          () => controller.saveDraft(handle: '@friend', message: message),
          throwsArgumentError,
        );
      }
      expect(() => controller.setTab(3), throwsRangeError);
      expect(
        () => controller.saveBrief(choice: -1, note: 'Hello'),
        throwsRangeError,
      );
      expect(
        () => controller.saveBrief(choice: 1, note: '  '),
        throwsArgumentError,
      );
      expect(
        () => controller.saveBrief(choice: 1, note: 'a' * 501),
        throwsArgumentError,
      );
      expect(controller.drafts, isEmpty);
      expect(controller.briefCompleted, isFalse);
      expect(store.snapshots, isEmpty);
      await controller.close();
    },
  );

  test('caps drafts at 20 without deleting existing user drafts', () async {
    final controller = PracticeController(store: MemoryPracticeStore());
    for (var i = 0; i < PracticeController.maxDrafts; i++) {
      await controller.saveDraft(handle: 'friend_$i', message: 'Draft $i');
    }
    expect(
      () => controller.saveDraft(handle: 'overflow', message: 'One too many'),
      throwsStateError,
    );
    expect(controller.drafts.length, 20);
    expect(controller.drafts.first.handle, '@friend_0');
    expect(() => controller.drafts.clear(), throwsUnsupportedError);
    await controller.close();
  });

  test(
    'clear removes practice progress while retaining sound and motion',
    () async {
      final store = MemoryPracticeStore();
      final controller = PracticeController(store: store);
      await controller.setSound(true);
      await controller.setReduceMotion(true);
      await controller.meetOffice();
      await controller.saveBrief(choice: 0, note: 'Question');
      await controller.saveDraft(handle: 'friend', message: 'An offer');
      controller.setTab(2);
      await controller.clearPractice();
      final restored = await restore(store);
      expect(restored.soundEnabled, isTrue);
      expect(restored.reduceMotion, isTrue);
      expect(restored.hasMetOffice, isFalse);
      expect(restored.selectedChoice, isNull);
      expect(restored.journalNote, isEmpty);
      expect(restored.drafts, isEmpty);
      expect(restored.tab, 0);
      await controller.close();
      await restored.close();
    },
  );

  test(
    'write failure warns without losing session state and a later write retries',
    () async {
      final store = MemoryPracticeStore()..failuresRemaining = 1;
      final controller = PracticeController(store: store);
      await controller.saveBrief(choice: 1, note: 'Keep this thought.');
      expect(controller.briefCompleted, isTrue);
      expect(controller.storageWarning, contains('could not be saved'));
      expect(store.value, isNull);
      await controller.setSound(true);
      expect(controller.storageWarning, isNull);
      final restored = await restore(store);
      expect(restored.journalNote, 'Keep this thought.');
      expect(restored.soundEnabled, isTrue);
      await controller.close();
      await restored.close();
    },
  );

  test(
    'overlapping saves serialize immutable snapshots and finish newest last',
    () async {
      final gate = Completer<void>();
      final store = MemoryPracticeStore()..nextWriteGate = gate;
      final controller = PracticeController(store: store);
      final first = controller.saveBrief(choice: 0, note: 'First');
      await Future<void>.delayed(Duration.zero);
      final second = controller.saveBrief(choice: 2, note: 'Second');
      final third = controller.setSound(true);
      expect(store.snapshots.length, 1);
      expect(controller.journalNote, 'Second');
      gate.complete();
      await Future.wait([first, second, third]);
      expect(store.maximumActiveWrites, 1);
      final snapshots = store.snapshots
          .map((s) => jsonDecode(s) as Map)
          .toList();
      expect(snapshots[0]['journalNote'], 'First');
      expect(snapshots[1]['journalNote'], 'Second');
      expect(snapshots[1]['soundEnabled'], isFalse);
      expect(snapshots[2]['soundEnabled'], isTrue);
      expect(jsonDecode(store.value!)['journalNote'], 'Second');
      await controller.close();
    },
  );

  test(
    'sound stays optional and close flushes writes and disposes audio once',
    () async {
      final audio = RecordingPracticeAudio();
      final store = MemoryPracticeStore();
      final controller = PracticeController(store: store, audio: audio);
      controller.cue('soft_tap.wav');
      expect(audio.cues, isEmpty);
      await controller.setSound(true);
      expect(audio.enabled, isTrue);
      controller.cue('paper_open.wav');
      expect(audio.cues, ['paper_open.wav']);
      await controller.setSound(false);
      controller.cue('arrival.wav');
      expect(audio.cues, hasLength(1));
      controller.setTab(2);
      await controller.close();
      controller.dispose();
      await controller.close();
      expect(audio.closes, 1);
      expect(jsonDecode(store.value!)['tab'], 2);
      expect(() => controller.setTab(0), throwsStateError);
    },
  );
}
