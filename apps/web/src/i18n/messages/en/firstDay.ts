import type {AreaMessages} from '../types';

/**
 * The first day (welcome, Sal's note, pick a company and an amount, review),
 * the mobile app prompt, sign-in, the first-order celebration, reminders, the
 * money choice and the "Welcome back" notice for a preserved guest desk.
 */
export default {
  /** Shared by several busy buttons while a choice is saved. */
  'firstDay.saving': 'Saving…',

  // The first day: the whole flow.
  /** Region label for the first-day screens. */
  'firstDay.screen.label': 'Your first day',
  /** The × button (accessible name). */
  'firstDay.skip': 'Skip first day',

  // Welcome.
  'firstDay.welcome.eyebrow': 'Sal’s saved you a seat.',
  'firstDay.welcome.title': 'Your first day starts here.',
  'firstDay.welcome.lede': 'Pick a company. Make a move.<br/>Find your feet on Wall Street.',
  'firstDay.welcome.start': 'Start my first day',
  'firstDay.welcome.explore': 'Take a look around',
  'firstDay.welcome.noSignIn': 'No sign-in needed.',

  // Sal's handwritten note. The blank line is kept on screen.
  'firstDay.note.eyebrow': 'A note from Sal',
  /** "The floor" is the trading floor. */
  'firstDay.note.title': 'Welcome to the floor.',
  'firstDay.note.body': 'Your first day starts with practice.\n\nPick a company. It’s free.',
  'firstDay.note.opening': 'Opening your desk…',

  // Pick a company and an amount of practice money ("paper").
  'firstDay.practice.eyebrow': 'Your first move',
  'firstDay.practice.title': 'Pick a company you know.',
  'firstDay.practice.lede': 'Start small. This one’s practice.',
  'firstDay.practice.loading': 'Finding companies…',
  'firstDay.practice.retryCompanies': 'Try companies again',
  'firstDay.practice.noCompanies': 'No companies are available just yet.',
  /** Label of the group of company buttons. */
  'firstDay.practice.companiesLabel': 'Choose a company',
  /** Accessible name of one company button: "Choose Apple". */
  'firstDay.practice.chooseCompany': 'Choose {name}',
  /** Shown under a company's name when its token symbol is unknown. */
  'firstDay.practice.symbolFallback': 'Stock token',
  'firstDay.practice.amountLabel': 'Amount to practice',
  'firstDay.practice.balanceUnavailable': 'Your paper balance is unavailable.',
  /** {cash} and {minimum} are amounts of practice money, already formatted. */
  'firstDay.practice.balanceTooLow': '{cash} paper available. You need at least {minimum} paper to practice.',
  /** {cash}, {minimum} and {maximum} are amounts of practice money, already formatted. */
  'firstDay.practice.balanceRange': '{cash} paper available. Practice with {minimum} to {maximum} paper.',
  'firstDay.practice.refreshDesk': 'Refresh your desk',
  'firstDay.practice.preparing': 'Getting ready…',
  'firstDay.practice.review': 'Review paper buy',
  'firstDay.practice.disclosure': 'You’ll review your quote before confirming. No real money moves.',

  // Review the quote.
  /** Eyebrow above the review when the company's name is not known. */
  'firstDay.review.companyFallback': 'your company',
  'firstDay.review.title': 'Review your first move.',
  'firstDay.review.token': 'Company token',
  'firstDay.review.shares': 'Shares',
  'firstDay.review.price': 'Price per share',
  'firstDay.review.fees': 'Fees',
  'firstDay.review.spend': 'Paper to spend',
  'firstDay.review.cashAfter': 'Paper cash after',
  'firstDay.review.confirming': 'Confirming…',
  'firstDay.review.confirm': 'Confirm paper buy',
  /** A countdown, updated every second. */
  'firstDay.review.expiresIn': 'Quote expires in {seconds}s',
  'firstDay.review.expired': 'Quote expired. Get a new review.',
  'firstDay.review.edit': 'Edit amount',

  // An order whose result is not known yet.
  'firstDay.pending.title': 'Your last order needs checking.',
  'firstDay.pending.body': 'Return to your desk to recover its result before making another move.',
  'firstDay.pending.check': 'Check from desk',
  'firstDay.receipt.refreshing': 'Your order is confirmed. Your desk is still refreshing.',

  // The mobile app prompt (welcome and profile).
  'firstDay.mobile.title': 'Better on mobile.',
  'firstDay.mobile.body': 'Get Trimmy on your phone for the full experience.',
  'firstDay.mobile.download': 'Download for Android',
  'firstDay.mobile.apk': 'APK download',
  'firstDay.mobile.soon': 'Download coming soon',
  /** Link to Trimmy's X account. */
  'firstDay.mobile.updates': 'Launch updates',

  // Sign-in.
  /** Region label of the sign-in screen. */
  'firstDay.signIn.label': 'Sign in',
  'firstDay.signIn.close': 'Close sign in',
  /** The email method's name under its icon, beside "Google" and "X". */
  'firstDay.signIn.methodEmail': 'email',
  'firstDay.signIn.continueWithEmail': 'Continue with email',
  'firstDay.signIn.continueWithGoogle': 'Continue with Google',
  'firstDay.signIn.continueWithX': 'Continue with X',
  'firstDay.signIn.title.gate': 'Your desk awaits.',
  'firstDay.signIn.title.expiredGuest': 'Sign in to Trimmy.',
  'firstDay.signIn.title.returning': 'Welcome back.',
  'firstDay.signIn.title.save': 'Make this desk yours.',
  'firstDay.signIn.title.new': 'Your seat’s waiting.',
  'firstDay.signIn.lede.gate': 'Sign in or create your account.',
  'firstDay.signIn.lede.expiredGuest': 'Open your account desk. The expired guest desk stays separate.',
  'firstDay.signIn.lede.save': 'Save your progress. Pick up on any device.',
  'firstDay.signIn.lede.new': 'Sign in and settle back in.',
  'firstDay.signIn.expiredNotice': 'Closing sign-in keeps the expired guest desk preserved.',
  'firstDay.signIn.lastUsed': 'Last used on this browser',
  'firstDay.signIn.guest': 'Continue as guest',
  'firstDay.signIn.guestError': 'Couldn’t save your choice. Try again.',
  /** Divider above the other sign-in methods' icons. */
  'firstDay.signIn.divider': 'or continue with',
  'firstDay.signIn.unavailable': 'Sign-in isn’t available here yet.',
  'firstDay.signIn.authenticating': 'Opening secure sign-in…',
  'firstDay.signIn.retrySignOut': 'Try signing out again',
  // An account that already has a desk.
  'firstDay.signIn.choice.title': 'Your saved desk is waiting.',
  'firstDay.signIn.choice.expired': 'This guest session has expired. Open your account to pick up where you left off.',
  'firstDay.signIn.choice.exists': 'There’s already a desk on this account. Your guest progress stays in this browser.',
  'firstDay.signIn.choice.open': 'Open my account',
  'firstDay.signIn.choice.keepGuest': 'Keep this guest desk',
  // Waiting.
  'firstDay.signIn.signingOut': 'See you soon.',
  'firstDay.signIn.opening': 'Opening your desk.',
  'firstDay.signIn.restoring': 'Restoring your progress…',
  'firstDay.signIn.moment': 'Just a moment…',
  // The emailed code.
  'firstDay.signIn.code.title': 'Check your inbox.',
  'firstDay.signIn.code.sentTo': 'Enter the code sent to <strong>{email}</strong>.',
  'firstDay.signIn.code.label': 'Your six-digit code',
  'firstDay.signIn.code.signingIn': 'Signing in…',
  /** A countdown, updated every second. */
  'firstDay.signIn.code.resendIn': 'Send again in {seconds}s',
  'firstDay.signIn.code.resend': 'Send a new code',
  'firstDay.signIn.code.otherEmail': 'Use a different email',
  // The email address.
  'firstDay.signIn.email.title': 'Your email. Your desk.',
  'firstDay.signIn.email.lede': 'We’ll send a code. No password to remember.',
  'firstDay.signIn.email.label': 'Email address',
  /** Example address in the empty field. Keep the example.com domain. */
  'firstDay.signIn.email.placeholder': 'you@example.com',
  'firstDay.signIn.email.sending': 'Sending your code…',
  'firstDay.signIn.email.otherWays': 'Other ways to sign in',
  // Sign-in errors, by error code.
  'firstDay.signIn.error.emailInvalid': 'Enter a valid email address.',
  'firstDay.signIn.error.codeInvalid': 'That code didn’t work. Check it and try again.',
  'firstDay.signIn.error.codeSendFailed': 'We couldn’t send the code. Try again in a moment.',
  'firstDay.signIn.error.commitPending': 'Check your last order from your desk before signing in.',
  'firstDay.signIn.error.profilePending': 'Finish saving your desk before signing in.',
  'firstDay.signIn.error.workdayPending': 'Check your saved assignment in Career before signing in.',
  /** The clock-out ends a workday on the desk. */
  'firstDay.signIn.error.dailyDeskPending': 'Check your earlier clock-out before signing in.',
  'firstDay.signIn.error.claimPending': 'Use the same sign-in method to finish saving this desk.',
  'firstDay.signIn.error.storage': 'Allow browser storage to keep your desk, then try again.',
  'firstDay.signIn.error.signOutFailed': 'Sign-out didn’t finish. Please try again.',
  'firstDay.signIn.error.generic': 'Sign-in couldn’t finish. Your progress is safe. Please try again.',

  // The first-order celebration.
  /** Region label. */
  'firstDay.order.label': 'Your first order',
  'firstDay.order.opening': 'Opening your trade',
  'firstDay.order.loadFailed': 'Couldn’t load your trade',
  'firstDay.order.loading': 'Opening your first stock…',
  'firstDay.order.retryLede': 'Try again to see your confirmed order.',
  'firstDay.order.title': 'You’ve placed your first order!',
  'firstDay.order.lede': 'Now let’s create your trader profile.',
  /** Shown on the ticket, and the accessible name of its check mark. */
  'firstDay.order.buyConfirmed': 'Buy confirmed',
  'firstDay.order.invested': 'Invested',
  /** {shares} is a number of shares, already formatted. */
  'firstDay.order.shares': 'Shares <strong>{shares}</strong>',
  /** {rank} is the rank's name from the server; {trims} a count of points. */
  'firstDay.order.reward': '{rank} · {trims} Trims total',
  'firstDay.order.continueError': 'Couldn’t continue. Try again.',
  'firstDay.order.disclosure': 'Confirmed paper order. No real money moved.',

  // Reminders (first day and Settings). The schedule matches the calendar file.
  'firstDay.reminders.label': 'Reminders',
  'firstDay.reminders.close': 'Close reminders',
  'firstDay.reminders.skip': 'Skip reminders',
  'firstDay.reminders.title': 'A little nudge?',
  'firstDay.reminders.lede': 'How often would you like a reminder?',
  'firstDay.reminders.frequency': 'Reminder frequency',
  'firstDay.reminders.daily': 'Once a day',
  /** 7 PM in the reader's own time zone; write the time naturally. */
  'firstDay.reminders.dailyCaption': 'Around 7 PM, your time.',
  'firstDay.reminders.occasional': 'A few times a week',
  /** Monday, Wednesday and Friday at 7 PM local time. */
  'firstDay.reminders.occasionalCaption': 'Mon, Wed and Fri, around 7 PM.',
  'firstDay.reminders.off': 'Keep it quiet',
  'firstDay.reminders.offCaption': 'I’ll come back on my own.',
  'firstDay.reminders.saved': 'Your preference is saved. Browsers can’t send Trimmy reminders while it’s closed, so add it to your calendar.',
  'firstDay.reminders.addToCalendar': 'Add to calendar',
  'firstDay.reminders.calendarError': 'Couldn’t create the calendar file. Try again.',
  'firstDay.reminders.saveError': 'Couldn’t save that. Try again.',

  // Practice money or fund the wallet.
  /** Region label. */
  'firstDay.money.label': 'Your next move',
  'firstDay.money.title': 'Your next move.',
  'firstDay.money.lede': 'Keep finding your feet, or fund your wallet.',
  /** The choice, and the accessible name of the × button that makes it. */
  'firstDay.money.keepFree': 'Keep using free money',
  'firstDay.money.keepFreeCaption': 'Build your confidence on the desk.',
  'firstDay.money.add': 'Add money',
  'firstDay.money.addCaption': 'See your deposit options.',
  'firstDay.money.footnote': 'You can add money from your desk any time.',
  'firstDay.money.error': 'Your trade is safe. Try continuing again.',

  // An existing account whose guest desk stayed separate.
  /** Heading and region label. */
  'firstDay.preserved.title': 'Welcome back',
  'firstDay.preserved.lede': 'Your saved trades and progress are ready.',
  'firstDay.preserved.expired': 'Your expired guest desk is preserved separately. It can no longer trade or merge.',
  'firstDay.preserved.separate': 'Your guest trades stay separate. Sign out to return to that desk.',
  'firstDay.preserved.go': 'Go to my desk',
} as const satisfies AreaMessages<'firstDay'>;
