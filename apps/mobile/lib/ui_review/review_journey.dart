import 'package:flutter/material.dart';

import 'review_account_money_pages.dart';
import 'review_animated_splash.dart';
import 'review_career_social_pages.dart';
import 'review_components.dart';
import 'review_followup_questions.dart';
import 'review_first_play.dart';
import 'review_first_desk.dart';
import 'review_optional_setup.dart';
import 'review_market_pages.dart';
import 'review_onboarding_pages.dart';
import 'review_welcome_note.dart';
import 'ui_review_app.dart';
import 'welcome_review_screen.dart';

enum ReviewPageId {
  coldLaunch,
  welcome,
  welcomeNote,
  goal,
  knowledge,
  persona,
  handle,
  starterMarket,
  marketSearch,
  stockPage,
  buyAmount,
  buyReview,
  tradeReport,
  firstPosition,
  streak,
  notifications,
  saveDesk,
  desk,
  portfolio,
  inbox,
  marketBrowse,
  ownedStock,
  reasons,
  holders,
  about,
  priceAlert,
  trimAmount,
  trimReview,
  career,
  lessonLibrary,
  lessonPlay,
  liveEvent,
  missionComplete,
  weeklyReport,
  promotion,
  trophies,
  feed,
  league,
  profile,
  shareCard,
  friends,
  signIn,
  email,
  emailCode,
  guestRecovery,
  preservedDesk,
  settings,
  notificationSettings,
  experienceSettings,
  privacy,
  reportBlock,
  paperReset,
  moneyIntroduction,
  moneyEligibility,
  depositMethod,
  depositAmount,
  depositReview,
  depositReceipt,
  moneyTradeAmount,
  moneyTradeReview,
  moneySigning,
  moneyPending,
  moneyTradeReceipt,
  withdrawAmount,
  withdrawAccount,
  withdrawReview,
  withdrawReceipt,
  walletTools,
  supportLegal,
  closeAccount,
  widgetSetup,
  complete,
}

extension ReviewPageIdLabel on ReviewPageId {
  String get label => switch (this) {
    ReviewPageId.coldLaunch => 'Cold launch',
    ReviewPageId.welcome => 'Welcome',
    ReviewPageId.welcomeNote => 'Welcome note',
    ReviewPageId.goal => 'Goal (archived questionnaire)',
    ReviewPageId.knowledge => 'Knowledge (archived questionnaire)',
    ReviewPageId.persona => 'Persona',
    ReviewPageId.handle => 'Username',
    ReviewPageId.notifications => 'Notification primer',
    ReviewPageId.starterMarket => 'First practice decision',
    ReviewPageId.marketSearch => 'Market search',
    ReviewPageId.stockPage => 'Company page',
    ReviewPageId.buyAmount => 'Buy amount',
    ReviewPageId.buyReview => 'Buy review',
    ReviewPageId.tradeReport => 'Trade report',
    ReviewPageId.firstPosition => 'First result and Day 1',
    ReviewPageId.streak => 'Day 1 (archived ceremony)',
    ReviewPageId.saveDesk => 'Save your desk',
    ReviewPageId.desk => 'Desk',
    ReviewPageId.portfolio => 'Portfolio',
    ReviewPageId.inbox => 'Inbox',
    ReviewPageId.marketBrowse => 'Market browse',
    ReviewPageId.ownedStock => 'Owned stock',
    ReviewPageId.reasons => 'Reasons',
    ReviewPageId.holders => 'Holders',
    ReviewPageId.about => 'About',
    ReviewPageId.priceAlert => 'Price alert',
    ReviewPageId.trimAmount => 'Trim amount',
    ReviewPageId.trimReview => 'Trim review',
    ReviewPageId.career => 'Career path',
    ReviewPageId.lessonLibrary => 'Lesson library',
    ReviewPageId.lessonPlay => 'Lesson play',
    ReviewPageId.liveEvent => 'Live event',
    ReviewPageId.missionComplete => 'Mission complete',
    ReviewPageId.weeklyReport => 'Weekly report',
    ReviewPageId.promotion => 'Promotion',
    ReviewPageId.trophies => 'Trophies',
    ReviewPageId.feed => 'Floor Feed',
    ReviewPageId.league => 'League',
    ReviewPageId.profile => 'Profile',
    ReviewPageId.shareCard => 'Career share card',
    ReviewPageId.friends => 'Friends',
    ReviewPageId.signIn => 'Sign-in methods',
    ReviewPageId.email => 'Email address',
    ReviewPageId.emailCode => 'Email code',
    ReviewPageId.guestRecovery => 'Guest recovery',
    ReviewPageId.preservedDesk => 'Preserved desk',
    ReviewPageId.settings => 'Settings',
    ReviewPageId.notificationSettings => 'Notification settings',
    ReviewPageId.experienceSettings => 'Sound, haptics and motion',
    ReviewPageId.privacy => 'Privacy',
    ReviewPageId.reportBlock => 'Report and block',
    ReviewPageId.paperReset => 'Paper reset',
    ReviewPageId.moneyIntroduction => 'Money introduction',
    ReviewPageId.moneyEligibility => 'Country and risk',
    ReviewPageId.depositMethod => 'Deposit method',
    ReviewPageId.depositAmount => 'Deposit amount',
    ReviewPageId.depositReview => 'Deposit review',
    ReviewPageId.depositReceipt => 'Deposit receipt',
    ReviewPageId.moneyTradeAmount => 'Money trade amount',
    ReviewPageId.moneyTradeReview => 'Money trade review',
    ReviewPageId.moneySigning => 'Money signing',
    ReviewPageId.moneyPending => 'Money pending',
    ReviewPageId.moneyTradeReceipt => 'Money trade receipt',
    ReviewPageId.withdrawAmount => 'Withdraw amount',
    ReviewPageId.withdrawAccount => 'Withdraw account',
    ReviewPageId.withdrawReview => 'Withdraw review',
    ReviewPageId.withdrawReceipt => 'Withdraw receipt',
    ReviewPageId.walletTools => 'Wallet tools',
    ReviewPageId.supportLegal => 'Support and legal',
    ReviewPageId.closeAccount => 'Close account',
    ReviewPageId.widgetSetup => 'Home screen widget preview',
    ReviewPageId.complete => 'Review index complete',
  };
}

class ReviewJourney extends StatefulWidget {
  const ReviewJourney({super.key, this.initialPage, this.startupReady});

  final int? initialPage;
  final Future<void>? startupReady;

  @override
  State<ReviewJourney> createState() => _ReviewJourneyState();
}

class _ReviewJourneyState extends State<ReviewJourney> {
  static const requestedPage = int.fromEnvironment(
    'TRIMMY_REVIEW_PAGE',
    defaultValue: 0,
  );

  late int index;
  final List<ReviewPageId> history = [];
  String? selectedPersona;
  String username = '';
  String reason = '';
  ReviewPracticePosition? position;
  String? personaDraft;
  bool welcomeHasBeenShown = false;

  @override
  void initState() {
    super.initState();
    index = (widget.initialPage ?? requestedPage).clamp(
      0,
      ReviewPageId.values.length - 1,
    );
  }

  ReviewPageId get page => ReviewPageId.values[index];

  // Explicit routes own the first-day flow. Enum order is only a screen gallery.
  void next() {
    if (index < ReviewPageId.values.length - 1) {
      jump(ReviewPageId.values[index + 1]);
    }
  }

  // Back edits within a flow. At a flow boundary it returns to the Desk,
  // never to a dismissed introduction or to an earlier gallery index.
  void back() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_isRoot) return;
    if (page == ReviewPageId.welcomeNote ||
        page == ReviewPageId.starterMarket ||
        page == ReviewPageId.firstPosition ||
        page == ReviewPageId.persona ||
        page == ReviewPageId.goal ||
        page == ReviewPageId.knowledge) {
      openDesk();
      return;
    }
    if (history.isNotEmpty) {
      setState(() => index = history.removeLast().index);
      return;
    }
    final parent = switch (page) {
      ReviewPageId.buyReview => ReviewPageId.buyAmount,
      ReviewPageId.buyAmount => ReviewPageId.stockPage,
      ReviewPageId.stockPage ||
      ReviewPageId.marketSearch => ReviewPageId.marketBrowse,
      ReviewPageId.trimReview => ReviewPageId.trimAmount,
      ReviewPageId.trimAmount ||
      ReviewPageId.reasons ||
      ReviewPageId.holders ||
      ReviewPageId.about ||
      ReviewPageId.priceAlert => ReviewPageId.ownedStock,
      ReviewPageId.lessonPlay => ReviewPageId.lessonLibrary,
      ReviewPageId.lessonLibrary ||
      ReviewPageId.liveEvent => ReviewPageId.career,
      _ => ReviewPageId.desk,
    };
    jump(parent, replace: true);
  }

  bool get _isRoot =>
      history.isEmpty &&
      (page == ReviewPageId.coldLaunch ||
          page == ReviewPageId.welcome ||
          page == ReviewPageId.desk);

  void skipIntroduction() => openDesk();

  void jump(ReviewPageId target, {bool replace = false}) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (page == ReviewPageId.welcome) welcomeHasBeenShown = true;
      if (replace) {
        history.clear();
      } else {
        history.add(page);
      }
      index = target.index;
    });
  }

  void openDesk() {
    personaDraft = null;
    jump(ReviewPageId.desk, replace: true);
  }

  void finishPersona() {
    selectedPersona = personaDraft ?? selectedPersona;
    openDesk();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: _isRoot,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) back();
    },
    child: AnimatedSwitcher(
      duration: uiReviewDuration(context, 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.025, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(page), child: _screen(page)),
    ),
  );

  Widget _screen(ReviewPageId id) => switch (id) {
    ReviewPageId.coldLaunch => ReviewColdLaunchPage(
      onContinue: () => jump(ReviewPageId.welcome, replace: true),
      ready: widget.startupReady,
    ),
    ReviewPageId.welcome => WelcomeReviewScreen(
      playEntrance: !welcomeHasBeenShown,
      onStart: () => jump(ReviewPageId.welcomeNote, replace: true),
      onHaveAccount: () => jump(ReviewPageId.signIn),
    ),
    ReviewPageId.welcomeNote => ReviewWelcomeNotePage(
      onSkip: skipIntroduction,
      onContinue: () => jump(ReviewPageId.starterMarket, replace: true),
    ),
    ReviewPageId.goal => ReviewQuestionPage(
      onBack: back,
      onSkip: skipIntroduction,
      onContinue: next,
    ),
    ReviewPageId.knowledge => ReviewKnowledgeQuestion(
      onSkip: skipIntroduction,
      onContinue: next,
    ),
    ReviewPageId.persona => ReviewPersonaQuestion(
      onSkip: openDesk,
      onContinue: finishPersona,
      initialSelection: selectedPersona,
      onSelected: (value) => personaDraft = value,
    ),
    ReviewPageId.handle => ReviewHandleQuestion(
      persona: selectedPersona ?? 'oracle',
      initialName: username,
      onNameChanged: (value) => username = value,
      onSkip: openDesk,
      onContinue: () => jump(ReviewPageId.saveDesk),
    ),
    ReviewPageId.notifications => ReviewReminderInvitation(onClose: openDesk),
    ReviewPageId.starterMarket => ReviewFirstPlayPage(
      onExit: openDesk,
      initialPosition: position,
      onComplete: (value) {
        position = value;
        reason = '';
        jump(ReviewPageId.firstPosition, replace: true);
      },
    ),
    ReviewPageId.marketSearch => ReviewMarketPage(
      mode: ReviewMarketMode.search,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.stockPage => ReviewStockPage(
      owned: false,
      tab: ReviewStockTab.overview,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.buyAmount => ReviewTradeTicketPage(
      kind: ReviewTicketKind.buy,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.buyReview => ReviewOrderReviewPage(
      selling: false,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.tradeReport => ReviewTradeReportPage(onContinue: openDesk),
    ReviewPageId.firstPosition =>
      position == null
          ? _desk()
          : ReviewFirstDayResultPage(position: position!, onContinue: openDesk),
    ReviewPageId.streak => ReviewStreakPage(onContinue: openDesk),
    ReviewPageId.saveDesk => ReviewAccountOptionsPage(
      onClose: openDesk,
      username: username,
    ),
    ReviewPageId.desk => _desk(),
    ReviewPageId.portfolio => ReviewPortfolioPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.inbox => ReviewInboxPage(onBack: back, onContinue: next),
    ReviewPageId.marketBrowse => ReviewMarketPage(
      mode: ReviewMarketMode.browse,
      onBack: back,
      onContinue: () => jump(ReviewPageId.stockPage),
    ),
    ReviewPageId.ownedStock => ReviewStockPage(
      owned: true,
      tab: ReviewStockTab.overview,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.reasons => ReviewStockPage(
      owned: true,
      tab: ReviewStockTab.reasons,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.holders => ReviewStockPage(
      owned: true,
      tab: ReviewStockTab.holders,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.about => ReviewStockPage(
      owned: true,
      tab: ReviewStockTab.about,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.priceAlert => ReviewPriceAlertPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.trimAmount => ReviewTradeTicketPage(
      kind: ReviewTicketKind.trim,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.trimReview => ReviewOrderReviewPage(
      selling: true,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.career => ReviewCareerPage(onContinue: next),
    ReviewPageId.lessonLibrary => ReviewLessonLibraryPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.lessonPlay => ReviewLessonPlayPage(
      onBack: back,
      onContinue: () => jump(ReviewPageId.missionComplete),
    ),
    ReviewPageId.liveEvent => ReviewLiveEventPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.missionComplete => ReviewMissionCompletePage(
      onContinue: () => jump(ReviewPageId.career, replace: true),
    ),
    ReviewPageId.weeklyReport => ReviewWeeklyReportPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.promotion => ReviewPromotionPage(onContinue: next),
    ReviewPageId.trophies => ReviewTrophiesPage(onBack: back, onContinue: next),
    ReviewPageId.feed => ReviewFeedPage(onContinue: next),
    ReviewPageId.league => ReviewLeaguePage(onContinue: next),
    ReviewPageId.profile => ReviewProfilePage(onContinue: next),
    ReviewPageId.shareCard => ReviewShareCardPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.friends => ReviewFriendsPage(onBack: back, onContinue: next),
    ReviewPageId.signIn => ReviewAccountOptionsPage(
      signIn: true,
      onClose: back,
    ),
    ReviewPageId.email => ReviewEmailPage(
      code: false,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.emailCode => ReviewEmailPage(
      code: true,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.guestRecovery => ReviewRecoveryPage(
      preserved: false,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.preservedDesk => ReviewRecoveryPage(
      preserved: true,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.settings => ReviewSettingsHubPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.notificationSettings => ReviewPreferencesPage(
      kind: ReviewPreferencesKind.notifications,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.experienceSettings => ReviewPreferencesPage(
      kind: ReviewPreferencesKind.experience,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.privacy => ReviewPreferencesPage(
      kind: ReviewPreferencesKind.privacy,
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.reportBlock => ReviewReportBlockPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.paperReset => ReviewPaperResetPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.moneyIntroduction => _money(ReviewMoneyStep.introduction),
    ReviewPageId.moneyEligibility => _money(ReviewMoneyStep.eligibility),
    ReviewPageId.depositMethod => _money(ReviewMoneyStep.depositMethod),
    ReviewPageId.depositAmount => _money(ReviewMoneyStep.depositAmount),
    ReviewPageId.depositReview => _money(ReviewMoneyStep.depositReview),
    ReviewPageId.depositReceipt => _money(ReviewMoneyStep.depositReceipt),
    ReviewPageId.moneyTradeAmount => _money(ReviewMoneyStep.tradeAmount),
    ReviewPageId.moneyTradeReview => _money(ReviewMoneyStep.tradeReview),
    ReviewPageId.moneySigning => _money(ReviewMoneyStep.signing),
    ReviewPageId.moneyPending => _money(ReviewMoneyStep.pending),
    ReviewPageId.moneyTradeReceipt => _money(ReviewMoneyStep.tradeReceipt),
    ReviewPageId.withdrawAmount => _money(ReviewMoneyStep.withdrawAmount),
    ReviewPageId.withdrawAccount => _money(ReviewMoneyStep.withdrawAccount),
    ReviewPageId.withdrawReview => _money(ReviewMoneyStep.withdrawReview),
    ReviewPageId.withdrawReceipt => _money(ReviewMoneyStep.withdrawReceipt),
    ReviewPageId.walletTools => ReviewWalletPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.supportLegal => ReviewSupportPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.closeAccount => ReviewCloseAccountPage(
      onBack: back,
      onContinue: next,
    ),
    ReviewPageId.widgetSetup => ReviewWidgetInvitation(onClose: openDesk),
    ReviewPageId.complete => _ReviewCompletePage(
      onRestart: () => jump(ReviewPageId.coldLaunch),
    ),
  };

  Widget _desk() => ReviewFirstDeskPage(
    position: position,
    persona: selectedPersona ?? 'oracle',
    username: username.isEmpty ? null : username,
    initialReason: reason,
    onReasonChanged: (value) => reason = value,
    onSaveProgress: () => jump(ReviewPageId.handle),
    onReminder: () => jump(ReviewPageId.notifications),
    onWidget: () => jump(ReviewPageId.widgetSetup),
    onPersona: () {
      personaDraft = selectedPersona;
      jump(ReviewPageId.persona);
    },
    onStartPractice: () => jump(ReviewPageId.starterMarket),
    onOpenCareer: () => jump(ReviewPageId.career),
    onExplore: () => jump(ReviewPageId.marketBrowse),
  );

  Widget _money(ReviewMoneyStep step) =>
      ReviewMoneyPage(step: step, onBack: back, onContinue: next);
}

class _ReviewCompletePage extends StatelessWidget {
  const _ReviewCompletePage({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => ReviewPageScaffold(
    eyebrow: '72 reviewable surfaces',
    title: 'The mobile UI map is complete.',
    subtitle:
        'These are deterministic visual foundations. Product truth stays in the sealed production contracts.',
    background: UiReviewColor.mint,
    bottom: ReviewPrimaryButton(
      label: 'Return to cold launch',
      onPressed: onRestart,
    ),
    child: const Column(
      children: [
        ReviewSal(mood: 'proud', width: 224),
        SizedBox(height: 14),
        ReviewPaper(
          shadow: false,
          child: Text(
            'Review from the beginning. Approve one screen, record its decisions, then move to the next.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}
