import type {AreaMessages} from '../types';

/**
 * The Profile tab and Settings: the player's trader, progress, account,
 * preferences, language, paper reset, comment privacy and account closure.
 * Rank labels ("Rookie", "Analyst"), handles, emails and the persona name
 * Settings receives come from elsewhere and arrive as values.
 */
export default {
  // Profile tab.
  'profile.page.title': 'Profile',
  /** Link from Profile to the Settings screen. */
  'profile.page.settings': 'Settings',
  /** Accessible name of the box with the avatar, handle and rank. */
  'profile.page.identityLabel': 'Your trader',
  /** Alt text of the chosen trader's avatar. Wolf, Oracle and Shark are names: never translated. */
  'profile.page.avatarAlt': '{persona, select, wolf {The Wolf, your chosen trader} oracle {The Oracle, your chosen trader} shark {The Shark, your chosen trader} other {Your chosen trader}}',
  /** Heading when the player has no handle, sign-in or trader yet. */
  'profile.page.makeItYours': 'Make it yours',
  'profile.page.choosePrompt': 'Choose who you play as.',
  'profile.page.start': 'Start my first day',
  'profile.page.progressTitle': 'Your progress',
  /** Link to the Career tab, followed by an arrow. */
  'profile.page.career': 'Career',
  'profile.page.progressStale': 'Progress couldn’t refresh.',
  'profile.page.retry': 'Retry',
  'profile.page.trimsEarned': 'Trims earned',
  /** Label under the streak count; the count is shown above it. */
  'profile.page.streakDays': '{days, plural, one {Day in a row} other {Days in a row}}',
  'profile.page.milestones': 'Milestones',
  /** Accessible name of the bar toward the next rank. {rank} is a rank name from the server. */
  'profile.page.rankProgress': 'Progress toward {rank}',
  /** {count} is already formatted; {rank} is a rank name from the server. */
  'profile.page.trimsToRank': '{count, plural, one {# more Trim to {rank}.} other {# more Trims to {rank}.}}',
  'profile.page.promotionMilestone': 'Finish your promotion milestone in Career.',
  'profile.page.nextRankReady': 'Your next rank is ready in Career.',
  /** At the top rank. {rank} is a rank name from the server. */
  'profile.page.topRank': '{rank}. Look how far you’ve come.',
  'profile.page.progressLoading': 'Loading your progress…',
  'profile.page.progressUnavailable': 'Your progress is unavailable.',
  'profile.page.careerStarts': 'Your career starts here.',
  'profile.page.progressUnchanged': 'Your saved progress has not changed.',
  'profile.page.firstMove': 'Make your first move and earn your first Trims.',

  // Trader choice (Profile editor, Settings row). Wolf, Oracle and Shark are names.
  'profile.trader.change': 'Change your trader',
  'profile.trader.choose': 'Choose your trader',
  'profile.trader.legend': 'Pick your trader',
  'profile.trader.question': 'Who will you play as?',
  'profile.trader.wolf': 'The Wolf',
  'profile.trader.wolfDescription': 'Bold. Fast. Loves a big move.',
  'profile.trader.oracle': 'The Oracle',
  'profile.trader.oracleDescription': 'Patient. Reads before moving.',
  'profile.trader.shark': 'The Shark',
  'profile.trader.sharkDescription': 'Calm when the crowd gets loud.',
  'profile.trader.saveError': 'Couldn’t save your trader. Your choice is still here. Try again.',
  'profile.trader.saving': 'Saving…',
  'profile.trader.save': 'Save trader',

  // Account and preferences (Profile tab and Settings).
  'profile.account.title': 'Account',
  'profile.account.signedInTitle': 'One account, every device',
  'profile.account.guestTitle': 'Keep your progress together',
  'profile.account.signedInBody': 'Use this same account on mobile for your trades, Trims and completed tasks.',
  'profile.account.guestBody': 'Sign in to pick up your trades and career on mobile.',
  'profile.account.signOut': 'Sign out',
  'profile.account.signIn': 'Sign in or create account',
  'profile.preferences.title': 'Preferences',
  'profile.preferences.motion': 'Character motion',
  'profile.preferences.motionHint': 'On this browser. Your device’s reduced-motion setting always applies.',
  'profile.preferences.help': 'Help & feedback',

  // Settings screen.
  /** Back link, after a left arrow. */
  'profile.settings.back': 'Back to Profile',
  'profile.settings.title': 'Settings',
  /** Row title; the button beside it uses the shared “Sign in”. */
  'profile.settings.signInTitle': 'Sign in',
  'profile.settings.signInHint': 'Sign in to keep your progress.',
  /** Google and X are names: never translated. */
  'profile.settings.signedInWith': '{method, select, email {Signed in with email} google {Signed in with Google} x {Signed in with X} other {Signed in}}',
  /** The player's @handle. */
  'profile.settings.handle': 'Handle',
  'profile.settings.trader': 'Your trader',
  'profile.settings.chooseCharacter': 'Choose a character',
  /** Short row buttons. */
  'profile.settings.change': 'Change',
  'profile.settings.choose': 'Choose',
  'profile.settings.open': 'Open',
  'profile.settings.reminders': 'Reminders',
  /** The saved reminder choice. Times may be written the way each language says them. */
  'profile.settings.remindersSaved': '{choice, select, daily {Once a day, around 7 PM. Saved on this browser.} occasional {Mon, Wed and Fri, around 7 PM. Saved on this browser.} off {Keep it quiet. Saved on this browser.} other {Saved on this browser.}}',
  'profile.settings.remindersNotSet': 'Not set on this browser.',
  'profile.settings.changeReminders': 'Change reminders',
  'profile.settings.addMoney': 'Add money',
  'profile.settings.addMoneyHint': 'See your deposit options.',
  'profile.settings.addMoneySignIn': 'Sign in to see your deposit options.',
  'profile.settings.sound': 'Sound',
  'profile.settings.soundHint': 'Sounds for key moments.',
  'profile.settings.animations': 'Animations',
  'profile.settings.animationsLimited': 'Limited by your device setting.',
  'profile.settings.animationsHint': 'Movement and celebrations.',
  'profile.settings.reduceMotion': 'Reduce motion',
  'profile.settings.reduceMotionOn': 'On. Follows your device setting.',
  'profile.settings.reduceMotionOff': 'Off. Follows your device setting.',
  'profile.settings.haptics': 'Haptics',
  'profile.settings.hapticsHint': 'Not available in a browser.',
  /** First-party usage events (counts only); turning it off forgets anything unsent. */
  'profile.settings.usage': 'Share usage data',
  'profile.settings.usageHint': 'Counts of which screens open and which steps finish, to make Trimmy better. No names, amounts or messages.',
  /** Section about practice (“paper”) money. */
  'profile.settings.paperSection': 'Paper',
  'profile.settings.paperLimit': 'Paper limit',
  'profile.settings.paperLimitUnavailable': 'Unavailable right now.',
  'profile.settings.supportSection': 'Support',
  'profile.settings.help': 'Help',
  'profile.settings.helpHint': 'Find @trimmyhq on X for help or feedback.',
  'profile.settings.helpLabel': 'Open help on X',
  'profile.settings.legalSection': 'Legal',
  'profile.settings.terms': 'Terms',
  'profile.settings.termsLabel': 'Open the terms',
  /** The privacy notice (legal document), not the comment privacy setting. */
  'profile.settings.privacyNotice': 'Privacy',
  'profile.settings.privacyNoticeLabel': 'Open the privacy notice',

  // Language selector. Language names are shown in their own language and never translated.
  'profile.language.title': 'Language',
  'profile.language.change': 'Change language',
  /** The option that follows the browser's languages. */
  'profile.language.browser': 'Browser language',
  /** Under “Browser language”. {language} is a language's own name, such as “Français”. */
  'profile.language.browserHint': 'Follows your browser: {language}',
  /** Row subtitle while following the browser. {language} is a language's own name. */
  'profile.language.browserCurrent': 'Browser language ({language})',
  'profile.language.notSaved': 'Your browser didn’t save this choice, so it only lasts for this visit.',
  /** {language} is a language's own name. */
  'profile.language.loadFailed': '{language} couldn’t load. Check your connection and try again.',

  // Paper reset.
  'profile.reset.row': 'Reset paper',
  'profile.reset.rowBusy': 'Resetting your paper desk.',
  'profile.reset.rowPending': 'Your confirmed reset is waiting to finish.',
  'profile.reset.rowHint': 'Clear paper trades and start again.',
  'profile.reset.finish': 'Finish reset',
  'profile.reset.open': 'Reset',
  'profile.reset.title': 'Reset your paper desk?',
  'profile.reset.body': 'This starts a fresh paper desk. Past receipts stay in your record. Your Career, Trims, rank, streak and money do not change.',
  /**
   * The phrase the player types to confirm. Lowercase, easy to type; outside
   * English, accents, capitals and apostrophe styles are not required.
   */
  'profile.reset.phrase': 'reset my paper desk',
  'profile.reset.phrasePrompt': 'Type “{phrase}” to continue.',
  /** Accessible name of the field. */
  'profile.reset.phraseLabel': 'Confirmation phrase. Type {phrase}.',
  'profile.reset.confirming': 'Resetting…',
  'profile.reset.confirm': 'Reset paper desk',
  'profile.reset.doneTitle': 'Paper desk reset',
  /** {amount} is already formatted, as in “10,000.00”. */
  'profile.reset.doneNewer': 'Newer trades were kept. Your balance is {amount} paper.',
  'profile.reset.done': 'Your desk is ready with {amount} paper.',
  'profile.reset.error.changed': 'Your paper desk changed. It was refreshed. Review it, then confirm the reset again.',
  'profile.reset.error.notNeeded': 'Your paper desk is already fresh. Nothing was cleared.',
  'profile.reset.error.offline': 'You are offline. Your exact reset request is saved for a safe retry.',
  'profile.reset.error.timeout': 'The reset took too long to confirm. Your exact request is saved for a safe retry.',
  'profile.reset.error.session': 'Your paper desk needs a fresh session before the reset can finish.',
  'profile.reset.error.rateLimited': 'Paper resets are limited. Try this saved request again later.',
  'profile.reset.error.unconfirmed': 'The reset could not be confirmed. Your exact request is saved for a safe retry.',
  'profile.reset.error.failed': 'Paper was not reset. Refresh your desk and try again.',

  // Comment privacy: who can see the reasons the player writes on stock pages.
  'profile.privacy.section': 'Privacy',
  /** Row title, dialog title and the options' group name. */
  'profile.privacy.title': 'Who can see my comments',
  'profile.privacy.change': 'Change who can see my comments',
  'profile.privacy.nobody': 'Nobody',
  'profile.privacy.everyone': 'Everyone',
  'profile.privacy.friends': 'Friends',
  'profile.privacy.now': '{visibility, select, nobody {Now: Nobody.} everyone {Now: Everyone.} friends {Now: Friends.} other {Now: {visibility}.}}',
  'profile.privacy.nobodyOption': 'Only you. This is the default.',
  'profile.privacy.everyoneOption': 'Anyone in Trimmy, on each stock page.',
  'profile.privacy.nobodyLine': 'Only you can see your comments.',
  'profile.privacy.everyoneLine': 'Anyone in Trimmy can see them on each stock page.',
  'profile.privacy.friendsLine': 'Only your Trimmy friends can see them on each stock page.',
  'profile.privacy.friendsUnavailable': 'Not available yet. Shares nothing until friends exist.',
  'profile.privacy.consent': 'Your comments and your handle will show on that stock’s page for anyone in Trimmy. Money never shows.',
  'profile.privacy.saving': '{visibility, select, nobody {Saving Nobody.} everyone {Saving Everyone.} friends {Saving Friends.} other {Saving {visibility}.}}',
  'profile.privacy.loading': 'Loading your choice.',
  'profile.privacy.needsRecovery': 'This guest desk needs recovery.',
  'profile.privacy.rateLimitedSave': '{seconds, plural, one {Too many changes. Try to save again in # second.} other {Too many changes. Try to save again in # seconds.}}',
  'profile.privacy.rateLimitedSaveSoon': 'Too many changes. Try to save again shortly.',
  'profile.privacy.rateLimitedLoad': '{seconds, plural, one {Too many changes. Try to load again in # second.} other {Too many changes. Try to load again in # seconds.}}',
  'profile.privacy.rateLimitedLoadSoon': 'Too many changes. Try to load again shortly.',
  'profile.privacy.offlineLoad': 'You are offline. Your choice could not load.',
  'profile.privacy.slowLoad': 'Your choice took too long to load.',
  'profile.privacy.sessionLoad': 'Your session needs a refresh before this can load.',
  'profile.privacy.accountClosed': 'This account is closed.',
  'profile.privacy.loadFailed': 'Your choice could not load.',
  /** {notSaved} is one of the two “not saved yet” sentences below. */
  'profile.privacy.offlineSave': 'You are offline. {notSaved}',
  'profile.privacy.slowSave': 'Saving took too long. {notSaved}',
  'profile.privacy.sessionSave': 'Your session needs a refresh. {notSaved}',
  'profile.privacy.saveFailed': 'Couldn’t save. {notSaved}',
  'profile.privacy.notSaved': '{visibility, select, nobody {Nobody is not saved yet.} everyone {Everyone is not saved yet.} friends {Friends is not saved yet.} other {{visibility} is not saved yet.}}',
  'profile.privacy.choiceNotSaved': 'Your choice is not saved yet.',
  'profile.privacy.accountClosedNotSaved': 'This account is closed. Nothing was saved.',
  'profile.privacy.unmatched': 'That save could not be matched. Choose again.',
  'profile.privacy.unavailable': 'Your choice is not available yet.',
  /** {line} is one of the four sentences describing who can see the comments. */
  'profile.privacy.saved': 'Saved. {line}',
  'profile.privacy.changedElsewhere': 'Changed on another device. Refreshed. {line}',

  // Account closure.
  'profile.closure.section': 'Account closure',
  /** Row title and both buttons. */
  'profile.closure.action': 'Close account',
  'profile.closure.rowHint': 'Review what happens to your records and wallet.',
  'profile.closure.title': 'Close your account?',
  'profile.closure.body': 'You will lose access to the saved account. Records that must be kept stay protected.',
  'profile.closure.wallet': 'If you funded a wallet, keep access to it first. Closing will not move its funds.',
  'profile.closure.error': 'Your account was not closed. Try again.',
  'profile.closure.closing': 'Closing…',
} as const satisfies AreaMessages<'profile'>;
