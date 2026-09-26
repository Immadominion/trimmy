import '../money/money_mode.dart';
import 'package:flutter/material.dart';

import '../career/reason_privacy_controller.dart';
import '../design/product_components.dart';
import '../design/product_motion_icon.dart';
import '../design/product_notice.dart';
import '../design/product_theme.dart';
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
    this.onLanguage,
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
  final VoidCallback? onLanguage;
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
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(
          context,
        ).colorScheme.copyWith(primary: ProductColor.violet),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Settings'),
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
                  title: 'Reminders',
                  onTap: widget.onReminderPreferences,
                ),
              if (widget.onMoney != null)
                _SettingsRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Add money',
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
    final account = widget.state.account;
    final methods = account.signInMethods
        .map((method) => method.label)
        .join(', ');
    return _SettingsSection(
      title: 'Account',
      children: [
        if (!account.signedIn)
          _SettingsRow(
            key: const ValueKey('settings-sign-in'),
            icon: Icons.login_rounded,
            title: 'Sign in',
            subtitle: 'Sign in to keep your progress.',
            onTap: widget.onSignIn,
          ),
        if (account.signedIn && account.handle.isNotEmpty)
          _SettingsRow(
            icon: Icons.alternate_email_rounded,
            title: 'Handle',
            subtitle: account.handle,
            onTap: widget.onEditHandle,
          ),
        _SettingsRow(
          icon: Icons.face_rounded,
          title: 'Your trader',
          subtitle: account.persona.isEmpty
              ? 'Choose a character'
              : account.persona,
          onTap: widget.onChangePersona,
        ),
        if (account.email != null)
          _SettingsRow(
            icon: Icons.mail_outline_rounded,
            title: 'Email',
            subtitle: account.email!,
          ),
        if (account.signedIn &&
            (methods.isNotEmpty || widget.onManageSignInMethods != null))
          _SettingsRow(
            icon: Icons.key_rounded,
            title: 'Sign-in methods',
            subtitle: methods.isEmpty ? 'Sign-in method unavailable.' : methods,
            onTap: widget.onManageSignInMethods,
          ),
        if (account.signedIn)
          _SettingsRow(
            key: const ValueKey('settings-sign-out'),
            icon: Icons.logout_rounded,
            title: 'Sign out',
            onTap: widget.onSignOut,
          ),
      ],
    );
  }

  Widget _notificationsSection(BuildContext context) {
    final rows = <Widget>[];
    for (final group in SettingsNotificationGroup.values) {
      rows.add(_SettingsSubheading(group.label));
      for (final kind in SettingsNotificationKind.values.where(
        (kind) => kind.group == group,
      )) {
        final value = widget.state.notification(kind);
        final enabled =
            value.available &&
            !value.updating &&
            widget.onNotificationChanged != null;
        rows.add(
          _SettingsSwitchRow(
            key: ValueKey('notification-${kind.name}'),
            title: kind.title,
            subtitle: value.available ? kind.description : 'Not available yet.',
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
    rows.add(const _SettingsSubheading('Quiet hours'));
    rows.add(
      _SettingsSwitchRow(
        key: const ValueKey('settings-quiet-hours'),
        title: 'Quiet hours',
        subtitle: quietHours.available
            ? quietHours.timeLabel
            : 'Not available yet.',
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

    return _SettingsSection(title: 'Notifications', children: rows);
  }

  Widget _appearanceSection(BuildContext context) {
    final appearance = widget.state.appearance;
    return _SettingsSection(
      title: 'Preferences',
      children: [
        _SettingsSwitchRow(
          key: const ValueKey('settings-sound'),
          title: 'Sound',
          subtitle: 'Sounds for key moments.',
          value: appearance.soundEnabled,
          onChanged: widget.onSoundChanged,
        ),
        _SettingsSwitchRow(
          key: const ValueKey('settings-haptics'),
          title: 'Haptics',
          subtitle: 'Taps you can feel.',
          value: appearance.hapticsEnabled,
          onChanged: widget.onHapticsChanged,
        ),
        if (widget.onAnimationsChanged != null)
          _SettingsSwitchRow(
            key: const ValueKey('settings-animations'),
            title: 'Animations',
            subtitle: appearance.systemReduceMotionEnabled
                ? 'Limited by your phone setting.'
                : 'Movement and celebrations.',
            value:
                appearance.animationsEnabled &&
                !appearance.systemReduceMotionEnabled,
            onChanged: appearance.systemReduceMotionEnabled
                ? null
                : widget.onAnimationsChanged,
          ),
        _SettingsRow(
          icon: Icons.motion_photos_off_outlined,
          title: 'Reduce motion',
          subtitle: appearance.systemReduceMotionEnabled
              ? 'On. Follows your phone setting.'
              : 'Off. Follows your phone setting.',
        ),
        _SettingsRow(
          icon: Icons.language_rounded,
          title: 'Language',
          subtitle: appearance.languageLabel,
          onTap: widget.onLanguage,
        ),
      ],
    );
  }

  Widget _paperSection(BuildContext context) => _SettingsSection(
    title: 'Paper',
    children: [
      _SettingsRow(
        icon: Icons.description_outlined,
        title: 'Paper limit',
        trailing: PaperAmount(
          _formatWhole(widget.state.paper.limit),
          style: Theme.of(context).textTheme.titleMedium,
          markSize: 18,
        ),
      ),
      if (widget.state.paper.resetAvailable && widget.onResetPaper != null)
        _SettingsRow(
          key: const ValueKey('settings-reset-paper'),
          icon: Icons.restart_alt_rounded,
          title: 'Reset paper',
          subtitle: _resettingPaper
              ? 'Resetting your paper desk.'
              : widget.state.paper.resetPending
              ? 'Your confirmed reset is waiting to finish.'
              : 'Clear paper trades and start again.',
          destructive: true,
          busy: _resettingPaper,
          onTap: _resettingPaper ? null : () => _confirmPaperReset(context),
        ),
    ],
  );

  Widget _moneySection(BuildContext context) {
    final money = widget.state.money;
    final children = <Widget>[
      _SettingsStatusRow(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Add money',
        subtitle: switch (money.availability) {
          SettingsFeatureAvailability.available => 'Card or crypto',
          SettingsFeatureAvailability.comingSoon =>
            'Money trading is coming later.',
          SettingsFeatureAvailability.unavailable =>
            'Money features are unavailable for this account.',
        },
        onTap: money.availability == SettingsFeatureAvailability.available
            ? widget.onMoney
            : null,
      ),
    ];
    if (money.currency != null) {
      children.add(_SettingsInfoRow(title: 'Currency', value: money.currency!));
    }
    if (money.partnerName != null) {
      children.add(
        _SettingsInfoRow(title: 'Deposit partner', value: money.partnerName!),
      );
    }
    if (money.feeSummary != null) {
      children.add(_SettingsInfoRow(title: 'Fees', value: money.feeSummary!));
    }
    if (money.countryStatus != null) {
      children.add(
        _SettingsInfoRow(title: 'Country check', value: money.countryStatus!),
      );
    }
    if (money.savedBankAccountCount != null) {
      children.add(
        _SettingsInfoRow(
          title: 'Bank accounts',
          value: '${money.savedBankAccountCount}',
        ),
      );
    }
    if (money.savedCardCount != null) {
      children.add(
        _SettingsInfoRow(title: 'Cards', value: '${money.savedCardCount}'),
      );
    }
    return _SettingsSection(title: 'Money', children: children);
  }

  Widget _walletSection(BuildContext context) {
    final wallet = widget.state.wallet;
    final address = wallet.address;
    final available =
        wallet.availability == SettingsFeatureAvailability.available;
    return _SettingsSection(
      title: 'Wallet',
      children: [
        _SettingsStatusRow(
          icon: Icons.wallet_outlined,
          title: 'Wallet',
          subtitle: switch (wallet.availability) {
            SettingsFeatureAvailability.available when address != null =>
              _shortAddress(address),
            SettingsFeatureAvailability.available =>
              'No wallet details are available yet.',
            SettingsFeatureAvailability.comingSoon =>
              'Wallet tools are coming later.',
            SettingsFeatureAvailability.unavailable =>
              'Wallet tools are unavailable for this account.',
          },
          onTap: available && address != null && widget.onWalletCopy != null
              ? () => widget.onWalletCopy!(address)
              : null,
          actionLabel: available && address != null ? 'Copy' : null,
        ),
        if (widget.onCheckWallet != null)
          _SettingsRow(
            icon: Icons.open_in_new_rounded,
            title: 'Check wallet',
            onTap: available ? widget.onCheckWallet : null,
          ),
        if (widget.onWalletExport != null)
          _SettingsRow(
            icon: Icons.ios_share_rounded,
            title: 'Back up wallet',
            subtitle: 'Keep access outside Trimmy.',
            onTap: available ? widget.onWalletExport : null,
          ),
      ],
    );
  }

  Widget _privacySection(BuildContext context) => _SettingsSection(
    title: 'Privacy',
    children: [
      if (widget.state.privacy != null)
        _SettingsChoiceRow(
          key: const ValueKey('settings-holdings-visibility'),
          title: 'Who sees my holdings',
          value: widget.state.privacy!.holdingsVisibility,
          onChanged: widget.onHoldingsVisibilityChanged,
        ),
      if (widget.reasonPrivacy != null)
        ReasonPrivacyRow(controller: widget.reasonPrivacy!),
      if (widget.onDownloadData != null)
        _SettingsRow(
          icon: Icons.download_rounded,
          title: 'Download my data',
          onTap: widget.onDownloadData,
        ),
    ],
  );

  Widget _supportSection(BuildContext context) => _SettingsSection(
    title: 'Support',
    children: [
      if (widget.onHelp != null)
        _SettingsRow(
          icon: Icons.help_outline_rounded,
          title: 'Help',
          onTap: widget.onHelp,
        ),
      if (widget.onSendFeedback != null)
        _SettingsRow(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Send feedback',
          onTap: widget.onSendFeedback,
        ),
      if (widget.onReportBug != null)
        _SettingsRow(
          icon: Icons.bug_report_outlined,
          title: 'Report a bug',
          subtitle: 'Your app version will be attached.',
          onTap: widget.onReportBug,
        ),
    ],
  );

  Widget _legalSection(BuildContext context) => _SettingsSection(
    title: 'Legal',
    children: [
      _SettingsRow(title: 'Terms', onTap: widget.onTerms),
      _SettingsRow(title: 'Privacy', onTap: widget.onPrivacy),
      if (widget.onRiskNotice != null)
        _SettingsRow(title: 'Risk notice', onTap: widget.onRiskNotice),
      if (widget.onTokenizedStocks != null)
        _SettingsRow(
          title: 'About tokenized stocks',
          subtitle: 'What they are and what they are not.',
          onTap: widget.onTokenizedStocks,
        ),
    ],
  );

  Widget _closeAccountSection(BuildContext context) => _SettingsSection(
    title: 'Account closure',
    children: [
      _SettingsRow(
        key: const ValueKey('settings-close-account'),
        icon: Icons.no_accounts_outlined,
        title: 'Close account',
        subtitle: 'Review what happens to your records and wallet.',
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
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: productSquircle(26),
          title: const Text('Reset your paper desk?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This starts a fresh paper desk. Past receipts stay in your record. Your Career, Trims, rank, streak and money do not change.',
                ),
                const SizedBox(height: 16),
                const Text('Type “reset my paper desk” to continue.'),
                const SizedBox(height: 8),
                Semantics(
                  label: 'Confirmation phrase. Type reset my paper desk.',
                  textField: true,
                  child: TextField(
                    key: const ValueKey('paper-reset-confirmation'),
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: 'Confirmation phrase',
                      hintText: 'reset my paper desk',
                      filled: true,
                      fillColor: ProductColor.paperRaised,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('confirm-reset-paper'),
              onPressed: confirmation == 'reset my paper desk'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              style: FilledButton.styleFrom(backgroundColor: ProductColor.loss),
              child: const Text('Reset paper desk'),
            ),
          ],
        ),
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
        builder: (dialogContext) => AlertDialog(
          title: const Text('Paper desk reset'),
          content: Text(
            receipt.hasNewerActivity
                ? 'Newer trades were kept. Your balance is ${receipt.paperBalance} paper.'
                : 'Your desk is ready with ${receipt.paperBalance} paper.',
          ),
          actions: [
            FilledButton(
              key: const ValueKey('paper-reset-receipt-done'),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on SettingsPaperResetException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          _settingsNotice(this.context, _resetFailureMessage(error.failure)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          _settingsNotice(this.context, 'Paper was not reset. Try again.'),
        );
      }
    } finally {
      if (mounted && _resettingPaper) {
        setState(() => _resettingPaper = false);
      }
    }
  }

  String _resetFailureMessage(
    SettingsPaperResetFailure failure,
  ) => switch (failure) {
    SettingsPaperResetFailure.staleRevision =>
      'Your paper desk changed. It was refreshed. Review it, then confirm the reset again.',
    SettingsPaperResetFailure.notNeeded =>
      'Your paper desk is already fresh. Nothing was cleared.',
    SettingsPaperResetFailure.offline =>
      'You are offline. Your exact reset request is saved for a safe retry.',
    SettingsPaperResetFailure.timeout =>
      'The reset took too long to confirm. Your exact request is saved for a safe retry.',
    SettingsPaperResetFailure.accountRequired =>
      'Your paper desk needs a fresh session before the reset can finish.',
    SettingsPaperResetFailure.rateLimited =>
      'Paper resets are limited. Try this saved request again later.',
    SettingsPaperResetFailure.unavailable =>
      'The reset could not be confirmed. Your exact request is saved for a safe retry.',
    SettingsPaperResetFailure.rejected =>
      'Paper was not reset. Refresh your desk and try again.',
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
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.busy = false,
    this.trailingAction,
  });

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
    leading: ProductMotionIcon(
      file: title == 'Sound'
          ? 'settings-sound.png'
          : title == 'Haptics'
          ? 'settings-haptics.png'
          : 'asset-bell.png',
    ),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (trailingAction != null)
          IconButton(
            tooltip: 'Edit quiet hours',
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
            (choice) => PopupMenuItem(value: choice, child: Text(choice.label)),
          )
          .toList(growable: false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.label,
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

String _formatWhole(int value) {
  final digits = value.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    final start = (end - 3).clamp(0, digits.length);
    groups.add(digits.substring(start, end));
  }
  final formatted = groups.reversed.join(',');
  return value < 0 ? '-$formatted' : formatted;
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
