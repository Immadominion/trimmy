import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/ui_review/review_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Sound, haptics and quiet volume survive a new session', () async {
    final first = ReviewFeedback();
    await first.load();
    expect(first.volume, .4);
    await first.setSound(false);
    await first.setHaptics(false);
    await first.setVolume(.2);
    first.dispose();

    final next = ReviewFeedback();
    await next.load();
    expect(next.sound, isFalse);
    expect(next.haptics, isFalse);
    expect(next.volume, .2);
    next.dispose();
  });

  test('Volume cannot exceed the quiet playback ceiling', () async {
    final feedback = ReviewFeedback();
    await feedback.setVolume(1);
    expect(feedback.volume, .4);
    await feedback.setVolume(-1);
    expect(feedback.volume, 0);
    feedback.dispose();
  });

  test('Disabled haptics and backgrounded presses stay silent', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final feedback = ReviewFeedback();
    await feedback.load();
    await feedback.setHaptics(false);
    feedback.press();
    expect(calls, isEmpty);
    await feedback.setHaptics(true);
    feedback.didChangeAppLifecycleState(AppLifecycleState.inactive);
    feedback.press();
    expect(calls, isEmpty);
    feedback.didChangeAppLifecycleState(AppLifecycleState.resumed);
    feedback.press(selection: true);
    expect(calls.single.method, 'HapticFeedback.vibrate');
    expect(calls.single.arguments, 'HapticFeedbackType.selectionClick');
    feedback.dispose();
  });

  test(
    'work preparation retries only missing players and keeps cues immediate',
    () async {
      final host = _AudioHost()..failContexts = 1;
      host.install();
      addTearDown(host.uninstall);
      final feedback = ReviewFeedback();
      await feedback.setHaptics(false);
      final first = feedback.prepareWork();
      expect(identical(first, feedback.prepareWork()), isTrue);
      await first;
      expect(host.created, hasLength(4));
      expect(host.disposed, hasLength(1));
      final prepared = Map<String, String>.from(host.sources);

      feedback.workCue(WorkSound.select);
      expect(host.resumed, isEmpty);
      feedback.didChangeAppLifecycleState(AppLifecycleState.inactive);
      feedback.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await feedback.prepareWork();
      expect(host.created, hasLength(5));
      for (final entry in prepared.entries) {
        expect(host.sources[entry.key], entry.value);
      }
      expect(
        host.resumed,
        isEmpty,
        reason: 'Preparing must never replay an old cue',
      );
      feedback.workCue(WorkSound.select);
      await _drain();
      expect(host.resumed, [host.created.last]);
      await feedback.prepareWork();
      expect(host.created, hasLength(5));
      feedback.dispose();
      await _drain();
      expect(host.disposed.toSet(), host.created.toSet());
    },
  );

  for (final entrance in [false, true]) {
    test(
      '${entrance ? 'entrance' : 'tap'} audio disposes failed preparation and can retry',
      () async {
        final host = _AudioHost()..failContexts = 1;
        host.install();
        addTearDown(host.uninstall);
        final feedback = ReviewFeedback();
        await feedback.setHaptics(false);
        final prepare = entrance
            ? feedback.prepareEntrance
            : feedback.prepareTap;
        await prepare();
        expect(host.disposed, host.created);
        await prepare();
        await prepare();
        expect(host.created, hasLength(2));
        expect(host.resumed, isEmpty);
        entrance ? feedback.playEntrance() : feedback.press();
        await _drain();
        expect(host.resumed, [host.created.last]);
        feedback.dispose();
        await _drain();
        expect(host.disposed.toSet(), host.created.toSet());
      },
    );
  }

  test('disposing during preparation leaves no player or late cue', () async {
    final gate = Completer<void>();
    final host = _AudioHost()..contextGate = gate.future;
    host.install();
    addTearDown(host.uninstall);
    final feedback = ReviewFeedback();
    await feedback.load();
    final preparing = feedback.prepareWork();
    await _drain();
    expect(host.created, hasLength(1));
    feedback.dispose();
    gate.complete();
    await preparing;
    await feedback.prepareWork();
    await feedback.prepareTap();
    await feedback.prepareEntrance();
    feedback.workCue(WorkSound.select);
    feedback.playEntrance();
    expect(host.created, hasLength(1));
    expect(host.disposed, host.created);
    expect(host.resumed, isEmpty);
  });
}

Future<void> _drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _TestAudioCache extends AudioCache {
  @override
  Future<String> loadPath(String fileName) async => '/test/$fileName';
}

/// Exercises real AudioPlayer preparation through a simulated native device.
class _AudioHost {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final created = <String>[];
  final disposed = <String>[];
  final resumed = <String>[];
  final sources = <String, String>{};
  int failContexts = 0;
  Future<void>? contextGate;
  late AudioCache _previousCache;

  void install() {
    _previousCache = AudioCache.instance;
    AudioCache.instance = _TestAudioCache();
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global/events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        final args = call.arguments as Map;
        final id = args['playerId'] as String;
        switch (call.method) {
          case 'create':
            created.add(id);
            messenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$id'),
              (_) async => null,
            );
          case 'setAudioContext':
            await contextGate;
            if (failContexts > 0) {
              failContexts--;
              throw PlatformException(code: 'AUDIO_DEVICE_BUSY');
            }
          case 'setSourceUrl':
            sources[id] = args['url'] as String;
            await messenger.handlePlatformMessage(
              'xyz.luan/audioplayers/events/$id',
              const StandardMethodCodec().encodeSuccessEnvelope({
                'event': 'audio.onPrepared',
                'value': true,
              }),
              (_) {},
            );
          case 'resume':
            resumed.add(id);
          case 'dispose':
            disposed.add(id);
          case 'getCurrentPosition':
            return 0;
        }
        return null;
      },
    );
  }

  void uninstall() {
    AudioCache.instance = _previousCache;
    for (final name in [
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      for (final id in created) 'xyz.luan/audioplayers/events/$id',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  }
}
