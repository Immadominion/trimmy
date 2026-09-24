import 'package:flutter/material.dart';

import '../product/account/sign_in_methods_page.dart';

import 'review_components.dart';
import 'review_followup_questions.dart';
import 'ui_review_app.dart';

/// These optional destinations belong to the isolated UI review. They never
/// impersonate a completed authentication, permission grant or widget install.
void showReviewSetupNotice(BuildContext context, String action) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              action,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'This is a UI preview. No account has been connected and no phone settings have been changed.',
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 20),
            ReviewPrimaryButton(
              label: 'Got it',
              background: UiReviewColor.violet,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    ),
  );
}

class ReviewAccountOptionsPage extends StatelessWidget {
  const ReviewAccountOptionsPage({
    super.key,
    required this.onClose,
    this.username,
    this.signIn = false,
  });
  final VoidCallback onClose;
  final String? username;
  final bool signIn;

  @override
  Widget build(BuildContext context) => signIn
      ? SignInMethodsPage(
          onClose: onClose,
          onEmail: () =>
              showReviewSetupNotice(context, 'email sign-in preview'),
          onGoogle: () =>
              showReviewSetupNotice(context, 'Google sign-in preview'),
          onX: () => showReviewSetupNotice(context, 'X sign-in preview'),
          onApple: () =>
              showReviewSetupNotice(context, 'Apple sign-in preview'),
        )
      : ReviewQuestionFrame(
          title: 'Keep your career with you.',
          caption: 'Save your progress and pick it up on another phone.',
          skipLabel: 'Close account setup',
          onSkip: onClose,
          onContinue: onClose,
          continueLabel: 'Back to my desk',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (username != null && username!.isNotEmpty) ...[
                Text(
                  '@$username',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
              ],
              for (final method in const [
                ('Apple', Icons.apple_rounded),
                ('Google', Icons.g_mobiledata_rounded),
                ('X', Icons.alternate_email_rounded),
                ('email', Icons.mail_outline_rounded),
              ]) ...[
                _SetupAction(
                  key: ValueKey('save-${method.$1}'),
                  label: 'Continue with ${method.$1}',
                  icon: method.$2,
                  onTap: () => showReviewSetupNotice(
                    context,
                    '${method.$1} sign-in preview',
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 14),
              const Text(
                'UI preview • Sign-in is not connected here.',
                style: TextStyle(color: Color(0xFF797585), fontSize: 13),
              ),
            ],
          ),
        );
}

class ReviewReminderInvitation extends StatelessWidget {
  const ReviewReminderInvitation({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ReviewQuestionFrame(
    title: 'See you tomorrow?',
    caption:
        'A little nudge to learn or check in. You never need to trade to keep a streak.',
    skipLabel: 'Close reminder setup',
    onSkip: onClose,
    onContinue: () =>
        showReviewSetupNotice(context, 'Notification permission preview'),
    continueLabel: 'Allow notifications',
    secondaryLabel: 'Not now',
    child: Column(
      children: [
        const ReviewSal(mood: 'teaching', width: 174),
        const SizedBox(height: 22),
        _SoftPanel(
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TRIMMY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: UiReviewColor.violet,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Your next move is waiting.',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 7),
              Text(
                'Take a moment for your career.',
                style: TextStyle(height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Reminder preview. This review build does not send notifications.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF797585), fontSize: 13, height: 1.4),
        ),
      ],
    ),
  );
}

class ReviewWidgetInvitation extends StatelessWidget {
  const ReviewWidgetInvitation({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => ReviewQuestionFrame(
    title: 'A little Trimmy at home.',
    caption: 'Keep your next activity in sight.',
    skipLabel: 'Close widget preview',
    onSkip: onClose,
    onContinue: onClose,
    continueLabel: 'Back to my desk',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SoftPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your next move',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'A moment for your career.',
                style: TextStyle(fontSize: 15),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: const ReviewSal(mood: 'proud', width: 176),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        const Text(
          'Widget preview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Home screen widgets are not available in this review build yet.',
          style: TextStyle(color: Color(0xFF797585), height: 1.45),
        ),
      ],
    ),
  );
}

class _SoftPanel extends StatelessWidget {
  const _SoftPanel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: ShapeDecoration(
      color: const Color(0xFFF2EEFF),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(30)),
    ),
    child: child,
  );
}

class _SetupAction extends StatelessWidget {
  const _SetupAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF7F8FA),
    shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(22)),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
