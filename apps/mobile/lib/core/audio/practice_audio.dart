import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

abstract interface class PracticeAudio {
  void setEnabled(bool value);
  void cue(String filename);
  Future<void> close();
}

/// A default for constructor-injected controllers, which need no platform audio.
class SilentPracticeAudio implements PracticeAudio {
  @override
  void setEnabled(bool value) {}
  @override
  void cue(String filename) {}
  @override
  Future<void> close() async {}
}

/// Optional, single-voice, non-looping feedback that cannot block application UI.
class LocalPracticeAudio with WidgetsBindingObserver implements PracticeAudio {
  LocalPracticeAudio() {
    WidgetsBinding.instance.addObserver(this);
  }

  static const _allowed = {'soft_tap.wav', 'paper_open.wav', 'arrival.wav'};
  AudioPlayer? _player;
  bool _enabled = false;
  bool _foreground = true;
  bool _closed = false;
  int _generation = 0;
  DateTime? _lastCue;
  Future<void>? _closing;

  @override
  void setEnabled(bool value) {
    if (_closed) return;
    _enabled = value;
    if (!value) {
      _generation++;
      unawaited(_stop());
    }
  }

  @override
  void cue(String filename) {
    if (_closed || !_enabled || !_foreground || !_allowed.contains(filename)) {
      return;
    }
    final now = DateTime.now();
    if (_lastCue != null && now.difference(_lastCue!).inMilliseconds < 100) {
      return;
    }
    _lastCue = now;
    unawaited(_play(filename, ++_generation));
  }

  Future<void> _play(String filename, int generation) async {
    try {
      final player = _player ??= AudioPlayer();
      // Release is explicit so an accidental future loop setting cannot persist.
      await player.setReleaseMode(ReleaseMode.release);
      if (_closed || !_enabled || !_foreground || generation != _generation) {
        return;
      }
      await player.play(AssetSource('audio/$filename'), volume: 0.65);
      // A mute/background event can arrive while platform playback is starting.
      if (_closed || !_enabled || !_foreground) await player.stop();
    } catch (_) {
      // Browser autoplay denial, missing device and plugin failures stay silent.
    }
  }

  Future<void> _stop() async {
    try {
      await _player?.stop();
    } catch (_) {
      // Audio is optional; storage and navigation remain independent.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _generation++;
      unawaited(_stop());
    }
  }

  @override
  Future<void> close() => _closing ??= _disposePlayer();

  Future<void> _disposePlayer() async {
    _closed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    try {
      await _player?.dispose();
    } catch (_) {
      // Teardown must not surface a playback failure to the application.
    }
  }
}
