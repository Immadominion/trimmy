import { STOCKS } from '../fixtures';
import type { useAccountWatchlist } from './use-account-watchlist';

export function AccountBar({account, guestIds, scope = 'sample'}: {
  account: ReturnType<typeof useAccountWatchlist>; guestIds: readonly string[]; scope?: 'account' | 'sample';
}) {
  const {auth, snapshot, error} = account;
  if (!auth.enabled && !auth.errorCode) return null;
  const description = !auth.ready ? 'Connecting sign-in…' : !auth.authenticated
    ? auth.errorCode ? 'Sign-in is unavailable. Your local workspace is ready.' : 'Sign in to save your watchlist across devices.'
    : error === 'WATCHLIST_TAB_BUSY' ? 'Your account is open in another tab. Close it there, then try again.'
    : error === 'WATCHLIST_TAB_UNAVAILABLE' ? 'This browser cannot open a shared account save. Try another supported browser.'
    : error === 'WATCHLIST_CHANGE_FAILED' ? 'That change could not be saved. Your previous list is still here.'
    : error ? 'Your account could not be opened. Try again.'
    : !snapshot ? 'Opening your account watchlist…'
    : ({saved: 'Watchlist saved to your account.', local: 'Saved in this browser. Waiting to sync.', syncing: 'Saving your watchlist…', offline: 'Saved in this browser. Sync will try again.', conflict: 'Your watchlist changed on another device. Both versions are kept.', protected: 'Saved data needs attention. Your existing copy is protected.', loginRequired: 'Sign out and reconnect to continue account sync.', closed: 'Account disconnected.'})[snapshot.status];
  const liveDescription = !auth.ready ? 'Connecting sign-in…' : !auth.authenticated
    ? auth.errorCode ? 'Sign-in is unavailable. You can still explore stocks.' : 'Sign in to see your linked wallet.'
    : error || snapshot?.status === 'loginRequired' ? 'Your account needs attention. Try again or sign out and reconnect.'
    : 'Your account is connected.';
  const names = (ids: readonly string[]) => ids.length ? ids.map(id => STOCKS.find(stock => stock.id === id)?.name ?? id).join(', ') : 'Empty watchlist';
  return <section className="account-bar" aria-label="Your account">
    <p role="status">{scope === 'sample' ? <>Sample watchlist: {description}</> : liveDescription}</p>
    <div className="account-actions">
      {!auth.authenticated && auth.enabled && <button disabled={!auth.ready || auth.busy} onClick={auth.login}>Continue with X</button>}
      {auth.authenticated && <>
        {(error || snapshot?.status === 'offline' || snapshot?.status === 'protected' || snapshot?.status === 'loginRequired') && <button onClick={account.retry}>Try again</button>}
        {scope === 'sample' && snapshot?.status === 'saved' && snapshot.assetIds.length === 0 && guestIds.length > 0 && <button onClick={() => account.setAssetIds(guestIds)}>Add my local watchlist</button>}
        <button disabled={auth.busy} onClick={() => {void auth.logout();}}>Sign out</button>
      </>}
    </div>
    {scope === 'sample' && snapshot?.status === 'conflict' && <div className="account-conflict">
      <p><strong>In this browser:</strong> {names(snapshot.assetIds)}</p>
      <p><strong>In your account:</strong> {names(snapshot.conflictAssetIds ?? [])}</p>
      <div className="account-actions"><button onClick={account.useLocal}>Keep this browser’s list</button><button onClick={account.useRemote}>Use my account’s list</button></div>
    </div>}
  </section>;
}
