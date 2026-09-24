import 'package:flutter/material.dart';

import 'ada_rig.dart';
export 'ada_rig.dart' show AdaBeat, AdaRigPose, AdaRigPainter;

/// A finite cutout actor: independently controlled head, eyes and forearm.
/// All meaningful information lives in the accompanying native dialogue.
class AdaActor extends StatefulWidget {
  const AdaActor({
    super.key,
    required this.beat,
    this.animate = true,
    this.imageProvider = const AssetImage('assets/images/ada-acting-v1.webp'),
  });

  final AdaBeat beat;
  final bool animate;
  final ImageProvider imageProvider;

  @override
  State<AdaActor> createState() => _AdaActorState();
}

class _AdaActorState extends State<AdaActor>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  ImageStream? _stream;
  late final ImageStreamListener _listener;
  ImageInfo? _image;
  bool _canMove = false;
  bool _failed = false;
  bool _foreground = true;
  late AdaBeat _reactionBeat;
  AdaRigPose _from = const AdaRigPose();

  AdaRigPose get _pose =>
      AdaRigPose.reaction(_from, _reactionBeat, _controller.value);

  @override
  void initState() {
    super.initState();
    _reactionBeat = widget.beat;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      value: 1,
    );
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _listener = ImageStreamListener(_receiveImage, onError: _receiveError);
    WidgetsBinding.instance.addObserver(this);
  }

  void _receiveImage(ImageInfo image, bool synchronousCall) {
    final first = _image == null;
    final previous = _image;
    _image = image;
    _failed = false;
    previous?.dispose();
    if (first) _configure(restart: true);
    if (!synchronousCall && mounted) setState(() {});
  }

  void _receiveError(Object error, StackTrace? stack) {
    _failed = true;
    _configure();
    if (mounted) setState(() {});
  }

  void _resolveImage() {
    final stream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _image?.dispose();
    _image = null;
    _failed = false;
    _stream = stream..addListener(_listener);
  }

  void _configure({bool restart = false}) {
    if (!_canMove ||
        !_foreground ||
        !widget.animate ||
        _image == null ||
        _failed) {
      _controller.stop();
      _controller.value = 1;
    } else if (restart) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _canMove =
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        TickerMode.valuesOf(context).enabled;
    // Offstage/reduced-motion changes settle immediately. Re-enabling motion
    // must not replay an old completion or an interrupted reaction.
    _configure();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant AdaActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) _resolveImage();
    if (oldWidget.beat != widget.beat) {
      _from = _pose;
      _reactionBeat = widget.beat;
      _configure(restart: true);
    } else if (oldWidget.animate != widget.animate) {
      _configure();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // A return from background uses the final pose; never catch up old acting.
    _controller.stop();
    _controller.value = 1;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stream?.removeListener(_listener);
    _image?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 480 / 512,
        child: _image == null
            ? Image.asset(
                'assets/images/ada-graphic-v2.webp',
                key: ValueKey(_failed ? 'ada-art-fallback' : 'ada-art-loading'),
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    key: const ValueKey('ada-rig'),
                    painter: AdaRigPainter(
                      image: _image!.image,
                      pose: _pose,
                      beat: _reactionBeat,
                    ),
                  );
                },
              ),
      ),
    ),
  );
}
