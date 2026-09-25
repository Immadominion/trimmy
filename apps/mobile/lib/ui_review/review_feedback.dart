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
  bool _tapRequested = false;
  bool _entranceRequested = false;
  bool _workRequested = false;
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

  Future<void> prepareWork() {
    if (_disposed) return Future<void>.value();
    _workRequested = true;
    return _preparingWork ??= _prepareWork().whenComplete(
      () => _preparingWork = null,
    );
  }

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
      if (_workPlayers.containsKey(entry.key)) continue;
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
          await _disposePlayer(player);
          return;
        }
        _workPlayers[entry.key] = player;
      } catch (_) {
        await _disposePlayer(player);
      }
    }
  }

  void workCue(WorkSound cue) {
    _cueRevision++;
    impact(selection: cue == WorkSound.select);
    final player = _workPlayers[cue];
    if (_disposed || !sound || !_foreground || volume == 0 || player == null) {
      return;
    }
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
      if (_disposed) return;
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

  Future<void> prepareTap() {
    if (_disposed || _tapReady) return Future<void>.value();
    _tapRequested = true;
    return _preparingTap ??= _prepareTap().whenComplete(
      () => _preparingTap = null,
    );
  }

  Future<void> prepareEntrance() {
    if (_disposed || _entranceReady) return Future<void>.value();
    _entranceRequested = true;
    return _preparingEntrance ??= _prepareEntrance().whenComplete(
      () => _preparingEntrance = null,
    );
  }

  void _observeLifecycle() {
    if (_observing) return;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  Future<void> _prepareTap() async {
    await load();
    if (_disposed) return;
    _observeLifecycle();
    final player = AudioPlayer();
    try {
      final context = AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      );
      await player.setAudioContext(context);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(volume);
      await player.setSource(AssetSource('audio/soft_tap.wav'));
      if (_disposed) {
        await _disposePlayer(player);
        return;
      }
      _tap = player;
      _tapReady = true;
    } catch (error) {
      await _disposePlayer(player);
      debugPrint('Trimmy button audio could not prepare: $error');
      // Feedback is optional. Never delay the action or queue late taps.
    }
  }

  Future<void> _prepareEntrance() async {
    await load();
    if (_disposed) return;
    _observeLifecycle();
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
      await player.setVolume(volume * .85);
      // Never fall back to v3/v2: both contain the two pop accents the user
      // rejected. A pre-v4 bundle stays quiet until the next full app run.
      await player.setSource(AssetSource('audio/wall_street_orbit_v4.wav'));
      if (_disposed) {
        await _disposePlayer(player);
        return;
      }
      _entrance = player;
      _entranceReady = true;
    } catch (error) {
      await _disposePlayer(player);
      debugPrint('Trimmy entrance audio could not prepare: $error');
      // An unavailable audio device never blocks the visual entrance.
    }
  }

  void playEntrance() {
    if (_disposed || !sound || volume == 0 || !_foreground || !_entranceReady) {
      return;
    }
    final generation = ++_entranceGeneration;
    unawaited(() async {
      try {
        // The prepared source starts at zero; stopEntrance resets it for any
        // later visit. Seeking here can wait for a native event and miss the
        // first visible frame of the coin entrance.
        await _entrance!.resume();
        if (_disposed ||
            generation != _entranceGeneration ||
            !sound ||
            !_foreground) {
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
    if (_disposed) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stopWork();
      _playGeneration++;
      unawaited(_tap?.stop().catchError((Object _) {}) ?? Future<void>.value());
      stopEntrance();
    } else {
      // Recover a temporarily unavailable audio device without replaying cues
      // that were missed while loading or while the app was in the background.
      if (_tapRequested) unawaited(prepareTap());
      if (_entranceRequested) unawaited(prepareEntrance());
      if (_workRequested) unawaited(prepareWork());
    }
  }

  Future<void> _disposePlayer(AudioPlayer player) async {
    try {
      await player.dispose();
    } catch (_) {
      // A failed native player may also refuse cleanup. Keep feedback optional.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWork();
    for (final player in _workPlayers.values) {
      unawaited(_disposePlayer(player));
    }
    _playGeneration++;
    _entranceGeneration++;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    if (_tap != null) unawaited(_disposePlayer(_tap!));
    if (_entrance != null) unawaited(_disposePlayer(_entrance!));
    super.dispose();
  }
}
