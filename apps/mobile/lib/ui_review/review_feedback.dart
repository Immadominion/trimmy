import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WorkSound { select, paper, saved, complete }

/// Shared device feedback preferences used by review and production screens.
/// The historical storage keys stay stable so existing choices are preserved.
/// The tap player lives across page transitions so navigation cannot cut it off.
class ReviewFeedback extends ChangeNotifier with WidgetsBindingObserver {
  static final shared = ReviewFeedback();
  static const _prefix = 'trimmy.uiReview.feedback.';
  SharedPreferences? _preferences;
  Future<void>? _loading;
  Future<void>? _preparingTap;
  Future<void>? _preparingEntrance;
  AudioPlayer? _tap;
  AudioPlayer? _entrance;
  bool _tapReady = false;
  bool _entranceReady = false;
  bool _foreground = true;
  bool _observing = false;
  bool sound = true;
  bool haptics = true;
  double volume = .4;
  int _playGeneration = 0;
  int _entranceGeneration = 0;
  final _workPlayers = <WorkSound, AudioPlayer>{};
  Future<void>? _preparingWork;
  int _workGeneration = 0;
  bool _disposed = false;
  int _cueRevision = 0;
  int get cueRevision => _cueRevision;
  final _feedbackClock = Stopwatch()..start();
  int? _lastImpactMicros;

  Future<void> prepareWork() => _preparingWork ??= _prepareWork();
  Future<void> _prepareWork() async {
    await load();
    if (_disposed) return;
    _observeLifecycle();
    const sources = {
      WorkSound.select: 'soft_tap.wav',
      WorkSound.paper: 'paper_open.wav',
      WorkSound.saved: 'saved_mark_v1.wav',
      WorkSound.complete: 'arrival.wav',
    };
    for (final entry in sources.entries) {
      if (_disposed) return;
      final player = AudioPlayer();
      try {
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
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setVolume(volume);
        await player.setSource(AssetSource('audio/${entry.value}'));
        if (_disposed) {
          await player.dispose();
          return;
        }
        _workPlayers[entry.key] = player;
      } catch (_) {
        await player.dispose();
      }
    }
  }

  void workCue(WorkSound cue) {
    _cueRevision++;
    impact(selection: cue == WorkSound.select);
    final player = _workPlayers[cue];
    if (!sound || !_foreground || volume == 0 || player == null) return;
    final generation = ++_workGeneration;
    unawaited(() async {
      try {
        for (final other in _workPlayers.values) {
          await other.stop();
        }
        if (generation == _workGeneration && sound && _foreground) {
          await player.setVolume(volume);
          if (generation == _workGeneration && sound && _foreground) {
            await player.resume();
          }
        }
      } catch (_) {}
    }());
  }

  void _stopWork() {
    _workGeneration++;
    for (final player in _workPlayers.values) {
      unawaited(player.stop().catchError((Object _) {}));
    }
  }

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;
      sound = preferences.getBool('${_prefix}sound') ?? true;
      haptics = preferences.getBool('${_prefix}haptics') ?? true;
      volume = (preferences.getDouble('${_prefix}volume') ?? .4).clamp(0, .4);
      notifyListeners();
    } catch (_) {
      // Storage failure must not hold the demo on its splash.
    }
  }

  Future<void> setSound(bool value) async {
    await load();
    sound = value;
    if (!value) {
      _stopWork();
      _playGeneration++;
      unawaited(_tap?.stop().catchError((Object _) {}) ?? Future<void>.value());
      stopEntrance();
    }
    notifyListeners();
    await _preferences
        ?.setBool('${_prefix}sound', value)
        .catchError((Object _) => false);
  }

  Future<void> setHaptics(bool value) async {
    await load();
    haptics = value;
    notifyListeners();
    await _preferences
        ?.setBool('${_prefix}haptics', value)
        .catchError((Object _) => false);
  }

  Future<void> setVolume(double value) async {
    await load();
    volume = value.clamp(0, .4);
    notifyListeners();
    if (_tapReady) await _tap?.setVolume(volume).catchError((Object _) {});
    if (_entranceReady) {
      await _entrance?.setVolume(volume * .85).catchError((Object _) {});
    }
    await _preferences
        ?.setDouble('${_prefix}volume', volume)
        .catchError((Object _) => false);
  }

  Future<void> prepareTap() => _preparingTap ??= _prepareTap();

  Future<void> prepareEntrance() => _preparingEntrance ??= _prepareEntrance();

  void _observeLifecycle() {
    if (_observing) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  Future<void> _prepareTap() async {
    await load();
    if (_disposed) return;
    _observeLifecycle();
    try {
      final context = AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      );
      final player = _tap = AudioPlayer();
      await player.setAudioContext(context);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(volume);
      await player.setSource(AssetSource('audio/soft_tap.wav'));
      if (_disposed) {
        await player.dispose();
        return;
      }
      _tapReady = true;
    } catch (error) {
      _preparingTap = null;
      debugPrint('Trimmy button audio could not prepare: $error');
      // Feedback is optional. Never delay the action or queue late taps.
    }
  }

  Future<void> _prepareEntrance() async {
    await load();
    _observeLifecycle();
    try {
      final player = _entrance = AudioPlayer();
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
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(volume * .85);
      // Never fall back to v3/v2: both contain the two pop accents the user
      // rejected. A pre-v4 bundle stays quiet until the next full app run.
      await player.setSource(AssetSource('audio/wall_street_orbit_v4.wav'));
      _entranceReady = true;
    } catch (error) {
      debugPrint('Trimmy entrance audio could not prepare: $error');
      // An unavailable audio device never blocks the visual entrance.
    }
  }

  void playEntrance() {
    if (!sound || volume == 0 || !_foreground || !_entranceReady) return;
    final generation = ++_entranceGeneration;
    unawaited(() async {
      try {
        // The prepared source starts at zero; stopEntrance resets it for any
        // later visit. Seeking here can wait for a native event and miss the
        // first visible frame of the coin entrance.
        await _entrance!.resume();
        if (generation != _entranceGeneration || !sound || !_foreground) {
          await _entrance!.stop();
        }
      } catch (error) {
        debugPrint('Trimmy entrance audio could not play: $error');
      }
    }());
  }

  void stopEntrance() {
    _entranceGeneration++;
    unawaited(
      _entrance?.stop().catchError((Object _) {}) ?? Future<void>.value(),
    );
  }

  void impact({bool selection = false}) {
    if (_disposed || !_foreground || !haptics) return;
    final now = _feedbackClock.elapsedMicroseconds;
    if (_lastImpactMicros != null && now - _lastImpactMicros! < 80000) return;
    _lastImpactMicros = now;
    if (selection) {
      unawaited(HapticFeedback.selectionClick());
    } else {
      unawaited(HapticFeedback.lightImpact());
    }
  }

  void press({bool selection = false}) {
    _cueRevision++;
    impact(selection: selection);
    if (_disposed || !sound || volume == 0 || !_foreground || !_tapReady) {
      return;
    }
    final generation = ++_playGeneration;
    unawaited(() async {
      try {
        await _tap!.stop();
        if (generation == _playGeneration && sound && _foreground) {
          await _tap!.resume();
        }
      } catch (_) {}
    }());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stopWork();
      _playGeneration++;
      unawaited(_tap?.stop().catchError((Object _) {}) ?? Future<void>.value());
      stopEntrance();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWork();
    for (final player in _workPlayers.values) {
      unawaited(player.dispose());
    }
    _playGeneration++;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    unawaited(_tap?.dispose() ?? Future<void>.value());
    unawaited(_entrance?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}
