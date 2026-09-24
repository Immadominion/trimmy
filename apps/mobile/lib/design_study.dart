import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design_study/craft.dart';
import 'design_study/mission.dart';
import 'design_study/activities.dart';
import 'design_study/progress.dart';
import 'design_study/office_scene.dart';
import 'design_study/study_audio.dart';
import 'design_study/office_keepsakes.dart';
import 'design_study/update_review.dart';
import 'design_study/career.dart';
import 'design_study/career_review_page.dart';
import 'design_study/practice_catalog.generated.dart';
import 'account/account_controller.dart';
import 'account/account_host.dart';
import 'account/account_portfolio_panel.dart';
import 'account/account_settings.dart';
import 'markets/stock_research_host.dart';
import 'markets/stock_research_panel.dart';
import 'social/invitations_panel.dart';
import 'social/relationships_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) WidgetsBinding.instance.ensureSemantics();
  for (final family in ['manrope', 'rubik']) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$family/OFL.txt'));
    });
  }
  final preferences = await SharedPreferences.getInstance();
  runApp(
    StockResearchHost(
      child: PracticeAccountHost(
        preferences: preferences,
        builder: (context, account, configurationFailed) => OfficeStudy(
          key: ValueKey(account?.navigationEpoch ?? 0),
          preferences: preferences,
          progressRepository: account?.repository,
          accountController: account,
          accountConfigurationFailed: configurationFailed,
        ),
      ),
    ),
  );
}

/// Separate candidate entry point. Does not mutate the production practice save.
class OfficeStudy extends StatefulWidget {
  const OfficeStudy({
    super.key,
    required this.preferences,
    this.progressRepository,
    this.audio,
    this.accountController,
    this.accountConfigurationFailed = false,
  });
  final SharedPreferences preferences;
  final OfficeProgressRepository? progressRepository;
  final StudyAudioOutput? audio;
  final AccountController? accountController;
  final bool accountConfigurationFailed;
  @override
  State<OfficeStudy> createState() => _OfficeStudyState();
}

class _OfficeStudyState extends State<OfficeStudy> {
  static const motionKey = 'trimmy.office-layout-study.reduce-motion.v1';
  static const soundKey =
      'trimmy.office.sound.v1'; // gitleaks:allow -- local preferences key, not a credential
  late final StudyAudioOutput audio;
  int launchIntent = 0;
  bool soundEnabled = false;
  late final OfficeProgressRepository repository;
  int tab = 0;
  bool reduceMotion = false, opening = false;
  String? saveError;
  OfficeProgress get progress => repository.state;
  OfficeCareer get career => OfficeCareer(progress);
  bool get completed => progress.completions.isNotEmpty;
  bool get allDone => career.isComplete;
  ActivityDefinition get nextActivity =>
      studyActivityById(career.nextActivityId)!;
  String? get teamBranchChoice => progress
      .completions[OfficeActivityIds.reviewTeamUpdate]
      ?.selectedChoiceId;

  ActivityBranchVariant? branchVariantFor(
    ActivityDefinition activity, [
    ActivityCompletion? saved,
  ]) {
    final key = activity.id == OfficeActivityIds.reviewTeamUpdate
        ? saved?.selectedChoiceId ?? teamBranchChoice
        : teamBranchChoice;
    return activity.branchVariants[key];
  }

  String get officeFollowup {
    if (allDone && progress.active == null) {
      return 'Ada: Four floors, and a plan we can file. Let’s look back at your decisions and choose what to practice next.';
    }
    if (progress.active != null) {
      return 'Your place is saved. Continue where you stopped.';
    }
    if (progress.completions.containsKey(OfficeActivityIds.planNotAPromise)) {
      return 'Ada: The plan is honest now. Write it up as the plan we can file.';
    }
    if (progress.completions.containsKey(OfficeActivityIds.setALossLimit)) {
      return 'Ada: Your limit is set. Now keep the plan a plan, not a promise.';
    }
    if (progress.completions.containsKey(OfficeActivityIds.finishTeamUpdate)) {
      return '${branchVariantFor(finishTeamUpdateActivity)?.officeConsequence ?? 'Ada and Nia have the completed fictional update.'} '
          'Floor 4 is open: let’s plan what to invest, within a limit.';
    }
    if (progress.completions.containsKey(OfficeActivityIds.readReturnedCosts)) {
      return teamBranchChoice == 'share-qualified-sales'
          ? 'Nia: The costs are filed. Return to your qualified sales update and revise it with the profit result.'
          : 'Nia: The requested costs are filed. Finish the profit comparison you held open.';
    }
    if (progress.completions.containsKey(OfficeActivityIds.reviewTeamUpdate)) {
      return branchVariantFor(
            reviewTeamUpdateActivity,
            progress.completions[OfficeActivityIds.reviewTeamUpdate],
          )?.officeConsequence ??
          'Nia will return with the missing costs.';
    }
    if (progress.completions.containsKey(
      OfficeActivityIds.prepareTheComparison,
    )) {
      return 'Ada: Your first two floors are filed. Nia from the research team has a new update for you to review.';
    }
    if (progress.completions.containsKey('check-concentration')) {
      return 'Ada: You found what depends on Aster. Bring your three checks into one comparison.';
    }
    if (progress.completions.containsKey('count-the-fees')) {
      return 'Ada: The fee is accounted for. Now check the companies behind the purchases.';
    }
    if (progress.completions.containsKey('compare-company-value')) {
      return 'Ada: You compared all the shares. Next, follow the fee in an order estimate.';
    }
    if (progress.completions.containsKey(OfficeActivityIds.prepareTheUpdate)) {
      return 'Ada: ${updateOfficeReply(progress.completions[OfficeActivityIds.prepareTheUpdate]!.selectedChoiceId)} Floor 2 is open. Let’s look beyond one share price.';
    }
    if (progress.completions.containsKey(OfficeActivityIds.checkTheSample)) {
      return 'Ada: Three notes checked. Bring them together in our update.';
    }
    if (progress.completions.containsKey(OfficeActivityIds.salesAndProfit)) {
      return 'Ada: Costs checked. Now look at who was asked.';
    }
    if (completed) return 'Ada: Date checked. Next, follow the costs.';
    return nextActivity.officeDescription;
  }

  @override
  void initState() {
    super.initState();
    reduceMotion = widget.preferences.get(motionKey) == true;
    soundEnabled = widget.preferences.get(soundKey) == true;
    audio = widget.audio ?? StudyAudio();
    audio.setEnabled(soundEnabled);
    repository =
        widget.progressRepository ??
        OfficeProgressRepository.fromPreferences(widget.preferences);
    if (repository.loadIssue != null) {
      saveError =
          'Your saved progress could not be opened. Try again to reload it.';
    }
  }

  @override
  void dispose() {
    launchIntent++;
    unawaited(audio.close());
    super.dispose();
  }

  void selectTab(int value) {
    launchIntent++;
    setState(() => tab = value);
  }

  Future<void> openActivity(
    BuildContext context, [
    ActivityDefinition? activity,
  ]) async {
    if (opening || repository.loadIssue != null) return;
    final intent = ++launchIntent;
    final fromOffice = tab == 0;
    setState(() {
      opening = true;
      saveError = null;
    });
    try {
      await repository.startActivity((activity ?? nextActivity).id);
      if (!context.mounted || intent != launchIntent) return;
      final openedActivity = studyActivities.firstWhere(
        (a) => a.id == repository.state.active!.activityId,
      );
      final playHandoff = fromOffice && repository.state.active!.stage == 0;
      audio.play(StudySound.paper);
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: studyDuration(context, 520),
          reverseTransitionDuration: studyDuration(context, 260),
          pageBuilder: (context, animation, secondaryAnimation) =>
              ActivityStudy(
                repository: repository,
                activity: openedActivity,
                audio: audio,
                assignmentFlight: playHandoff,
                onReturnToOffice: () {
                  if (mounted) setState(() => tab = 0);
                },
              ),
          // Clear the room before introducing the activity's text. The Hero
          // stays above both routes, so the envelope remains continuous.
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              Stack(
                fit: StackFit.expand,
                children: [
                  FadeTransition(
                    opacity: animation.drive(
                      CurveTween(curve: const Interval(0, .3)),
                    ),
                    child: const ColoredBox(color: StudyColor.paper),
                  ),
                  FadeTransition(
                    opacity: animation.drive(
                      CurveTween(
                        curve: const Interval(.3, .85, curve: Curves.easeOut),
                      ),
                    ),
                    child: child,
                  ),
                ],
              ),
        ),
      );
    } catch (_) {
      if (mounted) {
        saveError = 'This activity could not be opened. Please try again.';
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> openCareerReview(BuildContext context) async {
    if (opening || repository.loadIssue != null || !allDone) return;
    final intent = ++launchIntent;
    setState(() => opening = true);
    CareerReviewAction? action;
    try {
      action = await Navigator.of(context).push<CareerReviewAction>(
        MaterialPageRoute(
          builder: (_) => CareerReviewPage(repository: repository),
        ),
      );
    } finally {
      if (mounted) setState(() => opening = false);
    }
    if (!context.mounted || intent != launchIntent || action == null) return;
    if (action.portfolio) {
      selectTab(1);
    } else if (action.activityId case final id?) {
      await openActivity(context, studyActivityById(id));
    }
  }

  Future<void> retryProgress() async {
    try {
      await repository.retryLoad();
    } catch (_) {
      // Keep the protected save and offer another reload; never reset it here.
    }
    if (mounted) {
      setState(() {
        saveError = repository.loadIssue == null
            ? null
            : 'Your saved progress could not be opened. Try again to reload it.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Trimmy',
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: StudyColor.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: StudyColor.pine,
        surface: StudyColor.paper,
        onSurface: StudyColor.ink,
        primary: StudyColor.pine,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 16, height: 1.45),
        bodyLarge: TextStyle(fontSize: 17, height: 1.45),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations:
            reduceMotion || MediaQuery.disableAnimationsOf(context),
      ),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 6, 12, 4),
                    child: Row(
                      children: [
                        Text(
                          'trimmy',
                          textScaler: TextScaler.noScaling,
                          style: display(
                            30,
                            color: StudyColor.pine,
                            weight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        _noticeBadge(context),
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: () {
                            launchIntent++;
                            settings(context);
                          },
                          icon: const Icon(Icons.tune_rounded, size: 24),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: switch (tab) {
                      0 => office(context),
                      1 => portfolio(context),
                      _ => journal(context),
                    },
                  ),
                  dock(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget office(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final sections = <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 45, minHeight: 50),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: StudyColor.mint,
                  shape: studyShape(15),
                ),
                child: Semantics(
                  label: 'Floor ${career.currentFloor}',
                  child: Text(
                    career.currentFloor.toString().padLeft(2, '0'),
                    style: display(20, color: StudyColor.pine),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your office', style: display(25)),
                    const SizedBox(height: 5),
                    Text(
                      '${career.completedOn(career.currentFloor)} of ${career.activitiesOn(career.currentFloor).length} activities saved.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: StudyColor.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Your office floors',
                onPressed: () {
                  launchIntent++;
                  floors(context);
                },
                icon: const CraftGlyph('office', size: 30),
              ),
            ],
          ),
        ),
        Stack(
          fit: StackFit.expand,
          children: [
            OfficeScene(
              activityId: nextActivity.id,
              complete: allDone && progress.active == null,
              onOpen: opening || repository.loadIssue != null
                  ? null
                  : () {
                      if (allDone && progress.active == null) {
                        openCareerReview(context);
                      } else {
                        openActivity(context);
                      }
                    },
            ),
            if (completed)
              Positioned(
                left: 12,
                bottom: 10,
                child: OfficeKeepsakes(
                  completedActivityIds: progress.completions.keys.toSet(),
                  onOpenNotes: () => selectTab(2),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      allDone && progress.active == null
                          ? 'Your first review'
                          : nextActivity.title,
                      style: display(24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    allDone && progress.active == null ? 'Done' : '3 min',
                    style: const TextStyle(
                      fontSize: 13,
                      color: StudyColor.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                officeFollowup,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: StudyColor.muted,
                ),
              ),
              const SizedBox(height: 18),
              CraftButton(
                label: opening
                    ? 'Opening…'
                    : allDone && progress.active == null
                    ? 'Open your review'
                    : progress.active != null
                    ? 'Continue activity'
                    : 'Start activity',
                glyph: allDone && progress.active == null ? 'journal' : 'play',
                onPressed: opening || repository.loadIssue != null
                    ? null
                    : allDone && progress.active == null
                    ? () => openCareerReview(context)
                    : () => openActivity(context),
              ),
              if (repository.loadIssue != null)
                TextButton(
                  onPressed: retryProgress,
                  child: const Text('Try again'),
                ),
              if (saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    saveError!,
                    style: const TextStyle(color: Color(0xFF9F3045)),
                  ),
                ),
            ],
          ),
        ),
      ];
      final needsScroll =
          constraints.maxHeight < 610 ||
          MediaQuery.textScalerOf(context).scale(16) > 21;
      if (needsScroll) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sections[0],
              AspectRatio(aspectRatio: 4 / 3, child: sections[1]),
              sections[2],
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sections[0],
          Expanded(child: sections[1]),
          sections[2],
        ],
      );
    },
  );

  Widget dock() => Container(
    decoration: const BoxDecoration(
      color: StudyColor.paper,
      border: Border(top: BorderSide(color: StudyColor.line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 6),
        child: Row(
          children: List.generate(3, (index) {
            final name = ['Office', 'Portfolio', 'Journal'][index];
            final selected = tab == index;
            return Expanded(
              child: Semantics(
                selected: selected,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => selectTab(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: studyDuration(context, 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 5,
                            ),
                            decoration: ShapeDecoration(
                              color: selected
                                  ? StudyColor.mint
                                  : Colors.transparent,
                              shape: studyShape(14),
                            ),
                            child: CraftGlyph(
                              ['office', 'portfolio', 'journal'][index],
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            name,
                            style: TextStyle(
                              fontFamily: 'Rubik',
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected
                                  ? StudyColor.pine
                                  : StudyColor.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    ),
  );

  Widget journal(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Text('Your notes', style: display(30)),
      const SizedBox(height: 10),
      const Text(
        'Your saved answers, with the latest work first.',
        style: TextStyle(color: StudyColor.muted),
      ),
      const SizedBox(height: 28),
      if (allDone) ...[
        StudyPanel(
          color: StudyColor.mint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your first review', style: display(24)),
              const SizedBox(height: 8),
              const Text(
                'Four floors of decisions. See what you filed and pick something to practice again.',
              ),
              const SizedBox(height: 16),
              CraftButton(
                key: const ValueKey('journal-career-review'),
                label: 'Open your review',
                glyph: 'journal',
                onPressed: opening || repository.loadIssue != null
                    ? null
                    : () => openCareerReview(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
      ],
      if (!completed) ...[
        const Center(child: CraftGlyph('journal', size: 80)),
        const SizedBox(height: 24),
        Text('Your first activity goes here.', style: display(23)),
        const SizedBox(height: 10),
        const Text('Finish an activity with Ada to save what you learned.'),
        const SizedBox(height: 24),
        CraftButton(
          label: progress.active == null
              ? 'Start activity'
              : 'Continue activity',
          glyph: 'envelope',
          onPressed: opening || repository.loadIssue != null
              ? null
              : () => openActivity(context),
        ),
      ],
      for (final activity in studyActivities.reversed)
        if (progress.completions[activity.id] case final saved?) ...[
          Row(
            children: [
              const CraftGlyph('check', size: 24),
              const SizedBox(width: 8),
              Expanded(child: Text(activity.title, style: display(23))),
            ],
          ),
          const SizedBox(height: 16),
          StudyPanel(
            key: ValueKey('journal-${activity.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What you checked',
                  style: TextStyle(color: StudyColor.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  branchVariantFor(activity, saved)?.draftHeadline ??
                      activity.draftHeadline,
                  style: display(21),
                ),
                if (activity.id == OfficeActivityIds.prepareTheUpdate) ...[
                  const SizedBox(height: 20),
                  UpdateDraft(
                    choiceId: saved.selectedChoiceId,
                    firstSaved: true,
                  ),
                ] else if (activity.id == OfficeActivityIds.checkTheSample ||
                    activity.evidence.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    activity.evidence.isNotEmpty
                        ? 'Your first answer'
                        : 'Your first headline',
                    style: const TextStyle(
                      color: StudyColor.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activity.choices
                        .firstWhere(
                          (choice) => choice.id == saved.selectedChoiceId,
                        )
                        .detail,
                    style: display(20),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  activity.id == OfficeActivityIds.prepareTheUpdate
                      ? 'What the notes support'
                      : activity.evidence.isNotEmpty
                      ? 'What the figures showed'
                      : 'What the report showed',
                  style: TextStyle(color: StudyColor.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  branchVariantFor(activity, saved)?.journalEvidence ??
                      activity.journalEvidence,
                ),
                const SizedBox(height: 20),
                Text(
                  activity.id == OfficeActivityIds.prepareTheUpdate
                      ? saved.corrected
                            ? 'You revised the draft with Ada before filing the update.'
                            : 'All three facts in your draft matched the notes.'
                      : saved.corrected
                      ? 'You changed your answer after checking the explanation.'
                      : activity.evidence.isNotEmpty
                      ? 'You checked the figures and chose the supported answer.'
                      : 'You checked the report and chose the correct answer.',
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  color: StudyColor.mint,
                  child: Text(
                    branchVariantFor(activity, saved)?.correctedHeadline ??
                        activity.correctedHeadline,
                    style: display(20, color: StudyColor.pine),
                  ),
                ),
                if (activity.id == OfficeActivityIds.prepareTheUpdate) ...[
                  const SizedBox(height: 20),
                  Text('Ada’s reply', style: display(19)),
                  const SizedBox(height: 8),
                  Text(
                    updateOfficeReply(saved.selectedChoiceId),
                    style: const TextStyle(height: 1.4),
                  ),
                ],
                if (activity.id == OfficeActivityIds.reviewTeamUpdate) ...[
                  const SizedBox(height: 20),
                  Text('Nia’s reply', style: display(19)),
                  const SizedBox(height: 8),
                  Text(
                    branchVariantFor(activity, saved)?.officeConsequence ??
                        'Nia will follow the saved action.',
                    style: const TextStyle(height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          CraftButton(
            key: ValueKey('replay-${activity.id}'),
            label: progress.active != null ? 'Continue activity' : 'Try again',
            fill: Colors.white,
            ink: StudyColor.pine,
            base: StudyColor.line,
            outlined: true,
            onPressed: opening || repository.loadIssue != null
                ? null
                : () => openActivity(
                    context,
                    progress.active != null ? nextActivity : activity,
                  ),
          ),
          const SizedBox(height: 32),
        ],
    ],
  );

  Widget portfolio(BuildContext context) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Text('Your portfolio', style: display(30)),
      const SizedBox(height: 10),
      const Text(
        'Your wallet and the companies you want to understand.',
        style: TextStyle(color: StudyColor.muted),
      ),
      const SizedBox(height: 24),
      if (widget.accountController?.canSignIn == true)
        AccountPortfolioPanel(
          controller: widget.accountController,
          onSignIn: () => settings(context),
        )
      else
        StudyPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your wallet belongs here', style: display(22)),
              const SizedBox(height: 8),
              const Text(
                'Account access is not available in this build. You can still explore stock prices and play through the office.',
              ),
            ],
          ),
        ),
      const SizedBox(height: 28),
      if (StockResearchScope.maybeOf(context, listen: false) != null) ...[
        StudyPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: CraftGlyph('report', size: 38),
              ),
              const SizedBox(height: 12),
              Text('Meet the real companies', style: display(23)),
              const SizedBox(height: 8),
              const Text(
                'Look up tokenized stocks, compare their issuers and explore price history.',
              ),
              const SizedBox(height: 18),
              CraftButton(
                key: const ValueKey('portfolio-stock-prices'),
                label: 'Explore stocks',
                onPressed: () => stockPricesSheet(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
      Text('From your office', style: display(21)),
      const SizedBox(height: 8),
      Text(
        completed
            ? '${progress.completions.length} ${progress.completions.length == 1 ? 'activity' : 'activities'} filed. The fictional companies in your activities are practice, separate from your wallet.'
            : 'Read company reports and make your first decisions with Ada. Activities use fictional companies.',
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: () => selectTab(allDone ? 2 : 0),
        icon: Icon(
          allDone ? Icons.menu_book_rounded : Icons.door_front_door_outlined,
        ),
        label: Text(allDone ? 'Read your Journal' : 'Back to the office'),
      ),
      const SizedBox(height: 22),
    ],
  );

  Future<void> floors(BuildContext context) async {
    final activityId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      useSafeArea: true,
      backgroundColor: StudyColor.paper,
      shape: studyShape(28),
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Your office floors', style: display(29)),
            const SizedBox(height: 12),
            Text(
              allDone
                  ? 'All ${practiceCatalogFloors.length} floors are complete. Revisit an activity or read your notes.'
                  : 'You’re on Floor ${career.currentFloor}. Finish each activity to open the next.',
            ),
            if (progress.active != null && progress.active!.stage < 4) ...[
              const SizedBox(height: 10),
              const Text(
                'Finish your current activity before opening another. Your place is saved.',
              ),
            ],
            const SizedBox(height: 24),
            for (final floor in practiceCatalogFloors.entries) ...[
              StudyPanel(
                color: career.isFloorUnlocked(floor.key)
                    ? StudyColor.mint
                    : Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Floor ${floor.key}', style: display(22)),
                    const SizedBox(height: 8),
                    Text(
                      floor.value,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      career.isFloorUnlocked(floor.key)
                          ? '${career.completedOn(floor.key)} of ${career.activitiesOn(floor.key).length} activities saved'
                          : 'Finish Floor ${floor.key - 1} to open this floor.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final id in career.activitiesOn(floor.key)) ...[
                CraftButton(
                  key: ValueKey('floor-activity-$id'),
                  label: studyActivityById(id)!.title,
                  detail: progress.active?.activityId == id
                      ? 'Continue activity'
                      : progress.isUnlocked(id) && !career.canOpen(id)
                      ? progress.completions.containsKey(id)
                            ? 'Saved · Finish your current activity first'
                            : 'Finish your current activity first'
                      : progress.completions.containsKey(id)
                      ? 'Saved · Try again'
                      : progress.isUnlocked(id)
                      ? 'Ready to start'
                      : 'Complete the previous activity first',
                  glyph: progress.completions.containsKey(id)
                      ? 'check'
                      : 'report',
                  fill: Colors.white,
                  ink: StudyColor.pine,
                  base: StudyColor.line,
                  outlined: true,
                  onPressed:
                      opening ||
                          repository.loadIssue != null ||
                          !career.canOpen(id)
                      ? null
                      : () => Navigator.pop(sheetContext, id),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
            ],
            CraftButton(
              label: 'Back to your office',
              onPressed: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
    if (activityId != null && context.mounted) {
      await openActivity(context, studyActivityById(activityId));
    }
  }

  /// The top-right badge. Its meaning is unchanged: how much practice is
  /// filed. What changes is that the bell is a real control when there is an
  /// account, opening that account's invitations.
  ///
  /// This is an entry point, not a notification. Nothing polls, so the office
  /// does not claim to know that something is waiting.
  Widget _noticeBadge(BuildContext context) {
    final invitations = widget.accountController?.invitationsController;
    final label = completed
        ? 'Activities completed: ${progress.completions.length}'
        : 'Your first activity is ready';
    final badge = ExcludeSemantics(
      child: Row(
        children: [
          const CraftGlyph('bell', size: 26),
          const SizedBox(width: 6),
          Text(
            completed ? '${progress.completions.length}' : 'Ready',
            style: display(15),
          ),
        ],
      ),
    );
    if (invitations == null) {
      return Semantics(label: label, child: badge);
    }
    return Semantics(
      label: '$label. Opens your invitations.',
      button: true,
      child: ExcludeSemantics(
        child: InkWell(
          key: const ValueKey('office-notices'),
          onTap: () {
            launchIntent++;
            invitationsSheet(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: badge,
          ),
        ),
      ),
    );
  }

  /// The invitations panel in its own sheet, reachable from the office.
  Future<void> invitationsSheet(BuildContext context) async {
    final invitations = widget.accountController?.invitationsController;
    if (invitations == null) return;
    final relationships = widget.accountController?.relationshipsController;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      useSafeArea: true,
      backgroundColor: StudyColor.paper,
      shape: studyShape(28),
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: relationships == null
            ? InvitationsPanel(controller: invitations)
            : RelationshipsPanel(
                relationships: relationships,
                invitations: invitations,
              ),
      ),
    );
  }

  /// Public stock prices in their own sheet. No account is needed to look, so
  /// this is offered whether or not anyone is signed in.
  Future<void> stockPricesSheet(BuildContext context) async {
    final scope = StockResearchScope.maybeOf(context, listen: false);
    if (scope == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      useSafeArea: true,
      backgroundColor: StudyColor.paper,
      shape: studyShape(28),
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          32 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: StockResearchPanel(
          controller: scope.controller,
          configurationFailed: scope.configurationFailed,
          // Null for a guest, so keeping is simply absent rather than offered
          // and then refused.
          following: widget.accountController?.followedStocksController,
        ),
      ),
    );
  }

  Future<void> settings(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .88,
    ),
    useSafeArea: true,
    backgroundColor: StudyColor.paper,
    shape: studyShape(28),
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, localSetState) => SingleChildScrollView(
        child: Padding(
          // Keep the account form above the keyboard when a field is focused.
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            32 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Settings', style: display(26)),
              ),
              const SizedBox(height: 20),
              AccountSettings(
                controller: widget.accountController,
                configurationFailed: widget.accountConfigurationFailed,
              ),
              if (StockResearchScope.maybeOf(context, listen: false) != null)
                ListTile(
                  key: const ValueKey('settings-stock-prices'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Stock prices'),
                  subtitle: const Text(
                    'Look up what a provider lists. Reading only.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => stockPricesSheet(context),
                ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reduce motion'),
                subtitle: const Text('Keep every result. Skip the movement.'),
                value: reduceMotion,
                onChanged: (value) async {
                  setState(() => reduceMotion = value);
                  localSetState(() {});
                  try {
                    final saved = await widget.preferences.setBool(
                      motionKey,
                      value,
                    );
                    if (!saved) throw StateError('Preference save failed');
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Motion is changed for this session, but the setting could not be saved.',
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sound'),
                subtitle: const Text(
                  'Soft feedback for paper, choices and saved answers.',
                ),
                value: soundEnabled,
                onChanged: (value) async {
                  setState(() => soundEnabled = value);
                  audio.setEnabled(value);
                  localSetState(() {});
                  try {
                    final saved = await widget.preferences.setBool(
                      soundKey,
                      value,
                    );
                    if (!saved) throw StateError('Preference save failed');
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Sound is changed for this session, but the setting could not be saved.',
                        ),
                      ),
                    );
                  }
                },
              ),
              if (soundEnabled)
                TextButton.icon(
                  onPressed: () => audio.play(StudySound.paper),
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text('Preview sound'),
                ),
              const SizedBox(height: 18),
              CraftButton(
                label: 'Done',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
