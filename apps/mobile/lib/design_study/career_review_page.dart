import 'package:flutter/material.dart';

import 'activities.dart';
import 'ada_actor.dart';
import 'career_review.dart';
import 'craft.dart';
import 'progress.dart';

/// Navigation intent only. The office opens the normal resumable activity once
/// this route is closed; the review itself never writes practice or account data.
class CareerReviewAction {
  const CareerReviewAction.practice(this.activityId) : portfolio = false;
  const CareerReviewAction.portfolio() : activityId = null, portfolio = true;
  final String? activityId;
  final bool portfolio;
}

class CareerReviewPage extends StatefulWidget {
  const CareerReviewPage({super.key, required this.repository});
  final OfficeProgressRepository repository;
  @override
  State<CareerReviewPage> createState() => _CareerReviewPageState();
}

class _CareerReviewPageState extends State<CareerReviewPage> {
  int floor = 1;
  static const accents = [
    StudyColor.yellow,
    StudyColor.mint,
    Color(0xFFF8DCE5),
    Color(0xFFE7E0FA),
  ];

  void practice(OfficeCareerReview review, String id) => Navigator.of(
    context,
  ).pop(CareerReviewAction.practice(review.unfinishedActivityId ?? id));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: StudyColor.paper,
    appBar: AppBar(
      backgroundColor: StudyColor.paper,
      title: const Text('Your first review'),
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: AnimatedBuilder(
            animation: widget.repository,
            builder: (context, _) {
              final review = OfficeCareerReview(widget.repository.state);
              if (!review.available || widget.repository.loadIssue != null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Finish the four floors to open your review. Your saved activities stay in your Journal.',
                  ),
                );
              }
              final folder = review.folders[floor - 1];
              return SingleChildScrollView(
                key: const PageStorageKey('career-review'),
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: SizedBox(
                        width: 159.375,
                        height: 170,
                        child: AdaActor(beat: AdaBeat.complete),
                      ),
                    ),
                    Text(
                      'Look at what you filed.',
                      textAlign: TextAlign.center,
                      style: display(
                        30,
                        weight: FontWeight.w800,
                        color: StudyColor.deep,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ada: You checked the evidence, worked with the team and made a plan. These are your decisions.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 26),
                    Text('Open a floor’s folder', style: display(21)),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wideText =
                            MediaQuery.textScalerOf(context).scale(16) > 21;
                        final width = wideText
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 10) / 2;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final item in review.folders)
                              SizedBox(
                                width: width,
                                child: CraftButton(
                                  key: ValueKey('review-floor-${item.floor}'),
                                  label: 'Floor ${item.floor}',
                                  detail: item.title,
                                  selected: floor == item.floor,
                                  fill: floor == item.floor
                                      ? accents[item.floor - 1]
                                      : Colors.white,
                                  ink: StudyColor.ink,
                                  base: StudyColor.line,
                                  outlined: true,
                                  onPressed: () =>
                                      setState(() => floor = item.floor),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: studyDuration(context, 220),
                      child: StudyPanel(
                        key: ValueKey('review-folder-$floor'),
                        color: accents[floor - 1],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(folder.takeaway, style: display(24)),
                            const SizedBox(height: 16),
                            const Text(
                              'What you filed',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(folder.filedStatement),
                            if (folder.colleagueReply case final reply?) ...[
                              const SizedBox(height: 16),
                              Text(
                                reply,
                                key: const ValueKey('review-nia-reply'),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Material(
                              type: MaterialType.transparency,
                              child: ExpansionTile(
                                key: PageStorageKey('review-evidence-$floor'),
                                tilePadding: EdgeInsets.zero,
                                title: const Text(
                                  'Your answer and the evidence',
                                ),
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          folder.revised
                                              ? 'Your first answer, before revising'
                                              : 'Your saved decision',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          folder.firstDecision,
                                          key: ValueKey(
                                            'review-first-answer-$floor',
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'What supported the final note',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(folder.evidence),
                                        const SizedBox(height: 14),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              key: ValueKey('review-replay-$floor'),
                              onPressed: () =>
                                  practice(review, folder.activityId),
                              child: Text(
                                review.unfinishedActivityId == null
                                    ? 'Practice this decision again'
                                    : 'Continue your open activity',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text('Keep it fresh.', style: display(26)),
                    const SizedBox(height: 8),
                    const Text(
                      'Revisit a decision whenever you want. Your first answers and completed floors stay saved.',
                    ),
                    const SizedBox(height: 18),
                    if (review.unfinishedActivityId case final id?) ...[
                      Text(
                        'You have an activity open: ${studyActivityById(id)!.title}.',
                      ),
                      const SizedBox(height: 12),
                      CraftButton(
                        key: const ValueKey('review-continue'),
                        label: 'Continue activity',
                        glyph: 'play',
                        onPressed: () => practice(review, id),
                      ),
                    ] else
                      for (final id in review.practiceActivityIds) ...[
                        CraftButton(
                          key: ValueKey('review-practice-$id'),
                          label: studyActivityById(id)!.title,
                          detail: review.practiceReason(id),
                          fill: Colors.white,
                          ink: StudyColor.pine,
                          base: StudyColor.line,
                          outlined: true,
                          onPressed: () => practice(review, id),
                        ),
                        const SizedBox(height: 12),
                      ],
                    const SizedBox(height: 20),
                    Text('Take a look outside the office.', style: display(23)),
                    const SizedBox(height: 8),
                    const Text(
                      'Explore real companies and the token issuers behind them.',
                    ),
                    const SizedBox(height: 14),
                    CraftButton(
                      key: const ValueKey('review-portfolio'),
                      label: 'Open Portfolio',
                      glyph: 'portfolio',
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const CareerReviewAction.portfolio()),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
