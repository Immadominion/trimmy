import 'dart:async';

import '../../l10n/l10n.dart';
import '../money/money_mode.dart';
import 'package:flutter/material.dart';

import '../career/reason_privacy_controller.dart';
import '../design/product_components.dart';
import '../design/product_motion_icon.dart';
import '../design/product_notice.dart';
import '../design/product_theme.dart';
import 'language_settings.dart';
import 'reason_privacy_settings.dart';
import 'settings_models.dart';

class ProductSettingsScreen extends StatefulWidget {
  const ProductSettingsScreen({
    super.key,
    required this.state,
    this.reasonPrivacy,
    this.onSignIn,
    this.onSignOut,
    this.onEditHandle,
    this.onChangePersona,
    this.onManageSignInMethods,
    this.onNotificationChanged,
    this.onQuietHoursChanged,
    this.onEditQuietHours,
    this.onSoundChanged,
    this.onHapticsChanged,
    this.onAnimationsChanged,
    this.onResetPaper,
    this.onMoney,
    this.onReminderPreferences,
    this.onWalletCopy,
    this.onCheckWallet,
    this.onWalletExport,
    this.onHoldingsVisibilityChanged,
    this.onDownloadData,
    this.onHelp,
    this.onSendFeedback,
    this.onReportBug,
    this.onTerms,
    this.onPrivacy,
    this.onRiskNotice,
    this.onTokenizedStocks,
    this.onCloseAccount,
  });

  final ProductSettingsState state;

  /// The server-owned "Who can see my reasons" choice. When absent the row
  /// is not shown, because there is nothing honest to show.
  final ReasonPrivacyController? reasonPrivacy;
  final VoidCallback? onSignIn;
  final VoidCallback? onSignOut;
  final VoidCallback? onEditHandle;
  final VoidCallback? onChangePersona;
  final VoidCallback? onManageSignInMethods;
  final SettingsNotificationChanged? onNotificationChanged;
  final ValueChanged<bool>? onQuietHoursChanged;
  final VoidCallback? onEditQuietHours;
  final ValueChanged<bool>? onSoundChanged;
  final ValueChanged<bool>? onHapticsChanged;
  final ValueChanged<bool>? onAnimationsChanged;
  final SettingsPaperReset? onResetPaper;
  final VoidCallback? onMoney;
  final VoidCallback? onReminderPreferences;
  final ValueChanged<String>? onWalletCopy;
  final VoidCallback? onCheckWallet;
  final VoidCallback? onWalletExport;
  final ValueChanged<SettingsVisibility>? onHoldingsVisibilityChanged;
  final VoidCallback? onDownloadData;
  final VoidCallback? onHelp;
  final VoidCallback? onSendFeedback;
  final VoidCallback? onReportBug;
  final VoidCallback? onTerms;
  final VoidCallback? onPrivacy;
  final VoidCallback? onRiskNotice;
  final VoidCallback? onTokenizedStocks;
  final VoidCallback? onCloseAccount;

  @override
  State<ProductSettingsScreen> createState() => _ProductSettingsScreenState();
}

class _ProductSettingsScreenState extends State<ProductSettingsScreen> {
  var _resettingPaper = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(
          context,
        ).colorScheme.copyWith(primary: ProductColor.violet),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(l10n.commonSettings),
          centerTitle: false,
          backgroundColor: ProductColor.paper,
          foregroundColor: ProductColor.ink,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            key: const ValueKey('settings-list'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              _accountSection(context),
              if (widget.onReminderPreferences != null)
                _SettingsRow(
                  icon: Icons.notifications_outlined,
                  title: l10n.settingsReminders,
                  onTap: widget.onReminderPreferences,
                ),
              if (widget.onMoney != null)
                _SettingsRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: l10n.commonAddMoney,
                  onTap: widget.onMoney,
                ),
              if (widget.state.notifications.values.any(
                (value) => value.available,
              ))
                _notificationsSection(context),
              _appearanceSection(context),
              if (!MoneyModeScope.isReal(context)) _paperSection(context),
              if (widget.state.money.availability ==
                  SettingsFeatureAvailability.available)
                _moneySection(context),
              if (widget.state.wallet.address != null) _walletSection(context),
              if (widget.state.privacy != null || widget.reasonPrivacy != null)
                _privacySection(context),
              if (widget.onHelp != null ||
                  widget.onSendFeedback != null ||
                  widget.onReportBug != null)
                _supportSection(context),
              if (widget.onTerms != null || widget.onPrivacy != null)
                _legalSection(context),
              if (widget.state.account.signedIn &&
                  widget.onCloseAccount != null)
                _closeAccountSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountSection(BuildContext context) {
    final l10n = context.l10n;
    final account = widget.state.account;
    final methods = account.signInMethods
        .map((method) => method.label(l10n))
        .join(', ');
    return _SettingsSection(
      title: l10n.settingsAccountSection,
      children: [
        if (!account.signedIn)
          _SettingsRow(
            key: const ValueKey('settings-sign-in'),
            icon: Icons.login_rounded,
            title: l10n.commonSignIn,
            subtitle: l10n.settingsSignInDetail,
            onTap: widget.onSignIn,
          ),
        if (account.signedIn && account.handle.isNotEmpty)
          _SettingsRow(
            icon: Icons.alternate_email_rounded,
            title: l10n.settingsHandle,
            subtitle: account.handle,
            onTap: widget.onEditHandle,
          ),
        _SettingsRow(
          icon: Icons.face_rounded,
          title: l10n.settingsYourTrader,
          subtitle: account.persona.isEmpty
              ? l10n.settingsChooseCharacter
              : account.persona,
          onTap: widget.onChangePersona,
        ),
        if (account.email != null)
          _SettingsRow(
            icon: Icons.mail_outline_rounded,
            title: l10n.settingsEmail,
            subtitle: account.email!,
          ),
        if (account.signedIn &&
            (methods.isNotEmpty || widget.onManageSignInMethods != null))
          _SettingsRow(
            icon: Icons.key_rounded,
            title: l10n.settingsSignInMethods,
            subtitle: methods.isEmpty
                ? l10n.settingsSignInMethodsUnavailable
                : methods,
            onTap: widget.onManageSignInMethods,
          ),
        if (account.signedIn)
          _SettingsRow(
            key: const ValueKey('settings-sign-out'),
            icon: Icons.logout_rounded,
            title: l10n.settingsSignOut,
            onTap: widget.onSignOut,
          ),
      ],
    );
  }

  Widget _notificationsSection(BuildContext context) {
    final l10n = context.l10n;
    final formats = context.formats;
    final rows = <Widget>[];
    for (final group in SettingsNotificationGroup.values) {
      if (!widget.state.notifications.entries.any(
        (e) => e.key.group == group && e.value.available,
      )) {
        continue;
      }
      rows.add(_SettingsSubheading(group.label(l10n)));
      for (final kind in SettingsNotificationKind.values.where(
        (kind) => kind.group == group,
      )) {
        final value = widget.state.notification(kind);
        if (!value.available) continue;
        final enabled =
            value.available &&
            !value.updating &&
            widget.onNotificationChanged != null;
        rows.add(
          _SettingsSwitchRow(
            key: ValueKey('notification-${kind.name}'),
            title: kind.title(l10n),
            subtitle: value.available
                ? kind.description(l10n, formats)
                : l10n.settingsNotAvailableYet,
            value: value.enabled,
            busy: value.updating,
            onChanged: enabled
                ? (next) => widget.onNotificationChanged!(kind, next)
                : null,
          ),
        );
      }
    }

    final quietHours = widget.state.quietHours;
    if (quietHours.available) {
      rows.add(_SettingsSubheading(l10n.settingsQuietHours));
      rows.add(
        _SettingsSwitchRow(
          key: const ValueKey('settings-quiet-hours'),
          title: l10n.settingsQuietHours,
          subtitle: quietHours.available
              ? quietHours.timeLabel(l10n)
              : l10n.settingsNotAvailableYet,
          value: quietHours.enabled,
          busy: quietHours.updating,
          onChanged:
              quietHours.available &&
                  !quietHours.updating &&
                  widget.onQuietHoursChanged != null
              ? widget.onQuietHoursChanged
              : null,
          trailingAction: quietHours.available ? widget.onEditQuietHours : null,
        ),
      );
    }
    return _SettingsSection(
      title: l10n.settingsNotificationsSection,
      children: rows,
    );
  }

  Widget _appearanceSection(BuildContext context) {
    final l10n = context.l10n;
    final appearance = widget.state.appearance;
    return _SettingsSection(
      title: l10n.settingsPreferencesSection,
      children: [
        _SettingsSwitchRow(
          key: const ValueKey('settings-sound'),
          iconFile: 'settings-sound.png',
          title: l10n.settingsSound,
          subtitle: l10n.settingsSoundDetail,
          value: appearance.soundEnabled,
          onChanged: widget.onSoundChanged,
        ),
        _SettingsSwitchRow(
          key: const ValueKey('settings-haptics'),
          iconFile: 'settings-haptics.png',
          title: l10n.settingsHaptics,
          subtitle: l10n.settingsHapticsDetail,
          value: appearance.hapticsEnabled,
          onChanged: widget.onHapticsChanged,
        ),
        if (widget.onAnimationsChanged != null)
          _SettingsSwitchRow(
            key: const ValueKey('settings-animations'),
            title: l10n.settingsAnimations,
            subtitle: appearance.systemReduceMotionEnabled
                ? l10n.settingsAnimationsLimited
                : l10n.settingsAnimationsDetail,
            value:
                appearance.animationsEnabled &&
                !appearance.systemReduceMotionEnabled,
            onChanged: appearance.systemReduceMotionEnabled
                ? null
                : widget.onAnimationsChanged,
          ),
        _SettingsRow(
          icon: Icons.motion_photos_off_outlined,
          title: l10n.settingsReduceMotion,
          subtitle: appearance.systemReduceMotionEnabled
              ? l10n.settingsReduceMotionOn
              : l10n.settingsReduceMotionOff,
        ),
        _languageRow(context),
      ],
    );
  }

  Widget _languageRow(BuildContext context) {
    final languages = AppLocaleScope.maybeOf(context);
    return _SettingsRow(
      key: const ValueKey('settings-language'),
      icon: Icons.language_rounded,
      title: context.l10n.settingsLanguage,
      subtitle: languageChoiceLabel(
        context,
        languages?.language ?? AppLanguage.phone,
      ),
      onTap: languages == null
          ? null
          : () => unawaited(showLanguagePicker(context, languages)),
    );
  }

  Widget _paperSection(BuildContext context) => _SettingsSection(
    title: context.l10n.modePaper,
    children: [
      _SettingsRow(
        icon: Icons.description_outlined,
        title: context.l10n.settingsPaperLimit,
        // PaperAmount reads the English figure ("10,000") and writes it for
        // the reader. A locale-formatted figure would be misread: pt-BR
        // "10.000" parses as ten.
        trailing: PaperAmount(
          groupDecimal('${widget.state.paper.limit}'),
          style: Theme.of(context).textTheme.titleMedium,
          markSize: 18,
        ),
      ),
      if (widget.state.paper.resetAvailable && widget.onResetPaper != null)
        _SettingsRow(
          key: const ValueKey('settings-reset-paper'),
          icon: Icons.restart_alt_rounded,
          title: context.l10n.settingsResetPaper,
          subtitle: _resettingPaper
              ? context.l10n.settingsResetPaperBusy
              : widget.state.paper.resetPending
              ? context.l10n.settingsResetPaperPending
              : context.l10n.settingsResetPaperDetail,
          destructive: true,
          busy: _resettingPaper,
          onTap: _resettingPaper ? null : () => _confirmPaperReset(context),
        ),
    ],
  );

  Widget _moneySection(BuildContext context) {
    final l10n = context.l10n;
    final formats = context.formats;
    final money = widget.state.money;
    final children = <Widget>[
      _SettingsStatusRow(
        icon: Icons.account_balance_wallet_outlined,
        title: l10n.commonAddMoney,
        subtitle: switch (money.availability) {
          SettingsFeatureAvailability.available =>
            l10n.settingsMoneyCardOrCrypto,
          SettingsFeatureAvailability.comingSoon =>
            l10n.settingsMoneyComingSoon,
          SettingsFeatureAvailability.unavailable =>
            l10n.settingsMoneyUnavailable,
        },
        onTap: money.availability == SettingsFeatureAvailability.available
            ? widget.onMoney
            : null,
      ),
    ];
    if (money.currency != null) {
      children.add(
        _SettingsInfoRow(title: l10n.settingsCurrency, value: money.currency!),
      );
    }
    if (money.partnerName != null) {
      children.add(
        _SettingsInfoRow(
          title: l10n.settingsDepositPartner,
          value: money.partnerName!,
        ),
      );
    }
    if (money.feeSummary != null) {
      children.add(
        _SettingsInfoRow(title: l10n.settingsFees, value: money.feeSummary!),
      );
    }
    if (money.countryStatus != null) {
      children.add(
        _SettingsInfoRow(
          title: l10n.settingsCountryCheck,
          value: money.countryStatus!,
        ),
      );
    }
    if (money.savedBankAccountCount != null) {
      children.add(
        _SettingsInfoRow(
          title: l10n.settingsBankAccounts,
          value: formats.integer(money.savedBankAccountCount!),
        ),
      );
    }
    if (money.savedCardCount != null) {
      children.add(
        _SettingsInfoRow(
          title: l10n.settingsCards,
          value: formats.integer(money.savedCardCount!),
        ),
      );
    }
    return _SettingsSection(
      title: l10n.settingsMoneySection,
      children: children,
    );
  }

  Widget _walletSection(BuildContext context) {
    final l10n = context.l10n;
    final wallet = widget.state.wallet;
    final address = wallet.address;
    final available =
        wallet.availability == SettingsFeatureAvailability.available;
    return _SettingsSection(
      title: l10n.settingsWallet,
      children: [
        _SettingsStatusRow(
          icon: Icons.wallet_outlined,
          title: l10n.settingsWallet,
          subtitle: switch (wallet.availability) {
            SettingsFeatureAvailability.available when address != null =>
              _shortAddress(address),
            SettingsFeatureAvailability.available =>
              l10n.settingsWalletNoDetails,
            SettingsFeatureAvailability.comingSoon =>
              l10n.settingsWalletComingSoon,
            SettingsFeatureAvailability.unavailable =>
              l10n.settingsWalletUnavailable,
          },
          onTap: available && address != null && widget.onWalletCopy != null
              ? () => widget.onWalletCopy!(address)
              : null,
          actionLabel: available && address != null ? l10n.commonCopy : null,
        ),
        if (widget.onCheckWallet != null)
          _SettingsRow(
            icon: Icons.open_in_new_rounded,
            title: l10n.settingsCheckWallet,
            onTap: available ? widget.onCheckWallet : null,
          ),
        if (widget.onWalletExport != null)
          _SettingsRow(
            icon: Icons.ios_share_rounded,
            title: l10n.settingsBackUpWallet,
            subtitle: l10n.settingsBackUpWalletDetail,
            onTap: available ? widget.onWalletExport : null,
          ),
      ],
    );
  }

  Widget _privacySection(BuildContext context) => _SettingsSection(
    title: context.l10n.settingsPrivacySection,
    children: [
      if (widget.state.privacy != null)
        _SettingsChoiceRow(
          key: const ValueKey('settings-holdings-visibility'),
          title: context.l10n.settingsHoldingsVisibility,
          value: widget.state.privacy!.holdingsVisibility,
          onChanged: widget.onHoldingsVisibilityChanged,
        ),
      if (widget.reasonPrivacy != null)
        ReasonPrivacyRow(controller: widget.reasonPrivacy!),
      if (widget.onDownloadData != null)
        _SettingsRow(
          icon: Icons.download_rounded,
          title: context.l10n.settingsDownloadData,
          onTap: widget.onDownloadData,
        ),
    ],
  );

  Widget _supportSection(BuildContext context) => _SettingsSection(
    title: context.l10n.settingsSupportSection,
    children: [
      if (widget.onHelp != null)
        _SettingsRow(
          icon: Icons.help_outline_rounded,
          title: context.l10n.infoHelpTitle,
          onTap: widget.onHelp,
        ),
      if (widget.onSendFeedback != null)
        _SettingsRow(
          icon: Icons.chat_bubble_outline_rounded,
          title: context.l10n.settingsSendFeedback,
          onTap: widget.onSendFeedback,
        ),
      if (widget.onReportBug != null)
        _SettingsRow(
          icon: Icons.bug_report_outlined,
          title: context.l10n.settingsReportBug,
          subtitle: context.l10n.settingsReportBugDetail,
          onTap: widget.onReportBug,
        ),
    ],
  );

  Widget _legalSection(BuildContext context) => _SettingsSection(
    title: context.l10n.settingsLegalSection,
    children: [
      _SettingsRow(title: context.l10n.infoTermsTitle, onTap: widget.onTerms),
      _SettingsRow(
        title: context.l10n.infoPrivacyTitle,
        onTap: widget.onPrivacy,
      ),
      if (widget.onRiskNotice != null)
        _SettingsRow(
          title: context.l10n.settingsRiskNotice,
          onTap: widget.onRiskNotice,
        ),
      if (widget.onTokenizedStocks != null)
        _SettingsRow(
          title: context.l10n.settingsAboutTokenizedStocks,
          subtitle: context.l10n.settingsAboutTokenizedStocksDetail,
          onTap: widget.onTokenizedStocks,
        ),
    ],
  );

  Widget _closeAccountSection(BuildContext context) => _SettingsSection(
    title: context.l10n.settingsAccountClosureSection,
    children: [
      _SettingsRow(
        key: const ValueKey('settings-close-account'),
        icon: Icons.no_accounts_outlined,
        title: context.l10n.settingsCloseAccount,
        subtitle: context.l10n.settingsCloseAccountDetail,
        destructive: true,
        onTap: widget.state.account.signedIn ? widget.onCloseAccount : null,
      ),
    ],
  );

  Future<void> _confirmPaperReset(BuildContext context) async {
    var confirmation = '';
    final reset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final l10n = dialogContext.l10n;
          // The phrase is typed in the reader's language and compared
          // exactly, as the English phrase always was.
          final phrase = l10n.settingsResetPaperPhrase;
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: productSquircle(26),
            title: Text(l10n.settingsResetPaperTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settingsResetPaperBody),
                  const SizedBox(height: 16),
                  Text(l10n.settingsResetPaperInstruction(phrase)),
                  const SizedBox(height: 8),
                  Semantics(
                    label: l10n.settingsResetPaperFieldLabel(phrase),
                    textField: true,
                    child: TextField(
                      key: const ValueKey('paper-reset-confirmation'),
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      decoration: InputDecoration(
                        labelText: l10n.settingsResetPaperFieldTitle,
                        hintText: phrase,
                        filled: true,
                        fillColor: ProductColor.paperRaised,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => confirmation = value),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                key: const ValueKey('confirm-reset-paper'),
                onPressed: confirmation == phrase
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: ProductColor.loss,
                ),
                child: Text(l10n.settingsResetPaperConfirm),
              ),
            ],
          );
        },
      ),
    );
    if (reset != true || !mounted || widget.onResetPaper == null) return;

    setState(() => _resettingPaper = true);
    try {
      final receipt = await widget.onResetPaper!();
      if (!mounted) return;
      setState(() => _resettingPaper = false);
      await showDialog<void>(
        context: this.context,
        builder: (dialogContext) {
          final l10n = dialogContext.l10n;
          final balance = dialogContext.formats.number(receipt.paperBalance);
          return AlertDialog(
            title: Text(l10n.settingsResetPaperDoneTitle),
            content: Text(
              receipt.hasNewerActivity
                  ? l10n.settingsResetPaperDoneNewer(balance)
                  : l10n.settingsResetPaperDone(balance),
            ),
            actions: [
              FilledButton(
                key: const ValueKey('paper-reset-receipt-done'),
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.commonDone),
              ),
            ],
          );
        },
      );
    } on SettingsPaperResetException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          _settingsNotice(
            this.context,
            _resetFailureMessage(this.context.l10n, error.failure),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          _settingsNotice(
            this.context,
            this.context.l10n.settingsResetPaperFailed,
          ),
        );
      }
    } finally {
      if (mounted && _resettingPaper) {
        setState(() => _resettingPaper = false);
      }
    }
  }

  String _resetFailureMessage(
    AppLocalizations l10n,
    SettingsPaperResetFailure failure,
  ) => switch (failure) {
    SettingsPaperResetFailure.staleRevision => l10n.settingsResetPaperStale,
    SettingsPaperResetFailure.notNeeded => l10n.settingsResetPaperNotNeeded,
    SettingsPaperResetFailure.offline => l10n.settingsResetPaperOffline,
    SettingsPaperResetFailure.timeout => l10n.settingsResetPaperTimeout,
    SettingsPaperResetFailure.accountRequired =>
      l10n.settingsResetPaperAccountRequired,
    SettingsPaperResetFailure.rateLimited => l10n.settingsResetPaperRateLimited,
    SettingsPaperResetFailure.unavailable => l10n.settingsResetPaperUnavailable,
    SettingsPaperResetFailure.rejected => l10n.settingsResetPaperRejected,
  };
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Material(
          color: ProductColor.paperRaised,
          shape: productSquircle(24),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    ),
  );
}

class _SettingsSubheading extends StatelessWidget {
  const _SettingsSubheading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: ProductColor.paper,
    padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: ProductColor.muted,
        letterSpacing: .7,
      ),
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.busy = false,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? ProductColor.loss : ProductColor.ink;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      minTileHeight: 60,
      enabled: onTap != null,
      leading: icon == null
          ? null
          : ProductMotionIcon(file: _iconAsset(icon!), active: onTap != null),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: onTap == null && trailing == null ? ProductColor.muted : color,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
      trailing: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : trailing ??
                (onTap == null
                    ? null
                    : const Icon(Icons.chevron_right_rounded, size: 22)),
      onTap: busy ? null : onTap,
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    super.key,
    this.iconFile = 'asset-bell.png',
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.busy = false,
    this.trailingAction,
  });

  /// The row's motion icon. Notifications use the bell.
  final String iconFile;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool busy;
  final VoidCallback? trailingAction;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.fromLTRB(16, 3, 10, 3),
    minTileHeight: 68,
    enabled: onChanged != null,
    title: Text(
      title,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: onChanged == null ? ProductColor.muted : ProductColor.ink,
      ),
    ),
    leading: ProductMotionIcon(file: iconFile),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailingAction != null)
          IconButton(
            tooltip: context.l10n.settingsEditQuietHours,
            onPressed: trailingAction,
            icon: const Icon(Icons.schedule_rounded),
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: ProductColor.violet,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
      ],
    ),
    onTap: onChanged == null ? null : () => onChanged!(!value),
  );
}

class _SettingsStatusRow extends StatelessWidget {
  const _SettingsStatusRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    minTileHeight: 68,
    leading: ProductMotionIcon(file: _iconAsset(icon)),
    title: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    trailing: actionLabel == null
        ? (onTap == null
              ? null
              : const Icon(Icons.chevron_right_rounded, size: 22))
        : TextButton(onPressed: onTap, child: Text(actionLabel!)),
    onTap: actionLabel == null ? onTap : null,
  );
}

class _SettingsInfoRow extends StatelessWidget {
  const _SettingsInfoRow({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(title)),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _SettingsChoiceRow extends StatelessWidget {
  const _SettingsChoiceRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final SettingsVisibility value;
  final ValueChanged<SettingsVisibility>? onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    minTileHeight: 60,
    title: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    trailing: PopupMenuButton<SettingsVisibility>(
      enabled: onChanged != null,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => SettingsVisibility.values
          .map(
            (choice) => PopupMenuItem(
              value: choice,
              child: Text(choice.label(context.l10n)),
            ),
          )
          .toList(growable: false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.label(context.l10n),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: onChanged == null ? ProductColor.muted : ProductColor.pine,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded),
        ],
      ),
    ),
  );
}

String _shortAddress(String address) {
  if (address.length <= 14) return address;
  return '${address.substring(0, 6)}...${address.substring(address.length - 6)}';
}

String _iconAsset(IconData icon) => switch (icon) {
  Icons.login_rounded => 'settings-lock.png',
  Icons.person_outline_rounded ||
  Icons.face_rounded ||
  Icons.no_accounts_outlined => 'nav-plumpy-profile.png',
  Icons.mail_outline_rounded ||
  Icons.alternate_email_rounded => 'account-email-rounded.png',
  Icons.key_rounded || Icons.logout_rounded => 'settings-lock.png',
  Icons.chat_bubble_outline_rounded ||
  Icons.help_outline_rounded => 'career-comments.png',
  Icons.description_outlined => 'goal-book-animated.png',
  Icons.download_rounded ||
  Icons.wallet_outlined ||
  Icons.account_balance_wallet_outlined => 'nav-plumpy-desk.png',
  _ => 'settings-gear.png',
};
SnackBar _settingsNotice(BuildContext context, String message) => SnackBar(
  duration: const Duration(seconds: 4),
  behavior: SnackBarBehavior.floating,
  backgroundColor: Colors.transparent,
  elevation: 0,
  content: ProductNotice(
    message: message,
    onDismiss: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
  ),
);
