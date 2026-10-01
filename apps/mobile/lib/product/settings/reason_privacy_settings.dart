import 'package:flutter/material.dart';

import '../../account/guest_session.dart';
import '../../l10n/l10n.dart';
import '../career/reason_privacy_controller.dart';
import '../career/reason_sharing_repository.dart';
import '../design/product_motion_icon.dart';
import '../design/product_theme.dart';

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
      final l10n = context.l10n;
      final retry = _retryAction();
      return ListTile(
        key: const ValueKey('settings-reason-privacy'),
        contentPadding: const EdgeInsets.fromLTRB(16, 3, 10, 3),
        minTileHeight: 68,
        leading: const ProductMotionIcon(file: 'settings-lock.png'),
        enabled: canChoose,
        title: Text(
          l10n.reasonPrivacyTitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: canChoose ? ProductColor.ink : ProductColor.muted,
          ),
        ),
        subtitle: Semantics(
          liveRegion: true,
          child: Text(
            _subtitle(l10n),
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
                child: Text(l10n.commonTryAgain),
              )
            : privacy == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: Text(
                      privacy.visibility.label(l10n),
                      key: const ValueKey('settings-reason-privacy-value'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: ProductColor.violet,
                      ),
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

  String _subtitle(AppLocalizations l10n) {
    final privacy = controller.privacy;
    final pending = controller.pending;
    if (controller.saving && pending != null) {
      return l10n.reasonPrivacySavingChoice(pending.visibility.label(l10n));
    }
    if (controller.loading && privacy == null) {
      return l10n.reasonPrivacyLoading;
    }
    final guest = controller.guestSessionFailure;
    if (guest != null) return _guestMessage(guest, l10n);
    final failure = controller.failure;
    if (failure != null) {
      return privacy == null
          ? _loadFailureMessage(failure, l10n)
          : _saveFailureMessage(failure, pending, l10n);
    }
    if (privacy == null) return l10n.reasonPrivacyNotAvailable;
    final status = _describe(
      l10n,
      privacy.visibility,
      friendsSharingAvailable: privacy.friendsSharingAvailable,
    );
    return switch (controller.notice) {
      ReasonPrivacyNotice.saved => l10n.reasonPrivacySavedStatus(status),
      ReasonPrivacyNotice.changedElsewhere =>
        l10n.reasonPrivacyChangedElsewhere(status),
      null => status,
    };
  }

  String _guestMessage(GuestSessionFailure failure, AppLocalizations l10n) =>
      switch (failure) {
        GuestSessionFailure.expired ||
        GuestSessionFailure.revoked => l10n.reasonPrivacyGuestRecovery,
        _ => l10n.reasonPrivacySessionRefresh,
      };

  String _loadFailureMessage(
    ReasonSharingFailure failure,
    AppLocalizations l10n,
  ) => switch (failure) {
    ReasonSharingFailure.offline => l10n.reasonPrivacyLoadOffline,
    ReasonSharingFailure.timeout => l10n.reasonPrivacyLoadTimeout,
    ReasonSharingFailure.rateLimited => _rateLimited(
      seconds: l10n.reasonPrivacyRateLimitedLoadSeconds,
      shortly: l10n.reasonPrivacyRateLimitedLoad,
    ),
    ReasonSharingFailure.accountRequired => l10n.reasonPrivacyLoadSession,
    ReasonSharingFailure.accountNotFound => l10n.reasonPrivacyAccountClosed,
    _ => l10n.reasonPrivacyLoadFailed,
  };

  String _saveFailureMessage(
    ReasonSharingFailure failure,
    ReasonPrivacyWrite? pending,
    AppLocalizations l10n,
  ) {
    final choice = pending?.visibility.label(l10n);
    return switch (failure) {
      ReasonSharingFailure.offline =>
        choice == null
            ? l10n.reasonPrivacySaveOffline
            : l10n.reasonPrivacySaveOfflineChoice(choice),
      ReasonSharingFailure.timeout =>
        choice == null
            ? l10n.reasonPrivacySaveTimeout
            : l10n.reasonPrivacySaveTimeoutChoice(choice),
      ReasonSharingFailure.rateLimited => _rateLimited(
        seconds: l10n.reasonPrivacyRateLimitedSaveSeconds,
        shortly: l10n.reasonPrivacyRateLimitedSave,
      ),
      ReasonSharingFailure.accountRequired =>
        choice == null
            ? l10n.reasonPrivacySaveSession
            : l10n.reasonPrivacySaveSessionChoice(choice),
      ReasonSharingFailure.accountNotFound =>
        l10n.reasonPrivacySaveAccountClosed,
      ReasonSharingFailure.idempotencyConflict =>
        l10n.reasonPrivacySaveMismatch,
      _ =>
        choice == null
            ? l10n.reasonPrivacySaveFailed
            : l10n.reasonPrivacySaveFailedChoice(choice),
    };
  }

  /// The wait the server asked for, when it sent one, else "shortly".
  String _rateLimited({
    required String Function(int seconds) seconds,
    required String shortly,
  }) {
    final delay = controller.retryAfter;
    if (delay == null || delay.inSeconds <= 0) return shortly;
    return seconds(delay.inSeconds);
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
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.reasonPrivacyTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              l10n.reasonPrivacySheetNow(widget.current.label(l10n)),
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
                  l10n.reasonPrivacyConsentLine,
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
              child: Text(l10n.commonSave),
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
    final l10n = context.l10n;
    final title = option.label(l10n);
    final line = switch (option) {
      ReasonVisibility.nobody => l10n.reasonPrivacyNobodyOption,
      ReasonVisibility.everyone => l10n.reasonPrivacyEveryoneOption,
      ReasonVisibility.friends =>
        friendsSharingAvailable
            ? l10n.reasonPrivacyFriendsAvailableLine
            : l10n.reasonPrivacyFriendsLine,
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

/// Who can see your comments now, as one sentence.
String _describe(
  AppLocalizations l10n,
  ReasonVisibility visibility, {
  required bool friendsSharingAvailable,
}) => switch (visibility) {
  ReasonVisibility.nobody => l10n.reasonPrivacyNobodyLine,
  ReasonVisibility.everyone => l10n.reasonPrivacyEveryoneLine,
  ReasonVisibility.friends =>
    friendsSharingAvailable
        ? l10n.reasonPrivacyFriendsAvailableLine
        : l10n.reasonPrivacyFriendsLine,
};
