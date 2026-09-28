/**
 * Opens the Add money sheet (crypto deposit; card funding "Coming soon") from
 * the first day's "Add money" choice, the Desk or Settings. The money side
 * registers the opener while own money is available (ProductApp); callers make
 * sure the person is signed in first, as mobile's `_openFunding` does. With no
 * opener, `openFundWallet` returns false and callers say plainly that adding
 * money isn't open here. It never pretends a deposit started.
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
