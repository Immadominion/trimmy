import type {AreaMessages} from '../types';

/**
 * Words and sentences several screens share. Areas keep their own copy even
 * when the English matches, whenever the context could need different words
 * in another language; only truly generic actions live here.
 */
export default {
  'common.appTitle': 'Trimmy | Your practice desk',
  'common.tryAgain': 'Try again',
  'common.dismiss': 'Dismiss',
  'common.signIn': 'Sign in',
  'common.continue': 'Continue',
  'common.cancel': 'Cancel',
  'common.save': 'Save',
  'common.done': 'Done',
  'common.checking': 'Checking…',
  'common.unavailable': 'Unavailable',
  /** Shown where a figure is unknown. */
  'common.noValue': '—',
  /** Practice money, as a unit after an amount: "100.00 paper". */
  'common.paperUnit': 'paper',
  'common.paperAmount': '{amount} paper',
  /** Large numbers in short form: "1.2K", "3.4M", "1.2B", "1.5T". {value} is already formatted. */
  'common.compactThousand': '{value}K',
  'common.compactMillion': '{value}M',
  'common.compactBillion': '{value}B',
  'common.compactTrillion': '{value}T',
  'common.loadingDesk': 'Loading your desk…',
  'common.loadFailed': 'We couldn’t load this just yet.',
  'common.salArtAlt': 'Sal, your Wall Street mentor, beside a purple office chair',
  /** Shared error copy for practice requests, by error code. */
  'common.error.storage': 'Allow browser storage to keep this desk and its orders safe, then try again.',
  'common.error.lock': 'Use a browser with secure tab coordination, such as current Chrome, to keep paper orders safe.',
  'common.error.sessionChanged': 'Your desk changed in another tab. Reload this page before continuing.',
  'common.error.previewExpired': 'This quote expired. Get a new review before confirming.',
  'common.error.sessionEnded': 'This session is no longer available. Your saved desk has not been replaced.',
  'common.error.cashInsufficient': 'This amount is more than the paper cash available.',
  'common.error.positionInsufficient': 'Your position changed. Refresh your desk before selling.',
  'common.error.portfolioChanged': 'Your desk changed. Refresh it and review a new quote.',
  'common.error.rateLimited': 'A few too many requests. Give it a moment, then try again.',
  'common.error.pending': 'An earlier order still needs checking. Return to your desk to recover it first.',
  'common.error.price': 'A current paper quote isn’t available for this token. Try another company or come back later.',
  'common.error.network': 'Check your connection and try again. Your saved desk is unchanged.',
} as const satisfies AreaMessages<'common'>;
