import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';
import { usePracticeAccountAuth } from './privy-provider';
import { FollowedStocksStore } from './followed-stocks';
import type { FollowedStocksView } from './followed-stocks';

export interface FollowedStocksWorkspace {
  /** Null for a guest, so a control can be absent rather than offered and refused. */
  readonly view: FollowedStocksView | null;
  isFollowing(assetId: string): boolean;
  follow(assetId: string): void;
  unfollow(assetId: string): void;
  refresh(): void;
}

const IDLE: FollowedStocksWorkspace = Object.freeze({
  view: null,
  isFollowing: () => false,
  follow: () => {},
  unfollow: () => {},
  refresh: () => {},
});

/**
 * The verified account's real followed list.
 *
 * Deliberately much simpler than the sample watchlist session: no tab lease, no
 * background polling and no local durability, because this list changes rarely
 * from one place and a real asset must never be invented offline. It is created
 * with the identity and closed the moment that identity changes.
 */
export function useFollowedStocks(): FollowedStocksWorkspace {
  const auth = usePracticeAccountAuth();
  const authRef = useRef(auth);
  authRef.current = auth;
  const {subject, apiOrigin, authenticated} = auth;
  const [store, setStore] = useState<FollowedStocksStore | null>(null);

  useEffect(() => {
    if (!authenticated || !subject || !apiOrigin) {
      setStore(null);
      return;
    }
    const created = new FollowedStocksStore({
      subject,
      currentSubject: () => authRef.current.subject,
      accessToken: expected => authRef.current.freshAccessToken(expected),
      apiBaseUrl: apiOrigin,
    });
    setStore(created);
    return () => {
      created.close();
      setStore(null);
    };
  }, [subject, apiOrigin, authenticated]);

  const view = useSyncExternalStore(
    useCallback(listener => (store ? store.subscribe(listener) : () => {}), [store]),
    useCallback(() => store?.getSnapshot() ?? null, [store]),
    useCallback(() => null, []),
  );

  return useMemo(() => {
    if (!store) return IDLE;
    return {
      view,
      isFollowing: (assetId: string) => store.isFollowing(assetId),
      follow: (assetId: string) => { void store.follow(assetId); },
      unfollow: (assetId: string) => { void store.unfollow(assetId); },
      refresh: () => { void store.refresh(); },
    };
  }, [store, view]);
}
