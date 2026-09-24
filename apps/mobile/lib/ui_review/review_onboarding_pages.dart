import 'dart:async';

import 'package:flutter/material.dart';

import 'review_components.dart';
import 'ui_review_app.dart';

class ReviewQuestionPage extends StatefulWidget {
  const ReviewQuestionPage({
    super.key,
    required this.onBack,
    required this.onContinue,
    this.onSkip,
  });

  final VoidCallback onBack, onContinue;
  final VoidCallback? onSkip;

  @override
  State<ReviewQuestionPage> createState() => _ReviewQuestionPageState();
}

class _ReviewQuestionPageState extends State<ReviewQuestionPage> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => _buildGoal(context);

  Widget _buildGoal(BuildContext context) {
    const choices = [
      ('Learn', 'Start from the basics', 'book'),
      ('Practice', 'Get comfortable before trading', 'goal'),
      ('Trade', 'Make sharper stock decisions', 'chart'),
      ('Beat my friends', 'Play the weekly league', 'friends'),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: widget.onSkip ?? widget.onBack,
                          tooltip: 'Skip questions',
                          icon: const Icon(Icons.close_rounded, size: 27),
                          color: UiReviewColor.ink,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          '1',
                          style: TextStyle(
                            fontFamily: 'Dejanire Sans',
                            color: UiReviewColor.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 9),
                        SizedBox(
                          width: 67,
                          child: ReviewProgress(value: 1 / 4),
                        ),
                        const SizedBox(width: 9),
                        const Text(
                          '4',
                          style: TextStyle(
                            fontFamily: 'Dejanire Sans',
                            color: Color(0xFF898592),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Why are you here?',
                      style: TextStyle(
                        fontFamily: reviewDisplay,
                        color: UiReviewColor.ink,
                        fontSize: 36,
                        height: 1.04,
                        letterSpacing: -1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Row(
                      children: [
                        ReviewSal(width: 58),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No answer is wrong.',
                            style: TextStyle(
                              fontFamily: 'Dejanire Sans',
                              color: Color(0xFF666172),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    for (var index = 0; index < choices.length; index++) ...[
                      _GoalChoice(
                        title: choices[index].$1,
                        subtitle: choices[index].$2,
                        iconName: choices[index].$3,
                        index: index,
                        selected: selected == index,
                        onTap: () => setState(() => selected = index),
                      ),
                      if (index != choices.length - 1)
                        const SizedBox(height: 11),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(22, 9, 22, 12),
              child: ReviewPrimaryButton(
                label: 'Continue',
                background: UiReviewColor.violet,
                onPressed: widget.onContinue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalChoice extends StatelessWidget {
  const _GoalChoice({
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final String title, subtitle, iconName;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? const Color(0xFFF0EDFF) : const Color(0xFFF7F8FA),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      animationDuration: uiReviewDuration(context, 180),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                _GoalAnimatedIcon(
                  key: ValueKey('goal-icon-$index'),
                  name: iconName,
                  delay: Duration(milliseconds: index * 100),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Dejanire Sans',
                          color: UiReviewColor.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontFamily: 'Dejanire Sans',
                          color: Color(0xFF797585),
                          fontSize: 12.5,
                          height: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_rounded,
                    size: 23,
                    color: UiReviewColor.violet,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _GoalAnimatedIcon extends StatefulWidget {
  const _GoalAnimatedIcon({super.key, required this.name, required this.delay});

  final String name;
  final Duration delay;

  @override
  State<_GoalAnimatedIcon> createState() => _GoalAnimatedIconState();
}

class _GoalAnimatedIconState extends State<_GoalAnimatedIcon> {
  Timer? startTimer, stopTimer;
  bool playing = false;

  @override
  void initState() {
    super.initState();
    startTimer = Timer(widget.delay, () {
      if (!mounted) return;
      setState(() => playing = true);
      stopTimer = Timer(const Duration(milliseconds: 1170), () {
        if (mounted) setState(() => playing = false);
      });
    });
  }

  @override
  void dispose() {
    startTimer?.cancel();
    stopTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    final extension = playing && !reducedMotion ? 'gif' : 'png';
    return ExcludeSemantics(
      child: Image.asset(
        'assets/images/ui_review/icons8/goal-${widget.name}-animated.$extension',
        width: 48,
        height: 48,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class ReviewNotificationsPrimerPage extends StatelessWidget {
  const ReviewNotificationsPrimerPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'A nudge from Sal',
    title: 'Keep a little time for stocks.',
    subtitle:
        'Allow notifications for a daily check-in reminder. You can turn it off in Settings.',
    onBack: onBack,
    background: Colors.white,
    bottom: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReviewPrimaryButton(
          label: 'Allow notifications',
          onPressed: onContinue,
        ),
        ReviewTextButton(label: 'Not now', onPressed: onContinue),
      ],
    ),
    child: Column(
      children: [
        const ReviewSalMessage(
          mood: 'teaching',
          message: "One nudge a day. I’ll save you a seat.",
          background: UiReviewColor.paper,
        ),
        const SizedBox(height: 22),
        Transform.rotate(
          angle: .025,
          child: ReviewPaper(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trimmy would like to send you notifications',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'A reminder to learn and check your stocks.',
                  style: TextStyle(
                    color: UiReviewColor.ink.withValues(alpha: .68),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Don’t allow',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Allow',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: UiReviewColor.violet,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
