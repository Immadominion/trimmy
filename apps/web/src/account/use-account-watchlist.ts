import { useCallback, useEffect, useRef, useState } from 'react';
import { usePracticeAccountAuth } from './privy-provider';
import { acquireAccountLease } from './tab-lease';
import type { AccountLease } from './tab-lease';
import { WatchlistSession } from './watchlist-sync';
import type { WatchlistView } from './watchlist-sync';
import { useAccountPortfolio } from './use-account-portfolio';

export function useAccountWatchlist() {
  const auth = usePracticeAccountAuth();
  const authRef = useRef(auth);
  authRef.current = auth;
  const [retry, setRetry] = useState(0);
  const [state, setState] = useState<{subject: string; apiOrigin: string; verificationEpoch: number;
    value: WatchlistView | null; error: string | null} | null>(null);
  const owner = useRef<{subject: string; apiOrigin: string; session: WatchlistSession; schedule(): void} | null>(null);
  const verificationSequence = useRef(0);

  useEffect(() => {
    const {subject, apiOrigin} = auth;
    if (!subject || !apiOrigin) return;
    const cancelled = new AbortController();
    let lease: AccountLease | undefined;
    let session: WatchlistSession | undefined;
    let unsubscribe: (() => void) | undefined;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let running = false;
    let again = false;
    let failures = 0;
    let verificationEpoch = 0;
    const current = () => !cancelled.signal.aborted && authRef.current.subject === subject && authRef.current.apiOrigin === apiOrigin;
    const publish = () => {
      if (current() && session) setState({subject, apiOrigin, verificationEpoch,
        value: session.getSnapshot(), error: null});
    };
    const schedule = (delay = 350) => {
      if (!current() || document.hidden || !session || ['protected', 'conflict', 'loginRequired', 'closed'].includes(session.getSnapshot().status)) return;
      if (running) {again = true; return;}
      clearTimeout(timer);
      timer = setTimeout(() => {void sync();}, delay);
    };
    const sync = async () => {
      if (!session || !current() || document.hidden || running) return;
      running = true;
      let succeeded = false;
      try {await session.synchronize(); succeeded = true; failures = 0;}
      catch { /* The session exposes only fixed, actionable status codes. */ }
      finally {
        running = false;
        if (!current()) return;
        const status = session.getSnapshot().status;
        if (status === 'offline' && failures < 2) schedule([1000, 4000][failures++]!);
        else if (succeeded && (again || status === 'local')) {again = false; schedule();}
      }
    };
    const wake = () => {
      if (document.hidden) {clearTimeout(timer); return;}
      failures = 0;
      schedule(0);
    };
    setState({subject, apiOrigin, verificationEpoch: 0, value: null, error: null});
    document.addEventListener('visibilitychange', wake);
    window.addEventListener('online', wake);
    void (async () => {
      try {
        lease = await acquireAccountLease(subject, {locks: navigator.locks, signal: cancelled.signal});
        if (!current()) {lease.release(); return;}
        session = await WatchlistSession.open({
          subject,
          currentSubject: () => current() ? subject : null,
          accessToken: expected => authRef.current.freshAccessToken(expected),
          storage: window.localStorage,
          storageEvents: window,
          apiBaseUrl: apiOrigin,
        });
        if (!current()) {session.close(); lease.release(); return;}
        verificationEpoch = ++verificationSequence.current;
        owner.current = {subject, apiOrigin, session, schedule: () => {failures = 0; schedule();}};
        unsubscribe = session.subscribe(publish);
        publish();
        schedule(0);
      } catch (error) {
        session?.close();
        lease?.release();
        if (current()) setState({subject, apiOrigin, verificationEpoch: 0, value: null,
          error: error && typeof error === 'object' && 'code' in error && typeof error.code === 'string'
            ? error.code : 'WATCHLIST_UNAVAILABLE'});
      }
    })();
    return () => {
      cancelled.abort();
      clearTimeout(timer);
      unsubscribe?.();
      session?.close();
      lease?.release();
      if (owner.current?.session === session) owner.current = null;
      document.removeEventListener('visibilitychange', wake);
      window.removeEventListener('online', wake);
    };
  }, [auth.subject, auth.apiOrigin, retry]);

  const snapshot = auth.subject && state?.subject === auth.subject && state.apiOrigin === auth.apiOrigin ? state.value : null;
  const error = auth.subject && state?.subject === auth.subject && state.apiOrigin === auth.apiOrigin ? state.error : null;
  const verifiedAccountId = snapshot && !['loginRequired', 'closed'].includes(snapshot.status)
    ? snapshot.accountId : null;
  const requestAccountReverification = useCallback(() => setRetry(value => value + 1), []);
  const portfolio = useAccountPortfolio(auth, verifiedAccountId, {
    verificationEpoch: state?.verificationEpoch ?? 0,
    requestReverification: requestAccountReverification,
  });
  const perform = (operation: (session: WatchlistSession) => void): boolean => {
    const current = owner.current;
    if (!current || current.subject !== authRef.current.subject || current.apiOrigin !== authRef.current.apiOrigin) return false;
    try {operation(current.session); current.schedule(); return true;}
    catch {
      setState(previous => previous?.subject === current.subject && previous.apiOrigin === current.apiOrigin
        ? {...previous, error: 'WATCHLIST_CHANGE_FAILED'} : previous);
      return false;
    }
  };
  return Object.freeze({
    auth, snapshot, error, portfolio,
    canEdit: snapshot !== null && !['protected', 'closed', 'loginRequired'].includes(snapshot.status),
    setAssetIds: (ids: readonly string[]) => perform(session => session.setAssetIds(ids)),
    useLocal: () => perform(session => session.useLocal()),
    useRemote: () => perform(session => session.useRemote()),
    retry: () => {
      const current = owner.current;
      if (current && current.subject === authRef.current.subject && current.apiOrigin === authRef.current.apiOrigin) {
        if (current.session.getSnapshot().status === 'loginRequired') setRetry(value => value + 1);
        else if (current.session.getSnapshot().status === 'protected') perform(session => session.reload());
        else current.schedule();
      } else setRetry(value => value + 1);
    },
  });
}
