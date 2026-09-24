import 'package:flutter/material.dart';

import 'review_components.dart';
import 'ui_review_app.dart';
import 'review_feedback.dart';

class ReviewSaveDeskPage extends StatelessWidget {
  const ReviewSaveDeskPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Your first day is safe on this phone',
    title: 'Save your desk anywhere.',
    subtitle:
        'Sign in to restore it on another phone, compete with friends, or add money later.',
    onBack: onBack,
    background: UiReviewColor.lilac,
    child: Column(
      children: [
        Transform.rotate(
          angle: -.02,
          child: const ReviewPaper(
            color: UiReviewColor.lemon,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: UiReviewColor.violet,
                  child: Text(
                    'O',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@trimmydemo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text('Rookie • 50 Trims • Day 1'),
                    ],
                  ),
                ),
                Icon(Icons.lock_rounded),
              ],
            ),
          ),
        ),
        const SizedBox(height: 31),
        _SignInMethod(
          label: 'Continue with X',
          icon: Icons.alternate_email_rounded,
          color: UiReviewColor.ink,
          foreground: Colors.white,
          onTap: onContinue,
        ),
        const SizedBox(height: 10),
        _SignInMethod(
          label: 'Continue with Google',
          icon: Icons.g_mobiledata_rounded,
          onTap: onContinue,
        ),
        const SizedBox(height: 10),
        _SignInMethod(
          label: 'Continue with email',
          icon: Icons.mail_outline_rounded,
          onTap: onContinue,
        ),
        const SizedBox(height: 6),
        ReviewTextButton(label: 'Later', onPressed: onContinue),
      ],
    ),
  );
}

class _SignInMethod extends StatelessWidget {
  const _SignInMethod({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.foreground = UiReviewColor.ink,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color, foreground;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(21),
      side: const BorderSide(color: UiReviewColor.ink, width: 1.2),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            const SizedBox(width: 17),
            Icon(icon, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 53),
          ],
        ),
      ),
    ),
  );
}

class ReviewEmailPage extends StatelessWidget {
  const ReviewEmailPage({
    super.key,
    required this.code,
    required this.onBack,
    required this.onContinue,
  });
  final bool code;
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: code ? 'Check your inbox' : 'Save your desk',
    title: code ? 'Enter the code.' : 'What is your email?',
    subtitle: code
        ? 'We sent six digits to demo@trimmy.xyz.'
        : 'We will send one sign-in code. No password.',
    onBack: onBack,
    bottom: ReviewPrimaryButton(
      label: code ? 'Sign in' : 'Send code',
      onPressed: onContinue,
    ),
    child: Column(
      children: [
        if (code)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final digit in const ['2', '0', '4', '8', '1', '6'])
                _CodeCell(digit),
            ],
          )
        else
          TextFormField(
            initialValue: 'demo@trimmy.xyz',
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email address',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: UiReviewColor.ink,
                  width: 1.3,
                ),
              ),
            ),
          ),
        const SizedBox(height: 23),
        const ReviewSalMessage(
          mood: 'deadpan',
          message:
              'A saved desk survives a lost phone. The market will survive too.',
        ),
        if (code) ...[
          const SizedBox(height: 15),
          ReviewTextButton(label: 'Use a different email', onPressed: onBack),
        ],
      ],
    ),
  );
}

class _CodeCell extends StatelessWidget {
  const _CodeCell(this.digit);
  final String digit;
  @override
  Widget build(BuildContext context) => Container(
    width: 47,
    height: 58,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: UiReviewColor.ink, width: 1.3),
    ),
    child: Text(
      digit,
      style: const TextStyle(
        fontFamily: reviewDisplay,
        fontSize: 25,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class ReviewRecoveryPage extends StatelessWidget {
  const ReviewRecoveryPage({
    super.key,
    required this.preserved,
    required this.onBack,
    required this.onContinue,
  });
  final bool preserved;
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: preserved ? 'Both desks are safe' : 'This desk needs you',
    title: preserved ? 'We kept them separate.' : 'Your guest desk expired.',
    subtitle: preserved
        ? 'Your signed-in desk and this guest desk have separate histories. Nothing was silently merged.'
        : 'Sign in to recover a saved desk, or begin a fresh practice desk.',
    onBack: onBack,
    background: preserved ? UiReviewColor.mint : UiReviewColor.lemon,
    bottom: ReviewPrimaryButton(
      label: preserved ? 'Open my signed-in desk' : 'Sign in to recover',
      onPressed: onContinue,
    ),
    child: Column(
      children: [
        ReviewSal(mood: preserved ? 'proud' : 'warning', width: 190),
        const SizedBox(height: 15),
        ReviewPaper(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preserved ? 'GUEST DESK PRESERVED' : 'WHAT STAYS SAFE',
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                preserved
                    ? '10,001.72 paper • 1 Apple position'
                    : 'Confirmed server records and any separately saved account.',
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                preserved
                    ? 'You can choose which desk to use. A merge is not available.'
                    : 'Starting over creates a new 10,000 paper desk.',
                style: TextStyle(
                  color: UiReviewColor.ink.withValues(alpha: .66),
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (!preserved) ...[
          const SizedBox(height: 12),
          ReviewTextButton(label: 'Start a new desk', onPressed: onContinue),
        ],
      ],
    ),
  );
}

class ReviewSettingsHubPage extends StatelessWidget {
  const ReviewSettingsHubPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: '@trimmydemo',
    title: 'Settings',
    subtitle:
        'Quiet controls for your account, alerts, paper desk and privacy.',
    onBack: onBack,
    child: Column(
      children: [
        _SettingsGroup(
          title: 'ACCOUNT',
          rows: [
            _SettingsRow(
              icon: Icons.alternate_email_rounded,
              label: 'Handle',
              value: '@trimmydemo',
              onTap: onContinue,
            ),
            _SettingsRow(
              icon: Icons.face_rounded,
              label: 'Persona',
              value: 'The Oracle',
              onTap: onContinue,
            ),
            _SettingsRow(
              icon: Icons.login_rounded,
              label: 'Sign-in methods',
              value: 'X • email',
              onTap: onContinue,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsGroup(
          title: 'EXPERIENCE',
          rows: [
            _SettingsRow(
              icon: Icons.notifications_none_rounded,
              label: 'Notifications',
              value: '6 on',
              onTap: onContinue,
            ),
            _SettingsRow(
              icon: Icons.graphic_eq_rounded,
              label: 'Sound, haptics and motion',
              value: 'System',
              onTap: onContinue,
            ),
            _SettingsRow(
              icon: Icons.language_rounded,
              label: 'Language',
              value: 'English',
              onTap: onContinue,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsGroup(
          title: 'YOUR DESKS',
          rows: [
            _SettingsRow(
              icon: Icons.description_outlined,
              label: 'Paper desk',
              value: '10,000 limit',
              onTap: onContinue,
            ),
            _SettingsRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Money and wallet',
              value: 'Preview',
              onTap: onContinue,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsGroup(
          title: 'PRIVACY AND HELP',
          rows: [
            _SettingsRow(
              icon: Icons.visibility_outlined,
              label: 'Who sees my reasons',
              value: 'Nobody',
              onTap: onContinue,
            ),
            _SettingsRow(
              icon: Icons.help_outline_rounded,
              label: 'Support and legal',
              onTap: onContinue,
            ),
            _SettingsRow(
              icon: Icons.person_off_outlined,
              label: 'Close account',
              danger: true,
              onTap: onContinue,
            ),
          ],
        ),
      ],
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.rows});
  final String title;
  final List<Widget> rows;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: UiReviewColor.ink.withValues(alpha: .55),
          fontSize: 10,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 7),
      Material(
        color: Colors.white,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(23),
          side: BorderSide(color: UiReviewColor.ink.withValues(alpha: .12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i != rows.length - 1) const Divider(height: 1, indent: 56),
            ],
          ],
        ),
      ),
    ],
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      icon,
      color: danger ? const Color(0xFFB73549) : UiReviewColor.ink,
    ),
    title: Text(
      label,
      style: TextStyle(
        color: danger ? const Color(0xFFB73549) : UiReviewColor.ink,
        fontWeight: FontWeight.w700,
      ),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != null)
          Text(
            value!,
            style: TextStyle(
              color: UiReviewColor.ink.withValues(alpha: .52),
              fontSize: 11,
            ),
          ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
    onTap: onTap,
  );
}

enum ReviewPreferencesKind { notifications, experience, privacy }

class ReviewPreferencesPage extends StatefulWidget {
  const ReviewPreferencesPage({
    super.key,
    required this.kind,
    required this.onBack,
    required this.onContinue,
  });
  final ReviewPreferencesKind kind;
  final VoidCallback onBack, onContinue;
  @override
  State<ReviewPreferencesPage> createState() => _ReviewPreferencesPageState();
}

class _ReviewPreferencesPageState extends State<ReviewPreferencesPage> {
  final values = <String, bool>{};
  String privacy = 'Nobody';

  @override
  void initState() {
    super.initState();
    ReviewFeedback.shared.addListener(_feedbackChanged);
    ReviewFeedback.shared.load();
  }

  void _feedbackChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ReviewFeedback.shared.removeListener(_feedbackChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = widget.kind == ReviewPreferencesKind.notifications;
    final experience = widget.kind == ReviewPreferencesKind.experience;
    final title = notifications
        ? 'Notifications'
        : experience
        ? 'Sound and motion'
        : 'Who sees your activity?';
    final subtitle = notifications
        ? 'Choose which moments can interrupt you.'
        : experience
        ? 'Trimmy follows your phone by default.'
        : 'Reasons and holdings can have different audiences later. This setting controls reasons.';
    return ReviewPageScaffold(
      title: title,
      subtitle: subtitle,
      onBack: widget.onBack,
      bottom: ReviewPrimaryButton(
        label: 'Save changes',
        onPressed: widget.onContinue,
      ),
      child: notifications
          ? _toggleList(const [
              'Wall Street open',
              'Wall Street close',
              'Streak reminder',
              'Mission ready',
              'Live events',
              'Price alerts',
              'League result',
              'Friend activity',
              'Trade receipts',
            ])
          : experience
          ? Column(
              children: [
                _toggleList(const [
                  'Sound',
                  'Haptics',
                  'Animations',
                  'Use system reduce motion',
                ]),
                const SizedBox(height: 18),
                Text(
                  'Sound level · ${(ReviewFeedback.shared.volume * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: ReviewFeedback.shared.volume,
                  max: .4,
                  divisions: 8,
                  label: '${(ReviewFeedback.shared.volume * 100).round()}%',
                  onChanged: ReviewFeedback.shared.sound
                      ? (value) => ReviewFeedback.shared.setVolume(value)
                      : null,
                  onChangeEnd: (_) => ReviewFeedback.shared.press(),
                ),
              ],
            )
          : Column(
              children: [
                for (final option in const [
                  'Friends',
                  'Everyone',
                  'Nobody',
                ]) ...[
                  ReviewChoice(
                    title: option,
                    subtitle: option == 'Friends'
                        ? 'Only confirmed friends'
                        : option == 'Everyone'
                        ? 'Anyone on the floor'
                        : 'Only you',
                    selected: privacy == option,
                    onTap: () => setState(() => privacy = option),
                    color: UiReviewColor.mint,
                  ),
                  if (option != 'Nobody') const SizedBox(height: 10),
                ],
                const SizedBox(height: 22),
                const ReviewPreviewNotice(
                  text:
                      'Changing this never publishes old reasons without the server confirming the new setting.',
                ),
              ],
            ),
    );
  }

  Widget _toggleList(List<String> labels) => Column(
    children: [
      for (var index = 0; index < labels.length; index++) ...[
        Container(
          padding: const EdgeInsets.fromLTRB(15, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: UiReviewColor.ink.withValues(alpha: .12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  labels[index],
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Switch(
                value: labels[index] == 'Sound'
                    ? ReviewFeedback.shared.sound
                    : labels[index] == 'Haptics'
                    ? ReviewFeedback.shared.haptics
                    : values[labels[index]] ?? index < 6,
                onChanged: (value) {
                  if (labels[index] == 'Sound') {
                    ReviewFeedback.shared.setSound(value);
                  } else if (labels[index] == 'Haptics') {
                    ReviewFeedback.shared.setHaptics(value);
                  } else {
                    setState(() => values[labels[index]] = value);
                  }
                },
                activeTrackColor: UiReviewColor.pine,
                activeThumbColor: Colors.white,
              ),
            ],
          ),
        ),
        if (index != labels.length - 1) const SizedBox(height: 8),
      ],
      if (widget.kind == ReviewPreferencesKind.notifications) ...[
        const SizedBox(height: 22),
        const ReviewPaper(
          shadow: false,
          color: UiReviewColor.lilac,
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quiet hours',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text('10:00 PM to 7:00 AM', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              Text(
                'OFF',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class ReviewReportBlockPage extends StatefulWidget {
  const ReviewReportBlockPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });
  final VoidCallback onBack, onContinue;
  @override
  State<ReviewReportBlockPage> createState() => _ReviewReportBlockPageState();
}

class _ReviewReportBlockPageState extends State<ReviewReportBlockPage> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: '@marketmax',
    title: 'Report this reason',
    subtitle:
        'Choose the closest problem. Reports do not tell the author who sent them.',
    onBack: widget.onBack,
    bottom: ReviewPrimaryButton(
      label: 'Send report',
      onPressed: widget.onContinue,
      background: const Color(0xFFB73549),
    ),
    child: Column(
      children: [
        for (
          var i = 0;
          i <
              const [
                'Spam or promotion',
                'Harassment',
                'Dangerous financial claim',
                'Private information',
              ].length;
          i++
        ) ...[
          ReviewChoice(
            title: const [
              'Spam or promotion',
              'Harassment',
              'Dangerous financial claim',
              'Private information',
            ][i],
            selected: selected == i,
            onTap: () => setState(() => selected = i),
            color: const Color(0xFFF8E1E5),
          ),
          if (i != 3) const SizedBox(height: 9),
        ],
        const SizedBox(height: 22),
        ReviewPaper(
          shadow: false,
          color: const Color(0xFFF8E1E5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BLOCK @MARKETMAX',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              const Text(
                'You will stop seeing each other. Friendship and eligible invitations are removed.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: widget.onContinue,
                child: const Text('Block account'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ReviewPaperResetPage extends StatelessWidget {
  const ReviewPaperResetPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });
  final VoidCallback onBack, onContinue;
  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Paper desk',
    title: 'Start a fresh paper cycle?',
    subtitle:
        'Your current holdings disappear from the active desk. Career progress, Trims, streak and history stay.',
    onBack: onBack,
    background: const Color(0xFFF8E1E5),
    bottom: ReviewPrimaryButton(
      label: 'Reset paper desk',
      onPressed: onContinue,
      background: const Color(0xFFB73549),
    ),
    child: Column(
      children: [
        const ReviewSalMessage(
          mood: 'warning',
          message: 'This is a clean desk, not a time machine.',
          background: UiReviewColor.paper,
        ),
        const SizedBox(height: 19),
        const ReviewPaper(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AFTER RESET',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 9),
              _ResetFact(
                icon: Icons.description_outlined,
                text: '10,000 paper cash',
              ),
              _ResetFact(
                icon: Icons.history_rounded,
                text: 'Old trades remain in history',
              ),
              _ResetFact(
                icon: Icons.workspace_premium_outlined,
                text: '50 Trims and Rookie rank stay',
              ),
              _ResetFact(
                icon: Icons.delete_outline_rounded,
                text: 'Current Apple position leaves the active desk',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          initialValue: 'RESET PAPER',
          decoration: InputDecoration(
            labelText: 'Type RESET PAPER',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ],
    ),
  );
}

class _ResetFact extends StatelessWidget {
  const _ResetFact({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

enum ReviewMoneyStep {
  introduction,
  eligibility,
  depositMethod,
  depositAmount,
  depositReview,
  depositReceipt,
  tradeAmount,
  tradeReview,
  signing,
  pending,
  tradeReceipt,
  withdrawAmount,
  withdrawAccount,
  withdrawReview,
  withdrawReceipt,
}

class ReviewMoneyPage extends StatelessWidget {
  const ReviewMoneyPage({
    super.key,
    required this.step,
    required this.onBack,
    required this.onContinue,
  });
  final ReviewMoneyStep step;
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) {
    final (eyebrow, title, subtitle) = switch (step) {
      ReviewMoneyStep.introduction => (
        'Money desk preview',
        'Practice first. Add money when ready.',
        'Money is a separate desk with country checks, clear fees and one risk lesson.',
      ),
      ReviewMoneyStep.eligibility => (
        'Country and risk',
        'Before money moves.',
        'Confirm where you live and understand what a tokenized stock is.',
      ),
      ReviewMoneyStep.depositMethod => (
        'Add money • step 1',
        'How should money arrive?',
        'Available methods depend on your country and partner.',
      ),
      ReviewMoneyStep.depositAmount => (
        'Add money • step 2',
        'Choose an amount.',
        'The fee and amount that lands update before review.',
      ),
      ReviewMoneyStep.depositReview => (
        'Add money • review',
        'Check every number.',
        'The partner performs the exchange and identity check.',
      ),
      ReviewMoneyStep.depositReceipt => (
        'Add money • receipt',
        'Money reached your desk.',
        'The final receipt stays in Inbox and email.',
      ),
      ReviewMoneyStep.tradeAmount => (
        'Money order • AAPLx',
        'Choose your investment.',
        'This uses the money desk and the verified stock token shown below.',
      ),
      ReviewMoneyStep.tradeReview => (
        'Money order • review',
        'Check the stock and token.',
        'One confirmation authorizes this exact order.',
      ),
      ReviewMoneyStep.signing => (
        'Money order • signing',
        'Approve this order.',
        'Your wallet signs the reviewed transaction in the background.',
      ),
      ReviewMoneyStep.pending => (
        'Money order • pending',
        'Waiting for confirmation.',
        'Keep this receipt open. Trimmy will recover an unknown outcome safely.',
      ),
      ReviewMoneyStep.tradeReceipt => (
        'Money order • receipt',
        'Your order is confirmed.',
        'Apple now appears on your money desk.',
      ),
      ReviewMoneyStep.withdrawAmount => (
        'Withdraw • step 1',
        'How much should leave?',
        'Choose an amount from your available money balance.',
      ),
      ReviewMoneyStep.withdrawAccount => (
        'Withdraw • step 2',
        'Where should it go?',
        'Choose a verified saved bank account.',
      ),
      ReviewMoneyStep.withdrawReview => (
        'Withdraw • review',
        'Check what arrives.',
        'The fee and destination are final before confirmation.',
      ),
      ReviewMoneyStep.withdrawReceipt => (
        'Withdraw • receipt',
        'Withdrawal requested.',
        'The partner will update this receipt when the bank settles it.',
      ),
    };
    return ReviewPageScaffold(
      eyebrow: eyebrow,
      title: title,
      subtitle: subtitle,
      onBack: onBack,
      background: _moneyBackground,
      bottom: ReviewPrimaryButton(
        label: _actionLabel,
        onPressed: onContinue,
        background: _actionColor,
        foreground: _actionColor == UiReviewColor.lemon
            ? UiReviewColor.ink
            : Colors.white,
      ),
      child: Column(
        children: [
          const ReviewPreviewNotice(),
          const SizedBox(height: 22),
          _content(),
        ],
      ),
    );
  }

  Color get _moneyBackground => switch (step) {
    ReviewMoneyStep.introduction ||
    ReviewMoneyStep.eligibility => UiReviewColor.lilac,
    ReviewMoneyStep.depositReceipt ||
    ReviewMoneyStep.tradeReceipt ||
    ReviewMoneyStep.withdrawReceipt => UiReviewColor.mint,
    ReviewMoneyStep.pending || ReviewMoneyStep.signing => UiReviewColor.lemon,
    _ => UiReviewColor.paper,
  };

  Color get _actionColor => step == ReviewMoneyStep.introduction
      ? UiReviewColor.ink
      : step == ReviewMoneyStep.pending
      ? UiReviewColor.lemon
      : UiReviewColor.pine;

  String get _actionLabel => switch (step) {
    ReviewMoneyStep.introduction => 'Check eligibility',
    ReviewMoneyStep.eligibility => 'I understand • Continue',
    ReviewMoneyStep.depositMethod => 'Use bank transfer',
    ReviewMoneyStep.depositAmount => 'Review deposit',
    ReviewMoneyStep.depositReview => 'Confirm deposit',
    ReviewMoneyStep.depositReceipt => 'Open money desk',
    ReviewMoneyStep.tradeAmount => 'Review order',
    ReviewMoneyStep.tradeReview => 'Confirm money order',
    ReviewMoneyStep.signing => 'Approve in wallet',
    ReviewMoneyStep.pending => 'Check status',
    ReviewMoneyStep.tradeReceipt => 'Done',
    ReviewMoneyStep.withdrawAmount => 'Choose bank account',
    ReviewMoneyStep.withdrawAccount => 'Review withdrawal',
    ReviewMoneyStep.withdrawReview => 'Confirm withdrawal',
    ReviewMoneyStep.withdrawReceipt => 'Done',
  };

  Widget _content() => switch (step) {
    ReviewMoneyStep.introduction => const Column(
      children: [
        ReviewSal(mood: 'teaching', width: 190),
        SizedBox(height: 14),
        ReviewPaper(
          shadow: false,
          child: Column(
            children: [
              _MoneyFact(
                icon: Icons.school_rounded,
                title: 'Practice stays available',
                body: 'Your paper desk never requires a deposit.',
              ),
              Divider(height: 26),
              _MoneyFact(
                icon: Icons.public_rounded,
                title: 'Country comes first',
                body: 'Eligibility and partner terms decide what is available.',
              ),
              Divider(height: 26),
              _MoneyFact(
                icon: Icons.receipt_long_rounded,
                title: 'Every step has a receipt',
                body: 'Fees, stock token and status remain visible.',
              ),
            ],
          ),
        ),
      ],
    ),
    ReviewMoneyStep.eligibility => const Column(
      children: [
        ReviewPaper(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'COUNTRY',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('NG')),
                title: Text(
                  'Nigeria',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Availability must be confirmed by the selected partner',
                ),
                trailing: Icon(Icons.expand_more_rounded),
              ),
            ],
          ),
        ),
        SizedBox(height: 14),
        ReviewPaper(
          shadow: false,
          color: UiReviewColor.lemon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ONE RISK LESSON',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'A tokenized stock follows an asset through an issuer. It may not give voting rights, and its on-chain price can differ when Wall Street is closed.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    ReviewMoneyStep.depositMethod => const Column(
      children: [
        _MoneyChoice(
          icon: Icons.account_balance_rounded,
          title: 'Bank transfer',
          detail: 'Usually lowest fee • 1 to 2 business days',
          selected: true,
        ),
        SizedBox(height: 10),
        _MoneyChoice(
          icon: Icons.credit_card_rounded,
          title: 'Card',
          detail: 'Faster • partner fee applies',
        ),
        SizedBox(height: 10),
        _MoneyChoice(
          icon: Icons.open_in_new_rounded,
          title: 'From another app',
          detail: 'Availability depends on partner',
        ),
      ],
    ),
    ReviewMoneyStep.depositAmount => const Column(
      children: [
        _MoneyAmount(amount: '50,000', currency: '₦ NGN'),
        SizedBox(height: 18),
        ReviewPaper(
          shadow: false,
          child: Column(
            children: [
              _MoneyRow(label: 'Partner fee', value: '750 NGN'),
              SizedBox(height: 11),
              _MoneyRow(label: 'Exchange rate', value: 'Partner quote'),
              SizedBox(height: 11),
              _MoneyRow(label: 'Estimated desk credit', value: '49,250 NGN'),
            ],
          ),
        ),
      ],
    ),
    ReviewMoneyStep.depositReview => const _MoneyReceipt(
      title: 'ADD MONEY',
      rows: [
        ('Method', 'Bank transfer'),
        ('Amount', '50,000 NGN'),
        ('Partner fee', '750 NGN'),
        ('What lands', '49,250 NGN'),
        ('Partner', 'To be selected'),
      ],
    ),
    ReviewMoneyStep.depositReceipt => const _MoneyReceipt(
      title: 'RECEIPT • CONFIRMED',
      rows: [
        ('Money desk', '49,250 NGN'),
        ('Method', 'Bank transfer'),
        ('Fee', '750 NGN'),
        ('Reference', 'TRM-24092026'),
      ],
      success: true,
    ),
    ReviewMoneyStep.tradeAmount => const Column(
      children: [
        _MoneyAmount(amount: '10,000', currency: '₦ NGN'),
        SizedBox(height: 18),
        ReviewPaper(
          shadow: false,
          child: Column(
            children: [
              _MoneyRow(label: 'Stock', value: 'Apple'),
              SizedBox(height: 11),
              _MoneyRow(label: 'Token', value: 'AAPLx'),
              SizedBox(height: 11),
              _MoneyRow(label: 'Estimated shares', value: '0.0184'),
              SizedBox(height: 11),
              _MoneyRow(label: 'Available', value: '49,250 NGN'),
            ],
          ),
        ),
      ],
    ),
    ReviewMoneyStep.tradeReview => const _MoneyReceipt(
      title: 'MONEY ORDER',
      rows: [
        ('Company', 'Apple'),
        ('Stock token', 'AAPLx'),
        ('Issuer', 'Verified issuer'),
        ('On-chain price', '333.82 USD'),
        ('Amount', '10,000 NGN'),
        ('Fee', 'Shown by provider'),
      ],
    ),
    ReviewMoneyStep.signing => const Column(
      children: [
        SizedBox(height: 24),
        Icon(Icons.fingerprint_rounded, size: 120, color: UiReviewColor.violet),
        SizedBox(height: 20),
        Text(
          'One exact order',
          style: TextStyle(
            fontFamily: reviewDisplay,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '10,000 NGN of Apple • AAPLx',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 24),
        ReviewPaper(
          shadow: false,
          child: Text(
            'Your wallet approves only the transaction shown on the reviewed receipt.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.4, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
    ReviewMoneyStep.pending => const Column(
      children: [
        SizedBox(height: 20),
        CircularProgressIndicator(color: UiReviewColor.ink),
        SizedBox(height: 24),
        Text(
          'Submitted on Solana',
          style: TextStyle(
            fontFamily: reviewDisplay,
            fontSize: 27,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Trimmy is checking the final chain status.',
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 22),
        ReviewPaper(
          shadow: false,
          child: Column(
            children: [
              _MoneyRow(label: 'Order', value: '10,000 NGN AAPLx'),
              SizedBox(height: 10),
              _MoneyRow(label: 'Status', value: 'Pending'),
              SizedBox(height: 10),
              _MoneyRow(label: 'Reference', value: 'TRM-AAPL-01'),
            ],
          ),
        ),
      ],
    ),
    ReviewMoneyStep.tradeReceipt => const _MoneyReceipt(
      title: 'ORDER • CONFIRMED',
      rows: [
        ('Stock', 'Apple • AAPLx'),
        ('Amount', '10,000 NGN'),
        ('Shares', '0.0184'),
        ('Network fee', 'Sponsored'),
        ('Status', 'Confirmed'),
      ],
      success: true,
    ),
    ReviewMoneyStep.withdrawAmount => const Column(
      children: [
        _MoneyAmount(amount: '20,000', currency: '₦ NGN'),
        SizedBox(height: 18),
        ReviewPaper(
          shadow: false,
          child: Column(
            children: [
              _MoneyRow(label: 'Available', value: '39,250 NGN'),
              SizedBox(height: 11),
              _MoneyRow(label: 'Estimated fee', value: '500 NGN'),
              SizedBox(height: 11),
              _MoneyRow(label: 'What arrives', value: '19,500 NGN'),
            ],
          ),
        ),
      ],
    ),
    ReviewMoneyStep.withdrawAccount => const Column(
      children: [
        _MoneyChoice(
          icon: Icons.account_balance_rounded,
          title: 'GTBank • 0123',
          detail: 'Joel A. • verified',
          selected: true,
        ),
        SizedBox(height: 10),
        _MoneyChoice(
          icon: Icons.add_rounded,
          title: 'Add bank account',
          detail: 'Verified by the selected partner',
        ),
      ],
    ),
    ReviewMoneyStep.withdrawReview => const _MoneyReceipt(
      title: 'WITHDRAWAL',
      rows: [
        ('Amount', '20,000 NGN'),
        ('Bank', 'GTBank • 0123'),
        ('Fee', '500 NGN'),
        ('What arrives', '19,500 NGN'),
        ('Timing', 'Partner estimate'),
      ],
    ),
    ReviewMoneyStep.withdrawReceipt => const _MoneyReceipt(
      title: 'WITHDRAWAL • REQUESTED',
      rows: [
        ('Amount', '20,000 NGN'),
        ('Destination', 'GTBank • 0123'),
        ('Status', 'Processing'),
        ('Reference', 'TRM-WD-01'),
      ],
      success: true,
    ),
  };
}

class _MoneyFact extends StatelessWidget {
  const _MoneyFact({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title, body;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(fontSize: 12, height: 1.35)),
          ],
        ),
      ),
    ],
  );
}

class _MoneyChoice extends StatelessWidget {
  const _MoneyChoice({
    required this.icon,
    required this.title,
    required this.detail,
    this.selected = false,
  });
  final IconData icon;
  final String title, detail;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: selected ? UiReviewColor.mint : Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: UiReviewColor.ink, width: selected ? 1.8 : 1),
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: UiReviewColor.ink,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(detail, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        if (selected)
          const Icon(Icons.check_circle_rounded, color: UiReviewColor.pine),
      ],
    ),
  );
}

class _MoneyAmount extends StatelessWidget {
  const _MoneyAmount({required this.amount, required this.currency});
  final String amount, currency;
  @override
  Widget build(BuildContext context) => ReviewPaper(
    shadow: false,
    color: UiReviewColor.lilac,
    child: Column(
      children: [
        Text(
          amount,
          style: const TextStyle(
            fontFamily: reviewDisplay,
            fontSize: 54,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          currency,
          style: const TextStyle(letterSpacing: 1, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        const Row(
          children: [
            Expanded(
              child: Text(
                '10,000',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: Text(
                '25,000',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: Text(
                '50,000',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: Text(
                'MAX',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MoneyReceipt extends StatelessWidget {
  const _MoneyReceipt({
    required this.title,
    required this.rows,
    this.success = false,
  });
  final String title;
  final List<(String, String)> rows;
  final bool success;
  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -.01,
    child: ReviewPaper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (success)
            const Center(
              child: Icon(
                Icons.check_circle_rounded,
                size: 62,
                color: UiReviewColor.pine,
              ),
            ),
          if (success) const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < rows.length; i++) ...[
            _MoneyRow(label: rows[i].$1, value: rows[i].$2),
            if (i != rows.length - 1) const SizedBox(height: 13),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 17),
            child: Divider(),
          ),
          const Text(
            'UI PREVIEW • PARTNER AND LIVE AVAILABILITY NOT SELECTED',
            style: TextStyle(
              fontSize: 9,
              height: 1.3,
              letterSpacing: .6,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            color: UiReviewColor.ink.withValues(alpha: .62),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class ReviewWalletPage extends StatelessWidget {
  const ReviewWalletPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });
  final VoidCallback onBack, onContinue;
  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'For people who want the details',
    title: 'Wallet tools',
    subtitle: 'Everyday trading keeps chain details in the background.',
    onBack: onBack,
    bottom: ReviewPrimaryButton(
      label: 'Check wallet possession',
      onPressed: onContinue,
    ),
    child: Column(
      children: [
        const ReviewPaper(
          shadow: false,
          color: UiReviewColor.lilac,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WALLET ADDRESS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '8jLm...42Qp',
                style: TextStyle(
                  fontFamily: reviewDisplay,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text('Created for your signed-in Trimmy account'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsGroup(
          title: 'TOOLS',
          rows: [
            _SettingsRow(
              icon: Icons.copy_rounded,
              label: 'Copy address',
              onTap: onContinue,
            ),
            _SettingsRow(
              icon: Icons.verified_user_outlined,
              label: 'Check wallet',
              value: 'Verified',
              onTap: onContinue,
            ),
            _SettingsRow(
              icon: Icons.file_download_outlined,
              label: 'Export instructions',
              onTap: onContinue,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const ReviewPreviewNotice(
          text:
              'Never paste a recovery phrase into Trimmy. Export steps open only through the wallet provider.',
        ),
      ],
    ),
  );
}

class ReviewSupportPage extends StatelessWidget {
  const ReviewSupportPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });
  final VoidCallback onBack, onContinue;
  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    title: 'Support and legal',
    subtitle: 'Help, disclosures and the rules behind the product.',
    onBack: onBack,
    child: _SettingsGroup(
      title: 'HELP',
      rows: [
        _SettingsRow(
          icon: Icons.help_outline_rounded,
          label: 'Help centre',
          onTap: onContinue,
        ),
        _SettingsRow(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Send feedback',
          onTap: onContinue,
        ),
        _SettingsRow(
          icon: Icons.bug_report_outlined,
          label: 'Report a bug',
          onTap: onContinue,
        ),
        _SettingsRow(
          icon: Icons.description_outlined,
          label: 'Terms',
          onTap: onContinue,
        ),
        _SettingsRow(
          icon: Icons.privacy_tip_outlined,
          label: 'Privacy',
          onTap: onContinue,
        ),
        _SettingsRow(
          icon: Icons.warning_amber_rounded,
          label: 'Risk disclosure',
          onTap: onContinue,
        ),
        _SettingsRow(
          icon: Icons.token_outlined,
          label: 'How tokenized stocks work',
          onTap: onContinue,
        ),
      ],
    ),
  );
}

class ReviewCloseAccountPage extends StatelessWidget {
  const ReviewCloseAccountPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });
  final VoidCallback onBack, onContinue;
  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Account access',
    title: 'Close your account?',
    subtitle:
        'You lose access to the saved account. Records that must be retained remain protected.',
    onBack: onBack,
    background: const Color(0xFFF8E1E5),
    bottom: ReviewPrimaryButton(
      label: 'Close account',
      onPressed: onContinue,
      background: const Color(0xFFB73549),
    ),
    child: Column(
      children: [
        const ReviewSal(mood: 'warning', width: 180),
        const SizedBox(height: 16),
        const ReviewPaper(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THIS ACTION',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 9),
              _ResetFact(
                icon: Icons.logout_rounded,
                text: 'Signs this account out everywhere',
              ),
              _ResetFact(
                icon: Icons.lock_outline_rounded,
                text: 'Locks access to its saved desks',
              ),
              _ResetFact(
                icon: Icons.receipt_long_outlined,
                text: 'Keeps records required for safety and law',
              ),
              _ResetFact(
                icon: Icons.undo_rounded,
                text: 'Cannot be undone in the app',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          initialValue: 'CLOSE ACCOUNT',
          decoration: InputDecoration(
            labelText: 'Type CLOSE ACCOUNT',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ],
    ),
  );
}
