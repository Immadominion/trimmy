/**
 * MERGE POINT — fund wallet.
 *
 * The deposit sheet (crypto deposit: the wallet's Solana receive address and QR
 * for USDC, SOL for fees; card funding "Coming soon") is built in the separate
 * money-mode worktree. This module is the single call site the first-day
 * "Add money" choice (and later Desk or Settings) uses to open it.
 *
 * To wire it at merge: have the deposit sheet's host call
 * `registerFundWalletOpener(source => openDepositSheet(source))` once it is
 * mounted (or replace the body of `openFundWallet`). Callers already make sure
 * the person is signed in first, as mobile's `_openFunding` does.
 *
 * Until then `openFundWallet` returns false and callers say plainly that
 * deposits are not open on the web yet. It never pretends a deposit started.
 */
export type FundWalletSource = 'first-day' | 'desk' | 'settings';
export type FundWalletOpener = (source: FundWalletSource) => void;

let opener: FundWalletOpener | null = null;

export function registerFundWalletOpener(next: FundWalletOpener | null): () => void {
  opener = next;
  return () => {if (opener === next) opener = null;};
}

/** Opens the deposit sheet. Returns false when it is not available in this build. */
export function openFundWallet(source: FundWalletSource): boolean {
  if (!opener) return false;
  opener(source);
  return true;
}
