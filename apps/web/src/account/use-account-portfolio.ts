import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {AccountDataClient} from './account-data-client.js';
import {AccountDataError, type AccountDataErrorCode} from './account-data-models.js';
import {
  AccountPortfolioStore,
  type AccountPortfolioIssue,
  type AccountPortfolioState,
} from './account-portfolio.js';
import type {PracticeAccountAuth} from './privy-provider.js';

export interface VerifiedAccountBinding {
  readonly subject: string;
  readonly accountId: string;
  readonly apiOrigin: string;
  /** Changes only after a new authenticated server session establishes this mapping. */
  readonly verificationEpoch: number;
}

export interface AccountPortfolioLifecycleView {
  /** Present only after the API established the subject-to-account UUID mapping. */
  readonly binding: VerifiedAccountBinding | null;
  /** A store snapshot for the exact current binding. Old bindings are masked during render. */
  readonly snapshot: AccountPortfolioState | null;
  readonly errorCode: AccountPortfolioIssue | AccountDataErrorCode | null;
  /** Starts a read only while the same verified binding remains active and visible. */
  readonly refresh: () => boolean;
  /** Requests a new server binding after a terminal account-authentication failure. */
  readonly retry: () => boolean;
}

export interface AccountPortfolioLifecycleOptions {
  readonly verificationEpoch?: number;
  readonly requestReverification?: () => void;
}

interface Observation {
  readonly key: string;
  readonly snapshot: AccountPortfolioState | null;
  readonly setupError: AccountDataErrorCode | null;
}

interface Owner {
  readonly key: string;
  readonly store: AccountPortfolioStore;
  terminal: boolean;
  reverificationRequested: boolean;
}

const TERMINAL_ISSUES = new Set<AccountPortfolioIssue>([
  'ACCOUNT_DATA_ACCOUNT_CHANGED',
  'ACCOUNT_PORTFOLIO_WALLET_CHANGED',
  'ACCOUNT_DATA_TOKEN_UNAVAILABLE',
  'ACCOUNT_CONTEXT_UNAUTHENTICATED',
  'ACCOUNT_HOLDINGS_UNAUTHENTICATED',
  'ACCOUNT_DATA_CLOSED',
]);

function bindingKey(binding: VerifiedAccountBinding): string {
  return `${binding.subject}\u0000${binding.accountId}\u0000${binding.apiOrigin}\u0000${binding.verificationEpoch}`;
}

/**
 * Owns the read-only account portfolio for one server-verified browser session.
 *
 * `verifiedAccountId` must come from the authenticated `/v1/practice/session`
 * response. A DID or locally cached account UUID is insufficient to mount it.
 */
export function useAccountPortfolio(auth: PracticeAccountAuth,
  verifiedAccountId: string | null,
  options: AccountPortfolioLifecycleOptions = {}): AccountPortfolioLifecycleView {
  const authRef = useRef(auth);
  authRef.current = auth;
  const requestReverificationRef = useRef(options.requestReverification);
  requestReverificationRef.current = options.requestReverification;
  const verificationEpoch = options.verificationEpoch ?? 1;
  const binding = useMemo<VerifiedAccountBinding | null>(() => {
    if (!auth.ready || !auth.authenticated || auth.errorCode !== null || !auth.subject ||
        !auth.apiOrigin || !verifiedAccountId || !Number.isSafeInteger(verificationEpoch) || verificationEpoch < 1) {
      return null;
    }
    return Object.freeze({subject: auth.subject, accountId: verifiedAccountId, apiOrigin: auth.apiOrigin,
      verificationEpoch});
  }, [auth.ready, auth.authenticated, auth.errorCode, auth.subject, auth.apiOrigin, verifiedAccountId,
    verificationEpoch]);
  const key = binding ? bindingKey(binding) : null;
  const currentKey = useRef<string | null>(key);
  currentKey.current = key;
  const owner = useRef<Owner | null>(null);
  const [observation, setObservation] = useState<Observation | null>(null);

  useEffect(() => {
    if (!binding) return;
    const mountedKey = bindingKey(binding);
    const current = () => currentKey.current === mountedKey;
    let store: AccountPortfolioStore;
    try {
      const client = new AccountDataClient({
        apiOrigin: binding.apiOrigin,
        subject: binding.subject,
        accountId: binding.accountId,
        currentSubject: () => current() && authRef.current.ready && authRef.current.authenticated &&
          authRef.current.errorCode === null && authRef.current.subject === binding.subject &&
          authRef.current.apiOrigin === binding.apiOrigin ? binding.subject : null,
        accessToken: async expectedSubject => {
          const active = authRef.current;
          if (!current() || expectedSubject !== binding.subject || !active.ready || !active.authenticated ||
              active.errorCode !== null || active.subject !== binding.subject ||
              active.apiOrigin !== binding.apiOrigin) return null;
          return active.freshAccessToken(expectedSubject);
        },
      });
      store = new AccountPortfolioStore({client});
    } catch (error) {
      const code = error instanceof AccountDataError ? error.code : 'ACCOUNT_DATA_INVALID_CONFIGURATION';
      if (current()) setObservation(Object.freeze({key: mountedKey, snapshot: null, setupError: code}));
      return;
    }

    const mounted: Owner = {key: mountedKey, store, terminal: false, reverificationRequested: false};
    owner.current = mounted;
    let unsubscribe: (() => void) | null = null;
    const publish = () => {
      if (!current() || owner.current !== mounted) return;
      const snapshot = store.getSnapshot();
      setObservation(Object.freeze({key: mountedKey, snapshot, setupError: null}));
      if (snapshot.issue && TERMINAL_ISSUES.has(snapshot.issue)) {
        mounted.terminal = true;
        const release = unsubscribe;
        unsubscribe = null;
        release?.();
        store.close();
      }
    };
    const refresh = () => {
      if (!current() || owner.current !== mounted || mounted.terminal || document.hidden ||
          navigator.onLine === false) return;
      void store.refresh().catch(() => { /* The immutable store state carries the fixed error code. */ });
    };
    const requestReverification = () => {
      if (!current() || owner.current !== mounted || !mounted.terminal || mounted.reverificationRequested ||
          !requestReverificationRef.current) return;
      mounted.reverificationRequested = true;
      try { requestReverificationRef.current(); }
      catch { /* One explicit event may request at most one new server binding. */ }
    };
    const wake = () => {
      if (document.hidden) return;
      if (mounted.terminal) requestReverification();
      else refresh();
    };
    const lostConnectivity = () => {
      if (current() && owner.current === mounted && !mounted.terminal) store.observeConnectivity(false);
    };

    unsubscribe = store.subscribe(publish);
    publish();
    document.addEventListener('visibilitychange', wake);
    window.addEventListener('online', wake);
    window.addEventListener('offline', lostConnectivity);
    if (navigator.onLine === false) store.observeConnectivity(false);
    else refresh();

    return () => {
      document.removeEventListener('visibilitychange', wake);
      window.removeEventListener('online', wake);
      window.removeEventListener('offline', lostConnectivity);
      unsubscribe?.();
      unsubscribe = null;
      if (owner.current === mounted) owner.current = null;
      store.close();
    };
  }, [binding]);

  const refresh = useCallback((): boolean => {
    const active = owner.current;
    if (!active || active.key !== currentKey.current || active.terminal || document.hidden ||
        navigator.onLine === false) return false;
    void active.store.refresh().catch(() => { /* The immutable store state carries the fixed error code. */ });
    return true;
  }, []);
  const retry = useCallback((): boolean => {
    const active = owner.current;
    const request = requestReverificationRef.current;
    if (!active || active.key !== currentKey.current || !active.terminal ||
        active.reverificationRequested || !request) return false;
    active.reverificationRequested = true;
    try { request(); return true; }
    catch { return false; }
  }, []);
  const visible = key !== null && observation?.key === key ? observation : null;
  return useMemo(() => Object.freeze({
    binding,
    snapshot: visible?.snapshot ?? null,
    errorCode: visible?.setupError ?? visible?.snapshot?.issue ?? null,
    refresh,
    retry,
  }), [binding, visible, refresh, retry]);
}
