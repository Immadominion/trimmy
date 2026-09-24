import 'package:flutter/material.dart';

import '../../account/guest_session.dart';
import '../career/reason_privacy_controller.dart';
import '../career/reason_sharing_repository.dart';
import '../design/product_motion_icon.dart';
import '../design/product_theme.dart';

const reasonPrivacyConsentLine =
    "Your comments and your handle will show on that stock's page for anyone in Trimmy. Money never shows.";
const reasonPrivacyFriendsLine =
    'Not available yet. Shares nothing until friends exist.';
const reasonPrivacyFriendsAvailableLine =
    'Only your Trimmy friends can see them on each stock page.';

/// The "Who can see my comments" settings row. It shows only what the server
/// confirmed. A choice in flight reads as saving until the server answers.
class ReasonPrivacyRow extends StatelessWidget {
  const ReasonPrivacyRow({super.key, required this.controller});

  final ReasonPrivacyController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final privacy = controller.privacy;
      final pending = controller.pending;
      final canChoose = privacy != null && !controller.busy;
      final theme = Theme.of(context);
      final retry = _retryAction();
      return ListTile(
        key: const ValueKey('settings-reason-privacy'),
        contentPadding: const EdgeInsets.fromLTRB(16, 3, 10, 3),
        minTileHeight: 68,
        leading: const ProductMotionIcon(file: 'settings-lock.png'),
        enabled: canChoose,
        title: Text(
          'Who can see my comments',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: canChoose ? ProductColor.ink : ProductColor.muted,
          ),
        ),
        subtitle: Semantics(
          liveRegion: true,
          child: Text(
            _subtitle(),
            key: const ValueKey('settings-reason-privacy-status'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _failed ? ProductColor.loss : ProductColor.muted,
            ),
          ),
        ),
        trailing: controller.busy
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    key: ValueKey(
                      controller.saving
                          ? 'settings-reason-privacy-saving'
                          : 'settings-reason-privacy-loading',
                    ),
                    strokeWidth: 2,
                  ),
                ),
              )
            : retry != null
            ? TextButton(
                key: const ValueKey('settings-reason-privacy-retry'),
                onPressed: retry,
                child: const Text('Try again'),
              )
            : privacy == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    privacy.visibility.label,
                    key: const ValueKey('settings-reason-privacy-value'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: ProductColor.violet,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_rounded),
                ],
              ),
        onTap: canChoose ? () => _choose(context, privacy, pending) : null,
      );
    },
  );

  bool get _failed =>
      controller.failure != null || controller.guestSessionFailure != null;

  VoidCallback? _retryAction() {
    if (controller.busy || !_failed) return null;
    if (controller.failure == ReasonSharingFailure.idempotencyConflict ||
        controller.failure == ReasonSharingFailure.accountNotFound) {
      return null;
    }
    return controller.retry;
  }

  String _subtitle() {
    final privacy = controller.privacy;
    final pending = controller.pending;
    if (controller.saving && pending != null) {
      return 'Saving ${pending.visibility.label}.';
    }
    if (controller.loading && privacy == null) return 'Loading your choice.';
    final guest = controller.guestSessionFailure;
    if (guest != null) return _guestMessage(guest);
    final failure = controller.failure;
    if (failure != null) {
      return privacy == null
          ? _loadFailureMessage(failure)
          : _saveFailureMessage(failure, pending);
    }
    if (privacy == null) return 'Your choice is not available yet.';
    return switch (controller.notice) {
      ReasonPrivacyNotice.saved =>
        'Saved. ${_describe(privacy.visibility, privacy.friendsSharingAvailable)}',
      ReasonPrivacyNotice.changedElsewhere =>
        'Changed on another device. Refreshed. ${_describe(privacy.visibility, privacy.friendsSharingAvailable)}',
      null => _describe(privacy.visibility, privacy.friendsSharingAvailable),
    };
  }

  String _describe(ReasonVisibility visibility, bool friendsSharingAvailable) =>
      switch (visibility) {
        ReasonVisibility.nobody => 'Only you can see your comments.',
        ReasonVisibility.everyone =>
          'Anyone in Trimmy can see them on each stock page.',
        ReasonVisibility.friends =>
          friendsSharingAvailable
              ? reasonPrivacyFriendsAvailableLine
              : reasonPrivacyFriendsLine,
      };

  String _guestMessage(GuestSessionFailure failure) => switch (failure) {
    GuestSessionFailure.expired ||
    GuestSessionFailure.revoked => 'This guest desk needs recovery.',
    _ => 'Your session needs a refresh. Try again.',
  };

  String _loadFailureMessage(ReasonSharingFailure failure) => switch (failure) {
    ReasonSharingFailure.offline =>
      'You are offline. Your choice could not load.',
    ReasonSharingFailure.timeout => 'Your choice took too long to load.',
    ReasonSharingFailure.rateLimited => _rateLimited('load'),
    ReasonSharingFailure.accountRequired =>
      'Your session needs a refresh before this can load.',
    ReasonSharingFailure.accountNotFound => 'This account is closed.',
    _ => 'Your choice could not load.',
  };

  String _saveFailureMessage(
    ReasonSharingFailure failure,
    ReasonPrivacyWrite? pending,
  ) {
    final choice = pending?.visibility.label;
    final notSaved = choice == null
        ? 'Your choice is not saved yet.'
        : '$choice is not saved yet.';
    return switch (failure) {
      ReasonSharingFailure.offline => 'You are offline. $notSaved',
      ReasonSharingFailure.timeout => 'Saving took too long. $notSaved',
      ReasonSharingFailure.rateLimited => _rateLimited('save'),
      ReasonSharingFailure.accountRequired =>
        'Your session needs a refresh. $notSaved',
      ReasonSharingFailure.accountNotFound =>
        'This account is closed. Nothing was saved.',
      ReasonSharingFailure.idempotencyConflict =>
        'That save could not be matched. Choose again.',
      _ => "Couldn't save. $notSaved",
    };
  }

  String _rateLimited(String action) {
    final delay = controller.retryAfter;
    if (delay == null || delay.inSeconds <= 0) {
      return 'Too many changes. Try to $action again shortly.';
    }
    final seconds = delay.inSeconds;
    return 'Too many changes. Try to $action again in $seconds '
        '${seconds == 1 ? 'second' : 'seconds'}.';
  }

  Future<void> _choose(
    BuildContext context,
    ReasonPrivacy privacy,
    ReasonPrivacyWrite? pending,
  ) async {
    final choice = await showModalBottomSheet<ReasonVisibility>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ProductColor.paper,
      shape: productSquircle(28),
      builder: (_) => ReasonPrivacySheet(
        current: privacy.visibility,
        initial: pending?.visibility ?? privacy.visibility,
        friendsSharingAvailable: privacy.friendsSharingAvailable,
      ),
    );
    if (choice == null || !context.mounted) return;
    await controller.choose(choice);
  }
}

/// Three honest choices and one thick confirm button. Choosing Everyone shows
/// the consent line before anything is saved.
class ReasonPrivacySheet extends StatefulWidget {
  const ReasonPrivacySheet({
    super.key,
    required this.current,
    required this.initial,
    required this.friendsSharingAvailable,
  });

  /// The server-confirmed choice.
  final ReasonVisibility current;

  /// The pre-selected option when the sheet opens.
  final ReasonVisibility initial;
  final bool friendsSharingAvailable;

  @override
  State<ReasonPrivacySheet> createState() => _ReasonPrivacySheetState();
}

class _ReasonPrivacySheetState extends State<ReasonPrivacySheet> {
  late ReasonVisibility _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Who can see my comments', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Now: ${widget.current.label}.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final option in const [
              ReasonVisibility.nobody,
              ReasonVisibility.everyone,
              ReasonVisibility.friends,
            ]) ...[
              _ReasonPrivacyOption(
                key: ValueKey('reason-privacy-option-${option.name}'),
                option: option,
                selected: option == _selected,
                friendsSharingAvailable: widget.friendsSharingAvailable,
                onSelected: () => setState(() => _selected = option),
              ),
              const SizedBox(height: 8),
            ],
            if (_selected == ReasonVisibility.everyone) ...[
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                child: Text(
                  reasonPrivacyConsentLine,
                  key: const ValueKey('reason-privacy-consent'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('reason-privacy-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: ProductColor.violet,
                minimumSize: const Size(double.infinity, 52),
                shape: productSquircle(20),
              ),
              onPressed: () => Navigator.of(context).pop(_selected),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonPrivacyOption extends StatelessWidget {
  const _ReasonPrivacyOption({
    super.key,
    required this.option,
    required this.selected,
    required this.friendsSharingAvailable,
    required this.onSelected,
  });

  final ReasonVisibility option;
  final bool selected;
  final bool friendsSharingAvailable;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (title, line) = switch (option) {
      ReasonVisibility.nobody => ('Nobody', 'Only you. This is the default.'),
      ReasonVisibility.everyone => (
        'Everyone',
        'Anyone in Trimmy, on each stock page.',
      ),
      ReasonVisibility.friends => (
        'Friends',
        friendsSharingAvailable
            ? reasonPrivacyFriendsAvailableLine
            : reasonPrivacyFriendsLine,
      ),
    };
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: title,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? const Color(0xFFECE7FA) : ProductColor.paperRaised,
          shape: productSquircle(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSelected,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(line, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 22,
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 22,
                            color: ProductColor.violet,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
