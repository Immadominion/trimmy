import type {AreaMessages} from '../types';

/**
 * The app shell: navigation, notices and empty pages around every screen,
 * the Desk (home) screen, its Desk additions, and the expired guest desk.
 * Rank labels, assignment titles and notes come from the API and stay as sent.
 */
export default {
  // Frame and navigation. The tab names follow the glossary (Desk, Market, Career, Profile).
  'shell.skipToContent': 'Skip to content',
  /** Accessible name of the Trimmy logo button, which opens the Desk tab. */
  'shell.nav.brandLabel': 'Trimmy desk',
  'shell.nav.label': 'Main navigation',
  'shell.nav.desk': 'Desk',
  'shell.nav.market': 'Market',
  'shell.nav.career': 'Career',
  'shell.nav.profile': 'Profile',
  /** A small chip under the logo while the account is in Real mode (own money). */
  'shell.nav.realMoney': 'Real money',
  /** The sidebar identity button when the player has no handle and no sign-in label yet. */
  'shell.nav.yourDesk': 'Your desk',
  /** While a saved sign-in is restored, before anything else shows. */
  'shell.opening': 'Opening Trimmy…',

  // Pages that replace the whole workspace.
  'shell.unconfigured.title': 'Your desk is almost ready.',
  'shell.unconfigured.body': 'Practice is unavailable here right now. Please try again later.',
  'shell.storageChanged.title': 'Your desk changed in another tab.',
  'shell.storageChanged.body': 'Reload to restore the latest desk before making another move.',
  'shell.storageChanged.reload': 'Reload your desk',
  /** Heading of the error box when the desk cannot load; the detail below it is shared error copy. */
  'shell.deskError.title': 'Your desk needs a moment.',

  // Notices above the current screen.
  'shell.pendingOrder.title': 'Let’s check your last order.',
  'shell.pendingOrder.body': 'The connection ended before its receipt arrived. Checking uses the same order so it won’t be placed twice.',
  'shell.pendingOrder.check': 'Check order',
  'shell.recovered': 'Your order is confirmed. The same receipt and updated desk are restored.',
  /** A workday answer was sent but its save was never confirmed. */
  'shell.workPending.title': 'Your assignment has an unconfirmed save.',
  'shell.workPending.check': 'Check saved work',
  'shell.fundingUnavailable': 'Adding money isn’t available on the web yet. You can keep practicing with free money.',
  /** The end-of-day story (clock-out) from an earlier day still needs to be confirmed. */
  'shell.dailyPending.title': 'Your earlier desk story needs confirmation.',
  'shell.dailyPending.check': 'Check clock-out',

  // Pages that need an account.
  /** Trades made with the player's own money (Real mode). */
  'shell.history.title': 'Your trades',
  'shell.history.body': 'Sign in to see the trades you made with your own money.',
  'shell.community.title': 'See what traders are saying',
  'shell.community.body': 'Sign in to join the Trimmy community.',

  // Career and workday tabs before the player has a desk.
  'shell.guest.careerTitle': 'Your career starts here.',
  'shell.guest.workTitle': 'Your first assignment awaits.',
  'shell.guest.body': 'Start a free practice desk to build your experience.',
  'shell.guest.start': 'Start practicing',

  // A workday that cannot open yet. {day} is the earlier workday number to finish first.
  'shell.work.locked': 'File day {day} to open this assignment.',
  'shell.work.backToCareer': 'Back to Career',
  'shell.work.opening': 'Opening your assignment…',
  'shell.work.failed': 'Your assignment couldn’t open.',

  /**
   * The chosen trader as Settings shows it. Wolf, Oracle and Shark are names
   * and are never translated; {name} is the same name, capitalized, for any
   * other value.
   */
  'shell.settings.persona': '{persona, select, wolf {The Wolf} oracle {The Oracle} shark {The Shark} other {The {name}}}',

  // Desk (home tab).
  'shell.desk.label': 'Your desk',
  'shell.desk.title': 'Your desk.',
  'shell.desk.saveDesk': 'Save your desk',
  /** Accessible name of the practice balance card. */
  'shell.desk.balanceLabel': 'Paper balance',
  /** Card heading when the full value of cash and positions is known. */
  'shell.desk.paperBalance': 'Your paper balance',
  /** Card heading when only the cash is known. */
  'shell.desk.paperCash': 'Your paper cash',
  'shell.desk.availableToPractice': 'Available to practice',
  'shell.desk.openPositions': 'Open positions',
  'shell.desk.pricesUpdating': 'Holding prices are updating.',
  'shell.desk.fastBuy': 'Fast buy',

  // Sal's note on the Desk. {rank} is the next rank's name as the API sends it.
  'shell.desk.salLabel': 'A note from Sal',
  'shell.desk.salTrims': '{count} Trims earned.',
  'shell.desk.salPositions': '{count, plural, one {# position on your desk.} other {# positions on your desk.}}',
  'shell.desk.salRoom': 'Room for your next move.',
  'shell.desk.salFirstCompany': 'Your first company awaits.',
  'shell.desk.salNextRank': '{count} more toward {rank}. See your next career step.',
  'shell.desk.salCareer': 'Your career, from your first move to today.',
  'shell.desk.salPositionsCopy': 'Take a closer look at what you own.',
  'shell.desk.salHistoryCopy': 'Your earlier moves are saved below. There’s more to explore.',
  'shell.desk.salFirstCopy': 'Pick a name you know. Get curious.',
  'shell.desk.seeCareer': 'See your career',
  'shell.desk.reviewPosition': 'Review a position',
  'shell.desk.exploreCompanies': 'Explore companies',
  'shell.desk.findFirstCompany': 'Find your first company',

  // Positions and recent moves on the Desk. {shares} is a formatted share count; {date} a short date.
  'shell.desk.positions': 'Your positions',
  'shell.desk.exploreMarket': 'Explore Market',
  'shell.desk.emptyHistoryTitle': 'A little room to explore.',
  'shell.desk.emptyFreshTitle': 'A fresh start.',
  'shell.desk.emptyHistoryBody': 'No open positions. Find a company that catches your eye.',
  'shell.desk.emptyFreshBody': 'Your companies will live here after your first move.',
  'shell.desk.positionShares': '{symbol} · {shares} shares',
  'shell.desk.valueUnavailable': 'Value unavailable',
  /** What the position cost in practice money. */
  'shell.desk.positionCost': 'Cost {amount} paper',
  'shell.desk.recentMoves': 'Recent moves',
  /** A past practice order; {name} is the company. */
  'shell.desk.moveTitle': '{action, select, buy {Bought {name}} other {Sold {name}}}',
  'shell.desk.moveDetail': '{shares} shares · {date}',

  // Desk additions.
  /** The inbox of notifications for signed-in accounts. */
  'shell.home.updates': 'Updates',
  /** Invitation while the player has not chosen Wolf, Oracle or Shark. */
  'shell.home.pickTrader': 'Pick your trader',
  'shell.home.pickTraderBody': 'Make this desk yours.',

  // A guest desk this browser can no longer open.
  'shell.guestRecovery.label': 'Guest desk recovery',
  'shell.guestRecovery.expiredTitle': 'Guest session expired',
  'shell.guestRecovery.endedTitle': 'Guest session ended',
  'shell.guestRecovery.expiredBody': 'Your guest records are preserved. This desk can no longer trade or be saved to an account.',
  'shell.guestRecovery.endedBody': 'Your guest records are preserved, but this browser can no longer open the desk.',
  'shell.guestRecovery.signInNote': 'Sign in to open your saved account. Your guest desk stays untouched.',
  'shell.guestRecovery.signInUnavailable': 'Sign-in is unavailable right now.',
  'shell.guestRecovery.startNewGuest': 'Start a new guest desk',
  'shell.guestRecovery.confirmTitle': 'Start fresh?',
  'shell.guestRecovery.confirmBody': 'This removes this browser’s access to your old desk. You can’t undo it.',
  'shell.guestRecovery.confirmWarning': 'Your balance, positions and history won’t move to the new desk.',
  'shell.guestRecovery.opening': 'Opening…',
  'shell.guestRecovery.startNew': 'Start a new desk',
  'shell.guestRecovery.keep': 'Keep this desk',
  'shell.guestRecovery.expiredFailed': 'Couldn’t start again. Your expired desk is still preserved.',
  'shell.guestRecovery.endedFailed': 'Couldn’t start again. Your old desk is still preserved.',
} as const satisfies AreaMessages<'shell'>;
