import 'dart:async';

import 'package:flutter/material.dart';

import 'sign_in_chair_art.dart';

// These are the reviewed account-page colours. Keeping them local preserves
// this presentation without importing review state or changing the app theme.
const _ink = Color(0xFF251B38);
const _violet = Color(0xFF7455E8);
const _muted = Color(0xFF797585);

/// Account presentation shared by the product route and the UI preview.
/// The caller owns authentication, availability, errors and navigation.
class SignInMethodsPage extends StatelessWidget {
  const SignInMethodsPage({
    super.key,
    required this.onClose,
    required this.onEmail,
    required this.onGoogle,
    required this.onX,
    this.onApple,
    this.title = 'Welcome back.',
    this.caption = 'Your next move is waiting.',
    this.error,
    this.notice,
    this.busy = false,
    this.onGuest,
    this.showClose = true,
  });

  final VoidCallback? onClose;
  final VoidCallback? onEmail;
  final VoidCallback? onGoogle;
  final VoidCallback? onX;
  final VoidCallback? onApple;
  final String title;
  final String caption;
  final String? error;
  final String? notice;
  final bool busy;
  final VoidCallback? onGuest;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final providers = [
      if (onApple != null) ('Apple', onApple),
      ('Google', onGoogle),
      ('X', onX),
    ];
    final close = busy ? null : onClose;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showClose)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    button: true,
                    enabled: close != null,
                    label: 'Close sign in',
                    onTap: close,
                    child: ExcludeSemantics(
                      child: IconButton(
                        key: const ValueKey('sign-in-close'),
                        tooltip: 'Close sign in',
                        onPressed: close,
                        color: _ink,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          minimumSize: const Size(48, 48),
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 29),
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final heroHeight = (constraints.maxHeight * .35).clamp(
                    180.0,
                    285.0,
                  );
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - 32).clamp(
                          0.0,
                          double.infinity,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            children: [
                              const SizedBox(height: 8),
                              SignInChairArt(
                                key: const ValueKey(SignInChairArt.clipAsset),
                                height: heroHeight,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'Bricolage Grotesque',
                                  color: _ink,
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                  height: 1.05,
                                  letterSpacing: -1.3,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                caption,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'Dejanire Sans',
                                  color: _muted,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                ),
                              ),
                              if (notice != null && notice!.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                _AccountMessage(
                                  key: const ValueKey('sign-in-notice'),
                                  text: notice!,
                                  color: _muted,
                                ),
                              ],
                              if (error != null && error!.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                _AccountMessage(
                                  key: const ValueKey('sign-in-error'),
                                  text: error!,
                                  color: const Color(0xFFB73549),
                                ),
                              ],
                              const SizedBox(height: 28),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _EmailButton(
                                key: const ValueKey('sign-in-email'),
                                busy: busy,
                                onPressed: busy ? null : onEmail,
                              ),
                              if (onGuest != null)
                                TextButton(
                                  key: const ValueKey('sign-in-guest'),
                                  onPressed: busy ? null : onGuest,
                                  style: TextButton.styleFrom(
                                    foregroundColor: _muted,
                                    minimumSize: const Size(48, 48),
                                    textStyle: const TextStyle(
                                      fontFamily: 'Dejanire Sans',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  child: const Text('Continue as guest'),
                                ),
                              SizedBox(height: onGuest != null ? 12 : 24),
                              const Row(
                                children: [
                                  Expanded(
                                    child: Divider(color: Color(0xFFEAE8EF)),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 18,
                                    ),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        fontFamily: 'Dejanire Sans',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: _muted,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(color: Color(0xFFEAE8EF)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final (index, (provider, callback))
                                      in providers.indexed)
                                    Expanded(
                                      child: _ProviderButton(
                                        key: ValueKey(
                                          'sign-in-${provider.toLowerCase()}',
                                        ),
                                        provider: provider,
                                        iconDelay: Duration(
                                          milliseconds: 180 + index * 80,
                                        ),
                                        onTap: busy ? null : callback,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountMessage extends StatelessWidget {
  const _AccountMessage({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Dejanire Sans',
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
    ),
  );
}

class _EmailButton extends StatefulWidget {
  const _EmailButton({super.key, required this.onPressed, required this.busy});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  State<_EmailButton> createState() => _EmailButtonState();
}

class _EmailButtonState extends State<_EmailButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final contentColor = enabled ? Colors.white : _ink.withValues(alpha: .62);
    final label = widget.busy ? 'Connecting…' : 'Continue with email';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      value: widget.busy ? 'In progress' : null,
      liveRegion: widget.busy,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: AnimatedScale(
          duration: reduced
              ? Duration.zero
              : Duration(milliseconds: _pressed ? 70 : 150),
          scale: _pressed && enabled ? .985 : 1,
          curve: Curves.easeOutCubic,
          child: Material(
            color: enabled ? _violet : const Color(0xFFECEBF1),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPressed,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58, minWidth: 96),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 24),
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Dejanire Sans',
                            color: contentColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (widget.busy)
                        SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            value: reduced ? 1 : null,
                            color: contentColor,
                            strokeWidth: 2,
                          ),
                        )
                      else
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: contentColor,
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderButton extends StatefulWidget {
  const _ProviderButton({
    super.key,
    required this.provider,
    required this.iconDelay,
    required this.onTap,
  });

  final String provider;
  final Duration iconDelay;
  final VoidCallback? onTap;

  @override
  State<_ProviderButton> createState() => _ProviderButtonState();
}

class _ProviderButtonState extends State<_ProviderButton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  Timer? _startTimer;
  bool _started = false;
  bool _reducedMotion = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _settle() {
    _startTimer?.cancel();
    _startTimer = null;
    _entrance.value = 1;
    _started = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _reducedMotion = media.disableAnimations || media.accessibleNavigation;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (_reducedMotion ||
        !TickerMode.valuesOf(context).enabled ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      _settle();
    } else if (!_started) {
      _started = true;
      _startTimer = Timer(widget.iconDelay, () {
        _startTimer = null;
        if (mounted) _entrance.forward();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _settle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startTimer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  Widget _icon() => AnimatedScale(
    scale: _pressed && !_reducedMotion ? .84 : 1,
    duration: _reducedMotion
        ? Duration.zero
        : Duration(milliseconds: _pressed ? 100 : 280),
    curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
    child: AnimatedBuilder(
      animation: _entrance,
      child: Image.asset(
        widget.provider == 'X'
            ? 'assets/images/ui_review/icons8/account-x-standalone-rounded.png'
            : 'assets/images/ui_review/icons8/account-${widget.provider.toLowerCase()}-rounded.png',
        width: 24,
        height: 24,
        color: widget.onTap == null ? _ink.withValues(alpha: .38) : _ink,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
      builder: (context, child) {
        final settle = Curves.easeOutBack.transform(_entrance.value);
        final arrival = Curves.easeOutCubic.transform(_entrance.value);
        return Transform.translate(
          offset: Offset(0, 5 * (1 - arrival)),
          child: Transform.rotate(
            angle: -.12 * (1 - settle),
            child: Transform.scale(scale: .65 + .35 * settle, child: child),
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Semantics(
        label: 'Continue with ${widget.provider}',
        button: true,
        enabled: widget.onTap != null,
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: Material(
            color: const Color(0xFFF4F3F7),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (pressed) =>
                  setState(() => _pressed = pressed),
              child: SizedBox(
                width: 64,
                height: 64,
                child: Center(child: _icon()),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 9),
      ExcludeSemantics(
        child: Text(
          widget.provider,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Dejanire Sans',
            color: widget.onTap == null ? _ink.withValues(alpha: .38) : _ink,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}
