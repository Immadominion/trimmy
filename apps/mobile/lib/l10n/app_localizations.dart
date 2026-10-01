import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('pt'),
  ];

  /// Generic button that closes a sheet or dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic button that moves to the next step.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// Generic button that finishes a flow and closes it.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Generic button or tooltip that closes a sheet, page or dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Generic button or tooltip that goes back one step.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Generic button shown after something failed, to repeat the same action.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Short generic button to repeat a failed action, where space is tight.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Generic button that saves a choice.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Generic button that opens sign-in.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get commonSignIn;

  /// Short button on an amount field that fills in the largest amount allowed. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get commonMax;

  /// Button or label for buying shares of a stock.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get commonBuy;

  /// Button or label for selling shares of a stock.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get commonSell;

  /// Career rank 1 of 6, the starting rank of a new player. Shown as a title, like a job level on Wall Street.
  ///
  /// In en, this message translates to:
  /// **'Rookie'**
  String get rankRookie;

  /// Career rank 2 of 6. A Wall Street job title.
  ///
  /// In en, this message translates to:
  /// **'Analyst'**
  String get rankAnalyst;

  /// Career rank 3 of 6. A Wall Street job title.
  ///
  /// In en, this message translates to:
  /// **'Trader'**
  String get rankTrader;

  /// Career rank 4 of 6. A Wall Street job title.
  ///
  /// In en, this message translates to:
  /// **'Senior Trader'**
  String get rankSeniorTrader;

  /// Career rank 5 of 6. A partner of the firm.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get rankPartner;

  /// Career rank 6 of 6, the top rank.
  ///
  /// In en, this message translates to:
  /// **'Legend'**
  String get rankLegend;

  /// A shortened number in thousands, such as a market cap or a token amount. Keep the unit as short as your language's financial press writes it.
  ///
  /// In en, this message translates to:
  /// **'{value}K'**
  String formatCompactThousand(String value);

  /// A shortened number in millions (10^6), such as a market cap.
  ///
  /// In en, this message translates to:
  /// **'{value}M'**
  String formatCompactMillion(String value);

  /// A shortened number in billions, meaning thousands of millions (10^9), such as a market cap.
  ///
  /// In en, this message translates to:
  /// **'{value}B'**
  String formatCompactBillion(String value);

  /// A shortened number in trillions, meaning millions of millions (10^12), such as a market cap.
  ///
  /// In en, this message translates to:
  /// **'{value}T'**
  String formatCompactTrillion(String value);

  /// Shown in place of a stock's price when no price could be read.
  ///
  /// In en, this message translates to:
  /// **'Price unavailable'**
  String get marketPriceUnavailable;

  /// Generic button or row that opens adding real money (a deposit) to the wallet. Keep short, it sits on buttons.
  ///
  /// In en, this message translates to:
  /// **'Add money'**
  String get commonAddMoney;

  /// Generic busy label while a choice is being saved.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get commonSaving;

  /// Generic busy label while the app checks something with the server.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get commonChecking;

  /// Generic busy label while the app connects to a service.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get commonConnecting;

  /// Generic busy label while something is being sent.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get commonSending;

  /// Generic busy label while an order or action waits for confirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirming…'**
  String get commonConfirming;

  /// Generic loading label.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// Generic button that opens something. Verb. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// Generic button or tooltip that loads the latest data again. Verb.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// Generic button that copies a value, such as a wallet address. Verb. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// Generic button that declines an offer for now.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get commonNotNow;

  /// Generic button that skips an optional step. Verb. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get commonSkip;

  /// Title of the trade history page and buttons that open it.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get commonHistory;

  /// Title of the Settings page and buttons or tooltips that open it.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonSettings;

  /// Screen reader label for a button that is busy. {label} is the button's own label, already translated, such as 'Buy'.
  ///
  /// In en, this message translates to:
  /// **'{label} in progress'**
  String commonInProgress(String label);

  /// Name of Practice mode, where you trade with practice money (English calls it Paper). Shown on the mode switch and labels. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get modePaper;

  /// Name of Real mode, where you trade real tokenized stocks with real money. Shown on the mode switch and labels. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Real'**
  String get modeReal;

  /// Settings row title and the title of the language picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Language choice that follows the phone's own language setting. Shown as the Language row's value in Settings and as the first option in the language picker. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Phone language'**
  String get settingsLanguagePhone;

  /// Line under the 'Phone language' option in the language picker, explaining that the app follows the phone.
  ///
  /// In en, this message translates to:
  /// **'Uses the language your phone is set to.'**
  String get settingsLanguagePhoneDetail;

  /// Short message at the bottom of the screen when the app could not save that the player chose to continue without an account (as a guest).
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save your choice. Try again.'**
  String get appGuestChoiceNotSaved;

  /// Short message at the bottom of the screen when a signed-in player taps the Career screen's "save your desk" prompt. The desk is the player's home screen and progress; "saved" means it is tied to their account.
  ///
  /// In en, this message translates to:
  /// **'Your desk is already saved.'**
  String get appDeskAlreadySaved;

  /// Short message at the bottom of the screen when the player opens Fast buy while their practice desk is reconnecting to the server.
  ///
  /// In en, this message translates to:
  /// **'Your desk is reconnecting. Try again in a moment.'**
  String get appDeskReconnecting;

  /// Short message at the bottom of the screen after the player switches from Real mode to Practice mode (English calls Practice mode "Paper") from a stock page. Use the same mode name as the modePaper key.
  ///
  /// In en, this message translates to:
  /// **'Switched to Paper.'**
  String get appSwitchedToPaper;

  /// Short message at the bottom of the screen when the player opens the Career mission "write a reason" again while the reason they already saved (why they bought a stock) is still being confirmed by the server. "Career" is the Career tab.
  ///
  /// In en, this message translates to:
  /// **'Your saved reason is being checked. Refresh your Career.'**
  String get appReasonBeingChecked;

  /// Short message at the bottom of the screen when the player opens the Career mission "write a reason" while their practice desk (English: "paper desk") is not connected. The reason is why they bought a stock.
  ///
  /// In en, this message translates to:
  /// **'Your confirmed paper desk must be online before you can write this reason.'**
  String get appReasonNeedsPaperDesk;

  /// Short message at the bottom of the screen when the Career mission "write a reason" has no practice-money purchase to write about; the app then opens the Market tab. "Mission" is a Career mission (not a workday assignment). "Paper buy" means a purchase made with practice money.
  ///
  /// In en, this message translates to:
  /// **'This mission needs a confirmed paper buy you still hold. Choose a stock when you are ready.'**
  String get appReasonNeedsPaperBuy;

  /// Short message at the bottom of the screen when the player tries to claim a promotion to the next career rank but their career data is out of date. "the Floor" is the Career screen (the trading floor); translations may simply say "your career".
  ///
  /// In en, this message translates to:
  /// **'Refresh the Floor before claiming this promotion.'**
  String get appPromotionRefreshFirst;

  /// Short message at the bottom of the screen when the app could not prepare the request that claims a promotion to the next career rank.
  ///
  /// In en, this message translates to:
  /// **'Your promotion could not be prepared. Try again.'**
  String get appPromotionNotPrepared;

  /// Short message at the bottom of the screen when the player's career changed while a promotion was being claimed. "the Floor" is the Career screen; translations may say "refresh it".
  ///
  /// In en, this message translates to:
  /// **'Your career changed. Refresh the Floor and try again.'**
  String get appPromotionCareerChanged;

  /// Short message at the bottom of the screen when the player tries to write a reason before their practice desk (English: "paper desk") has finished opening.
  ///
  /// In en, this message translates to:
  /// **'Your paper desk is still opening. Try again.'**
  String get appPaperDeskStillOpening;

  /// Short message at the bottom of the screen after the player's first practice trade went through but the app could not record that the first-trade step of the introduction is done.
  ///
  /// In en, this message translates to:
  /// **'The trade is safe, but this step was not saved.'**
  String get appFirstTradeStepNotSaved;

  /// Short message at the bottom of the screen when tapping a stock (a holding, a feed item) could not open its page.
  ///
  /// In en, this message translates to:
  /// **'This stock couldn’t open. Try again.'**
  String get appStockCouldNotOpen;

  /// Short message at the bottom of the screen when the Real mode trade history could not be opened because the server is not configured or reachable.
  ///
  /// In en, this message translates to:
  /// **'History couldn’t connect. Try again.'**
  String get appHistoryCouldNotConnect;

  /// Short message at the bottom of the screen when reporting another player's shared reason (a post in the community feed) failed.
  ///
  /// In en, this message translates to:
  /// **'Report didn’t send. Try again.'**
  String get appReportNotSent;

  /// Short message at the bottom of the screen when blocking another player from the community feed failed. "trader" is another player.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t block this trader. Try again.'**
  String get appBlockFailed;

  /// Short message at the bottom of the screen after the player copies their Solana wallet address in Settings.
  ///
  /// In en, this message translates to:
  /// **'Wallet address copied.'**
  String get appWalletAddressCopied;

  /// Short message at the bottom of the screen when the wallet backup page (opened in the browser) could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open wallet backup. Try again.'**
  String get appWalletBackupFailed;

  /// Status line while the practice desk (English: "paper desk", where the player trades with practice money) is loading. Shown on the first-trade screen, the Market intro card and stock pages.
  ///
  /// In en, this message translates to:
  /// **'Opening your paper desk.'**
  String get appPaperDeskOpening;

  /// Message on the desk, first-trade screen and stock pages when the practice desk could not load because the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'Your paper desk is offline. Check your connection and try again.'**
  String get appPaperDeskOffline;

  /// Message on the desk, first-trade screen and stock pages when loading the practice desk timed out.
  ///
  /// In en, this message translates to:
  /// **'Your paper desk took too long to open. Try again.'**
  String get appPaperDeskTimeout;

  /// Message on the desk, first-trade screen and stock pages when the practice desk could not load because the sign-in session expired.
  ///
  /// In en, this message translates to:
  /// **'Your paper desk needs a fresh session. Try again.'**
  String get appPaperDeskSession;

  /// Message on the desk, first-trade screen and stock pages when the practice desk could not load for any other reason.
  ///
  /// In en, this message translates to:
  /// **'Your paper desk is unavailable. Try again.'**
  String get appPaperDeskUnavailable;

  /// Status line on the Desk, Career and Profile screens when the career data (rank, Trims, streak) shown is an older saved copy because the latest could not load.
  ///
  /// In en, this message translates to:
  /// **'Showing your last confirmed career record. Refresh to update it.'**
  String get appCareerStale;

  /// Status line in the missions section of the Career screen when the career and its missions came from different moments. Missions are Career missions (goals that lead to a promotion), not workday assignments.
  ///
  /// In en, this message translates to:
  /// **'Your career changed while missions were loading. Refresh to match them.'**
  String get appMissionsMismatch;

  /// Status line in the missions section of the Career screen when the missions shown are an older saved copy.
  ///
  /// In en, this message translates to:
  /// **'Showing your last confirmed missions. Refresh to update them.'**
  String get appMissionsStale;

  /// Status line in the missions section of the Career screen when missions could not load because the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'Your missions are offline. Check your connection and try again.'**
  String get appMissionsOffline;

  /// Status line in the missions section of the Career screen when loading missions timed out.
  ///
  /// In en, this message translates to:
  /// **'Your missions took too long to open. Try again.'**
  String get appMissionsTimeout;

  /// Status line in the missions section of the Career screen when missions could not load because the sign-in session expired.
  ///
  /// In en, this message translates to:
  /// **'Your missions need a fresh session. Try again.'**
  String get appMissionsSession;

  /// Status line in the missions section of the Career screen when the server asked the app to slow down.
  ///
  /// In en, this message translates to:
  /// **'Your missions are refreshing too quickly. Try again shortly.'**
  String get appMissionsRateLimited;

  /// Status line in the missions section of the Career screen when missions need a finished player profile.
  ///
  /// In en, this message translates to:
  /// **'Finish setting up your Trimmy profile, then try again.'**
  String get appMissionsProfileRequired;

  /// Status line in the missions section of the Career screen when missions could not load for any other reason.
  ///
  /// In en, this message translates to:
  /// **'Your missions are unavailable. Try again.'**
  String get appMissionsUnavailable;

  /// Message on the full-screen "Couldn’t open Trimmy" page when the player's profile could not load and no more specific reason is known.
  ///
  /// In en, this message translates to:
  /// **'Your Trimmy profile is unavailable. Try again.'**
  String get appProfileUnavailable;

  /// Message on the full-screen "Couldn’t open Trimmy" page after signing in worked but opening the player's desk (home screen) failed.
  ///
  /// In en, this message translates to:
  /// **'Your account is connected. Try opening your desk again.'**
  String get appAccountEntryFailed;

  /// Label above the total value (cash plus stocks) on the Desk balance card in Real mode, where the player uses real money. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Total balance'**
  String get appRealBalanceLabel;

  /// Line under the Real mode balance on the Desk while the wallet balance is being refreshed.
  ///
  /// In en, this message translates to:
  /// **'Updating balance…'**
  String get appRealBalanceUpdating;

  /// Line under the Real mode balance on the Desk when the balance shown is the USDC (a US dollar stablecoin) cash in the wallet. Keep "USDC".
  ///
  /// In en, this message translates to:
  /// **'USDC available'**
  String get appRealBalanceUsdcAvailable;

  /// Line under the Real mode total balance on the Desk, splitting it into money not invested (cash) and the value of the stocks held. Keep the middle dot separator.
  ///
  /// In en, this message translates to:
  /// **'{cash} cash · {stocks} in stocks'**
  String appRealBalanceSplit(String cash, String stocks);

  /// Status banner on the Desk in Practice mode when both the practice desk (English: "paper desk") and the career data shown are older saved copies because Trimmy is not connected.
  ///
  /// In en, this message translates to:
  /// **'Showing your last confirmed paper desk and career record. Trading is paused until Trimmy reconnects.'**
  String get appDeskStaleBoth;

  /// Status banner on the Desk in Practice mode when the practice desk (English: "paper desk") shown is an older saved copy because Trimmy is not connected.
  ///
  /// In en, this message translates to:
  /// **'Showing your last confirmed paper desk. Trading is paused until Trimmy reconnects.'**
  String get appDeskStalePaper;

  /// Message on a stock page in Real mode (real money) when the app could not reach the trading service, so Buy and Sell are unavailable.
  ///
  /// In en, this message translates to:
  /// **'Trading couldn’t connect.'**
  String get appTradingCouldNotConnect;

  /// Message on a stock page in Real mode while the app checks whether real-money trading is available.
  ///
  /// In en, this message translates to:
  /// **'Checking trading…'**
  String get appTradingChecking;

  /// Message on a stock page in Real mode when real-money trading is switched off for now.
  ///
  /// In en, this message translates to:
  /// **'Trading is temporarily paused.'**
  String get appTradingPaused;

  /// Message on a stock page in Real mode when this stock cannot be bought or sold with real money yet.
  ///
  /// In en, this message translates to:
  /// **'Not tradeable with real money yet.'**
  String get appTradingNotTradeable;

  /// Shown on a stock page's token details in place of the issuer's name (the company that issues the tokenized stock) when it is unknown.
  ///
  /// In en, this message translates to:
  /// **'Issuer unavailable'**
  String get appVersionIssuerUnavailable;

  /// Shown on a stock page's token details when the market data does not say how the tokenized stock is backed by real shares.
  ///
  /// In en, this message translates to:
  /// **'Backing details are not available in this market read.'**
  String get appVersionBackingUnavailable;

  /// Shown on a stock page's token details: the tokenized stock trades on the blockchain, and the issuer's own trading hours are unknown.
  ///
  /// In en, this message translates to:
  /// **'Trades on chain. Issuer hours are unavailable.'**
  String get appVersionTradingHoursUnavailable;

  /// Title of a small sheet shown when the player opens a Career mission while in Real mode. Career missions can only be done with practice money. Translate as a Career mission done in Practice mode (es misión, pt missão, fr objectif).
  ///
  /// In en, this message translates to:
  /// **'A simulator assignment'**
  String get appRealMissionTitle;

  /// Text of the sheet titled "A simulator assignment": the Career mission must be done on the practice desk (with practice money).
  ///
  /// In en, this message translates to:
  /// **'Complete this task on your training desk.'**
  String get appRealMissionBody;

  /// Button on the sheet titled "A simulator assignment" that switches to Practice mode and opens the mission. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Open training desk'**
  String get appRealMissionButton;

  /// Title of the confirmation dialog in Settings before the player permanently closes their account.
  ///
  /// In en, this message translates to:
  /// **'Close your account?'**
  String get appCloseAccountTitle;

  /// Text of the close-account dialog when the account has no wallet with funds to back up. Records the company must keep by law stay protected.
  ///
  /// In en, this message translates to:
  /// **'You will lose access to the saved account. Records that must be kept stay protected.'**
  String get appCloseAccountBodyNoWallet;

  /// Text of the close-account dialog when the account has a Solana wallet: the player should back it up first, since closing the account does not move the money in the wallet.
  ///
  /// In en, this message translates to:
  /// **'Keep access to your wallet before closing your account. Closing will not move its funds. You will lose access to your saved desk.'**
  String get appCloseAccountBodyWallet;

  /// Button in the close-account dialog that opens the wallet backup page first. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Back up wallet'**
  String get appCloseAccountBackUpWallet;

  /// Red button in the close-account dialog that permanently closes the account. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Close account'**
  String get appCloseAccountConfirm;

  /// Card at the top of the Market list during the first-trade step of the introduction, once the practice desk is ready. The trade uses practice money.
  ///
  /// In en, this message translates to:
  /// **'Pick a company. Your first trade is free.'**
  String get appFirstTradePrompt;

  /// Title of the full-screen page while the app loads the player's profile at start.
  ///
  /// In en, this message translates to:
  /// **'Opening Trimmy'**
  String get appOpeningTrimmy;

  /// Title of the full-screen page when the player's profile could not load at start. A message and a Try again button follow.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open Trimmy'**
  String get appCouldNotOpenTrimmy;

  /// Title of the full-screen page while the practice desk (the Desk tab) loads.
  ///
  /// In en, this message translates to:
  /// **'Opening your desk'**
  String get appOpeningDesk;

  /// Title of the full-screen page in the Desk tab when the practice desk could not load. A message and a Try again button follow.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open your desk'**
  String get appCouldNotOpenDesk;

  /// Title of the full-screen page while the app loads the player's first confirmed practice trade, right after the first trade of the introduction.
  ///
  /// In en, this message translates to:
  /// **'Opening your trade'**
  String get appOpeningTrade;

  /// Title of the full-screen page when the player's first confirmed practice trade could not load.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load your trade'**
  String get appCouldNotLoadTrade;

  /// Message under "Couldn’t load your trade", above a Try again button.
  ///
  /// In en, this message translates to:
  /// **'Try again to see your confirmed order.'**
  String get appCouldNotLoadTradeBody;

  /// Screen reader label for the animated logo on the launch screen while the app starts.
  ///
  /// In en, this message translates to:
  /// **'Trimmy is opening'**
  String get appSplashOpening;

  /// Screen reader label for the portrait of Sal, the player's boss on the trading floor. Sal is a name and is never translated.
  ///
  /// In en, this message translates to:
  /// **'Sal, your floor boss'**
  String get designCastSal;

  /// Screen reader label for the portrait of Wolf, a trader character. Wolf is a name and is never translated.
  ///
  /// In en, this message translates to:
  /// **'The Wolf trader portrait'**
  String get designCastWolf;

  /// Screen reader label for the portrait of Oracle, a trader character. Oracle is a name and is never translated.
  ///
  /// In en, this message translates to:
  /// **'The Oracle trader portrait'**
  String get designCastOracle;

  /// Screen reader label for the portrait of Shark, a trader character. Shark is a name and is never translated.
  ///
  /// In en, this message translates to:
  /// **'The Shark trader portrait'**
  String get designCastShark;

  /// Screen reader label for the small folded-sheet icon that marks practice money (English: "paper"). Lowercase.
  ///
  /// In en, this message translates to:
  /// **'paper'**
  String get designPaperMark;

  /// Screen reader label for an amount of practice money (English: "paper"), such as a balance. {amount} is the number, already formatted.
  ///
  /// In en, this message translates to:
  /// **'{amount} paper'**
  String designPaperAmount(String amount);

  /// Small button that switches to Real mode, where the player trades with real money. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Use real money'**
  String get designUseRealMoney;

  /// Tooltip and screen reader label of the close (X) button on a short message shown at the bottom of the screen.
  ///
  /// In en, this message translates to:
  /// **'Dismiss message'**
  String get designDismissMessage;

  /// Screen reader label for the green check mark shown when something is done.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get designCompleted;

  /// Big title of the full-screen moment after the player is promoted to a new career rank. {rank} is the new rank's name, already translated (one of the rank* keys, such as "Analyst"). {rankId} is the rank's internal id (rookie, analyst, trader, seniorTrader, partner, legend) and only picks the English article "a" or "an"; other languages can use the same text in both branches. Avoid wording that depends on the player's gender.
  ///
  /// In en, this message translates to:
  /// **'{rankId, select, analyst{You’re an {rank}!} other{You’re a {rank}!}}'**
  String appPromotionTitle(String rankId, String rank);

  /// Line under the promotion title. "the floor" is the trading floor where the player works.
  ///
  /// In en, this message translates to:
  /// **'A new chapter on the floor.'**
  String get appPromotionMessage;

  /// Small label above the player's previous career rank on the promotion screen. Keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get appPromotionFrom;

  /// Small label above the player's new career rank on the promotion screen. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'New rank'**
  String get appPromotionNewRank;

  /// Small label above the number of Trims (points) the promotion gave, on the promotion screen. Keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'Earned'**
  String get appPromotionEarned;

  /// Number of Trims (the game's points, a proper noun that is never translated) a promotion gave. Shown on the promotion screen.
  ///
  /// In en, this message translates to:
  /// **'{trims} Trims'**
  String appPromotionTrims(String trims);

  /// Button at the bottom of the promotion screen that returns to the Career tab. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Back to Career'**
  String get appPromotionBackToCareer;

  /// Big title of the full-screen moment after the player's first practice purchase. A position is a stock you hold.
  ///
  /// In en, this message translates to:
  /// **'Your first position.'**
  String get appFirstPositionTitle;

  /// Line under "Your first position." celebrating the player's first order (a request to buy).
  ///
  /// In en, this message translates to:
  /// **'You’ve placed your first order!'**
  String get appFirstPositionMessage;

  /// Small label above the ticker symbol of the stock bought (such as AAPLx) on the first position screen. Keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get appFirstPositionStock;

  /// Small label above how many shares were bought (such as 1.25) on the first position screen. Keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get appFirstPositionShares;

  /// Small label above the time the order was confirmed on the first position screen. Keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get appFirstPositionTime;

  /// Time the first order was confirmed, in UTC (Coordinated Universal Time). {time} is a 24-hour clock time.
  ///
  /// In en, this message translates to:
  /// **'{time} UTC'**
  String appFirstPositionTimeUtc(String time);

  /// Big title of the full-screen moment after the player finishes their first workday ("Day 1").
  ///
  /// In en, this message translates to:
  /// **'Day 1, done.'**
  String get appDayOneTitle;

  /// Line under "Day 1, done." "the floor" is the trading floor where the player works.
  ///
  /// In en, this message translates to:
  /// **'See you on the floor tomorrow.'**
  String get appDayOneMessage;

  /// Message on the full-screen "Couldn’t open Trimmy" page when the player's guest desk (progress kept without an account) has expired and must be recovered.
  ///
  /// In en, this message translates to:
  /// **'This guest desk needs recovery.'**
  String get appSessionGuestRecovery;

  /// Message on the full-screen "Couldn’t open Trimmy" page when the answers from the introduction questions could not be saved on the phone.
  ///
  /// In en, this message translates to:
  /// **'Your answers could not be saved. Try once more.'**
  String get appSessionAnswersNotSaved;

  /// Message on the full-screen "Couldn’t open Trimmy" page when a step of the introduction could not be saved on the phone.
  ///
  /// In en, this message translates to:
  /// **'That step could not be saved. Try again.'**
  String get appSessionStepNotSaved;

  /// Message on the full-screen "Couldn’t open Trimmy" page when the setup saved on the phone is damaged and the introduction must start over.
  ///
  /// In en, this message translates to:
  /// **'Your Trimmy setup could not be opened. Start it again.'**
  String get appSessionSetupUnreadable;

  /// Message on the full-screen "Couldn’t open Trimmy" page when the player's profile could not load because the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'Your profile is offline. Check your connection and try again.'**
  String get appSessionReadOffline;

  /// Message on the full-screen "Couldn’t open Trimmy" page when loading the player's profile timed out.
  ///
  /// In en, this message translates to:
  /// **'Your profile took too long to open. Try again.'**
  String get appSessionReadTimeout;

  /// Message on the full-screen "Couldn’t open Trimmy" page when the player's profile could not load because the sign-in session expired.
  ///
  /// In en, this message translates to:
  /// **'Your profile needs a fresh session. Try again.'**
  String get appSessionReadSession;

  /// Message on the full-screen "Couldn’t open Trimmy" page when the player's profile could not load for any other reason.
  ///
  /// In en, this message translates to:
  /// **'Your profile is unavailable. Try again.'**
  String get appSessionReadUnavailable;

  /// Message when saving the profile failed because another player already uses that name (the player's public name on the trading floor).
  ///
  /// In en, this message translates to:
  /// **'That floor name is taken. Choose another one.'**
  String get appSessionHandleTaken;

  /// Message when an introduction step needs the player's first practice trade to be confirmed by the server first.
  ///
  /// In en, this message translates to:
  /// **'Your confirmed trade must reach the desk before this step can continue.'**
  String get appSessionTradeRequired;

  /// Message when an introduction step was tried before the server finished confirming the previous one.
  ///
  /// In en, this message translates to:
  /// **'Trimmy is still confirming that moment. Try again.'**
  String get appSessionNotReady;

  /// Message when the account behind the player's desk changed (for example after signing in elsewhere) while saving.
  ///
  /// In en, this message translates to:
  /// **'Your desk identity changed. Open it again and retry.'**
  String get appSessionPrincipalChanged;

  /// Message when saving the profile failed because it was changed on another phone or computer meanwhile.
  ///
  /// In en, this message translates to:
  /// **'Your profile changed on another device. Try again.'**
  String get appSessionConflict;

  /// Message when saving the profile failed because the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Reconnect and try again.'**
  String get appSessionWriteOffline;

  /// Message when saving the profile timed out.
  ///
  /// In en, this message translates to:
  /// **'That took too long. Try again.'**
  String get appSessionWriteTimeout;

  /// Message when saving the profile failed because the sign-in session changed or expired.
  ///
  /// In en, this message translates to:
  /// **'Your session changed. Open your profile again.'**
  String get appSessionWriteSession;

  /// Message when saving a profile or introduction step failed for any other reason.
  ///
  /// In en, this message translates to:
  /// **'That step was not saved. Try again.'**
  String get appSessionWriteFailed;

  /// Message at the bottom of the Market list when the next page of stocks could not load.
  ///
  /// In en, this message translates to:
  /// **'Could not load more stocks. Try again.'**
  String get appMarketLoadMoreFailed;

  /// Message on the Market tab when the list of stocks could not load. Pulling the list down reloads it.
  ///
  /// In en, this message translates to:
  /// **'Stocks could not load. Pull down to try again.'**
  String get appMarketCatalogFailed;

  /// Message on the first-trade screen when the three suggested stocks to start with could not be found. "symbol" is a ticker symbol such as AAPL.
  ///
  /// In en, this message translates to:
  /// **'Starter picks are unavailable. Search by company or symbol.'**
  String get appMarketNoStarterPicks;

  /// Message on the Market and first-trade screens when this version of the app has no market data service set up (test builds).
  ///
  /// In en, this message translates to:
  /// **'Market data is not configured in this build.'**
  String get appMarketNotConfigured;

  /// Message on the Market and first-trade screens when the market data service asked the app to slow down.
  ///
  /// In en, this message translates to:
  /// **'Market data is busy. Try again in a moment.'**
  String get appMarketBusy;

  /// Message on the Market and first-trade screens when loading market data timed out.
  ///
  /// In en, this message translates to:
  /// **'Market data took too long. Try again.'**
  String get appMarketTimeout;

  /// Message on the Market and first-trade screens when market data could not load because the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Check your connection and try again.'**
  String get appMarketOffline;

  /// Message on the Market and first-trade screens when stocks could not load for any other reason.
  ///
  /// In en, this message translates to:
  /// **'Stocks could not load. Try again.'**
  String get appMarketUnavailable;

  /// Bottom navigation tab: the home screen, the player's trading desk. Keep under 10 characters.
  ///
  /// In en, this message translates to:
  /// **'Desk'**
  String get tabDesk;

  /// Bottom navigation tab: the list of stocks to research and trade. Keep under 10 characters.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get tabMarket;

  /// Bottom navigation tab: the player's career (rank, missions, promotions). Keep under 10 characters.
  ///
  /// In en, this message translates to:
  /// **'Career'**
  String get tabCareer;

  /// Bottom navigation tab: the player's profile. Keep under 10 characters.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tabProfile;

  /// Tooltip and screen reader label of the close (X) button on the first practice trade page. Skips the whole guided first trade.
  ///
  /// In en, this message translates to:
  /// **'Skip first trade'**
  String get firstTradeSkip;

  /// Big title of the guided first practice trade page, the first thing a new player does.
  ///
  /// In en, this message translates to:
  /// **'Your first move.'**
  String get firstTradeTitle;

  /// Loading text while the practice (paper) account opens before the first trade. The ellipsis is one character.
  ///
  /// In en, this message translates to:
  /// **'Opening your paper desk…'**
  String get firstTradeOpeningDesk;

  /// Error when the practice account could not open on the first trade page, above a Try again button.
  ///
  /// In en, this message translates to:
  /// **'Your paper desk is unavailable. Try again.'**
  String get firstTradeDeskUnavailable;

  /// Error when leaving the first trade page failed (for example skipping it while offline).
  ///
  /// In en, this message translates to:
  /// **'Couldn’t continue. Try again.'**
  String get firstTradeContinueError;

  /// Section title above three starter companies on the first trade page.
  ///
  /// In en, this message translates to:
  /// **'Pick a company.'**
  String get firstTradePickCompany;

  /// Small button next to "Pick a company." that shows a one-line explanation of what a share is. One short word.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get firstTradeHint;

  /// The guide bubble explaining what a share is, for someone who has never bought one.
  ///
  /// In en, this message translates to:
  /// **'A share is a small piece of a company. Pick one.'**
  String get firstTradeCompanyGuide;

  /// Section title above the amount picker on the first trade page; the player chooses how many dollars of practice money to invest.
  ///
  /// In en, this message translates to:
  /// **'Select price'**
  String get firstTradeAmountTitle;

  /// Guide bubble above the amount picker: the money is practice money, so it costs nothing.
  ///
  /// In en, this message translates to:
  /// **'Pick an amount to try. It’s free.'**
  String get firstTradeAmountGuide;

  /// Main button that opens the order review for the first practice buy. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Review buy'**
  String get firstTradeReviewBuy;

  /// Celebration headline after the first practice buy is confirmed.
  ///
  /// In en, this message translates to:
  /// **'You’ve placed your first order!'**
  String get firstTradeOrderPlaced;

  /// Line under the celebration headline; the next step asks the player to sign in or continue as a guest.
  ///
  /// In en, this message translates to:
  /// **'Now let’s create your trader profile.'**
  String get firstTradeCreateProfile;

  /// Label on the receipt of the first practice buy, and its screen reader label.
  ///
  /// In en, this message translates to:
  /// **'Buy confirmed'**
  String get firstTradeBuyConfirmed;

  /// Label next to the amount of practice money invested, on the first buy receipt.
  ///
  /// In en, this message translates to:
  /// **'Invested'**
  String get firstTradeInvested;

  /// Receipt line showing how many shares the first practice buy got. {shares} is an already formatted number such as 0.512. The two spaces separate the label from the figure.
  ///
  /// In en, this message translates to:
  /// **'Shares  {shares}'**
  String firstTradeSharesLine(String shares);

  /// Reward shown on the first buy receipt. {trims} is a formatted whole number. Trims is the name of the game points and stays as is.
  ///
  /// In en, this message translates to:
  /// **'+{trims} Trims'**
  String firstTradeTrimsEarned(String trims);

  /// Option (and tooltip) to keep playing with practice money instead of adding real money, right after the first trade.
  ///
  /// In en, this message translates to:
  /// **'Keep using free money'**
  String get firstTradeKeepFreeMoney;

  /// Caption under "Keep using free money".
  ///
  /// In en, this message translates to:
  /// **'Build your confidence on the desk.'**
  String get firstTradeKeepFreeMoneyDetail;

  /// How many shares the first practice buy got, on the celebration card. {shares} is the exact formatted figure (it can be a fraction such as 0.512); {count} is the same number, used only to choose singular or plural.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{shares} shares}}'**
  String firstTradeSharesCount(num count, String shares);

  /// The practice money spent on the first buy, on the celebration card. {amount} is a formatted number such as 100.00.
  ///
  /// In en, this message translates to:
  /// **'{amount} free money'**
  String firstTradeFreeMoneyAmount(String amount);

  /// Headline of the step after the first trade where the player chooses between practice money and adding real money.
  ///
  /// In en, this message translates to:
  /// **'Your next move.'**
  String get firstTradeNextMove;

  /// Line under "Your next move.": keep practising, or add real money to the wallet.
  ///
  /// In en, this message translates to:
  /// **'Keep finding your feet, or fund your wallet.'**
  String get firstTradeNextMoveBody;

  /// Caption under the "Add money" option after the first trade.
  ///
  /// In en, this message translates to:
  /// **'See your deposit options.'**
  String get firstTradeAddMoneyDetail;

  /// Small reassurance under the two options after the first trade.
  ///
  /// In en, this message translates to:
  /// **'You can add money from your desk any time.'**
  String get firstTradeAddMoneyLater;

  /// Error after the first trade when moving on failed; the practice trade itself is saved.
  ///
  /// In en, this message translates to:
  /// **'Your trade is safe. Try continuing again.'**
  String get firstTradeContinueSafe;

  /// Error under the amount field when it is empty or not a number.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount.'**
  String get amountPickerErrorEmpty;

  /// Error when the typed amount has more than two decimals.
  ///
  /// In en, this message translates to:
  /// **'Use up to 2 decimal places.'**
  String get amountPickerErrorDecimals;

  /// Error when the amount is below the minimum. {amount} is a formatted dollar amount such as $1.
  ///
  /// In en, this message translates to:
  /// **'Choose at least {amount}.'**
  String amountPickerErrorMin(String amount);

  /// Error when the amount is above the maximum. {amount} is a formatted dollar amount such as $10,000.
  ///
  /// In en, this message translates to:
  /// **'Choose up to {amount}.'**
  String amountPickerErrorMax(String amount);

  /// Label of the amount text field. The amounts are US dollars.
  ///
  /// In en, this message translates to:
  /// **'Amount in dollars'**
  String get amountPickerFieldLabel;

  /// Screen reader label of the large amount display, which opens the editor when tapped. {amount} is the formatted figure; {value} is the same number, used only to choose singular or plural.
  ///
  /// In en, this message translates to:
  /// **'{value, plural, other{Amount, {amount} dollars. Edit amount}}'**
  String amountPickerEditSemantics(num value, String amount);

  /// Tooltip of the minus button. {amount} is the formatted step; {step} is the same number for singular or plural.
  ///
  /// In en, this message translates to:
  /// **'{step, plural, other{Decrease amount by {amount} dollars}}'**
  String amountPickerDecreaseTooltip(num step, String amount);

  /// Tooltip of the plus button. {amount} is the formatted step; {step} is the same number for singular or plural.
  ///
  /// In en, this message translates to:
  /// **'{step, plural, other{Increase amount by {amount} dollars}}'**
  String amountPickerIncreaseTooltip(num step, String amount);

  /// Screen reader label of a preset amount chip. {amountText} is the formatted whole amount; {amount} is the same number for singular or plural.
  ///
  /// In en, this message translates to:
  /// **'{amount, plural, other{Set amount to {amountText} dollars}}'**
  String amountPickerPresetSemantics(num amount, String amountText);

  /// Answer card title for the onboarding question "Why are you here?". Short label. The player wants to learn how stocks work.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get onboardingGoalLearn;

  /// Smaller line under the answer "Learn" on the onboarding goal question.
  ///
  /// In en, this message translates to:
  /// **'Start with the basics.'**
  String get onboardingGoalLearnDetail;

  /// Answer card title for the onboarding question "Why are you here?". Short label. The player wants to practice (a verb here, not the Practice mode name).
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get onboardingGoalPractice;

  /// Smaller line under the answer "Practice". "Make calls" means make your own buy and sell decisions; "paper" is practice money (pretend money).
  ///
  /// In en, this message translates to:
  /// **'Make calls with paper.'**
  String get onboardingGoalPracticeDetail;

  /// Answer card title for the onboarding question "Why are you here?". Short label. The player wants to trade stocks using practice money ("paper").
  ///
  /// In en, this message translates to:
  /// **'Trade with paper'**
  String get onboardingGoalTrade;

  /// Smaller line under the answer "Trade with paper": practice trades use real, live market prices.
  ///
  /// In en, this message translates to:
  /// **'Build confidence at live prices.'**
  String get onboardingGoalTradeDetail;

  /// Answer card title for the onboarding question "Why are you here?". Short label. Playing against friends (currently hidden).
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get onboardingGoalFriends;

  /// Smaller line under the answer "Friends": competing in leagues with friends is not available yet.
  ///
  /// In en, this message translates to:
  /// **'Leagues are not available yet.'**
  String get onboardingGoalFriendsDetail;

  /// One answer on a 1 to 5 scale for the onboarding question "How much do you know about trading?" (stock trading). First person. Level 1: knows nothing yet.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get onboardingKnowledgeNothing;

  /// One answer on a 1 to 5 scale for the onboarding question "How much do you know about trading?" (stock trading). First person. Level 2.
  ///
  /// In en, this message translates to:
  /// **'I know the basics'**
  String get onboardingKnowledgeBasics;

  /// One answer on a 1 to 5 scale for the onboarding question "How much do you know about trading?" (stock trading). First person. Level 3: has practised with pretend money, not real money. Avoid gendered forms.
  ///
  /// In en, this message translates to:
  /// **'I have practised'**
  String get onboardingKnowledgePractised;

  /// One answer on a 1 to 5 scale for the onboarding question "How much do you know about trading?" (stock trading). First person. Level 4: has traded stocks for real before.
  ///
  /// In en, this message translates to:
  /// **'I have traded before'**
  String get onboardingKnowledgeTraded;

  /// One answer on a 1 to 5 scale for the onboarding question "How much do you know about trading?" (stock trading). First person. Level 5: trades stocks every day.
  ///
  /// In en, this message translates to:
  /// **'I trade every day'**
  String get onboardingKnowledgeDaily;

  /// Answer card title for the onboarding question "Pick your daily goal." A "move" is one trading decision, a practice trade. The lightest goal: just open the app each day. Avoid gendered forms.
  ///
  /// In en, this message translates to:
  /// **'Show up'**
  String get onboardingDailyShowUp;

  /// Smaller line under the daily goal "Show up". "Desk" is the home screen (Escritorio / Mesa / Bureau).
  ///
  /// In en, this message translates to:
  /// **'Open Trimmy and check your desk.'**
  String get onboardingDailyShowUpDetail;

  /// Answer card title for the onboarding question "Pick your daily goal." A "move" is one trading decision, a practice trade. One move per day.
  ///
  /// In en, this message translates to:
  /// **'One move'**
  String get onboardingDailyOneMove;

  /// Smaller line under the daily goal "One move": make one well thought-out trade with practice money ("paper").
  ///
  /// In en, this message translates to:
  /// **'Make one focused paper trade.'**
  String get onboardingDailyOneMoveDetail;

  /// Answer card title for the onboarding question "Pick your daily goal." A "move" is one trading decision, a practice trade. Three moves per day.
  ///
  /// In en, this message translates to:
  /// **'Three moves'**
  String get onboardingDailyThreeMoves;

  /// Smaller line under the daily goal "Three moves": make three well thought-out trades with practice money ("paper").
  ///
  /// In en, this message translates to:
  /// **'Make three focused paper trades.'**
  String get onboardingDailyThreeMovesDetail;

  /// Sal, the floor boss, speaks in a large speech bubble before the onboarding questions: five quick questions, then the player makes a first trade with practice money ("paper").
  ///
  /// In en, this message translates to:
  /// **'Five quick questions, then your first paper trade.'**
  String get onboardingSalHello;

  /// One of the five onboarding questions, asked by Sal, the floor boss, in a speech bubble. Asks why the player came to Trimmy.
  ///
  /// In en, this message translates to:
  /// **'Why are you here?'**
  String get onboardingQuestionGoal;

  /// One of the five onboarding questions, asked by Sal, the floor boss, in a speech bubble. Asks how much the player knows about stock trading; the answers are a 1 to 5 scale from "Nothing yet" to "I trade every day".
  ///
  /// In en, this message translates to:
  /// **'How much do you know about trading?'**
  String get onboardingQuestionKnowledge;

  /// One of the five onboarding questions, asked by Sal, the floor boss, in a speech bubble. The player picks one of three trader characters (Wolf, Oracle, Shark) to play as.
  ///
  /// In en, this message translates to:
  /// **'Pick your trader.'**
  String get onboardingQuestionPersona;

  /// One of the five onboarding questions, asked by Sal, the floor boss, in a speech bubble. The player picks how much to do each day.
  ///
  /// In en, this message translates to:
  /// **'Pick your daily goal.'**
  String get onboardingQuestionDailyGoal;

  /// One of the five onboarding questions, asked by Sal, the floor boss, in a speech bubble. Asks for a public username (handle). "The floor" means the people on the trading floor. Avoid gendered forms ("chamado").
  ///
  /// In en, this message translates to:
  /// **'What should the floor call you?'**
  String get onboardingQuestionHandle;

  /// Label of the text field where the player types a public username (shown with an @ in front).
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get onboardingHandleLabel;

  /// Helper text under the username field: the allowed length.
  ///
  /// In en, this message translates to:
  /// **'3 to 18 characters'**
  String get onboardingHandleHelper;

  /// Error under the username field when it is too short.
  ///
  /// In en, this message translates to:
  /// **'Use at least 3 characters.'**
  String get onboardingHandleTooShort;

  /// Error under the username field when it is too long.
  ///
  /// In en, this message translates to:
  /// **'Use 18 characters or fewer.'**
  String get onboardingHandleTooLong;

  /// Error under the username field when it does not start with a letter.
  ///
  /// In en, this message translates to:
  /// **'Start with a letter.'**
  String get onboardingHandleStartWithLetter;

  /// Hint under the username field: which characters a username may contain (letters, digits and the _ character).
  ///
  /// In en, this message translates to:
  /// **'Use letters, numbers or underscores.'**
  String get onboardingHandleCharacters;

  /// Screen reader label of the progress bar at the top of the onboarding questions.
  ///
  /// In en, this message translates to:
  /// **'Onboarding progress'**
  String get onboardingProgressLabel;

  /// Screen reader value of the onboarding progress bar.
  ///
  /// In en, this message translates to:
  /// **'{percent} percent'**
  String onboardingProgressValue(int percent);

  /// Small counter next to the onboarding progress bar: which question this is out of how many. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'{step} of {total}'**
  String onboardingProgressStep(int step, int total);

  /// Screen reader label of a speech bubble from Sal, the floor boss. {text} is what Sal says.
  ///
  /// In en, this message translates to:
  /// **'Sal says: {text}'**
  String onboardingSalSays(String text);

  /// Sal, the floor boss, asks to send notifications: he will alert the player when the Wall Street stock market opens and closes, and trading in Trimmy is possible at any hour.
  ///
  /// In en, this message translates to:
  /// **'I\'ll ring you when Wall Street opens and closes. Trading here stays open.'**
  String get onboardingNotificationsAsk;

  /// Sal says this instead when notifications cannot be turned on in this version of the app yet.
  ///
  /// In en, this message translates to:
  /// **'Alerts are almost ready.'**
  String get onboardingNotificationsSoon;

  /// Title on the notifications step: next, the phone shows its own permission prompt for notifications.
  ///
  /// In en, this message translates to:
  /// **'Your phone asks next.'**
  String get onboardingNotificationsPhoneAsks;

  /// Title on the notifications step when notifications are not available yet: carry on setting up the home screen ("desk").
  ///
  /// In en, this message translates to:
  /// **'Keep setting up your desk.'**
  String get onboardingNotificationsKeepSettingUp;

  /// Line under the title on the notifications step. "Settings" is the app's Settings screen (Configuración / Configurações / Réglages).
  ///
  /// In en, this message translates to:
  /// **'You can change alerts any time in Settings.'**
  String get onboardingNotificationsChangeLater;

  /// Line on the notifications step when notifications are not available yet: alerts will show up once sending them is switched on.
  ///
  /// In en, this message translates to:
  /// **'Alerts will appear here after delivery is connected.'**
  String get onboardingNotificationsLater;

  /// Main button label while the onboarding answers are being saved. Keep under 26 characters.
  ///
  /// In en, this message translates to:
  /// **'Saving your setup'**
  String get onboardingNotificationsSaving;

  /// Main button on the notifications step: asks the phone for permission to send notifications.
  ///
  /// In en, this message translates to:
  /// **'Turn on alerts'**
  String get onboardingNotificationsTurnOn;

  /// Text button after saving the onboarding answers failed: goes back to the previous questions.
  ///
  /// In en, this message translates to:
  /// **'Review my answers'**
  String get onboardingReviewAnswers;

  /// Large text shown for a moment after onboarding while the Market screen opens. No ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Opening the market'**
  String get onboardingOpeningMarket;

  /// Error on the notifications step when the onboarding answers could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Your setup was not saved. Try again.'**
  String get onboardingSetupNotSaved;

  /// Error on the notifications step when the phone failed to show its notification permission prompt.
  ///
  /// In en, this message translates to:
  /// **'The phone did not open the request. Try again.'**
  String get onboardingPermissionRequestFailed;

  /// Screen reader label of the portrait of Sal, the player's boss on the trading floor.
  ///
  /// In en, this message translates to:
  /// **'Sal, your floor boss'**
  String get onboardingSalPortrait;

  /// Screen reader label of a drawing of a phone showing a notification permission prompt.
  ///
  /// In en, this message translates to:
  /// **'Preview of the phone notification permission'**
  String get onboardingPermissionPreview;

  /// Error at the bottom of the welcome screen or the welcome note when the step could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Could not save that step. Try again.'**
  String get onboardingIntroSaveError;

  /// Screen reader label of the thin progress bar while the app saves how far the player got in the introduction.
  ///
  /// In en, this message translates to:
  /// **'Saving your place'**
  String get onboardingIntroSaving;

  /// Error after the first trade celebration or the reminder choice could not be saved on the phone.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save that. Try again.'**
  String get onboardingCouldNotSave;

  /// Tooltip and screen reader label of the close (X) button on the reminder step after the first trade: continues without reminders.
  ///
  /// In en, this message translates to:
  /// **'Skip reminders'**
  String get onboardingReminderSkip;

  /// Title of the reminder step after the first trade: would the player like a reminder to come back?
  ///
  /// In en, this message translates to:
  /// **'A little nudge?'**
  String get onboardingReminderTitle;

  /// Line under the reminder step title, above the reminder choices.
  ///
  /// In en, this message translates to:
  /// **'How often would you like a reminder?'**
  String get onboardingReminderQuestion;

  /// Message on the reminder step when the phone refused notifications. "Phone settings" are the phone's own settings, not the app's.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off. You can change this in your phone settings.'**
  String get onboardingReminderPermissionOff;

  /// Message on the reminder step when the reminder choice was saved but this version of the app cannot send notifications yet.
  ///
  /// In en, this message translates to:
  /// **'Your preference is saved. Notifications aren’t available on this build yet.'**
  String get onboardingReminderUnavailable;

  /// Error on the reminder step when the phone could not schedule the reminder.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t set the reminder. Try again.'**
  String get onboardingReminderNotSet;

  /// Message on the reminder step when the reminder choice was changed on another phone or computer in the meantime.
  ///
  /// In en, this message translates to:
  /// **'Your preference changed on another device. Choose again.'**
  String get onboardingReminderChanged;

  /// Message on the reminder step: the choice was saved on this phone but the reminder could not be scheduled.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone. Couldn’t set the reminder. Try again.'**
  String get onboardingReminderSavedNotSet;

  /// Message on the reminder step: the choice was saved on this phone and will be synced to the account once the phone is online.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone. Sync will retry when you’re online.'**
  String get onboardingReminderSavedOffline;

  /// Name of one of the three trader characters the player can play as (bold and fast), shown on the persona picker, the profile and in settings. Wolf, Oracle and Shark are character names and are never translated; keep the name, and decide whether your language needs an article (English says "The Wolf").
  ///
  /// In en, this message translates to:
  /// **'The Wolf'**
  String get personaWolfName;

  /// Name of one of the three trader characters the player can play as (patient, reads first). Wolf, Oracle and Shark are character names and are never translated; keep the name, and decide whether your language needs an article (English says "The Wolf").
  ///
  /// In en, this message translates to:
  /// **'The Oracle'**
  String get personaOracleName;

  /// Name of one of the three trader characters the player can play as (calm under pressure). Wolf, Oracle and Shark are character names and are never translated; keep the name, and decide whether your language needs an article (English says "The Wolf").
  ///
  /// In en, this message translates to:
  /// **'The Shark'**
  String get personaSharkName;

  /// Short description under a trader character's name, where the player picks a trader to play as. Three short fragments in the English. Avoid adjectives that change with gender where you can (the player identifies with this character). The Wolf: daring, quick, loves big trades (a "move" is a trade or a big price swing).
  ///
  /// In en, this message translates to:
  /// **'Bold. Fast. Loves a big move.'**
  String get personaWolfDetail;

  /// Short description under a trader character's name, where the player picks a trader to play as. Three short fragments in the English. Avoid adjectives that change with gender where you can (the player identifies with this character). The Oracle: patient, researches before acting.
  ///
  /// In en, this message translates to:
  /// **'Patient. Reads before moving.'**
  String get personaOracleDetail;

  /// Short description under a trader character's name, where the player picks a trader to play as. Three short fragments in the English. Avoid adjectives that change with gender where you can (the player identifies with this character). The Shark: stays calm when other investors panic.
  ///
  /// In en, this message translates to:
  /// **'Calm when the crowd gets loud.'**
  String get personaSharkDetail;

  /// Screen reader label of a trader character's portrait. {name} is the character's name as shown in the app (the personaWolfName, personaOracleName or personaSharkName text).
  ///
  /// In en, this message translates to:
  /// **'{name} trader portrait'**
  String personaPortrait(String name);

  /// Title of the page where the player picks one of three trader characters to play as (opened from the profile).
  ///
  /// In en, this message translates to:
  /// **'Pick your trader'**
  String get personaPickerTitle;

  /// Line under "Pick your trader": which character the player wants to be in the game.
  ///
  /// In en, this message translates to:
  /// **'Who will you play as?'**
  String get personaPickerSubtitle;

  /// Button at the bottom of the trader picker that saves the chosen character. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get personaPickerChoose;

  /// Error on the trader picker when the chosen character could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Could not save your choice. Try again.'**
  String get personaPickerSaveError;

  /// The big headline on the very first screen a new player sees, centered among floating stock coins: an invitation to start a career on Wall Street. {wallStreet} is always the words 'Wall Street' (never translated); it is drawn in purple on a line of its own with a heartbeat animation. The words before it and the words after it are each centered on their own lines above and below it, so keep each side short (about 10 to 12 characters fit on one line; longer text wraps). If the sentence ends right after {wallStreet}, put the final period directly after it and it stays on the Wall Street line.
  ///
  /// In en, this message translates to:
  /// **'Start your {wallStreet} career.'**
  String welcomeHeadline(String wallStreet);

  /// Screen reader label for the welcome screen's animated headline: the headline sentence, then a short description of the picture, where coins showing tokenized stocks circle around the headline.
  ///
  /// In en, this message translates to:
  /// **'Start your Wall Street career. Tokenized stocks orbit the invitation.'**
  String get welcomeHeroSemantics;

  /// Main button on the welcome screen, also its screen reader label. Starts the game: the player begins their first day at work on Wall Street. First person ("my"). Keep under 30 characters; it can wrap to two lines.
  ///
  /// In en, this message translates to:
  /// **'Start my first day'**
  String get welcomeStartFirstDay;

  /// Small text button under the main button on the welcome screen, for people who already have an account or want to make one. Keep under 26 characters: the button has a fixed height and must stay on one line.
  ///
  /// In en, this message translates to:
  /// **'Sign in or create account'**
  String get welcomeSignInOrCreate;

  /// Tooltip and screen reader label of the close (X) button on the welcome note from Sal, the boss, shown right after the welcome screen. Skips the introduction.
  ///
  /// In en, this message translates to:
  /// **'Skip introduction'**
  String get welcomeNoteSkip;

  /// Big title of the welcome note pinned on a board, from Sal, the floor boss. "The floor" is the trading floor of the Wall Street firm where the player now works. The line break (\n) is deliberate: put it where a short first line reads well. Avoid gendered welcome words ("Bienvenido").
  ///
  /// In en, this message translates to:
  /// **'Welcome to\nthe floor.'**
  String get welcomeNoteTitle;

  /// Body of the welcome note from Sal, under "Welcome to the floor." Two short paragraphs separated by a blank line (\n\n): the first day begins with a practice trade, and buying a piece of a company costs nothing because it uses practice money.
  ///
  /// In en, this message translates to:
  /// **'Your first day starts with practice.\n\nPick a company. It’s free.'**
  String get welcomeNoteBody;

  /// Chart period button on a stock page: one day. Abbreviation, keep 2 or 3 characters (1 + the first letter of 'day').
  ///
  /// In en, this message translates to:
  /// **'1D'**
  String get chartPeriodDay;

  /// Chart period button on a stock page: one week. Abbreviation, keep 2 or 3 characters (1 + the first letter of 'week').
  ///
  /// In en, this message translates to:
  /// **'1W'**
  String get chartPeriodWeek;

  /// Chart period button on a stock page: one month. Abbreviation, keep 2 or 3 characters (1 + the first letter of 'month').
  ///
  /// In en, this message translates to:
  /// **'1M'**
  String get chartPeriodMonth;

  /// Chart period button on a stock page: one year. Abbreviation, keep 2 or 3 characters (1 + the first letter of 'year').
  ///
  /// In en, this message translates to:
  /// **'1Y'**
  String get chartPeriodYear;

  /// Screen reader label for the price chart on a stock page. {from} is the first price in the chart, {to} the last. Pressing and holding the chart shows each price.
  ///
  /// In en, this message translates to:
  /// **'Price chart. {from} to {to}. Hold to explore.'**
  String chartPriceLabel(String from, String to);

  /// Line above the price chart after tapping one of the player's buy markers. {shares} is how many shares were bought ('0.2'), {price} the price per share, {date} the date and time ('30 Sep · 14:05'). Keep the dots.
  ///
  /// In en, this message translates to:
  /// **'Bought {shares} · {price} · {date}'**
  String chartTradeBoughtSummary(String shares, String price, String date);

  /// Line above the price chart after tapping one of the player's sell markers. {shares} is how many shares were sold ('0.2'), {price} the price per share, {date} the date and time ('30 Sep · 14:05'). Keep the dots.
  ///
  /// In en, this message translates to:
  /// **'Sold {shares} · {price} · {date}'**
  String chartTradeSoldSummary(String shares, String price, String date);

  /// Screen reader label and tooltip of a buy marker on the price chart. {shares} is how many shares the player bought, as shown ('0.2'); {count} is the same number for choosing the plural form. {price} is the price per share, {date} the date and time ('30 Sep · 14:05').
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Bought {shares} shares at {price}, {date}}}'**
  String chartTradeBoughtLabel(
    num count,
    String shares,
    String price,
    String date,
  );

  /// Screen reader label and tooltip of a sell marker on the price chart. {shares} is how many shares the player sold, as shown ('0.2'); {count} is the same number for choosing the plural form. {price} is the price per share, {date} the date and time ('30 Sep · 14:05').
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Sold {shares} shares at {price}, {date}}}'**
  String chartTradeSoldLabel(
    num count,
    String shares,
    String price,
    String date,
  );

  /// One letter inside a small marker on the price chart where the player bought: the first letter of 'Buy' (or 'Bought'). A count may follow it ('B2'). Exactly one letter.
  ///
  /// In en, this message translates to:
  /// **'B'**
  String get chartTradeMarkerBuy;

  /// One letter inside a small marker on the price chart where the player sold: the first letter of 'Sell' (or 'Sold'). A count may follow it ('S2'). Exactly one letter.
  ///
  /// In en, this message translates to:
  /// **'S'**
  String get chartTradeMarkerSell;

  /// Shown under the chart periods on a stock page when the player picks one year but the app has no year of history.
  ///
  /// In en, this message translates to:
  /// **'A year of history is not available yet.'**
  String get chartNoYear;

  /// Shown in place of the price chart on a stock page when the price history failed to load.
  ///
  /// In en, this message translates to:
  /// **'Price history is unavailable. Try again.'**
  String get chartHistoryUnavailable;

  /// Shown above the price chart when it comes from an older reading of the prices. Pull down to refresh.
  ///
  /// In en, this message translates to:
  /// **'This is an older reading. Refresh for a newer chart.'**
  String get chartStaleReading;

  /// Shown in place of the price chart when the chosen period has fewer than two price readings.
  ///
  /// In en, this message translates to:
  /// **'There are not enough readings for this period.'**
  String get chartNotEnoughReadings;

  /// Screen reader label for the small seven-day price line on a stock page.
  ///
  /// In en, this message translates to:
  /// **'Seven day company price movement'**
  String get chartSevenDayLabel;

  /// Caption under the small seven-day price line on a stock page. It shows the real company's stock on its exchange, not the token.
  ///
  /// In en, this message translates to:
  /// **'7-day listed stock movement'**
  String get chartSevenDayCaption;

  /// Shown in place of the price chart on a stock page when there is no history for the chosen token version (issuer's token).
  ///
  /// In en, this message translates to:
  /// **'Price history is not available for this version yet.'**
  String get chartNoHistoryForVersion;

  /// Shown in place of the relative price chart when the price readings are invalid (zero or missing).
  ///
  /// In en, this message translates to:
  /// **'These readings cannot be compared reliably.'**
  String get chartReadingsNotComparable;

  /// Small line under the percent change of the relative price chart. {time} is the date and time of the chosen reading ('30/9 14:05'). The change is measured from the first reading of the period. Keep 'UTC'.
  ///
  /// In en, this message translates to:
  /// **'{time} UTC · From the first reading'**
  String chartReadingAt(String time);

  /// Screen reader label for the relative price chart (percent change since the first reading). {symbol} is the token symbol.
  ///
  /// In en, this message translates to:
  /// **'{symbol} relative history'**
  String chartRelativeHistoryLabel(String symbol);

  /// Screen reader value of the relative price chart: the percent change at a reading. {change} is a signed percent ('+1.25%'), {time} the date and time ('30/9 14:05'). Keep 'UTC'.
  ///
  /// In en, this message translates to:
  /// **'{change} at {time} UTC'**
  String chartChangeAtTime(String change, String time);

  /// Hint under the relative price chart when it has breaks: the price provider sent no reading for those times. Dragging a finger along the chart shows each reading.
  ///
  /// In en, this message translates to:
  /// **'Gaps mean the provider returned no reading. Drag to explore.'**
  String get chartGapsHint;

  /// Hint under the relative price chart: dragging a finger along the chart shows each reading.
  ///
  /// In en, this message translates to:
  /// **'Drag across the chart to explore.'**
  String get chartDragHint;

  /// Title on a stock page's Holders tab when the list of the largest token holders failed to load. A Retry button follows.
  ///
  /// In en, this message translates to:
  /// **'Holders couldn’t load'**
  String get holdersLoadFailedTitle;

  /// Line under 'Holders couldn’t load' on a stock page's Holders tab.
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment.'**
  String get holdersLoadFailedBody;

  /// Shown on a stock page's Holders tab when the token has no holders to list.
  ///
  /// In en, this message translates to:
  /// **'No holders to show'**
  String get holdersEmpty;

  /// Column heading on a stock page's Holders tab: the wallet (address or name) that holds the token. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Holder'**
  String get holdersColumnHolder;

  /// Column heading on a stock page's Holders tab: how many tokens each wallet holds. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get holdersColumnTokens;

  /// Tooltip on the info icon of a stock page's Holders tab: the list only covers the biggest token accounts. {count} is how many accounts were read, such as 20.
  ///
  /// In en, this message translates to:
  /// **'Balances from the largest {count} token accounts. Not the full holder list.'**
  String holdersSampleNote(String count);

  /// Large title at the top of the Market tab, the list of tokenized stocks.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get marketTitle;

  /// Small line under the Market tab title, saying what the list holds: tokens that track real company stocks.
  ///
  /// In en, this message translates to:
  /// **'Tokenized stocks'**
  String get marketSubtitle;

  /// Tooltip on the sort button of the Market tab. {sort} is the current sort option, already translated, such as 'Featured' or 'Biggest gains'.
  ///
  /// In en, this message translates to:
  /// **'Sort: {sort}'**
  String marketSortTooltip(String sort);

  /// Screen reader label for the sort button (an icon) on the Market tab.
  ///
  /// In en, this message translates to:
  /// **'Sort stocks'**
  String get marketSortButtonLabel;

  /// Tooltip and screen reader label for the search button (a magnifier icon) on the Market tab.
  ///
  /// In en, this message translates to:
  /// **'Search companies'**
  String get marketSearchButtonLabel;

  /// Title of the bottom sheet that picks how the Market list is ordered. Only the stocks loaded so far are sorted.
  ///
  /// In en, this message translates to:
  /// **'Sort loaded stocks'**
  String get marketSortTitle;

  /// Sort option on the Market list: Trimmy's own order. Short list item.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get marketSortFeatured;

  /// Sort option on the Market list: alphabetical by company name. Short list item.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get marketSortName;

  /// Sort option on the Market list: the stocks that rose most in the last 24 hours first. Short list item.
  ///
  /// In en, this message translates to:
  /// **'Biggest gains'**
  String get marketSortBiggestGains;

  /// Sort option on the Market list: the stocks that fell most in the last 24 hours first. Short list item.
  ///
  /// In en, this message translates to:
  /// **'Biggest drops'**
  String get marketSortBiggestDrops;

  /// Sort option on the Market list: the most expensive share price first. Short list item.
  ///
  /// In en, this message translates to:
  /// **'Highest price'**
  String get marketSortHighestPrice;

  /// Sort option on the Market list: the stocks owned by the most Trimmy players first. Short list item.
  ///
  /// In en, this message translates to:
  /// **'Most held'**
  String get marketSortMostHeld;

  /// Filter chip on the Market tab that shows every stock. Feminine plural in Romance languages (all stocks). Keep very short: chips sit in a row.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get marketListAll;

  /// Filter chip on the Market tab: a short list of good first stocks for beginners. Keep under 16 characters.
  ///
  /// In en, this message translates to:
  /// **'Starter picks'**
  String get marketListStarterPicks;

  /// Filter chip on the Market tab: stocks many people look at right now. Keep under 16 characters.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get marketListTrending;

  /// Filter chip on the Market tab: stocks whose price moved a lot today. Keep under 16 characters.
  ///
  /// In en, this message translates to:
  /// **'Movers'**
  String get marketListMovers;

  /// Filter chip on the Market tab: stocks owned by the most Trimmy players. Keep under 18 characters.
  ///
  /// In en, this message translates to:
  /// **'Most held'**
  String get marketListMostHeld;

  /// Filter chip on the Market tab that shows the companies the player follows (their watchlist). Keep under 16 characters.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get marketListFollowing;

  /// Filter chip on the Market tab: stocks recently tokenized on the blockchain. Keep under 18 characters.
  ///
  /// In en, this message translates to:
  /// **'New on chain'**
  String get marketListNewOnChain;

  /// Filter chip on the Market tab: technology companies. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Tech'**
  String get marketListTech;

  /// Filter chip on the Market tab: banks and financial companies. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get marketListFinance;

  /// Filter chip on the Market tab: energy companies. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Energy'**
  String get marketListEnergy;

  /// Filter chip on the Market tab: health care companies. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get marketListHealth;

  /// Filter chip on the Market tab: consumer goods companies (shops, food, brands). Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Consumer'**
  String get marketListConsumer;

  /// Filter chip on the Market tab: exchange-traded funds and commodity funds such as the S&P 500, gold and oil. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Funds'**
  String get marketListFunds;

  /// Filter chip on the Market tab: private companies tokenized before they list on a stock exchange (before their IPO). Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Pre-IPO'**
  String get marketListPreIpo;

  /// Shown on the Market tab while a filter loads the whole stock list before it can show matches.
  ///
  /// In en, this message translates to:
  /// **'Checking every stock…'**
  String get marketLoadingAll;

  /// Title on the Market tab's Following filter when the player follows no company yet. A watchlist is the list of companies you follow.
  ///
  /// In en, this message translates to:
  /// **'Your watchlist starts here.'**
  String get marketEmptyFollowingTitle;

  /// Line under the empty watchlist title on the Market tab. 'Follow' is the button on each company card ('+ Follow').
  ///
  /// In en, this message translates to:
  /// **'Tap Follow on a company to keep it here.'**
  String get marketEmptyFollowingBody;

  /// Title on the Market tab's Funds filter when it has no funds.
  ///
  /// In en, this message translates to:
  /// **'No funds to show yet.'**
  String get marketEmptyFunds;

  /// Title on the Market tab's Pre-IPO filter when it has no companies. Pre-IPO: private companies not yet listed on a stock exchange.
  ///
  /// In en, this message translates to:
  /// **'No pre-IPO companies to show yet.'**
  String get marketEmptyPreIpo;

  /// Title on the Market tab when the list has no stocks.
  ///
  /// In en, this message translates to:
  /// **'No stocks to show yet.'**
  String get marketEmptyStocks;

  /// Line under an empty Market list, suggesting the search.
  ///
  /// In en, this message translates to:
  /// **'Try searching for a company.'**
  String get marketEmptyBody;

  /// Title of the full-screen company search, and the button under an empty Market list that opens it.
  ///
  /// In en, this message translates to:
  /// **'Find a company'**
  String get marketFindCompany;

  /// Button under the Following list on the Market tab when some followed companies failed to load. Tapping it tries again.
  ///
  /// In en, this message translates to:
  /// **'Some stocks could not load. Retry'**
  String get marketFollowingLoadFailed;

  /// Screen reader label for the spinner at the bottom of the Market list while the next page of stocks loads.
  ///
  /// In en, this message translates to:
  /// **'Loading more stocks'**
  String get marketLoadingMore;

  /// Status card on the Market tab when the phone has no internet connection.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Check your connection.'**
  String get marketOffline;

  /// Status card on the Market tab when the stock list could not be loaded from the server.
  ///
  /// In en, this message translates to:
  /// **'The market list is unavailable.'**
  String get marketListUnavailable;

  /// Short notice after the player follows a company from the Market list. {name} is the company name. 'Following' is the name of the watchlist filter; a natural sentence such as 'You now follow Apple.' is fine.
  ///
  /// In en, this message translates to:
  /// **'{name} added to Following.'**
  String marketFollowAdded(String name);

  /// Short notice after the player unfollows a company from the Market list. {name} is the company name. A natural sentence such as 'You no longer follow Apple.' is fine.
  ///
  /// In en, this message translates to:
  /// **'{name} removed from Following.'**
  String marketFollowRemoved(String name);

  /// Notice when a guest tries to follow a company. A Sign in button sits next to it. The watchlist is the list of companies you follow.
  ///
  /// In en, this message translates to:
  /// **'Sign in to save your watchlist.'**
  String get marketFollowSignInNeeded;

  /// Notice when the player tries to follow a company but already follows the maximum number.
  ///
  /// In en, this message translates to:
  /// **'Your watchlist is full. Remove a company first.'**
  String get marketFollowListFull;

  /// Notice when following or unfollowing a company failed (Market list and stock page).
  ///
  /// In en, this message translates to:
  /// **'Following did not change. Try again.'**
  String get marketFollowUnchanged;

  /// Small button on a company card in the Market list that adds the company to the watchlist. Keep the plus sign. Keep under 10 characters.
  ///
  /// In en, this message translates to:
  /// **'+ Follow'**
  String get marketFollowButton;

  /// The same small button on a company card once the player follows the company; tapping it unfollows. Keep under 10 characters.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get marketFollowingButton;

  /// Green tag on a company card in Real mode, and on a token version in the version picker: this token can be bought and sold with real money right now. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Tradeable'**
  String get marketTradeable;

  /// Shown instead of the 24-hour price change when it is not known (company cards, search results, position card).
  ///
  /// In en, this message translates to:
  /// **'Change unavailable'**
  String get marketChangeUnavailable;

  /// Under the price on a Market company card: the price change over the last 24 hours. {change} is a signed percent such as '+1.25%'. Keep the two spaces, and abbreviate hours as is usual (24h, 24 h).
  ///
  /// In en, this message translates to:
  /// **'{change}  24h'**
  String marketCardChange24h(String change);

  /// Screen reader label for a company card in the Market list. {name} is the company name, {symbol} its ticker, {price} the share price, {change} the 24-hour change (a percent, or the words 'change unavailable'). {tradeable} is 'yes' in Real mode when the stock can be traded now, which adds the word 'tradeable'.
  ///
  /// In en, this message translates to:
  /// **'{tradeable, select, yes{{name}, {symbol}, {price}, {change}, tradeable} other{{name}, {symbol}, {price}, {change}}}'**
  String marketCardLabel(
    String tradeable,
    String name,
    String symbol,
    String price,
    String change,
  );

  /// Part of the screen reader label of a Market company card, in place of the 24-hour change when it is not known. Lowercase: it follows a comma.
  ///
  /// In en, this message translates to:
  /// **'change unavailable'**
  String get marketChangeUnavailableSpoken;

  /// Screen reader label for a price change with an arrow. {direction} is 'down', 'up' or 'unchanged'. {change} is the signed percent, such as '-1.20%'.
  ///
  /// In en, this message translates to:
  /// **'{direction, select, down{Down {change}} up{Up {change}} other{Unchanged {change}}}'**
  String marketChangeSpoken(String direction, String change);

  /// Screen reader label for a company's logo picture. {name} is the company name.
  ///
  /// In en, this message translates to:
  /// **'{name} logo'**
  String marketCompanyLogoLabel(String name);

  /// Screen reader label for the small paper icon that marks practice money (English calls practice money 'paper'). Lowercase.
  ///
  /// In en, this message translates to:
  /// **'paper'**
  String get marketPaperMarkLabel;

  /// Screen reader label for an amount of practice money shown with the paper icon. {amount} is the figure, such as '1,250.5'. English 'paper' means practice money.
  ///
  /// In en, this message translates to:
  /// **'{amount} paper'**
  String marketPaperAmountLabel(String amount);

  /// Hint text in the company search field: type a company name or its ticker symbol.
  ///
  /// In en, this message translates to:
  /// **'Name or symbol'**
  String get marketSearchHint;

  /// Tooltip and screen reader label for the X button that empties the company search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get marketSearchClear;

  /// Heading above the companies the player opened recently, on the company search screen before typing.
  ///
  /// In en, this message translates to:
  /// **'Recently viewed'**
  String get marketRecentTitle;

  /// Button next to 'Recently viewed' that empties the list. Verb. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get marketRecentClear;

  /// Title on the company search screen when there are no recent companies yet.
  ///
  /// In en, this message translates to:
  /// **'Find your next company'**
  String get marketRecentEmptyTitle;

  /// Line under 'Find your next company' on the empty company search screen.
  ///
  /// In en, this message translates to:
  /// **'Your recent searches will appear here.'**
  String get marketRecentEmptyBody;

  /// Shown when a company search finds nothing. {query} is what the player typed. Suggests typing the ticker symbol instead.
  ///
  /// In en, this message translates to:
  /// **'Nothing called “{query}”. Try the symbol.'**
  String marketSearchNoResults(String query);

  /// Screen reader label for a placeholder row while search results load.
  ///
  /// In en, this message translates to:
  /// **'Loading company'**
  String get marketSearchLoadingResult;

  /// Shown on the company search screen when a search failed before it finished.
  ///
  /// In en, this message translates to:
  /// **'Search did not finish. Try again.'**
  String get marketSearchDidNotFinish;

  /// Notice above company search results that came from an older reading.
  ///
  /// In en, this message translates to:
  /// **'These results are old. Search again for a newer list.'**
  String get marketSearchStale;

  /// Notice on the company search screen when the phone has no internet connection.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Check your connection and try again.'**
  String get marketSearchOffline;

  /// Notice on the company search screen when the search stopped because the app went to the background.
  ///
  /// In en, this message translates to:
  /// **'The search paused. Try again.'**
  String get marketSearchPaused;

  /// Notice on the company search screen when the server asks the app to slow down.
  ///
  /// In en, this message translates to:
  /// **'Too many searches. Wait a moment and try again.'**
  String get marketSearchRateLimited;

  /// Notice on the company search screen when the server did not answer in time.
  ///
  /// In en, this message translates to:
  /// **'The search took too long. Try again.'**
  String get marketSearchTimeout;

  /// Notice on the company search screen when this version of the app was built without search (test builds).
  ///
  /// In en, this message translates to:
  /// **'Company search is not available in this build.'**
  String get marketSearchDisabled;

  /// Notice on the company search screen for any other search failure.
  ///
  /// In en, this message translates to:
  /// **'Company search is unavailable. Try again.'**
  String get marketSearchUnavailable;

  /// Tooltip and screen reader label for the star button on a stock page, which adds the company to the watchlist. {name} is the company name.
  ///
  /// In en, this message translates to:
  /// **'Follow {name}'**
  String stockFollowTooltip(String name);

  /// Tooltip and screen reader label for the filled star button on a stock page, which removes the company from the watchlist. {name} is the company name.
  ///
  /// In en, this message translates to:
  /// **'Unfollow {name}'**
  String stockUnfollowTooltip(String name);

  /// Tooltip and screen reader label for the share button on a stock page. {name} is the company name.
  ///
  /// In en, this message translates to:
  /// **'Share {name}'**
  String stockShareTooltip(String name);

  /// Title of the card on a stock page that shows how many shares the player owns and what they are worth.
  ///
  /// In en, this message translates to:
  /// **'Your position'**
  String get stockPositionTitle;

  /// Small label next to the price change under a stock's price: the change is over the last 24 hours. Lowercase. Keep short.
  ///
  /// In en, this message translates to:
  /// **'past 24h'**
  String get stockPast24h;

  /// Title in place of the price chart on a stock page when the chart failed to load. A Try again button follows.
  ///
  /// In en, this message translates to:
  /// **'Chart did not load'**
  String get stockChartFailedTitle;

  /// Title in place of the price chart on a stock page when there is not enough price history yet.
  ///
  /// In en, this message translates to:
  /// **'No chart yet'**
  String get stockChartEmptyTitle;

  /// Line under 'No chart yet' on a stock page.
  ///
  /// In en, this message translates to:
  /// **'This token needs more price history.'**
  String get stockChartEmptyBody;

  /// Tooltip and screen reader label for the bell button next to the chart periods on a stock page.
  ///
  /// In en, this message translates to:
  /// **'Set a price alert'**
  String get stockPriceAlertTooltip;

  /// Small line under a stock's price chart: the time of the chart's last reading. {time} is a time ('14:05') or a date and time ('30 Sep · 14:05').
  ///
  /// In en, this message translates to:
  /// **'Chart to {time}'**
  String stockChartUpdatedAt(String time);

  /// Large line on the 'Your position' card of a stock page: how many shares the player owns. {shares} is the number as shown, possibly fractional ('2.5'); {count} is the same number for choosing the plural form.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{shares} shares}}'**
  String stockPositionShares(num count, String shares);

  /// Label on the 'Your position' card: what the owned shares are worth now.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get stockPositionValue;

  /// Label on the 'Your position' card right after a confirmed trade: what the owned shares were worth at that trade's price.
  ///
  /// In en, this message translates to:
  /// **'Value at trade'**
  String get stockPositionValueAtTrade;

  /// Shown on the 'Your position' card instead of a value when there is no price for the stock right now.
  ///
  /// In en, this message translates to:
  /// **'Not priced'**
  String get stockPositionNotPriced;

  /// Label on the 'Your position' card: the average price paid per share.
  ///
  /// In en, this message translates to:
  /// **'Average cost'**
  String get stockPositionAverageCost;

  /// Label on the 'Your position' card: the gain or loss on the shares, as a percent. Noun.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get stockPositionReturn;

  /// Label on the 'Your position' card right after a confirmed trade: the gain or loss at that trade's price. Noun.
  ///
  /// In en, this message translates to:
  /// **'Return at trade'**
  String get stockPositionReturnAtTrade;

  /// Screen reader label for the row of three tabs (About, Holders, Comments) on a stock page.
  ///
  /// In en, this message translates to:
  /// **'Company details'**
  String get stockSectionsLabel;

  /// Tab on a stock page: description, figures and token versions of the company. Keep under 12 characters: three tabs share one row.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get stockSectionAbout;

  /// Tab on a stock page: the largest wallets holding this token. Keep under 12 characters: three tabs share one row.
  ///
  /// In en, this message translates to:
  /// **'Holders'**
  String get stockSectionHolders;

  /// Tab on a stock page: the reasons players shared for buying this stock. Keep under 12 characters: three tabs share one row.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get stockSectionComments;

  /// Button under a shortened company description on a stock page that shows all of it.
  ///
  /// In en, this message translates to:
  /// **'Read more'**
  String get stockAboutReadMore;

  /// Button under a full company description on a stock page that shortens it again.
  ///
  /// In en, this message translates to:
  /// **'Read less'**
  String get stockAboutReadLess;

  /// Label of a figure on a stock page: the dollar value of this token traded in the last 24 hours.
  ///
  /// In en, this message translates to:
  /// **'24h volume'**
  String get stockMetricVolume24h;

  /// Label of a figure on a stock page: how much money sits in the token's trading pools.
  ///
  /// In en, this message translates to:
  /// **'Liquidity'**
  String get stockMetricLiquidity;

  /// Label of a figure on a stock page: the total value of all of this token in existence.
  ///
  /// In en, this message translates to:
  /// **'Token market cap'**
  String get stockMetricTokenMarketCap;

  /// Label of a figure on a stock page: how many wallets hold this token.
  ///
  /// In en, this message translates to:
  /// **'Token holders'**
  String get stockMetricTokenHolders;

  /// Label of a figure on a stock page: the total value of the real company on the stock market.
  ///
  /// In en, this message translates to:
  /// **'Company market cap'**
  String get stockMetricCompanyMarketCap;

  /// Label of a figure on a stock page: the company's industry, such as Tech.
  ///
  /// In en, this message translates to:
  /// **'Sector'**
  String get stockMetricSector;

  /// Heading on a stock page above the list of this company's tokens, one per issuer (for example Backed's AAPLx and Ondo's AAPLon).
  ///
  /// In en, this message translates to:
  /// **'Available tokens'**
  String get stockTokensTitle;

  /// Tooltip and screen reader label for the copy button next to a token on a stock page. It copies the token's address on the blockchain. {symbol} is the token symbol.
  ///
  /// In en, this message translates to:
  /// **'Copy {symbol} address'**
  String stockCopyAddressTooltip(String symbol);

  /// Short notice after a token or wallet address was copied (stock page token list and Holders tab).
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get stockAddressCopied;

  /// Shown on a stock page's About tab while there is no description or figure yet.
  ///
  /// In en, this message translates to:
  /// **'Details are on their way'**
  String get stockAboutEmpty;

  /// Button on a stock page in Real mode when real money cannot trade this company: switches to Practice mode (English 'Paper') to trade it with practice money.
  ///
  /// In en, this message translates to:
  /// **'Practice in Paper'**
  String get stockPracticeInPaper;

  /// Screen reader label for the button that picks which issuer's token to trade, when none is chosen. Each company can have several tokens, one per issuer.
  ///
  /// In en, this message translates to:
  /// **'Token versions'**
  String get stockVersionsLabel;

  /// Screen reader label for the token picker button on a stock page. {version} is the chosen token, issuer and symbol, such as 'Ondo · NVDAon'. 'Change' says the button changes it.
  ///
  /// In en, this message translates to:
  /// **'Token version {version}. Change'**
  String stockVersionSelectedLabel(String version);

  /// Text of the token picker button on a stock page when no token is chosen yet: how many tokens (one per issuer) this company has.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 version} other{{count} versions}}'**
  String stockVersionsCount(int count);

  /// Title of the sheet that lists a company's tokens, one per issuer, to pick which one to trade.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get stockVersionsTitle;

  /// Line under a token in the version picker when it cannot be traded and the server gave no reason.
  ///
  /// In en, this message translates to:
  /// **'Not available to trade.'**
  String get stockVersionNotTradeable;

  /// Big title of the screen where you write why you bought a stock, after a practice buy. 'Reason' is a short note on why you bought.
  ///
  /// In en, this message translates to:
  /// **'Write your reason'**
  String get reasonWriteTitle;

  /// Big title of the same screen after your reason (why you bought) was saved.
  ///
  /// In en, this message translates to:
  /// **'Reason saved'**
  String get reasonWriteSavedTitle;

  /// Question under the title of the write-your-reason screen, inviting you to explain why you bought the stock.
  ///
  /// In en, this message translates to:
  /// **'What made you buy?'**
  String get reasonWritePrompt;

  /// Hint text in the empty text field where you write your reason for buying a stock. Ends with an ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Your take on this stock…'**
  String get reasonWriteHint;

  /// Main full-width button that saves your reason for buying. Keep under 24 characters.
  ///
  /// In en, this message translates to:
  /// **'Save reason'**
  String get reasonWriteSave;

  /// Main full-width button shown after saving your reason failed: tries to save the same reason again. Keep under 24 characters.
  ///
  /// In en, this message translates to:
  /// **'Retry reason'**
  String get reasonWriteRetry;

  /// Main full-width button shown when this buy already has a reason: closes the screen so the app refreshes. Keep under 24 characters.
  ///
  /// In en, this message translates to:
  /// **'Close and refresh'**
  String get reasonWriteCloseRefresh;

  /// Reward line after saving your reason: the Trims (the game's points, a proper noun, never translated) you earned. {amount} is a whole number.
  ///
  /// In en, this message translates to:
  /// **'+{amount} Trims'**
  String reasonWriteRewardTrims(String amount);

  /// Line after saving your reason when it earned no Trims: the Career mission (a goal on the Career floor, not a workday assignment) still counted. Use the Career mission word: misión / missão / objectif.
  ///
  /// In en, this message translates to:
  /// **'Mission recorded'**
  String get reasonWriteMissionRecorded;

  /// How many shares of this stock you hold, under the company name on the write-your-reason screen. {shares} is the number as shown, which can have decimals (for example 1.5); {count} is the same number for choosing the plural form.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{shares} share} other{{shares} shares}}'**
  String reasonWriteHeldShares(num count, String shares);

  /// Error under the reason field when the text is too long or has line breaks.
  ///
  /// In en, this message translates to:
  /// **'Use one line and 180 characters or fewer.'**
  String get reasonWriteErrorInvalidInput;

  /// Error under the reason field when the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Your reason was not saved. Try again.'**
  String get reasonWriteErrorOffline;

  /// Error under the reason field when saving timed out.
  ///
  /// In en, this message translates to:
  /// **'Saving took too long. Try again.'**
  String get reasonWriteErrorTimeout;

  /// Error under the reason field when the sign-in session must be refreshed.
  ///
  /// In en, this message translates to:
  /// **'Refresh your session before saving this reason.'**
  String get reasonWriteErrorAccount;

  /// Error under the reason field when the player's profile (handle) is not set up yet.
  ///
  /// In en, this message translates to:
  /// **'Finish setting up your profile before saving this reason.'**
  String get reasonWriteErrorProfile;

  /// Error under the reason field when the practice buy (English 'paper buy') no longer exists. 'Desk' is the practice desk, the home tab.
  ///
  /// In en, this message translates to:
  /// **'This paper buy was not found. Refresh your desk.'**
  String get reasonWriteErrorOrderNotFound;

  /// Error under the reason field when the order is not a confirmed practice buy (English 'paper buy').
  ///
  /// In en, this message translates to:
  /// **'A reason can be added only to a confirmed paper buy.'**
  String get reasonWriteErrorBuyRequired;

  /// Error under the reason field when you already sold the stock.
  ///
  /// In en, this message translates to:
  /// **'You need to still hold this stock before saving a reason.'**
  String get reasonWriteErrorPositionRequired;

  /// Error under the reason field when this practice buy (English 'paper buy') already has a saved reason. 'Career' is the Career tab.
  ///
  /// In en, this message translates to:
  /// **'This paper buy already has a reason. Refresh your Career.'**
  String get reasonWriteErrorExists;

  /// Error under the reason field when a retried save did not match the first attempt on the server. 'Career' is the Career tab.
  ///
  /// In en, this message translates to:
  /// **'This retry could not be matched. Refresh your Career.'**
  String get reasonWriteErrorRetryMismatch;

  /// Error under the reason field when the server asks to slow down.
  ///
  /// In en, this message translates to:
  /// **'Reasons are busy right now. Try again shortly.'**
  String get reasonWriteErrorRateLimited;

  /// Generic error under the reason field when saving failed.
  ///
  /// In en, this message translates to:
  /// **'Your reason was not saved. Try again.'**
  String get reasonWriteErrorGeneric;

  /// Title of the Settings row and of its bottom sheet where you choose who can see your comments (short notes on why you bought a stock).
  ///
  /// In en, this message translates to:
  /// **'Who can see my comments'**
  String get reasonPrivacyTitle;

  /// Privacy choice name: only you see your comments. Shown as the row's current value in Settings, as an option title in the sheet, and inside status lines. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get reasonPrivacyNobody;

  /// Privacy choice name: anyone in Trimmy sees your comments. Shown as the row's current value in Settings, as an option title in the sheet, and inside status lines. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get reasonPrivacyEveryone;

  /// Privacy choice name: only your Trimmy friends see your comments. Shown as the row's current value in Settings, as an option title in the sheet, and inside status lines. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get reasonPrivacyFriends;

  /// Status line under the Settings row while your new choice is being saved. {choice} is the choice's name, already translated (Nobody, Everyone or Friends). You may put it in quotes.
  ///
  /// In en, this message translates to:
  /// **'Saving {choice}.'**
  String reasonPrivacySavingChoice(String choice);

  /// Status line under the Settings row while your saved choice loads.
  ///
  /// In en, this message translates to:
  /// **'Loading your choice.'**
  String get reasonPrivacyLoading;

  /// Status line under the Settings row before your choice could be read.
  ///
  /// In en, this message translates to:
  /// **'Your choice is not available yet.'**
  String get reasonPrivacyNotAvailable;

  /// Status line under the Settings row right after your choice was saved. {status} is a full sentence, already translated, saying who can see your comments now.
  ///
  /// In en, this message translates to:
  /// **'Saved. {status}'**
  String reasonPrivacySavedStatus(String status);

  /// Status line under the Settings row when the choice was changed on another device and the row now shows that newer choice. {status} is a full sentence, already translated, saying who can see your comments now.
  ///
  /// In en, this message translates to:
  /// **'Changed on another device. Refreshed. {status}'**
  String reasonPrivacyChangedElsewhere(String status);

  /// Status line under the Settings row when the choice is Nobody.
  ///
  /// In en, this message translates to:
  /// **'Only you can see your comments.'**
  String get reasonPrivacyNobodyLine;

  /// Status line under the Settings row when the choice is Everyone. 'Them' is your comments.
  ///
  /// In en, this message translates to:
  /// **'Anyone in Trimmy can see them on each stock page.'**
  String get reasonPrivacyEveryoneLine;

  /// Status line under the Settings row, and the Friends option's line in the sheet, while the friends feature does not exist yet: choosing Friends shares nothing for now.
  ///
  /// In en, this message translates to:
  /// **'Not available yet. Shares nothing until friends exist.'**
  String get reasonPrivacyFriendsLine;

  /// Status line under the Settings row, and the Friends option's line in the sheet, once friends exist. 'Them' is your comments.
  ///
  /// In en, this message translates to:
  /// **'Only your Trimmy friends can see them on each stock page.'**
  String get reasonPrivacyFriendsAvailableLine;

  /// Bold consent line in the sheet when you select Everyone, before saving. 'Handle' is your public username (@name). 'Money never shows' means amounts you invested are never shown.
  ///
  /// In en, this message translates to:
  /// **'Your comments and your handle will show on that stock\'s page for anyone in Trimmy. Money never shows.'**
  String get reasonPrivacyConsentLine;

  /// Line under the Nobody option in the sheet.
  ///
  /// In en, this message translates to:
  /// **'Only you. This is the default.'**
  String get reasonPrivacyNobodyOption;

  /// Line under the Everyone option in the sheet.
  ///
  /// In en, this message translates to:
  /// **'Anyone in Trimmy, on each stock page.'**
  String get reasonPrivacyEveryoneOption;

  /// Small line under the sheet's title: your current saved choice. {choice} is the choice's name, already translated (Nobody, Everyone or Friends).
  ///
  /// In en, this message translates to:
  /// **'Now: {choice}.'**
  String reasonPrivacySheetNow(String choice);

  /// Error under the Settings row when the guest account (a desk used without signing in) expired or was revoked and must be recovered.
  ///
  /// In en, this message translates to:
  /// **'This guest desk needs recovery.'**
  String get reasonPrivacyGuestRecovery;

  /// Error under the Settings row when the guest session must be refreshed.
  ///
  /// In en, this message translates to:
  /// **'Your session needs a refresh. Try again.'**
  String get reasonPrivacySessionRefresh;

  /// Error under the Settings row when your choice could not load because the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Your choice could not load.'**
  String get reasonPrivacyLoadOffline;

  /// Error under the Settings row when loading your choice timed out.
  ///
  /// In en, this message translates to:
  /// **'Your choice took too long to load.'**
  String get reasonPrivacyLoadTimeout;

  /// Error under the Settings row when the sign-in session must be refreshed before your choice can load.
  ///
  /// In en, this message translates to:
  /// **'Your session needs a refresh before this can load.'**
  String get reasonPrivacyLoadSession;

  /// Error under the Settings row when the account no longer exists.
  ///
  /// In en, this message translates to:
  /// **'This account is closed.'**
  String get reasonPrivacyAccountClosed;

  /// Generic error under the Settings row when your choice could not load.
  ///
  /// In en, this message translates to:
  /// **'Your choice could not load.'**
  String get reasonPrivacyLoadFailed;

  /// Error under the Settings row when saving failed because the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Your choice is not saved yet.'**
  String get reasonPrivacySaveOffline;

  /// Error under the Settings row when saving a choice failed because the phone is offline. {choice} is the choice's name, already translated (Nobody, Everyone or Friends). You may write 'The option {choice}' to keep grammar neutral.
  ///
  /// In en, this message translates to:
  /// **'You are offline. {choice} is not saved yet.'**
  String reasonPrivacySaveOfflineChoice(String choice);

  /// Error under the Settings row when saving timed out.
  ///
  /// In en, this message translates to:
  /// **'Saving took too long. Your choice is not saved yet.'**
  String get reasonPrivacySaveTimeout;

  /// Error under the Settings row when saving a choice timed out. {choice} is the choice's name, already translated (Nobody, Everyone or Friends).
  ///
  /// In en, this message translates to:
  /// **'Saving took too long. {choice} is not saved yet.'**
  String reasonPrivacySaveTimeoutChoice(String choice);

  /// Error under the Settings row when the sign-in session must be refreshed before saving.
  ///
  /// In en, this message translates to:
  /// **'Your session needs a refresh. Your choice is not saved yet.'**
  String get reasonPrivacySaveSession;

  /// Error under the Settings row when the sign-in session must be refreshed before saving a choice. {choice} is the choice's name, already translated (Nobody, Everyone or Friends).
  ///
  /// In en, this message translates to:
  /// **'Your session needs a refresh. {choice} is not saved yet.'**
  String reasonPrivacySaveSessionChoice(String choice);

  /// Error under the Settings row when saving failed because the account no longer exists.
  ///
  /// In en, this message translates to:
  /// **'This account is closed. Nothing was saved.'**
  String get reasonPrivacySaveAccountClosed;

  /// Error under the Settings row when a retried save did not match the first attempt on the server, so you must choose again.
  ///
  /// In en, this message translates to:
  /// **'That save could not be matched. Choose again.'**
  String get reasonPrivacySaveMismatch;

  /// Generic error under the Settings row when saving failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Your choice is not saved yet.'**
  String get reasonPrivacySaveFailed;

  /// Generic error under the Settings row when saving a choice failed. {choice} is the choice's name, already translated (Nobody, Everyone or Friends).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. {choice} is not saved yet.'**
  String reasonPrivacySaveFailedChoice(String choice);

  /// Error under the Settings row when loading your choice was refused because of too many requests, with no known wait time.
  ///
  /// In en, this message translates to:
  /// **'Too many changes. Try to load again shortly.'**
  String get reasonPrivacyRateLimitedLoad;

  /// Error under the Settings row when loading your choice was refused because of too many requests. {seconds} is how many seconds to wait (1 or more).
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Too many changes. Try to load again in {seconds} second.} other{Too many changes. Try to load again in {seconds} seconds.}}'**
  String reasonPrivacyRateLimitedLoadSeconds(int seconds);

  /// Error under the Settings row when saving your choice was refused because of too many requests, with no known wait time.
  ///
  /// In en, this message translates to:
  /// **'Too many changes. Try to save again shortly.'**
  String get reasonPrivacyRateLimitedSave;

  /// Error under the Settings row when saving your choice was refused because of too many requests. {seconds} is how many seconds to wait (1 or more).
  ///
  /// In en, this message translates to:
  /// **'{seconds, plural, =1{Too many changes. Try to save again in {seconds} second.} other{Too many changes. Try to save again in {seconds} seconds.}}'**
  String reasonPrivacyRateLimitedSaveSeconds(int seconds);

  /// Title of the bottom sheet that opens when someone taps Report on another trader's comment (a short note on why they bought a stock) on a stock page. Asks which category fits.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting this?'**
  String get reasonReportSheetTitle;

  /// Line under the title of the report sheet on a stock page's comments tab. 'Reason' here means the reason for reporting (the category), not the trade reason. Reassures that the report is anonymous to the author.
  ///
  /// In en, this message translates to:
  /// **'Choose the closest reason. The author will not see who reported it.'**
  String get reasonReportSheetBody;

  /// Title of the confirmation dialog after choosing a report category for another trader's reason (the short note on why they bought) on a stock page. English says 'reason' here and 'comment' elsewhere for the same thing.
  ///
  /// In en, this message translates to:
  /// **'Report this reason?'**
  String get reasonReportConfirmTitle;

  /// Body of the report confirmation dialog. 'It' is the reported reason (comment). Each branch names the chosen report category (spam, harassment, impersonation, unsafe content, something else). The reason disappears from the page once the server receives the report. For 'other' you may simply say Trimmy will review it.
  ///
  /// In en, this message translates to:
  /// **'{category, select, spam{Trimmy will review it as spam. It will leave this page after the report is received.} harassment{Trimmy will review it as harassment. It will leave this page after the report is received.} impersonation{Trimmy will review it as impersonation. It will leave this page after the report is received.} unsafe{Trimmy will review it as unsafe content. It will leave this page after the report is received.} other{Trimmy will review it as something else. It will leave this page after the report is received.}}'**
  String reasonReportConfirmBody(String category);

  /// Verb. Small button on another trader's comment card, and the confirm button of the report dialog. Sends a report to moderators. Keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reasonReportAction;

  /// Verb. Small button on another trader's comment card, and the confirm button of the block dialog. Blocks that person. Keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get reasonBlockAction;

  /// Short notice shown after a report on a comment was received by the server.
  ///
  /// In en, this message translates to:
  /// **'Report received.'**
  String get reasonReportReceived;

  /// Title of the dialog confirming that you want to block the author of a comment. {handle} is their username, shown after @ and never translated.
  ///
  /// In en, this message translates to:
  /// **'Block @{handle}?'**
  String reasonBlockConfirmTitle(String handle);

  /// Body of the block confirmation dialog on a stock page's comments tab. 'Reasons' are the person's comments on why they bought. Explains what blocking does.
  ///
  /// In en, this message translates to:
  /// **'Their reasons will leave this page. Any friendship and open invitations between you will also be removed. Public reasons can still be seen from other accounts.'**
  String get reasonBlockConfirmBody;

  /// Short notice after blocking someone from their comment. {handle} is their username after @, never translated. Prefer a phrasing that avoids gender (for example 'You blocked @name.').
  ///
  /// In en, this message translates to:
  /// **'@{handle} blocked.'**
  String reasonBlockDone(String handle);

  /// Notice when a report or block failed because the same setting changed on another device.
  ///
  /// In en, this message translates to:
  /// **'This changed on another device. Choose again.'**
  String get reasonSafetyErrorConflict;

  /// Notice when reports or blocks were sent too quickly.
  ///
  /// In en, this message translates to:
  /// **'Too many changes at once. Wait a moment and try again.'**
  String get reasonSafetyErrorRateLimited;

  /// Notice when a report or block is not allowed for the signed-in account.
  ///
  /// In en, this message translates to:
  /// **'This action is unavailable for your account right now.'**
  String get reasonSafetyErrorUnavailable;

  /// Notice when a report or block may or may not have reached the server. The app retries it later without doing it twice.
  ///
  /// In en, this message translates to:
  /// **'We could not confirm the result. It will retry safely.'**
  String get reasonSafetyErrorUnconfirmed;

  /// Notice when a report or block failed for any other reason.
  ///
  /// In en, this message translates to:
  /// **'That action could not be completed. Try again.'**
  String get reasonSafetyErrorGeneric;

  /// Empty state on a stock page's comments tab when nobody has shared a comment (a short note on why they bought) on this stock.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get reasonEmpty;

  /// Empty state on a stock page's comments tab when the Friends filter is on and no friend has shared a comment.
  ///
  /// In en, this message translates to:
  /// **'No comments from friends yet'**
  String get reasonEmptyFriends;

  /// Notice on a stock page's comments tab when the app could not read all of your own saved reasons for this stock.
  ///
  /// In en, this message translates to:
  /// **'Your complete reason history could not be loaded here.'**
  String get reasonOwnHistoryIncomplete;

  /// Notice on a stock page's comments tab when the app could not check whether your own reason on this stock is private. A Try again button follows.
  ///
  /// In en, this message translates to:
  /// **'Your private reason status could not be checked.'**
  String get reasonOwnStatusFailed;

  /// Button at the bottom of the comments list that loads more comments. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get reasonShowMore;

  /// Error on a stock page's comments tab when the sign-in session must be refreshed.
  ///
  /// In en, this message translates to:
  /// **'Your session needs a refresh before comments can load.'**
  String get reasonLoadSessionRefresh;

  /// Error on a stock page's comments tab when the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Comments couldn’t load.'**
  String get reasonLoadOffline;

  /// Error on a stock page's comments tab when loading timed out.
  ///
  /// In en, this message translates to:
  /// **'Comments took too long to load.'**
  String get reasonLoadTimeout;

  /// Error on a stock page's comments tab when the server asks to slow down.
  ///
  /// In en, this message translates to:
  /// **'Comments are refreshing too quickly. Try again shortly.'**
  String get reasonLoadRateLimited;

  /// Generic error on a stock page's comments tab when comments failed to load.
  ///
  /// In en, this message translates to:
  /// **'Comments couldn’t load.'**
  String get reasonLoadFailed;

  /// Screen reader label for the two-button switch (Everyone, Friends) above the comments on a stock page.
  ///
  /// In en, this message translates to:
  /// **'Choose whose comments to see'**
  String get reasonAudienceSemantics;

  /// Filter button above the comments on a stock page: show comments from everyone who shares publicly. Half-width button, keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get reasonAudienceEveryone;

  /// Filter button above the comments on a stock page: show only your friends' comments. Half-width button, keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get reasonAudienceFriends;

  /// Tiny badge on a comment card that marks your own comment. Keep under 6 characters.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get reasonYouBadge;

  /// Small grey line on a comment card: when the comment (reason) was saved. {date} is a date with day, short month and year; {time} is a 24-hour time.
  ///
  /// In en, this message translates to:
  /// **'Saved {date}, {time}'**
  String reasonSavedAt(String date, String time);

  /// Banner on a stock page's comments tab when you wrote a comment on this stock but only you can see it. A Settings button follows.
  ///
  /// In en, this message translates to:
  /// **'Your comment is private.'**
  String get reasonPrivateLine;

  /// Screen reader label while the comments on a stock page load.
  ///
  /// In en, this message translates to:
  /// **'Loading comments'**
  String get reasonLoadingComments;

  /// Title of the Fast buy sheet, a quick search that goes straight to buying a stock. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Fast buy'**
  String get fastBuyTitle;

  /// Tooltip and screen reader label of the close (X) button on the Fast buy sheet.
  ///
  /// In en, this message translates to:
  /// **'Close fast buy'**
  String get fastBuyClose;

  /// Hint text in the search field of the Fast buy sheet. The person types a company name or a ticker symbol (such as AAPL). Keep under 32 characters.
  ///
  /// In en, this message translates to:
  /// **'Search a name or ticker'**
  String get fastBuySearchHint;

  /// Notice on the Fast buy sheet when the stock the person tapped could not be opened for buying.
  ///
  /// In en, this message translates to:
  /// **'This stock couldn’t open. Try again.'**
  String get fastBuyOpenFailed;

  /// Error on the Fast buy sheet (real money mode) when the list of stocks that can be bought could not be loaded. A Retry button follows.
  ///
  /// In en, this message translates to:
  /// **'Trading couldn’t connect.'**
  String get fastBuyConnectFailed;

  /// Empty state on the Fast buy sheet when there is nothing to buy and nothing was searched.
  ///
  /// In en, this message translates to:
  /// **'No stocks available to buy right now.'**
  String get fastBuyNoneAvailable;

  /// Empty state on the Fast buy sheet (real money mode) when no stock that can be bought matches the search text.
  ///
  /// In en, this message translates to:
  /// **'No tradeable stock matches that.'**
  String get fastBuyNoTradeableMatch;

  /// Empty state on the Fast buy sheet (practice mode) when the search found no company.
  ///
  /// In en, this message translates to:
  /// **'No matches yet.'**
  String get fastBuyNoMatches;

  /// An amount of practice money (English calls practice money 'paper'). Used as a screen reader label for the amount typed on the practice order keypad, and anywhere a bare practice money amount is read out. {amount} is the figure already formatted, without any currency symbol.
  ///
  /// In en, this message translates to:
  /// **'{amount} paper'**
  String paperAmount(String amount);

  /// Practice order ticket, small grey line under the big typed number when the person types a number of shares: roughly how much practice money that is. Keep the ≈ sign. {amount} is the figure already formatted, without a currency symbol.
  ///
  /// In en, this message translates to:
  /// **'≈ {amount} paper'**
  String paperOrderEquivalentPaper(String amount);

  /// Practice order ticket, small grey line under the big typed amount when the person types an amount of practice money: roughly how many shares that buys or sells. Keep the ≈ sign. {count} is the share count as a number (often fractional, such as 0.043212) and only picks the grammatical form; {shares} is the same figure formatted for display. English keeps 'shares' for every count on purpose; use your language's singular and plural forms.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{≈ {shares} shares}}'**
  String paperOrderEquivalentShares(num count, String shares);

  /// Practice order ticket, small grey line under the typed amount when no price is known yet: the conversion between money and shares will appear on the next (review) step.
  ///
  /// In en, this message translates to:
  /// **'Conversion shown at review'**
  String get paperOrderConversionAtReview;

  /// Title at the top of the practice order ticket when buying. {symbol} is the stock's ticker symbol, never translated. Keep short, it sits in the top bar.
  ///
  /// In en, this message translates to:
  /// **'Buy {symbol}'**
  String paperOrderBuyTitle(String symbol);

  /// Title at the top of the practice order ticket when selling. {symbol} is the stock's ticker symbol, never translated. Keep short, it sits in the top bar.
  ///
  /// In en, this message translates to:
  /// **'Sell {symbol}'**
  String paperOrderSellTitle(String symbol);

  /// Title in the top bar of the practice order review step, before confirming a buy. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Review your buy'**
  String get paperOrderReviewBuyTitle;

  /// Title in the top bar of the practice order review step, before confirming a sale. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Review your sell'**
  String get paperOrderReviewSellTitle;

  /// Title in the top bar after a practice buy or sell went through. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed'**
  String get paperOrderConfirmedTitle;

  /// Screen reader label for the grab handle at the top of the first practice trade review sheet. Swiping down closes the sheet so the person can change the amount.
  ///
  /// In en, this message translates to:
  /// **'Swipe down to edit your buy'**
  String get paperOrderFirstTradeSwipeHint;

  /// Tooltip and screen reader label of the close (X) button on the first practice trade review sheet. It leaves the first trade without buying.
  ///
  /// In en, this message translates to:
  /// **'Skip first trade'**
  String get paperOrderFirstTradeSkip;

  /// Large heading of the first practice trade review sheet, shown during onboarding before the person confirms their first buy. Ends with a period in English.
  ///
  /// In en, this message translates to:
  /// **'Review your buy.'**
  String get paperOrderFirstTradeReviewTitle;

  /// Row label on the first trade review ticket. The value on the right is how many shares the buy gets.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get paperOrderSharesLabel;

  /// Row label on the order review ticket. The value on the right is the price of one share.
  ///
  /// In en, this message translates to:
  /// **'Price per share'**
  String get paperOrderPricePerShare;

  /// Row label on the order review ticket. The value on the right is the fee charged for the order.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get paperOrderFee;

  /// Label above the large total amount on the first trade review ticket.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get paperOrderTotal;

  /// Busy label on the main button of the first trade review sheet while the buy is being confirmed. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Confirming buy…'**
  String get paperOrderConfirmingBuy;

  /// Busy label on the main button of the first trade review sheet while the app asks for the latest price. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Checking price…'**
  String get paperOrderCheckingPrice;

  /// Main button on the order review step that places the practice buy. Keep under 20 characters.
  ///
  /// In en, this message translates to:
  /// **'Confirm buy'**
  String get paperOrderConfirmBuy;

  /// Main button on the order review step that places the practice sale. Keep under 20 characters.
  ///
  /// In en, this message translates to:
  /// **'Confirm sell'**
  String get paperOrderConfirmSell;

  /// A number of shares, used as the value of 'Your position' after a trade and as the screen reader label of a share count typed on the order keypad. {count} is the share count as a number (it can be fractional, such as 2.1605) and only picks the grammatical form; {shares} is the same figure formatted for display. English keeps 'shares' for every count on purpose; use your language's singular and plural forms.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{shares} shares}}'**
  String paperOrderSharesValue(num count, String shares);

  /// Small grey line above the keypad when selling: how many shares the person owns and can sell. {count} is the share count as a number (it can be fractional) and only picks the grammatical form; {shares} is the same figure formatted for display. English keeps 'shares' for every count on purpose; use your language's singular and plural forms.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{shares} shares available}}'**
  String paperOrderSharesAvailable(num count, String shares);

  /// Small grey line above the keypad when buying: how much practice money (English says 'paper') the person can spend. {amount} is the figure already formatted, without a currency symbol.
  ///
  /// In en, this message translates to:
  /// **'{amount} paper available'**
  String paperOrderPaperAvailable(String amount);

  /// Bold line on the order review ticket before a practice buy is confirmed: how many shares the person is about to buy. {count} is the share count as a number (often fractional) and only picks the grammatical form; {shares} is the same figure formatted for display. English keeps 'shares' for every count on purpose.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Buying {shares} shares}}'**
  String paperOrderBuyingShares(num count, String shares);

  /// Bold line on the order review ticket before a practice sale is confirmed: how many shares the person is about to sell. {count} is the share count as a number (often fractional) and only picks the grammatical form; {shares} is the same figure formatted for display. English keeps 'shares' for every count on purpose.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Selling {shares} shares}}'**
  String paperOrderSellingShares(num count, String shares);

  /// Label above the total on the review ticket of a practice buy: the amount of practice money the person pays.
  ///
  /// In en, this message translates to:
  /// **'You pay'**
  String get paperOrderYouPay;

  /// Label above the total on the review ticket of a practice sale: the amount of practice money the person gets back.
  ///
  /// In en, this message translates to:
  /// **'You receive'**
  String get paperOrderYouReceive;

  /// Screen reader announcement for the success check mark after a practice buy went through.
  ///
  /// In en, this message translates to:
  /// **'Buy confirmed'**
  String get paperOrderBuyConfirmed;

  /// Screen reader announcement for the success check mark after a practice sale went through.
  ///
  /// In en, this message translates to:
  /// **'Sale confirmed'**
  String get paperOrderSaleConfirmed;

  /// Large heading after a practice buy: the stock now sits on the person's desk (the Desk, the home tab with their practice holdings). {symbol} is the ticker symbol, never translated.
  ///
  /// In en, this message translates to:
  /// **'{symbol} is on your desk.'**
  String paperOrderOnYourDesk(String symbol);

  /// Large heading after a practice sale that sold every share: the stock is no longer on the person's desk (the Desk, the home tab). {symbol} is the ticker symbol, never translated.
  ///
  /// In en, this message translates to:
  /// **'{symbol} left your desk.'**
  String paperOrderLeftYourDesk(String symbol);

  /// Large heading after a practice sale that sold only some shares: the person still holds the stock, with fewer shares. {symbol} is the ticker symbol, never translated.
  ///
  /// In en, this message translates to:
  /// **'Your {symbol} position changed.'**
  String paperOrderPositionChanged(String symbol);

  /// Grey line under the heading after a practice buy: how many shares were bought. {count} is the share count as a number (often fractional) and only picks the grammatical form; {shares} is the same figure formatted for display. English keeps 'shares' for every count on purpose.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Bought {shares} shares}}'**
  String paperOrderBoughtShares(num count, String shares);

  /// Grey line under the heading after a practice sale: how many shares were sold. {count} is the share count as a number (often fractional) and only picks the grammatical form; {shares} is the same figure formatted for display. English keeps 'shares' for every count on purpose.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Sold {shares} shares}}'**
  String paperOrderSoldShares(num count, String shares);

  /// Row label on the trade receipt. The value is how many shares of this stock the person now holds.
  ///
  /// In en, this message translates to:
  /// **'Your position'**
  String get paperOrderYourPosition;

  /// Row label on the trade receipt. The value is what the person's shares of this stock are worth now, in practice money.
  ///
  /// In en, this message translates to:
  /// **'Position value'**
  String get paperOrderPositionValue;

  /// Row label on the trade receipt. The value is how many Trims (the game's points, a proper noun, never translated) the trade earned, such as +10.
  ///
  /// In en, this message translates to:
  /// **'Trims earned'**
  String get paperOrderTrimsEarned;

  /// Label of the one-line text field on the trade receipt where the person writes why they bought the stock (their reason).
  ///
  /// In en, this message translates to:
  /// **'Why did you buy?'**
  String get paperOrderReasonLabel;

  /// Hint inside the empty reason field on the trade receipt: write the reason in one short, clear line.
  ///
  /// In en, this message translates to:
  /// **'One clear line'**
  String get paperOrderReasonHint;

  /// Button under the reason field on the trade receipt that saves why the person bought. Keep under 24 characters.
  ///
  /// In en, this message translates to:
  /// **'Save reason'**
  String get paperOrderSaveReason;

  /// Same button as 'Save reason' after saving the reason failed: tries to save the same reason again. Keep under 24 characters.
  ///
  /// In en, this message translates to:
  /// **'Retry reason'**
  String get paperOrderRetryReason;

  /// Large reward line after the reason was saved: how many Trims (the game's points, a proper noun, never translated) the person earned for writing it. {amount} is a whole number.
  ///
  /// In en, this message translates to:
  /// **'+{amount} Trims'**
  String paperOrderReasonTrims(String amount);

  /// Large line after the reason was saved when it earned no Trims (the daily limit was reached).
  ///
  /// In en, this message translates to:
  /// **'Reason saved'**
  String get paperOrderReasonSaved;

  /// The person's own saved reason, shown in quotation marks under 'Reason saved'. Use your language's quotation marks. {note} is the text the person wrote, never translated.
  ///
  /// In en, this message translates to:
  /// **'“{note}”'**
  String paperOrderReasonQuote(String note);

  /// Grey line on the receipt after a practice buy when writing down a reason cannot be offered right now. The trade itself went through.
  ///
  /// In en, this message translates to:
  /// **'Your trade is confirmed. Saving a reason is unavailable right now.'**
  String get paperOrderReasonUnavailable;

  /// Screen reader label for the two-option switch on the order ticket that chooses whether the typed amount is money or a number of shares.
  ///
  /// In en, this message translates to:
  /// **'Order amount unit'**
  String get paperOrderUnitLabel;

  /// Option on the order ticket's two-option switch: type the order as an amount of practice money (English calls practice money 'paper'). The other option is 'Shares'. Very tight space, about 10 characters: a short word for money is enough.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get paperOrderUnitPaper;

  /// Option on the order ticket's two-option switch: type the order as a number of shares. The other option is the money option. Very tight space, about 10 characters.
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get paperOrderUnitShares;

  /// Screen reader label for the backspace key on the order ticket's number keypad. Removes the last typed digit.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get paperOrderKeyDelete;

  /// Screen reader label for the decimal key on the order ticket's number keypad. The key shows the reader's decimal mark (a point or a comma depending on the region).
  ///
  /// In en, this message translates to:
  /// **'Decimal point'**
  String get paperOrderKeyDecimal;

  /// Error notice on the order ticket when the company has no tradeable stock token (version) to order.
  ///
  /// In en, this message translates to:
  /// **'This company has no available version.'**
  String get paperOrderNoVersion;

  /// Error notice on the trade receipt: the trade went through but saving the person's reason failed.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed. Your reason was not saved. Try again.'**
  String get paperOrderReasonNotSaved;

  /// Error notice on the trade receipt after an unexpected failure while saving the reason. The trade itself went through.
  ///
  /// In en, this message translates to:
  /// **'The trade is done, but the reason was not saved. Try again.'**
  String get paperOrderReasonNotSavedDone;

  /// Error notice when the reason is longer than 180 characters or has a line break.
  ///
  /// In en, this message translates to:
  /// **'Use one line and 180 characters or fewer.'**
  String get paperOrderReasonTooLong;

  /// Error notice on the trade receipt: the trade went through, but the phone has no connection so the reason was not saved.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed. You are offline, so your reason was not saved. Try again.'**
  String get paperOrderReasonOffline;

  /// Error notice on the trade receipt: the trade went through, but saving the reason timed out.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed. Saving the reason took too long. Try again.'**
  String get paperOrderReasonTimeout;

  /// Error notice on the trade receipt: the trade went through, but the sign-in session expired so the reason cannot be saved yet.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed. Your session needs to be refreshed before saving the reason.'**
  String get paperOrderReasonSessionExpired;

  /// Error notice on the trade receipt: the trade went through, but the person must finish their profile before reasons can be saved.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed. Finish setting up your profile before saving the reason.'**
  String get paperOrderReasonProfileRequired;

  /// Error notice on the trade receipt: the server could not find the order the reason belongs to. 'Desk' is the home tab.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed. This order was not found. Refresh your desk.'**
  String get paperOrderReasonOrderNotFound;

  /// Error notice: a reason can only be written for a confirmed practice buy ('paper buy' means a buy with practice money).
  ///
  /// In en, this message translates to:
  /// **'Reasons can be saved only after a confirmed paper buy.'**
  String get paperOrderReasonBuyRequired;

  /// Error notice on the trade receipt: the person must still own this stock to save a reason for buying it.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed. Hold this stock before saving a reason.'**
  String get paperOrderReasonPositionRequired;

  /// Error notice on the trade receipt: a reason was already saved for this trade. 'Career' is the Career tab.
  ///
  /// In en, this message translates to:
  /// **'This trade already has a saved reason. Refresh your career.'**
  String get paperOrderReasonExists;

  /// Error notice on the trade receipt: a repeated attempt to save the reason did not match the first attempt. 'Career' is the Career tab.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed. This retry could not be matched. Refresh your career.'**
  String get paperOrderReasonRetryMismatch;

  /// Error notice on the trade receipt: too many reason saves right now (rate limit). The trade went through.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed. Reasons are busy right now. Try again shortly.'**
  String get paperOrderReasonBusy;

  /// Error notice on the order ticket when the typed amount is zero or not valid.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount above zero.'**
  String get paperOrderErrorInvalidAmount;

  /// Error notice on the order ticket: not enough practice money (English says 'paper') for this buy.
  ///
  /// In en, this message translates to:
  /// **'There is not enough paper for this order.'**
  String get paperOrderErrorInsufficientPaper;

  /// Error notice on the order ticket: the person owns fewer shares than they tried to sell.
  ///
  /// In en, this message translates to:
  /// **'There are not enough shares to sell.'**
  String get paperOrderErrorInsufficientShares;

  /// Error notice: the price shown on the review step is too old. The person goes back to get a new quote (a fresh price estimate).
  ///
  /// In en, this message translates to:
  /// **'That price expired. Check a new quote.'**
  String get paperOrderErrorQuoteExpired;

  /// Error notice: the stock price changed before the order was placed. The person goes back to see a new quote (a fresh price estimate).
  ///
  /// In en, this message translates to:
  /// **'The price moved. Check the new quote.'**
  String get paperOrderErrorPriceChanged;

  /// Error notice on the order ticket when the phone has no internet connection.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Check your connection and try again.'**
  String get paperOrderErrorOffline;

  /// Error notice on the order ticket when the server took too long to answer.
  ///
  /// In en, this message translates to:
  /// **'That took too long. Try again.'**
  String get paperOrderErrorTimeout;

  /// Error notice on the order ticket when the person must sign in (save their desk, their practice account) before ordering. 'Desk' is the home tab with their practice holdings.
  ///
  /// In en, this message translates to:
  /// **'Save your desk before placing this order.'**
  String get paperOrderErrorAccountRequired;

  /// Error notice: the same order was already placed once. 'Desk' is the home tab.
  ///
  /// In en, this message translates to:
  /// **'This order was already received. Refresh your desk.'**
  String get paperOrderErrorDuplicate;

  /// Error notice on the order ticket when the server refused the order or its answer did not match.
  ///
  /// In en, this message translates to:
  /// **'The order was not accepted.'**
  String get paperOrderErrorRejected;

  /// Error notice on the order ticket after an unexpected failure.
  ///
  /// In en, this message translates to:
  /// **'The order did not go through. Try again.'**
  String get paperOrderErrorUnavailable;

  /// Real mode order screen, notice when a buy needs more USDC (a US dollar token) in the person's wallet. USDC, SOL and Solana are never translated.
  ///
  /// In en, this message translates to:
  /// **'Add USDC to your Solana wallet first.'**
  String get liveOrderErrorAddUsdc;

  /// Real mode order screen, notice when the wallet needs more SOL (Solana's own coin) to pay network fees. SOL is never translated.
  ///
  /// In en, this message translates to:
  /// **'Add SOL to cover network and account fees.'**
  String get liveOrderErrorAddSol;

  /// Real mode order screen, notice when someone tries to sell more of a tokenized stock than they hold.
  ///
  /// In en, this message translates to:
  /// **'You don’t have enough of this token to sell.'**
  String get liveOrderErrorInsufficientHoldings;

  /// Real mode order screen, notice when an order is larger than the most Trimmy allows per order.
  ///
  /// In en, this message translates to:
  /// **'This order is above the current trade limit.'**
  String get liveOrderErrorTradeLimit;

  /// Real mode order screen, notice when the app is too old to show the token issuer's terms. The issuer is the firm that creates the token.
  ///
  /// In en, this message translates to:
  /// **'Update Trimmy to review the issuer terms before trading.'**
  String get liveOrderErrorAppUpdate;

  /// Real mode order screen, notice when the person must tick the box accepting the token issuer's terms again.
  ///
  /// In en, this message translates to:
  /// **'Confirm the issuer terms to continue.'**
  String get liveOrderErrorTermsRequired;

  /// Real mode order screen, notice when the person has no wallet yet.
  ///
  /// In en, this message translates to:
  /// **'Create your wallet to continue.'**
  String get liveOrderErrorWalletRequired;

  /// Real mode order screen, notice when an earlier order has not finished confirming, so a new one cannot start.
  ///
  /// In en, this message translates to:
  /// **'Your previous trade is still confirming.'**
  String get liveOrderErrorOrderPending;

  /// Real mode order screen, notice when the price shown for the order is too old. A quote is the price estimate before an order.
  ///
  /// In en, this message translates to:
  /// **'That price expired. Get a fresh quote.'**
  String get liveOrderErrorQuoteExpired;

  /// Real mode order screen, notice when the price service is overloaded.
  ///
  /// In en, this message translates to:
  /// **'Quotes are busy. Try again in a moment.'**
  String get liveOrderErrorBusy;

  /// Real mode order screen, notice when no market can fill this order now. A route is the path an order takes through markets.
  ///
  /// In en, this message translates to:
  /// **'No route for this order right now. Try another amount.'**
  String get liveOrderErrorNoRoute;

  /// Real mode order screen, notice when the tokenized stock only trades during US market hours and the market is closed.
  ///
  /// In en, this message translates to:
  /// **'This stock trades while US markets are open. Try again then.'**
  String get liveOrderErrorMarketClosed;

  /// Real mode order screen, notice when the order is smaller than the smallest order a market maker (a firm that offers prices) accepts.
  ///
  /// In en, this message translates to:
  /// **'This order is under the market maker’s minimum. Try a larger amount.'**
  String get liveOrderErrorBelowMinimum;

  /// Real mode order screen, notice when the price offered is too far from the real market price, so Trimmy refuses it.
  ///
  /// In en, this message translates to:
  /// **'That price is too far from the market right now. Try again shortly or a smaller amount.'**
  String get liveOrderErrorPriceOffMarket;

  /// Real mode order screen, notice when network fees are too high for this order right now.
  ///
  /// In en, this message translates to:
  /// **'The fees are too high for this order. Try later.'**
  String get liveOrderErrorFeeTooHigh;

  /// Real mode order screen, notice when the person's sign-in expired or the account changed.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to use your wallet.'**
  String get liveOrderErrorAccountRequired;

  /// Real mode order screen, notice when the reviewed order cannot be sent as is and needs a new price.
  ///
  /// In en, this message translates to:
  /// **'This order needs a fresh quote.'**
  String get liveOrderErrorFreshQuote;

  /// Real mode order screen, notice when the trading service could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Trading couldn’t connect. Try again.'**
  String get liveOrderErrorUnavailable;

  /// Real mode order screen, notice for any other error from the trading service.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t complete this step. Try again.'**
  String get liveOrderErrorGeneric;

  /// Real mode order screen, notice when someone taps Review before ticking the box that accepts the token issuer's terms.
  ///
  /// In en, this message translates to:
  /// **'Confirm the issuer terms first.'**
  String get liveOrderConfirmTermsFirst;

  /// Real mode sell screen, notice when the typed number of shares is not a valid number.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid share amount.'**
  String get liveOrderInvalidShares;

  /// Real mode buy screen, notice when the typed USDC amount (US dollar token) is not a valid number.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid USDC amount.'**
  String get liveOrderInvalidUsdc;

  /// Real mode order screen, notice when the typed amount is above the per-order limit. {amount} is the limit with its unit, already formatted.
  ///
  /// In en, this message translates to:
  /// **'Up to {amount} per order.'**
  String liveOrderUpToPerOrder(String amount);

  /// Real mode buy screen, notice when the typed amount is below the smallest buy for this token. {amount} is that minimum with its unit, already formatted.
  ///
  /// In en, this message translates to:
  /// **'Orders for this token start at {amount}.'**
  String liveOrderMinimum(String amount);

  /// Real mode order screen, notice shown when someone tries to order while the market is closed: the market status line as a sentence. {status} is already translated, such as 'Closed · opens Mon 1:05 AM'. Usually just adds your language's full stop.
  ///
  /// In en, this message translates to:
  /// **'{status}.'**
  String liveOrderMarketNotice(String status);

  /// Real mode order screen, notice when the app could not get a checked price for the order.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t get a verified quote. Try again.'**
  String get liveOrderQuoteFailed;

  /// Real mode order screen, notice after sending an order when the reply was lost; the app checks the result and reassures that the order is never sent twice.
  ///
  /// In en, this message translates to:
  /// **'Checking the result. Your order won’t be sent twice.'**
  String get liveOrderCheckingResult;

  /// Real mode order screen, notice when approving the transaction in the wallet did not finish, so nothing was sent.
  ///
  /// In en, this message translates to:
  /// **'Signing didn’t finish. No order was sent.'**
  String get liveOrderSigningFailed;

  /// Real mode order screen, notice while the app retries checking an order's status.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to check your order…'**
  String get liveOrderReconnecting;

  /// Real mode order screen, notice when the issuer's terms web page could not open.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open the issuer’s terms. Try again.'**
  String get liveOrderTermsOpenFailed;

  /// Real mode order screen and trade history, notice when the blockchain explorer page for a transaction could not open.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open the transaction. Try again.'**
  String get liveOrderTransactionOpenFailed;

  /// Real mode order screen, top bar title when the stock's name is not known yet. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Trade'**
  String get liveOrderTitleFallback;

  /// Real mode order screen, title when the signed-in account changed while trading.
  ///
  /// In en, this message translates to:
  /// **'Your account changed'**
  String get liveOrderAccountChangedTitle;

  /// Real mode order screen, text under 'Your account changed': sign in, then open this trade screen again.
  ///
  /// In en, this message translates to:
  /// **'Reopen trading after signing in.'**
  String get liveOrderAccountChangedBody;

  /// Real mode order screen, title when the app could not read the status of the person's last order.
  ///
  /// In en, this message translates to:
  /// **'Let’s check your last order'**
  String get liveOrderCheckLastOrderTitle;

  /// Real mode order screen, title when the trading service could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Trading couldn’t connect'**
  String get liveOrderConnectFailedTitle;

  /// Real mode order screen, text under a connection error title: try again once the phone is online.
  ///
  /// In en, this message translates to:
  /// **'Try again when you’re connected.'**
  String get liveOrderConnectedRetryBody;

  /// Real mode order screen, title when Trimmy has paused real-money trading for everyone.
  ///
  /// In en, this message translates to:
  /// **'Trading is temporarily paused'**
  String get liveOrderPausedTitle;

  /// Real mode order screen, reassurance under 'Trading is temporarily paused': the person's money and stocks are safe.
  ///
  /// In en, this message translates to:
  /// **'Your wallet and holdings are still here.'**
  String get liveOrderPausedBody;

  /// Real mode order screen, title when the chosen tokenized stock cannot be bought or sold in Trimmy.
  ///
  /// In en, this message translates to:
  /// **'This token isn’t tradable here yet'**
  String get liveOrderNotTradableTitle;

  /// Real mode order screen, text under 'This token isn't tradable here yet'.
  ///
  /// In en, this message translates to:
  /// **'Choose another stock to trade.'**
  String get liveOrderChooseAnother;

  /// Real mode order screen, button that goes back to the stock list. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Back to stocks'**
  String get liveOrderBackToStocks;

  /// Real mode order screen, under the amount field while the wallet balance loads.
  ///
  /// In en, this message translates to:
  /// **'Checking balance…'**
  String get liveOrderCheckingBalance;

  /// Real mode order screen, under the amount field: how much the person can spend (USDC) or sell (shares). {amount} is the amount with its unit, already formatted.
  ///
  /// In en, this message translates to:
  /// **'{amount} available'**
  String liveOrderAvailable(String amount);

  /// Real mode order screen, heading while buying. {symbol} is the token symbol, never translated. 'Buy' is a verb here.
  ///
  /// In en, this message translates to:
  /// **'Buy {symbol}'**
  String liveOrderBuyTitle(String symbol);

  /// Real mode order screen, heading while selling. {symbol} is the token symbol, never translated. 'Sell' is a verb here.
  ///
  /// In en, this message translates to:
  /// **'Sell {symbol}'**
  String liveOrderSellTitle(String symbol);

  /// Real mode order screen, small button that switches a sell order to a buy order. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Buy instead'**
  String get liveOrderBuyInstead;

  /// Real mode order screen, small button that switches a buy order to a sell order. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Sell instead'**
  String get liveOrderSellInstead;

  /// Real mode order screen, label above the amount field when selling.
  ///
  /// In en, this message translates to:
  /// **'You sell'**
  String get liveOrderYouSell;

  /// Real mode order screen, label above the amount field when buying, and the first line of the order review.
  ///
  /// In en, this message translates to:
  /// **'You pay'**
  String get liveOrderYouPay;

  /// Real mode order screen, small line: the most one order can be. {amount} is the limit with its unit, already formatted.
  ///
  /// In en, this message translates to:
  /// **'Order limit: {amount}'**
  String liveOrderLimit(String amount);

  /// Real mode sell screen: after tapping Max (sell everything), the amount was lowered to the per-order limit. {amount} is that limit with its unit, already formatted.
  ///
  /// In en, this message translates to:
  /// **'Max capped at the order limit of {amount}.'**
  String liveOrderLimitCappedMax(String amount);

  /// Real mode sell screen: after tapping a quick percent such as 75%, the amount was lowered to the per-order limit. {percent} is the chosen percent, already formatted. {amount} is the limit with its unit.
  ///
  /// In en, this message translates to:
  /// **'{percent} capped at the order limit of {amount}.'**
  String liveOrderLimitCappedPercent(String percent, String amount);

  /// Real mode order screen, main button label while the app gets the price and fees. Keep under 30 characters.
  ///
  /// In en, this message translates to:
  /// **'Checking price and fees…'**
  String get liveOrderCheckingPrice;

  /// Real mode order screen, main button that shows the buy's price and fees before confirming. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Review buy'**
  String get liveOrderReviewBuy;

  /// Real mode order screen, main button that shows the sale's price and fees before confirming. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Review sell'**
  String get liveOrderReviewSell;

  /// Real mode order review, heading above the buy's price and fees.
  ///
  /// In en, this message translates to:
  /// **'Review your buy'**
  String get liveOrderReviewBuyTitle;

  /// Real mode order review, heading above the sale's price and fees.
  ///
  /// In en, this message translates to:
  /// **'Review your sell'**
  String get liveOrderReviewSellTitle;

  /// Real mode order review, row label: about how much the person gets. Keep the ≈ sign (approximately).
  ///
  /// In en, this message translates to:
  /// **'You receive ≈'**
  String get liveOrderYouReceive;

  /// Real mode order review, row label: the least the person can get if the price moves (slippage protection).
  ///
  /// In en, this message translates to:
  /// **'Minimum received'**
  String get liveOrderMinimumReceived;

  /// Real mode order review, row label: Solana network fees plus the cost of opening a token account, paid in SOL.
  ///
  /// In en, this message translates to:
  /// **'Network + account fees'**
  String get liveOrderNetworkFees;

  /// Real mode order review, row label: the percentage fee charged on the exchange of USDC for the token or back.
  ///
  /// In en, this message translates to:
  /// **'Swap fee'**
  String get liveOrderSwapFee;

  /// Real mode order review, row label for how the price was set.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get liveOrderPrice;

  /// Real mode order review, value of the Price row: the price is fixed by a market maker (a firm that offers prices) rather than moving with a market.
  ///
  /// In en, this message translates to:
  /// **'Fixed quote from a market maker'**
  String get liveOrderFixedQuote;

  /// Real mode order review, row label: the firm that creates the token, such as xStocks or Ondo.
  ///
  /// In en, this message translates to:
  /// **'Issuer'**
  String get liveOrderIssuer;

  /// Real mode order review, row label: a percentage the token's issuer charges on every transfer.
  ///
  /// In en, this message translates to:
  /// **'Issuer fee'**
  String get liveOrderIssuerFee;

  /// Real mode order review, main button that sends the buy with real money. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Confirm buy'**
  String get liveOrderConfirmBuy;

  /// Real mode order review, main button that sends the sale. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Confirm sell'**
  String get liveOrderConfirmSell;

  /// Real mode order review, button that goes back to change the amount. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Edit amount'**
  String get liveOrderEditAmount;

  /// Real mode order result, title when the buy or sale went through.
  ///
  /// In en, this message translates to:
  /// **'Trade confirmed'**
  String get liveOrderTradeConfirmed;

  /// Real mode order result, title while the network confirms the buy or sale.
  ///
  /// In en, this message translates to:
  /// **'Confirming your trade'**
  String get liveOrderConfirmingTrade;

  /// Real mode order result, title when the price shown for the order is too old to use.
  ///
  /// In en, this message translates to:
  /// **'Quote expired'**
  String get liveOrderQuoteExpired;

  /// Real mode order result, title when the buy or sale did not go through.
  ///
  /// In en, this message translates to:
  /// **'Trade didn’t complete'**
  String get liveOrderTradeIncomplete;

  /// Real mode order result, text under 'Trade confirmed'. Solana is the blockchain, never translated.
  ///
  /// In en, this message translates to:
  /// **'Your order is confirmed on Solana.'**
  String get liveOrderConfirmedBody;

  /// Real mode order result, text under 'Confirming your trade': the screen can be closed and opened later to see the result.
  ///
  /// In en, this message translates to:
  /// **'You can close this. Reopen the trade to check its status.'**
  String get liveOrderPendingBody;

  /// Real mode order result, text under 'Quote expired'.
  ///
  /// In en, this message translates to:
  /// **'Get a fresh price to continue.'**
  String get liveOrderExpiredBody;

  /// Real mode order result, text under 'Trade didn't complete': the order did not go through.
  ///
  /// In en, this message translates to:
  /// **'Your order wasn’t filled.'**
  String get liveOrderFailedBody;

  /// Real mode order result, link that opens the wallet's activity on a blockchain explorer website. Keep the ↗ arrow.
  ///
  /// In en, this message translates to:
  /// **'View wallet activity ↗'**
  String get liveOrderViewWalletActivity;

  /// Real mode order result, link that opens the transaction on a blockchain explorer website. Keep the ↗ arrow.
  ///
  /// In en, this message translates to:
  /// **'View transaction ↗'**
  String get liveOrderViewTransaction;

  /// Real mode order result, button that asks for a new price after the old one expired. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Get fresh price'**
  String get liveOrderGetFreshPrice;

  /// Real mode order screen, issuer card: the token is not offered to people living in these countries. {regions} is a comma-separated list of country names from the server (in English).
  ///
  /// In en, this message translates to:
  /// **'Not for residents of {regions}'**
  String liveOrderIssuerExcluded(String regions);

  /// Real mode order screen, issuer card: warning that the token's issuer charges a percentage on every buy and every sale. {percent} is already formatted.
  ///
  /// In en, this message translates to:
  /// **'Issuer fee: {percent} on every buy and sell'**
  String liveOrderIssuerFeeNote(String percent);

  /// Real mode order screen, issuer card: the statement next to a checkbox the person ticks to confirm they may buy this token under the issuer's terms. First person.
  ///
  /// In en, this message translates to:
  /// **'I’m eligible under the issuer’s terms.'**
  String get liveOrderLegacyAttestation;

  /// Real mode order screen, issuer card: link that opens the issuer's terms web page. Keep the ↗ arrow. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Issuer terms ↗'**
  String get liveOrderIssuerTerms;

  /// Real mode trade history, status of a trade the network is still confirming. Short label on a row.
  ///
  /// In en, this message translates to:
  /// **'Confirming'**
  String get liveHistoryStatusConfirming;

  /// Real mode trade history, status of a trade (a buy or sale) that went through. Short label on a row.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get liveHistoryStatusConfirmed;

  /// Real mode trade history, status of a trade that did not go through. Short label on a row.
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get liveHistoryStatusFailed;

  /// Real mode trade history, status of a trade whose price ran out of time before it was sent. Short label on a row.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get liveHistoryStatusExpired;

  /// Real mode trade history, message when the sign-in expired or the account changed.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to see your trades.'**
  String get liveHistoryErrorSignIn;

  /// Real mode trade history, message when the list of trades could not load.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load your trades. Try again.'**
  String get liveHistoryErrorLoad;

  /// Real mode trade history, message when older trades could not load.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load more trades. Try again.'**
  String get liveHistoryErrorLoadMore;

  /// Real mode trade history, message when the stock page for a trade could not open.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open this stock. Try again.'**
  String get liveHistoryErrorOpenStock;

  /// Real mode trade history, top bar title. A trade is one buy or sale with real money.
  ///
  /// In en, this message translates to:
  /// **'Your trades'**
  String get liveHistoryTitle;

  /// Real mode trade history, title when the person has no trades yet.
  ///
  /// In en, this message translates to:
  /// **'Your first trade starts here'**
  String get liveHistoryEmptyTitle;

  /// Real mode trade history, text under the empty title.
  ///
  /// In en, this message translates to:
  /// **'Your orders will appear here.'**
  String get liveHistoryEmptyBody;

  /// Real mode trade history, button at the bottom that loads older trades. Keep short.
  ///
  /// In en, this message translates to:
  /// **'More trades'**
  String get liveHistoryMore;

  /// Real mode trade history, row title for a past buy. Here 'Buy' is a noun (a purchase of the token), not a command. {symbol} is the token symbol, never translated.
  ///
  /// In en, this message translates to:
  /// **'Buy {symbol}'**
  String liveHistoryRowBuy(String symbol);

  /// Real mode trade history, row title for a past sale. Here 'Sell' is a noun (a sale of the token), not a command. {symbol} is the token symbol, never translated.
  ///
  /// In en, this message translates to:
  /// **'Sell {symbol}'**
  String liveHistoryRowSell(String symbol);

  /// Real mode trade history, expanded buy: label above the amount the person paid.
  ///
  /// In en, this message translates to:
  /// **'You paid'**
  String get liveHistoryYouPaid;

  /// Real mode trade history, expanded sale: label above the amount of the token the person sold.
  ///
  /// In en, this message translates to:
  /// **'You sold'**
  String get liveHistoryYouSold;

  /// Real mode trade history, expanded trade: label above what the person got.
  ///
  /// In en, this message translates to:
  /// **'You received'**
  String get liveHistoryYouReceived;

  /// Real mode trade history, small note: the amounts shown are the real ones recorded on the blockchain.
  ///
  /// In en, this message translates to:
  /// **'Final amounts from the confirmed transaction.'**
  String get liveHistoryFinalAmounts;

  /// Real mode trade history, expanded trade: label above the amount the price quote said the person would get.
  ///
  /// In en, this message translates to:
  /// **'Quoted output'**
  String get liveHistoryQuotedOutput;

  /// Real mode trade history, expanded trade: label above the least the person could get if the price moved.
  ///
  /// In en, this message translates to:
  /// **'Minimum output'**
  String get liveHistoryMinimumOutput;

  /// Real mode trade history, small note: these amounts are estimates from the order; the blockchain transaction has the real ones.
  ///
  /// In en, this message translates to:
  /// **'Order estimates. See the transaction for the final amounts.'**
  String get liveHistoryEstimates;

  /// Real mode trade history, button that opens the trade's transaction on a blockchain explorer website. Keep short.
  ///
  /// In en, this message translates to:
  /// **'View transaction'**
  String get liveHistoryViewTransaction;

  /// Real mode trade history, button that opens the traded stock's page. 'Open' is a verb. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Open stock'**
  String get liveHistoryOpenStock;

  /// Real mode, stock order screen and token picker: short status line for a tokenized stock whose market never closes. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Open 24/7'**
  String get liveTradingOpenAlways;

  /// Real mode: short status line for a tokenized stock that trades now and also trades on weekends.
  ///
  /// In en, this message translates to:
  /// **'Open now, including weekends'**
  String get liveTradingOpenWeekends;

  /// Real mode: short status line for a tokenized stock whose market is open right now. 'Open' describes the market, not a verb.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get liveTradingOpenNow;

  /// Real mode: status line when the company that issues the token (the issuer) has paused trading in it.
  ///
  /// In en, this message translates to:
  /// **'Paused by the issuer'**
  String get liveTradingPausedByIssuer;

  /// Real mode: status line when the market has paused trading in a tokenized stock and no restart time is known.
  ///
  /// In en, this message translates to:
  /// **'Paused by the market'**
  String get liveTradingPausedByMarket;

  /// Real mode: status line when the market paused trading in a tokenized stock. {time} says when it restarts and already includes any 'at' or 'on' your language needs (see liveTradingTimeToday). Keep the ' · ' separator.
  ///
  /// In en, this message translates to:
  /// **'Paused · resumes {time}'**
  String liveTradingPausedResumes(String time);

  /// Real mode: status line during a short break between US trading sessions, when no restart time is known.
  ///
  /// In en, this message translates to:
  /// **'Short pause'**
  String get liveTradingShortPause;

  /// Real mode: status line during a short break between US trading sessions. {time} says when trading restarts and already includes any 'at' or 'on' your language needs. Keep the ' · ' separator.
  ///
  /// In en, this message translates to:
  /// **'Short pause · resumes {time}'**
  String liveTradingShortPauseResumes(String time);

  /// Real mode: status line when a tokenized stock's market is closed and no opening time is known. Describes the market.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get liveTradingClosed;

  /// Real mode: status line when a tokenized stock's market is closed. Also shown on the disabled order button. {time} says when it opens and already includes any 'at' or 'on' your language needs. Keep the ' · ' separator.
  ///
  /// In en, this message translates to:
  /// **'Closed · opens {time}'**
  String liveTradingClosedOpens(String time);

  /// Real mode, order screen: note under the market status for a tokenized stock that trades at almost any hour, stopping briefly between US market sessions.
  ///
  /// In en, this message translates to:
  /// **'Trades around the clock, with short pauses between US sessions.'**
  String get liveTradingHoursAroundClock;

  /// Real mode, order screen: note under the market status for a tokenized stock that trades all day on weekdays. 'US Eastern' is the US Eastern time zone (New York).
  ///
  /// In en, this message translates to:
  /// **'Trades 24 hours a day, Sunday evening to Friday evening (US Eastern).'**
  String get liveTradingHoursWeekdays;

  /// Real mode, order screen: note for a tokenized stock that trades only during regular US stock market hours, Monday to Friday, 9:30 to 16:00 New York time. Write the two times the way your language writes times.
  ///
  /// In en, this message translates to:
  /// **'Trades during US market hours only, 9:30 AM to 4 PM Eastern on weekdays.'**
  String get liveTradingHoursRegular;

  /// Real mode, order screen: note for a tokenized stock that trades only during some US stock market sessions.
  ///
  /// In en, this message translates to:
  /// **'Trades during US market sessions only.'**
  String get liveTradingHoursSessions;

  /// When a closed or paused tokenized stock opens again, later today. It fills {time} in 'Closed · opens {time}', 'resumes {time}' and 'It opens {time}', so it follows a verb like 'opens'. Add the 'at' your language uses there. {clock} is the local time, already formatted for your language. {hour} is the hour that clock shows (1 for 1:05): use the plural branches only if a word changes for one o'clock (Spanish 'a la 1:05' but 'a las 9:31'), otherwise keep the single 'other' branch.
  ///
  /// In en, this message translates to:
  /// **'{hour, plural, other{{clock}}}'**
  String liveTradingTimeToday(int hour, String clock);

  /// When a closed tokenized stock opens again, tomorrow. Follows a verb like 'opens' (see liveTradingTimeToday). {clock} is the local time, already formatted. {hour} is the hour that clock shows, for languages whose words change at one o'clock.
  ///
  /// In en, this message translates to:
  /// **'{hour, plural, other{tomorrow {clock}}}'**
  String liveTradingTimeTomorrow(int hour, String clock);

  /// When a closed tokenized stock opens again, later this week. Follows a verb like 'opens' (see liveTradingTimeToday). {weekday} is the short day name, already formatted ('Wed', 'mié.', 'qua.', 'mer.'). {clock} is the local time. {hour} is the hour that clock shows, for languages whose words change at one o'clock.
  ///
  /// In en, this message translates to:
  /// **'{hour, plural, other{{weekday} {clock}}}'**
  String liveTradingTimeWeekday(int hour, String weekday, String clock);

  /// When a closed tokenized stock opens again, a week or more away. Follows a verb like 'opens' (see liveTradingTimeToday). {date} is a short month and day, already formatted ('Oct 12', '12 oct.'). {clock} is the local time. {hour} is the hour that clock shows, for languages whose words change at one o'clock.
  ///
  /// In en, this message translates to:
  /// **'{hour, plural, other{{date}, {clock}}}'**
  String liveTradingTimeDate(int hour, String date, String clock);

  /// Real mode, token picker on a stock page: why one company's token cannot be traded. The issuer is the firm that creates the token; Trimmy does not offer that firm's tokens.
  ///
  /// In en, this message translates to:
  /// **'This issuer is not offered in Trimmy.'**
  String get liveTradingReasonIssuerNotOffered;

  /// Real mode, token picker on a stock page: why a token cannot be bought or sold in Trimmy for now.
  ///
  /// In en, this message translates to:
  /// **'Not available to trade in Trimmy yet.'**
  String get liveTradingReasonNotYet;

  /// Real mode, token picker: why a token cannot be traded. Trimmy could not verify the firm that created the token.
  ///
  /// In en, this message translates to:
  /// **'Trimmy could not confirm who issued this token.'**
  String get liveTradingReasonIdentity;

  /// Real mode, token picker: why a token cannot be traded. The firm that created it limits it in ways Trimmy cannot accept.
  ///
  /// In en, this message translates to:
  /// **'The issuer has restrictions on this token that Trimmy cannot accept.'**
  String get liveTradingReasonRestricted;

  /// Real mode, token picker: why a token cannot be traded. Too few people trade it, so prices could jump.
  ///
  /// In en, this message translates to:
  /// **'Too little trading to buy and sell it safely.'**
  String get liveTradingReasonLowLiquidity;

  /// Real mode, token picker: why a token cannot be traded. A route is the path an order takes through markets to be filled; none passed Trimmy's checks.
  ///
  /// In en, this message translates to:
  /// **'No order route passed Trimmy’s safety checks.'**
  String get liveTradingReasonNoRoute;

  /// Real mode, token picker: why a token cannot be traded. The token's price is far from the price of the real company share it tracks.
  ///
  /// In en, this message translates to:
  /// **'Its price is too far from the real share price.'**
  String get liveTradingReasonPriceOff;

  /// Real mode, token picker: why a token cannot be traded right now. Trimmy is reviewing it.
  ///
  /// In en, this message translates to:
  /// **'Paused while Trimmy checks this token.'**
  String get liveTradingReasonHeldBack;

  /// Real mode, token picker: why a token cannot be traded. Trimmy has not reviewed it yet.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet.'**
  String get liveTradingReasonNotChecked;

  /// Real mode, token picker: why a token cannot be traded yet. Its market is closed; once it opens Trimmy reviews the token. {time} says when, and already includes any 'at' or 'on' your language needs (see liveTradingTimeToday).
  ///
  /// In en, this message translates to:
  /// **'Its market is closed. It opens {time}, then Trimmy checks it.'**
  String liveTradingReasonClosedOpens(String time);

  /// Real mode, token picker: why a token cannot be traded right now. It only trades while US stock markets are open.
  ///
  /// In en, this message translates to:
  /// **'Trades only while US markets are open.'**
  String get liveTradingReasonUsHours;

  /// Real mode, token picker: why a token cannot be traded yet. Its market just opened and Trimmy is reviewing it first.
  ///
  /// In en, this message translates to:
  /// **'Its market is open. Trimmy is checking it before you can trade.'**
  String get liveTradingReasonAwaitingReview;

  /// Real mode, token picker: why a token cannot be traded right now. A market maker is a firm that offers prices to buy and sell; none is offering a price now.
  ///
  /// In en, this message translates to:
  /// **'No market maker is quoting it right now.'**
  String get liveTradingReasonNoMarketMaker;

  /// Real mode, token picker: general reason a token cannot be bought or sold in Trimmy.
  ///
  /// In en, this message translates to:
  /// **'Not available to trade in Trimmy.'**
  String get liveTradingReasonUnavailable;

  /// Real mode, token picker on a stock page: stands in for the issuer's name when it is not known, before ' · ' and the token symbol (for example 'Other issuer · NVDA'). Keep short.
  ///
  /// In en, this message translates to:
  /// **'Other issuer'**
  String get liveTradingOtherIssuer;

  /// Real mode, Desk holdings list: title while the person's wallet is being checked.
  ///
  /// In en, this message translates to:
  /// **'Checking your wallet…'**
  String get holdingsCheckingWallet;

  /// Real mode, Desk holdings list: title when the person has no wallet yet, above an 'Add money' button.
  ///
  /// In en, this message translates to:
  /// **'Your wallet starts here'**
  String get holdingsWalletStarts;

  /// Real mode, Desk holdings list: title when the wallet holds no tokenized stocks.
  ///
  /// In en, this message translates to:
  /// **'No stocks yet'**
  String get holdingsEmptyTitle;

  /// Real mode, Desk holdings list: text under 'No stocks yet', above an 'Explore stocks' button.
  ///
  /// In en, this message translates to:
  /// **'Your first stock starts here.'**
  String get holdingsEmptyBody;

  /// Real mode, Desk holdings list: button that opens the Market to find a stock. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Explore stocks'**
  String get holdingsExplore;

  /// Desk wallet card, action button under the card that opens a quick stock purchase. Shares a row with up to two other buttons; keep very short (under 12 characters).
  ///
  /// In en, this message translates to:
  /// **'Fast buy'**
  String get walletFastBuy;

  /// Desk wallet card in Real mode, action button that sends money out of the wallet. Verb. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get walletSend;

  /// Desk wallet card, label above the big amount: money not invested in stocks.
  ///
  /// In en, this message translates to:
  /// **'Cash balance'**
  String get walletCashBalance;

  /// Desk wallet card in Practice mode, label above the big amount: practice cash plus the value of every position.
  ///
  /// In en, this message translates to:
  /// **'Account balance'**
  String get walletAccountBalance;

  /// Desk wallet card in Practice mode, label above the big amount when some positions have no price, so the total covers only what has a price.
  ///
  /// In en, this message translates to:
  /// **'Known value'**
  String get walletKnownValue;

  /// Screen reader label for the mode button on the Real wallet card: switches to Practice mode (English calls it Paper), trading with practice money.
  ///
  /// In en, this message translates to:
  /// **'Switch to paper mode'**
  String get walletSwitchToPaper;

  /// Screen reader label for the mode button on the Practice wallet card: switches to Real mode, trading with real money.
  ///
  /// In en, this message translates to:
  /// **'Switch to real money mode'**
  String get walletSwitchToReal;

  /// Desk wallet card in Real mode, small note under the cash amount: the cash is USDC (a US dollar token) ready to use. USDC is never translated.
  ///
  /// In en, this message translates to:
  /// **'USDC available'**
  String get walletUsdcAvailable;

  /// Desk wallet card in Practice mode, small note under the balance: how many stocks the person holds. A position is one stock you own. {countText} is {count} already formatted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{countText} position} other{{countText} positions}}'**
  String walletPositions(int count, String countText);

  /// Desk wallet card in Practice mode, small note when a few positions have no price right now.
  ///
  /// In en, this message translates to:
  /// **'Some prices unavailable'**
  String get walletSomePricesUnavailable;

  /// Desk wallet card in Practice mode, small note when no position has a price right now.
  ///
  /// In en, this message translates to:
  /// **'Position prices unavailable'**
  String get walletPositionPricesUnavailable;

  /// Desk wallet card in Real mode, small note while the SOL balance loads. SOL is Solana's coin, never translated.
  ///
  /// In en, this message translates to:
  /// **'Checking SOL…'**
  String get walletCheckingSol;

  /// Desk wallet card in Real mode, small note: how much SOL (Solana's coin, used to pay network fees) the wallet holds. {amount} is already formatted.
  ///
  /// In en, this message translates to:
  /// **'{amount} SOL for fees'**
  String walletSolForFees(String amount);

  /// Screen reader label for the two small coin logos on the Real wallet card. USDC and SOL are never translated.
  ///
  /// In en, this message translates to:
  /// **'USDC and SOL'**
  String get walletCashMarks;

  /// Error on the Add money sheet when creating the player's Solana wallet failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t create your wallet. Try again.'**
  String get fundCreateWalletFailed;

  /// Shown on the Add money sheet when the server cannot tell which wallet belongs to the account, so no deposit address is shown.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t confirm your wallet.'**
  String get fundWalletUnconfirmed;

  /// Shown on the Add money sheet when the phone has no internet connection.
  ///
  /// In en, this message translates to:
  /// **'You’re offline. Reconnect to load your wallet.'**
  String get fundWalletOffline;

  /// Shown on the Add money sheet when the wallet could not be loaded. A 'Try again' button follows.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load your wallet.'**
  String get fundWalletLoadFailed;

  /// Tab on the Add money sheet: pay with regular money by card, Apple Pay or Google Pay (as opposed to the Crypto tab, which shows a wallet address to transfer crypto to). Keep very short: two tabs share one row.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get fundTabCash;

  /// Tab on the Add money sheet: transfer USDC or SOL from another crypto wallet to the player's Solana address. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Crypto'**
  String get fundTabCrypto;

  /// Title on the Add money sheet when the player has no wallet yet, above a 'Create wallet' button.
  ///
  /// In en, this message translates to:
  /// **'A wallet for your money'**
  String get fundWalletMissingTitle;

  /// Busy label of the 'Create wallet' button while the wallet is being created.
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get fundCreatingWallet;

  /// Button on the Add money sheet that creates the player's Solana wallet. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Create wallet'**
  String get fundCreateWallet;

  /// Screen reader label of the QR code that holds the player's deposit address on the Solana network. {address} is the wallet address, never translated.
  ///
  /// In en, this message translates to:
  /// **'Solana deposit address {address}'**
  String fundDepositQrLabel(String address);

  /// Warning under the deposit address: other tokens or networks would be lost. USDC, SOL and Solana are never translated.
  ///
  /// In en, this message translates to:
  /// **'Send only USDC or SOL to this account on the Solana network.'**
  String get fundSendOnlyWarning;

  /// Label of the copy button for two seconds after the deposit address was copied. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get fundAddressCopied;

  /// Button that copies the player's Solana deposit address. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get fundCopyAddress;

  /// Error on the guest desk recovery page when starting a new guest desk failed, after the guest session expired. The old desk is still kept.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t start again. Your expired desk is still preserved.'**
  String get guestDeskStartAgainFailedExpired;

  /// Error on the guest desk recovery page when starting a new guest desk failed, after the guest session ended. The old desk is still kept.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t start again. Your old desk is still preserved.'**
  String get guestDeskStartAgainFailed;

  /// Title of the confirmation step before replacing the old guest desk (playing without an account) with a brand new one. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Start fresh?'**
  String get guestDeskStartFreshTitle;

  /// Title of the page shown when the player's guest session (playing without an account) expired and can no longer be used.
  ///
  /// In en, this message translates to:
  /// **'Guest session expired'**
  String get guestDeskExpiredTitle;

  /// Title of the page shown when the player's guest session (playing without an account) was ended by the server and this phone can no longer open it.
  ///
  /// In en, this message translates to:
  /// **'Guest session ended'**
  String get guestDeskEndedTitle;

  /// Warning on the confirmation step before starting a new guest desk: this phone loses access to the old desk for good.
  ///
  /// In en, this message translates to:
  /// **'This removes this phone’s access to your old desk. You can’t undo it.'**
  String get guestDeskStartFreshMessage;

  /// Body of the 'Guest session expired' page. The old guest desk's records are kept, but it can no longer buy or sell, nor be moved into an account.
  ///
  /// In en, this message translates to:
  /// **'Your guest records are preserved. This desk can no longer trade or be saved to an account.'**
  String get guestDeskExpiredMessage;

  /// Body of the 'Guest session ended' page.
  ///
  /// In en, this message translates to:
  /// **'Your guest records are preserved, but this phone can no longer open the desk.'**
  String get guestDeskEndedMessage;

  /// Card on the confirmation step before starting a new guest desk: the practice money balance, the stocks held and the trade history stay with the old desk.
  ///
  /// In en, this message translates to:
  /// **'Your balance, positions and history won’t move to the new desk.'**
  String get guestDeskStartFreshDetail;

  /// Card on the guest session expired or ended page, suggesting to sign in to an existing account.
  ///
  /// In en, this message translates to:
  /// **'Sign in to open your saved account. Your guest desk stays untouched.'**
  String get guestDeskSignInDetail;

  /// Busy label on the 'Start a new desk' button while the new guest desk is being opened.
  ///
  /// In en, this message translates to:
  /// **'Opening…'**
  String get guestDeskOpening;

  /// Main button on the confirmation step: replace the old guest desk with a new one. Full-width button.
  ///
  /// In en, this message translates to:
  /// **'Start a new desk'**
  String get guestDeskStartNewConfirm;

  /// Text button on the confirmation step: go back without starting a new desk.
  ///
  /// In en, this message translates to:
  /// **'Keep this desk'**
  String get guestDeskKeep;

  /// Text button on the guest session expired or ended page: start over without an account. Opens a confirmation step first.
  ///
  /// In en, this message translates to:
  /// **'Start a new guest desk'**
  String get guestDeskStartNewGuest;

  /// Title of the page shown after a guest signs in to an account that already existed: the account's own desk opens. Avoid a gendered welcome (no 'bienvenido', 'bem-vindo').
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get guestDeskPreservedTitle;

  /// Line under 'Welcome back': the account's saved trades (buys and sells) and game progress have loaded.
  ///
  /// In en, this message translates to:
  /// **'Your saved trades and progress are ready.'**
  String get guestDeskPreservedMessage;

  /// Card on the 'Welcome back' page when the guest session had expired: the old guest desk is kept apart, cannot trade anymore and cannot be merged into the account.
  ///
  /// In en, this message translates to:
  /// **'Your expired guest desk is preserved separately. It can no longer trade or merge.'**
  String get guestDeskPreservedExpiredDetail;

  /// Card on the 'Welcome back' page: trades made as a guest are not merged into the account; signing out goes back to the guest desk.
  ///
  /// In en, this message translates to:
  /// **'Your guest trades stay separate. Sign out to return to that desk.'**
  String get guestDeskPreservedDetail;

  /// Main button on the 'Welcome back' page that opens the account's desk (the home tab). Full-width button.
  ///
  /// In en, this message translates to:
  /// **'Go to my desk'**
  String get guestDeskGoToDesk;

  /// Error in the card tab of the Add money sheet when paying by card is switched off. The player can still send crypto from another wallet.
  ///
  /// In en, this message translates to:
  /// **'Card deposits aren’t available yet. You can still transfer from another wallet.'**
  String get onrampErrorNotEnabled;

  /// Error in the card payment form when the account session ended.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to continue.'**
  String get onrampErrorSignIn;

  /// Error when a card payment (checkout) is too old to be tracked by the app. Support must check it; if it was paid, the wallet balance still updates.
  ///
  /// In en, this message translates to:
  /// **'This checkout needs to be checked with support. Your wallet balance will still update.'**
  String get onrampErrorExpired;

  /// Error in the card payment form when another request is still running.
  ///
  /// In en, this message translates to:
  /// **'Give it a moment, then try again.'**
  String get onrampErrorBusy;

  /// Error under the amount field of the card payment form when the amount is outside the allowed range. {min} and {max} are US dollar amounts already formatted.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount from {min} to {max}.'**
  String onrampErrorAmount(String min, String max);

  /// Error in the card payment form when the wallet is missing or changed since the sheet opened.
  ///
  /// In en, this message translates to:
  /// **'Refresh your wallet before continuing.'**
  String get onrampErrorWalletChanged;

  /// Generic error when the card payment page could not be prepared or opened.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open payment. Try again in a moment.'**
  String get onrampErrorUnavailable;

  /// Generic error in the card payment form when a step failed unexpectedly.
  ///
  /// In en, this message translates to:
  /// **'This step didn’t finish. Try again.'**
  String get onrampErrorStep;

  /// Error under the receipt email field of the card payment form when no valid email was typed.
  ///
  /// In en, this message translates to:
  /// **'Enter an email for your receipt.'**
  String get onrampErrorEmail;

  /// Error while waiting for a card payment: its status could not be read. Warns not to pay twice.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t refresh this deposit. Check again before paying again.'**
  String get onrampErrorRefresh;

  /// Title after a test card payment (in the test environment, no real money) finished.
  ///
  /// In en, this message translates to:
  /// **'Test deposit complete'**
  String get onrampTestDoneTitle;

  /// Title after a real card payment finished and the money reached the wallet. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Money added'**
  String get onrampDoneTitle;

  /// Title when a card payment went through but the money could not be delivered to the wallet.
  ///
  /// In en, this message translates to:
  /// **'Deposit needs attention'**
  String get onrampFailedTitle;

  /// Title while the card payment page is open in the browser and the app waits for it.
  ///
  /// In en, this message translates to:
  /// **'Finish your deposit'**
  String get onrampPendingTitle;

  /// Line after a test card payment finished. USDC, Solana and devnet (Solana's test network) are never translated.
  ///
  /// In en, this message translates to:
  /// **'Test USDC arrived on Solana devnet.'**
  String get onrampTestDoneBody;

  /// Line after a card payment finished. USDC is a US dollar token, never translated.
  ///
  /// In en, this message translates to:
  /// **'Your USDC is in your wallet.'**
  String get onrampDoneBody;

  /// Line when a card payment needs attention. Crossmint is the payment provider. 'Order' is the purchase order of this payment (not a stock order); its ID is shown below.
  ///
  /// In en, this message translates to:
  /// **'Contact Crossmint with this order ID. Don’t pay again.'**
  String get onrampFailedBody;

  /// Line while the card payment page is open in the phone's browser.
  ///
  /// In en, this message translates to:
  /// **'Finish payment in your browser, then return here.'**
  String get onrampPendingBody;

  /// Button that opens the card payment page again in the browser. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Open payment'**
  String get onrampOpenPayment;

  /// Small selectable line under a card payment: the payment provider's purchase order ID (not a stock order). {orderId} is an ID, never translated.
  ///
  /// In en, this message translates to:
  /// **'Order {orderId}'**
  String onrampOrderId(String orderId);

  /// Busy line in the card tab of the Add money sheet while the app checks whether card payment is available.
  ///
  /// In en, this message translates to:
  /// **'Checking payment options…'**
  String get onrampCheckingOptions;

  /// Line in the card tab of the Add money sheet when paying by card is not available.
  ///
  /// In en, this message translates to:
  /// **'Card deposits aren’t available yet.'**
  String get onrampCardUnavailable;

  /// Text button that switches to the Crypto tab to send crypto from another wallet.
  ///
  /// In en, this message translates to:
  /// **'Transfer from a wallet'**
  String get onrampTransferFromWallet;

  /// Small label above the card payment form in the test environment: no real money is charged.
  ///
  /// In en, this message translates to:
  /// **'Test checkout'**
  String get onrampTestCheckout;

  /// Heading of the card payment form listing the ways to pay. Apple Pay and Google Pay are product names, never translated.
  ///
  /// In en, this message translates to:
  /// **'Card, Apple Pay or Google Pay'**
  String get onrampMethods;

  /// Small line under the payment methods heading: which methods can be used is shown on the payment page.
  ///
  /// In en, this message translates to:
  /// **'Available options appear at checkout.'**
  String get onrampMethodsNote;

  /// Heading above the amount field of the card payment form (an amount in US dollars). Keep short.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get onrampAmountLabel;

  /// Label of the field for the email address the payment receipt is sent to.
  ///
  /// In en, this message translates to:
  /// **'Receipt email'**
  String get onrampReceiptEmail;

  /// Line in the card payment form: the money arrives as USDC (a US dollar token) on Solana; fees are shown on the payment page.
  ///
  /// In en, this message translates to:
  /// **'USDC on Solana. Fees shown at checkout.'**
  String get onrampUsdcNote;

  /// Line in the card payment form when the payment provider asks the player to prove they own the wallet by signing a message. Signing moves no money.
  ///
  /// In en, this message translates to:
  /// **'Confirm this wallet is yours. This signs a message, not a payment.'**
  String get onrampConfirmWallet;

  /// Title of an expandable section showing the exact message the player signs to prove they own the wallet.
  ///
  /// In en, this message translates to:
  /// **'Verification message'**
  String get onrampVerificationMessage;

  /// Busy label of the card payment form's main button.
  ///
  /// In en, this message translates to:
  /// **'One moment…'**
  String get onrampOneMoment;

  /// Main button of the card payment form when the wallet must first be verified by signing a message. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Verify & continue'**
  String get onrampVerifyContinue;

  /// Small line under the card payment form naming the payment provider. Crossmint is a company name, never translated.
  ///
  /// In en, this message translates to:
  /// **'Powered by Crossmint'**
  String get onrampPoweredByCrossmint;

  /// Large title on the sign-in page, above the sign-in buttons (email, Apple, Google, X). The 'desk' is the player's trading desk in the game. Keep short: it is a 40pt headline.
  ///
  /// In en, this message translates to:
  /// **'Your desk awaits.'**
  String get signInTitleDeskAwaits;

  /// Large title on the sign-in page when the player's guest session expired and they come back to sign in to their account. Trimmy is the app's name. Keep short: it is a 40pt headline.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Trimmy.'**
  String get signInTitleTrimmy;

  /// Line under the sign-in page title. The same buttons both sign in to an existing account and create a new one.
  ///
  /// In en, this message translates to:
  /// **'Sign in or create your account.'**
  String get signInCaption;

  /// Line under the sign-in page title when the player's guest session (playing without an account) expired. Signing in opens the account's own desk; the old guest desk is kept apart and is not merged.
  ///
  /// In en, this message translates to:
  /// **'Open your account desk. The expired guest desk stays separate.'**
  String get signInCaptionExpired;

  /// Small note on the sign-in page when the guest session expired: closing the sign-in page does not delete the old guest desk.
  ///
  /// In en, this message translates to:
  /// **'Closing sign-in keeps the expired guest desk preserved.'**
  String get signInNoticeExpired;

  /// Error on the sign-in page when the provider signed the player in but Trimmy's server could not connect the account. Reassures that the current desk (practice progress on this phone) is kept.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t connect your account. Your desk is still here.'**
  String get signInErrorConnection;

  /// Same error as signInErrorConnection, shown when the player's guest session expired: the previous (guest) desk is kept.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t connect your account. Your previous desk is preserved.'**
  String get signInErrorConnectionExpired;

  /// Generic error on the sign-in page when a sign-in step failed unexpectedly.
  ///
  /// In en, this message translates to:
  /// **'That did not finish. Try again.'**
  String get signInErrorUnfinished;

  /// Message on the sign-in page after the player closed the Google, Apple or X sign-in window without finishing. Not an error: the desk is kept.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was closed. Your desk is still here.'**
  String get signInClosed;

  /// Same as signInClosed, shown when the player's guest session expired: the previous (guest) desk is kept.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was closed. Your previous desk is preserved.'**
  String get signInClosedExpired;

  /// Error on the email sign-in page when the one-time code from the email was wrong or expired.
  ///
  /// In en, this message translates to:
  /// **'That code did not work. Try again.'**
  String get signInErrorCode;

  /// Shown when signing in cannot work at the moment (the sign-in service is not available). Used on the sign-in page and on the guest desk recovery page.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is unavailable right now.'**
  String get signInUnavailable;

  /// Error under the email field on the sign-in page when what was typed is not a complete email address.
  ///
  /// In en, this message translates to:
  /// **'Enter a full email address.'**
  String get signInErrorEmailInvalid;

  /// Error on the email sign-in page when the one-time sign-in code could not be emailed.
  ///
  /// In en, this message translates to:
  /// **'We could not send the code. Try again.'**
  String get signInErrorSendCode;

  /// Error on the email code page when the code field is empty or not a valid code.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from your email.'**
  String get signInErrorCodeMissing;

  /// Tooltip and screen reader label of the X button that closes the sign-in page.
  ///
  /// In en, this message translates to:
  /// **'Close sign in'**
  String get signInCloseTooltip;

  /// Button and back-arrow tooltip on the email code page: go back and type another email address.
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get signInUseDifferentEmail;

  /// Large title on the account page when sign-in is not available in this app build. Saving the desk means keeping the player's progress in an account. Keep short: it is a 36pt headline.
  ///
  /// In en, this message translates to:
  /// **'Save your desk.'**
  String get signInTitleSaveDesk;

  /// Large title on the page where the player types the sign-in code that was emailed to them. Keep short: it is a 36pt headline.
  ///
  /// In en, this message translates to:
  /// **'Check your email.'**
  String get signInTitleCheckEmail;

  /// Large title on the page where the player types their email address to get a sign-in code. Keep short: it is a 36pt headline.
  ///
  /// In en, this message translates to:
  /// **'Your email.'**
  String get signInTitleYourEmail;

  /// Line under the title on the account page when sign-in is unavailable and the guest session expired: the old guest desk is kept apart.
  ///
  /// In en, this message translates to:
  /// **'The expired guest desk stays separate.'**
  String get signInExpiredDeskSeparate;

  /// Line under the title on the account page when sign-in is unavailable: the player's progress stays saved on this phone only.
  ///
  /// In en, this message translates to:
  /// **'Your desk stays on this phone.'**
  String get signInDeskStaysOnPhone;

  /// Line under the title on the email code page. {email} is the address the code was sent to, never translated.
  ///
  /// In en, this message translates to:
  /// **'We sent a code to {email}.'**
  String signInCodeSentTo(String email);

  /// Line under the title on the email page, before the player types their email address.
  ///
  /// In en, this message translates to:
  /// **'We’ll send you a sign-in code.'**
  String get signInWeWillSendCode;

  /// Explanation on the account page when this version of the app has no sign-in configured (test builds). Progress stays on this phone.
  ///
  /// In en, this message translates to:
  /// **'Account sign-in is not set up in this build. Your desk stays on this phone.'**
  String get signInNotSetUp;

  /// Same as signInNotSetUp, shown when the guest session expired: the old guest desk is kept.
  ///
  /// In en, this message translates to:
  /// **'Account sign-in is not set up in this build. The expired guest desk stays preserved.'**
  String get signInNotSetUpExpired;

  /// Button on the first sign-in page: play without an account, on this phone only. Prefer a gender-neutral phrasing for the player.
  ///
  /// In en, this message translates to:
  /// **'Continue as guest'**
  String get signInContinueAsGuest;

  /// Button on the account page when sign-in is unavailable: close it and keep playing. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get signInLater;

  /// Label of the field where the player types the one-time sign-in code from the email. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get signInCodeLabel;

  /// Label of the email address field on the sign-in page.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get signInEmailLabel;

  /// Button on the email page that emails a one-time sign-in code. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get signInSendCode;

  /// Default large title of the sign-in buttons page, greeting someone who comes back. Avoid a gendered welcome (no 'bienvenido', 'bem-vindo'). Keep short: it is a 40pt headline.
  ///
  /// In en, this message translates to:
  /// **'Welcome back.'**
  String get signInWelcomeBackTitle;

  /// Default line under signInWelcomeBackTitle. 'Move' is a move in the game (the player's next trade or decision).
  ///
  /// In en, this message translates to:
  /// **'Your next move is waiting.'**
  String get signInWelcomeBackCaption;

  /// Small all-caps word between two divider lines, between the email button and the Apple, Google and X buttons. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get signInOr;

  /// Main button on the sign-in page: sign in with an email code. Full-width button.
  ///
  /// In en, this message translates to:
  /// **'Continue with email'**
  String get signInContinueWithEmail;

  /// Screen reader value read after the email button's label while sign-in is connecting.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get signInBusyValue;

  /// Screen reader label of a round sign-in button. {provider} is the sign-in service's name, never translated: Apple, Google or X.
  ///
  /// In en, this message translates to:
  /// **'Continue with {provider}'**
  String signInContinueWithProvider(String provider);

  /// Title of a sheet on the Career map (a city street of workdays) when you tap a day that has not been written yet.
  ///
  /// In en, this message translates to:
  /// **'The next neighbourhood'**
  String get careerWorldNextNeighbourhood;

  /// Text of the sheet on the Career map when you tap a day that has not been written yet.
  ///
  /// In en, this message translates to:
  /// **'More assignments are on the way.'**
  String get careerWorldMoreOnTheWay;

  /// Line in the sheet on the Career map when you tap a locked workday: finish the previous workday first. {day} is the previous workday's number. 'This desk' means this locked day on the map.
  ///
  /// In en, this message translates to:
  /// **'Complete day {day} to open this desk.'**
  String careerWorldLockedHint(int day);

  /// Loading text on the Career map while your workdays load.
  ///
  /// In en, this message translates to:
  /// **'Opening your week…'**
  String get careerWorldLoading;

  /// Error on the Career map when your workdays could not be loaded. A 'Try again' button follows.
  ///
  /// In en, this message translates to:
  /// **'Your assignments couldn’t load.'**
  String get careerWorldLoadFailed;

  /// Small district heading on the Career map (a drawn city street) above the days after the first twenty workdays, which are not written yet.
  ///
  /// In en, this message translates to:
  /// **'Beyond the first month'**
  String get careerWorldBeyondFirstMonth;

  /// Small district heading on the Career map (a drawn city street) above stretches of days that are not written yet.
  ///
  /// In en, this message translates to:
  /// **'The city keeps growing'**
  String get careerWorldCityGrowing;

  /// Small all-caps label above today's workday on the Career map when you have not started it. Keep it in capitals and under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'START HERE'**
  String get careerWorldStartHere;

  /// Small all-caps label above today's workday on the Career map when you already started it. Keep it in capitals and under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE'**
  String get careerWorldContinue;

  /// Grey label under a day on the Career map that has not been written yet. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Coming later'**
  String get careerWorldComingLater;

  /// Small green label under a workday on the Career map that you completed (handed in). Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Filed'**
  String get careerWorldFiled;

  /// Screen reader label of a completed workday on the Career map. {day} is the workday's number.
  ///
  /// In en, this message translates to:
  /// **'Day {day}, filed'**
  String careerWorldDayFiled(int day);

  /// Screen reader label of today's workday on the Career map. {day} is the workday's number.
  ///
  /// In en, this message translates to:
  /// **'Day {day}, current assignment'**
  String careerWorldDayCurrent(int day);

  /// Screen reader label of a workday on the Career map that opens after you finish the earlier ones. {day} is the workday's number.
  ///
  /// In en, this message translates to:
  /// **'Day {day}, locked'**
  String careerWorldDayLocked(int day);

  /// Screen reader label of a day on the Career map that has not been written yet. {day} is the day's number.
  ///
  /// In en, this message translates to:
  /// **'Day {day}, coming later'**
  String careerWorldDayComingLater(int day);

  /// Text button on the Desk tab when today's workday assignment could not load. Tapping it tries again.
  ///
  /// In en, this message translates to:
  /// **'Reload your assignment'**
  String get workdayEntryReload;

  /// Small all-caps line on the Desk tab's card for today's workday assignment. {day} is the workday's number; {speaker} is the name of the colleague who gives the assignment in capitals (SAL, ORACLE, SHARK, WOLF), never translated. Keep it in capitals.
  ///
  /// In en, this message translates to:
  /// **'DAY {day} · {speaker}'**
  String workdayEntryEyebrow(int day, String speaker);

  /// Line under the assignment title on the Desk tab's workday card when you have not started it yet.
  ///
  /// In en, this message translates to:
  /// **'Your next assignment'**
  String get workdayEntryNext;

  /// Line under the assignment title on the Desk tab's workday card when you already started it.
  ///
  /// In en, this message translates to:
  /// **'Continue your assignment'**
  String get workdayEntryContinue;

  /// Section title on the Desk tab (and the History page) above the list of your recent practice trades.
  ///
  /// In en, this message translates to:
  /// **'Your activity'**
  String get deskActivityTitle;

  /// Shown under 'Your activity' on the Desk tab when you have not bought or sold anything yet.
  ///
  /// In en, this message translates to:
  /// **'Your first trade starts the story.'**
  String get deskActivityEmpty;

  /// Title of one row in the Desk tab's activity list: you bought shares of this stock. {symbol} is the stock's ticker symbol, never translated.
  ///
  /// In en, this message translates to:
  /// **'Bought {symbol}'**
  String deskActivityBought(String symbol);

  /// Title of one row in the Desk tab's activity list: you sold shares of this stock. {symbol} is the stock's ticker symbol, never translated.
  ///
  /// In en, this message translates to:
  /// **'Sold {symbol}'**
  String deskActivitySold(String symbol);

  /// Section title on the Desk tab above a preview of public comments other traders shared about stocks.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get deskCommunityTitle;

  /// Row in the Desk tab's Community section for guests. Tapping it opens sign in, then the community comments.
  ///
  /// In en, this message translates to:
  /// **'See what traders are saying'**
  String get deskCommunityPrompt;

  /// Row title in the Desk tab's Community section when the comments could not be loaded. Tapping it opens the community page.
  ///
  /// In en, this message translates to:
  /// **'Community couldn’t load'**
  String get deskCommunityLoadFailed;

  /// Row title in the Desk tab's Community section while the comments are loading.
  ///
  /// In en, this message translates to:
  /// **'Opening community…'**
  String get deskCommunityOpening;

  /// Row title in the Desk tab's Community section when nobody has posted yet. Tapping it opens the community page.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation'**
  String get deskCommunityStart;

  /// Subtitle under the Community row on the Desk tab, explaining what the community page holds.
  ///
  /// In en, this message translates to:
  /// **'Public comments from other traders.'**
  String get deskCommunitySubtitle;

  /// Title of a community comment preview on the Desk tab: who posted it and which stock it is about. {handle} is the person's username, never translated (the @ stays). {cashtag} is the stock's symbol with a dollar sign in front, never translated.
  ///
  /// In en, this message translates to:
  /// **'@{handle} on {cashtag}'**
  String deskCommunityPostByHandle(String handle, String cashtag);

  /// Title of a community comment preview on the Desk tab when the author has no username: 'a trader' commented about this stock. {cashtag} is the stock's symbol with a dollar sign in front, never translated.
  ///
  /// In en, this message translates to:
  /// **'A trader on {cashtag}'**
  String deskCommunityPostByTrader(String cashtag);

  /// Large title at the top of the Desk tab (the home tab with your balance and stocks). Keep short.
  ///
  /// In en, this message translates to:
  /// **'Your desk'**
  String get deskTitle;

  /// Tooltip and screen reader label of the bell button at the top of the Desk tab. It opens your notifications (replies and news from the community).
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get deskUpdatesTooltip;

  /// Screen reader label of the round avatar button at the top right of the Desk tab. It opens your Profile.
  ///
  /// In en, this message translates to:
  /// **'Open profile'**
  String get deskOpenProfile;

  /// Screen reader label of the trader character avatar picture at the top right of the Desk tab. {name} is the chosen trader character's name.
  ///
  /// In en, this message translates to:
  /// **'{name} profile picture'**
  String deskPersonaPicture(String name);

  /// Small label on the Desk tab shown right AFTER a separate bold number of days in a row you showed up (the streak), as in '5 day streak'. The number itself is NOT part of this text and always comes first, so write the words that follow the number. {count} is that number of days, only used to pick the singular or plural form.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{day streak}}'**
  String deskStreakLabel(int count);

  /// Section title on the Desk tab above the list of stocks you own.
  ///
  /// In en, this message translates to:
  /// **'Holdings'**
  String get deskHoldingsTitle;

  /// Small text button next to the 'Holdings' title on the Desk tab. Opens the Market to explore more stocks. Verb. Keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get deskExplore;

  /// How many shares of a stock you hold or traded, under the company name in the Desk holdings list and in the activity list. Shares can be fractional. {quantity} is the amount already formatted (for example '0.5', '12' or '1,250'). {count} is the same amount as a number, only used to pick singular or plural. English always says 'shares'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{quantity} shares}}'**
  String deskShareCount(num count, String quantity);

  /// Title of a row on the Desk tab that opens the picker of trader characters (The Wolf, The Oracle, The Shark). Keep short.
  ///
  /// In en, this message translates to:
  /// **'Pick your trader'**
  String get deskPickTraderTitle;

  /// Subtitle under 'Pick your trader' on the Desk tab. 'Desk' is the home tab, where your balance and stocks live.
  ///
  /// In en, this message translates to:
  /// **'Make this desk yours.'**
  String get deskPickTraderSubtitle;

  /// Title of a row on the Desk tab for guests. Tapping it opens sign in so your desk (practice balance, stocks, progress) is kept in an account. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Save your desk'**
  String get deskSaveTitle;

  /// Subtitle under 'Save your desk' on the Desk tab: signing in keeps your desk on your other phones and computers.
  ///
  /// In en, this message translates to:
  /// **'Keep it on your other devices.'**
  String get deskSaveSubtitle;

  /// Small violet label on the Desk tab's career card, shown when your rank has not loaded yet. Normally the rank name (such as 'Rookie') is shown instead.
  ///
  /// In en, this message translates to:
  /// **'Your career'**
  String get deskCareerFallback;

  /// Title of the Desk tab's career card when there is no current career mission to show. Tapping the card opens the Career tab.
  ///
  /// In en, this message translates to:
  /// **'See your next step'**
  String get deskNextStepFallback;

  /// Title of the empty state in the Desk tab's holdings section, when you own no stocks.
  ///
  /// In en, this message translates to:
  /// **'No stocks yet'**
  String get deskEmptyTitle;

  /// Text under 'No stocks yet' on the Desk tab.
  ///
  /// In en, this message translates to:
  /// **'Pick a company to begin.'**
  String get deskEmptyBody;

  /// Text button under 'No stocks yet' on the Desk tab. Opens the Market. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Explore stocks'**
  String get deskEmptyExplore;

  /// Screen reader label for a stock row's value on the Desk when its price is not available right now (the screen shows a dash instead of a number).
  ///
  /// In en, this message translates to:
  /// **'Value unavailable'**
  String get deskHoldingValueUnavailable;

  /// Desk line about market hours while the New York Stock Exchange is open. In Trimmy, tokenized stocks can be traded at any hour, every day; Wall Street (never translated) keeps its own hours. {duration} is the time left, already written with a short-duration message such as '6h' or '2h 30m'.
  ///
  /// In en, this message translates to:
  /// **'Stocks trade here 24/7. Wall Street closes in {duration}.'**
  String clockWallStreetClosesIn(String duration);

  /// Desk line about market hours while the New York Stock Exchange is closed. In Trimmy, tokenized stocks can be traded at any hour, every day; Wall Street (never translated) keeps its own hours. {duration} is the time until it opens, already written with a short-duration message such as '17h 30m' or '2d 16h'.
  ///
  /// In en, this message translates to:
  /// **'Stocks trade here 24/7. Wall Street opens in {duration}.'**
  String clockWallStreetOpensIn(String duration);

  /// Short time span in minutes, used inside 'Wall Street opens in {duration}.'. Use your language's usual short unit. {minutes} is 1 to 59.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, other{{minutes}m}}'**
  String clockDurationMinutes(int minutes);

  /// Short time span in whole hours, used inside 'Wall Street closes in {duration}.'. Use your language's usual short unit. {hours} is 1 to 23.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, other{{hours}h}}'**
  String clockDurationHours(int hours);

  /// Short time span in hours and minutes, used inside 'Wall Street opens in {duration}.'. Use your language's usual short units. {hours} is 1 to 23, {minutes} is 1 to 59.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, other{{hours}h {minutes}m}}'**
  String clockDurationHoursMinutes(int hours, int minutes);

  /// Short time span in whole days, used inside 'Wall Street opens in {duration}.'. Use your language's usual short unit for days. {days} is 1 or more.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, other{{days}d}}'**
  String clockDurationDays(int days);

  /// Short time span in days and hours, used inside 'Wall Street opens in {duration}.' over a weekend or holiday. Use your language's usual short units. {days} is 1 or more, {hours} is 1 to 23.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, other{{days}d {hours}h}}'**
  String clockDurationDaysHours(int days, int hours);

  /// Small status under the optional note field of a workday assignment: your note was saved. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get workdayDraftSaved;

  /// Small status under the optional note field of a workday assignment: saving your note failed for now. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Not saved yet'**
  String get workdayDraftNotSaved;

  /// Title of a dialog when you close a workday assignment while your latest note edits could not be saved.
  ///
  /// In en, this message translates to:
  /// **'Leave this note?'**
  String get workdayLeaveTitle;

  /// Text of the 'Leave this note?' dialog in a workday assignment.
  ///
  /// In en, this message translates to:
  /// **'Your latest edits haven’t saved yet.'**
  String get workdayLeaveBody;

  /// Dialog button: stay in the workday assignment and keep editing the note. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Keep writing'**
  String get workdayLeaveKeepWriting;

  /// Dialog button: close the workday assignment and lose the unsaved note edits.
  ///
  /// In en, this message translates to:
  /// **'Leave without saving'**
  String get workdayLeaveWithoutSaving;

  /// Error under a workday assignment when sending your answer failed for an unexpected reason. You can try again.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save yet. Try again.'**
  String get workdaySaveRetry;

  /// Top bar title of a workday assignment screen: which workday this is, counted from your first day. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Day {day}'**
  String workdayDayTitle(int day);

  /// Tooltip and screen reader label of the close (X) button on a workday assignment screen. Your progress is saved before it closes.
  ///
  /// In en, this message translates to:
  /// **'Save and close'**
  String get workdaySaveAndClose;

  /// Big title after you hand in (file) the last step of a workday assignment. Short and upbeat.
  ///
  /// In en, this message translates to:
  /// **'Filed.'**
  String get workdayFiledTitle;

  /// Reward line on a filed workday assignment: the Trims (Trimmy's points, a proper noun, never translated) you earned. {trims} is the number of points.
  ///
  /// In en, this message translates to:
  /// **'+{trims} Trims'**
  String workdayTrimsEarned(int trims);

  /// Teaser of the next workday under a filed assignment. {day} is the next workday's number; {title} is its title, written by the server.
  ///
  /// In en, this message translates to:
  /// **'Day {day}: {title}'**
  String workdayNextDay(int day, String title);

  /// Small text button in a workday assignment's decision step that shows a hint. Shown after a wrong answer. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Hint?'**
  String get workdayHintShow;

  /// Small text button in a workday assignment's decision step that hides the hint again. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Hide hint'**
  String get workdayHintHide;

  /// Heading of the last step of a workday assignment: you write a short update for your team at the office ('the desk' is the in-game office team, not the app's Desk tab).
  ///
  /// In en, this message translates to:
  /// **'Send the desk an update'**
  String get workdayFileHeading;

  /// Instruction under 'Send the desk an update': pick the two statements that the source document backs up.
  ///
  /// In en, this message translates to:
  /// **'Keep the two facts the source supports.'**
  String get workdayFileBody;

  /// Placeholder text in the optional note field of the last step of a workday assignment.
  ///
  /// In en, this message translates to:
  /// **'Add a note (optional)'**
  String get workdayNoteHint;

  /// Main button after you file a workday assignment: go back to the Career map, drawn as a city street. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Back to the street'**
  String get workdayButtonBack;

  /// Main button in the first step of a workday assignment: submit the details you pinned from the source. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Check the evidence'**
  String get workdayButtonCheckEvidence;

  /// Main button in the second step of a workday assignment: submit your answer to the decision question. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Send your decision'**
  String get workdayButtonSendDecision;

  /// Main button in the last step of a workday assignment: hand in (file) your update to the team. Keep short.
  ///
  /// In en, this message translates to:
  /// **'File update'**
  String get workdayButtonFile;

  /// Screen reader hint on a selectable detail in a workday assignment: double tap to pin (select) this detail.
  ///
  /// In en, this message translates to:
  /// **'Pin detail'**
  String get workdayPinDetail;

  /// Screen reader hint on a pinned (selected) detail in a workday assignment: double tap to unpin it.
  ///
  /// In en, this message translates to:
  /// **'Unpin detail'**
  String get workdayUnpinDetail;

  /// When the next workday (a day of assignments from Sal) unlocks: later today. Shown under the next day's title on the Career map and after you file today's assignment. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Opens soon'**
  String get workdayOpensSoon;

  /// When the next workday (a day of assignments from Sal) unlocks: tomorrow. Shown under the next day's title on the Career map and after you file today's assignment. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Opens tomorrow'**
  String get workdayOpensTomorrow;

  /// When the next workday (a day of assignments from Sal) unlocks: on a day later this week. {weekday} is the full weekday name in your language, as the phone writes it (for example 'Monday', 'lunes', 'segunda-feira', 'lundi'). Keep short.
  ///
  /// In en, this message translates to:
  /// **'Opens {weekday}'**
  String workdayOpensOnWeekday(String weekday);

  /// When the next workday (a day of assignments from Sal) unlocks: on a date a week or more away. {date} is a short numeric day and month, already formatted for your language (for example '30/9' or '30/09'). Keep short.
  ///
  /// In en, this message translates to:
  /// **'Opens {date}'**
  String workdayOpensOnDate(String date);

  /// Error in a workday assignment, under the answer, when the details you pinned from the source document do not back up the update you are preparing for the team. You can try again.
  ///
  /// In en, this message translates to:
  /// **'Check the source again. Those details don’t support this update.'**
  String get workdayErrorCheckEvidence;

  /// Error in a workday assignment when your answer to the decision question is wrong and the server sent no specific feedback. You can try again.
  ///
  /// In en, this message translates to:
  /// **'Take another look at the figures.'**
  String get workdayErrorCheckDecision;

  /// Message in a workday assignment when today's assignment was already completed (for example on another phone) and the next workday has not started yet.
  ///
  /// In en, this message translates to:
  /// **'Today’s assignment is done. Your next workday opens soon.'**
  String get workdayErrorTomorrow;

  /// Message in a workday assignment when there is no work today (for example a weekend). 'The desk' here is the office team you work for in the game, not the app's Desk tab.
  ///
  /// In en, this message translates to:
  /// **'The desk is closed today. Come back on the next workday.'**
  String get workdayErrorClosed;

  /// Message in a workday assignment when the same assignment was changed on another phone or screen; the app reloaded the latest version.
  ///
  /// In en, this message translates to:
  /// **'Your work changed on another screen. We’ve refreshed it.'**
  String get workdayErrorChanged;

  /// Message in a workday assignment when you try to work on a later assignment before handing in (filing) the earlier one.
  ///
  /// In en, this message translates to:
  /// **'File the earlier assignment first.'**
  String get workdayErrorLocked;

  /// Message in a workday assignment when you signed in or out meanwhile. 'Your desk' is the app's home tab (Desk).
  ///
  /// In en, this message translates to:
  /// **'Your account changed. Open your desk again.'**
  String get workdayErrorSession;

  /// Generic error in a workday assignment when saving failed (no connection or a server problem). Your answers are kept on screen so you can try again.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save yet. Your work is still here. Try again.'**
  String get workdayErrorSaveFailed;

  /// Title of a Career mission: make your first buy with practice money. Shown on the Career tab's mission list and on the Desk as the next mission. Keep under 40 characters.
  ///
  /// In en, this message translates to:
  /// **'Buy your first stock'**
  String get careerMissionFirstPaperBuyTitle;

  /// Title of a Career mission: write a short reason (why you bought) on a stock you hold. Shown on the Desk as the next mission. Keep under 40 characters.
  ///
  /// In en, this message translates to:
  /// **'Write your reason'**
  String get careerMissionWriteAReasonTitle;

  /// Title of a Career mission: keep holding a stock through a day when the market falls (a 'red day': red is the color of losses). Shown on the Career tab's mission list and on the Desk. Keep under 40 characters.
  ///
  /// In en, this message translates to:
  /// **'Hold through a red day'**
  String get careerMissionHoldThroughRedDayTitle;

  /// Status message on the Career and Profile tabs when the Career record could not load because the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'Your career is offline. Check your connection and try again.'**
  String get careerErrorOffline;

  /// Status message on the Career and Profile tabs when loading the Career record timed out.
  ///
  /// In en, this message translates to:
  /// **'Your career took too long to open. Try again.'**
  String get careerErrorTimeout;

  /// Status message on the Career and Profile tabs when the sign-in session expired while loading the Career record.
  ///
  /// In en, this message translates to:
  /// **'Your career needs a fresh session. Try again.'**
  String get careerErrorSession;

  /// Status message on the Career and Profile tabs when the server asked the app to slow down refreshing the Career record.
  ///
  /// In en, this message translates to:
  /// **'Your career is refreshing too quickly. Try again shortly.'**
  String get careerErrorRateLimited;

  /// Status message on the Career and Profile tabs when the Career record needs a finished profile first.
  ///
  /// In en, this message translates to:
  /// **'Finish setting up your Trimmy profile, then try again.'**
  String get careerErrorProfileRequired;

  /// Status message on the Career and Profile tabs when the Career record could not load for any other reason.
  ///
  /// In en, this message translates to:
  /// **'Your career is unavailable. Try again.'**
  String get careerErrorUnavailable;

  /// Title of the streak strip on the Career tab: how many days in a row the player has been active. English keeps 'day' singular in every case ('2 day streak').
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{countText} day streak}}'**
  String careerStreakDays(int count, String countText);

  /// Tooltip and screen reader label of a small refresh icon on the streak strip, shown when this week's activity could not load. Loads it again.
  ///
  /// In en, this message translates to:
  /// **'Retry activity'**
  String get careerStreakRetryActivity;

  /// Screen reader label for one day of this week on the streak strip. {date} is the day (English reads the ISO date, other languages the weekday and date in words, already formatted). {status}: active = the player did something that day; upcoming = the day is still ahead; none = no activity that day; unavailable = activity could not load.
  ///
  /// In en, this message translates to:
  /// **'{date}, {status, select, active{active} upcoming{upcoming} none{no activity} unavailable{activity unavailable} other{activity unavailable}}'**
  String careerStreakDaySemantics(String date, String status);

  /// Title of the progress sheet on the Career tab and of the progress card on the Profile tab (rank, Trims and streak).
  ///
  /// In en, this message translates to:
  /// **'Your progress'**
  String get careerYourProgress;

  /// Caption under the player's Trims total on the Career and Profile tabs, explaining that Trims are career points.
  ///
  /// In en, this message translates to:
  /// **'Career points'**
  String get careerPointsLabel;

  /// The player's total Trims on the Career and Profile tabs. Trims are Trimmy's career points, a proper noun: never translate 'Trims'. English always says 'Trims', even for 1; a singular 'Trim' is fine where your language needs it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{countText} Trims}}'**
  String careerTrimsCount(int count, String countText);

  /// Trims just earned, under the 'rank unlocked' message after a promotion on the Career tab. Trims are career points, a proper noun: never translate 'Trims'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{+{countText} Trims}}'**
  String careerTrimsAwarded(int count, String countText);

  /// Title of the Community page, a list of comments other players shared about their trades.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get communityTitle;

  /// Title of the Community page when it shows only new comments from people the player follows (their updates).
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get communityUpdatesTitle;

  /// Tab at the top of the Community page: comments from all players. Keep under 16 characters.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get communityScopeEveryone;

  /// Tab at the top of the Community page: comments only from people the player follows. Keep under 16 characters.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get communityScopeFollowing;

  /// Error line on the Community page when the comments could not load, next to a Retry button.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load activity. Try again.'**
  String get communityLoadFailed;

  /// Error line on the Community page when following, unfollowing or turning updates on or off did not save.
  ///
  /// In en, this message translates to:
  /// **'That change didn’t save. Try again.'**
  String get communitySaveFailed;

  /// Empty state title on the Community updates page: there are no new comments from people the player follows.
  ///
  /// In en, this message translates to:
  /// **'You’re all caught up'**
  String get communityEmptyUpdatesTitle;

  /// Empty state text on the Community updates page.
  ///
  /// In en, this message translates to:
  /// **'New comments from people you follow appear here.'**
  String get communityEmptyUpdatesBody;

  /// Empty state title on the Community page's Following tab when the player follows nobody yet: this is where the people they follow will show up.
  ///
  /// In en, this message translates to:
  /// **'Your people, here'**
  String get communityEmptyFollowingTitle;

  /// Empty state text on the Community page's Following tab. 'Everyone' is the name of the other tab (communityScopeEveryone): use the same word.
  ///
  /// In en, this message translates to:
  /// **'Follow a trader from Everyone.'**
  String get communityEmptyFollowingBody;

  /// Empty state title on the Community page's Everyone tab when nobody has shared a comment yet.
  ///
  /// In en, this message translates to:
  /// **'No shared comments yet'**
  String get communityEmptyEveryoneTitle;

  /// Empty state text on the Community page's Everyone tab.
  ///
  /// In en, this message translates to:
  /// **'Public comments will appear here.'**
  String get communityEmptyEveryoneBody;

  /// Name shown on a Community comment whose author has no @handle. Means 'a trader', a player of Trimmy.
  ///
  /// In en, this message translates to:
  /// **'Trader'**
  String get communityAnonymousTrader;

  /// Small button on a Community comment showing the player already follows its author. Tapping it unfollows. Keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get communityFollowingButton;

  /// Small button on a Community comment that follows its author. Keep the '+' and keep under 12 characters.
  ///
  /// In en, this message translates to:
  /// **'+ Follow'**
  String get communityFollowButton;

  /// Tooltip and screen reader label of the menu button (three dots) on a Community comment.
  ///
  /// In en, this message translates to:
  /// **'Comment options'**
  String get communityCommentOptions;

  /// Menu item on a Community comment: stop getting updates when this person shares a new comment.
  ///
  /// In en, this message translates to:
  /// **'Mute updates'**
  String get communityMuteUpdates;

  /// Menu item on a Community comment: get updates when this person shares a new comment.
  ///
  /// In en, this message translates to:
  /// **'Turn on updates'**
  String get communityTurnOnUpdates;

  /// Menu item on a Community comment: report it to Trimmy as inappropriate. Verb.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get communityReport;

  /// Menu item on a Community comment: block the person who wrote it.
  ///
  /// In en, this message translates to:
  /// **'Block trader'**
  String get communityBlockTrader;

  /// When a Community comment was shared, under it. {date} is the day and month, {time} the time, both already formatted. Keep the middle dot or use your language's usual way to join a date and a time.
  ///
  /// In en, this message translates to:
  /// **'{date} · {time}'**
  String communityPostTime(String date, String time);

  /// Button at the bottom of the Community page that loads older comments.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get communityLoadMore;

  /// Large title at the top of the Career tab, where the player sees their rank, Trims, streak and missions.
  ///
  /// In en, this message translates to:
  /// **'Career'**
  String get floorTitle;

  /// Tooltip and screen reader label of the close (X) button on the 'Your progress' sheet of the Career tab.
  ///
  /// In en, this message translates to:
  /// **'Close progress'**
  String get floorCloseProgress;

  /// Button at the top of the Career tab that opens the player's progress. Shown while the rank name is not known yet (the rank name replaces it later). Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get floorProgressButton;

  /// Title of the empty state on the Career tab when the Career record could not load.
  ///
  /// In en, this message translates to:
  /// **'Career couldn’t load'**
  String get floorCareerLoadFailed;

  /// Button on the Career tab's error state that opens the Market to look at stocks. Keep under 20 characters.
  ///
  /// In en, this message translates to:
  /// **'Browse stocks'**
  String get floorBrowseStocks;

  /// Tooltip shown when the player taps their Trims total on the Career tab. Trims is a proper noun: never translate it.
  ///
  /// In en, this message translates to:
  /// **'Trims are career points. Earn them through activities to move up in rank.'**
  String get floorTrimsTooltip;

  /// Heading of the list of Career missions on the Career tab (for example 'Buy your first stock'). Translate with your Career mission word (misión, missão, objectif), not the word for a workday assignment.
  ///
  /// In en, this message translates to:
  /// **'Career milestones'**
  String get floorMilestonesTitle;

  /// Subtitle under the Career missions heading while the missions are not loaded.
  ///
  /// In en, this message translates to:
  /// **'Your activities'**
  String get floorMilestonesActivities;

  /// Subtitle under the Career missions heading: how many of the missions are done.
  ///
  /// In en, this message translates to:
  /// **'{complete} of {total} complete'**
  String floorMilestonesComplete(String complete, String total);

  /// Status line above the Career missions while the missions and the rank are being brought back in sync.
  ///
  /// In en, this message translates to:
  /// **'Updating your progress…'**
  String get floorMilestonesUpdating;

  /// Title of the empty state where the Career missions should be, when they could not load.
  ///
  /// In en, this message translates to:
  /// **'Activities couldn’t load'**
  String get floorActivitiesLoadFailed;

  /// Title of the Career mission to write a short comment on why you made a trade. Shown in the Career tab's mission list. Keep under 40 characters.
  ///
  /// In en, this message translates to:
  /// **'Comment on your trade'**
  String get floorMissionCommentTitle;

  /// Small status label above a Career mission that is done. Agrees with your Career mission word. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get floorMissionStatusComplete;

  /// Small status label above a Career mission the player can do now. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get floorMissionStatusReady;

  /// Small status label above a Career mission that is not available yet. Agrees with your Career mission word. Keep under 14 characters.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get floorMissionStatusLocked;

  /// Hint under the 'Hold through a red day' Career mission: keep owning a stock through a day when the market falls.
  ///
  /// In en, this message translates to:
  /// **'Keep a stock through a down day.'**
  String get floorMissionHoldHint;

  /// Text button under the 'Comment on your trade' Career mission. Opens writing a comment on a trade. Keep under 24 characters.
  ///
  /// In en, this message translates to:
  /// **'Write a comment'**
  String get floorMissionWriteComment;

  /// Text button under a ready Career mission. Opens the Market to pick a stock. Keep under 24 characters.
  ///
  /// In en, this message translates to:
  /// **'Find a stock'**
  String get floorMissionFindStock;

  /// Button under a completed promotion mission on the Career tab. Claims the promotion to the next rank. {rank} is the rank's name, already translated.
  ///
  /// In en, this message translates to:
  /// **'Become {rank}'**
  String floorMissionBecomeRank(String rank);

  /// Title of the card on the Career tab right after a promotion. {rank} is the new rank's name, already translated.
  ///
  /// In en, this message translates to:
  /// **'{rank} unlocked'**
  String floorPromotionUnlocked(String rank);

  /// Line above the rank progress bar on the Career tab when the player has the top rank.
  ///
  /// In en, this message translates to:
  /// **'Highest rank reached'**
  String get floorRankHighestReached;

  /// Line above the rank progress bar on the Career tab when the player can claim a promotion. {rank} is the next rank's name, already translated.
  ///
  /// In en, this message translates to:
  /// **'Promotion ready for {rank}'**
  String floorRankPromotionReady(String rank);

  /// Line above the rank progress bar on the Career tab: the player has enough Trims for the next rank but must still finish the promotion mission.
  ///
  /// In en, this message translates to:
  /// **'Threshold reached. Finish the promotion mission'**
  String get floorRankThresholdReached;

  /// Line above the rank progress bar on the Career tab: how many more Trims (career points) the player needs to reach the next rank. English leaves 'Trims' implied ('260 to Analyst'). {rank} is the next rank's name, already translated. Trims is a proper noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{countText} to {rank}}}'**
  String floorRankTrimsToNext(int count, String countText, String rank);

  /// Screen reader label for the rank progress bar on the Career tab. {percent} is a whole number from 0 to 100. {status} is the line shown above the bar, already translated (for example '260 to Analyst').
  ///
  /// In en, this message translates to:
  /// **'Rank progress {percent} percent. {status}'**
  String floorRankProgressSemantics(String percent, String status);

  /// Large title at the top of the Profile tab.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// Shown on the Profile tab in place of the player's @handle when they have not picked one yet.
  ///
  /// In en, this message translates to:
  /// **'Your profile'**
  String get profileYourProfile;

  /// Title on the Profile tab for someone not signed in, above the button that opens sign-in.
  ///
  /// In en, this message translates to:
  /// **'Make it yours'**
  String get profileGuestTitle;

  /// Text on the Profile tab for someone not signed in: signing in keeps their practice trades and Career progress in one account.
  ///
  /// In en, this message translates to:
  /// **'Sign in to keep your trades and career together.'**
  String get profileGuestBody;

  /// Line on the Profile tab when the Career progress could not be refreshed, next to a Retry button. The last known progress is still shown.
  ///
  /// In en, this message translates to:
  /// **'Progress couldn’t refresh.'**
  String get profileProgressRefreshFailed;

  /// Button on the Profile tab that loads the Career progress (rank, Trims, streak) when it has not loaded yet.
  ///
  /// In en, this message translates to:
  /// **'Load progress'**
  String get profileLoadProgress;

  /// Row on the Profile tab that opens choosing a trader persona (the Wolf, the Oracle or the Shark: characters the player plays as).
  ///
  /// In en, this message translates to:
  /// **'Choose your trader'**
  String get profileChooseTrader;

  /// Row title on the Profile tab showing the trader persona the player picked (the Wolf, the Oracle or the Shark).
  ///
  /// In en, this message translates to:
  /// **'Your trader'**
  String get profileYourTrader;

  /// Tooltip and screen reader label of the edit button on the player's portrait on the Profile tab. Opens choosing another trader persona.
  ///
  /// In en, this message translates to:
  /// **'Change your trader'**
  String get profileChangeTrader;

  /// The player's streak on the Profile tab: how many days in a row they have been active. Shown large, above the label 'Streak'.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{countText} day} other{{countText} days}}'**
  String profileStreakDays(int count, String countText);

  /// Small label on the Profile tab under the number of days in a row the player has been active. Keep under 16 characters.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get profileStreakLabel;

  /// One choice in the sheet 'Why are you reporting this?' on a shared reason (a comment on a stock page). Also inserted lowercase in 'Trimmy will review it as …'. Keep under 30 characters.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get socialReportCategorySpam;

  /// One choice in the sheet 'Why are you reporting this?' on a shared reason: the comment harasses someone. Keep under 30 characters.
  ///
  /// In en, this message translates to:
  /// **'Harassment'**
  String get socialReportCategoryHarassment;

  /// One choice in the sheet 'Why are you reporting this?' on a shared reason: the author pretends to be someone else. Keep under 30 characters.
  ///
  /// In en, this message translates to:
  /// **'Impersonation'**
  String get socialReportCategoryImpersonation;

  /// One choice in the sheet 'Why are you reporting this?' on a shared reason: the comment is harmful or dangerous. Keep under 30 characters.
  ///
  /// In en, this message translates to:
  /// **'Unsafe content'**
  String get socialReportCategoryUnsafe;

  /// Last choice in the sheet 'Why are you reporting this?' on a shared reason: any other problem. Keep under 30 characters.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get socialReportCategoryOther;

  /// Title of the Help page and the Settings row that opens it (under Support).
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get infoHelpTitle;

  /// Title of the Terms of use page and the Settings row that opens it (under Legal).
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get infoTermsTitle;

  /// Title of the Privacy notice page and the Settings row that opens it (under Legal).
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get infoPrivacyTitle;

  /// Heading on the Help page. The page points the player to Trimmy's account on X.
  ///
  /// In en, this message translates to:
  /// **'Talk to us'**
  String get infoContactTitle;

  /// Text on the Help page. @trimmyhq is Trimmy's account on X (the social network formerly Twitter); keep both as they are.
  ///
  /// In en, this message translates to:
  /// **'Find @trimmyhq on X for help or feedback.'**
  String get infoContactBody;

  /// Short confirmation after the link on the Help, Terms or Privacy page was copied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get infoLinkCopied;

  /// Button on the Help page that copies the link to Trimmy's X account.
  ///
  /// In en, this message translates to:
  /// **'Copy contact link'**
  String get infoCopyContactLink;

  /// Button on the Terms and Privacy pages that copies the link to the same page on Trimmy's website.
  ///
  /// In en, this message translates to:
  /// **'Copy website link'**
  String get infoCopyWebsiteLink;

  /// Line under the heading of the Terms and Privacy pages. {date} is a date already formatted for the reader, such as "26 September 2026".
  ///
  /// In en, this message translates to:
  /// **'Last updated {date}'**
  String infoLastUpdated(String date);

  /// One line in the list of provider privacy policies on the Privacy page. {provider} is a company name such as "Privy"; {url} is the link to its privacy policy. Only the punctuation changes between languages.
  ///
  /// In en, this message translates to:
  /// **'{provider}: {url}'**
  String infoProviderPolicyLink(String provider, String url);

  /// Section heading on the Privacy page and on the Terms page, about practice trading (practice money) and the Career game.
  ///
  /// In en, this message translates to:
  /// **'Practice and Career'**
  String get infoPracticeAndCareerTitle;

  /// Main heading of the Privacy notice page.
  ///
  /// In en, this message translates to:
  /// **'Privacy, in plain words.'**
  String get infoPrivacyHeading;

  /// First paragraph of the Privacy notice. Legal text: translate faithfully and plainly, keep every obligation and warning.
  ///
  /// In en, this message translates to:
  /// **'This notice describes information handled by the Trimmy app and its supporting services.'**
  String get infoPrivacyIntro;

  /// Section heading on the Privacy notice page, about signing in or playing as a guest.
  ///
  /// In en, this message translates to:
  /// **'Your account or guest session'**
  String get infoPrivacyAccountTitle;

  /// Privacy notice paragraph about sign-in. Privy is a sign-in provider (proper noun). Legal text: translate faithfully and plainly, keep every obligation and warning.
  ///
  /// In en, this message translates to:
  /// **'Sign-in uses Privy and the email or social provider you choose. Trimmy receives account identifiers, session credentials and available linked-account details, such as your email, handle or profile image, to authenticate you and recover your progress. Continuing as a guest creates a separate session; guest activity can also be stored on our server. Signing in can link that progress to your account.'**
  String get infoPrivacyAccountBody;

  /// Privacy notice paragraph under "Practice and Career". Trims are the game points (never translated). Legal text: translate faithfully and plainly.
  ///
  /// In en, this message translates to:
  /// **'Your practice orders, balances, activity answers, completed workdays, streaks, Trims, watchlist and trader profile support the game and your progress. Preferences and unfinished activity drafts can be saved on your device; account and progress records are also stored on our server.'**
  String get infoPrivacyPracticeBody;

  /// Section heading on the Privacy notice page, about shared comments (reasons) and following other players.
  ///
  /// In en, this message translates to:
  /// **'Comments and following'**
  String get infoPrivacyCommentsTitle;

  /// Privacy notice paragraph about comments and following. Legal text: translate faithfully and plainly, keep every warning.
  ///
  /// In en, this message translates to:
  /// **'Your comment-sharing choice controls which other users can see your comments with your handle, trader persona and the asset discussed. The community feed does not publish your order amounts or wallet balance. We store follows, sharing preferences, blocks and reports to provide these features and address abuse. Public blockchain activity remains visible independently of these settings.'**
  String get infoPrivacyCommentsBody;

  /// Section heading on the Privacy notice page, about the crypto wallet and real-money trades.
  ///
  /// In en, this message translates to:
  /// **'Wallets and real trades'**
  String get infoPrivacyWalletsTitle;

  /// Privacy notice paragraph about wallets. Privy and Solana are proper nouns. Legal text: translate faithfully and plainly, keep every warning.
  ///
  /// In en, this message translates to:
  /// **'Privy supplies the embedded wallet and signing interface. Trimmy uses your public Solana address to read balances, request quotes and prepare reviewed transactions. Our server receives signed transactions for submission and stores order terms, transaction references and status. Wallet addresses, token amounts and transaction signatures are public on the blockchain. Closing Trimmy cannot erase those records.'**
  String get infoPrivacyWalletsBody;

  /// Section heading on the Privacy notice page, about adding money to the wallet through Crossmint.
  ///
  /// In en, this message translates to:
  /// **'Funding'**
  String get infoPrivacyFundingTitle;

  /// Privacy notice paragraph about adding money. Crossmint is a payment provider (proper noun). "Onramp server" is Trimmy's server for adding money. Legal text: translate faithfully and plainly.
  ///
  /// In en, this message translates to:
  /// **'When you use Crossmint checkout, Trimmy shares the email, destination wallet, requested amount and wallet-ownership proof needed to prepare the order. Crossmint handles payment and identity-verification information in its checkout. Trimmy receives order and delivery status; our onramp server does not collect card numbers or verification documents.'**
  String get infoPrivacyFundingBody;

  /// Privacy notice paragraph about reminders and notifications. Firebase Cloud Messaging is a product name. "Trade updates" is the notification switch (settingsNotificationTrades) and "Settings" the app's Settings page (commonSettings): use the same words. Legal text: translate faithfully and plainly.
  ///
  /// In en, this message translates to:
  /// **'Career reminders are scheduled on your device with your permission. You can change the reminder preference in Trimmy or disable notifications in device settings. Trade updates are optional on supported devices. If enabled, we store a device notification token and use Firebase Cloud Messaging to send a short update when a real order finishes. Amounts and balances are not included. You can turn trade updates off in Settings. Social and price alerts are not available yet.'**
  String get infoPrivacyRemindersBody;

  /// Section heading on the Privacy notice page, about service providers and technical logs.
  ///
  /// In en, this message translates to:
  /// **'Services and technical records'**
  String get infoPrivacyServicesTitle;

  /// Privacy notice paragraph about providers. Jupiter, Privy and Crossmint are company names. Legal text: translate faithfully and plainly.
  ///
  /// In en, this message translates to:
  /// **'Hosting and database providers support the app. Market-data services receive asset queries; Jupiter and blockchain providers receive wallet or transaction queries needed for real trading. Privy, your sign-in provider and Crossmint handle information under their own policies and may process it in other countries. Network information, request times, identifiers and errors help deliver the service, limit abuse and investigate failures.'**
  String get infoPrivacyServicesBody;

  /// Section heading on the Privacy notice page, about the player's choices and what happens to their records.
  ///
  /// In en, this message translates to:
  /// **'Your choices and records'**
  String get infoPrivacyChoicesTitle;

  /// Privacy notice paragraph about choices and records. "Settings" is the app's Settings page (commonSettings): use the same word. Legal text: translate faithfully and plainly, keep every warning.
  ///
  /// In en, this message translates to:
  /// **'You can change sharing and reminder preferences in Settings. Signing out does not delete server records. Closing an account disables access but does not erase its historical records, delete your provider account, move assets or remove blockchain data. Clearing app data can remove local progress and access information; make sure you can recover a funded wallet before doing so.'**
  String get infoPrivacyChoicesBody;

  /// Privacy notice paragraph about data requests. @trimmyhq is Trimmy's X account; keep it and "X" as they are. Legal text: translate faithfully and plainly, keep every warning.
  ///
  /// In en, this message translates to:
  /// **'Contact @trimmyhq on X to ask about access, correction or deletion of information held by Trimmy. Ask for a private conversation and do not post credentials or personal documents publicly. We may need to verify the request. Provider records follow their own policies; blockchain records cannot be deleted by Trimmy.'**
  String get infoPrivacyRequestsBody;

  /// Section heading on the Privacy notice page, above links to the privacy policies of Privy and Crossmint.
  ///
  /// In en, this message translates to:
  /// **'Provider privacy policies'**
  String get infoPrivacyProvidersTitle;

  /// Main heading of the Terms of use page.
  ///
  /// In en, this message translates to:
  /// **'Using Trimmy.'**
  String get infoTermsHeading;

  /// First paragraph of the Terms of use. Legal text: translate faithfully and plainly.
  ///
  /// In en, this message translates to:
  /// **'Trimmy combines a trading simulation with a separate real-money mode. These terms describe the app as it works today. Features remain in development.'**
  String get infoTermsIntro;

  /// Terms paragraph under "Practice and Career". "Paper" means practice money. Trims are the game points (never translated). Legal text: translate faithfully and plainly, keep every disclaimer.
  ///
  /// In en, this message translates to:
  /// **'Paper balances and orders are simulated. Trims, streaks and Career ranks record game progress; they cannot be withdrawn as money. Practice can use sample or market reference data. Completing an activity does not establish investment suitability, and comments from other users are their own views. Educational content is not personalized investment, legal or tax advice.'**
  String get infoTermsPracticeBody;

  /// Section heading on the Terms page, about Real mode (trading with real money).
  ///
  /// In en, this message translates to:
  /// **'Real money'**
  String get infoTermsRealMoneyTitle;

  /// Terms paragraph about Real mode. "Real" is the mode name (modeReal). "Mainnet" is Solana's live network. Legal text: translate faithfully and plainly, keep every warning.
  ///
  /// In en, this message translates to:
  /// **'Real mode uses a Solana mainnet wallet and supported tokenized stocks. An order can move real assets when you review and confirm it. Check the asset, amount, fees and destination before approving. A quote is an estimate that can expire; a submitted or pending order is not a confirmed trade. History currently shows reviewed quote amounts, not a complete statement of final fills, fees or external transfers.'**
  String get infoTermsRealMoneyBody;

  /// Terms paragraph about the risks of tokenized stocks. Legal text: translate faithfully and plainly, keep every warning.
  ///
  /// In en, this message translates to:
  /// **'Tokenized stocks are subject to their issuer terms and do not necessarily give the same rights as directly holding company shares. Prices can fall, liquidity can disappear, and issuer, network or provider failures can cause loss. Trimmy does not promise returns or execution at a displayed price.'**
  String get infoTermsTokenizedBody;

  /// Section heading on the Terms page, about adding money to the wallet.
  ///
  /// In en, this message translates to:
  /// **'Funding your wallet'**
  String get infoTermsFundingTitle;

  /// Terms paragraph about adding money. USDC and SOL are token symbols, Solana and Crossmint are proper nouns. "Mainnet" is Solana's live network. Legal text: translate faithfully and plainly, keep every warning.
  ///
  /// In en, this message translates to:
  /// **'Send only supported USDC or SOL to the displayed address on the Solana network. Verify the address and network before sending; a completed blockchain transfer cannot simply be undone by Trimmy. SOL is also needed for network fees. Crossmint card checkout is currently a test environment: its test funds do not fund mainnet trades. Its production availability, payment methods, verification and fees depend on the provider.'**
  String get infoTermsFundingBody;

  /// Section heading on the Terms page, about protecting sign-in and wallet access.
  ///
  /// In en, this message translates to:
  /// **'Account access'**
  String get infoTermsAccessTitle;

  /// Terms paragraph about account and wallet safety. Legal and safety text: translate faithfully and plainly, keep every warning (especially "never share").
  ///
  /// In en, this message translates to:
  /// **'Protect your sign-in method and review wallet prompts carefully. Never share a private key, recovery phrase or one-time sign-in code with support. This build does not yet provide in-app withdrawals or wallet export. Closing your account does not withdraw assets. Resolve wallet access before closing an account or removing the app from a funded device.'**
  String get infoTermsAccessBody;

  /// Section heading on the Terms page, about who may use real-money features and third-party services.
  ///
  /// In en, this message translates to:
  /// **'Eligibility and other services'**
  String get infoTermsEligibilityTitle;

  /// Terms paragraph about eligibility. Privy and Crossmint are company names. Legal text: translate faithfully and plainly, keep every obligation.
  ///
  /// In en, this message translates to:
  /// **'You must meet the applicable asset issuer and service-provider requirements, including location and eligibility restrictions. Seeing an asset or obtaining a quote does not establish eligibility. Privy, Crossmint, trading providers and asset issuers have separate terms. Trimmy does not promise availability in every country.'**
  String get infoTermsEligibilityBody;

  /// Section heading on the Terms page, about rules for comments and community features.
  ///
  /// In en, this message translates to:
  /// **'Using the community'**
  String get infoTermsCommunityTitle;

  /// Terms paragraph with the community rules. Legal text: translate faithfully and plainly, keep every rule.
  ///
  /// In en, this message translates to:
  /// **'Share comments you have the right to publish. Do not impersonate others, expose private information, manipulate the market, harass users or interfere with accounts and services. Sharing settings, blocking and reporting tools are available for comments and community interactions.'**
  String get infoTermsCommunityBody;

  /// Section heading on the Terms page, about service availability and how to ask questions.
  ///
  /// In en, this message translates to:
  /// **'Availability and questions'**
  String get infoTermsAvailabilityTitle;

  /// Last Terms paragraph. @trimmyhq is Trimmy's X account; keep it and "X" as they are. Legal text: translate faithfully and plainly, keep the statutory rights sentence intact.
  ///
  /// In en, this message translates to:
  /// **'Market data, quotes, notifications and network confirmation can be delayed or unavailable. Features and these notices may change as development continues. Nothing here removes rights that cannot be excluded under applicable law. Contact @trimmyhq on X for help or questions about these terms.'**
  String get infoTermsAvailabilityBody;

  /// Settings row that opens the daily reminder preferences, and the heading of the Reminders part of the Privacy notice. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get settingsReminders;

  /// Settings section title above sign-in, handle, character, email and sign-out rows.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccountSection;

  /// Line under the Sign in row in Settings, for a guest. Signing in keeps their game progress safe.
  ///
  /// In en, this message translates to:
  /// **'Sign in to keep your progress.'**
  String get settingsSignInDetail;

  /// Settings row title. The value under it is the player's public @username, such as "@mira".
  ///
  /// In en, this message translates to:
  /// **'Handle'**
  String get settingsHandle;

  /// Settings row title. The value under it is the character (persona) the player picked, such as "The Wolf". Tapping it changes the character.
  ///
  /// In en, this message translates to:
  /// **'Your trader'**
  String get settingsYourTrader;

  /// Line under "Your trader" in Settings when no character has been picked yet.
  ///
  /// In en, this message translates to:
  /// **'Choose a character'**
  String get settingsChooseCharacter;

  /// Settings row title. The value under it is the email address of the signed-in account.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get settingsEmail;

  /// Settings row title. The value under it lists how the player signs in, such as "Email, X".
  ///
  /// In en, this message translates to:
  /// **'Sign-in methods'**
  String get settingsSignInMethods;

  /// Line under "Sign-in methods" in Settings when the app cannot tell how the player signs in.
  ///
  /// In en, this message translates to:
  /// **'Sign-in method unavailable.'**
  String get settingsSignInMethodsUnavailable;

  /// Name of the "sign in with email" method in the list under "Sign-in methods" in Settings, such as "Email, X" (Google and X stay as they are). Keep short.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get settingsSignInMethodEmail;

  /// Settings row that signs the player out of their account.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// Settings section title above the notification switches.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotificationsSection;

  /// Small upper-cased subheading inside Notifications in Settings, above market alerts (Wall Street open and close, price alerts). Keep short.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get settingsNotificationGroupMarket;

  /// Small upper-cased subheading inside Notifications in Settings, above Career alerts (streak, missions, promotions, league). Career is the app's career tab. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Career'**
  String get settingsNotificationGroupCareer;

  /// Small upper-cased subheading inside Notifications in Settings, above alerts about friends. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Social'**
  String get settingsNotificationGroupSocial;

  /// Small upper-cased subheading inside Notifications in Settings, above trade updates and news from Trimmy. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsNotificationGroupAccount;

  /// Notification switch title in Settings: a notification when the US stock market (Wall Street) opens.
  ///
  /// In en, this message translates to:
  /// **'Wall Street open'**
  String get settingsNotificationOpen;

  /// Line under the "Wall Street open" notification switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'When Wall Street opens.'**
  String get settingsNotificationOpenDetail;

  /// Notification switch title in Settings: a notification when the US stock market (Wall Street) closes.
  ///
  /// In en, this message translates to:
  /// **'Wall Street close'**
  String get settingsNotificationClose;

  /// Line under the "Wall Street close" notification switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'When Wall Street closes.'**
  String get settingsNotificationCloseDetail;

  /// Notification switch title in Settings: news and events about stocks the player owns.
  ///
  /// In en, this message translates to:
  /// **'Events on my stocks'**
  String get settingsNotificationEvents;

  /// Line under the "Events on my stocks" notification switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'Updates that affect stocks you hold.'**
  String get settingsNotificationEventsDetail;

  /// Notification switch title in Settings: alerts when a followed stock's price moves a lot.
  ///
  /// In en, this message translates to:
  /// **'Price alerts'**
  String get settingsNotificationPrices;

  /// Line under the "Price alerts" notification switch in Settings. {small} and {large} are percents already formatted for the reader ("5%" and "10%").
  ///
  /// In en, this message translates to:
  /// **'Moves of {small} or {large} on followed stocks.'**
  String settingsNotificationPricesDetail(String small, String large);

  /// Notification switch title in Settings: a reminder before the player loses their streak (days in a row of play).
  ///
  /// In en, this message translates to:
  /// **'Streak reminder'**
  String get settingsNotificationStreak;

  /// Line under the "Streak reminder" notification switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'When your streak is at risk.'**
  String get settingsNotificationStreakDetail;

  /// Notification switch title in Settings: Career missions (goals on the Career floor, such as promotion missions), not the workday assignments.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get settingsNotificationMissions;

  /// Line under the "Missions" notification switch in Settings. Missions are Career goals, not workday assignments.
  ///
  /// In en, this message translates to:
  /// **'New missions and progress.'**
  String get settingsNotificationMissionsDetail;

  /// Notification switch title in Settings: when the player is promoted to a new career rank (Rookie, Analyst, Trader...). Not sales offers.
  ///
  /// In en, this message translates to:
  /// **'Promotions'**
  String get settingsNotificationPromotions;

  /// Line under the "Promotions" notification switch in Settings. A rank is a career level (Rookie, Analyst, Trader, Senior Trader, Partner, Legend).
  ///
  /// In en, this message translates to:
  /// **'When you earn a new rank.'**
  String get settingsNotificationPromotionsDetail;

  /// Notification switch title in Settings: the weekly league where players are ranked against each other.
  ///
  /// In en, this message translates to:
  /// **'League'**
  String get settingsNotificationLeague;

  /// Line under the "League" notification switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'League results and position changes.'**
  String get settingsNotificationLeagueDetail;

  /// Notification switch title in Settings: activity from the player's friends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get settingsNotificationFriends;

  /// Line under the "Friends" notification switch in Settings: trades friends make and the reasons they share for them.
  ///
  /// In en, this message translates to:
  /// **'Friends\' trades and reasons.'**
  String get settingsNotificationFriendsDetail;

  /// Notification switch title in Settings: a push notification when a real-money order finishes. Also used in the Privacy notice.
  ///
  /// In en, this message translates to:
  /// **'Trade updates'**
  String get settingsNotificationTrades;

  /// Line under the "Trade updates" notification switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'When a real-money order finishes.'**
  String get settingsNotificationTradesDetail;

  /// Notification switch title in Settings: news about the app itself.
  ///
  /// In en, this message translates to:
  /// **'News from Trimmy'**
  String get settingsNotificationNews;

  /// Line under the "News from Trimmy" notification switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'Product news and updates.'**
  String get settingsNotificationNewsDetail;

  /// Line under a notification switch in Settings when that notification does not exist yet.
  ///
  /// In en, this message translates to:
  /// **'Not available yet.'**
  String get settingsNotAvailableYet;

  /// Settings subheading and switch title: hours of the night when Trimmy sends no notifications.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours'**
  String get settingsQuietHours;

  /// Line under the "Quiet hours" switch in Settings. {start} and {end} are clock times already formatted for the reader, such as "10:00 PM" and "7:00 AM".
  ///
  /// In en, this message translates to:
  /// **'{start} to {end}'**
  String settingsQuietHoursRange(String start, String end);

  /// Tooltip and screen reader label of the clock button next to the "Quiet hours" switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'Edit quiet hours'**
  String get settingsEditQuietHours;

  /// Settings section title above sound, haptics, animation, motion and language settings.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settingsPreferencesSection;

  /// Settings switch title that turns the app's sounds on or off.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get settingsSound;

  /// Line under the "Sound" switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'Sounds for key moments.'**
  String get settingsSoundDetail;

  /// Settings switch title that turns vibration feedback (haptics) on or off.
  ///
  /// In en, this message translates to:
  /// **'Haptics'**
  String get settingsHaptics;

  /// Line under the "Haptics" switch in Settings: small vibrations when you tap.
  ///
  /// In en, this message translates to:
  /// **'Taps you can feel.'**
  String get settingsHapticsDetail;

  /// Settings switch title that turns animations on or off.
  ///
  /// In en, this message translates to:
  /// **'Animations'**
  String get settingsAnimations;

  /// Line under the "Animations" switch in Settings when the phone's own "reduce motion" setting is on, so the switch is locked.
  ///
  /// In en, this message translates to:
  /// **'Limited by your phone setting.'**
  String get settingsAnimationsLimited;

  /// Line under the "Animations" switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'Movement and celebrations.'**
  String get settingsAnimationsDetail;

  /// Settings row title showing the phone's accessibility "reduce motion" setting.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get settingsReduceMotion;

  /// Line under "Reduce motion" in Settings when the phone's reduce motion setting is on.
  ///
  /// In en, this message translates to:
  /// **'On. Follows your phone setting.'**
  String get settingsReduceMotionOn;

  /// Line under "Reduce motion" in Settings when the phone's reduce motion setting is off.
  ///
  /// In en, this message translates to:
  /// **'Off. Follows your phone setting.'**
  String get settingsReduceMotionOff;

  /// Settings row title in the practice section. The amount next to it is how much practice money (English "paper") the player's rank gives them.
  ///
  /// In en, this message translates to:
  /// **'Paper limit'**
  String get settingsPaperLimit;

  /// Settings row title that starts over the practice desk: practice trades are cleared and the practice money is refilled. Destructive action, shown in red.
  ///
  /// In en, this message translates to:
  /// **'Reset paper'**
  String get settingsResetPaper;

  /// Line under "Reset paper" in Settings while the practice desk is being reset.
  ///
  /// In en, this message translates to:
  /// **'Resetting your paper desk.'**
  String get settingsResetPaperBusy;

  /// Line under "Reset paper" in Settings when a reset the player already confirmed has not finished yet (for example, it was offline).
  ///
  /// In en, this message translates to:
  /// **'Your confirmed reset is waiting to finish.'**
  String get settingsResetPaperPending;

  /// Line under "Reset paper" in Settings.
  ///
  /// In en, this message translates to:
  /// **'Clear paper trades and start again.'**
  String get settingsResetPaperDetail;

  /// Title of the dialog that confirms resetting the practice desk (English "paper desk").
  ///
  /// In en, this message translates to:
  /// **'Reset your paper desk?'**
  String get settingsResetPaperTitle;

  /// Body of the dialog that confirms resetting the practice desk. Trims are the game points (never translated). "Money" means real money.
  ///
  /// In en, this message translates to:
  /// **'This starts a fresh paper desk. Past receipts stay in your record. Your Career, Trims, rank, streak and money do not change.'**
  String get settingsResetPaperBody;

  /// The exact phrase the player must type to confirm resetting the practice desk. Also the field's hint. The typed text is compared with this message exactly, so write it in lower case, with no punctuation and no apostrophe, and keep it easy to type on a phone keyboard.
  ///
  /// In en, this message translates to:
  /// **'reset my paper desk'**
  String get settingsResetPaperPhrase;

  /// Instruction in the practice desk reset dialog. {phrase} is the confirmation phrase (settingsResetPaperPhrase), such as "reset my paper desk".
  ///
  /// In en, this message translates to:
  /// **'Type “{phrase}” to continue.'**
  String settingsResetPaperInstruction(String phrase);

  /// Screen reader label of the text field in the practice desk reset dialog. {phrase} is the confirmation phrase (settingsResetPaperPhrase).
  ///
  /// In en, this message translates to:
  /// **'Confirmation phrase. Type {phrase}.'**
  String settingsResetPaperFieldLabel(String phrase);

  /// Label of the text field in the practice desk reset dialog where the player types the confirmation phrase.
  ///
  /// In en, this message translates to:
  /// **'Confirmation phrase'**
  String get settingsResetPaperFieldTitle;

  /// Red button in the practice desk reset dialog that performs the reset. Keep under 20 characters.
  ///
  /// In en, this message translates to:
  /// **'Reset paper desk'**
  String get settingsResetPaperConfirm;

  /// Title of the dialog shown after the practice desk was reset ("the paper desk has been reset").
  ///
  /// In en, this message translates to:
  /// **'Paper desk reset'**
  String get settingsResetPaperDoneTitle;

  /// Body of the dialog after the practice desk was reset. {amount} is the new practice money balance, already formatted ("10,000").
  ///
  /// In en, this message translates to:
  /// **'Your desk is ready with {amount} paper.'**
  String settingsResetPaperDone(String amount);

  /// Body of the dialog after the practice desk was reset, when trades made after the reset request were kept. {amount} is the practice money balance, already formatted ("9,250").
  ///
  /// In en, this message translates to:
  /// **'Newer trades were kept. Your balance is {amount} paper.'**
  String settingsResetPaperDoneNewer(String amount);

  /// Message after resetting the practice desk failed for an unknown reason.
  ///
  /// In en, this message translates to:
  /// **'Paper was not reset. Try again.'**
  String get settingsResetPaperFailed;

  /// Message after a practice desk reset was refused because the desk changed in the meantime (for example, on another device). The desk was reloaded.
  ///
  /// In en, this message translates to:
  /// **'Your paper desk changed. It was refreshed. Review it, then confirm the reset again.'**
  String get settingsResetPaperStale;

  /// Message when a practice desk reset was not needed because the desk is already new.
  ///
  /// In en, this message translates to:
  /// **'Your paper desk is already fresh. Nothing was cleared.'**
  String get settingsResetPaperNotNeeded;

  /// Message when the practice desk reset could not be sent because the phone is offline. The same request is kept and will be retried without risk of a double reset.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Your exact reset request is saved for a safe retry.'**
  String get settingsResetPaperOffline;

  /// Message when the practice desk reset timed out. The same request is kept and will be retried without risk of a double reset.
  ///
  /// In en, this message translates to:
  /// **'The reset took too long to confirm. Your exact request is saved for a safe retry.'**
  String get settingsResetPaperTimeout;

  /// Message when the practice desk reset needs the player to sign in again (their session expired).
  ///
  /// In en, this message translates to:
  /// **'Your paper desk needs a fresh session before the reset can finish.'**
  String get settingsResetPaperAccountRequired;

  /// Message when the player reset the practice desk too often. The request is kept to try later.
  ///
  /// In en, this message translates to:
  /// **'Paper resets are limited. Try this saved request again later.'**
  String get settingsResetPaperRateLimited;

  /// Message when the server could not confirm the practice desk reset. The same request is kept and will be retried without risk of a double reset.
  ///
  /// In en, this message translates to:
  /// **'The reset could not be confirmed. Your exact request is saved for a safe retry.'**
  String get settingsResetPaperUnavailable;

  /// Message when the server refused the practice desk reset.
  ///
  /// In en, this message translates to:
  /// **'Paper was not reset. Refresh your desk and try again.'**
  String get settingsResetPaperRejected;

  /// Settings section title about real money: adding money, currency, fees, saved cards.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get settingsMoneySection;

  /// Line under "Add money" in Settings: you can add money with a card or with crypto. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Card or crypto'**
  String get settingsMoneyCardOrCrypto;

  /// Line under "Add money" in Settings when trading with real money is not offered yet.
  ///
  /// In en, this message translates to:
  /// **'Money trading is coming later.'**
  String get settingsMoneyComingSoon;

  /// Line under "Add money" in Settings when this account cannot use real money.
  ///
  /// In en, this message translates to:
  /// **'Money features are unavailable for this account.'**
  String get settingsMoneyUnavailable;

  /// Label in the Money section of Settings; the value next to it is a currency, such as "USD".
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsCurrency;

  /// Label in the Money section of Settings; the value next to it is the company that handles adding money, such as "Crossmint".
  ///
  /// In en, this message translates to:
  /// **'Deposit partner'**
  String get settingsDepositPartner;

  /// Label in the Money section of Settings; the value next to it summarizes the fees.
  ///
  /// In en, this message translates to:
  /// **'Fees'**
  String get settingsFees;

  /// Label in the Money section of Settings; the value next to it says whether the player's country is allowed.
  ///
  /// In en, this message translates to:
  /// **'Country check'**
  String get settingsCountryCheck;

  /// Label in the Money section of Settings; the value next to it is how many bank accounts are saved.
  ///
  /// In en, this message translates to:
  /// **'Bank accounts'**
  String get settingsBankAccounts;

  /// Label in the Money section of Settings; the value next to it is how many payment cards are saved.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get settingsCards;

  /// Settings section title and row title for the player's Solana crypto wallet. The row shows the shortened wallet address.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get settingsWallet;

  /// Line under "Wallet" in Settings when the wallet address is not known yet.
  ///
  /// In en, this message translates to:
  /// **'No wallet details are available yet.'**
  String get settingsWalletNoDetails;

  /// Line under "Wallet" in Settings when wallet tools are not offered yet.
  ///
  /// In en, this message translates to:
  /// **'Wallet tools are coming later.'**
  String get settingsWalletComingSoon;

  /// Line under "Wallet" in Settings when this account cannot use wallet tools.
  ///
  /// In en, this message translates to:
  /// **'Wallet tools are unavailable for this account.'**
  String get settingsWalletUnavailable;

  /// Settings row that opens the wallet on a public blockchain explorer (opens outside the app).
  ///
  /// In en, this message translates to:
  /// **'Check wallet'**
  String get settingsCheckWallet;

  /// Settings row that exports the wallet so the player can access it outside Trimmy.
  ///
  /// In en, this message translates to:
  /// **'Back up wallet'**
  String get settingsBackUpWallet;

  /// Line under "Back up wallet" in Settings.
  ///
  /// In en, this message translates to:
  /// **'Keep access outside Trimmy.'**
  String get settingsBackUpWalletDetail;

  /// Settings section title above who can see your holdings and comments, and downloading your data.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacySection;

  /// Settings row title; the value next to it is who can see what the player owns (Friends, Everyone, Nobody).
  ///
  /// In en, this message translates to:
  /// **'Who sees my holdings'**
  String get settingsHoldingsVisibility;

  /// Choice in Settings: only the player's friends can see their holdings. Keep short, it sits next to the row title.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get settingsVisibilityFriends;

  /// Choice in Settings: everyone in Trimmy can see the player's holdings. Keep short, it sits next to the row title.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get settingsVisibilityEveryone;

  /// Choice in Settings: nobody else can see the player's holdings. Keep short, it sits next to the row title.
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get settingsVisibilityNobody;

  /// Settings row that downloads a copy of the player's data.
  ///
  /// In en, this message translates to:
  /// **'Download my data'**
  String get settingsDownloadData;

  /// Settings section title above Help, Send feedback and Report a bug.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupportSection;

  /// Settings row that lets the player tell the team what they think of the app.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get settingsSendFeedback;

  /// Settings row that lets the player report a problem in the app.
  ///
  /// In en, this message translates to:
  /// **'Report a bug'**
  String get settingsReportBug;

  /// Line under "Report a bug" in Settings: the app version number is added to the report automatically.
  ///
  /// In en, this message translates to:
  /// **'Your app version will be attached.'**
  String get settingsReportBugDetail;

  /// Settings section title above Terms, Privacy, Risk notice and About tokenized stocks.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get settingsLegalSection;

  /// Settings row that opens the notice about the risks of trading with real money.
  ///
  /// In en, this message translates to:
  /// **'Risk notice'**
  String get settingsRiskNotice;

  /// Settings row that opens an explanation of tokenized stocks (tokens on Solana that track a company's stock).
  ///
  /// In en, this message translates to:
  /// **'About tokenized stocks'**
  String get settingsAboutTokenizedStocks;

  /// Line under "About tokenized stocks" in Settings. "They" are tokenized stocks.
  ///
  /// In en, this message translates to:
  /// **'What they are and what they are not.'**
  String get settingsAboutTokenizedStocksDetail;

  /// Settings section title above the Close account row.
  ///
  /// In en, this message translates to:
  /// **'Account closure'**
  String get settingsAccountClosureSection;

  /// Settings row (red) that starts closing the player's account. It first explains what happens.
  ///
  /// In en, this message translates to:
  /// **'Close account'**
  String get settingsCloseAccount;

  /// Line under "Close account" in Settings.
  ///
  /// In en, this message translates to:
  /// **'Review what happens to your records and wallet.'**
  String get settingsCloseAccountDetail;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the server rejects the address or the amount as invalid.
  ///
  /// In en, this message translates to:
  /// **'Check the address and the amount.'**
  String get sendErrorCheckInput;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the typed address is the person's own wallet.
  ///
  /// In en, this message translates to:
  /// **'That’s your own wallet. Enter another address.'**
  String get sendErrorSelf;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the address belongs to a token account or a program rather than a person's wallet.
  ///
  /// In en, this message translates to:
  /// **'That address isn’t a wallet. It may be a token account or a program. Ask for the wallet address instead.'**
  String get sendErrorNotWallet;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the receiving wallet is frozen for this token by its issuer.
  ///
  /// In en, this message translates to:
  /// **'That wallet can’t receive this token right now.'**
  String get sendErrorDestinationFrozen;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when Trimmy does not support sending this token.
  ///
  /// In en, this message translates to:
  /// **'This token can’t be sent from Trimmy.'**
  String get sendErrorAssetUnsupported;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the token's own transfer rules prevent Trimmy from sending it.
  ///
  /// In en, this message translates to:
  /// **'This token has transfer rules Trimmy can’t send with.'**
  String get sendErrorNotTransferable;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the firm that issues the token has paused all transfers.
  ///
  /// In en, this message translates to:
  /// **'Its issuer has paused transfers for now.'**
  String get sendErrorAssetPaused;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the issuer froze this token in the person's own wallet.
  ///
  /// In en, this message translates to:
  /// **'This token is frozen in your wallet. Contact its issuer.'**
  String get sendErrorAssetFrozen;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the amount is more than what the wallet can send.
  ///
  /// In en, this message translates to:
  /// **'You don’t have that much ready to send.'**
  String get sendErrorInsufficient;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the wallet needs more SOL (Solana's coin, never translated) to pay the network fee.
  ///
  /// In en, this message translates to:
  /// **'Add a little SOL to cover the network fee.'**
  String get sendErrorAddSol;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when sending SOL would leave a tiny remainder the network does not allow. {amount} is the smallest SOL to keep, already formatted.
  ///
  /// In en, this message translates to:
  /// **'Leave at least {amount} SOL, or send all of it.'**
  String sendErrorLeaveSol(String amount);

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when sending SOL to a brand new wallet below the minimum it needs to exist. {amount} is that minimum, already formatted.
  ///
  /// In en, this message translates to:
  /// **'A new wallet needs at least {amount} SOL to open.'**
  String sendErrorTooSmall(String amount);

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the server's safety simulation of the send failed, so nothing was sent. "Send" is a noun here: one transfer.
  ///
  /// In en, this message translates to:
  /// **'This send didn’t pass its check. Nothing was sent.'**
  String get sendErrorCheckFailed;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the reviewed send is too old to sign; the person reviews it again.
  ///
  /// In en, this message translates to:
  /// **'This review expired. Review it again.'**
  String get sendErrorReviewExpired;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when an earlier send is still unresolved.
  ///
  /// In en, this message translates to:
  /// **'Check your previous send before starting another.'**
  String get sendErrorPrevious;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the transaction to sign differs from what the person reviewed, so it was not signed.
  ///
  /// In en, this message translates to:
  /// **'This transaction doesn’t match your review. Nothing was sent.'**
  String get sendErrorMismatch;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the app could not save the send on the phone, which it needs to recover the send after a crash.
  ///
  /// In en, this message translates to:
  /// **'Allow device storage to keep your send recoverable.'**
  String get sendErrorStorage;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when another send request is still being handled.
  ///
  /// In en, this message translates to:
  /// **'One moment, then try again.'**
  String get sendErrorBusy;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the person closed the wallet's signing prompt.
  ///
  /// In en, this message translates to:
  /// **'Signing was cancelled. Nothing was sent.'**
  String get sendErrorCancelled;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when Trimmy has paused all sends.
  ///
  /// In en, this message translates to:
  /// **'Sending is paused right now. Try again later.'**
  String get sendErrorPaused;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice for any other error, usually a connection problem.
  ///
  /// In en, this message translates to:
  /// **'Sending couldn’t connect. Try again.'**
  String get sendErrorGeneric;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the app could not read the status of the person's last send. A "Check previous send" button sits above.
  ///
  /// In en, this message translates to:
  /// **'Your previous send couldn’t be checked. Try checking again.'**
  String get sendRecoveryFailed;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the recipient field does not hold a valid Solana address. Solana is never translated.
  ///
  /// In en, this message translates to:
  /// **'Enter a Solana wallet address.'**
  String get sendEnterAddress;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the amount field is empty or not a valid number.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount.'**
  String get sendEnterAmount;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when the typed amount is more than the wallet holds. {amount} is the available amount with its symbol, already formatted.
  ///
  /// In en, this message translates to:
  /// **'You have {amount} ready to send.'**
  String sendHaveReady(String amount);

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), top bar title. Verb: send money. Keep very short.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendTitle;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), button that checks the status of the last send again after a failed check. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Check previous send'**
  String get sendCheckPrevious;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), title when the wallet holds nothing that can be sent.
  ///
  /// In en, this message translates to:
  /// **'Nothing to send yet'**
  String get sendNothingTitle;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), text under "Nothing to send yet".
  ///
  /// In en, this message translates to:
  /// **'Add money or buy a stock first. Anything in your wallet can be sent from here.'**
  String get sendNothingBody;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), main heading above the form. Solana is never translated.
  ///
  /// In en, this message translates to:
  /// **'Send to a Solana wallet'**
  String get sendHeading;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), warning under the heading. "Sends" is a noun: transfers.
  ///
  /// In en, this message translates to:
  /// **'Only send to a Solana address. Sends can’t be undone.'**
  String get sendWarning;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), label of the dropdown that picks USDC, SOL or a stock token.
  ///
  /// In en, this message translates to:
  /// **'What to send'**
  String get sendWhatLabel;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), name of USDC in the dropdown. USDC is a US dollar token; keep "(USDC)".
  ///
  /// In en, this message translates to:
  /// **'US dollars (USDC)'**
  String get sendAssetUsdc;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), label of the field for the receiving wallet's address.
  ///
  /// In en, this message translates to:
  /// **'Recipient’s wallet address'**
  String get sendRecipientLabel;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), tooltip and screen reader label of the button that pastes an address from the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get sendPaste;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), label of the amount field when sending a stock token (counted in shares).
  ///
  /// In en, this message translates to:
  /// **'Shares'**
  String get sendSharesLabel;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), label of the amount field when sending USDC or SOL. {symbol} is USDC or SOL, never translated.
  ///
  /// In en, this message translates to:
  /// **'Amount ({symbol})'**
  String sendAmountLabel(String symbol);

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), helper line under the amount field: everything the wallet can send of the chosen asset. {amount} is the amount with its symbol, already formatted.
  ///
  /// In en, this message translates to:
  /// **'{amount} ready to send'**
  String sendReadyToSend(String amount);

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), note under the amount when sending SOL: the Max button leaves a little SOL behind for fees. {amount} is that SOL amount, already formatted.
  ///
  /// In en, this message translates to:
  /// **'Max keeps {amount} SOL so you can still pay network fees.'**
  String sendMaxKeepsSol(String amount);

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), main button that asks the server to check the send before signing. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Review send'**
  String get sendReview;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), heading of the review step before signing.
  ///
  /// In en, this message translates to:
  /// **'Review your send'**
  String get sendReviewTitle;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), review row label: the amount leaving the wallet.
  ///
  /// In en, this message translates to:
  /// **'You send'**
  String get sendYouSend;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), review row label: what arrives after the token issuer takes its fee. "They" is the recipient.
  ///
  /// In en, this message translates to:
  /// **'They receive, after the issuer fee'**
  String get sendTheyReceive;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), review row label: the Solana network fee, paid in SOL.
  ///
  /// In en, this message translates to:
  /// **'Network fee'**
  String get sendNetworkFee;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), review row label: a one-time SOL cost to open the recipient's account for this token. {symbol} is the token symbol, never translated.
  ///
  /// In en, this message translates to:
  /// **'Opens their {symbol} account (once)'**
  String sendOpensAccount(String symbol);

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), review step: label above the full recipient address.
  ///
  /// In en, this message translates to:
  /// **'To this Solana wallet'**
  String get sendToWallet;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), review step: warning under the recipient address.
  ///
  /// In en, this message translates to:
  /// **'Check every character. Sends can’t be undone, and Trimmy can’t get money back from a wrong address.'**
  String get sendCheckEvery;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), main button on the review step that signs and sends. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get sendNow;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), button on the review step that goes back to change the send. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get sendEdit;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), result title when the send is confirmed.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sendResultSent;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), result title while the send waits for the network.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get sendResultSending;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), result title when the network rejected the send.
  ///
  /// In en, this message translates to:
  /// **'It didn’t go through'**
  String get sendResultFailed;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), result title when the send expired before it was confirmed.
  ///
  /// In en, this message translates to:
  /// **'Send expired'**
  String get sendResultExpired;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), result title when the app stopped waiting but the send is not confirmed yet.
  ///
  /// In en, this message translates to:
  /// **'Still confirming'**
  String get sendResultChecking;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), text under "Sent".
  ///
  /// In en, this message translates to:
  /// **'It’s confirmed on Solana.'**
  String get sendBodySent;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), text under "Sending".
  ///
  /// In en, this message translates to:
  /// **'This usually takes a few seconds.'**
  String get sendBodySending;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), text under "It didn't go through".
  ///
  /// In en, this message translates to:
  /// **'Solana refused it. Only the network fee was spent.'**
  String get sendBodyFailed;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), text under "Send expired".
  ///
  /// In en, this message translates to:
  /// **'This transaction expired without confirmation. You can review a new send.'**
  String get sendBodyExpired;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), text under "Still confirming".
  ///
  /// In en, this message translates to:
  /// **'We’re still checking this send. Don’t send it again.'**
  String get sendBodyChecking;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), link that opens the transaction on Solscan, a Solana explorer website (name never translated).
  ///
  /// In en, this message translates to:
  /// **'View on Solscan'**
  String get sendViewSolscan;

  /// Send screen (Real mode, sends USDC, SOL or a stock token from the person's wallet to another Solana wallet), notice when tapping Done could not clear the saved send on the phone.
  ///
  /// In en, this message translates to:
  /// **'This send is saved. Try closing it again.'**
  String get sendCloseFailed;

  /// Reminder frequency choice (onboarding and Settings > Reminders): one of three cards. Title of the card for a reminder every weekday. Keep short.
  ///
  /// In en, this message translates to:
  /// **'On workdays'**
  String get reminderDailyLabel;

  /// Reminder frequency choice (onboarding and Settings > Reminders): one of three cards. Caption under "On workdays": the reminder comes at about 7 in the evening, only when an assignment is waiting.
  ///
  /// In en, this message translates to:
  /// **'Around 7 PM, when work is waiting.'**
  String get reminderDailyCaption;

  /// Reminder frequency choice (onboarding and Settings > Reminders): one of three cards. Title of the card for a reminder on Monday, Wednesday and Friday. Keep short.
  ///
  /// In en, this message translates to:
  /// **'A few times a week'**
  String get reminderOccasionalLabel;

  /// Reminder frequency choice (onboarding and Settings > Reminders): one of three cards. Caption under "A few times a week": Monday, Wednesday and Friday at about 7 in the evening.
  ///
  /// In en, this message translates to:
  /// **'Mon, Wed and Fri, around 7 PM.'**
  String get reminderOccasionalCaption;

  /// Reminder frequency choice (onboarding and Settings > Reminders): one of three cards. Title of the card for no reminders at all. Keep short.
  ///
  /// In en, this message translates to:
  /// **'Keep it quiet'**
  String get reminderOffLabel;

  /// Reminder frequency choice (onboarding and Settings > Reminders): one of three cards. Caption under "Keep it quiet", in the player's voice: they will open the app without being reminded.
  ///
  /// In en, this message translates to:
  /// **'I’ll come back on my own.'**
  String get reminderOffCaption;

  /// Workday reminder notification, shown by the phone outside the app at about 7 PM local time. Title of the notification. "Desk" is the home tab (Escritorio / Mesa / Bureau). Keep under 40 characters.
  ///
  /// In en, this message translates to:
  /// **'Your desk is waiting'**
  String get reminderNotificationTitle;

  /// Workday reminder notification, shown by the phone outside the app at about 7 PM local time. Text of the notification when no workday title is known. An assignment is a task inside a workday.
  ///
  /// In en, this message translates to:
  /// **'Your next assignment is waiting at your desk.'**
  String get reminderNotificationBody;

  /// Workday reminder notification, shown by the phone outside the app at about 7 PM local time. Text of the notification naming the waiting workday. {day} is the workday number; {title} is the workday's title, written by the server (it may stay in English).
  ///
  /// In en, this message translates to:
  /// **'Day {day}: {title}'**
  String reminderNotificationDay(int day, String title);

  /// Settings, trade update alerts (push notifications when a real-money order finishes). Message when the phone blocks notifications for Trimmy, so trade updates cannot turn on.
  ///
  /// In en, this message translates to:
  /// **'Notifications are off in device settings.'**
  String get pushErrorNotificationsOff;

  /// Settings, trade update alerts (push notifications when a real-money order finishes). Message when turning trade updates on or off failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t update notifications. Try again.'**
  String get pushErrorUpdate;

  /// Settings, trade update alerts (push notifications when a real-money order finishes). Message when trade updates could not be turned off because the phone is offline.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t turn off alerts. Try again when you’re online.'**
  String get pushErrorTurnOff;

  /// Settings, trade update alerts (push notifications when a real-money order finishes). Message when the phone could not register for notifications.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t connect notifications. Try again.'**
  String get pushErrorConnect;

  /// Button under the sign-in code field, for when the emailed code is slow or lost. Sends a fresh code to the same address.
  ///
  /// In en, this message translates to:
  /// **'Send a new code'**
  String get signInResendCode;

  /// The same button while it waits before another code may be sent; counts down every second. {seconds} is a whole number of seconds; keep the unit short.
  ///
  /// In en, this message translates to:
  /// **'Send again in {seconds}s'**
  String signInResendIn(int seconds);

  /// Shown while the account is being closed, after the player confirmed. Nothing can be tapped until it finishes.
  ///
  /// In en, this message translates to:
  /// **'Closing your account…'**
  String get appCloseAccountClosing;

  /// Shown when closing the account failed; the player is still signed in and nothing changed.
  ///
  /// In en, this message translates to:
  /// **'Your account was not closed. Try again.'**
  String get appCloseAccountFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'fr', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
