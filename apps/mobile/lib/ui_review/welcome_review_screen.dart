import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui_review_app.dart';
import 'review_feedback.dart';

// Welcome motion storyboard
// 0.00-2.15s  token faces spiral into the upper scene with a coin-only lens filter
// 2.15s+      tokens drift; the headline and lower mark share a soft heartbeat
// reduced     composition resolves immediately and all motion stays still
const _wallStreetBeatLift = 2.5;
const _wallStreetBeatScale = .012;
const _ctaDepth = 5.0;
const _logoBeatScale = .018;

class WelcomeReviewScreen extends StatefulWidget {
  const WelcomeReviewScreen({
    super.key,
    required this.onStart,
    required this.onHaveAccount,
    this.playEntrance = true,
  });
  final bool playEntrance;
  final VoidCallback onStart;
  final FutureOr<void> Function() onHaveAccount;
  @override
  State<WelcomeReviewScreen> createState() => _WelcomeReviewScreenState();
}

class _WelcomeReviewScreenState extends State<WelcomeReviewScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _entrance;
  late final AnimationController _idle;
  final List<Timer> _hapticTimers = [];
  bool _entranceStarted = false;
  bool _started = false;
  bool _reducedMotion = false;
  bool _foreground = true;
  ui.FragmentShader? _coinShader;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2150),
    );
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );
    unawaited(ReviewFeedback.shared.prepareEntrance());
    unawaited(ReviewFeedback.shared.prepareTap());
    _loadCoinShader();
  }

  Future<void> _loadCoinShader() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/coin_edge_smear.frag',
      );
      if (mounted) {
        final previous = _coinShader;
        setState(() => _coinShader = program.fragmentShader());
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => previous?.dispose(),
        );
      }
    } catch (_) {
      // Unsupported renderers retain the clean coin composition.
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // Shader tuning must participate in the same VS Code hot-reload workflow
    // as the layout, without requiring a second device build.
    _loadCoinShader();
  }

  void _stopArrival() {
    for (final timer in _hapticTimers) {
      timer.cancel();
    }
    _hapticTimers.clear();
    ReviewFeedback.shared.stopEntrance();
  }

  void _startEntrance() {
    if (_entranceStarted) return;
    _entranceStarted = true;
    if (!widget.playEntrance) {
      _entrance.value = 1;
      if (!_reducedMotion && _foreground) _idle.repeat();
      return;
    }
    if (_reducedMotion || !_foreground) return;
    ReviewFeedback.shared.playEntrance();
    // The two selection ticks sounded like button presses on iPhone. Keep
    // only one quiet tactile landing; the riser carries the coin motion.
    _hapticTimers.add(
      Timer(const Duration(milliseconds: 1830), () {
        if (mounted) ReviewFeedback.shared.impact();
      }),
    );
    _entrance.forward().then((_) {
      if (mounted && _foreground && !_reducedMotion && !_idle.isAnimating) {
        _idle.repeat();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final reduced = media.disableAnimations || media.accessibleNavigation;
    final wasReduced = _reducedMotion;
    _reducedMotion = reduced;
    if (reduced) {
      _stopArrival();
      _entrance.value = 1;
      _idle
        ..stop()
        ..value = 0;
      return;
    }
    if (wasReduced) {
      _entranceStarted = true;
      if (_foreground) {
        _idle.repeat();
      }
      return;
    }
    _startEntrance();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _hapticTimers) {
      timer.cancel();
    }
    _entrance.dispose();
    _idle.dispose();
    _coinShader?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stopArrival();
      _entrance.stop();
      _idle.stop();
    } else {
      _entrance.value = 1;
      if (!_reducedMotion) {
        _idle.repeat();
      }
    }
  }

  void _start() {
    if (_started) return;
    _stopArrival();
    ReviewFeedback.shared.press();
    setState(() => _started = true);
    widget.onStart();
  }

  Future<void> _account() async {
    if (_started) return;
    _stopArrival();
    ReviewFeedback.shared.press(selection: true);
    setState(() => _started = true);
    final completion = widget.onHaveAccount();
    // Review navigation replaces this screen synchronously and retains the
    // action lock during its exit. A pushed production route returns a Future.
    if (completion is! Future<void>) return;
    try {
      await completion;
    } finally {
      // Production pushes sign-in over this screen. Returning from that route
      // must restore its controls without replaying the entrance.
      if (mounted) setState(() => _started = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final needsScroll = media.textScaler.scale(1) > 1.3;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: UiReviewColor.paper,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: UiReviewColor.paper,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: UiReviewColor.paper,
      ),
      child: Scaffold(
        backgroundColor: UiReviewColor.paper,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 720;
            final contentHeight = needsScroll
                ? math.max(constraints.maxHeight, compact ? 820.0 : 900.0)
                : constraints.maxHeight;
            final content = SizedBox(
              width: constraints.maxWidth,
              height: contentHeight,
              child: _WelcomeContent(
                entrance: _entrance,
                idle: _idle,
                compact: compact,
                started: _started,
                bottomInset: media.padding.bottom,
                coinShader: _coinShader,
                onStart: _start,
                onHaveAccount: _account,
              ),
            );
            if (!needsScroll) return content;
            return SingleChildScrollView(child: content);
          },
        ),
      ),
    );
  }
}

class _WelcomeContent extends StatelessWidget {
  const _WelcomeContent({
    required this.entrance,
    required this.idle,
    required this.compact,
    required this.started,
    required this.bottomInset,
    required this.coinShader,
    required this.onStart,
    required this.onHaveAccount,
  });
  final Animation<double> entrance;
  final Animation<double> idle;
  final bool compact, started;
  final double bottomInset;
  final ui.FragmentShader? coinShader;
  final VoidCallback onStart, onHaveAccount;

  @override
  Widget build(BuildContext context) {
    final horizontal = compact ? 17.0 : 21.0;
    final hero = _WallStreetOrbit(
      entrance: entrance,
      idle: idle,
      compact: compact,
      coinShader: coinShader,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final logoSize = constraints.maxWidth * 1.9;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: constraints.maxHeight * .70,
              child: IgnorePointer(child: RepaintBoundary(child: hero)),
            ),
            Positioned(
              left: -constraints.maxWidth * .48,
              top: constraints.maxHeight * .63 - logoSize * .19,
              width: logoSize,
              height: logoSize,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: idle,
                    builder: (context, child) {
                      // The shared clock keeps both double beats in phase.
                      // Anchor below the visible crest so it gently rises;
                      // the separate CTA layer remains completely still.
                      return Transform.scale(
                        scale: 1 + _logoBeatScale * _heartbeat(idle.value),
                        alignment: Alignment.bottomCenter,
                        child: child,
                      );
                    },
                    child: RepaintBoundary(
                      child: Transform.rotate(
                        angle: -.52,
                        child: Image.asset(
                          'assets/images/ui_review/trimmy-mark.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: horizontal,
              right: horizontal,
              bottom: bottomInset + (compact ? 7 : 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedOpacity(
                    duration: uiReviewDuration(context, 160),
                    opacity: started ? .78 : 1,
                    child: _CareerButton(
                      entrance: entrance,
                      idle: idle,
                      onPressed: started ? null : onStart,
                    ),
                  ),
                  SizedBox(height: compact ? 7 : 9),
                  AnimatedBuilder(
                    animation: entrance,
                    builder: (context, child) => _FadeRise(
                      progress: _interval(entrance.value, .72, 1),
                      dy: 5,
                      child: child!,
                    ),
                    child: SizedBox(
                      height: MediaQuery.textScalerOf(context).scale(1) > 1.3
                          ? null
                          : 44,
                      child: TextButton(
                        onPressed: onHaveAccount,
                        style: TextButton.styleFrom(
                          foregroundColor: UiReviewColor.ink,
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Sign in or create account',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// Identity images come from Tokens.xyz, pinned in token-sources/manifest.json.
// Four compact orbital systems preserve a clear central reading area.
class _StockTokenSpec {
  const _StockTokenSpec(
    this.symbol,
    this.anchor,
    this.size,
    this.system,
    this.tilt,
    this.yaw,
    this.color,
  );
  final String symbol;
  final Offset anchor;
  final double size, tilt, yaw;
  final int system;
  final Color color;
  String get image =>
      'assets/images/ui_review/wall-street-orbit/token-$symbol.webp';
}

const _stockTokens = <_StockTokenSpec>[
  _StockTokenSpec(
    'TSLAx',
    Offset(.17, .30),
    70,
    0,
    -.22,
    -.28,
    Color(0xFFE6002A),
  ),
  _StockTokenSpec(
    'AAPLx',
    Offset(.44, .19),
    63,
    0,
    .12,
    .06,
    Color(0xFFB4B7C0),
  ),
  _StockTokenSpec(
    'NVDAx',
    Offset(.80, .31),
    67,
    1,
    .18,
    .32,
    Color(0xFF83BA00),
  ),
  _StockTokenSpec(
    'MSFTx',
    Offset(.86, .135),
    43,
    1,
    -.2,
    -.46,
    Color(0xFFEEB949),
  ),
  _StockTokenSpec(
    'METAx',
    Offset(.89, .545),
    42,
    1,
    -.14,
    -.35,
    Color(0xFF338BEA),
  ),
  _StockTokenSpec(
    'GOOGLx',
    Offset(.51, .36),
    34,
    0,
    .2,
    -.20,
    Color(0xFFE8D9AD),
  ),
  _StockTokenSpec(
    'AMZNx',
    Offset(.18, .77),
    65,
    2,
    .14,
    .35,
    Color(0xFFF2A130),
  ),
  _StockTokenSpec(
    'NFLXx',
    Offset(.78, .92),
    60,
    3,
    -.25,
    -.26,
    Color(0xFFCB1830),
  ),
  _StockTokenSpec(
    'COINx',
    Offset(.52, .795),
    65,
    3,
    .1,
    .12,
    Color(0xFF3263ED),
  ),
  _StockTokenSpec(
    'HOODx',
    Offset(.88, .735),
    42,
    3,
    -.15,
    .48,
    Color(0xFF90CB1F),
  ),
  _StockTokenSpec('AMDx', Offset(.115, .54), 46, 0, .2, -.5, Color(0xFF3B4044)),
  _StockTokenSpec(
    'ADBEx',
    Offset(.38, .925),
    36,
    2,
    -.2,
    -.18,
    Color(0xFFE43C49),
  ),
  _StockTokenSpec(
    'PYPLx',
    Offset(.19, .065),
    33,
    0,
    .3,
    .45,
    Color(0xFF2499D5),
  ),
  _StockTokenSpec('Vx', Offset(.64, .24), 32, 1, -.2, -.3, Color(0xFF6365AA)),
  _StockTokenSpec(
    'FIGx',
    Offset(.16, .915),
    52,
    2,
    .16,
    -.4,
    Color(0xFFC1A5EE),
  ),
  _StockTokenSpec('ORCLx', Offset(.70, .68), 28, 3, .2, .35, Color(0xFFE26B62)),
];
const _systemCenters = [
  Offset(.30, .22),
  Offset(.77, .27),
  Offset(.24, .78),
  Offset(.70, .77),
];

class _WallStreetOrbit extends StatelessWidget {
  const _WallStreetOrbit({
    required this.entrance,
    required this.idle,
    required this.compact,
    required this.coinShader,
  });
  final Animation<double> entrance, idle;
  final bool compact;
  final ui.FragmentShader? coinShader;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Start your Wall Street career. Tokenized stocks orbit the invitation.',
    child: ExcludeSemantics(
      child: AnimatedBuilder(
        animation: Listenable.merge([entrance, idle]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final center = Offset(width * .5, height * .545);
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _filteredCoins(width, height),
                  _buildHeadline(center),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _filteredCoins(double width, double height) {
    final coins = SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final entry
              in (_stockTokens.asMap().entries.toList()
                ..sort((a, b) => a.value.size.compareTo(b.value.size))))
            _buildToken(entry.value, entry.key, width, height),
        ],
      ),
    );
    final shader = coinShader;
    return shader == null
        ? coins
        : ImageFiltered(
            imageFilter: ui.ImageFilter.shader(shader),
            child: coins,
          );
  }

  Widget _buildHeadline(Offset center) {
    final progress = Curves.easeOutBack.transform(
      _interval(entrance.value, .29, .76),
    );
    final beat = _heartbeat(idle.value);
    return Positioned(
      left: center.dx - (compact ? 117 : 125),
      top: center.dy + ((1 - progress) * 12),
      width: compact ? 234 : 250,
      child: FractionalTranslation(
        // Center the actual three-line block within the coin-free space.
        translation: const Offset(0, -.5),
        child: Opacity(
          opacity: _interval(entrance.value, .24, .58),
          child: Transform.scale(
            scale: .88 + (.12 * progress),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: 'Bricolage Grotesque',
                fontSize: compact ? 36 : 39,
                height: .9,
                letterSpacing: compact ? -1.6 : -1.85,
                fontWeight: FontWeight.w800,
                color: UiReviewColor.ink,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Start your', textScaler: TextScaler.noScaling),
                  Transform.translate(
                    offset: Offset(0, -(_wallStreetBeatLift * beat)),
                    child: Transform.scale(
                      scale: 1 + (_wallStreetBeatScale * beat),
                      child: const Text(
                        'Wall Street',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(color: UiReviewColor.violet),
                      ),
                    ),
                  ),
                  const Text('career.', textScaler: TextScaler.noScaling),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToken(
    _StockTokenSpec spec,
    int index,
    double width,
    double height,
  ) {
    final local = _interval(
      entrance.value,
      (index % 4) * .032,
      .80 + (index % 4) * .04,
    );
    final travel = Curves.easeOutCubic.transform(local);
    final settle = Curves.easeOutBack.transform(local);
    final system = _systemCenters[spec.system];
    final origin = Offset(system.dx * width, system.dy * height);
    final anchor = Offset(spec.anchor.dx * width, spec.anchor.dy * height);
    final vector = anchor - origin;
    final phase = idle.value * math.pi * 2 + index * 1.7;
    final direction = spec.system.isEven ? 1.0 : -1.0;
    final turn = (1 - travel) * math.pi * 2.25 * direction;
    final idleAngle = math.sin(phase) * .045;
    final angle = turn + idleAngle;
    final expansion = 1 + (1 - travel) * .8;
    final point =
        origin +
        Offset(
          (vector.dx * math.cos(angle) - vector.dy * math.sin(angle)) *
              expansion,
          (vector.dx * math.sin(angle) + vector.dy * math.cos(angle)) *
              expansion,
        ) +
        Offset(math.cos(phase) * 1.5, math.sin(phase) * 2.2);
    final scale = (width / 370).clamp(.82, 1.08);
    final size = spec.size * scale * (.2 + .8 * settle);
    final rotation = spec.tilt + turn * .35 + math.sin(phase) * .025;
    // Reserve room for the lens displacement as well as the physical coin rim.
    final horizontalMargin = size * .5 + 26;
    return Positioned(
      left:
          point.dx.clamp(horizontalMargin, width - horizontalMargin) - size / 2,
      top: point.dy - size / 2,
      width: size,
      height: size,
      child: Opacity(
        opacity: _interval(local, 0, .16),
        child: _StockCoin(
          spec: spec,
          size: size,
          rotation: rotation,
          yaw: spec.yaw + math.sin(phase) * .025,
        ),
      ),
    );
  }
}

class _StockCoin extends StatelessWidget {
  const _StockCoin({
    required this.spec,
    required this.size,
    required this.rotation,
    required this.yaw,
  });
  final _StockTokenSpec spec;
  final double size, rotation, yaw;

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(spec.color, const Color(0xFF291D38), .42)!;
    return Transform.rotate(
      angle: rotation,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .0015)
          ..rotateY(yaw),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // A solid molded edge underneath the actual provider token image.
            for (var depth = 5; depth >= 1; depth--)
              Transform.translate(
                offset: Offset(depth * .7, depth * .7),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dark,
                  ),
                  child: SizedBox.square(dimension: size),
                ),
              ),
            Container(
              width: size,
              height: size,
              padding: EdgeInsets.all(size * .047),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(spec.color, Colors.white, .65)!,
                    spec.color,
                    dark,
                  ],
                ),
              ),
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      spec.image,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0x22FFFFFF),
                            Color(0x00FFFFFF),
                            Color(0x28261937),
                          ],
                          stops: [0, .45, 1],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CareerButton extends StatefulWidget {
  const _CareerButton({
    required this.entrance,
    required this.idle,
    required this.onPressed,
  });
  final Animation<double> entrance;
  final Animation<double> idle;
  final VoidCallback? onPressed;
  @override
  State<_CareerButton> createState() => _CareerButtonState();
}

class _CareerButtonState extends State<_CareerButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final textScaler = MediaQuery.textScalerOf(context);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(22),
    );
    return AnimatedBuilder(
      animation: widget.entrance,
      builder: (context, child) => _FadeRise(
        progress: _interval(widget.entrance.value, .62, .96),
        dy: 8,
        child: child!,
      ),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Start my first day',
        child: SizedBox(
          height: textScaler.scale(1) > 1.3
              ? textScaler.scale(20) * 5 + 24
              : 65,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                top: _ctaDepth,
                child: Material(color: const Color(0xFF4D36B6), shape: shape),
              ),
              Positioned.fill(
                bottom: _ctaDepth,
                child: AnimatedContainer(
                  duration: uiReviewDuration(context, _pressed ? 70 : 140),
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(
                    0,
                    _pressed && enabled ? _ctaDepth - 1 : 0,
                    0,
                  ),
                  child: Material(
                    color: enabled
                        ? UiReviewColor.violet
                        : UiReviewColor.violet.withValues(alpha: .48),
                    shape: shape,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: widget.onPressed,
                      onHighlightChanged: enabled
                          ? (value) => setState(() => _pressed = value)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Flexible(
                                child: Text(
                                  'Start my first day',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 11),
                              AnimatedBuilder(
                                animation: widget.idle,
                                builder: (context, child) =>
                                    Transform.translate(
                                      offset: Offset(
                                        math.sin(
                                              widget.idle.value * math.pi * 2,
                                            ) *
                                            2,
                                        0,
                                      ),
                                      child: child,
                                    ),
                                child: const ImageIcon(
                                  AssetImage(
                                    'assets/images/ui_review/icons8/animated-right-arrow.png',
                                  ),
                                  size: 23,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FadeRise extends StatelessWidget {
  const _FadeRise({required this.progress, required this.child, this.dy = 0});
  final double progress, dy;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final value = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    return Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, dy * (1 - value)),
        child: child,
      ),
    );
  }
}

double _interval(double value, double begin, double end) =>
    ((value - begin) / (end - begin)).clamp(0.0, 1.0);

double _heartbeat(double value) {
  final phase = (value % 1) * math.pi * 2;
  double pulse(double center, double width, double strength) {
    final distance = math
        .atan2(math.sin(phase - center), math.cos(phase - center))
        .abs();
    return strength * math.exp(-math.pow(distance / width, 2).toDouble());
  }

  return (pulse(.86, .18, 1) + pulse(1.15, .13, .42)).clamp(0.0, 1.0);
}
