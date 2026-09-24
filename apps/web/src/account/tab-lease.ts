export interface AccountLease {release(): void}
export interface ExclusiveLockPort {
  request(name: string, options: {mode: 'exclusive'; signal: AbortSignal}, callback: (lock: unknown) => Promise<void>): Promise<unknown>;
}
export class AccountLeaseError extends Error {
  constructor(readonly code: 'WATCHLIST_TAB_BUSY' | 'WATCHLIST_TAB_UNAVAILABLE' | 'WATCHLIST_SESSION_CHANGED') {
    super(code);
    this.name = 'AccountLeaseError';
  }
}

/** One cooperating tab owns an account's local queue. Close the session before
 * releasing this lease, so its late responses cannot write into the next owner.
 * Web Locks coordinate tabs/workers on this origin; the server still uses CAS. */
export function acquireAccountLease(subject: string, options: {
  readonly locks: ExclusiveLockPort | undefined;
  readonly signal: AbortSignal;
  readonly timeoutMs?: number;
}): Promise<AccountLease> {
  const {locks, signal} = options;
  if (!/^did:privy:[A-Za-z0-9]{1,128}$/.test(subject)) return Promise.reject(new AccountLeaseError('WATCHLIST_SESSION_CHANGED'));
  if (signal.aborted) return Promise.reject(new AccountLeaseError('WATCHLIST_SESSION_CHANGED'));
  if (!locks) return Promise.reject(new AccountLeaseError('WATCHLIST_TAB_UNAVAILABLE'));
  return new Promise<AccountLease>((resolve, reject) => {
    const waiting = new AbortController();
    let timedOut = false;
    let acquired = false;
    const abort = () => waiting.abort();
    signal.addEventListener('abort', abort, {once: true});
    const timer = setTimeout(() => {timedOut = true; waiting.abort();}, options.timeoutMs ?? 1000);
    const cleanup = () => {clearTimeout(timer); signal.removeEventListener('abort', abort);};
    void Promise.resolve().then(() => locks.request(`trimmy.watchlist.v1.${subject}`, {mode: 'exclusive', signal: waiting.signal}, async lock => {
      cleanup();
      if (!lock || signal.aborted || waiting.signal.aborted) throw new AccountLeaseError('WATCHLIST_SESSION_CHANGED');
      acquired = true;
      await new Promise<void>(release => resolve(Object.freeze({release})));
    })).catch(() => {
      cleanup();
      if (!acquired) reject(new AccountLeaseError(signal.aborted ? 'WATCHLIST_SESSION_CHANGED' : timedOut ? 'WATCHLIST_TAB_BUSY' : 'WATCHLIST_TAB_UNAVAILABLE'));
    });
  });
}
