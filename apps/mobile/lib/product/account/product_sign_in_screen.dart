import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../account/account_controller.dart';
import '../../account/auth.dart';
import '../design/product_theme.dart';
import 'sign_in_methods_page.dart';

enum _EmailStage { methods, address, code }

/// The account gate is a page because saving a desk is a meaningful decision.
/// Guests can leave without losing the local paper desk.
class ProductSignInScreen extends StatefulWidget {
  const ProductSignInScreen({
    super.key,
    required this.controller,
    required this.onLater,
    this.onSignedIn,
    this.configurationFailed = false,
    this.expiredGuestRecovery = false,
    this.entryGate = false,
  });

  final AccountController? controller;
  final VoidCallback onLater;
  final VoidCallback? onSignedIn;
  final bool configurationFailed;
  final bool expiredGuestRecovery;

  /// At startup only the labelled guest action may grant guest access.
  final bool entryGate;

  @override
  State<ProductSignInScreen> createState() => _ProductSignInScreenState();
}

class _ProductSignInScreenState extends State<ProductSignInScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  var _stage = _EmailStage.methods;
  var _sentTo = '';
  var _busy = false;
  var _operation = 0;
  var _completionQueued = false;
  var _completed = false;
  String? _error;

  bool get _unavailable =>
      widget.configurationFailed ||
      widget.controller == null ||
      !widget.controller!.canSignIn;

  bool get _waiting =>
      _busy ||
      widget.controller?.phase == AccountPhase.initializing ||
      widget.controller?.phase == AccountPhase.connecting;

  String get _connectionError => widget.expiredGuestRecovery
      ? 'We could not connect your account. Your previous desk is preserved.'
      : 'We could not connect your account. Your desk is still here.';

  String? get _visibleError =>
      _error ??
      (widget.controller?.phase == AccountPhase.error
          ? _connectionError
          : null);

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_accountChanged);
    _scheduleCompletion();
  }

  @override
  void didUpdateWidget(covariant ProductSignInScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller?.removeListener(_accountChanged);
    widget.controller?.addListener(_accountChanged);
    _operation++;
    _busy = false;
    _completionQueued = false;
    _completed = false;
    _error = null;
    if (_stage == _EmailStage.code) _stage = _EmailStage.address;
    _sentTo = '';
    _code.clear();
    _scheduleCompletion();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_accountChanged);
    _operation++;
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _accountChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleCompletion();
  }

  void _scheduleCompletion() {
    final controller = widget.controller;
    if (controller?.phase != AccountPhase.active ||
        _completionQueued ||
        _completed) {
      return;
    }
    _completionQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(controller, widget.controller)) return;
      _completionQueued = false;
      if (_completed || controller?.phase != AccountPhase.active) return;
      _completed = true;
      widget.onSignedIn?.call();
    });
  }

  Future<void> _run(Future<void> Function(int operation) action) async {
    if (_waiting || _unavailable) return;
    final operation = ++_operation;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(operation);
    } catch (_) {
      if (mounted && operation == _operation) {
        setState(() => _error = 'That did not finish. Try again.');
      }
    } finally {
      if (mounted && operation == _operation) setState(() => _busy = false);
    }
  }

  bool _isCurrentOperation(int operation, AccountController controller) =>
      mounted &&
      operation == _operation &&
      identical(controller, widget.controller);

  Future<void> _oauth(PracticeOAuthProvider provider) =>
      _run((operation) async {
        final controller = widget.controller;
        if (controller == null) return;
        final result = await controller.signIn(provider);
        if (!_isCurrentOperation(operation, controller)) return;
        _handleSignInResult(result, email: false);
      });

  void _handleSignInResult(PracticeSignInResult result, {required bool email}) {
    final phase = widget.controller?.phase;
    if (phase == AccountPhase.active) return;
    if (result == PracticeSignInResult.cancelled) {
      setState(() {
        _error = widget.expiredGuestRecovery
            ? 'Sign-in was closed. Your previous desk is preserved.'
            : 'Sign-in was closed. Your desk is still here.';
      });
    } else if (phase == AccountPhase.error ||
        result == PracticeSignInResult.signedIn ||
        result == PracticeSignInResult.sessionChanged) {
      // A provider credential is not a completed server account connection.
      setState(() => _error = _connectionError);
    } else {
      setState(() {
        _error = email
            ? 'That code did not work. Try again.'
            : 'Sign-in is unavailable right now.';
      });
    }
  }

  Future<void> _sendCode() => _run((operation) async {
    final controller = widget.controller;
    final email = normalizePracticeEmail(_email.text);
    if (email == null) {
      setState(() => _error = 'Enter a full email address.');
      return;
    }
    if (controller == null) return;
    final result = await controller.sendEmailCode(email);
    if (!_isCurrentOperation(operation, controller)) return;
    if (result == PracticeEmailCodeResult.sent) {
      setState(() {
        _sentTo = email;
        _stage = _EmailStage.code;
      });
    } else {
      setState(() => _error = 'We could not send the code. Try again.');
    }
  });

  Future<void> _verifyCode() => _run((operation) async {
    final controller = widget.controller;
    final code = normalizePracticeEmailCode(_code.text);
    if (code == null) {
      setState(() => _error = 'Enter the code from your email.');
      return;
    }
    if (controller == null) return;
    final result = await controller.signInWithEmailCode(
      email: _sentTo,
      code: code,
    );
    if (!_isCurrentOperation(operation, controller)) return;
    _handleSignInResult(result, email: true);
  });

  void _backToPreviousStep() {
    if (_waiting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      if (_stage == _EmailStage.code) {
        _code.clear();
        _stage = _EmailStage.address;
      } else {
        _stage = _EmailStage.methods;
      }
    });
  }

  void _close() {
    if (_waiting) return;
    FocusScope.of(context).unfocus();
    widget.onLater();
  }

  void _openEmail() {
    if (_waiting || _unavailable) return;
    setState(() {
      _error = null;
      _stage = _EmailStage.address;
    });
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _waiting;
    final unavailable = _unavailable;
    return PopScope<void>(
      // The startup gate can only grant guest access through its named action.
      // In-flow account pages still handle Back through the close callback.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _waiting) return;
        if (_stage != _EmailStage.methods && !_unavailable) {
          _backToPreviousStep();
        } else if (!widget.entryGate) {
          _close();
        }
      },
      child: _stage == _EmailStage.methods && !unavailable
          ? SignInMethodsPage(
              showClose: !widget.entryGate,
              onGuest: widget.entryGate ? _close : null,
              onClose: waiting ? null : _close,
              onEmail: waiting ? null : _openEmail,
              // Privy's native Apple flow is iOS-only. Keep its place while
              // connecting; SignInMethodsPage disables every method via busy.
              onApple: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
                  ? () => _oauth(PracticeOAuthProvider.apple)
                  : null,
              onGoogle: waiting
                  ? null
                  : () => _oauth(PracticeOAuthProvider.google),
              onX: waiting ? null : () => _oauth(PracticeOAuthProvider.x),
              title: widget.expiredGuestRecovery
                  ? 'Sign in to Trimmy.'
                  : 'Your desk awaits.',
              caption: widget.expiredGuestRecovery
                  ? 'Open your account desk. The expired guest desk stays separate.'
                  : 'Sign in or create your account.',
              notice: widget.expiredGuestRecovery
                  ? 'Closing sign-in keeps the expired guest desk preserved.'
                  : null,
              error: _visibleError,
              busy: waiting,
            )
          : _formPage(context, waiting, unavailable),
    );
  }

  Widget _formPage(BuildContext context, bool waiting, bool unavailable) {
    final codeStep = _stage == _EmailStage.code;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!unavailable)
                    IconButton(
                      key: const ValueKey('sign-in-back'),
                      tooltip: codeStep ? 'Use a different email' : 'Back',
                      onPressed: waiting ? null : _backToPreviousStep,
                      icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                    )
                  else
                    const SizedBox(width: 48),
                  if (!widget.entryGate)
                    IconButton(
                      key: const ValueKey('sign-in-close'),
                      tooltip: 'Close sign in',
                      onPressed: waiting ? null : _close,
                      icon: const Icon(Icons.close_rounded, color: _ink),
                    ),
                ],
              ),
              const SizedBox(height: 38),
              Text(
                unavailable
                    ? widget.expiredGuestRecovery
                          ? 'Sign in to Trimmy.'
                          : 'Save your desk.'
                    : codeStep
                    ? 'Check your email.'
                    : 'Your email.',
                style: const TextStyle(
                  fontFamily: 'Bricolage Grotesque',
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  height: 1.08,
                  letterSpacing: -1.1,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                unavailable
                    ? widget.expiredGuestRecovery
                          ? 'The expired guest desk stays separate.'
                          : 'Your desk stays on this phone.'
                    : codeStep
                    ? 'We sent a code to $_sentTo.'
                    : 'We’ll send you a sign-in code.',
                style: const TextStyle(
                  fontFamily: 'Dejanire Sans',
                  color: _muted,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 30),
              if (unavailable) ...[
                Text(
                  widget.expiredGuestRecovery
                      ? 'Account sign-in is not set up in this build. The expired guest desk stays preserved.'
                      : 'Account sign-in is not set up in this build. Your desk stays on this phone.',
                  style: const TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 24),
                _AccountAction(
                  key: const ValueKey('sign-in-later'),
                  label: widget.entryGate ? 'Continue as guest' : 'Later',
                  onPressed: waiting ? null : _close,
                ),
              ] else ...[
                AutofillGroup(
                  child: TextField(
                    key: ValueKey(
                      codeStep ? 'sign-in-code-field' : 'sign-in-email-field',
                    ),
                    controller: codeStep ? _code : _email,
                    enabled: !waiting,
                    autofocus: true,
                    keyboardType: codeStep
                        ? TextInputType.number
                        : TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: [
                      codeStep
                          ? AutofillHints.oneTimeCode
                          : AutofillHints.email,
                    ],
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(
                      fontFamily: 'Dejanire Sans',
                      color: _ink,
                      fontSize: 18,
                      letterSpacing: .2,
                    ),
                    decoration: InputDecoration(
                      labelText: codeStep ? 'Code' : 'Email address',
                      floatingLabelStyle: const TextStyle(color: _violet),
                      filled: true,
                      fillColor: const Color(0xFFF5F3F8),
                      contentPadding: const EdgeInsets.all(20),
                      border: _fieldBorder,
                      enabledBorder: _fieldBorder,
                      disabledBorder: _fieldBorder,
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: _violet),
                      ),
                    ),
                    onSubmitted: waiting
                        ? null
                        : (_) => codeStep ? _verifyCode() : _sendCode(),
                  ),
                ),
                if (_visibleError != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _visibleError!,
                      key: const ValueKey('sign-in-error'),
                      style: const TextStyle(
                        color: ProductColor.loss,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _AccountAction(
                  key: ValueKey(
                    codeStep ? 'sign-in-verify' : 'sign-in-send-code',
                  ),
                  label: waiting
                      ? codeStep
                            ? 'Connecting…'
                            : 'Sending…'
                      : codeStep
                      ? 'Sign in'
                      : 'Send code',
                  onPressed: waiting
                      ? null
                      : codeStep
                      ? _verifyCode
                      : _sendCode,
                  busy: waiting,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: waiting ? null : _backToPreviousStep,
                  style: TextButton.styleFrom(foregroundColor: _muted),
                  child: Text(codeStep ? 'Use a different email' : 'Back'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _ink = Color(0xFF251B38);
const _violet = Color(0xFF7455E8);
const _muted = Color(0xFF797585);
final _fieldBorder = OutlineInputBorder(
  borderRadius: BorderRadius.circular(20),
  borderSide: BorderSide.none,
);

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: _violet,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFEAE5F6),
      disabledForegroundColor: _muted,
      minimumSize: const Size.fromHeight(58),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      shape: productSquircle(24),
      textStyle: const TextStyle(
        fontFamily: 'Dejanire Sans',
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    child: Semantics(
      liveRegion: busy,
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}
