import '../notifications/reminder_preferences.dart';
export '../notifications/reminder_preferences.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/l10n.dart';
import '../../ui_review/review_feedback.dart';
import '../../ui_review/review_trade_ticket.dart';
import '../design/product_motion_icon.dart';
import '../design/product_success_mark.dart';
import '../design/product_theme.dart';
import '../market/market_craft.dart';
import '../notifications/notification_permission.dart';
import 'onboarding_models.dart';
import '../analytics/product_events.dart'
    show PermissionOutcome, ProductEvent, ReminderFrequency;
import '../analytics/usage_scope.dart';

/// What went wrong on the celebration or next-move step.
enum _FollowupError { notSaved, continueFailed }

/// Optional preferences never submit another order. The final callback commits
/// the existing server-verified introduction checkpoint before opening Home.
class FirstStockFollowup extends StatefulWidget {
  const FirstStockFollowup({
    super.key,
    required this.preferences,
    required this.principal,
    required this.name,
    required this.symbol,
    required this.shares,
    required this.onFinish,
    this.logoUrl,
    this.amount,
    this.initialStep = 0,
    this.onCelebrationContinue,
    this.syncPreferences,
    this.orderId,
  });
  final SharedPreferences preferences;
  final String principal, name, symbol, shares;
  final String? logoUrl, amount, orderId;
  final int initialStep;
  final Future<void> Function(bool addMoney) onFinish;
  final Future<void> Function()? onCelebrationContinue;
  final Future<void> Function()? syncPreferences;

  static String stepKey(String principal) =>
      'trimmy.first-stock-setup.v1.$principal';

  static const celebratedOrderKey = 'trimmy.entry.celebrated-order.v1';

  static Future<void> acknowledgeCelebration(
    SharedPreferences preferences,
    String principal,
    String orderId,
  ) async {
    if (!await preferences.setString(celebratedOrderKey, orderId) ||
        !await preferences.setInt(stepKey(principal), 1)) {
      throw StateError('CELEBRATION_NOT_SAVED');
    }
  }

  @override
  State<FirstStockFollowup> createState() => _FirstStockFollowupState();
}

class _FirstStockFollowupState extends State<FirstStockFollowup> {
  late int _step =
      (widget.preferences.getInt(
                FirstStockFollowup.stepKey(widget.principal),
              ) ??
              // Claiming a tutorial desk can change its local principal key.
              // Only the same server-confirmed order may skip its celebration.
              (widget.initialStep == 0 &&
                      widget.orderId != null &&
                      widget.preferences.getString(
                            FirstStockFollowup.celebratedOrderKey,
                          ) ==
                          widget.orderId
                  ? 1
                  : widget.initialStep))
          .clamp(0, 2);
  bool _busy = false;
  _FollowupError? _error;

  @override
  void initState() {
    super.initState();
    if (_step == 0) ReviewFeedback.shared.workCue(WorkSound.complete);
  }

  Future<void> _next() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_step == 0 && widget.onCelebrationContinue != null) {
        await widget.onCelebrationContinue!();
        if (mounted) setState(() => _step = 1);
        return;
      }
      final next = _step + 1;
      if (!await widget.preferences.setInt(
        FirstStockFollowup.stepKey(widget.principal),
        next,
      )) {
        throw StateError('STEP_NOT_SAVED');
      }
      if (mounted) setState(() => _step = next);
    } catch (_) {
      if (mounted) setState(() => _error = _FollowupError.notSaved);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(bool money) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onFinish(money);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _FollowupError.continueFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 1) {
      return ReminderPreferencePage(
        preferences: widget.preferences,
        principal: widget.principal,
        onDone: _next,
        syncPreferences: widget.syncPreferences,
      );
    }
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final formats = context.formats;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _step == 0 ? _next() : _finish(false);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              if (_step == 2)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, top: 6),
                    child: IconButton(
                      tooltip: l10n.firstTradeKeepFreeMoney,
                      onPressed: _busy ? null : () => _finish(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                  children: [
                    if (_step == 0) ...[
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: .7, end: 1),
                        duration: productDuration(context, 560),
                        curve: Curves.easeOutBack,
                        builder: (_, value, child) =>
                            Transform.scale(scale: value, child: child),
                        child: const ProductSuccessMark(size: 78),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.firstTradeOrderPlaced,
                        textAlign: TextAlign.center,
                        style: theme.headlineLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.firstTradeCreateProfile,
                        textAlign: TextAlign.center,
                        style: theme.bodyLarge,
                      ),
                      const SizedBox(height: 30),
                      ReviewTradeTicket(
                        upper: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CompanyLogo(
                                  name: widget.name,
                                  color: ProductColor.violet,
                                  logoUrl: widget.logoUrl,
                                  size: 48,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    widget.name,
                                    style: theme.titleLarge,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(
                              l10n.firstTradeSharesCount(
                                _shareCount(widget.shares),
                                formats.number(widget.shares),
                              ),
                              style: theme.headlineMedium,
                            ),
                            if (widget.amount != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                l10n.firstTradeFreeMoneyAmount(
                                  formats.number(widget.amount!),
                                ),
                                style: theme.bodyMedium,
                              ),
                            ],
                          ],
                        ),
                        lower: Text(
                          l10n.firstTradeBuyConfirmed,
                          style: theme.titleMedium?.copyWith(
                            color: ProductColor.gain,
                          ),
                        ),
                      ),
                    ] else ...[
                      Center(
                        child: Image.asset(
                          'assets/images/career_world/safe.png',
                          height: 155,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Text(l10n.firstTradeNextMove, style: theme.headlineLarge),
                      const SizedBox(height: 12),
                      Text(l10n.firstTradeNextMoveBody, style: theme.bodyLarge),
                      const SizedBox(height: 28),
                      SetupChoiceCard(
                        title: l10n.firstTradeKeepFreeMoney,
                        caption: l10n.firstTradeKeepFreeMoneyDetail,
                        icon: const ProductMotionIcon(
                          file: 'goal-goal-animated.png',
                          animatedFile: 'goal-goal-animated.gif',
                          size: 34,
                        ),
                        onTap: _busy ? null : () => _finish(false),
                      ),
                      const SizedBox(height: 14),
                      SetupChoiceCard(
                        title: l10n.commonAddMoney,
                        caption: l10n.firstTradeAddMoneyDetail,
                        icon: const Icon(
                          Icons.add_rounded,
                          color: ProductColor.violet,
                          size: 30,
                        ),
                        onTap: _busy ? null : () => _finish(true),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        l10n.firstTradeAddMoneyLater,
                        style: theme.bodySmall,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        switch (_error!) {
                          _FollowupError.notSaved =>
                            l10n.onboardingCouldNotSave,
                          _FollowupError.continueFailed =>
                            l10n.firstTradeContinueSafe,
                        },
                        style: theme.bodyMedium?.copyWith(
                          color: ProductColor.loss,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_step == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: ProductColor.violet,
                        padding: const EdgeInsets.all(18),
                        shape: productSquircle(22),
                      ),
                      child: Text(
                        _busy ? l10n.commonSaving : l10n.commonContinue,
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

/// The share count for picking "share" or "shares" in each language. The
/// text shown is always the exact figure the server sent.
num _shareCount(String shares) =>
    double.tryParse(shares.replaceAll(',', '')) ?? 0;

/// What the reminder step tells the player after trying to save.
enum _ReminderNotice {
  permissionDenied,
  notificationsUnavailable,
  reminderNotSet,
  changedElsewhere,
  notSaved,
  savedReminderNotSet,
  savedSyncPending,
}

class ReminderPreferencePage extends StatefulWidget {
  const ReminderPreferencePage({
    super.key,
    required this.preferences,
    required this.principal,
    required this.onDone,
    this.syncPreferences,
    this.requestPermission = ProductNotificationPermission.request,
    this.setReminder = ProductNotificationPermission.setReminder,
  });
  final SharedPreferences preferences;
  final String principal;
  final Future<void> Function() onDone;
  final Future<void> Function()? syncPreferences;
  final RequestOnboardingNotificationPermission requestPermission;
  final Future<bool> Function(String preference) setReminder;
  @override
  State<ReminderPreferencePage> createState() => _ReminderPreferencePageState();
}

class _ReminderPreferencePageState extends State<ReminderPreferencePage> {
  late ReminderPreference? _selected = ReminderPreferences.read(
    widget.preferences,
    widget.principal,
  );
  bool _busy = false;
  _ReminderNotice? _message;
  bool _saved = false;

  Future<void> _save({bool skip = false}) async {
    if (_busy) return;
    final choice = skip ? ReminderPreference.off : _selected;
    if (choice == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    var savedLocally = false;
    var scheduledLocally = false;
    try {
      if (_saved && !skip) {
        await widget.onDone();
        return;
      }
      final permission = choice == ReminderPreference.off
          ? OnboardingNotificationStatus.notRequested
          : await widget.requestPermission();
      await ReminderPreferences.save(
        widget.preferences,
        widget.principal,
        choice,
        permission,
      );
      savedLocally = true;
      if (mounted) {
        UsageScope.of(context).track(
          ProductEvent.reminderChoice(
            ReminderFrequency.values.byName(choice.name),
            switch (permission) {
              OnboardingNotificationStatus.granted => PermissionOutcome.granted,
              OnboardingNotificationStatus.denied => PermissionOutcome.denied,
              _ => PermissionOutcome.notAsked,
            },
          ),
        );
      }
      var scheduled = await widget.setReminder(
        permission == OnboardingNotificationStatus.granted
            ? choice.name
            : ReminderPreference.off.name,
      );
      scheduledLocally = scheduled;
      await widget.syncPreferences?.call();
      if (!mounted) return;
      final effective = ReminderPreferences.read(
        widget.preferences,
        widget.principal,
      );
      if (effective != choice) {
        scheduled = await widget.setReminder(
          (effective ?? ReminderPreference.off).name,
        );
        if (!mounted) return;
        setState(() => _selected = effective);
      }
      if (choice != ReminderPreference.off &&
          permission != OnboardingNotificationStatus.granted) {
        setState(() {
          _saved = true;
          _message = permission == OnboardingNotificationStatus.denied
              ? _ReminderNotice.permissionDenied
              : _ReminderNotice.notificationsUnavailable;
        });
      } else if (!scheduled) {
        setState(() => _message = _ReminderNotice.reminderNotSet);
      } else {
        await widget.onDone();
      }
    } on ReminderPreferenceChanged {
      if (!mounted) return;
      // The server may have adopted a newer opt-out. Cancel the old schedule too.
      try {
        await widget.setReminder(
          (ReminderPreferences.read(widget.preferences, widget.principal) ??
                  ReminderPreference.off)
              .name,
        );
      } catch (_) {
        /* Reconciled again when the app resumes. */
      }
      if (mounted) {
        setState(() {
          _selected = ReminderPreferences.read(
            widget.preferences,
            widget.principal,
          );
          _message = _ReminderNotice.changedElsewhere;
        });
      }
    } catch (_) {
      if (mounted) {
        _saved = savedLocally && scheduledLocally;
        setState(
          () => _message = !savedLocally
              ? _ReminderNotice.notSaved
              : !scheduledLocally
              ? _ReminderNotice.savedReminderNotSet
              : _ReminderNotice.savedSyncPending,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _notice(
    AppLocalizations l10n,
    _ReminderNotice notice,
  ) => switch (notice) {
    _ReminderNotice.permissionDenied => l10n.onboardingReminderPermissionOff,
    _ReminderNotice.notificationsUnavailable =>
      l10n.onboardingReminderUnavailable,
    _ReminderNotice.reminderNotSet => l10n.onboardingReminderNotSet,
    _ReminderNotice.changedElsewhere => l10n.onboardingReminderChanged,
    _ReminderNotice.notSaved => l10n.onboardingCouldNotSave,
    _ReminderNotice.savedReminderNotSet => l10n.onboardingReminderSavedNotSet,
    _ReminderNotice.savedSyncPending => l10n.onboardingReminderSavedOffline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save(skip: true);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 6),
                  child: IconButton(
                    tooltip: l10n.onboardingReminderSkip,
                    onPressed: _busy ? null : () => _save(skip: true),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: ProductMotionIcon(
                        file: 'asset-bell.png',
                        size: 52,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      l10n.onboardingReminderTitle,
                      style: theme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.onboardingReminderQuestion,
                      style: theme.bodyLarge,
                    ),
                    const SizedBox(height: 30),
                    for (final preference in ReminderPreference.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SetupChoiceCard(
                          title: preference.label(l10n),
                          caption: preference.caption(l10n),
                          selected: _selected == preference,
                          onTap: _busy
                              ? null
                              : () {
                                  ReviewFeedback.shared.press(selection: true);
                                  setState(() {
                                    _selected = preference;
                                    _saved = false;
                                    _message = null;
                                  });
                                },
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _notice(l10n, _message!),
                          style: theme.bodyMedium,
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy || _selected == null
                            ? null
                            : () => _save(),
                        style: FilledButton.styleFrom(
                          backgroundColor: ProductColor.violet,
                          padding: const EdgeInsets.all(18),
                          shape: productSquircle(22),
                        ),
                        child: Text(
                          _busy ? l10n.commonSaving : l10n.commonContinue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupChoiceCard extends StatelessWidget {
  const SetupChoiceCard({
    super.key,
    required this.title,
    required this.caption,
    required this.onTap,
    this.selected = false,
    this.icon,
  });
  final String title, caption;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? icon;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: AnimatedContainer(
      duration: productDuration(context, 160),
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
      decoration: ShapeDecoration(
        color: selected ? ProductColor.violet : const Color(0xFFE8E4F0),
        shape: productSquircle(25),
      ),
      child: Material(
        color: selected ? const Color(0xFFFAF8FF) : ProductColor.paperRaised,
        shape: productSquircle(23),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 16)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        caption,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
