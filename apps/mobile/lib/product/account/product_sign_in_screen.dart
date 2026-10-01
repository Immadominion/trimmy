import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../account/account_controller.dart';
import '../../account/auth.dart';
import '../../l10n/l10n.dart';
import '../design/product_theme.dart';
import 'sign_in_methods_page.dart';

enum _EmailStage { methods, address, code }

/// What went wrong, kept as a reason so the message follows the app language.
enum _SignInError {
  unfinished,
  closed,
  connection,
  code,
  unavailable,
  emailInvalid,
  sendFailed,
  codeMissing,
}

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
  _SignInError? _error;

  bool get _unavailable =>
      widget.configurationFailed ||
      widget.controller == null ||
      !widget.controller!.canSignIn;

  bool get _waiting =>
      _busy ||
      widget.controller?.phase == AccountPhase.initializing ||
      widget.controller?.phase == AccountPhase.connecting;

  String _connectionError(AppLocalizations l10n) => widget.expiredGuestRecovery
      ? l10n.signInErrorConnectionExpired
      : l10n.signInErrorConnection;

  String _errorText(_SignInError error, AppLocalizations l10n) =>
      switch (error) {
        _SignInError.unfinished => l10n.signInErrorUnfinished,
        _SignInError.closed =>
          widget.expiredGuestRecovery
              ? l10n.signInClosedExpired
              : l10n.signInClosed,
        _SignInError.connection => _connectionError(l10n),
        _SignInError.code => l10n.signInErrorCode,
        _SignInError.unavailable => l10n.signInUnavailable,
        _SignInError.emailInvalid => l10n.signInErrorEmailInvalid,
        _SignInError.sendFailed => l10n.signInErrorSendCode,
        _SignInError.codeMissing => l10n.signInErrorCodeMissing,
      };

  String? _visibleError(AppLocalizations l10n) {
    final error = _error;
    if (error != null) return _errorText(error, l10n);
    return widget.controller?.phase == AccountPhase.error
        ? _connectionError(l10n)
        : null;
  }

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
        setState(() => _error = _SignInError.unfinished);
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
      setState(() => _error = _SignInError.closed);
    } else if (phase == AccountPhase.error ||
        result == PracticeSignInResult.signedIn ||
        result == PracticeSignInResult.sessionChanged) {
      // A provider credential is not a completed server account connection.
      setState(() => _error = _SignInError.connection);
    } else {
      setState(() {
        _error = email ? _SignInError.code : _SignInError.unavailable;
      });
    }
  }

  Future<void> _sendCode() => _run((operation) async {
    final controller = widget.controller;
    final email = normalizePracticeEmail(_email.text);
    if (email == null) {
      setState(() => _error = _SignInError.emailInvalid);
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
      setState(() => _error = _SignInError.sendFailed);
    }
  });

  Future<void> _verifyCode() => _run((operation) async {
    final controller = widget.controller;
    final code = normalizePracticeEmailCode(_code.text);
    if (code == null) {
      setState(() => _error = _SignInError.codeMissing);
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
    final l10n = context.l10n;
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
                  ? l10n.signInTitleTrimmy
                  : l10n.signInTitleDeskAwaits,
              caption: widget.expiredGuestRecovery
                  ? l10n.signInCaptionExpired
                  : l10n.signInCaption,
              notice: widget.expiredGuestRecovery
                  ? l10n.signInNoticeExpired
                  : null,
              error: _visibleError(l10n),
              busy: waiting,
            )
          : _formPage(context, waiting, unavailable),
    );
  }

  Widget _formPage(BuildContext context, bool waiting, bool unavailable) {
    final codeStep = _stage == _EmailStage.code;
    final l10n = context.l10n;
    final visibleError = _visibleError(l10n);
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
                      tooltip: codeStep
                          ? l10n.signInUseDifferentEmail
                          : l10n.commonBack,
                      onPressed: waiting ? null : _backToPreviousStep,
                      icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                    )
                  else
                    const SizedBox(width: 48),
                  if (!widget.entryGate)
                    IconButton(
                      key: const ValueKey('sign-in-close'),
                      tooltip: l10n.signInCloseTooltip,
                      onPressed: waiting ? null : _close,
                      icon: const Icon(Icons.close_rounded, color: _ink),
                    ),
                ],
              ),
              const SizedBox(height: 38),
              Text(
                unavailable
                    ? widget.expiredGuestRecovery
                          ? l10n.signInTitleTrimmy
                          : l10n.signInTitleSaveDesk
                    : codeStep
                    ? l10n.signInTitleCheckEmail
                    : l10n.signInTitleYourEmail,
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
                          ? l10n.signInExpiredDeskSeparate
                          : l10n.signInDeskStaysOnPhone
                    : codeStep
                    ? l10n.signInCodeSentTo(_sentTo)
                    : l10n.signInWeWillSendCode,
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
                      ? l10n.signInNotSetUpExpired
                      : l10n.signInNotSetUp,
                  style: const TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 24),
                _AccountAction(
                  key: const ValueKey('sign-in-later'),
                  label: widget.entryGate
                      ? l10n.signInContinueAsGuest
                      : l10n.signInLater,
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
                      labelText: codeStep
                          ? l10n.signInCodeLabel
                          : l10n.signInEmailLabel,
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
                if (visibleError != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      visibleError,
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
                            ? l10n.commonConnecting
                            : l10n.commonSending
                      : codeStep
                      ? l10n.commonSignIn
                      : l10n.signInSendCode,
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
                  child: Text(
                    codeStep ? l10n.signInUseDifferentEmail : l10n.commonBack,
                  ),
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
