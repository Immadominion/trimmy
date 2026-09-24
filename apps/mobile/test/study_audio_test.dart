import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/study_audio.dart';

class _Backend implements StudyAudioBackend {
  final calls = <String>[];
  final started = <StudySound>[];
  final gates = <String, Completer<void>>{};
  final failures = <String>{};
  StudySound? prepared;
  int concurrent = 0;
  int maximumConcurrent = 0;

  Future<void> _run(String operation, [void Function()? complete]) async {
    calls.add(operation);
    concurrent++;
    if (concurrent > maximumConcurrent) maximumConcurrent = concurrent;
    try {
      final gate = gates.remove(operation);
      if (gate != null) await gate.future;
      if (failures.remove(operation)) throw StateError('Optional audio failed');
      complete?.call();
    } finally {
      concurrent--;
    }
  }

  @override
  Future<void> prepare(StudySound sound) =>
      _run('prepare:${sound.name}', () => prepared = sound);

  @override
  Future<void> start() => _run('start', () => started.add(prepared!));

  @override
  Future<void> stop() => _run('stop');

  @override
  Future<void> close() => _run('close');
}

void main() {
  late _Backend backend;
  late StudyAudio audio;
  late Duration now;

  setUp(() {
    backend = _Backend();
    now = Duration.zero;
    audio = StudyAudio(
      backend: backend,
      clock: () => now,
      observeLifecycle: false,
    );
  });

  tearDown(() async {
    // Every delayed test must release its gate so disposal can finish.
    await audio.close();
    expect(backend.maximumConcurrent, lessThanOrEqualTo(1));
  });

  test('default off; enabling does not replay a discarded event', () async {
    audio.play(StudySound.paper);
    await pumpEventQueue();
    expect(audio.enabled, isFalse);
    expect(backend.calls, isEmpty);
    audio.setEnabled(true);
    await pumpEventQueue();
    expect(backend.calls, isEmpty);
    audio.play(StudySound.select);
    await pumpEventQueue();
    expect(backend.started, [StudySound.select]);
  });

  test('a slow preparation coalesces newer events to the latest', () async {
    final gate = Completer<void>();
    backend.gates['prepare:paper'] = gate;
    audio.setEnabled(true);
    audio.play(StudySound.paper);
    await pumpEventQueue();
    audio.play(StudySound.select);
    audio.play(StudySound.saved);
    expect(backend.started, isEmpty);
    gate.complete();
    await pumpEventQueue();
    expect(backend.started, [StudySound.saved]);
    expect(backend.calls, isNot(contains('prepare:select')));
  });

  test('disable during preparation prevents a delayed native start', () async {
    final gate = Completer<void>();
    backend.gates['prepare:paper'] = gate;
    audio.setEnabled(true);
    audio.play(StudySound.paper);
    await pumpEventQueue();
    audio.setEnabled(false);
    gate.complete();
    await pumpEventQueue();
    expect(backend.started, isEmpty);
    expect(backend.calls.last, 'stop');
    audio.setEnabled(true);
    await pumpEventQueue();
    expect(backend.started, isEmpty);
  });

  test('disable then enable does not revive an in-flight event', () async {
    final gate = Completer<void>();
    backend.gates['prepare:paper'] = gate;
    audio.setEnabled(true);
    audio.play(StudySound.paper);
    await pumpEventQueue();
    audio.setEnabled(false);
    audio.setEnabled(true);
    audio.play(StudySound.saved);
    gate.complete();
    await pumpEventQueue();
    expect(backend.started, [StudySound.saved]);
  });

  for (final lifecycle in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    test('$lifecycle invalidates pending audio and never resumes it', () async {
      final gate = Completer<void>();
      backend.gates['prepare:paper'] = gate;
      audio.setEnabled(true);
      audio.play(StudySound.paper);
      await pumpEventQueue();
      audio.didChangeAppLifecycleState(lifecycle);
      audio.play(StudySound.saved);
      gate.complete();
      await pumpEventQueue();
      audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(backend.started, isEmpty);
      audio.play(StudySound.select);
      await pumpEventQueue();
      expect(backend.started, [StudySound.select]);
    });
  }

  test('an already issued start is followed by stop on disable', () async {
    final gate = Completer<void>();
    backend.gates['start'] = gate;
    audio.setEnabled(true);
    audio.play(StudySound.paper);
    await pumpEventQueue();
    expect(backend.calls.last, 'start');
    audio.setEnabled(false);
    audio.play(StudySound.saved);
    gate.complete();
    await pumpEventQueue();
    expect(backend.calls.last, 'stop');
    expect(backend.started, [StudySound.paper]);
    expect(backend.calls.where((call) => call == 'start'), hasLength(1));
  });

  test('close invalidates immediately and disposes exactly once', () async {
    final gate = Completer<void>();
    backend.gates['prepare:paper'] = gate;
    audio.setEnabled(true);
    audio.play(StudySound.paper);
    await pumpEventQueue();
    final closing = audio.close();
    expect(identical(closing, audio.close()), isTrue);
    expect(audio.enabled, isFalse);
    audio.setEnabled(true);
    audio.play(StudySound.saved);
    gate.complete();
    await closing;
    expect(backend.started, isEmpty);
    expect(backend.calls.last, 'close');
    expect(backend.calls.where((call) => call == 'close'), hasLength(1));
  });

  test(
    'repeated cue is throttled but different feedback can replace it',
    () async {
      audio.setEnabled(true);
      audio.play(StudySound.select);
      await pumpEventQueue();
      now = const Duration(milliseconds: 119);
      audio.play(StudySound.select);
      await pumpEventQueue();
      expect(backend.started, [StudySound.select]);
      now = const Duration(milliseconds: 120);
      audio.play(StudySound.select);
      await pumpEventQueue();
      audio.play(StudySound.saved);
      await pumpEventQueue();
      expect(backend.started, [
        StudySound.select,
        StudySound.select,
        StudySound.saved,
      ]);
    },
  );

  test('old prepared cues expire instead of arriving late', () async {
    final gate = Completer<void>();
    backend.gates['prepare:paper'] = gate;
    audio.setEnabled(true);
    audio.play(StudySound.paper);
    await pumpEventQueue();
    now = const Duration(milliseconds: 401);
    gate.complete();
    await pumpEventQueue();
    expect(backend.started, isEmpty);
    audio.play(StudySound.select);
    await pumpEventQueue();
    expect(backend.started, [StudySound.select]);
  });

  test('an event expiring behind a stop does not even load', () async {
    final gate = Completer<void>();
    backend.gates['stop'] = gate;
    audio.setEnabled(true);
    audio.play(StudySound.paper);
    now = const Duration(seconds: 1);
    gate.complete();
    await pumpEventQueue();
    expect(backend.calls, ['stop']);
  });

  for (final failedOperation in ['stop', 'prepare:paper', 'start']) {
    test(
      '$failedOperation failure is silent and a later cue can work',
      () async {
        backend.failures.add(failedOperation);
        audio.setEnabled(true);
        audio.play(StudySound.paper);
        await pumpEventQueue();
        expect(backend.started, isEmpty);
        audio.play(StudySound.saved);
        await pumpEventQueue();
        expect(backend.started, [StudySound.saved]);
      },
    );
  }

  test('stop and dispose failures do not escape teardown', () async {
    backend.failures.addAll(['stop', 'close']);
    await audio.close();
    expect(backend.calls, ['stop', 'close']);
  });

  testWidgets('binding lifecycle observation stops and unregisters', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final observedBackend = _Backend();
    final observed = StudyAudio(backend: observedBackend);
    observed.setEnabled(true);
    observed.play(StudySound.select);
    await tester.pump();
    expect(observedBackend.started, [StudySound.select]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    observed.play(StudySound.paper);
    await tester.pump();
    expect(observedBackend.calls.last, 'stop');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(observedBackend.started, [StudySound.select]);
    await observed.close();
    final callsAtClose = observedBackend.calls.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(observedBackend.calls, hasLength(callsAtClose));
  });
}
