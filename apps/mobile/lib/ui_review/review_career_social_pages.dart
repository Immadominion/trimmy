import 'package:flutter/material.dart';

import 'review_components.dart';
import 'review_market_pages.dart';
import 'ui_review_app.dart';

class ReviewCareerPage extends StatelessWidget {
  const ReviewCareerPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: UiReviewColor.lilac,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
              children: [
                const Text(
                  'THE FLOOR',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your Career',
                  style: TextStyle(
                    fontFamily: reviewDisplay,
                    fontSize: 37,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                const _FloorSegments(selected: 'Career'),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                  decoration: BoxDecoration(
                    color: UiReviewColor.ink,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Row(
                    children: [
                      CircleAvatar(
                        radius: 29,
                        backgroundColor: UiReviewColor.lemon,
                        child: Icon(
                          Icons.badge_rounded,
                          color: UiReviewColor.ink,
                          size: 30,
                        ),
                      ),
                      SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ROOKIE',
                              style: TextStyle(
                                color: UiReviewColor.lemon,
                                fontSize: 11,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '50 Trims',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: reviewDisplay,
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 8),
                            ReviewProgress(
                              value: 1 / 6,
                              color: UiReviewColor.mint,
                              track: Colors.white24,
                              height: 8,
                            ),
                            SizedBox(height: 5),
                            Text(
                              '250 to Analyst',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ReviewSal(mood: 'deadpan', width: 86),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                const ReviewSectionLabel('Rookie path'),
                const SizedBox(height: 7),
                Text(
                  'Finish the current node to open the next.',
                  style: TextStyle(
                    color: UiReviewColor.ink.withValues(alpha: .65),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 17),
                _CareerPath(onOpen: onContinue),
                const SizedBox(height: 28),
                ReviewSectionLabel(
                  'Lessons',
                  trailing: TextButton(
                    onPressed: onContinue,
                    child: const Text('See all'),
                  ),
                ),
                const SizedBox(height: 10),
                const _LessonStrip(),
                const SizedBox(height: 26),
                const ReviewSectionLabel('Trophies'),
                const SizedBox(height: 10),
                const _TrophyStrip(),
              ],
            ),
          ),
          const ReviewBottomTabs(selected: 'Floor'),
        ],
      ),
    ),
  );
}

class _FloorSegments extends StatelessWidget {
  const _FloorSegments({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: UiReviewColor.ink.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        for (final label in const ['Feed', 'League', 'Career'])
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: label == selected
                    ? UiReviewColor.ink
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: label == selected ? Colors.white : UiReviewColor.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _CareerPath extends StatelessWidget {
  const _CareerPath({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    const nodes = [
      ('Buy your first stock', 'DONE', true),
      ('Write your first reason', 'DONE', true),
      ('Follow 3 companies', '+20 TRIMS', false),
      ('Hold through a red day', 'LOCKED', false),
      ('Promotion review', 'ANALYST', false),
    ];
    return Stack(
      children: [
        Positioned(
          left: 30,
          top: 24,
          bottom: 24,
          width: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: UiReviewColor.ink.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        Column(
          children: [
            for (var index = 0; index < nodes.length; index++) ...[
              Row(
                children: [
                  Container(
                    width: index == 2 ? 66 : 58,
                    height: index == 2 ? 66 : 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: nodes[index].$3
                          ? UiReviewColor.mint
                          : index == 2
                          ? UiReviewColor.lemon
                          : const Color(0xFFD8D1E8),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: UiReviewColor.ink,
                        width: index == 2 ? 2 : 1.2,
                      ),
                    ),
                    child: Icon(
                      nodes[index].$3
                          ? Icons.check_rounded
                          : index == 2
                          ? Icons.play_arrow_rounded
                          : Icons.lock_outline_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      color: index == 2
                          ? UiReviewColor.lemon
                          : UiReviewColor.paper,
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(21),
                        side: BorderSide(
                          color: UiReviewColor.ink.withValues(
                            alpha: index == 2 ? 1 : .14,
                          ),
                          width: index == 2 ? 1.6 : 1,
                        ),
                      ),
                      child: ListTile(
                        onTap: index == 2 ? onOpen : null,
                        title: Text(
                          nodes[index].$1,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          nodes[index].$2,
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: .8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        trailing: index == 2
                            ? const Icon(Icons.arrow_forward_rounded)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              if (index != nodes.length - 1) const SizedBox(height: 14),
            ],
          ],
        ),
      ],
    );
  }
}

class _LessonStrip extends StatelessWidget {
  const _LessonStrip();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 130,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: const [
        _LessonCard(
          number: '01',
          title: 'What is a ticker?',
          color: UiReviewColor.lemon,
          status: '2 MIN',
        ),
        SizedBox(width: 10),
        _LessonCard(
          number: '02',
          title: 'Why prices move',
          color: UiReviewColor.mint,
          status: '2 MIN',
        ),
        SizedBox(width: 10),
        _LessonCard(
          number: '03',
          title: 'Tokenized stocks',
          color: UiReviewColor.pink,
          status: 'LOCKED',
        ),
      ],
    ),
  );
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.number,
    required this.title,
    required this.color,
    required this.status,
  });

  final String number, title, status;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 142,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: UiReviewColor.ink, width: 1.2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: const TextStyle(
            fontFamily: reviewDisplay,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(height: 1.1, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          status,
          style: const TextStyle(
            fontSize: 9,
            letterSpacing: .8,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _TrophyStrip extends StatelessWidget {
  const _TrophyStrip();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisAlignment: MainAxisAlignment.spaceAround,
    children: [
      _Trophy(
        icon: Icons.shopping_bag_rounded,
        label: 'First position',
        earned: true,
      ),
      _Trophy(
        icon: Icons.edit_note_rounded,
        label: 'First reason',
        earned: true,
      ),
      _Trophy(
        icon: Icons.trending_up_rounded,
        label: 'First trim',
        earned: false,
      ),
    ],
  );
}

class _Trophy extends StatelessWidget {
  const _Trophy({
    required this.icon,
    required this.label,
    required this.earned,
  });

  final IconData icon;
  final String label;
  final bool earned;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    child: Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: earned ? UiReviewColor.lemon : const Color(0xFFD8D1C2),
            shape: BoxShape.circle,
            border: Border.all(color: UiReviewColor.ink, width: 1.2),
          ),
          child: Icon(
            icon,
            color: earned
                ? UiReviewColor.ink
                : UiReviewColor.ink.withValues(alpha: .35),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class ReviewLessonLibraryPage extends StatelessWidget {
  const ReviewLessonLibraryPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Career lessons',
    title: 'Two minutes. One idea.',
    subtitle:
        'Lessons are always replayable. A first completion earns 10 Trims.',
    onBack: onBack,
    child: Column(
      children: [
        const ReviewSalMessage(
          mood: 'teaching',
          message: 'Learn the noun before you risk the verb.',
        ),
        const SizedBox(height: 20),
        _LessonLibraryRow(
          number: '01',
          title: 'What is a ticker?',
          detail: '4 taps • ready',
          color: UiReviewColor.lemon,
          onTap: onContinue,
        ),
        const SizedBox(height: 11),
        _LessonLibraryRow(
          number: '02',
          title: 'Why prices move',
          detail: '5 taps • ready',
          color: UiReviewColor.mint,
          onTap: onContinue,
        ),
        const SizedBox(height: 11),
        _LessonLibraryRow(
          number: '03',
          title: 'A stock, on a token',
          detail: '5 taps • next',
          color: UiReviewColor.pink,
          onTap: onContinue,
        ),
        const SizedBox(height: 11),
        _LessonLibraryRow(
          number: '04',
          title: 'What is a red day?',
          detail: '4 taps • locked',
          color: const Color(0xFFD8D1C2),
          onTap: () {},
        ),
        const SizedBox(height: 11),
        _LessonLibraryRow(
          number: '05',
          title: 'Trim, do not panic',
          detail: '6 taps • locked',
          color: const Color(0xFFD8D1C2),
          onTap: () {},
        ),
      ],
    ),
  );
}

class _LessonLibraryRow extends StatelessWidget {
  const _LessonLibraryRow({
    required this.number,
    required this.title,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  final String number, title, detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: UiReviewColor.ink, width: 1.2),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Text(
              number,
              style: const TextStyle(
                fontFamily: reviewDisplay,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded),
          ],
        ),
      ),
    ),
  );
}

class ReviewLessonPlayPage extends StatefulWidget {
  const ReviewLessonPlayPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack, onContinue;

  @override
  State<ReviewLessonPlayPage> createState() => _ReviewLessonPlayPageState();
}

class _ReviewLessonPlayPageState extends State<ReviewLessonPlayPage> {
  int selected = 1;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Ticker • 2 of 4',
    title: 'Which one is the ticker?',
    subtitle: 'A ticker is the short code the market uses for a company.',
    onBack: widget.onBack,
    trailing: const SizedBox(width: 82, child: ReviewProgress(value: .5)),
    bottom: ReviewPrimaryButton(
      label: 'Check answer',
      onPressed: widget.onContinue,
    ),
    child: Column(
      children: [
        const ReviewSalMessage(
          mood: 'teaching',
          message: 'The company has a name. The market likes a shortcut.',
        ),
        const SizedBox(height: 27),
        Transform.rotate(
          angle: -.025,
          child: ReviewPaper(
            color: UiReviewColor.lilac,
            child: const Column(
              children: [
                ReviewCompanyLogo(symbol: 'AAPL', color: UiReviewColor.pink),
                SizedBox(height: 12),
                Text(
                  'APPLE',
                  style: TextStyle(
                    fontFamily: reviewDisplay,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'AAPL',
                  style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        ReviewChoice(
          title: 'Apple',
          subtitle: 'The company name',
          selected: selected == 0,
          onTap: () => setState(() => selected = 0),
        ),
        const SizedBox(height: 11),
        ReviewChoice(
          title: 'AAPL',
          subtitle: 'The ticker',
          selected: selected == 1,
          onTap: () => setState(() => selected = 1),
          color: UiReviewColor.mint,
        ),
      ],
    ),
  );
}

class ReviewLiveEventPage extends StatefulWidget {
  const ReviewLiveEventPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack, onContinue;

  @override
  State<ReviewLiveEventPage> createState() => _ReviewLiveEventPageState();
}

class _ReviewLiveEventPageState extends State<ReviewLiveEventPage> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Live event • Nvidia',
    title: 'Earnings tonight.',
    subtitle: 'You hold Nvidia. What will you do before the report?',
    onBack: widget.onBack,
    background: UiReviewColor.lemon,
    bottom: ReviewPrimaryButton(
      label: 'Save my decision • +10 Trims',
      onPressed: widget.onContinue,
    ),
    child: Column(
      children: [
        const ReviewSalMessage(
          mood: 'skeptical',
          message: 'A decision is yours. The market will ignore your feelings.',
        ),
        const SizedBox(height: 18),
        const ReviewPaper(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THE FACT',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Nvidia reports results after Wall Street closes.',
                style: TextStyle(
                  fontSize: 18,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text('Your position: 300 paper • +4.2%'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (
          var i = 0;
          i < const ['Hold', 'Trim half', 'Sell', 'Ask Sal'].length;
          i++
        ) ...[
          ReviewChoice(
            title: const ['Hold', 'Trim half', 'Sell', 'Ask Sal'][i],
            selected: selected == i,
            onTap: () => setState(() => selected = i),
            color: UiReviewColor.mint,
          ),
          if (i != 3) const SizedBox(height: 9),
        ],
      ],
    ),
  );
}

class ReviewMissionCompletePage extends StatelessWidget {
  const ReviewMissionCompletePage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Mission complete',
    title: 'You followed the evidence.',
    subtitle: 'The path remembers the result once.',
    background: UiReviewColor.mint,
    bottom: ReviewPrimaryButton(
      label: 'Collect 20 Trims',
      onPressed: onContinue,
    ),
    child: Column(
      children: [
        const ReviewSal(mood: 'proud', width: 216),
        const SizedBox(height: 4),
        const Text(
          '+20',
          style: TextStyle(
            fontFamily: reviewDisplay,
            fontSize: 66,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Text(
          'TRIMS',
          style: TextStyle(letterSpacing: 1.4, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 24),
        const ReviewPaper(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ROOKIE PATH',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Follow 3 companies',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 11),
              ReviewProgress(value: 1, color: UiReviewColor.pine),
              SizedBox(height: 7),
              Text('Next: Hold through a red day'),
            ],
          ),
        ),
      ],
    ),
  );
}

class ReviewWeeklyReportPage extends StatelessWidget {
  const ReviewWeeklyReportPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Week of 14 September',
    title: 'Your floor report.',
    subtitle: 'A week of decisions, written down clearly.',
    onBack: onBack,
    background: UiReviewColor.violet,
    foreground: Colors.white,
    bottom: ReviewPrimaryButton(
      label: 'Read • +5 Trims',
      onPressed: onContinue,
      background: UiReviewColor.lemon,
      foreground: UiReviewColor.ink,
    ),
    child: Transform.rotate(
      angle: -.012,
      child: ReviewPaper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WEEK 01',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You made one decision and explained it.',
              style: TextStyle(
                fontFamily: reviewDisplay,
                fontSize: 26,
                height: 1.05,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 22),
            const Row(
              children: [
                Expanded(
                  child: ReviewStat(label: 'trades', value: '1'),
                ),
                Expanded(
                  child: ReviewStat(label: 'reasons', value: '1'),
                ),
                Expanded(
                  child: ReviewStat(label: 'desk move', value: '+0.02%'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Divider(),
            ),
            const Text(
              'BEST LEARNING MOMENT',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'You checked the exact stock token before buying.',
              style: TextStyle(height: 1.4, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(13),
              color: UiReviewColor.lemon,
              child: const Text(
                'NEXT WEEK: Follow three companies from different sectors.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ReviewPromotionPage extends StatelessWidget {
  const ReviewPromotionPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: UiReviewColor.ink,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          children: [
            const Text(
              'PROMOTION',
              style: TextStyle(
                color: UiReviewColor.lemon,
                letterSpacing: 1.7,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Rookie no more.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: reviewDisplay,
                color: Colors.white,
                fontSize: 43,
                height: .96,
                fontWeight: FontWeight.w800,
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  const Positioned(
                    left: -30,
                    bottom: 0,
                    child: ReviewSal(mood: 'celebrating', width: 250),
                  ),
                  Positioned(
                    right: 0,
                    top: 46,
                    child: Transform.rotate(
                      angle: .05,
                      child: ReviewPaper(
                        color: UiReviewColor.lemon,
                        child: const Column(
                          children: [
                            Icon(Icons.workspace_premium_rounded, size: 62),
                            SizedBox(height: 6),
                            Text(
                              'ANALYST',
                              style: TextStyle(
                                fontFamily: reviewDisplay,
                                fontSize: 29,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              '+100 Trims',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text('New desk lamp unlocked'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ReviewPrimaryButton(
              label: 'Take the Analyst desk',
              onPressed: onContinue,
              background: UiReviewColor.lemon,
              foreground: UiReviewColor.ink,
            ),
          ],
        ),
      ),
    ),
  );
}

class ReviewTrophiesPage extends StatelessWidget {
  const ReviewTrophiesPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });

  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Career cabinet',
    title: 'Trophies',
    subtitle: 'Milestones stay after the week and league reset.',
    onBack: onBack,
    bottom: ReviewPrimaryButton(label: 'Continue', onPressed: onContinue),
    child: GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: .8,
      children: const [
        _TrophyTile(
          icon: Icons.shopping_bag_rounded,
          title: 'First position',
          detail: 'Earned today',
          earned: true,
        ),
        _TrophyTile(
          icon: Icons.edit_note_rounded,
          title: 'First reason',
          detail: 'Earned today',
          earned: true,
        ),
        _TrophyTile(
          icon: Icons.content_cut_rounded,
          title: 'First trim',
          detail: 'Lock your first gain',
        ),
        _TrophyTile(
          icon: Icons.calendar_month_rounded,
          title: 'Seven days',
          detail: 'Keep a 7 day streak',
        ),
        _TrophyTile(
          icon: Icons.groups_rounded,
          title: 'Floor friend',
          detail: 'Add your first friend',
        ),
        _TrophyTile(
          icon: Icons.workspace_premium_rounded,
          title: 'Analyst',
          detail: 'Earn the promotion',
        ),
      ],
    ),
  );
}

class _TrophyTile extends StatelessWidget {
  const _TrophyTile({
    required this.icon,
    required this.title,
    required this.detail,
    this.earned = false,
  });

  final IconData icon;
  final String title, detail;
  final bool earned;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: earned ? UiReviewColor.lemon : const Color(0xFFE8E3D8),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(
        color: earned
            ? UiReviewColor.ink
            : UiReviewColor.ink.withValues(alpha: .15),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: earned
                ? UiReviewColor.ink
                : UiReviewColor.ink.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: earned
                ? Colors.white
                : UiReviewColor.ink.withValues(alpha: .38),
          ),
        ),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          style: const TextStyle(
            fontSize: 10,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class ReviewFeedPage extends StatelessWidget {
  const ReviewFeedPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: UiReviewColor.paper,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                const Text(
                  'THE FLOOR',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'What people did',
                  style: TextStyle(
                    fontFamily: reviewDisplay,
                    fontSize: 37,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 15),
                const _FloorSegments(selected: 'Feed'),
                const SizedBox(height: 15),
                Row(
                  children: [
                    const Expanded(
                      child: _AudienceChip(label: 'Friends', selected: true),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: _AudienceChip(label: 'Everyone')),
                    const SizedBox(width: 8),
                    ReviewIconButton(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Invite',
                      onPressed: onContinue,
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                const _FeedSlip(
                  handle: '@mira',
                  action: 'trimmed',
                  symbol: 'NVDA',
                  amount: '200 paper',
                  result: '+8.4%',
                  reason: 'I locked part of the gain before earnings.',
                  accent: UiReviewColor.pink,
                ),
                const SizedBox(height: 15),
                const _FeedSlip(
                  handle: '@tobe',
                  action: 'bought',
                  symbol: 'AAPL',
                  amount: '350 paper',
                  result: '+0.8%',
                  reason: 'The services side is what I am following.',
                  accent: UiReviewColor.mint,
                ),
              ],
            ),
          ),
          const ReviewBottomTabs(selected: 'Floor'),
        ],
      ),
    ),
  );
}

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: selected ? UiReviewColor.ink : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: UiReviewColor.ink.withValues(alpha: .2)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: selected ? Colors.white : UiReviewColor.ink,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _FeedSlip extends StatelessWidget {
  const _FeedSlip({
    required this.handle,
    required this.action,
    required this.symbol,
    required this.amount,
    required this.result,
    required this.reason,
    required this.accent,
  });

  final String handle, action, symbol, amount, result, reason;
  final Color accent;

  @override
  Widget build(BuildContext context) => ReviewPaper(
    shadow: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: accent,
              child: Text(
                handle.substring(1, 2).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$handle $action',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              result,
              style: const TextStyle(
                color: UiReviewColor.pine,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(12),
          color: accent.withValues(alpha: .65),
          child: Row(
            children: [
              ReviewCompanyLogo(symbol: symbol, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  symbol,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Text(
          '“$reason”',
          style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 9),
        Text(
          '18 minutes ago',
          style: TextStyle(
            color: UiReviewColor.ink.withValues(alpha: .5),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class ReviewLeaguePage extends StatelessWidget {
  const ReviewLeaguePage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: UiReviewColor.ink,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: [
                const Text(
                  'THE FLOOR',
                  style: TextStyle(
                    color: UiReviewColor.lemon,
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Bronze League',
                        style: TextStyle(
                          fontFamily: reviewDisplay,
                          color: Colors.white,
                          fontSize: 37,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '4 DAYS',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                const _FloorSegmentsDark(selected: 'League'),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: UiReviewColor.lemon,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '12',
                        style: TextStyle(
                          fontFamily: reviewDisplay,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'YOUR RANK',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '@trimmydemo',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        '50 Trims',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        onPressed: onContinue,
                        icon: const Icon(Icons.ios_share_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Scored on Trims. Money never counts.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: UiReviewColor.paper,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Column(
                    children: [
                      _LeagueRow(
                        position: 1,
                        handle: '@farah',
                        rank: 'Analyst',
                        trims: 210,
                        zone: 1,
                      ),
                      _LeagueRow(
                        position: 2,
                        handle: '@mira',
                        rank: 'Analyst',
                        trims: 185,
                        zone: 1,
                      ),
                      _LeagueRow(
                        position: 3,
                        handle: '@dami',
                        rank: 'Rookie',
                        trims: 160,
                        zone: 1,
                      ),
                      _LeagueRow(
                        position: 11,
                        handle: '@tobe',
                        rank: 'Rookie',
                        trims: 60,
                      ),
                      _LeagueRow(
                        position: 12,
                        handle: '@trimmydemo',
                        rank: 'Rookie',
                        trims: 50,
                        current: true,
                      ),
                      _LeagueRow(
                        position: 18,
                        handle: '@jules',
                        rank: 'Rookie',
                        trims: 10,
                        zone: -1,
                      ),
                      _LeagueRow(
                        position: 19,
                        handle: '@emi',
                        rank: 'Rookie',
                        trims: 5,
                        zone: -1,
                      ),
                      _LeagueRow(
                        position: 20,
                        handle: '@rae',
                        rank: 'Rookie',
                        trims: 0,
                        zone: -1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const ReviewBottomTabs(selected: 'Floor'),
        ],
      ),
    ),
  );
}

class _FloorSegmentsDark extends StatelessWidget {
  const _FloorSegmentsDark({required this.selected});
  final String selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.white12,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        for (final label in const ['Feed', 'League', 'Career'])
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: label == selected
                    ? UiReviewColor.lemon
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: label == selected ? UiReviewColor.ink : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _LeagueRow extends StatelessWidget {
  const _LeagueRow({
    required this.position,
    required this.handle,
    required this.rank,
    required this.trims,
    this.current = false,
    this.zone = 0,
  });

  final int position, trims, zone;
  final String handle, rank;
  final bool current;

  @override
  Widget build(BuildContext context) => Container(
    color: current
        ? UiReviewColor.lemon
        : zone > 0
        ? UiReviewColor.mint.withValues(alpha: .38)
        : zone < 0
        ? UiReviewColor.pink.withValues(alpha: .16)
        : Colors.transparent,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '$position',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        CircleAvatar(
          radius: 17,
          backgroundColor: current
              ? UiReviewColor.violet
              : const Color(0xFFE4DECF),
          child: Text(
            handle.substring(1, 2).toUpperCase(),
            style: TextStyle(
              color: current ? Colors.white : UiReviewColor.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                handle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(rank, style: const TextStyle(fontSize: 9)),
            ],
          ),
        ),
        Text('$trims', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class ReviewProfilePage extends StatelessWidget {
  const ReviewProfilePage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: UiReviewColor.lemon,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Profile',
                        style: TextStyle(
                          fontFamily: reviewDisplay,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    ReviewIconButton(
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      onPressed: onContinue,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 225,
                      decoration: BoxDecoration(
                        color: UiReviewColor.violet,
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                    const Positioned(
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 88,
                        backgroundColor: UiReviewColor.ink,
                        child: Text(
                          'O',
                          style: TextStyle(
                            fontFamily: reviewDisplay,
                            color: UiReviewColor.violet,
                            fontSize: 104,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  '@trimmydemo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: reviewDisplay,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'THE ORACLE • ROOKIE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                ReviewPaper(
                  shadow: false,
                  child: const Wrap(
                    spacing: 28,
                    runSpacing: 22,
                    children: [
                      ReviewStat(label: 'streak', value: '1'),
                      ReviewStat(label: 'Trims', value: '50'),
                      ReviewStat(label: 'days', value: '1'),
                      ReviewStat(label: 'trades', value: '1'),
                      ReviewStat(label: 'locked gains', value: '0'),
                      ReviewStat(label: 'avg hold', value: '3h'),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: ReviewPrimaryButton(
                        label: 'Share career',
                        onPressed: onContinue,
                        icon: Icons.ios_share_rounded,
                        background: UiReviewColor.ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ReviewPrimaryButton(
                        label: 'Friends',
                        onPressed: onContinue,
                        icon: Icons.group_rounded,
                        background: UiReviewColor.violet,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const ReviewSectionLabel('Trophies'),
                const SizedBox(height: 11),
                const _TrophyStrip(),
              ],
            ),
          ),
          const ReviewBottomTabs(selected: 'Profile'),
        ],
      ),
    ),
  );
}

class ReviewShareCardPage extends StatelessWidget {
  const ReviewShareCardPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Career card',
    title: 'Your floor, in one frame.',
    subtitle: 'Only career progress appears. Returns stay private.',
    onBack: onBack,
    background: UiReviewColor.lilac,
    bottom: ReviewPrimaryButton(
      label: 'Share image',
      icon: Icons.ios_share_rounded,
      onPressed: onContinue,
    ),
    child: SizedBox(
      height: 500,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: UiReviewColor.ink,
          borderRadius: BorderRadius.circular(34),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(
                  'assets/images/ui_review/trimmy-mark.png',
                  width: 32,
                ),
                const SizedBox(width: 6),
                const Text(
                  'trimmy',
                  style: TextStyle(
                    fontFamily: reviewDisplay,
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const CircleAvatar(
              radius: 62,
              backgroundColor: UiReviewColor.violet,
              child: Text(
                'O',
                style: TextStyle(
                  fontFamily: reviewDisplay,
                  color: UiReviewColor.ink,
                  fontSize: 76,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '@trimmydemo',
              style: TextStyle(
                fontFamily: reviewDisplay,
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text(
              'THE ORACLE • ROOKIE',
              style: TextStyle(
                color: UiReviewColor.lemon,
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            const Row(
              children: [
                Expanded(
                  child: ReviewStatLight(label: 'STREAK', value: '1'),
                ),
                Expanded(
                  child: ReviewStatLight(label: 'TRIMS', value: '50'),
                ),
                Expanded(
                  child: ReviewStatLight(label: 'TROPHIES', value: '2'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              color: UiReviewColor.lemon,
              child: const Row(
                children: [
                  Icon(Icons.shopping_bag_rounded),
                  SizedBox(width: 9),
                  Text(
                    'FIRST POSITION',
                    style: TextStyle(fontWeight: FontWeight.w800),
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

class ReviewStatLight extends StatelessWidget {
  const ReviewStatLight({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          maxLines: 1,
          style: const TextStyle(
            fontFamily: reviewDisplay,
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 9,
          letterSpacing: .8,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class ReviewFriendsPage extends StatelessWidget {
  const ReviewFriendsPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Your people',
    title: 'Friends',
    subtitle:
        'Trade reasons and league progress stay more useful with people you know.',
    onBack: onBack,
    trailing: ReviewIconButton(
      icon: Icons.person_add_alt_1_rounded,
      label: 'Invite friend',
      onPressed: onContinue,
      background: UiReviewColor.lemon,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReviewPaper(
          shadow: false,
          color: UiReviewColor.lilac,
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INVITE LINK',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'trimmy.xyz/join/rookie7',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onContinue,
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const ReviewSectionLabel('Friends • 2'),
        const SizedBox(height: 9),
        const _FriendRow(
          handle: '@mira',
          rank: 'Analyst',
          streak: '12 day streak',
          color: UiReviewColor.pink,
        ),
        const Divider(height: 22),
        const _FriendRow(
          handle: '@tobe',
          rank: 'Rookie',
          streak: '4 day streak',
          color: UiReviewColor.mint,
        ),
        const SizedBox(height: 25),
        const ReviewSectionLabel('Pending'),
        const SizedBox(height: 9),
        const _FriendRow(
          handle: '@nene',
          rank: 'Invitation sent',
          streak: 'Waiting',
          color: UiReviewColor.lemon,
        ),
        const SizedBox(height: 25),
        const ReviewSectionLabel('Blocked'),
        const SizedBox(height: 8),
        Text(
          'Nobody blocked.',
          style: TextStyle(
            color: UiReviewColor.ink.withValues(alpha: .58),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.handle,
    required this.rank,
    required this.streak,
    required this.color,
  });
  final String handle, rank, streak;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 24,
        backgroundColor: color,
        child: Text(
          handle.substring(1, 2).toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(handle, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('$rank • $streak', style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
      const Icon(Icons.more_horiz_rounded),
    ],
  );
}

class ReviewInboxPage extends StatelessWidget {
  const ReviewInboxPage({
    super.key,
    required this.onBack,
    required this.onContinue,
  });
  final VoidCallback onBack, onContinue;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: 'Everything Trimmy told you',
    title: 'Inbox',
    subtitle: 'Messages, events, results and receipts live here.',
    onBack: onBack,
    trailing: const Text(
      '1 NEW',
      style: TextStyle(
        color: UiReviewColor.pink,
        fontSize: 10,
        letterSpacing: 1,
        fontWeight: FontWeight.w800,
      ),
    ),
    child: Column(
      children: [
        _InboxSlip(
          kind: 'SAL',
          title: 'Wall Street is open.',
          detail: 'Your desk is up 0.02%.',
          time: 'Now',
          color: UiReviewColor.lemon,
          unread: true,
          onTap: onContinue,
        ),
        const SizedBox(height: 11),
        _InboxSlip(
          kind: 'EVENT',
          title: 'Nvidia reports tonight.',
          detail: 'You hold it. Make a decision.',
          time: '2h',
          color: UiReviewColor.pink,
          onTap: onContinue,
        ),
        const SizedBox(height: 11),
        _InboxSlip(
          kind: 'RECEIPT',
          title: 'Apple buy confirmed.',
          detail: '500 paper • 1.497813 shares',
          time: '5h',
          color: UiReviewColor.mint,
          onTap: onContinue,
        ),
        const SizedBox(height: 11),
        _InboxSlip(
          kind: 'LEAGUE',
          title: 'Bronze week started.',
          detail: 'You are 12th of 20.',
          time: '1d',
          color: UiReviewColor.lilac,
          onTap: onContinue,
        ),
      ],
    ),
  );
}

class _InboxSlip extends StatelessWidget {
  const _InboxSlip({
    required this.kind,
    required this.title,
    required this.detail,
    required this.time,
    required this.color,
    required this.onTap,
    this.unread = false,
  });
  final String kind, title, detail, time;
  final Color color;
  final VoidCallback onTap;
  final bool unread;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(23),
      side: const BorderSide(color: UiReviewColor.ink, width: 1.1),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: UiReviewColor.ink,
                shape: BoxShape.circle,
              ),
              child: Icon(
                kind == 'SAL'
                    ? Icons.record_voice_over_rounded
                    : kind == 'EVENT'
                    ? Icons.bolt_rounded
                    : kind == 'RECEIPT'
                    ? Icons.receipt_long_rounded
                    : Icons.emoji_events_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        kind,
                        style: const TextStyle(
                          fontSize: 9,
                          letterSpacing: .9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: UiReviewColor.pink,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              time,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}
