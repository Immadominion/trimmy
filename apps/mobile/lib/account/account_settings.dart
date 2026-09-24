import 'package:flutter/material.dart';

import '../design_study/activities.dart';
import '../design_study/craft.dart';
import '../design_study/progress.dart';
import '../social/invitations_panel.dart';
import '../social/relationships_panel.dart';
import 'account_closure_client.dart';
import 'account_controller.dart';
import 'auth.dart';
import 'reconciliation.dart';
import 'wallet_possession_panel.dart';

enum _EmailStep { closed, address, code }

/// Functional account controls inside the existing Settings sheet. Visual
/// refinement and physical-device OAuth walkthroughs are tracked separately.
class AccountSettings extends StatefulWidget {
  const AccountSettings({
    super.key,
    required this.controller,
    this.configurationFailed = false,
  });
  final AccountController? controller;
  final bool configurationFailed;

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  bool _busy = false;
  String? _error;
  _EmailStep _emailStep = _EmailStep.closed;
  String _sentTo = '';
  final _emailField = TextEditingController();
  final _codeField = TextEditingController();
  final _emailFocus = FocusNode(debugLabel: 'Email address');
  final _codeFocus = FocusNode(debugLabel: 'Code');
  bool _closureOpen = false;
  final _closureField = TextEditingController();
  final _closureFocus = FocusNode(debugLabel: 'Closing confirmation');

  @override
  void dispose() {
    _emailField.dispose();
    _codeField.dispose();
    _closureField.dispose();
    _emailFocus.dispose();
    _codeFocus.dispose();
    _closureFocus.dispose();
    super.dispose();
  }

  /// Moves the keyboard to the step's field after the frame that shows it.
  void _focusAfterBuild(FocusNode node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node.canRequestFocus) node.requestFocus();
      });

  /// Closing controls. The server requires the exact words, so the person
  /// types them rather than tapping once. The copy says what closing does and,
  /// just as importantly, what it does not do.
  List<Widget> _closing(AccountController controller, bool waiting) {
    final typed = _closureField.text.trim();
    final matches = typed == accountClosureConfirmation;
    return [
      const SizedBox(height: 16),
      const Divider(),
      Text('Close this account', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      const Text(
        'Closing signs you out for good. This account cannot sign in again and '
        'there is no undo. Any invitation you have sent and nobody has answered '
        'is cancelled.',
      ),
      const SizedBox(height: 6),
      const Text(
        'Your saved practice is kept, not deleted. What you saved on this '
        'device stays on this device, as it does whenever you sign out.',
      ),
      const SizedBox(height: 8),
      if (!_closureOpen)
        TextButton(
          key: const ValueKey('account-close-open'),
          onPressed: waiting
              ? null
              : () {
                  setState(() => _closureOpen = true);
                  _focusAfterBuild(_closureFocus);
                },
          child: const Text('Close this account'),
        )
      else ...[
        Text('To confirm, type: $accountClosureConfirmation'),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('account-close-confirm'),
          controller: _closureField,
          focusNode: _closureFocus,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Confirmation'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        // Stacked rather than side by side, so the labels stay readable at
        // phone width and at large text sizes.
        CraftButton(
          key: const ValueKey('account-close-confirmed'),
          label: 'Close account',
          onPressed: waiting || !matches
              ? null
              : () => _perform(controller.closeAccount),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: waiting
              ? null
              : () => setState(() {
                  _closureOpen = false;
                  _closureField.clear();
                }),
          child: const Text('Keep my account'),
        ),
      ],
    ];
  }

  /// Invitations get their own sheet rather than a long list inside Settings,
  /// which would push sign-out far down the page.
  Future<void> _openInvitations(AccountController controller) async {
    final invitations = controller.invitationsController;
    if (invitations == null) return;
    final relationships = controller.relationshipsController;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 32),
        child: relationships == null
            ? InvitationsPanel(controller: invitations)
            : RelationshipsPanel(
                relationships: relationships,
                invitations: invitations,
              ),
      ),
    );
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'That change could not be saved. Your work is still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWalletCheck(AccountController controller) async {
    final wallet = controller.walletPossessionController;
    if (wallet == null) return;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 6, 24, 32),
          child: WalletPossessionPanel(controller: wallet),
        ),
      );
    } finally {
      // Closing the review is cancellation, never permission to sign later.
      wallet.cancel();
    }
  }

  Future<void> _sendCode(AccountController controller) => _perform(() async {
    final email = _emailField.text;
    if (normalizePracticeEmail(email) == null) {
      _error = 'Enter a full email address, like name@example.com.';
      return;
    }
    final result = await controller.sendEmailCode(email);
    if (!mounted) return;
    switch (result) {
      case PracticeEmailCodeResult.sent:
        _sentTo = normalizePracticeEmail(email)!;
        _codeField.clear();
        _emailStep = _EmailStep.code;
        _focusAfterBuild(_codeFocus);
      case PracticeEmailCodeResult.invalidEmail:
        _error = 'Enter a full email address, like name@example.com.';
      case PracticeEmailCodeResult.failed:
        _error = "We couldn't send a code. Check the address and try again.";
      case PracticeEmailCodeResult.unavailable:
        _error = 'Email sign-in is not available right now.';
    }
  });

  Future<void> _signInWithCode(AccountController controller) =>
      _perform(() async {
        final code = _codeField.text;
        if (normalizePracticeEmailCode(code) == null) {
          _error = 'Enter the code from the email.';
          return;
        }
        final result = await controller.signInWithEmailCode(
          email: _sentTo,
          code: code,
        );
        if (!mounted) return;
        switch (result) {
          case PracticeSignInResult.signedIn:
          case PracticeSignInResult.sessionChanged:
            _emailStep = _EmailStep.closed;
          case PracticeSignInResult.failed:
            _error = "That code didn't work. Try again or send a new code.";
          case PracticeSignInResult.cancelled:
          case PracticeSignInResult.unavailable:
            _error = 'Email sign-in is not available right now.';
        }
      });

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return controller == null
        ? _content(context, null)
        : ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _content(context, controller),
          );
  }

  Widget _content(BuildContext context, AccountController? controller) {
    final active = controller?.phase == AccountPhase.active;
    final waiting =
        _busy ||
        controller?.phase == AccountPhase.initializing ||
        controller?.phase == AccountPhase.connecting;
    final status = switch (controller?.syncStatus) {
      AccountSyncStatus.syncing => 'Saving to your account…',
      AccountSyncStatus.saved => 'Saved to your account.',
      AccountSyncStatus.offline =>
        'Saved on this device. Account sync will try again.',
      AccountSyncStatus.conflict =>
        'There are two versions of your progress. Both are kept.',
      AccountSyncStatus.protected =>
        'Saved progress needs attention before sync can continue.',
      AccountSyncStatus.loginRequired =>
        'Sign in again to continue account sync.',
      _ =>
        active
            ? 'Saved on this device. Waiting to sync.'
            : 'Your practice is saved on this device.',
    };
    final canSignIn =
        controller != null &&
        controller.canSignIn &&
        (!active || controller.syncStatus == AccountSyncStatus.loginRequired);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your account', style: display(20)),
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text(status)),
        if (widget.configurationFailed || controller == null) ...[
          const SizedBox(height: 8),
          Text(
            widget.configurationFailed
                ? 'Sign-in is unavailable in this build.'
                : 'Account sign-in is not connected in this build.',
          ),
        ],
        if (controller != null && controller.canSignIn) ...[
          const SizedBox(height: 12),
          if (canSignIn) ..._signInControls(controller, waiting),
          if (controller.phase == AccountPhase.error)
            TextButton(
              onPressed: waiting
                  ? null
                  : () => _perform(controller.retryConnection),
              child: const Text('Try connection again'),
            ),
          if (active && controller.syncStatus == AccountSyncStatus.offline)
            TextButton(
              onPressed: waiting
                  ? null
                  : () => _perform(controller.synchronize),
              child: const Text('Try sync again'),
            ),
          if (controller.canImportGuestProgress) ...[
            const Text(
              'Add the practice you saved before signing in to this empty account. Your device copy stays available when you sign out.',
            ),
            const SizedBox(height: 8),
            CraftButton(
              label: 'Add my device progress',
              onPressed: waiting
                  ? null
                  : () => _perform(controller.importGuestProgress),
            ),
          ],
          if (controller.syncStatus == AccountSyncStatus.conflict)
            ..._conflict(controller, waiting),
          if (controller.invitationsController != null)
            TextButton(
              key: const ValueKey('invitations-open'),
              onPressed: waiting ? null : () => _openInvitations(controller),
              child: const Text('Friends and invitations'),
            ),
          if (controller.walletPossessionController != null)
            TextButton(
              key: const ValueKey('wallet-proof-open'),
              onPressed: waiting ? null : () => _openWalletCheck(controller),
              child: const Text('Check your wallet'),
            ),
          if (controller.canCloseAccount) ..._closing(controller, waiting),
          if (active || controller.phase == AccountPhase.error)
            TextButton(
              onPressed: waiting ? null : () => _perform(controller.signOut),
              child: const Text('Sign out'),
            ),
          if (controller.errorCode != null &&
              controller.phase == AccountPhase.guest &&
              _error == null)
            const Text('Sign-in could not finish. You can try again.'),
        ],
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
        const SizedBox(height: 16),
        const Divider(),
      ],
    );
  }

  List<Widget> _signInControls(AccountController controller, bool waiting) {
    switch (_emailStep) {
      case _EmailStep.closed:
        return [
          CraftButton(
            label: waiting ? 'Connecting…' : 'Continue with X',
            onPressed: waiting
                ? null
                : () => _perform(() => controller.signIn()),
          ),
          const SizedBox(height: 10),
          CraftButton(
            label: 'Continue with Google',
            outlined: true,
            fill: Colors.white,
            ink: StudyColor.ink,
            base: StudyColor.line,
            onPressed: waiting
                ? null
                : () => _perform(
                    () => controller.signIn(PracticeOAuthProvider.google),
                  ),
          ),
          const SizedBox(height: 10),
          CraftButton(
            label: 'Continue with email',
            outlined: true,
            fill: Colors.white,
            ink: StudyColor.ink,
            base: StudyColor.line,
            onPressed: waiting
                ? null
                : () {
                    setState(() {
                      _error = null;
                      _emailStep = _EmailStep.address;
                    });
                    _focusAfterBuild(_emailFocus);
                  },
          ),
          const SizedBox(height: 4),
        ];
      case _EmailStep.address:
        return [
          const Text('We will email you a short code to sign in.'),
          const SizedBox(height: 8),
          TextField(
            controller: _emailField,
            focusNode: _emailFocus,
            enabled: !waiting,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: _field('Email address'),
            onSubmitted: (_) => _sendCode(controller),
          ),
          const SizedBox(height: 12),
          CraftButton(
            label: waiting ? 'Sending…' : 'Send code',
            onPressed: waiting ? null : () => _sendCode(controller),
          ),
          TextButton(
            onPressed: waiting
                ? null
                : () => setState(() {
                    _error = null;
                    _emailStep = _EmailStep.closed;
                  }),
            child: const Text('Back'),
          ),
        ];
      case _EmailStep.code:
        return [
          Text('Enter the code we sent to $_sentTo.'),
          const SizedBox(height: 8),
          TextField(
            controller: _codeField,
            focusNode: _codeFocus,
            enabled: !waiting,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: _field('Code'),
            onSubmitted: (_) => _signInWithCode(controller),
          ),
          const SizedBox(height: 12),
          CraftButton(
            label: waiting ? 'Connecting…' : 'Sign in',
            onPressed: waiting ? null : () => _signInWithCode(controller),
          ),
          TextButton(
            onPressed: waiting
                ? null
                : () => _perform(() async {
                    final result = await controller.sendEmailCode(_sentTo);
                    if (!mounted) return;
                    if (result != PracticeEmailCodeResult.sent) {
                      _error =
                          "We couldn't send a new code. Try again in a moment.";
                    } else {
                      _codeField.clear();
                    }
                  }),
            child: const Text('Send a new code'),
          ),
          TextButton(
            onPressed: waiting
                ? null
                : () {
                    setState(() {
                      _error = null;
                      _codeField.clear();
                      _emailStep = _EmailStep.address;
                    });
                    _focusAfterBuild(_emailFocus);
                  },
            child: const Text('Use a different email'),
          ),
        ];
    }
  }

  InputDecoration _field(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: StudyColor.line, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: StudyColor.line, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: StudyColor.pine, width: 2),
    ),
  );

  List<Widget> _conflict(AccountController controller, bool waiting) {
    final remote = controller.conflictingProgress;
    if (remote == null) {
      return [
        const Text(
          'The saved record needs recovery. Both copies remain protected.',
        ),
      ];
    }
    final local = controller.repository.state;
    final localChoice = reconcilePracticeDrafts(
      local: local,
      remote: remote,
      useRemoteDraft: false,
    );
    final remoteChoice = reconcilePracticeDrafts(
      local: local,
      remote: remote,
      useRemoteDraft: true,
    );
    return [
      const SizedBox(height: 12),
      Text('On this device: ${_description(local)}'),
      const SizedBox(height: 6),
      Text('In your account: ${_description(remote)}'),
      const SizedBox(height: 12),
      if (localChoice == null && remoteChoice == null)
        const Text(
          'These copies have different first answers. They are kept separately so your original notes stay intact. You can continue on this device.',
        ),
      if (localChoice != null || remoteChoice != null)
        const Text('Keep all first notes and choose where to continue.'),
      if (localChoice != null)
        TextButton(
          onPressed: waiting
              ? null
              : () => _perform(() => controller.resolveConflict(localChoice)),
          child: const Text('Continue from this device'),
        ),
      if (remoteChoice != null)
        TextButton(
          onPressed: waiting
              ? null
              : () => _perform(() => controller.resolveConflict(remoteChoice)),
          child: const Text('Continue from my account'),
        ),
    ];
  }

  String _description(OfficeProgress progress) {
    final notes = '${progress.completions.length} saved notes';
    final activity = progress.active;
    if (activity == null) return '$notes, no activity open.';
    final title = studyActivities
        .firstWhere((item) => item.id == activity.activityId)
        .title;
    return '$notes, $title in progress.';
  }
}
