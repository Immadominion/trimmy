import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Sal's looping welcome, shared by the real account page and its preview.
class SignInChairArt extends StatefulWidget {
  const SignInChairArt({super.key, required this.height});

  static const clipAsset = 'assets/images/ui_review/sal-chair-welcome-v3.webp';
  static const stillAsset =
      'assets/images/ui_review/sal-chair-welcome-v3-still.png';

  final double height;

  @override
  State<SignInChairArt> createState() => _SignInChairArtState();
}

class _SignInChairArtState extends State<SignInChairArt>
    with WidgetsBindingObserver {
  static const _legacyStill =
      'assets/images/ui_review/sal-sign-in-chair-v1.png';

  ui.Image? _frame;
  Timer? _frameTimer;
  Completer<void>? _frameWait;
  int _generation = 0;
  int _displayedFrames = 0;
  int _frameCount = 0;
  bool _running = false;
  bool _motionEnabled = false;
  bool _loadFailed = false;
  AssetBundle? _bundle;
  int _decodeWidth = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePlayback();
  }

  @override
  void reassemble() {
    super.reassemble();
    _updatePlayback();
  }

  void _updatePlayback() {
    final media = MediaQuery.of(context);
    _motionEnabled =
        !media.disableAnimations &&
        !media.accessibleNavigation &&
        TickerMode.valuesOf(context).enabled;
    _bundle = DefaultAssetBundle.of(context);
    _decodeWidth = ((media.size.width - 48) * media.devicePixelRatio)
        .ceil()
        .clamp(1, 1024);
    _syncPlayback(notify: false);
  }

  void _syncPlayback({bool notify = true}) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_motionEnabled ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      if (_running || _frame != null) _stop(notify: notify);
    } else if (!_running && !_loadFailed && _bundle != null) {
      _running = true;
      _displayedFrames = 0;
      unawaited(_play(_bundle!, _decodeWidth, ++_generation));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncPlayback();
  }

  bool _canPlay(int generation) =>
      mounted && _running && generation == _generation;

  Future<void> _play(AssetBundle bundle, int width, int generation) async {
    // Each active page owns one codec. Do not cache a live animation stream or
    // predecode a cast's worth of frames. The async owner disposes its codec
    // after any pending native decode has returned, including cancellation.
    ui.Codec? codec;
    try {
      final bytes = await bundle.load(SignInChairArt.clipAsset);
      if (!_canPlay(generation)) return;
      codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        targetWidth: width,
        allowUpscaling: false,
      );
      if (!_canPlay(generation)) return;
      _frameCount = codec.frameCount;
      while (_canPlay(generation)) {
        final decodeClock = Stopwatch()..start();
        final next = await codec.getNextFrame();
        if (!_canPlay(generation)) {
          next.image.dispose();
          return;
        }
        final previous = _frame;
        setState(() {
          _frame = next.image;
          _displayedFrames++;
        });
        // RawImage gives RenderImage its own clone; the state owns this handle.
        previous?.dispose();
        if (_frameCount == 1) return;
        final duration = next.duration > Duration.zero
            ? next.duration
            : const Duration(milliseconds: 16);
        // The codec wraps back to the first frame. Keep decoding one frame at
        // a time, including exports whose metadata requests a single play.
        final remaining = duration - decodeClock.elapsed;
        await _hold(remaining > Duration.zero ? remaining : Duration.zero);
      }
    } catch (_) {
      // A missing or damaged decorative clip never interrupts account actions.
      if (_canPlay(generation)) {
        _loadFailed = true;
        _stop();
      }
    } finally {
      codec?.dispose();
    }
  }

  Future<void> _hold(Duration duration) {
    final wait = Completer<void>();
    _frameWait = wait;
    _frameTimer = Timer(duration, () {
      _frameTimer = null;
      _frameWait = null;
      if (!wait.isCompleted) wait.complete();
    });
    return wait.future;
  }

  void _stop({bool notify = true}) {
    _running = false;
    _generation++;
    _frameTimer?.cancel();
    _frameTimer = null;
    final wait = _frameWait;
    _frameWait = null;
    if (wait != null && !wait.isCompleted) wait.complete();
    final previous = _frame;
    _frame = null;
    previous?.dispose();
    if (notify && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop(notify: false);
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IntProperty('displayedFrames', _displayedFrames));
    properties.add(IntProperty('frameCount', _frameCount));
    properties.add(FlagProperty('running', value: _running, ifTrue: 'looping'));
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: widget.height,
      width: double.infinity,
      child: _frame != null
          ? RawImage(
              key: const ValueKey('sign-in-chair-frame'),
              image: _frame,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            )
          : Image.asset(
              SignInChairArt.stillAsset,
              key: const ValueKey('sign-in-chair-still'),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stack) => Image.asset(
                _legacyStill,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
    ),
  );
}
