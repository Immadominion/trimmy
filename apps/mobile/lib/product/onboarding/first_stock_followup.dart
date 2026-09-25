import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../ui_review/review_feedback.dart';
import '../../ui_review/review_trade_ticket.dart';
import '../design/product_motion_icon.dart';
import '../design/product_success_mark.dart';
import '../design/product_theme.dart';
import '../market/market_craft.dart';
import '../notifications/notification_permission.dart';
import 'onboarding_models.dart';

enum ReminderPreference {
  daily('Once a day', 'Around 7 PM, your time.'),
  occasional('A few times a week', 'Mon, Wed and Fri, around 7 PM.'),
  off('Keep it quiet', 'I’ll come back on my own.');

  const ReminderPreference(this.label, this.caption);
  final String label, caption;
}

class ReminderPreferences {
  static String _key(String principal) => 'trimmy.reminders.v1.$principal';
  static ReminderPreference? read(
    SharedPreferences preferences,
    String principal,
  ) {
    final value = preferences.getString(_key(principal));
    for (final item in ReminderPreference.values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static Future<void> save(
    SharedPreferences preferences,
    String principal,
    ReminderPreference value,
    OnboardingNotificationStatus permission,
  ) async {
    if (!await preferences.setString(_key(principal), value.name) ||
        !await preferences.setString(
          '${_key(principal)}.permission',
          permission.name,
        )) {
      throw StateError('REMINDER_PREFERENCE_NOT_SAVED');
    }
  }

  /// Reconciles the active profile without displaying an OS permission prompt.
  /// A previous denial may have been changed in system Settings since saving.
  static Future<bool> sync(SharedPreferences preferences, String? principal) =>
      ProductNotificationPermission.setReminder(
        principal == null
            ? ReminderPreference.off.name
            : (read(preferences, principal) ?? ReminderPreference.off).name,
      );
}

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
    this.orderId,
  });
  final SharedPreferences preferences;
  final String principal, name, symbol, shares;
  final String? logoUrl, amount, orderId;
  final int initialStep;
  final Future<void> Function(bool addMoney) onFinish;
  final Future<void> Function()? onCelebrationContinue;

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
  String? _error;

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
      if (mounted) setState(() => _error = 'Couldn’t save that. Try again.');
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
        setState(() => _error = 'Your trade is safe. Try continuing again.');
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
      );
    }
    final theme = Theme.of(context).textTheme;
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
                      tooltip: 'Keep using free money',
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
                        'You’ve placed your first order!',
                        textAlign: TextAlign.center,
                        style: theme.headlineLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Now let’s create your trader profile.',
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
                              '${widget.shares} shares',
                              style: theme.headlineMedium,
                            ),
                            if (widget.amount != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                '${widget.amount} free money',
                                style: theme.bodyMedium,
                              ),
                            ],
                          ],
                        ),
                        lower: Text(
                          'Buy confirmed',
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
                      Text('Your next move.', style: theme.headlineLarge),
                      const SizedBox(height: 12),
                      Text(
                        'Keep finding your feet, or fund your wallet.',
                        style: theme.bodyLarge,
                      ),
                      const SizedBox(height: 28),
                      SetupChoiceCard(
                        title: 'Keep using free money',
                        caption: 'Build your confidence on the desk.',
                        icon: const ProductMotionIcon(
                          file: 'goal-goal-animated.png',
                          animatedFile: 'goal-goal-animated.gif',
                          size: 34,
                        ),
                        onTap: _busy ? null : () => _finish(false),
                      ),
                      const SizedBox(height: 14),
                      SetupChoiceCard(
                        title: 'Add money',
                        caption: 'See your deposit options.',
                        icon: const Icon(
                          Icons.add_rounded,
                          color: ProductColor.violet,
                          size: 30,
                        ),
                        onTap: _busy ? null : () => _finish(true),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'You can add money from your desk any time.',
                        style: theme.bodySmall,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        _error!,
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
                      child: Text(_busy ? 'Saving…' : 'Continue'),
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

class ReminderPreferencePage extends StatefulWidget {
  const ReminderPreferencePage({
    super.key,
    required this.preferences,
    required this.principal,
    required this.onDone,
    this.requestPermission = ProductNotificationPermission.request,
    this.setReminder = ProductNotificationPermission.setReminder,
  });
  final SharedPreferences preferences;
  final String principal;
  final Future<void> Function() onDone;
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
  String? _message;
  bool _saved = false;

  Future<void> _save({bool skip = false}) async {
    if (_busy) return;
    final choice = skip ? ReminderPreference.off : _selected;
    if (choice == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
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
      final scheduled = await widget.setReminder(
        permission == OnboardingNotificationStatus.granted
            ? choice.name
            : ReminderPreference.off.name,
      );
      if (!mounted) return;
      if (choice != ReminderPreference.off &&
          permission != OnboardingNotificationStatus.granted) {
        setState(() {
          _saved = true;
          _message = permission == OnboardingNotificationStatus.denied
              ? 'Notifications are off. You can change this in your phone settings.'
              : 'Your preference is saved. Notifications aren’t available on this build yet.';
        });
      } else if (!scheduled) {
        setState(() => _message = 'Couldn’t set the reminder. Try again.');
      } else {
        await widget.onDone();
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Couldn’t save that. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
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
                    tooltip: 'Skip reminders',
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
                    Text('A little nudge?', style: theme.headlineLarge),
                    const SizedBox(height: 12),
                    Text(
                      'How often would you like a reminder?',
                      style: theme.bodyLarge,
                    ),
                    const SizedBox(height: 30),
                    for (final preference in ReminderPreference.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SetupChoiceCard(
                          title: preference.label,
                          caption: preference.caption,
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
                        child: Text(_message!, style: theme.bodyMedium),
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
                        child: Text(_busy ? 'Saving…' : 'Continue'),
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
