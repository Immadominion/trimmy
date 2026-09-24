import type { ReactNode } from 'react';
import { formatClockTime, formatRawUnits, shortenAddress } from './account-amounts';
import type { AccountContextSnapshot, AccountHoldingsSnapshot } from './account-data-models';
import type { AccountPortfolioIssue, AccountPortfolioState } from './account-portfolio';
import type { AccountPortfolioLifecycleView } from './use-account-portfolio';

export interface AccountPortfolioPanelProps {
  readonly auth: Readonly<{enabled: boolean; ready: boolean; authenticated: boolean; errorCode: string | null}>;
  readonly portfolio: AccountPortfolioLifecycleView;
}

const RETRY_ISSUES = new Set<string>([
  'ACCOUNT_DATA_ACCOUNT_CHANGED', 'ACCOUNT_DATA_TOKEN_UNAVAILABLE', 'ACCOUNT_CONTEXT_UNAUTHENTICATED',
  'ACCOUNT_HOLDINGS_UNAUTHENTICATED', 'ACCOUNT_DATA_CLOSED', 'ACCOUNT_PORTFOLIO_WALLET_CHANGED',
]);

const NOT_CONFIGURED_ISSUES = new Set<string>(['ACCOUNT_CONTEXT_UNAVAILABLE', 'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED']);

function issueMessage(issue: AccountPortfolioIssue | string | null): string {
  switch (issue) {
    case 'ACCOUNT_CONTEXT_UNAVAILABLE':
    case 'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED': return 'Account details are not available on this server yet.';
    case 'ACCOUNT_HOLDINGS_WALLET_MISSING': return 'No wallet is linked to this account yet.';
    case 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS': return 'This account has more than one wallet, so balances are not shown.';
    case 'ACCOUNT_PORTFOLIO_WALLET_CHANGED': return 'The linked wallet changed. Try again.';
    case 'ACCOUNT_DATA_TOKEN_UNAVAILABLE':
    case 'ACCOUNT_CONTEXT_UNAUTHENTICATED':
    case 'ACCOUNT_HOLDINGS_UNAUTHENTICATED':
    case 'ACCOUNT_DATA_ACCOUNT_CHANGED':
    case 'ACCOUNT_DATA_CLOSED': return 'Sign in again to see your account.';
    case 'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED':
    case 'ACCOUNT_PORTFOLIO_OBSERVATION_IN_FUTURE': return 'The last check is out of date.';
    default: return 'Your account could not be checked.';
  }
}

function checkedAt(state: AccountPortfolioState): string {
  const time = state.portfolio ? formatClockTime(state.portfolio.holdings.holdings.observedAt) : null;
  return time ?? 'an unknown time';
}

function ContextRows({context}: {context: AccountContextSnapshot}) {
  const wallet = context.embeddedSolanaWallet;
  const x = context.xIdentity;
  return <>
    {wallet.status === 'candidate' && <div><dt>Wallet</dt><dd><span aria-label={`Wallet address ${wallet.address}`}>{shortenAddress(wallet.address)}</span></dd></div>}
    {x.status === 'verified' && <div><dt>X</dt><dd>@{x.usernameSnapshot}</dd></div>}
  </>;
}

function BalanceRows({holdings}: {holdings: AccountHoldingsSnapshot}) {
  const balances = holdings.holdings.balances;
  const sol = formatRawUnits(balances.nativeSol.amountRaw, 9) ?? 'Unavailable';
  const usdc = formatRawUnits(balances.usdc.amountRaw, balances.usdc.decimals) ?? 'Unavailable';
  const aaplxRecorded = balances.aaplx.amountRaw !== '0';
  return <>
    <div><dt>SOL</dt><dd>{sol}</dd></div>
    <div><dt>USDC</dt><dd>{usdc}</dd></div>
    {balances.usdc.hasFrozenAccounts && <p className="account-note">Some USDC is in a frozen account.</p>}
    {balances.usdc.accountCount > 1 && <p className="account-note">USDC is held in {balances.usdc.accountCount} accounts.</p>}
    <div><dt>AAPLx</dt><dd>{aaplxRecorded ? 'Amount not confirmed' : 'None'}</dd></div>
    {aaplxRecorded && <p className="account-note">AAPLx is recorded on this wallet. Its share amount is not confirmed yet.</p>}
  </>;
}

/**
 * Read-only account section for the Portfolio view. It renders the server's
 * last observation for the verified account exactly as received: balances
 * without prices, explicit freshness, and no mixing with the sample workspace.
 */
export function AccountPortfolioPanel({auth, portfolio}: AccountPortfolioPanelProps) {
  if (!auth.enabled) return null;
  const {binding, snapshot, errorCode, refresh, retry} = portfolio;
  let status: string;
  let rows: ReactNode = null;
  let action: ReactNode = null;
  if (!auth.ready) {
    status = 'Connecting sign-in…';
  } else if (!auth.authenticated) {
    status = 'Sign in to see the wallet linked to your account.';
  } else if (!binding) {
    status = 'Your account will be checked once it is verified.';
  } else if (!snapshot) {
    status = errorCode ? issueMessage(errorCode) : 'Checking your account…';
    if (errorCode && RETRY_ISSUES.has(errorCode)) action = <button onClick={() => {retry();}}>Try again</button>;
  } else {
    const retained = snapshot.portfolio;
    const canRefresh = snapshot.phase !== 'loading' && snapshot.phase !== 'offline' &&
      snapshot.phase !== 'accountChanged' && snapshot.phase !== 'closed';
    switch (snapshot.phase) {
      case 'loading': status = retained ? 'Checking again…' : 'Checking your account…'; break;
      case 'ready': status = `Checked at ${checkedAt(snapshot)}.`; break;
      case 'stale': status = retained ? `Checked at ${checkedAt(snapshot)}. This may have changed.` : 'The last check is out of date.'; break;
      case 'offline':
        // A server without the account adapter answers 503; that is not the
        // browser being offline, so say what is actually missing.
        status = snapshot.issue !== null && NOT_CONFIGURED_ISSUES.has(snapshot.issue) ? issueMessage(snapshot.issue)
          : retained ? `You're offline. This is what we saw at ${checkedAt(snapshot)}.` : "You're offline. Your account will be checked when you're back online.";
        break;
      case 'cancelled': status = 'The check was paused.'; break;
      case 'idle': status = 'Your account has not been checked yet.'; break;
      case 'error': status = issueMessage(snapshot.issue); break;
      case 'accountChanged':
      case 'closed': status = 'Sign in again to see your account.'; break;
    }
    const terminal = snapshot.issue !== null && RETRY_ISSUES.has(snapshot.issue);
    if (snapshot.phase !== 'accountChanged' && snapshot.phase !== 'closed') {
      rows = <dl className="account-rows">
        {snapshot.context && <ContextRows context={snapshot.context}/>}
        {retained && <BalanceRows holdings={retained.holdings}/>}
      </dl>;
    }
    if (terminal) action = <button onClick={() => {retry();}}>Try again</button>;
    else if (canRefresh) action = <button onClick={() => {refresh();}}>Check again</button>;
  }
  return <section className="account-portfolio" aria-labelledby="account-portfolio-title">
    <div className="account-portfolio-heading"><h2 id="account-portfolio-title">Your account</h2><span className="read-only-pill">Read-only</span></div>
    <p role="status">{status}</p>
    {rows}
    {action && <div className="account-actions">{action}</div>}
    <p className="account-note">Balances only. No prices, no buying or selling.</p>
  </section>;
}
