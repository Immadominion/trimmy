import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'craft.dart';
import 'document_desk.dart';
import 'activities.dart';
import 'progress.dart';
import 'ada_actor.dart';
import 'office_scene.dart';
import 'study_audio.dart';
import 'sample_evidence.dart';
import 'sample_headline.dart';
import 'update_assignment.dart';
import 'update_evidence.dart';
import 'update_composer.dart';
import 'update_review.dart';
import 'number_evidence.dart';

class ActivityStudy extends StatefulWidget {
  const ActivityStudy({
    super.key,
    required this.repository,
    required this.activity,
    this.onReturnToOffice,
    this.audio,
    this.assignmentFlight = false,
  });
  final OfficeProgressRepository repository;
  final ActivityDefinition activity;
  final VoidCallback? onReturnToOffice;
  final StudyAudioOutput? audio;
  final bool assignmentFlight;
  @override
  State<ActivityStudy> createState() => _ActivityStudyState();
}

class _ActivityStudyState extends State<ActivityStudy> {
  late ActivityProgress snapshot;
  ActivityDefinition get activity => widget.activity;
  bool get isDate => activity.id == OfficeActivityIds.checkTheDate;
  bool get isSample => activity.id == OfficeActivityIds.checkTheSample;
  bool get isUpdate => activity.id == OfficeActivityIds.prepareTheUpdate;
  bool get isTeamDecision => activity.id == OfficeActivityIds.reviewTeamUpdate;
  bool get isTeamFollowUp => activity.id == OfficeActivityIds.finishTeamUpdate;
  bool get hasNumberEvidence => activity.evidence.isNotEmpty;
  int get stage => snapshot.stage;
  String? get selected => snapshot.selectedChoiceId;
  bool get corrected => snapshot.corrected;
  String? get savedTeamBranch => widget
      .repository
      .state
      .completions[OfficeActivityIds.reviewTeamUpdate]
      ?.selectedChoiceId;
  String? get branchKey => activity.id == OfficeActivityIds.reviewTeamUpdate
      ? selected
      : savedTeamBranch;
  ActivityBranchVariant? get branchVariant =>
      activity.branchVariants[branchKey];
  bool get isAlternateTeamReplay =>
      isTeamDecision &&
      stage == 4 &&
      savedTeamBranch != null &&
      selected != savedTeamBranch;
  String get alternateTeamReplayFeedback =>
      savedTeamBranch == 'share-qualified-sales'
      ? 'You explored the request path. Your original qualified update remains saved and still shapes Nia’s return.'
      : 'You explored the qualified-update path. Your original request for costs remains saved and still shapes Nia’s return.';
  String get resolvedIntro => branchVariant?.intro ?? activity.intro;
  String get resolvedDraftHeadline =>
      branchVariant?.draftHeadline ?? activity.draftHeadline;
  String get resolvedCorrectedHeadline =>
      branchVariant?.correctedHeadline ?? activity.correctedHeadline;
  String get resolvedCorrectedFeedback =>
      branchVariant?.correctedFeedback ?? activity.correctedFeedback;
  String get resolvedSuccessFeedback =>
      branchVariant?.successFeedback ?? activity.successFeedback;
  bool allowExit = false, saving = false;
  bool animateReaction = false;
  String? saveError;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    snapshot = widget.repository.state.active!;
    animateReaction = snapshot.stage == 0;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> save(Future<dynamic> Function() operation) async {
    if (saving) return;
    setState(() {
      saving = true;
      saveError = null;
    });
    final previousStage = stage;
    final previousSelection = selected;
    final previousParts = snapshot.answerParts;
    try {
      await operation();
      if (!mounted) return;
      setState(() {
        final next = widget.repository.state.active ?? snapshot;
        animateReaction =
            next.stage != snapshot.stage ||
            next.selectedChoiceId != snapshot.selectedChoiceId ||
            !mapEquals(next.answerParts, snapshot.answerParts);
        snapshot = next;
      });
      if (stage == 4 && previousStage != 4) {
        widget.audio?.play(StudySound.saved);
      } else if (stage == 2 &&
          (selected != previousSelection ||
              !mapEquals(previousParts, snapshot.answerParts))) {
        widget.audio?.play(StudySound.select);
      } else if (stage != previousStage && stage <= 1) {
        widget.audio?.play(StudySound.paper);
      }
      if (stage != previousStage && scroll.hasClients) scroll.jumpTo(0);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              saveError = 'Your progress could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> advance(int next) =>
      save(() => widget.repository.inspectStage(next));

  Future<void> leave() async {
    if (saving || allowExit) return;
    await save(() => widget.repository.closeActivity());
    if (!mounted || saveError != null) return;
    widget.onReturnToOffice?.call();
    setState(() => allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> primaryAction() async {
    switch (stage) {
      case 0:
        await advance(1);
      case 1:
        await advance(2);
      case 2:
        await save(() => widget.repository.submitChoice());
      case 3:
        await save(() => widget.repository.acceptCorrection());
      case 4:
        await leave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = [1, 2, 3, 3, 4][stage];
    return PopScope<void>(
      canPop: allowExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: Scaffold(
        backgroundColor: StudyColor.paper,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 22, 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back to your office',
                          onPressed: saving ? null : leave,
                          icon: const Icon(Icons.close_rounded),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Semantics(
                            label: 'Activity progress',
                            value: '$progress of 4',
                            child: ExcludeSemantics(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  height: 12,
                                  child: Stack(
                                    children: [
                                      const Positioned.fill(
                                        child: ColoredBox(
                                          color: StudyColor.line,
                                        ),
                                      ),
                                      AnimatedFractionallySizedBox(
                                        duration: studyDuration(context, 350),
                                        curve: Curves.easeOutCubic,
                                        widthFactor: progress / 4,
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: StudyColor.pine,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          '$progress/4',
                          style: display(13, color: StudyColor.muted),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                      child: AnimatedSwitcher(
                        duration: studyDuration(context, 300),
                        switchInCurve: Curves.linear,
                        switchOutCurve: Curves.linear,
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                for (final child in previousChildren)
                                  ExcludeFocus(
                                    child: ExcludeSemantics(
                                      child: IgnorePointer(child: child),
                                    ),
                                  ),
                                ?currentChild,
                              ],
                            ),
                        transitionBuilder: (child, animation) => FadeTransition(
                          // Fade through paper instead of superimposing two
                          // faces and two paragraphs during a stage change.
                          opacity: animation.drive(
                            CurveTween(
                              curve: const Interval(
                                .55,
                                1,
                                curve: Curves.easeInOut,
                              ),
                            ),
                          ),
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .035),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(stage <= 1 ? 'evidence' : stage),
                          child: switch (stage) {
                            0 || 1 => evidence(),
                            2 => decision(),
                            3 => challenge(),
                            _ => outcome(),
                          },
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: StudyColor.paper,
                      border: const Border(
                        top: BorderSide(color: StudyColor.line),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (stage == 0) ...[
                          const Text(
                            'Fictional company · Practice activity',
                            style: TextStyle(
                              fontSize: 12,
                              color: StudyColor.muted,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (saveError != null) ...[
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              saveError!,
                              style: const TextStyle(color: Color(0xFF9F3045)),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        CraftButton(
                          label: saving
                              ? 'Saving…'
                              : switch (stage) {
                                  0 =>
                                    isUpdate
                                        ? 'Open your notes'
                                        : isSample
                                        ? 'Open the replies'
                                        : hasNumberEvidence
                                        ? 'Open the figures'
                                        : 'Open the report',
                                  1 =>
                                    isUpdate
                                        ? 'Build the update'
                                        : isSample
                                        ? 'Write the headline'
                                        : 'Choose an answer',
                                  2 =>
                                    isUpdate
                                        ? 'Review with Ada'
                                        : 'Submit answer',
                                  3 =>
                                    isUpdate
                                        ? 'File the corrected update'
                                        : isSample
                                        ? 'Use the trial results'
                                        : hasNumberEvidence
                                        ? 'Save the corrected answer'
                                        : isDate
                                        ? 'Add the year'
                                        : 'Include the costs',
                                  _ => 'Back to your office',
                                },
                          glyph: stage == 0
                              ? 'report'
                              : stage == 4
                              ? 'office'
                              : null,
                          onPressed: saving || (stage == 2 && selected == null)
                              ? null
                              : primaryAction,
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

  AdaBeat get actorBeat => switch (stage) {
    1 => AdaBeat.reading,
    2 when selected != null || snapshot.answerParts.isNotEmpty =>
      AdaBeat.thinking,
    3 => AdaBeat.correction,
    4 => AdaBeat.complete,
    _ => AdaBeat.listening,
  };

  Widget actor(double width) => SizedBox(
    width: width,
    child: AdaActor(beat: actorBeat, animate: animateReaction),
  );

  Widget dialogue(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: LayoutBuilder(
      builder: (context, constraints) {
        const name = Text(
          'Ada · Your guide',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: StudyColor.muted,
          ),
        );
        final words = Text(
          text,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        );
        if (MediaQuery.textScalerOf(context).scale(17) >= 26 ||
            constraints.maxWidth < 320) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  actor(88),
                  const SizedBox(width: 12),
                  const Expanded(child: name),
                ],
              ),
              const SizedBox(height: 12),
              words,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            actor(
              (isSample || isUpdate) && (stage == 1 || stage == 2) ? 88 : 128,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [name, const SizedBox(height: 7), words],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget evidence() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      dialogue(stage == 0 ? resolvedIntro : activity.sourceIntro),
      Row(
        children: [
          Expanded(
            child: Text(
              stage == 0
                  ? activity.title
                  : isUpdate
                  ? 'Your three notes'
                  : isSample
                  ? 'Read the replies'
                  : hasNumberEvidence
                  ? 'Check the figures'
                  : 'Check the report',
              style: display(27),
            ),
          ),
          if (stage == 1)
            IconButton(
              tooltip: isUpdate
                  ? 'Read the assignment again'
                  : 'Read the headline again',
              onPressed: saving ? null : () => advance(0),
              icon: const Icon(Icons.undo_rounded),
            ),
        ],
      ),
      const SizedBox(height: 20),
      StudyDocumentDesk(
        sourceOpen: stage == 1,
        headline: AssignmentHero(
          activityId: activity.id,
          enabled: widget.assignmentFlight && stage == 0,
          child: report(amended: false),
        ),
        source: sourcePaper(),
      ),
      if (stage == 0) ...[
        const SizedBox(height: 18),
        Semantics(
          button: true,
          label: isUpdate
              ? 'Open your three notes'
              : isSample
              ? 'Open the trial replies'
              : hasNumberEvidence
              ? 'Open the figures'
              : 'Open Aster’s report',
          child: Material(
            color: StudyColor.mint,
            shape: studyShape(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: saving ? null : () => advance(1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CraftGlyph('report', size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isUpdate
                                ? 'Your earlier notes'
                                : isSample
                                ? 'The trial replies'
                                : hasNumberEvidence
                                ? activity.sourceTitle
                                : 'The company’s report',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            isUpdate
                                ? 'Growth · Profit · Trial'
                                : isSample
                                ? '10 invited beta testers'
                                : hasNumberEvidence
                                ? 'Fictional practice examples'
                                : 'Aster’s report',
                            style: TextStyle(
                              fontSize: 13,
                              color: StudyColor.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const CraftGlyph('arrow', size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );

  Widget report({
    required bool amended,
    String? headline,
    bool compact = false,
  }) => Transform.rotate(
    angle: compact ? 0 : -.012,
    child: Container(
      padding: EdgeInsets.all(compact ? 18 : 23),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: StudyColor.yellow, width: 6)),
        boxShadow: [
          BoxShadow(
            color: Color(0xFFDFE1DB),
            offset: Offset(3, 5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CraftGlyph('office', size: 24),
                  const SizedBox(width: 9),
                  Text(
                    hasNumberEvidence ? 'PRACTICE' : 'ASTER',
                    style: display(16, weight: FontWeight.w800),
                  ),
                ],
              ),
              const Text(
                'Sep 2026',
                style: TextStyle(fontSize: 12, color: StudyColor.muted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SelectableText(
            headline ??
                (isDate
                    ? amended
                          ? 'In 2025, users grew'
                          : 'This year, users grew'
                    : amended
                    ? resolvedCorrectedHeadline
                    : resolvedDraftHeadline),
            style: display(
              compact ? 23 : 27,
              color: amended ? StudyColor.pine : StudyColor.ink,
            ),
          ),
          if (isDate) ...[
            const SizedBox(height: 6),
            Text(
              '80%.',
              style: display(
                compact ? 45 : 66,
                weight: FontWeight.w800,
                color: StudyColor.pine,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(height: 2, color: StudyColor.line),
          const SizedBox(height: 12),
          Row(
            children: [
              CraftGlyph(amended ? 'check' : 'envelope', size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  amended ? 'Answer saved' : 'A claim to check',
                  style: const TextStyle(fontSize: 12, color: StudyColor.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget sourcePaper() => hasNumberEvidence
      ? NumberEvidence(activity: activity)
      : isUpdate
      ? const UpdateEvidenceFolder()
      : isSample
      ? const SampleEvidence()
      : isDate
      ? dateSource()
      : moneySource();

  Widget dateSource() => Container(
    padding: const EdgeInsets.all(24),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: StudyColor.violet, width: 7)),
      boxShadow: [
        BoxShadow(
          color: Color(0xFFDFE1DB),
          offset: Offset(3, 5),
          blurRadius: 0,
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(activity.sourceTitle, style: display(21)),
        const SizedBox(height: 8),
        SelectableText(
          '2025',
          style: display(54, weight: FontWeight.w800, color: StudyColor.violet),
        ),
        const SizedBox(height: 24),
        const Text(
          'People using Aster',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        evidenceRow('2024', '100,000', .55),
        const SizedBox(height: 18),
        evidenceRow('2025', '180,000', 1),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: StudyColor.mint,
            shape: studyShape(14),
          ),
          child: const Text(
            '80% growth from 2024 to 2025.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Published February 2026',
          style: TextStyle(fontSize: 12, color: StudyColor.muted),
        ),
      ],
    ),
  );

  Widget moneySource() => Container(
    padding: const EdgeInsets.all(22),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: StudyColor.violet, width: 7)),
      boxShadow: [BoxShadow(color: Color(0xFFDFE1DB), offset: Offset(3, 5))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(activity.sourceTitle, style: display(23)),
        const SizedBox(height: 12),
        const Text(
          'Sales minus costs leaves profit.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 260 ||
                MediaQuery.textScalerOf(context).scale(16) > 21) {
              return Column(
                children: [
                  moneyYear('2024', r'$1,000', r'$600', r'$400', .6),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Divider(),
                  ),
                  moneyYear('2025', r'$1,500', r'$1,300', r'$200', 1300 / 1500),
                ],
              );
            }
            return moneyComparison();
          },
        ),
        const SizedBox(height: 20),
        const Text(
          'Simplified example · US dollars',
          style: TextStyle(fontSize: 12, color: StudyColor.muted),
        ),
      ],
    ),
  );

  Widget moneyComparison() => Table(
    columnWidths: const {
      0: FlexColumnWidth(.9),
      1: FlexColumnWidth(1.15),
      2: FlexColumnWidth(1.15),
    },
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    border: const TableBorder(
      horizontalInside: BorderSide(color: StudyColor.line),
    ),
    children: [
      TableRow(
        children: [
          const SizedBox.shrink(),
          for (final year in ['2024', '2025'])
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: Text(
                year,
                textAlign: TextAlign.right,
                style: display(18, color: StudyColor.violet),
              ),
            ),
        ],
      ),
      for (final row in [
        ('Sales', r'$1,000', r'$1,500'),
        ('Costs', r'$600', r'$1,300'),
        ('Profit', r'$400', r'$200'),
      ])
        TableRow(
          decoration: row.$1 == 'Profit'
              ? const BoxDecoration(color: StudyColor.mint)
              : null,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 6),
              child: Text(
                row.$1,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final cell in [('2024', row.$2), ('2025', row.$3)])
              Semantics(
                label: '${row.$1} in ${cell.$1}: ${cell.$2}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                    horizontal: 6,
                  ),
                  child: SelectableText(
                    cell.$2,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: row.$1 == 'Profit'
                          ? StudyColor.pine
                          : StudyColor.ink,
                    ),
                  ),
                ),
              ),
          ],
        ),
    ],
  );

  Widget moneyYear(
    String year,
    String sales,
    String costs,
    String profit,
    double costShare,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(year, style: display(24, color: StudyColor.violet)),
      const SizedBox(height: 14),
      for (final row in [
        ('Sales', sales),
        ('Costs', costs),
        ('Profit', profit),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  row.$1,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: row.$1 == 'Profit'
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
              SelectableText(
                row.$2,
                style: display(
                  20,
                  color: row.$1 == 'Profit' ? StudyColor.pine : StudyColor.ink,
                ),
              ),
            ],
          ),
        ),
      Semantics(
        label:
            '$year: sales $sales, minus costs $costs, leaves profit $profit.',
        child: ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: (costShare * 1000).round(),
                    child: const ColoredBox(
                      color: StudyColor.line,
                      child: SizedBox.expand(),
                    ),
                  ),
                  Expanded(
                    flex: ((1 - costShare) * 1000).round(),
                    child: const ColoredBox(
                      color: StudyColor.pine,
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget evidenceRow(String year, String value, double fraction) => Column(
    children: [
      Row(
        children: [
          Text(year, style: display(17)),
          const Spacer(),
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction,
          child: Container(
            height: 14,
            decoration: BoxDecoration(
              color: year == '2025' ? StudyColor.violet : StudyColor.line,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    ],
  );

  Widget decision() => isUpdate
      ? updateDecision()
      : isSample
      ? sampleDecision()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            dialogue(
              hasNumberEvidence
                  ? 'Which answer do the figures support?'
                  : 'What does the report tell you?',
            ),
            Text('Choose an answer', style: display(28)),
            const SizedBox(height: 22),
            report(amended: false, compact: true),
            const SizedBox(height: 24),
            for (final option in activity.presentedChoices) ...[
              choice(option),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: saving ? null : () => advance(1),
              child: Text(
                hasNumberEvidence
                    ? 'Read the figures again'
                    : 'Read the report again',
              ),
            ),
          ],
        );

  Widget sampleDecision() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      dialogue('Choose a count and a group that match the replies.'),
      Text('Write the headline', style: display(28)),
      const SizedBox(height: 22),
      SampleHeadline(
        parts: snapshot.answerParts,
        onSelect: saving
            ? null
            : (part, value) =>
                  save(() => widget.repository.selectAnswerPart(part, value)),
      ),
      const SizedBox(height: 18),
      TextButton(
        onPressed: saving ? null : () => advance(1),
        child: const Text('Read the replies again'),
      ),
    ],
  );

  Widget updateDecision() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      dialogue(
        'Pin three facts that our notes support. Tap a pinned fact to remove it.',
      ),
      Text('Build the update', style: display(28)),
      const SizedBox(height: 18),
      UpdateComposer(
        parts: snapshot.answerParts,
        onSelect: saving
            ? null
            : (part, value) =>
                  save(() => widget.repository.selectAnswerPart(part, value)),
      ),
      const SizedBox(height: 14),
      TextButton(
        onPressed: saving ? null : () => advance(1),
        child: const Text('Open your notes again'),
      ),
    ],
  );

  String get sampleChallengeTitle {
    final countFits = snapshot.answerParts['amount'] == 'eight-of-ten';
    final groupFits = snapshot.answerParts['group'] == 'testers';
    if (countFits) return 'The count fits. Check the group.';
    if (groupFits) return 'Two testers felt differently.';
    return activity.challengeTitle;
  }

  String get sampleChallengeText {
    final countFits = snapshot.answerParts['amount'] == 'eight-of-ten';
    final groupFits = snapshot.answerParts['group'] == 'testers';
    if (countFits) {
      return 'Eight of ten is the right count. But only the invited beta testers were asked. These replies cannot tell us what all customers think.';
    }
    if (groupFits) {
      return 'Beta testers is the right group. Eight liked Aster and two did not, so “all” goes further than their replies support.';
    }
    return activity.challengeText;
  }

  Widget choice(ActivityChoice option) {
    final active = selected == option.id;
    return CraftButton(
      label: option.label,
      detail: option.detail,
      selected: active,
      fill: active ? StudyColor.mint : Colors.white,
      ink: active ? StudyColor.pine : StudyColor.ink,
      base: active ? StudyColor.pine : StudyColor.line,
      outlined: true,
      onPressed: saving
          ? null
          : () => save(() => widget.repository.selectChoice(option.id)),
    );
  }

  Widget challenge() => isUpdate
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            dialogue('Let’s keep the update within what we checked.'),
            UpdateCorrection(choiceId: selected!),
            const SizedBox(height: 24),
            UpdateDraft(choiceId: selected!),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            dialogue(
              isSample
                  ? 'Check the count and who was asked.'
                  : hasNumberEvidence
                  ? activity.challengeTitle
                  : isDate
                  ? 'Which year does the report cover?'
                  : 'What happened to the costs?',
            ),
            Text('Let’s check one detail.', style: display(28)),
            const SizedBox(height: 22),
            report(
              amended: false,
              compact: true,
              headline: isSample || hasNumberEvidence
                  ? activity.choices
                        .firstWhere((choice) => choice.id == selected)
                        .detail
                  : null,
            ),
            const SizedBox(height: 22),
            StudyPanel(
              color: const Color(0xFFFFE9DF),
              border: const Color(0xFFE6BAAA),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSample ? sampleChallengeTitle : activity.challengeTitle,
                    style: display(21),
                  ),
                  const SizedBox(height: 10),
                  Text(isSample ? sampleChallengeText : activity.challengeText),
                  const SizedBox(height: 14),
                  Text(
                    isSample
                        ? 'Keep both details: 8 of 10 beta testers.'
                        : hasNumberEvidence
                        ? resolvedCorrectedHeadline
                        : isDate
                        ? 'Add the year to make the claim clear.'
                        : 'Subtract the costs to see what is left.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        );

  Widget outcome() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 10),
      Center(child: actor(156)),
      const SizedBox(height: 12),
      Text(
        isAlternateTeamReplay
            ? 'Replay complete.'
            : branchVariant?.outcomeTitle ??
                  (isUpdate ? 'Update filed.' : 'Good catch.'),
        textAlign: TextAlign.center,
        style: display(38, weight: FontWeight.w800, color: StudyColor.deep),
      ),
      const SizedBox(height: 10),
      Text(
        isAlternateTeamReplay
            ? alternateTeamReplayFeedback
            : corrected
            ? resolvedCorrectedFeedback
            : resolvedSuccessFeedback,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: StudyColor.deep),
      ),
      const SizedBox(height: 26),
      if (isUpdate)
        UpdateDraft(
          choiceId: updateCorrectChoiceId,
          filed: true,
          animate: animateReaction,
        )
      else
        report(amended: true),
      const SizedBox(height: 26),
      Text(
        isTeamDecision
            ? 'Your first team decision and Nia’s response are in your journal.'
            : isTeamFollowUp
            ? 'Your original team decision and this follow-up are both in your journal.'
            : isUpdate
            ? 'Your first saved draft and the filed update are in your journal.'
            : 'Your first answer and what you learned are in your journal.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: StudyColor.muted),
      ),
    ],
  );
}
