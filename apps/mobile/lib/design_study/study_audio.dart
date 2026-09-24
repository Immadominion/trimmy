import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

enum StudySound { paper, select, saved }

/// Narrow widget-facing contract; tests can inject a recorder without a plugin.
abstract interface class StudyAudioOutput {
  bool get enabled;
  void setEnabled(bool value);
  void play(StudySound sound);
  Future<void> close();
}

/// Preparation must not make sound. Methods are called one at a time.
///
/// This separation lets [StudyAudio] discard obsolete events after asynchronous
/// asset loading, before asking the platform to start playback.
abstract interface class StudyAudioBackend {
  Future<void> prepare(StudySound sound);
  Future<void> start();
  Future<void> stop();
  Future<void> close();
}

/// Optional tactile feedback, independent of navigation and progress storage.
///
/// Starts disabled. Enabling or resuming never replays a previous event. Call
/// [play] with [StudySound.saved] only after the progress write succeeds.
/// Playback failures are deliberately silent and all public triggers return
/// synchronously. [close] invalidates pending work immediately and completes
/// once the serialized backend has stopped and disposed.
///
/// A native start command already issued cannot be recalled. If invalidated
/// while it is in flight, the next serialized operation is stop; no subsequent
/// preparation or start is allowed for that event.
class StudyAudio with WidgetsBindingObserver implements StudyAudioOutput {
  StudyAudio({
    StudyAudioBackend? backend,
    Duration Function()? clock,
    this.observeLifecycle = true,
  }) : _backend = backend ?? _AssetStudyAudioBackend(),
       _clock = clock ?? (Stopwatch()..start()).elapsedClock {
    if (observeLifecycle) {
      final binding = WidgetsBinding.instance;
      final lifecycle = binding.lifecycleState;
      _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
      binding.addObserver(this);
    }
  }

  static const repeatInterval = Duration(milliseconds: 120);
  static const maximumEventAge = Duration(milliseconds: 400);

  final StudyAudioBackend _backend;
  final Duration Function() _clock;
  final bool observeLifecycle;
  bool _enabled = false;
  bool _foreground = true;
  bool _closed = false;
  bool _working = false;
  bool _mustStop = false;
  int _generation = 0;
  _SoundEvent? _pending;
  _SoundEvent? _lastAccepted;
  Completer<void>? _closing;

  @override
  bool get enabled => _enabled && !_closed;

  @override
  void setEnabled(bool value) {
    if (_closed || _enabled == value) return;
    _enabled = value;
    if (!value) _invalidate();
  }

  @override
  void play(StudySound sound) {
    if (_closed || !_enabled || !_foreground) return;
    final now = _clock();
    final previous = _lastAccepted;
    if (previous != null &&
        previous.sound == sound &&
        now - previous.createdAt < repeatInterval) {
      return;
    }
    final event = _SoundEvent(sound, ++_generation, now);
    _lastAccepted = event;
    // One replaceable event, rather than a queue of sounds that can become late.
    _pending = event;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_closed) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _invalidate();
  }

  void _invalidate() {
    _generation++;
    _pending = null;
    _lastAccepted = null;
    _mustStop = true;
    _schedule();
  }

  bool _isCurrent(_SoundEvent event) {
    final age = _clock() - event.createdAt;
    return !_closed &&
        _enabled &&
        _foreground &&
        event.generation == _generation &&
        !age.isNegative &&
        age <= maximumEventAge;
  }

  void _schedule() {
    if (_working) return;
    _working = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (true) {
        if (_mustStop) {
          _mustStop = false;
          await _silently(_backend.stop);
          continue;
        }
        if (_closed) {
          await _silently(_backend.close);
          _closing!.complete();
          return;
        }
        final event = _pending;
        _pending = null;
        if (event == null) return;
        if (!_isCurrent(event)) continue;
        // Stop must succeed before starting a different voice. If the backend
        // cannot stop, skip this optional cue instead of risking overlap.
        if (!await _silently(_backend.stop) || !_isCurrent(event)) continue;
        if (!await _silently(() => _backend.prepare(event.sound))) {
          _mustStop = true;
          continue;
        }
        if (!_isCurrent(event)) continue;
        if (!await _silently(_backend.start) || !_isCurrent(event)) {
          _mustStop = true;
        }
      }
    } finally {
      _working = false;
    }
  }

  static Future<bool> _silently(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (_) {
      // Missing audio device, autoplay denial and plugin errors stay optional.
      return false;
    }
  }

  @override
  Future<void> close() {
    final existing = _closing;
    if (existing != null) return existing.future;
    _closing = Completer<void>();
    _closed = true;
    _enabled = false;
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    _invalidate();
    return _closing!.future;
  }
}

class _SoundEvent {
  const _SoundEvent(this.sound, this.generation, this.createdAt);

  final StudySound sound;
  final int generation;
  final Duration createdAt;
}

extension on Stopwatch {
  Duration elapsedClock() => elapsed;
}

class _AssetStudyAudioBackend implements StudyAudioBackend {
  AudioPlayer? _player;

  @override
  Future<void> prepare(StudySound sound) async {
    final player = _player ??= AudioPlayer();
    await player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ),
    );
    await player.setReleaseMode(ReleaseMode.release);
    await player.setVolume(0.75);
    final asset = switch (sound) {
      StudySound.paper => 'audio/paper_open.wav',
      StudySound.select => 'audio/soft_tap.wav',
      StudySound.saved => 'audio/saved_mark_v1.wav',
    };
    // Do not use AudioPlayer.play: it resumes after its own asynchronous source
    // loading, bypassing the service's generation check.
    await player.setSource(AssetSource(asset));
  }

  @override
  Future<void> start() async => _player?.resume();

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> close() async {
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
