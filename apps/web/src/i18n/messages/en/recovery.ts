import type {AreaMessages} from '../types';

/**
 * The /wallet-recovery page: a separate page where an account holder signs in
 * with Privy and opens the recovery key of their Trimmy Solana wallet.
 */
export default {
  'recovery.documentTitle': 'Trimmy | Wallet recovery',
  'recovery.eyebrow': 'Your wallet, with you',
  'recovery.title': 'Keep access to<br/>your wallet.',
  /** {link} is the @trimmyhq link on X. */
  'recovery.footer': 'Need help? {link}<br/>Never send support a key or sign-in code.',

  // Opening the page.
  'recovery.invalidLink': 'This recovery link isn’t valid. Open wallet recovery from Trimmy in your browser.',
  'recovery.unavailable': 'Wallet recovery isn’t available here. Please try again later.',
  'recovery.opening': 'Opening wallet recovery…',
  'recovery.loadFailed': 'Wallet recovery couldn’t load. Reopen this page from Trimmy.',

  // Signing in. The Privy texts appear inside Privy's sign-in window.
  'recovery.account.opening': 'Opening your account…',
  'recovery.account.failed': 'Your account couldn’t load. Reopen this page to try again.',
  'recovery.signIn.intro': 'Sign in the same way you do in Trimmy. Then choose your wallet to open its recovery key in Privy.',
  'recovery.signIn.button': 'Sign in to Trimmy',
  'recovery.signIn.failed': 'Sign-in couldn’t open. Try again.',
  'recovery.privy.landingHeader': 'Sign in to Trimmy',
  'recovery.privy.loginMessage': 'Use the same account as your Trimmy app.',

  // Choosing the wallet and opening its key.
  'recovery.wallet.intro': 'Use your recovery key to import this same wallet into another compatible Solana wallet.',
  'recovery.wallet.mismatchTitle': 'This isn’t the matching account.',
  'recovery.wallet.mismatchBody': 'Sign in with the account you use for this wallet in Trimmy.',
  'recovery.wallet.none': 'No Trimmy Solana wallet is linked to this account.',
  'recovery.wallet.chooseLabel': 'Choose a Solana wallet',
  'recovery.wallet.solana': 'Solana wallet',
  /** On the chosen wallet. */
  'recovery.wallet.selected': 'Selected',
  'recovery.wallet.keyNote': 'Your key controls your funds. Keep it private. Privy displays it in a separate secure window; Trimmy does not receive it.',
  'recovery.wallet.wait': 'Please wait…',
  'recovery.wallet.openKey': 'Open recovery key',
  'recovery.wallet.windowClosed': 'Recovery window closed. You can reopen it if needed.',
  'recovery.wallet.windowFailed': 'The recovery window couldn’t open. Try again.',
  'recovery.wallet.switchAccount': 'Switch account',
  'recovery.wallet.signingOut': 'Signing out…',
  'recovery.wallet.signOutFailed': 'Couldn’t sign out. Try again.',
} as const satisfies AreaMessages<'recovery'>;
