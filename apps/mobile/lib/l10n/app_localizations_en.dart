// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonDone => 'Done';

  @override
  String get commonClose => 'Close';

  @override
  String get commonBack => 'Back';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSignIn => 'Sign in';

  @override
  String get commonMax => 'Max';

  @override
  String get commonBuy => 'Buy';

  @override
  String get commonSell => 'Sell';

  @override
  String get rankRookie => 'Rookie';

  @override
  String get rankAnalyst => 'Analyst';

  @override
  String get rankTrader => 'Trader';

  @override
  String get rankSeniorTrader => 'Senior Trader';

  @override
  String get rankPartner => 'Partner';

  @override
  String get rankLegend => 'Legend';

  @override
  String formatCompactThousand(String value) {
    return '${value}K';
  }

  @override
  String formatCompactMillion(String value) {
    return '${value}M';
  }

  @override
  String formatCompactBillion(String value) {
    return '${value}B';
  }

  @override
  String formatCompactTrillion(String value) {
    return '${value}T';
  }

  @override
  String get marketPriceUnavailable => 'Price unavailable';

  @override
  String get commonAddMoney => 'Add money';

  @override
  String get commonSaving => 'Saving…';

  @override
  String get commonChecking => 'Checking…';

  @override
  String get commonConnecting => 'Connecting…';

  @override
  String get commonSending => 'Sending…';

  @override
  String get commonConfirming => 'Confirming…';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonNotNow => 'Not now';

  @override
  String get commonSkip => 'Skip';

  @override
  String get commonHistory => 'History';

  @override
  String get commonSettings => 'Settings';

  @override
  String commonInProgress(String label) {
    return '$label in progress';
  }

  @override
  String get modePaper => 'Paper';

  @override
  String get modeReal => 'Real';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguagePhone => 'Phone language';

  @override
  String get settingsLanguagePhoneDetail =>
      'Uses the language your phone is set to.';

  @override
  String get appGuestChoiceNotSaved => 'Couldn’t save your choice. Try again.';

  @override
  String get appDeskAlreadySaved => 'Your desk is already saved.';

  @override
  String get appDeskReconnecting =>
      'Your desk is reconnecting. Try again in a moment.';

  @override
  String get appSwitchedToPaper => 'Switched to Paper.';

  @override
  String get appReasonBeingChecked =>
      'Your saved reason is being checked. Refresh your Career.';

  @override
  String get appReasonNeedsPaperDesk =>
      'Your confirmed paper desk must be online before you can write this reason.';

  @override
  String get appReasonNeedsPaperBuy =>
      'This mission needs a confirmed paper buy you still hold. Choose a stock when you are ready.';

  @override
  String get appPromotionRefreshFirst =>
      'Refresh the Floor before claiming this promotion.';

  @override
  String get appPromotionNotPrepared =>
      'Your promotion could not be prepared. Try again.';

  @override
  String get appPromotionCareerChanged =>
      'Your career changed. Refresh the Floor and try again.';

  @override
  String get appPaperDeskStillOpening =>
      'Your paper desk is still opening. Try again.';

  @override
  String get appFirstTradeStepNotSaved =>
      'The trade is safe, but this step was not saved.';

  @override
  String get appStockCouldNotOpen => 'This stock couldn’t open. Try again.';

  @override
  String get appHistoryCouldNotConnect =>
      'History couldn’t connect. Try again.';

  @override
  String get appReportNotSent => 'Report didn’t send. Try again.';

  @override
  String get appBlockFailed => 'Couldn’t block this trader. Try again.';

  @override
  String get appWalletAddressCopied => 'Wallet address copied.';

  @override
  String get appWalletBackupFailed => 'Couldn’t open wallet backup. Try again.';

  @override
  String get appPaperDeskOpening => 'Opening your paper desk.';

  @override
  String get appPaperDeskOffline =>
      'Your paper desk is offline. Check your connection and try again.';

  @override
  String get appPaperDeskTimeout =>
      'Your paper desk took too long to open. Try again.';

  @override
  String get appPaperDeskSession =>
      'Your paper desk needs a fresh session. Try again.';

  @override
  String get appPaperDeskUnavailable =>
      'Your paper desk is unavailable. Try again.';

  @override
  String get appCareerStale =>
      'Showing your last confirmed career record. Refresh to update it.';

  @override
  String get appMissionsMismatch =>
      'Your career changed while missions were loading. Refresh to match them.';

  @override
  String get appMissionsStale =>
      'Showing your last confirmed missions. Refresh to update them.';

  @override
  String get appMissionsOffline =>
      'Your missions are offline. Check your connection and try again.';

  @override
  String get appMissionsTimeout =>
      'Your missions took too long to open. Try again.';

  @override
  String get appMissionsSession =>
      'Your missions need a fresh session. Try again.';

  @override
  String get appMissionsRateLimited =>
      'Your missions are refreshing too quickly. Try again shortly.';

  @override
  String get appMissionsProfileRequired =>
      'Finish setting up your Trimmy profile, then try again.';

  @override
  String get appMissionsUnavailable =>
      'Your missions are unavailable. Try again.';

  @override
  String get appProfileUnavailable =>
      'Your Trimmy profile is unavailable. Try again.';

  @override
  String get appAccountEntryFailed =>
      'Your account is connected. Try opening your desk again.';

  @override
  String get appRealBalanceLabel => 'Total balance';

  @override
  String get appRealBalanceUpdating => 'Updating balance…';

  @override
  String get appRealBalanceUsdcAvailable => 'USDC available';

  @override
  String appRealBalanceSplit(String cash, String stocks) {
    return '$cash cash · $stocks in stocks';
  }

  @override
  String get appDeskStaleBoth =>
      'Showing your last confirmed paper desk and career record. Trading is paused until Trimmy reconnects.';

  @override
  String get appDeskStalePaper =>
      'Showing your last confirmed paper desk. Trading is paused until Trimmy reconnects.';

  @override
  String get appTradingCouldNotConnect => 'Trading could not connect.';

  @override
  String get appTradingChecking => 'Checking trading…';

  @override
  String get appTradingPaused => 'Trading is temporarily paused.';

  @override
  String get appTradingNotTradeable => 'Not tradeable with real money yet.';

  @override
  String get appVersionIssuerUnavailable => 'Issuer unavailable';

  @override
  String get appVersionBackingUnavailable =>
      'Backing details are not available in this market read.';

  @override
  String get appVersionTradingHoursUnavailable =>
      'Trades on chain. Issuer hours are unavailable.';

  @override
  String get appRealMissionTitle => 'A simulator assignment';

  @override
  String get appRealMissionBody => 'Complete this task on your training desk.';

  @override
  String get appRealMissionButton => 'Open training desk';

  @override
  String get appCloseAccountTitle => 'Close your account?';

  @override
  String get appCloseAccountBodyNoWallet =>
      'You will lose access to the saved account. Records that must be kept stay protected.';

  @override
  String get appCloseAccountBodyWallet =>
      'Keep access to your wallet before closing your account. Closing will not move its funds. You will lose access to your saved desk.';

  @override
  String get appCloseAccountBackUpWallet => 'Back up wallet';

  @override
  String get appCloseAccountConfirm => 'Close account';

  @override
  String get appFirstTradePrompt => 'Pick a company. Your first trade is free.';

  @override
  String get appOpeningTrimmy => 'Opening Trimmy';

  @override
  String get appCouldNotOpenTrimmy => 'Couldn’t open Trimmy';

  @override
  String get appOpeningDesk => 'Opening your desk';

  @override
  String get appCouldNotOpenDesk => 'Couldn’t open your desk';

  @override
  String get appOpeningTrade => 'Opening your trade';

  @override
  String get appCouldNotLoadTrade => 'Couldn’t load your trade';

  @override
  String get appCouldNotLoadTradeBody =>
      'Try again to see your confirmed order.';

  @override
  String get appSplashOpening => 'Trimmy is opening';

  @override
  String get designCastSal => 'Sal, your floor boss';

  @override
  String get designCastWolf => 'The Wolf trader portrait';

  @override
  String get designCastOracle => 'The Oracle trader portrait';

  @override
  String get designCastShark => 'The Shark trader portrait';

  @override
  String get designPaperMark => 'paper';

  @override
  String designPaperAmount(String amount) {
    return '$amount paper';
  }

  @override
  String get designUseRealMoney => 'Use real money';

  @override
  String get designDismissMessage => 'Dismiss message';

  @override
  String get designCompleted => 'Completed';

  @override
  String appPromotionTitle(String rankId, String rank) {
    String _temp0 = intl.Intl.selectLogic(rankId, {
      'analyst': 'You’re an $rank!',
      'other': 'You’re a $rank!',
    });
    return '$_temp0';
  }

  @override
  String get appPromotionMessage => 'A new chapter on the floor.';

  @override
  String get appPromotionFrom => 'From';

  @override
  String get appPromotionNewRank => 'New rank';

  @override
  String get appPromotionEarned => 'Earned';

  @override
  String appPromotionTrims(String trims) {
    return '$trims Trims';
  }

  @override
  String get appPromotionBackToCareer => 'Back to Career';

  @override
  String get appFirstPositionTitle => 'Your first position.';

  @override
  String get appFirstPositionMessage => 'You’ve placed your first order!';

  @override
  String get appFirstPositionStock => 'Stock';

  @override
  String get appFirstPositionShares => 'Shares';

  @override
  String get appFirstPositionTime => 'Time';

  @override
  String appFirstPositionTimeUtc(String time) {
    return '$time UTC';
  }

  @override
  String get appDayOneTitle => 'Day 1, done.';

  @override
  String get appDayOneMessage => 'See you on the floor tomorrow.';

  @override
  String get appSessionGuestRecovery => 'This guest desk needs recovery.';

  @override
  String get appSessionAnswersNotSaved =>
      'Your answers could not be saved. Try once more.';

  @override
  String get appSessionStepNotSaved =>
      'That step could not be saved. Try again.';

  @override
  String get appSessionSetupUnreadable =>
      'Your Trimmy setup could not be opened. Start it again.';

  @override
  String get appSessionReadOffline =>
      'Your profile is offline. Check your connection and try again.';

  @override
  String get appSessionReadTimeout =>
      'Your profile took too long to open. Try again.';

  @override
  String get appSessionReadSession =>
      'Your profile needs a fresh session. Try again.';

  @override
  String get appSessionReadUnavailable =>
      'Your profile is unavailable. Try again.';

  @override
  String get appSessionHandleTaken =>
      'That floor name is taken. Choose another one.';

  @override
  String get appSessionTradeRequired =>
      'Your confirmed trade must reach the desk before this step can continue.';

  @override
  String get appSessionNotReady =>
      'Trimmy is still confirming that moment. Try again.';

  @override
  String get appSessionPrincipalChanged =>
      'Your desk identity changed. Open it again and retry.';

  @override
  String get appSessionConflict =>
      'Your profile changed on another device. Try again.';

  @override
  String get appSessionWriteOffline =>
      'You are offline. Reconnect and try again.';

  @override
  String get appSessionWriteTimeout => 'That took too long. Try again.';

  @override
  String get appSessionWriteSession =>
      'Your session changed. Open your profile again.';

  @override
  String get appSessionWriteFailed => 'That step was not saved. Try again.';

  @override
  String get appMarketLoadMoreFailed =>
      'Could not load more stocks. Try again.';

  @override
  String get appMarketCatalogFailed =>
      'Stocks could not load. Pull down to try again.';

  @override
  String get appMarketNoStarterPicks =>
      'Starter picks are unavailable. Search by company or symbol.';

  @override
  String get appMarketNotConfigured =>
      'Market data is not configured in this build.';

  @override
  String get appMarketBusy => 'Market data is busy. Try again in a moment.';

  @override
  String get appMarketTimeout => 'Market data took too long. Try again.';

  @override
  String get appMarketOffline =>
      'You are offline. Check your connection and try again.';

  @override
  String get appMarketUnavailable => 'Stocks could not load. Try again.';

  @override
  String get tabDesk => 'Desk';

  @override
  String get tabMarket => 'Market';

  @override
  String get tabCareer => 'Career';

  @override
  String get tabProfile => 'Profile';

  @override
  String get firstTradeSkip => 'Skip first trade';

  @override
  String get firstTradeTitle => 'Your first move.';

  @override
  String get firstTradeOpeningDesk => 'Opening your paper desk…';

  @override
  String get firstTradeDeskUnavailable =>
      'Your paper desk is unavailable. Try again.';

  @override
  String get firstTradeContinueError => 'Couldn’t continue. Try again.';

  @override
  String get firstTradePickCompany => 'Pick a company.';

  @override
  String get firstTradeHint => 'Hint';

  @override
  String get firstTradeCompanyGuide =>
      'A share is a small piece of a company. Pick one.';

  @override
  String get firstTradeAmountTitle => 'Select price';

  @override
  String get firstTradeAmountGuide => 'Pick an amount to try. It’s free.';

  @override
  String get firstTradeReviewBuy => 'Review buy';

  @override
  String get firstTradeOrderPlaced => 'You’ve placed your first order!';

  @override
  String get firstTradeCreateProfile => 'Now let’s create your trader profile.';

  @override
  String get firstTradeBuyConfirmed => 'Buy confirmed';

  @override
  String get firstTradeInvested => 'Invested';

  @override
  String firstTradeSharesLine(String shares) {
    return 'Shares  $shares';
  }

  @override
  String firstTradeTrimsEarned(String trims) {
    return '+$trims Trims';
  }

  @override
  String get firstTradeKeepFreeMoney => 'Keep using free money';

  @override
  String get firstTradeKeepFreeMoneyDetail =>
      'Build your confidence on the desk.';

  @override
  String firstTradeSharesCount(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares shares',
    );
    return '$_temp0';
  }

  @override
  String firstTradeFreeMoneyAmount(String amount) {
    return '$amount free money';
  }

  @override
  String get firstTradeNextMove => 'Your next move.';

  @override
  String get firstTradeNextMoveBody =>
      'Keep finding your feet, or fund your wallet.';

  @override
  String get firstTradeAddMoneyDetail => 'See your deposit options.';

  @override
  String get firstTradeAddMoneyLater =>
      'You can add money from your desk any time.';

  @override
  String get firstTradeContinueSafe =>
      'Your trade is safe. Try continuing again.';

  @override
  String get amountPickerErrorEmpty => 'Enter an amount.';

  @override
  String get amountPickerErrorDecimals => 'Use up to 2 decimal places.';

  @override
  String amountPickerErrorMin(String amount) {
    return 'Choose at least $amount.';
  }

  @override
  String amountPickerErrorMax(String amount) {
    return 'Choose up to $amount.';
  }

  @override
  String get amountPickerFieldLabel => 'Amount in dollars';

  @override
  String amountPickerEditSemantics(num value, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      value,
      locale: localeName,
      other: 'Amount, $amount dollars. Edit amount',
    );
    return '$_temp0';
  }

  @override
  String amountPickerDecreaseTooltip(num step, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      step,
      locale: localeName,
      other: 'Decrease amount by $amount dollars',
    );
    return '$_temp0';
  }

  @override
  String amountPickerIncreaseTooltip(num step, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      step,
      locale: localeName,
      other: 'Increase amount by $amount dollars',
    );
    return '$_temp0';
  }

  @override
  String amountPickerPresetSemantics(num amount, String amountText) {
    String _temp0 = intl.Intl.pluralLogic(
      amount,
      locale: localeName,
      other: 'Set amount to $amountText dollars',
    );
    return '$_temp0';
  }

  @override
  String get onboardingGoalLearn => 'Learn';

  @override
  String get onboardingGoalLearnDetail => 'Start with the basics.';

  @override
  String get onboardingGoalPractice => 'Practice';

  @override
  String get onboardingGoalPracticeDetail => 'Make calls with paper.';

  @override
  String get onboardingGoalTrade => 'Trade with paper';

  @override
  String get onboardingGoalTradeDetail => 'Build confidence at live prices.';

  @override
  String get onboardingGoalFriends => 'Friends';

  @override
  String get onboardingGoalFriendsDetail => 'Leagues are not available yet.';

  @override
  String get onboardingKnowledgeNothing => 'Nothing yet';

  @override
  String get onboardingKnowledgeBasics => 'I know the basics';

  @override
  String get onboardingKnowledgePractised => 'I have practised';

  @override
  String get onboardingKnowledgeTraded => 'I have traded before';

  @override
  String get onboardingKnowledgeDaily => 'I trade every day';

  @override
  String get onboardingDailyShowUp => 'Show up';

  @override
  String get onboardingDailyShowUpDetail => 'Open Trimmy and check your desk.';

  @override
  String get onboardingDailyOneMove => 'One move';

  @override
  String get onboardingDailyOneMoveDetail => 'Make one focused paper trade.';

  @override
  String get onboardingDailyThreeMoves => 'Three moves';

  @override
  String get onboardingDailyThreeMovesDetail =>
      'Make three focused paper trades.';

  @override
  String get onboardingSalHello =>
      'Five quick questions, then your first paper trade.';

  @override
  String get onboardingQuestionGoal => 'Why are you here?';

  @override
  String get onboardingQuestionKnowledge =>
      'How much do you know about trading?';

  @override
  String get onboardingQuestionPersona => 'Pick your trader.';

  @override
  String get onboardingQuestionDailyGoal => 'Pick your daily goal.';

  @override
  String get onboardingQuestionHandle => 'What should the floor call you?';

  @override
  String get onboardingHandleLabel => 'Handle';

  @override
  String get onboardingHandleHelper => '3 to 18 characters';

  @override
  String get onboardingHandleTooShort => 'Use at least 3 characters.';

  @override
  String get onboardingHandleTooLong => 'Use 18 characters or fewer.';

  @override
  String get onboardingHandleStartWithLetter => 'Start with a letter.';

  @override
  String get onboardingHandleCharacters =>
      'Use letters, numbers or underscores.';

  @override
  String get onboardingProgressLabel => 'Onboarding progress';

  @override
  String onboardingProgressValue(int percent) {
    return '$percent percent';
  }

  @override
  String onboardingProgressStep(int step, int total) {
    return '$step of $total';
  }

  @override
  String onboardingSalSays(String text) {
    return 'Sal says: $text';
  }

  @override
  String get onboardingNotificationsAsk =>
      'I\'ll ring you when Wall Street opens and closes. Trading here stays open.';

  @override
  String get onboardingNotificationsSoon => 'Alerts are almost ready.';

  @override
  String get onboardingNotificationsPhoneAsks => 'Your phone asks next.';

  @override
  String get onboardingNotificationsKeepSettingUp =>
      'Keep setting up your desk.';

  @override
  String get onboardingNotificationsChangeLater =>
      'You can change alerts any time in Settings.';

  @override
  String get onboardingNotificationsLater =>
      'Alerts will appear here after delivery is connected.';

  @override
  String get onboardingNotificationsSaving => 'Saving your setup';

  @override
  String get onboardingNotificationsTurnOn => 'Turn on alerts';

  @override
  String get onboardingReviewAnswers => 'Review my answers';

  @override
  String get onboardingOpeningMarket => 'Opening the market';

  @override
  String get onboardingSetupNotSaved => 'Your setup was not saved. Try again.';

  @override
  String get onboardingPermissionRequestFailed =>
      'The phone did not open the request. Try again.';

  @override
  String get onboardingSalPortrait => 'Sal, your floor boss';

  @override
  String get onboardingPermissionPreview =>
      'Preview of the phone notification permission';

  @override
  String get onboardingIntroSaveError => 'Could not save that step. Try again.';

  @override
  String get onboardingIntroSaving => 'Saving your place';

  @override
  String get onboardingCouldNotSave => 'Couldn’t save that. Try again.';

  @override
  String get onboardingReminderSkip => 'Skip reminders';

  @override
  String get onboardingReminderTitle => 'A little nudge?';

  @override
  String get onboardingReminderQuestion =>
      'How often would you like a reminder?';

  @override
  String get onboardingReminderPermissionOff =>
      'Notifications are off. You can change this in your phone settings.';

  @override
  String get onboardingReminderUnavailable =>
      'Your preference is saved. Notifications aren’t available on this build yet.';

  @override
  String get onboardingReminderNotSet =>
      'Couldn’t set the reminder. Try again.';

  @override
  String get onboardingReminderChanged =>
      'Your preference changed on another device. Choose again.';

  @override
  String get onboardingReminderSavedNotSet =>
      'Saved on this phone. Couldn’t set the reminder. Try again.';

  @override
  String get onboardingReminderSavedOffline =>
      'Saved on this phone. Sync will retry when you’re online.';

  @override
  String get personaWolfName => 'The Wolf';

  @override
  String get personaOracleName => 'The Oracle';

  @override
  String get personaSharkName => 'The Shark';

  @override
  String get personaWolfDetail => 'Bold. Fast. Loves a big move.';

  @override
  String get personaOracleDetail => 'Patient. Reads before moving.';

  @override
  String get personaSharkDetail => 'Calm when the crowd gets loud.';

  @override
  String personaPortrait(String name) {
    return '$name trader portrait';
  }

  @override
  String get personaPickerTitle => 'Pick your trader';

  @override
  String get personaPickerSubtitle => 'Who will you play as?';

  @override
  String get personaPickerChoose => 'Choose';

  @override
  String get personaPickerSaveError => 'Could not save your choice. Try again.';

  @override
  String welcomeHeadline(String wallStreet) {
    return 'Start your $wallStreet career.';
  }

  @override
  String get welcomeHeroSemantics =>
      'Start your Wall Street career. Tokenized stocks orbit the invitation.';

  @override
  String get welcomeStartFirstDay => 'Start my first day';

  @override
  String get welcomeSignInOrCreate => 'Sign in or create account';

  @override
  String get welcomeNoteSkip => 'Skip introduction';

  @override
  String get welcomeNoteTitle => 'Welcome to\nthe floor.';

  @override
  String get welcomeNoteBody =>
      'Your first day starts with practice.\n\nPick a company. It’s free.';

  @override
  String get chartPeriodDay => '1D';

  @override
  String get chartPeriodWeek => '1W';

  @override
  String get chartPeriodMonth => '1M';

  @override
  String get chartPeriodYear => '1Y';

  @override
  String chartPriceLabel(String from, String to) {
    return 'Price chart. $from to $to. Hold to explore.';
  }

  @override
  String chartTradeBoughtSummary(String shares, String price, String date) {
    return 'Bought $shares · $price · $date';
  }

  @override
  String chartTradeSoldSummary(String shares, String price, String date) {
    return 'Sold $shares · $price · $date';
  }

  @override
  String chartTradeBoughtLabel(
    num count,
    String shares,
    String price,
    String date,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bought $shares shares at $price, $date',
    );
    return '$_temp0';
  }

  @override
  String chartTradeSoldLabel(
    num count,
    String shares,
    String price,
    String date,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sold $shares shares at $price, $date',
    );
    return '$_temp0';
  }

  @override
  String get chartTradeMarkerBuy => 'B';

  @override
  String get chartTradeMarkerSell => 'S';

  @override
  String get chartNoYear => 'A year of history is not available yet.';

  @override
  String get chartHistoryUnavailable =>
      'Price history is unavailable. Try again.';

  @override
  String get chartStaleReading =>
      'This is an older reading. Refresh for a newer chart.';

  @override
  String get chartNotEnoughReadings =>
      'There are not enough readings for this period.';

  @override
  String get chartSevenDayLabel => 'Seven day company price movement';

  @override
  String get chartSevenDayCaption => '7-day listed stock movement';

  @override
  String get chartNoHistoryForVersion =>
      'Price history is not available for this version yet.';

  @override
  String get chartReadingsNotComparable =>
      'These readings cannot be compared reliably.';

  @override
  String chartReadingAt(String time) {
    return '$time UTC · From the first reading';
  }

  @override
  String chartRelativeHistoryLabel(String symbol) {
    return '$symbol relative history';
  }

  @override
  String chartChangeAtTime(String change, String time) {
    return '$change at $time UTC';
  }

  @override
  String get chartGapsHint =>
      'Gaps mean the provider returned no reading. Drag to explore.';

  @override
  String get chartDragHint => 'Drag across the chart to explore.';

  @override
  String get holdersLoadFailedTitle => 'Holders couldn’t load';

  @override
  String get holdersLoadFailedBody => 'Try again in a moment.';

  @override
  String get holdersEmpty => 'No holders to show';

  @override
  String get holdersColumnHolder => 'Holder';

  @override
  String get holdersColumnTokens => 'Tokens';

  @override
  String holdersSampleNote(String count) {
    return 'Balances from the largest $count token accounts. Not the full holder list.';
  }

  @override
  String get marketTitle => 'Market';

  @override
  String get marketSubtitle => 'Tokenized stocks';

  @override
  String marketSortTooltip(String sort) {
    return 'Sort: $sort';
  }

  @override
  String get marketSortButtonLabel => 'Sort stocks';

  @override
  String get marketSearchButtonLabel => 'Search companies';

  @override
  String get marketSortTitle => 'Sort loaded stocks';

  @override
  String get marketSortFeatured => 'Featured';

  @override
  String get marketSortName => 'Name';

  @override
  String get marketSortBiggestGains => 'Biggest gains';

  @override
  String get marketSortBiggestDrops => 'Biggest drops';

  @override
  String get marketSortHighestPrice => 'Highest price';

  @override
  String get marketSortMostHeld => 'Most held';

  @override
  String get marketListAll => 'All';

  @override
  String get marketListStarterPicks => 'Starter picks';

  @override
  String get marketListTrending => 'Trending';

  @override
  String get marketListMovers => 'Movers';

  @override
  String get marketListMostHeld => 'Most held';

  @override
  String get marketListFollowing => 'Following';

  @override
  String get marketListNewOnChain => 'New on chain';

  @override
  String get marketListTech => 'Tech';

  @override
  String get marketListFinance => 'Finance';

  @override
  String get marketListEnergy => 'Energy';

  @override
  String get marketListHealth => 'Health';

  @override
  String get marketListConsumer => 'Consumer';

  @override
  String get marketListFunds => 'Funds';

  @override
  String get marketListPreIpo => 'Pre-IPO';

  @override
  String get marketLoadingAll => 'Checking every stock…';

  @override
  String get marketEmptyFollowingTitle => 'Your watchlist starts here.';

  @override
  String get marketEmptyFollowingBody =>
      'Tap Follow on a company to keep it here.';

  @override
  String get marketEmptyFunds => 'No funds to show yet.';

  @override
  String get marketEmptyPreIpo => 'No pre-IPO companies to show yet.';

  @override
  String get marketEmptyStocks => 'No stocks to show yet.';

  @override
  String get marketEmptyBody => 'Try searching for a company.';

  @override
  String get marketFindCompany => 'Find a company';

  @override
  String get marketFollowingLoadFailed => 'Some stocks could not load. Retry';

  @override
  String get marketLoadingMore => 'Loading more stocks';

  @override
  String get marketOffline => 'You are offline. Check your connection.';

  @override
  String get marketListUnavailable => 'The market list is unavailable.';

  @override
  String marketFollowAdded(String name) {
    return '$name added to Following.';
  }

  @override
  String marketFollowRemoved(String name) {
    return '$name removed from Following.';
  }

  @override
  String get marketFollowSignInNeeded => 'Sign in to save your watchlist.';

  @override
  String get marketFollowListFull =>
      'Your watchlist is full. Remove a company first.';

  @override
  String get marketFollowUnchanged => 'Following did not change. Try again.';

  @override
  String get marketFollowButton => '+ Follow';

  @override
  String get marketFollowingButton => 'Following';

  @override
  String get marketTradeable => 'Tradeable';

  @override
  String get marketChangeUnavailable => 'Change unavailable';

  @override
  String marketCardChange24h(String change) {
    return '$change  24h';
  }

  @override
  String marketCardLabel(
    String tradeable,
    String name,
    String symbol,
    String price,
    String change,
  ) {
    String _temp0 = intl.Intl.selectLogic(tradeable, {
      'yes': '$name, $symbol, $price, $change, tradeable',
      'other': '$name, $symbol, $price, $change',
    });
    return '$_temp0';
  }

  @override
  String get marketChangeUnavailableSpoken => 'change unavailable';

  @override
  String marketChangeSpoken(String direction, String change) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'down': 'Down $change',
      'up': 'Up $change',
      'other': 'Unchanged $change',
    });
    return '$_temp0';
  }

  @override
  String marketCompanyLogoLabel(String name) {
    return '$name logo';
  }

  @override
  String get marketPaperMarkLabel => 'paper';

  @override
  String marketPaperAmountLabel(String amount) {
    return '$amount paper';
  }

  @override
  String get marketSearchHint => 'Name or symbol';

  @override
  String get marketSearchClear => 'Clear search';

  @override
  String get marketRecentTitle => 'Recently viewed';

  @override
  String get marketRecentClear => 'Clear';

  @override
  String get marketRecentEmptyTitle => 'Find your next company';

  @override
  String get marketRecentEmptyBody => 'Your recent searches will appear here.';

  @override
  String marketSearchNoResults(String query) {
    return 'Nothing called “$query”. Try the symbol.';
  }

  @override
  String get marketSearchLoadingResult => 'Loading company';

  @override
  String get marketSearchDidNotFinish => 'Search did not finish. Try again.';

  @override
  String get marketSearchStale =>
      'These results are old. Search again for a newer list.';

  @override
  String get marketSearchOffline =>
      'You are offline. Check your connection and try again.';

  @override
  String get marketSearchPaused => 'The search paused. Try again.';

  @override
  String get marketSearchRateLimited =>
      'Too many searches. Wait a moment and try again.';

  @override
  String get marketSearchTimeout => 'The search took too long. Try again.';

  @override
  String get marketSearchDisabled =>
      'Company search is not available in this build.';

  @override
  String get marketSearchUnavailable =>
      'Company search is unavailable. Try again.';

  @override
  String stockFollowTooltip(String name) {
    return 'Follow $name';
  }

  @override
  String stockUnfollowTooltip(String name) {
    return 'Unfollow $name';
  }

  @override
  String stockShareTooltip(String name) {
    return 'Share $name';
  }

  @override
  String get stockPositionTitle => 'Your position';

  @override
  String get stockPast24h => 'past 24h';

  @override
  String get stockChartFailedTitle => 'Chart did not load';

  @override
  String get stockChartEmptyTitle => 'No chart yet';

  @override
  String get stockChartEmptyBody => 'This token needs more price history.';

  @override
  String get stockPriceAlertTooltip => 'Set a price alert';

  @override
  String stockChartUpdatedAt(String time) {
    return 'Chart to $time';
  }

  @override
  String stockPositionShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares shares',
    );
    return '$_temp0';
  }

  @override
  String get stockPositionValue => 'Value';

  @override
  String get stockPositionValueAtTrade => 'Value at trade';

  @override
  String get stockPositionNotPriced => 'Not priced';

  @override
  String get stockPositionAverageCost => 'Average cost';

  @override
  String get stockPositionReturn => 'Return';

  @override
  String get stockPositionReturnAtTrade => 'Return at trade';

  @override
  String get stockSectionsLabel => 'Company details';

  @override
  String get stockSectionAbout => 'About';

  @override
  String get stockSectionHolders => 'Holders';

  @override
  String get stockSectionComments => 'Comments';

  @override
  String get stockAboutReadMore => 'Read more';

  @override
  String get stockAboutReadLess => 'Read less';

  @override
  String get stockMetricVolume24h => '24h volume';

  @override
  String get stockMetricLiquidity => 'Liquidity';

  @override
  String get stockMetricTokenMarketCap => 'Token market cap';

  @override
  String get stockMetricTokenHolders => 'Token holders';

  @override
  String get stockMetricCompanyMarketCap => 'Company market cap';

  @override
  String get stockMetricSector => 'Sector';

  @override
  String get stockTokensTitle => 'Available tokens';

  @override
  String stockCopyAddressTooltip(String symbol) {
    return 'Copy $symbol address';
  }

  @override
  String get stockAddressCopied => 'Address copied';

  @override
  String get stockAboutEmpty => 'Details are on their way';

  @override
  String get stockPracticeInPaper => 'Practice in Paper';

  @override
  String get stockVersionsLabel => 'Token versions';

  @override
  String stockVersionSelectedLabel(String version) {
    return 'Token version $version. Change';
  }

  @override
  String stockVersionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count versions',
      one: '1 version',
    );
    return '$_temp0';
  }

  @override
  String get stockVersionsTitle => 'Versions';

  @override
  String get stockVersionNotTradeable => 'Not available to trade.';

  @override
  String get reasonWriteTitle => 'Write your reason';

  @override
  String get reasonWriteSavedTitle => 'Reason saved';

  @override
  String get reasonWritePrompt => 'What made you buy?';

  @override
  String get reasonWriteHint => 'Your take on this stock…';

  @override
  String get reasonWriteSave => 'Save reason';

  @override
  String get reasonWriteRetry => 'Retry reason';

  @override
  String get reasonWriteCloseRefresh => 'Close and refresh';

  @override
  String reasonWriteRewardTrims(String amount) {
    return '+$amount Trims';
  }

  @override
  String get reasonWriteMissionRecorded => 'Mission recorded';

  @override
  String reasonWriteHeldShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares shares',
      one: '$shares share',
    );
    return '$_temp0';
  }

  @override
  String get reasonWriteErrorInvalidInput =>
      'Use one line and 180 characters or fewer.';

  @override
  String get reasonWriteErrorOffline =>
      'You are offline. Your reason was not saved. Try again.';

  @override
  String get reasonWriteErrorTimeout => 'Saving took too long. Try again.';

  @override
  String get reasonWriteErrorAccount =>
      'Refresh your session before saving this reason.';

  @override
  String get reasonWriteErrorProfile =>
      'Finish setting up your profile before saving this reason.';

  @override
  String get reasonWriteErrorOrderNotFound =>
      'This paper buy was not found. Refresh your desk.';

  @override
  String get reasonWriteErrorBuyRequired =>
      'A reason can be added only to a confirmed paper buy.';

  @override
  String get reasonWriteErrorPositionRequired =>
      'You need to still hold this stock before saving a reason.';

  @override
  String get reasonWriteErrorExists =>
      'This paper buy already has a reason. Refresh your Career.';

  @override
  String get reasonWriteErrorRetryMismatch =>
      'This retry could not be matched. Refresh your Career.';

  @override
  String get reasonWriteErrorRateLimited =>
      'Reasons are busy right now. Try again shortly.';

  @override
  String get reasonWriteErrorGeneric => 'Your reason was not saved. Try again.';

  @override
  String get reasonPrivacyTitle => 'Who can see my comments';

  @override
  String get reasonPrivacyNobody => 'Nobody';

  @override
  String get reasonPrivacyEveryone => 'Everyone';

  @override
  String get reasonPrivacyFriends => 'Friends';

  @override
  String reasonPrivacySavingChoice(String choice) {
    return 'Saving $choice.';
  }

  @override
  String get reasonPrivacyLoading => 'Loading your choice.';

  @override
  String get reasonPrivacyNotAvailable => 'Your choice is not available yet.';

  @override
  String reasonPrivacySavedStatus(String status) {
    return 'Saved. $status';
  }

  @override
  String reasonPrivacyChangedElsewhere(String status) {
    return 'Changed on another device. Refreshed. $status';
  }

  @override
  String get reasonPrivacyNobodyLine => 'Only you can see your comments.';

  @override
  String get reasonPrivacyEveryoneLine =>
      'Anyone in Trimmy can see them on each stock page.';

  @override
  String get reasonPrivacyFriendsLine =>
      'Not available yet. Shares nothing until friends exist.';

  @override
  String get reasonPrivacyFriendsAvailableLine =>
      'Only your Trimmy friends can see them on each stock page.';

  @override
  String get reasonPrivacyConsentLine =>
      'Your comments and your handle will show on that stock\'s page for anyone in Trimmy. Money never shows.';

  @override
  String get reasonPrivacyNobodyOption => 'Only you. This is the default.';

  @override
  String get reasonPrivacyEveryoneOption =>
      'Anyone in Trimmy, on each stock page.';

  @override
  String reasonPrivacySheetNow(String choice) {
    return 'Now: $choice.';
  }

  @override
  String get reasonPrivacyGuestRecovery => 'This guest desk needs recovery.';

  @override
  String get reasonPrivacySessionRefresh =>
      'Your session needs a refresh. Try again.';

  @override
  String get reasonPrivacyLoadOffline =>
      'You are offline. Your choice could not load.';

  @override
  String get reasonPrivacyLoadTimeout => 'Your choice took too long to load.';

  @override
  String get reasonPrivacyLoadSession =>
      'Your session needs a refresh before this can load.';

  @override
  String get reasonPrivacyAccountClosed => 'This account is closed.';

  @override
  String get reasonPrivacyLoadFailed => 'Your choice could not load.';

  @override
  String get reasonPrivacySaveOffline =>
      'You are offline. Your choice is not saved yet.';

  @override
  String reasonPrivacySaveOfflineChoice(String choice) {
    return 'You are offline. $choice is not saved yet.';
  }

  @override
  String get reasonPrivacySaveTimeout =>
      'Saving took too long. Your choice is not saved yet.';

  @override
  String reasonPrivacySaveTimeoutChoice(String choice) {
    return 'Saving took too long. $choice is not saved yet.';
  }

  @override
  String get reasonPrivacySaveSession =>
      'Your session needs a refresh. Your choice is not saved yet.';

  @override
  String reasonPrivacySaveSessionChoice(String choice) {
    return 'Your session needs a refresh. $choice is not saved yet.';
  }

  @override
  String get reasonPrivacySaveAccountClosed =>
      'This account is closed. Nothing was saved.';

  @override
  String get reasonPrivacySaveMismatch =>
      'That save could not be matched. Choose again.';

  @override
  String get reasonPrivacySaveFailed =>
      'Couldn\'t save. Your choice is not saved yet.';

  @override
  String reasonPrivacySaveFailedChoice(String choice) {
    return 'Couldn\'t save. $choice is not saved yet.';
  }

  @override
  String get reasonPrivacyRateLimitedLoad =>
      'Too many changes. Try to load again shortly.';

  @override
  String reasonPrivacyRateLimitedLoadSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Too many changes. Try to load again in $seconds seconds.',
      one: 'Too many changes. Try to load again in $seconds second.',
    );
    return '$_temp0';
  }

  @override
  String get reasonPrivacyRateLimitedSave =>
      'Too many changes. Try to save again shortly.';

  @override
  String reasonPrivacyRateLimitedSaveSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: 'Too many changes. Try to save again in $seconds seconds.',
      one: 'Too many changes. Try to save again in $seconds second.',
    );
    return '$_temp0';
  }

  @override
  String get reasonReportSheetTitle => 'Why are you reporting this?';

  @override
  String get reasonReportSheetBody =>
      'Choose the closest reason. The author will not see who reported it.';

  @override
  String get reasonReportConfirmTitle => 'Report this reason?';

  @override
  String reasonReportConfirmBody(String category) {
    String _temp0 = intl.Intl.selectLogic(category, {
      'spam':
          'Trimmy will review it as spam. It will leave this page after the report is received.',
      'harassment':
          'Trimmy will review it as harassment. It will leave this page after the report is received.',
      'impersonation':
          'Trimmy will review it as impersonation. It will leave this page after the report is received.',
      'unsafe':
          'Trimmy will review it as unsafe content. It will leave this page after the report is received.',
      'other':
          'Trimmy will review it as something else. It will leave this page after the report is received.',
    });
    return '$_temp0';
  }

  @override
  String get reasonReportAction => 'Report';

  @override
  String get reasonBlockAction => 'Block';

  @override
  String get reasonReportReceived => 'Report received.';

  @override
  String reasonBlockConfirmTitle(String handle) {
    return 'Block @$handle?';
  }

  @override
  String get reasonBlockConfirmBody =>
      'Their reasons will leave this page. Any friendship and open invitations between you will also be removed. Public reasons can still be seen from other accounts.';

  @override
  String reasonBlockDone(String handle) {
    return '@$handle blocked.';
  }

  @override
  String get reasonSafetyErrorConflict =>
      'This changed on another device. Choose again.';

  @override
  String get reasonSafetyErrorRateLimited =>
      'Too many changes at once. Wait a moment and try again.';

  @override
  String get reasonSafetyErrorUnavailable =>
      'This action is unavailable for your account right now.';

  @override
  String get reasonSafetyErrorUnconfirmed =>
      'We could not confirm the result. It will retry safely.';

  @override
  String get reasonSafetyErrorGeneric =>
      'That action could not be completed. Try again.';

  @override
  String get reasonEmpty => 'No comments yet';

  @override
  String get reasonEmptyFriends => 'No comments from friends yet';

  @override
  String get reasonOwnHistoryIncomplete =>
      'Your complete reason history could not be loaded here.';

  @override
  String get reasonOwnStatusFailed =>
      'Your private reason status could not be checked.';

  @override
  String get reasonShowMore => 'Show more';

  @override
  String get reasonLoadSessionRefresh =>
      'Your session needs a refresh before comments can load.';

  @override
  String get reasonLoadOffline => 'You are offline. Comments couldn’t load.';

  @override
  String get reasonLoadTimeout => 'Comments took too long to load.';

  @override
  String get reasonLoadRateLimited =>
      'Comments are refreshing too quickly. Try again shortly.';

  @override
  String get reasonLoadFailed => 'Comments couldn’t load.';

  @override
  String get reasonAudienceSemantics => 'Choose whose comments to see';

  @override
  String get reasonAudienceEveryone => 'Everyone';

  @override
  String get reasonAudienceFriends => 'Friends';

  @override
  String get reasonYouBadge => 'You';

  @override
  String reasonSavedAt(String date, String time) {
    return 'Saved $date, $time';
  }

  @override
  String get reasonPrivateLine => 'Your comment is private.';

  @override
  String get reasonLoadingComments => 'Loading comments';

  @override
  String get fastBuyTitle => 'Fast buy';

  @override
  String get fastBuyClose => 'Close fast buy';

  @override
  String get fastBuySearchHint => 'Search a name or ticker';

  @override
  String get fastBuyOpenFailed => 'This stock couldn’t open. Try again.';

  @override
  String get fastBuyConnectFailed => 'Trading could not connect.';

  @override
  String get fastBuyNoneAvailable => 'No stocks available to buy right now.';

  @override
  String get fastBuyNoTradeableMatch => 'No tradeable stock matches that.';

  @override
  String get fastBuyNoMatches => 'No matches yet.';

  @override
  String paperAmount(String amount) {
    return '$amount paper';
  }

  @override
  String paperOrderEquivalentPaper(String amount) {
    return '≈ $amount paper';
  }

  @override
  String paperOrderEquivalentShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '≈ $shares shares',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderConversionAtReview => 'Conversion shown at review';

  @override
  String paperOrderBuyTitle(String symbol) {
    return 'Buy $symbol';
  }

  @override
  String paperOrderSellTitle(String symbol) {
    return 'Sell $symbol';
  }

  @override
  String get paperOrderReviewBuyTitle => 'Review your buy';

  @override
  String get paperOrderReviewSellTitle => 'Review your sell';

  @override
  String get paperOrderConfirmedTitle => 'Trade confirmed';

  @override
  String get paperOrderFirstTradeSwipeHint => 'Swipe down to edit your buy';

  @override
  String get paperOrderFirstTradeSkip => 'Skip first trade';

  @override
  String get paperOrderFirstTradeReviewTitle => 'Review your buy.';

  @override
  String get paperOrderSharesLabel => 'Shares';

  @override
  String get paperOrderPricePerShare => 'Price per share';

  @override
  String get paperOrderFee => 'Fee';

  @override
  String get paperOrderTotal => 'Total';

  @override
  String get paperOrderConfirmingBuy => 'Confirming buy…';

  @override
  String get paperOrderCheckingPrice => 'Checking price…';

  @override
  String get paperOrderConfirmBuy => 'Confirm buy';

  @override
  String get paperOrderConfirmSell => 'Confirm sell';

  @override
  String paperOrderSharesValue(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares shares',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSharesAvailable(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$shares shares available',
    );
    return '$_temp0';
  }

  @override
  String paperOrderPaperAvailable(String amount) {
    return '$amount paper available';
  }

  @override
  String paperOrderBuyingShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Buying $shares shares',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSellingShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Selling $shares shares',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderYouPay => 'You pay';

  @override
  String get paperOrderYouReceive => 'You receive';

  @override
  String get paperOrderBuyConfirmed => 'Buy confirmed';

  @override
  String get paperOrderSaleConfirmed => 'Sale confirmed';

  @override
  String paperOrderOnYourDesk(String symbol) {
    return '$symbol is on your desk.';
  }

  @override
  String paperOrderLeftYourDesk(String symbol) {
    return '$symbol left your desk.';
  }

  @override
  String paperOrderPositionChanged(String symbol) {
    return 'Your $symbol position changed.';
  }

  @override
  String paperOrderBoughtShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bought $shares shares',
    );
    return '$_temp0';
  }

  @override
  String paperOrderSoldShares(num count, String shares) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sold $shares shares',
    );
    return '$_temp0';
  }

  @override
  String get paperOrderYourPosition => 'Your position';

  @override
  String get paperOrderPositionValue => 'Position value';

  @override
  String get paperOrderTrimsEarned => 'Trims earned';

  @override
  String get paperOrderReasonLabel => 'Why did you buy?';

  @override
  String get paperOrderReasonHint => 'One clear line';

  @override
  String get paperOrderSaveReason => 'Save reason';

  @override
  String get paperOrderRetryReason => 'Retry reason';

  @override
  String paperOrderReasonTrims(String amount) {
    return '+$amount Trims';
  }

  @override
  String get paperOrderReasonSaved => 'Reason saved';

  @override
  String paperOrderReasonQuote(String note) {
    return '“$note”';
  }

  @override
  String get paperOrderReasonUnavailable =>
      'Your trade is confirmed. Saving a reason is unavailable right now.';

  @override
  String get paperOrderUnitLabel => 'Order amount unit';

  @override
  String get paperOrderUnitPaper => 'Paper';

  @override
  String get paperOrderUnitShares => 'Shares';

  @override
  String get paperOrderKeyDelete => 'Delete';

  @override
  String get paperOrderKeyDecimal => 'Decimal point';

  @override
  String get paperOrderNoVersion => 'This company has no available version.';

  @override
  String get paperOrderReasonNotSaved =>
      'Trade confirmed. Your reason was not saved. Try again.';

  @override
  String get paperOrderReasonNotSavedDone =>
      'The trade is done, but the reason was not saved. Try again.';

  @override
  String get paperOrderReasonTooLong =>
      'Use one line and 180 characters or fewer.';

  @override
  String get paperOrderReasonOffline =>
      'Trade confirmed. You are offline, so your reason was not saved. Try again.';

  @override
  String get paperOrderReasonTimeout =>
      'Trade confirmed. Saving the reason took too long. Try again.';

  @override
  String get paperOrderReasonSessionExpired =>
      'Trade confirmed. Your session needs to be refreshed before saving the reason.';

  @override
  String get paperOrderReasonProfileRequired =>
      'Trade confirmed. Finish setting up your profile before saving the reason.';

  @override
  String get paperOrderReasonOrderNotFound =>
      'Trade confirmed. This order was not found. Refresh your desk.';

  @override
  String get paperOrderReasonBuyRequired =>
      'Reasons can be saved only after a confirmed paper buy.';

  @override
  String get paperOrderReasonPositionRequired =>
      'Trade confirmed. Hold this stock before saving a reason.';

  @override
  String get paperOrderReasonExists =>
      'This trade already has a saved reason. Refresh your career.';

  @override
  String get paperOrderReasonRetryMismatch =>
      'Trade confirmed. This retry could not be matched. Refresh your career.';

  @override
  String get paperOrderReasonBusy =>
      'Trade confirmed. Reasons are busy right now. Try again shortly.';

  @override
  String get paperOrderErrorInvalidAmount => 'Enter an amount above zero.';

  @override
  String get paperOrderErrorInsufficientPaper =>
      'There is not enough paper for this order.';

  @override
  String get paperOrderErrorInsufficientShares =>
      'There are not enough shares to sell.';

  @override
  String get paperOrderErrorQuoteExpired =>
      'That price expired. Check a new quote.';

  @override
  String get paperOrderErrorPriceChanged =>
      'The price moved. Check the new quote.';

  @override
  String get paperOrderErrorOffline =>
      'You are offline. Check your connection and try again.';

  @override
  String get paperOrderErrorTimeout => 'That took too long. Try again.';

  @override
  String get paperOrderErrorAccountRequired =>
      'Save your desk before placing this order.';

  @override
  String get paperOrderErrorDuplicate =>
      'This order was already received. Refresh your desk.';

  @override
  String get paperOrderErrorRejected => 'The order was not accepted.';

  @override
  String get paperOrderErrorUnavailable =>
      'The order did not go through. Try again.';

  @override
  String get liveOrderErrorAddUsdc => 'Add USDC to your Solana wallet first.';

  @override
  String get liveOrderErrorAddSol =>
      'Add SOL to cover network and account fees.';

  @override
  String get liveOrderErrorInsufficientHoldings =>
      'You don’t have enough of this token to sell.';

  @override
  String get liveOrderErrorTradeLimit =>
      'This order is above the current trade limit.';

  @override
  String get liveOrderErrorAppUpdate =>
      'Update Trimmy to review the issuer terms before trading.';

  @override
  String get liveOrderErrorTermsRequired =>
      'Confirm the issuer terms to continue.';

  @override
  String get liveOrderErrorWalletRequired => 'Create your wallet to continue.';

  @override
  String get liveOrderErrorOrderPending =>
      'Your previous trade is still confirming.';

  @override
  String get liveOrderErrorQuoteExpired =>
      'That price expired. Get a fresh quote.';

  @override
  String get liveOrderErrorBusy => 'Quotes are busy. Try again in a moment.';

  @override
  String get liveOrderErrorNoRoute =>
      'No route for this order right now. Try another amount.';

  @override
  String get liveOrderErrorMarketClosed =>
      'This stock trades while US markets are open. Try again then.';

  @override
  String get liveOrderErrorBelowMinimum =>
      'This order is under the market maker’s minimum. Try a larger amount.';

  @override
  String get liveOrderErrorPriceOffMarket =>
      'That price is too far from the market right now. Try again shortly or a smaller amount.';

  @override
  String get liveOrderErrorFeeTooHigh =>
      'The fees are too high for this order. Try later.';

  @override
  String get liveOrderErrorAccountRequired =>
      'Sign in again to use your wallet.';

  @override
  String get liveOrderErrorFreshQuote => 'This order needs a fresh quote.';

  @override
  String get liveOrderErrorUnavailable =>
      'Trading couldn’t connect. Try again.';

  @override
  String get liveOrderErrorGeneric => 'Couldn’t complete this step. Try again.';

  @override
  String get liveOrderConfirmTermsFirst => 'Confirm the issuer terms first.';

  @override
  String get liveOrderInvalidShares => 'Enter a valid share amount.';

  @override
  String get liveOrderInvalidUsdc => 'Enter a valid USDC amount.';

  @override
  String liveOrderUpToPerOrder(String amount) {
    return 'Up to $amount per order.';
  }

  @override
  String liveOrderMinimum(String amount) {
    return 'Orders for this token start at $amount.';
  }

  @override
  String liveOrderMarketNotice(String status) {
    return '$status.';
  }

  @override
  String get liveOrderQuoteFailed =>
      'Couldn’t get a verified quote. Try again.';

  @override
  String get liveOrderCheckingResult =>
      'Checking the result. Your order won’t be sent twice.';

  @override
  String get liveOrderSigningFailed =>
      'Signing didn’t finish. No order was sent.';

  @override
  String get liveOrderReconnecting => 'Reconnecting to check your order…';

  @override
  String get liveOrderTermsOpenFailed =>
      'Couldn’t open the issuer’s terms. Try again.';

  @override
  String get liveOrderTransactionOpenFailed =>
      'Couldn’t open the transaction. Try again.';

  @override
  String get liveOrderTitleFallback => 'Trade';

  @override
  String get liveOrderAccountChangedTitle => 'Your account changed';

  @override
  String get liveOrderAccountChangedBody => 'Reopen trading after signing in.';

  @override
  String get liveOrderCheckLastOrderTitle => 'Let’s check your last order';

  @override
  String get liveOrderConnectFailedTitle => 'Trading couldn’t connect';

  @override
  String get liveOrderConnectedRetryBody => 'Try again when you’re connected.';

  @override
  String get liveOrderPausedTitle => 'Trading is temporarily paused';

  @override
  String get liveOrderPausedBody => 'Your wallet and holdings are still here.';

  @override
  String get liveOrderNotTradableTitle => 'This token isn’t tradable here yet';

  @override
  String get liveOrderChooseAnother => 'Choose another stock to trade.';

  @override
  String get liveOrderBackToStocks => 'Back to stocks';

  @override
  String get liveOrderCheckingBalance => 'Checking balance…';

  @override
  String liveOrderAvailable(String amount) {
    return '$amount available';
  }

  @override
  String liveOrderBuyTitle(String symbol) {
    return 'Buy $symbol';
  }

  @override
  String liveOrderSellTitle(String symbol) {
    return 'Sell $symbol';
  }

  @override
  String get liveOrderBuyInstead => 'Buy instead';

  @override
  String get liveOrderSellInstead => 'Sell instead';

  @override
  String get liveOrderYouSell => 'You sell';

  @override
  String get liveOrderYouPay => 'You pay';

  @override
  String liveOrderLimit(String amount) {
    return 'Order limit: $amount';
  }

  @override
  String liveOrderLimitCappedMax(String amount) {
    return 'Max capped at the order limit of $amount.';
  }

  @override
  String liveOrderLimitCappedPercent(String percent, String amount) {
    return '$percent capped at the order limit of $amount.';
  }

  @override
  String get liveOrderCheckingPrice => 'Checking price and fees…';

  @override
  String get liveOrderReviewBuy => 'Review buy';

  @override
  String get liveOrderReviewSell => 'Review sell';

  @override
  String get liveOrderReviewBuyTitle => 'Review your buy';

  @override
  String get liveOrderReviewSellTitle => 'Review your sell';

  @override
  String get liveOrderYouReceive => 'You receive ≈';

  @override
  String get liveOrderMinimumReceived => 'Minimum received';

  @override
  String get liveOrderNetworkFees => 'Network + account fees';

  @override
  String get liveOrderSwapFee => 'Swap fee';

  @override
  String get liveOrderPrice => 'Price';

  @override
  String get liveOrderFixedQuote => 'Fixed quote from a market maker';

  @override
  String get liveOrderIssuer => 'Issuer';

  @override
  String get liveOrderIssuerFee => 'Issuer fee';

  @override
  String get liveOrderConfirmBuy => 'Confirm buy';

  @override
  String get liveOrderConfirmSell => 'Confirm sell';

  @override
  String get liveOrderEditAmount => 'Edit amount';

  @override
  String get liveOrderTradeConfirmed => 'Trade confirmed';

  @override
  String get liveOrderConfirmingTrade => 'Confirming your trade';

  @override
  String get liveOrderQuoteExpired => 'Quote expired';

  @override
  String get liveOrderTradeIncomplete => 'Trade didn’t complete';

  @override
  String get liveOrderConfirmedBody => 'Your order is confirmed on Solana.';

  @override
  String get liveOrderPendingBody =>
      'You can close this. Reopen the trade to check its status.';

  @override
  String get liveOrderExpiredBody => 'Get a fresh price to continue.';

  @override
  String get liveOrderFailedBody => 'Your order wasn’t filled.';

  @override
  String get liveOrderViewWalletActivity => 'View wallet activity ↗';

  @override
  String get liveOrderViewTransaction => 'View transaction ↗';

  @override
  String get liveOrderGetFreshPrice => 'Get fresh price';

  @override
  String liveOrderIssuerExcluded(String regions) {
    return 'Not for residents of $regions';
  }

  @override
  String liveOrderIssuerFeeNote(String percent) {
    return 'Issuer fee: $percent on every buy and sell';
  }

  @override
  String get liveOrderLegacyAttestation =>
      'I’m eligible under the issuer’s terms.';

  @override
  String get liveOrderIssuerTerms => 'Issuer terms ↗';

  @override
  String get liveHistoryStatusConfirming => 'Confirming';

  @override
  String get liveHistoryStatusConfirmed => 'Confirmed';

  @override
  String get liveHistoryStatusFailed => 'Not completed';

  @override
  String get liveHistoryStatusExpired => 'Expired';

  @override
  String get liveHistoryErrorSignIn => 'Sign in again to see your trades.';

  @override
  String get liveHistoryErrorLoad => 'Couldn’t load your trades. Try again.';

  @override
  String get liveHistoryErrorLoadMore =>
      'Couldn’t load more trades. Try again.';

  @override
  String get liveHistoryErrorOpenStock =>
      'Couldn’t open this stock. Try again.';

  @override
  String get liveHistoryTitle => 'Your trades';

  @override
  String get liveHistoryEmptyTitle => 'Your first trade starts here';

  @override
  String get liveHistoryEmptyBody => 'Your orders will appear here.';

  @override
  String get liveHistoryMore => 'More trades';

  @override
  String liveHistoryRowBuy(String symbol) {
    return 'Buy $symbol';
  }

  @override
  String liveHistoryRowSell(String symbol) {
    return 'Sell $symbol';
  }

  @override
  String get liveHistoryYouPaid => 'You paid';

  @override
  String get liveHistoryYouSold => 'You sold';

  @override
  String get liveHistoryYouReceived => 'You received';

  @override
  String get liveHistoryFinalAmounts =>
      'Final amounts from the confirmed transaction.';

  @override
  String get liveHistoryQuotedOutput => 'Quoted output';

  @override
  String get liveHistoryMinimumOutput => 'Minimum output';

  @override
  String get liveHistoryEstimates =>
      'Order estimates. See the transaction for the final amounts.';

  @override
  String get liveHistoryViewTransaction => 'View transaction';

  @override
  String get liveHistoryOpenStock => 'Open stock';

  @override
  String get liveTradingOpenAlways => 'Open 24/7';

  @override
  String get liveTradingOpenWeekends => 'Open now, including weekends';

  @override
  String get liveTradingOpenNow => 'Open now';

  @override
  String get liveTradingPausedByIssuer => 'Paused by the issuer';

  @override
  String get liveTradingPausedByMarket => 'Paused by the market';

  @override
  String liveTradingPausedResumes(String time) {
    return 'Paused · resumes $time';
  }

  @override
  String get liveTradingShortPause => 'Short pause';

  @override
  String liveTradingShortPauseResumes(String time) {
    return 'Short pause · resumes $time';
  }

  @override
  String get liveTradingClosed => 'Closed';

  @override
  String liveTradingClosedOpens(String time) {
    return 'Closed · opens $time';
  }

  @override
  String get liveTradingHoursAroundClock =>
      'Trades around the clock, with short pauses between US sessions.';

  @override
  String get liveTradingHoursWeekdays =>
      'Trades 24 hours a day, Sunday evening to Friday evening (US Eastern).';

  @override
  String get liveTradingHoursRegular =>
      'Trades during US market hours only, 9:30 AM to 4 PM Eastern on weekdays.';

  @override
  String get liveTradingHoursSessions =>
      'Trades during US market sessions only.';

  @override
  String liveTradingTimeToday(int hour, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: '$clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeTomorrow(int hour, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: 'tomorrow $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeWeekday(int hour, String weekday, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: '$weekday $clock',
    );
    return '$_temp0';
  }

  @override
  String liveTradingTimeDate(int hour, String date, String clock) {
    String _temp0 = intl.Intl.pluralLogic(
      hour,
      locale: localeName,
      other: '$date, $clock',
    );
    return '$_temp0';
  }

  @override
  String get liveTradingReasonIssuerNotOffered =>
      'This issuer is not offered in Trimmy.';

  @override
  String get liveTradingReasonNotYet => 'Not available to trade in Trimmy yet.';

  @override
  String get liveTradingReasonIdentity =>
      'Trimmy could not confirm who issued this token.';

  @override
  String get liveTradingReasonRestricted =>
      'The issuer has restrictions on this token that Trimmy cannot accept.';

  @override
  String get liveTradingReasonLowLiquidity =>
      'Too little trading to buy and sell it safely.';

  @override
  String get liveTradingReasonNoRoute =>
      'No order route passed Trimmy’s safety checks.';

  @override
  String get liveTradingReasonPriceOff =>
      'Its price is too far from the real share price.';

  @override
  String get liveTradingReasonHeldBack =>
      'Paused while Trimmy checks this token.';

  @override
  String get liveTradingReasonNotChecked => 'Not checked yet.';

  @override
  String liveTradingReasonClosedOpens(String time) {
    return 'Its market is closed. It opens $time, then Trimmy checks it.';
  }

  @override
  String get liveTradingReasonUsHours =>
      'Trades only while US markets are open.';

  @override
  String get liveTradingReasonAwaitingReview =>
      'Its market is open. Trimmy is checking it before you can trade.';

  @override
  String get liveTradingReasonNoMarketMaker =>
      'No market maker is quoting it right now.';

  @override
  String get liveTradingReasonUnavailable =>
      'Not available to trade in Trimmy.';

  @override
  String get liveTradingOtherIssuer => 'Other issuer';

  @override
  String get holdingsCheckingWallet => 'Checking your wallet…';

  @override
  String get holdingsWalletStarts => 'Your wallet starts here';

  @override
  String get holdingsEmptyTitle => 'No stocks yet';

  @override
  String get holdingsEmptyBody => 'Your first stock starts here.';

  @override
  String get holdingsExplore => 'Explore stocks';

  @override
  String get walletFastBuy => 'Fast buy';

  @override
  String get walletSend => 'Send';

  @override
  String get walletCashBalance => 'Cash balance';

  @override
  String get walletAccountBalance => 'Account balance';

  @override
  String get walletKnownValue => 'Known value';

  @override
  String get walletSwitchToPaper => 'Switch to paper mode';

  @override
  String get walletSwitchToReal => 'Switch to real money mode';

  @override
  String get walletUsdcAvailable => 'USDC available';

  @override
  String walletPositions(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText positions',
    );
    return '$_temp0';
  }

  @override
  String get walletSomePricesUnavailable => 'Some prices unavailable';

  @override
  String get walletPositionPricesUnavailable => 'Position prices unavailable';

  @override
  String get walletCheckingSol => 'Checking SOL…';

  @override
  String walletSolForFees(String amount) {
    return '$amount SOL for fees';
  }

  @override
  String get walletCashMarks => 'USDC and SOL';

  @override
  String get fundCreateWalletFailed =>
      'Couldn’t create your wallet. Try again.';

  @override
  String get fundWalletUnconfirmed => 'We couldn’t confirm your wallet.';

  @override
  String get fundWalletOffline =>
      'You’re offline. Reconnect to load your wallet.';

  @override
  String get fundWalletLoadFailed => 'Couldn’t load your wallet.';

  @override
  String get fundTabCash => 'Cash';

  @override
  String get fundTabCrypto => 'Crypto';

  @override
  String get fundWalletMissingTitle => 'A wallet for your money';

  @override
  String get fundCreatingWallet => 'Creating…';

  @override
  String get fundCreateWallet => 'Create wallet';

  @override
  String fundDepositQrLabel(String address) {
    return 'Solana deposit address $address';
  }

  @override
  String get fundSendOnlyWarning =>
      'Send only USDC or SOL to this account on the Solana network.';

  @override
  String get fundAddressCopied => 'Copied';

  @override
  String get fundCopyAddress => 'Copy address';

  @override
  String get guestDeskStartAgainFailedExpired =>
      'Couldn’t start again. Your expired desk is still preserved.';

  @override
  String get guestDeskStartAgainFailed =>
      'Couldn’t start again. Your old desk is still preserved.';

  @override
  String get guestDeskStartFreshTitle => 'Start fresh?';

  @override
  String get guestDeskExpiredTitle => 'Guest session expired';

  @override
  String get guestDeskEndedTitle => 'Guest session ended';

  @override
  String get guestDeskStartFreshMessage =>
      'This removes this phone’s access to your old desk. You can’t undo it.';

  @override
  String get guestDeskExpiredMessage =>
      'Your guest records are preserved. This desk can no longer trade or be saved to an account.';

  @override
  String get guestDeskEndedMessage =>
      'Your guest records are preserved, but this phone can no longer open the desk.';

  @override
  String get guestDeskStartFreshDetail =>
      'Your balance, positions and history won’t move to the new desk.';

  @override
  String get guestDeskSignInDetail =>
      'Sign in to open your saved account. Your guest desk stays untouched.';

  @override
  String get guestDeskOpening => 'Opening…';

  @override
  String get guestDeskStartNewConfirm => 'Start a new desk';

  @override
  String get guestDeskKeep => 'Keep this desk';

  @override
  String get guestDeskStartNewGuest => 'Start a new guest desk';

  @override
  String get guestDeskPreservedTitle => 'Welcome back';

  @override
  String get guestDeskPreservedMessage =>
      'Your saved trades and progress are ready.';

  @override
  String get guestDeskPreservedExpiredDetail =>
      'Your expired guest desk is preserved separately. It can no longer trade or merge.';

  @override
  String get guestDeskPreservedDetail =>
      'Your guest trades stay separate. Sign out to return to that desk.';

  @override
  String get guestDeskGoToDesk => 'Go to my desk';

  @override
  String get onrampErrorNotEnabled =>
      'Card deposits aren’t available yet. You can still transfer from another wallet.';

  @override
  String get onrampErrorSignIn => 'Sign in again to continue.';

  @override
  String get onrampErrorExpired =>
      'This checkout needs to be checked with support. Your wallet balance will still update.';

  @override
  String get onrampErrorBusy => 'Give it a moment, then try again.';

  @override
  String onrampErrorAmount(String min, String max) {
    return 'Enter an amount from $min to $max.';
  }

  @override
  String get onrampErrorWalletChanged =>
      'Refresh your wallet before continuing.';

  @override
  String get onrampErrorUnavailable =>
      'Couldn’t open payment. Try again in a moment.';

  @override
  String get onrampErrorStep => 'This step didn’t finish. Try again.';

  @override
  String get onrampErrorEmail => 'Enter an email for your receipt.';

  @override
  String get onrampErrorRefresh =>
      'Couldn’t refresh this deposit. Check again before paying again.';

  @override
  String get onrampTestDoneTitle => 'Test deposit complete';

  @override
  String get onrampDoneTitle => 'Money added';

  @override
  String get onrampFailedTitle => 'Deposit needs attention';

  @override
  String get onrampPendingTitle => 'Finish your deposit';

  @override
  String get onrampTestDoneBody => 'Test USDC arrived on Solana devnet.';

  @override
  String get onrampDoneBody => 'Your USDC is in your wallet.';

  @override
  String get onrampFailedBody =>
      'Contact Crossmint with this order ID. Don’t pay again.';

  @override
  String get onrampPendingBody =>
      'Finish payment in your browser, then return here.';

  @override
  String get onrampOpenPayment => 'Open payment';

  @override
  String onrampOrderId(String orderId) {
    return 'Order $orderId';
  }

  @override
  String get onrampCheckingOptions => 'Checking payment options…';

  @override
  String get onrampCardUnavailable => 'Card deposits aren’t available yet.';

  @override
  String get onrampTransferFromWallet => 'Transfer from a wallet';

  @override
  String get onrampTestCheckout => 'Test checkout';

  @override
  String get onrampMethods => 'Card, Apple Pay or Google Pay';

  @override
  String get onrampMethodsNote => 'Available options appear at checkout.';

  @override
  String get onrampAmountLabel => 'Amount';

  @override
  String get onrampReceiptEmail => 'Receipt email';

  @override
  String get onrampUsdcNote => 'USDC on Solana. Fees shown at checkout.';

  @override
  String get onrampConfirmWallet =>
      'Confirm this wallet is yours. This signs a message, not a payment.';

  @override
  String get onrampVerificationMessage => 'Verification message';

  @override
  String get onrampOneMoment => 'One moment…';

  @override
  String get onrampVerifyContinue => 'Verify & continue';

  @override
  String get onrampPoweredByCrossmint => 'Powered by Crossmint';

  @override
  String get signInTitleDeskAwaits => 'Your desk awaits.';

  @override
  String get signInTitleTrimmy => 'Sign in to Trimmy.';

  @override
  String get signInCaption => 'Sign in or create your account.';

  @override
  String get signInCaptionExpired =>
      'Open your account desk. The expired guest desk stays separate.';

  @override
  String get signInNoticeExpired =>
      'Closing sign-in keeps the expired guest desk preserved.';

  @override
  String get signInErrorConnection =>
      'We could not connect your account. Your desk is still here.';

  @override
  String get signInErrorConnectionExpired =>
      'We could not connect your account. Your previous desk is preserved.';

  @override
  String get signInErrorUnfinished => 'That did not finish. Try again.';

  @override
  String get signInClosed => 'Sign-in was closed. Your desk is still here.';

  @override
  String get signInClosedExpired =>
      'Sign-in was closed. Your previous desk is preserved.';

  @override
  String get signInErrorCode => 'That code did not work. Try again.';

  @override
  String get signInUnavailable => 'Sign-in is unavailable right now.';

  @override
  String get signInErrorEmailInvalid => 'Enter a full email address.';

  @override
  String get signInErrorSendCode => 'We could not send the code. Try again.';

  @override
  String get signInErrorCodeMissing => 'Enter the code from your email.';

  @override
  String get signInCloseTooltip => 'Close sign in';

  @override
  String get signInUseDifferentEmail => 'Use a different email';

  @override
  String get signInTitleSaveDesk => 'Save your desk.';

  @override
  String get signInTitleCheckEmail => 'Check your email.';

  @override
  String get signInTitleYourEmail => 'Your email.';

  @override
  String get signInExpiredDeskSeparate =>
      'The expired guest desk stays separate.';

  @override
  String get signInDeskStaysOnPhone => 'Your desk stays on this phone.';

  @override
  String signInCodeSentTo(String email) {
    return 'We sent a code to $email.';
  }

  @override
  String get signInWeWillSendCode => 'We’ll send you a sign-in code.';

  @override
  String get signInNotSetUp =>
      'Account sign-in is not set up in this build. Your desk stays on this phone.';

  @override
  String get signInNotSetUpExpired =>
      'Account sign-in is not set up in this build. The expired guest desk stays preserved.';

  @override
  String get signInContinueAsGuest => 'Continue as guest';

  @override
  String get signInLater => 'Later';

  @override
  String get signInCodeLabel => 'Code';

  @override
  String get signInEmailLabel => 'Email address';

  @override
  String get signInSendCode => 'Send code';

  @override
  String get signInWelcomeBackTitle => 'Welcome back.';

  @override
  String get signInWelcomeBackCaption => 'Your next move is waiting.';

  @override
  String get signInOr => 'OR';

  @override
  String get signInContinueWithEmail => 'Continue with email';

  @override
  String get signInBusyValue => 'In progress';

  @override
  String signInContinueWithProvider(String provider) {
    return 'Continue with $provider';
  }

  @override
  String get careerWorldNextNeighbourhood => 'The next neighbourhood';

  @override
  String get careerWorldMoreOnTheWay => 'More assignments are on the way.';

  @override
  String careerWorldLockedHint(int day) {
    return 'Complete day $day to open this desk.';
  }

  @override
  String get careerWorldLoading => 'Opening your week…';

  @override
  String get careerWorldLoadFailed => 'Your assignments couldn’t load.';

  @override
  String get careerWorldBeyondFirstMonth => 'Beyond the first month';

  @override
  String get careerWorldCityGrowing => 'The city keeps growing';

  @override
  String get careerWorldStartHere => 'START HERE';

  @override
  String get careerWorldContinue => 'CONTINUE';

  @override
  String get careerWorldComingLater => 'Coming later';

  @override
  String get careerWorldFiled => 'Filed';

  @override
  String careerWorldDayFiled(int day) {
    return 'Day $day, filed';
  }

  @override
  String careerWorldDayCurrent(int day) {
    return 'Day $day, current assignment';
  }

  @override
  String careerWorldDayLocked(int day) {
    return 'Day $day, locked';
  }

  @override
  String careerWorldDayComingLater(int day) {
    return 'Day $day, coming later';
  }

  @override
  String get workdayEntryReload => 'Reload your assignment';

  @override
  String workdayEntryEyebrow(int day, String speaker) {
    return 'DAY $day · $speaker';
  }

  @override
  String get workdayEntryNext => 'Your next assignment';

  @override
  String get workdayEntryContinue => 'Continue your assignment';

  @override
  String get deskActivityTitle => 'Your activity';

  @override
  String get deskActivityEmpty => 'Your first trade starts the story.';

  @override
  String deskActivityBought(String symbol) {
    return 'Bought $symbol';
  }

  @override
  String deskActivitySold(String symbol) {
    return 'Sold $symbol';
  }

  @override
  String get deskCommunityTitle => 'Community';

  @override
  String get deskCommunityPrompt => 'See what traders are saying';

  @override
  String get deskCommunityLoadFailed => 'Community couldn’t load';

  @override
  String get deskCommunityOpening => 'Opening community…';

  @override
  String get deskCommunityStart => 'Start a conversation';

  @override
  String get deskCommunitySubtitle => 'Public comments from other traders.';

  @override
  String deskCommunityPostByHandle(String handle, String cashtag) {
    return '@$handle on $cashtag';
  }

  @override
  String deskCommunityPostByTrader(String cashtag) {
    return 'A trader on $cashtag';
  }

  @override
  String get deskTitle => 'Your desk';

  @override
  String get deskUpdatesTooltip => 'Updates';

  @override
  String get deskOpenProfile => 'Open profile';

  @override
  String deskPersonaPicture(String name) {
    return '$name profile picture';
  }

  @override
  String deskStreakLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'day streak',
    );
    return '$_temp0';
  }

  @override
  String get deskHoldingsTitle => 'Holdings';

  @override
  String get deskExplore => 'Explore';

  @override
  String deskShareCount(num count, String quantity) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$quantity shares',
    );
    return '$_temp0';
  }

  @override
  String get deskPickTraderTitle => 'Pick your trader';

  @override
  String get deskPickTraderSubtitle => 'Make this desk yours.';

  @override
  String get deskSaveTitle => 'Save your desk';

  @override
  String get deskSaveSubtitle => 'Keep it on your other devices.';

  @override
  String get deskCareerFallback => 'Your career';

  @override
  String get deskNextStepFallback => 'See your next step';

  @override
  String get deskEmptyTitle => 'No stocks yet';

  @override
  String get deskEmptyBody => 'Pick a company to begin.';

  @override
  String get deskEmptyExplore => 'Explore stocks';

  @override
  String get deskHoldingValueUnavailable => 'Value unavailable';

  @override
  String clockWallStreetClosesIn(String duration) {
    return 'Stocks trade here 24/7. Wall Street closes in $duration.';
  }

  @override
  String clockWallStreetOpensIn(String duration) {
    return 'Stocks trade here 24/7. Wall Street opens in $duration.';
  }

  @override
  String clockDurationMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '${minutes}m',
    );
    return '$_temp0';
  }

  @override
  String clockDurationHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '${hours}h',
    );
    return '$_temp0';
  }

  @override
  String clockDurationHoursMinutes(int hours, int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '${hours}h ${minutes}m',
    );
    return '$_temp0';
  }

  @override
  String clockDurationDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '${days}d',
    );
    return '$_temp0';
  }

  @override
  String clockDurationDaysHours(int days, int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '${days}d ${hours}h',
    );
    return '$_temp0';
  }

  @override
  String get workdayDraftSaved => 'Saved';

  @override
  String get workdayDraftNotSaved => 'Not saved yet';

  @override
  String get workdayLeaveTitle => 'Leave this note?';

  @override
  String get workdayLeaveBody => 'Your latest edits haven’t saved yet.';

  @override
  String get workdayLeaveKeepWriting => 'Keep writing';

  @override
  String get workdayLeaveWithoutSaving => 'Leave without saving';

  @override
  String get workdaySaveRetry => 'Couldn’t save yet. Try again.';

  @override
  String workdayDayTitle(int day) {
    return 'Day $day';
  }

  @override
  String get workdaySaveAndClose => 'Save and close';

  @override
  String get workdayFiledTitle => 'Filed.';

  @override
  String workdayTrimsEarned(int trims) {
    return '+$trims Trims';
  }

  @override
  String workdayNextDay(int day, String title) {
    return 'Day $day: $title';
  }

  @override
  String get workdayHintShow => 'Hint?';

  @override
  String get workdayHintHide => 'Hide hint';

  @override
  String get workdayFileHeading => 'Send the desk an update';

  @override
  String get workdayFileBody => 'Keep the two facts the source supports.';

  @override
  String get workdayNoteHint => 'Add a note (optional)';

  @override
  String get workdayButtonBack => 'Back to the street';

  @override
  String get workdayButtonCheckEvidence => 'Check the evidence';

  @override
  String get workdayButtonSendDecision => 'Send your decision';

  @override
  String get workdayButtonFile => 'File update';

  @override
  String get workdayPinDetail => 'Pin detail';

  @override
  String get workdayUnpinDetail => 'Unpin detail';

  @override
  String get workdayOpensSoon => 'Opens soon';

  @override
  String get workdayOpensTomorrow => 'Opens tomorrow';

  @override
  String workdayOpensOnWeekday(String weekday) {
    return 'Opens $weekday';
  }

  @override
  String workdayOpensOnDate(String date) {
    return 'Opens $date';
  }

  @override
  String get workdayErrorCheckEvidence =>
      'Check the source again. Those details don’t support this update.';

  @override
  String get workdayErrorCheckDecision => 'Take another look at the figures.';

  @override
  String get workdayErrorTomorrow =>
      'Today’s assignment is done. Your next workday opens soon.';

  @override
  String get workdayErrorClosed =>
      'The desk is closed today. Come back on the next workday.';

  @override
  String get workdayErrorChanged =>
      'Your work changed on another screen. We’ve refreshed it.';

  @override
  String get workdayErrorLocked => 'File the earlier assignment first.';

  @override
  String get workdayErrorSession =>
      'Your account changed. Open your desk again.';

  @override
  String get workdayErrorSaveFailed =>
      'Couldn’t save yet. Your work is still here. Try again.';

  @override
  String get careerMissionFirstPaperBuyTitle => 'Buy your first stock';

  @override
  String get careerMissionWriteAReasonTitle => 'Write your reason';

  @override
  String get careerMissionHoldThroughRedDayTitle => 'Hold through a red day';

  @override
  String get careerErrorOffline =>
      'Your career is offline. Check your connection and try again.';

  @override
  String get careerErrorTimeout =>
      'Your career took too long to open. Try again.';

  @override
  String get careerErrorSession =>
      'Your career needs a fresh session. Try again.';

  @override
  String get careerErrorRateLimited =>
      'Your career is refreshing too quickly. Try again shortly.';

  @override
  String get careerErrorProfileRequired =>
      'Finish setting up your Trimmy profile, then try again.';

  @override
  String get careerErrorUnavailable => 'Your career is unavailable. Try again.';

  @override
  String careerStreakDays(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText day streak',
    );
    return '$_temp0';
  }

  @override
  String get careerStreakRetryActivity => 'Retry activity';

  @override
  String careerStreakDaySemantics(String date, String status) {
    String _temp0 = intl.Intl.selectLogic(status, {
      'active': 'active',
      'upcoming': 'upcoming',
      'none': 'no activity',
      'unavailable': 'activity unavailable',
      'other': 'activity unavailable',
    });
    return '$date, $_temp0';
  }

  @override
  String get careerYourProgress => 'Your progress';

  @override
  String get careerPointsLabel => 'Career points';

  @override
  String careerTrimsCount(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText Trims',
    );
    return '$_temp0';
  }

  @override
  String careerTrimsAwarded(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$countText Trims',
    );
    return '$_temp0';
  }

  @override
  String get communityTitle => 'Community';

  @override
  String get communityUpdatesTitle => 'Updates';

  @override
  String get communityScopeEveryone => 'Everyone';

  @override
  String get communityScopeFollowing => 'Following';

  @override
  String get communityLoadFailed => 'Couldn’t load activity. Try again.';

  @override
  String get communitySaveFailed => 'That change didn’t save. Try again.';

  @override
  String get communityEmptyUpdatesTitle => 'You’re all caught up';

  @override
  String get communityEmptyUpdatesBody =>
      'New comments from people you follow appear here.';

  @override
  String get communityEmptyFollowingTitle => 'Your people, here';

  @override
  String get communityEmptyFollowingBody => 'Follow a trader from Everyone.';

  @override
  String get communityEmptyEveryoneTitle => 'No shared comments yet';

  @override
  String get communityEmptyEveryoneBody => 'Public comments will appear here.';

  @override
  String get communityAnonymousTrader => 'Trader';

  @override
  String get communityFollowingButton => 'Following';

  @override
  String get communityFollowButton => '+ Follow';

  @override
  String get communityCommentOptions => 'Comment options';

  @override
  String get communityMuteUpdates => 'Mute updates';

  @override
  String get communityTurnOnUpdates => 'Turn on updates';

  @override
  String get communityReport => 'Report';

  @override
  String get communityBlockTrader => 'Block trader';

  @override
  String communityPostTime(String date, String time) {
    return '$date · $time';
  }

  @override
  String get communityLoadMore => 'Load more';

  @override
  String get floorTitle => 'Career';

  @override
  String get floorCloseProgress => 'Close progress';

  @override
  String get floorProgressButton => 'Progress';

  @override
  String get floorCareerLoadFailed => 'Career couldn’t load';

  @override
  String get floorBrowseStocks => 'Browse stocks';

  @override
  String get floorTrimsTooltip =>
      'Trims are career points. Earn them through activities to move up in rank.';

  @override
  String get floorMilestonesTitle => 'Career milestones';

  @override
  String get floorMilestonesActivities => 'Your activities';

  @override
  String floorMilestonesComplete(String complete, String total) {
    return '$complete of $total complete';
  }

  @override
  String get floorMilestonesUpdating => 'Updating your progress…';

  @override
  String get floorActivitiesLoadFailed => 'Activities couldn’t load';

  @override
  String get floorMissionCommentTitle => 'Comment on your trade';

  @override
  String get floorMissionStatusComplete => 'Complete';

  @override
  String get floorMissionStatusReady => 'Ready';

  @override
  String get floorMissionStatusLocked => 'Locked';

  @override
  String get floorMissionHoldHint => 'Keep a stock through a down day.';

  @override
  String get floorMissionWriteComment => 'Write a comment';

  @override
  String get floorMissionFindStock => 'Find a stock';

  @override
  String floorMissionBecomeRank(String rank) {
    return 'Become $rank';
  }

  @override
  String floorPromotionUnlocked(String rank) {
    return '$rank unlocked';
  }

  @override
  String get floorRankHighestReached => 'Highest rank reached';

  @override
  String floorRankPromotionReady(String rank) {
    return 'Promotion ready for $rank';
  }

  @override
  String get floorRankThresholdReached =>
      'Threshold reached. Finish the promotion mission';

  @override
  String floorRankTrimsToNext(int count, String countText, String rank) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText to $rank',
    );
    return '$_temp0';
  }

  @override
  String floorRankProgressSemantics(String percent, String status) {
    return 'Rank progress $percent percent. $status';
  }

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileYourProfile => 'Your profile';

  @override
  String get profileGuestTitle => 'Make it yours';

  @override
  String get profileGuestBody =>
      'Sign in to keep your trades and career together.';

  @override
  String get profileProgressRefreshFailed => 'Progress couldn’t refresh.';

  @override
  String get profileLoadProgress => 'Load progress';

  @override
  String get profileChooseTrader => 'Choose your trader';

  @override
  String get profileYourTrader => 'Your trader';

  @override
  String get profileChangeTrader => 'Change your trader';

  @override
  String profileStreakDays(int count, String countText) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countText days',
      one: '$countText day',
    );
    return '$_temp0';
  }

  @override
  String get profileStreakLabel => 'Streak';

  @override
  String get socialReportCategorySpam => 'Spam';

  @override
  String get socialReportCategoryHarassment => 'Harassment';

  @override
  String get socialReportCategoryImpersonation => 'Impersonation';

  @override
  String get socialReportCategoryUnsafe => 'Unsafe content';

  @override
  String get socialReportCategoryOther => 'Something else';

  @override
  String get infoHelpTitle => 'Help';

  @override
  String get infoTermsTitle => 'Terms';

  @override
  String get infoPrivacyTitle => 'Privacy';

  @override
  String get infoContactTitle => 'Talk to us';

  @override
  String get infoContactBody => 'Find @trimmyhq on X for help or feedback.';

  @override
  String get infoLinkCopied => 'Link copied';

  @override
  String get infoCopyContactLink => 'Copy contact link';

  @override
  String get infoCopyWebsiteLink => 'Copy website link';

  @override
  String infoLastUpdated(String date) {
    return 'Last updated $date';
  }

  @override
  String infoProviderPolicyLink(String provider, String url) {
    return '$provider: $url';
  }

  @override
  String get infoPracticeAndCareerTitle => 'Practice and Career';

  @override
  String get infoPrivacyHeading => 'Privacy, in plain words.';

  @override
  String get infoPrivacyIntro =>
      'This notice describes information handled by the Trimmy app and its supporting services.';

  @override
  String get infoPrivacyAccountTitle => 'Your account or guest session';

  @override
  String get infoPrivacyAccountBody =>
      'Sign-in uses Privy and the email or social provider you choose. Trimmy receives account identifiers, session credentials and available linked-account details, such as your email, handle or profile image, to authenticate you and recover your progress. Continuing as a guest creates a separate session; guest activity can also be stored on our server. Signing in can link that progress to your account.';

  @override
  String get infoPrivacyPracticeBody =>
      'Your practice orders, balances, activity answers, completed workdays, streaks, Trims, watchlist and trader profile support the game and your progress. Preferences and unfinished activity drafts can be saved on your device; account and progress records are also stored on our server.';

  @override
  String get infoPrivacyCommentsTitle => 'Comments and following';

  @override
  String get infoPrivacyCommentsBody =>
      'Your comment-sharing choice controls which other users can see your comments with your handle, trader persona and the asset discussed. The community feed does not publish your order amounts or wallet balance. We store follows, sharing preferences, blocks and reports to provide these features and address abuse. Public blockchain activity remains visible independently of these settings.';

  @override
  String get infoPrivacyWalletsTitle => 'Wallets and real trades';

  @override
  String get infoPrivacyWalletsBody =>
      'Privy supplies the embedded wallet and signing interface. Trimmy uses your public Solana address to read balances, request quotes and prepare reviewed transactions. Our server receives signed transactions for submission and stores order terms, transaction references and status. Wallet addresses, token amounts and transaction signatures are public on the blockchain. Closing Trimmy cannot erase those records.';

  @override
  String get infoPrivacyFundingTitle => 'Funding';

  @override
  String get infoPrivacyFundingBody =>
      'When you use Crossmint checkout, Trimmy shares the email, destination wallet, requested amount and wallet-ownership proof needed to prepare the order. Crossmint handles payment and identity-verification information in its checkout. Trimmy receives order and delivery status; our onramp server does not collect card numbers or verification documents.';

  @override
  String get infoPrivacyRemindersBody =>
      'Career reminders are scheduled on your device with your permission. You can change the reminder preference in Trimmy or disable notifications in device settings. Trade updates are optional on supported devices. If enabled, we store a device notification token and use Firebase Cloud Messaging to send a short update when a real order finishes. Amounts and balances are not included. You can turn trade updates off in Settings. Social and price alerts are not available yet.';

  @override
  String get infoPrivacyServicesTitle => 'Services and technical records';

  @override
  String get infoPrivacyServicesBody =>
      'Hosting and database providers support the app. Market-data services receive asset queries; Jupiter and blockchain providers receive wallet or transaction queries needed for real trading. Privy, your sign-in provider and Crossmint handle information under their own policies and may process it in other countries. Network information, request times, identifiers and errors help deliver the service, limit abuse and investigate failures.';

  @override
  String get infoPrivacyChoicesTitle => 'Your choices and records';

  @override
  String get infoPrivacyChoicesBody =>
      'You can change sharing and reminder preferences in Settings. Signing out does not delete server records. Closing an account disables access but does not erase its historical records, delete your provider account, move assets or remove blockchain data. Clearing app data can remove local progress and access information; make sure you can recover a funded wallet before doing so.';

  @override
  String get infoPrivacyRequestsBody =>
      'Contact @trimmyhq on X to ask about access, correction or deletion of information held by Trimmy. Ask for a private conversation and do not post credentials or personal documents publicly. We may need to verify the request. Provider records follow their own policies; blockchain records cannot be deleted by Trimmy.';

  @override
  String get infoPrivacyProvidersTitle => 'Provider privacy policies';

  @override
  String get infoTermsHeading => 'Using Trimmy.';

  @override
  String get infoTermsIntro =>
      'Trimmy combines a trading simulation with a separate real-money mode. These terms describe the app as it works today. Features remain in development.';

  @override
  String get infoTermsPracticeBody =>
      'Paper balances and orders are simulated. Trims, streaks and Career ranks record game progress; they cannot be withdrawn as money. Practice can use sample or market reference data. Completing an activity does not establish investment suitability, and comments from other users are their own views. Educational content is not personalized investment, legal or tax advice.';

  @override
  String get infoTermsRealMoneyTitle => 'Real money';

  @override
  String get infoTermsRealMoneyBody =>
      'Real mode uses a Solana mainnet wallet and supported tokenized stocks. An order can move real assets when you review and confirm it. Check the asset, amount, fees and destination before approving. A quote is an estimate that can expire; a submitted or pending order is not a confirmed trade. History currently shows reviewed quote amounts, not a complete statement of final fills, fees or external transfers.';

  @override
  String get infoTermsTokenizedBody =>
      'Tokenized stocks are subject to their issuer terms and do not necessarily give the same rights as directly holding company shares. Prices can fall, liquidity can disappear, and issuer, network or provider failures can cause loss. Trimmy does not promise returns or execution at a displayed price.';

  @override
  String get infoTermsFundingTitle => 'Funding your wallet';

  @override
  String get infoTermsFundingBody =>
      'Send only supported USDC or SOL to the displayed address on the Solana network. Verify the address and network before sending; a completed blockchain transfer cannot simply be undone by Trimmy. SOL is also needed for network fees. Crossmint card checkout is currently a test environment: its test funds do not fund mainnet trades. Its production availability, payment methods, verification and fees depend on the provider.';

  @override
  String get infoTermsAccessTitle => 'Account access';

  @override
  String get infoTermsAccessBody =>
      'Protect your sign-in method and review wallet prompts carefully. Never share a private key, recovery phrase or one-time sign-in code with support. This build does not yet provide in-app withdrawals or wallet export. Closing your account does not withdraw assets. Resolve wallet access before closing an account or removing the app from a funded device.';

  @override
  String get infoTermsEligibilityTitle => 'Eligibility and other services';

  @override
  String get infoTermsEligibilityBody =>
      'You must meet the applicable asset issuer and service-provider requirements, including location and eligibility restrictions. Seeing an asset or obtaining a quote does not establish eligibility. Privy, Crossmint, trading providers and asset issuers have separate terms. Trimmy does not promise availability in every country.';

  @override
  String get infoTermsCommunityTitle => 'Using the community';

  @override
  String get infoTermsCommunityBody =>
      'Share comments you have the right to publish. Do not impersonate others, expose private information, manipulate the market, harass users or interfere with accounts and services. Sharing settings, blocking and reporting tools are available for comments and community interactions.';

  @override
  String get infoTermsAvailabilityTitle => 'Availability and questions';

  @override
  String get infoTermsAvailabilityBody =>
      'Market data, quotes, notifications and network confirmation can be delayed or unavailable. Features and these notices may change as development continues. Nothing here removes rights that cannot be excluded under applicable law. Contact @trimmyhq on X for help or questions about these terms.';

  @override
  String get settingsReminders => 'Reminders';

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsSignInDetail => 'Sign in to keep your progress.';

  @override
  String get settingsHandle => 'Handle';

  @override
  String get settingsYourTrader => 'Your trader';

  @override
  String get settingsChooseCharacter => 'Choose a character';

  @override
  String get settingsEmail => 'Email';

  @override
  String get settingsSignInMethods => 'Sign-in methods';

  @override
  String get settingsSignInMethodsUnavailable => 'Sign-in method unavailable.';

  @override
  String get settingsSignInMethodEmail => 'Email';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsNotificationsSection => 'Notifications';

  @override
  String get settingsNotificationGroupMarket => 'Market';

  @override
  String get settingsNotificationGroupCareer => 'Career';

  @override
  String get settingsNotificationGroupSocial => 'Social';

  @override
  String get settingsNotificationGroupAccount => 'Account';

  @override
  String get settingsNotificationOpen => 'Wall Street open';

  @override
  String get settingsNotificationOpenDetail => 'When Wall Street opens.';

  @override
  String get settingsNotificationClose => 'Wall Street close';

  @override
  String get settingsNotificationCloseDetail => 'When Wall Street closes.';

  @override
  String get settingsNotificationEvents => 'Events on my stocks';

  @override
  String get settingsNotificationEventsDetail =>
      'Updates that affect stocks you hold.';

  @override
  String get settingsNotificationPrices => 'Price alerts';

  @override
  String settingsNotificationPricesDetail(String small, String large) {
    return 'Moves of $small or $large on followed stocks.';
  }

  @override
  String get settingsNotificationStreak => 'Streak reminder';

  @override
  String get settingsNotificationStreakDetail => 'When your streak is at risk.';

  @override
  String get settingsNotificationMissions => 'Missions';

  @override
  String get settingsNotificationMissionsDetail => 'New missions and progress.';

  @override
  String get settingsNotificationPromotions => 'Promotions';

  @override
  String get settingsNotificationPromotionsDetail =>
      'When you earn a new rank.';

  @override
  String get settingsNotificationLeague => 'League';

  @override
  String get settingsNotificationLeagueDetail =>
      'League results and position changes.';

  @override
  String get settingsNotificationFriends => 'Friends';

  @override
  String get settingsNotificationFriendsDetail =>
      'Friends\' trades and reasons.';

  @override
  String get settingsNotificationTrades => 'Trade updates';

  @override
  String get settingsNotificationTradesDetail =>
      'When a real-money order finishes.';

  @override
  String get settingsNotificationNews => 'News from Trimmy';

  @override
  String get settingsNotificationNewsDetail => 'Product news and updates.';

  @override
  String get settingsNotAvailableYet => 'Not available yet.';

  @override
  String get settingsQuietHours => 'Quiet hours';

  @override
  String settingsQuietHoursRange(String start, String end) {
    return '$start to $end';
  }

  @override
  String get settingsEditQuietHours => 'Edit quiet hours';

  @override
  String get settingsPreferencesSection => 'Preferences';

  @override
  String get settingsSound => 'Sound';

  @override
  String get settingsSoundDetail => 'Sounds for key moments.';

  @override
  String get settingsHaptics => 'Haptics';

  @override
  String get settingsHapticsDetail => 'Taps you can feel.';

  @override
  String get settingsAnimations => 'Animations';

  @override
  String get settingsAnimationsLimited => 'Limited by your phone setting.';

  @override
  String get settingsAnimationsDetail => 'Movement and celebrations.';

  @override
  String get settingsReduceMotion => 'Reduce motion';

  @override
  String get settingsReduceMotionOn => 'On. Follows your phone setting.';

  @override
  String get settingsReduceMotionOff => 'Off. Follows your phone setting.';

  @override
  String get settingsPaperLimit => 'Paper limit';

  @override
  String get settingsResetPaper => 'Reset paper';

  @override
  String get settingsResetPaperBusy => 'Resetting your paper desk.';

  @override
  String get settingsResetPaperPending =>
      'Your confirmed reset is waiting to finish.';

  @override
  String get settingsResetPaperDetail => 'Clear paper trades and start again.';

  @override
  String get settingsResetPaperTitle => 'Reset your paper desk?';

  @override
  String get settingsResetPaperBody =>
      'This starts a fresh paper desk. Past receipts stay in your record. Your Career, Trims, rank, streak and money do not change.';

  @override
  String get settingsResetPaperPhrase => 'reset my paper desk';

  @override
  String settingsResetPaperInstruction(String phrase) {
    return 'Type “$phrase” to continue.';
  }

  @override
  String settingsResetPaperFieldLabel(String phrase) {
    return 'Confirmation phrase. Type $phrase.';
  }

  @override
  String get settingsResetPaperFieldTitle => 'Confirmation phrase';

  @override
  String get settingsResetPaperConfirm => 'Reset paper desk';

  @override
  String get settingsResetPaperDoneTitle => 'Paper desk reset';

  @override
  String settingsResetPaperDone(String amount) {
    return 'Your desk is ready with $amount paper.';
  }

  @override
  String settingsResetPaperDoneNewer(String amount) {
    return 'Newer trades were kept. Your balance is $amount paper.';
  }

  @override
  String get settingsResetPaperFailed => 'Paper was not reset. Try again.';

  @override
  String get settingsResetPaperStale =>
      'Your paper desk changed. It was refreshed. Review it, then confirm the reset again.';

  @override
  String get settingsResetPaperNotNeeded =>
      'Your paper desk is already fresh. Nothing was cleared.';

  @override
  String get settingsResetPaperOffline =>
      'You are offline. Your exact reset request is saved for a safe retry.';

  @override
  String get settingsResetPaperTimeout =>
      'The reset took too long to confirm. Your exact request is saved for a safe retry.';

  @override
  String get settingsResetPaperAccountRequired =>
      'Your paper desk needs a fresh session before the reset can finish.';

  @override
  String get settingsResetPaperRateLimited =>
      'Paper resets are limited. Try this saved request again later.';

  @override
  String get settingsResetPaperUnavailable =>
      'The reset could not be confirmed. Your exact request is saved for a safe retry.';

  @override
  String get settingsResetPaperRejected =>
      'Paper was not reset. Refresh your desk and try again.';

  @override
  String get settingsMoneySection => 'Money';

  @override
  String get settingsMoneyCardOrCrypto => 'Card or crypto';

  @override
  String get settingsMoneyComingSoon => 'Money trading is coming later.';

  @override
  String get settingsMoneyUnavailable =>
      'Money features are unavailable for this account.';

  @override
  String get settingsCurrency => 'Currency';

  @override
  String get settingsDepositPartner => 'Deposit partner';

  @override
  String get settingsFees => 'Fees';

  @override
  String get settingsCountryCheck => 'Country check';

  @override
  String get settingsBankAccounts => 'Bank accounts';

  @override
  String get settingsCards => 'Cards';

  @override
  String get settingsWallet => 'Wallet';

  @override
  String get settingsWalletNoDetails => 'No wallet details are available yet.';

  @override
  String get settingsWalletComingSoon => 'Wallet tools are coming later.';

  @override
  String get settingsWalletUnavailable =>
      'Wallet tools are unavailable for this account.';

  @override
  String get settingsCheckWallet => 'Check wallet';

  @override
  String get settingsBackUpWallet => 'Back up wallet';

  @override
  String get settingsBackUpWalletDetail => 'Keep access outside Trimmy.';

  @override
  String get settingsPrivacySection => 'Privacy';

  @override
  String get settingsHoldingsVisibility => 'Who sees my holdings';

  @override
  String get settingsVisibilityFriends => 'Friends';

  @override
  String get settingsVisibilityEveryone => 'Everyone';

  @override
  String get settingsVisibilityNobody => 'Nobody';

  @override
  String get settingsDownloadData => 'Download my data';

  @override
  String get settingsSupportSection => 'Support';

  @override
  String get settingsSendFeedback => 'Send feedback';

  @override
  String get settingsReportBug => 'Report a bug';

  @override
  String get settingsReportBugDetail => 'Your app version will be attached.';

  @override
  String get settingsLegalSection => 'Legal';

  @override
  String get settingsRiskNotice => 'Risk notice';

  @override
  String get settingsAboutTokenizedStocks => 'About tokenized stocks';

  @override
  String get settingsAboutTokenizedStocksDetail =>
      'What they are and what they are not.';

  @override
  String get settingsAccountClosureSection => 'Account closure';

  @override
  String get settingsCloseAccount => 'Close account';

  @override
  String get settingsCloseAccountDetail =>
      'Review what happens to your records and wallet.';

  @override
  String get sendErrorCheckInput => 'Check the address and the amount.';

  @override
  String get sendErrorSelf => 'That’s your own wallet. Enter another address.';

  @override
  String get sendErrorNotWallet =>
      'That address isn’t a wallet. It may be a token account or a program. Ask for the wallet address instead.';

  @override
  String get sendErrorDestinationFrozen =>
      'That wallet can’t receive this token right now.';

  @override
  String get sendErrorAssetUnsupported =>
      'This token can’t be sent from Trimmy.';

  @override
  String get sendErrorNotTransferable =>
      'This token has transfer rules Trimmy can’t send with.';

  @override
  String get sendErrorAssetPaused => 'Its issuer has paused transfers for now.';

  @override
  String get sendErrorAssetFrozen =>
      'This token is frozen in your wallet. Contact its issuer.';

  @override
  String get sendErrorInsufficient => 'You don’t have that much ready to send.';

  @override
  String get sendErrorAddSol => 'Add a little SOL to cover the network fee.';

  @override
  String sendErrorLeaveSol(String amount) {
    return 'Leave at least $amount SOL, or send all of it.';
  }

  @override
  String sendErrorTooSmall(String amount) {
    return 'A new wallet needs at least $amount SOL to open.';
  }

  @override
  String get sendErrorCheckFailed =>
      'This send didn’t pass its check. Nothing was sent.';

  @override
  String get sendErrorReviewExpired => 'This review expired. Review it again.';

  @override
  String get sendErrorPrevious =>
      'Check your previous send before starting another.';

  @override
  String get sendErrorMismatch =>
      'This transaction doesn’t match your review. Nothing was sent.';

  @override
  String get sendErrorStorage =>
      'Allow device storage to keep your send recoverable.';

  @override
  String get sendErrorBusy => 'One moment, then try again.';

  @override
  String get sendErrorCancelled => 'Signing was cancelled. Nothing was sent.';

  @override
  String get sendErrorPaused => 'Sending is paused right now. Try again later.';

  @override
  String get sendErrorGeneric => 'Sending couldn’t connect. Try again.';

  @override
  String get sendRecoveryFailed =>
      'Your previous send couldn’t be checked. Try checking again.';

  @override
  String get sendEnterAddress => 'Enter a Solana wallet address.';

  @override
  String get sendEnterAmount => 'Enter an amount.';

  @override
  String sendHaveReady(String amount) {
    return 'You have $amount ready to send.';
  }

  @override
  String get sendTitle => 'Send';

  @override
  String get sendCheckPrevious => 'Check previous send';

  @override
  String get sendNothingTitle => 'Nothing to send yet';

  @override
  String get sendNothingBody =>
      'Add money or buy a stock first. Anything in your wallet can be sent from here.';

  @override
  String get sendHeading => 'Send to a Solana wallet';

  @override
  String get sendWarning =>
      'Only send to a Solana address. Sends can’t be undone.';

  @override
  String get sendWhatLabel => 'What to send';

  @override
  String get sendAssetUsdc => 'US dollars (USDC)';

  @override
  String get sendRecipientLabel => 'Recipient’s wallet address';

  @override
  String get sendPaste => 'Paste';

  @override
  String get sendSharesLabel => 'Shares';

  @override
  String sendAmountLabel(String symbol) {
    return 'Amount ($symbol)';
  }

  @override
  String sendReadyToSend(String amount) {
    return '$amount ready to send';
  }

  @override
  String sendMaxKeepsSol(String amount) {
    return 'Max keeps $amount SOL so you can still pay network fees.';
  }

  @override
  String get sendReview => 'Review send';

  @override
  String get sendReviewTitle => 'Review your send';

  @override
  String get sendYouSend => 'You send';

  @override
  String get sendTheyReceive => 'They receive, after the issuer fee';

  @override
  String get sendNetworkFee => 'Network fee';

  @override
  String sendOpensAccount(String symbol) {
    return 'Opens their $symbol account (once)';
  }

  @override
  String get sendToWallet => 'To this Solana wallet';

  @override
  String get sendCheckEvery =>
      'Check every character. Sends can’t be undone, and Trimmy can’t get money back from a wrong address.';

  @override
  String get sendNow => 'Send now';

  @override
  String get sendEdit => 'Edit';

  @override
  String get sendResultSent => 'Sent';

  @override
  String get sendResultSending => 'Sending';

  @override
  String get sendResultFailed => 'It didn’t go through';

  @override
  String get sendResultExpired => 'Send expired';

  @override
  String get sendResultChecking => 'Still confirming';

  @override
  String get sendBodySent => 'It’s confirmed on Solana.';

  @override
  String get sendBodySending => 'This usually takes a few seconds.';

  @override
  String get sendBodyFailed =>
      'Solana refused it. Only the network fee was spent.';

  @override
  String get sendBodyExpired =>
      'This transaction expired without confirmation. You can review a new send.';

  @override
  String get sendBodyChecking =>
      'We’re still checking this send. Don’t send it again.';

  @override
  String get sendViewSolscan => 'View on Solscan';

  @override
  String get sendCloseFailed => 'This send is saved. Try closing it again.';

  @override
  String get reminderDailyLabel => 'On workdays';

  @override
  String get reminderDailyCaption => 'Around 7 PM, when work is waiting.';

  @override
  String get reminderOccasionalLabel => 'A few times a week';

  @override
  String get reminderOccasionalCaption => 'Mon, Wed and Fri, around 7 PM.';

  @override
  String get reminderOffLabel => 'Keep it quiet';

  @override
  String get reminderOffCaption => 'I’ll come back on my own.';

  @override
  String get reminderNotificationTitle => 'Your desk is waiting';

  @override
  String get reminderNotificationBody =>
      'Your next assignment is waiting at your desk.';

  @override
  String reminderNotificationDay(int day, String title) {
    return 'Day $day: $title';
  }

  @override
  String get pushErrorNotificationsOff =>
      'Notifications are off in device settings.';

  @override
  String get pushErrorUpdate => 'Couldn’t update notifications. Try again.';

  @override
  String get pushErrorTurnOff =>
      'Couldn’t turn off alerts. Try again when you’re online.';

  @override
  String get pushErrorConnect =>
      'Couldn’t connect notifications. Please try again.';

  @override
  String get signInResendCode => 'Send a new code';

  @override
  String signInResendIn(int seconds) {
    return 'Send again in ${seconds}s';
  }

  @override
  String get appCloseAccountClosing => 'Closing your account…';

  @override
  String get appCloseAccountFailed => 'Your account was not closed. Try again.';
}
