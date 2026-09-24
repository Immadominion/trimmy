import { BoundHttp, WatchlistSyncError } from './watchlist-sync';
import type { BoundHttpOptions } from './watchlist-sync';

const FOLLOWING_PATH = '/v1/following';
const MAX_FOLLOWED = 50;
const ASSET_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export type FollowedStocksStatus = 'idle' | 'loading' | 'ready' | 'saving' | 'error';

export interface FollowedStocksView {
  readonly assetIds: readonly string[];
  readonly revision: number;
  readonly status: FollowedStocksStatus;
  readonly errorCode: string | null;
  readonly full: boolean;
}

interface Snapshot {
  readonly revision: number;
  readonly assetIds: readonly string[];
}

const EMPTY: Snapshot = Object.freeze({revision: 0, assetIds: Object.freeze([]) as readonly string[]});

function fail(code = 'FOLLOWING_INVALID_PROTOCOL'): never {
  throw new WatchlistSyncError(code);
}

export function isStorableAssetId(value: unknown): value is string {
  return typeof value === 'string' && value.length <= 100 && ASSET_ID.exec(value)?.[0] === value;
}

function snapshot(input: unknown): Snapshot {
  if (!input || typeof input !== 'object' || Array.isArray(input)) fail();
  const record = input as Record<string, unknown>;
  const keys = Object.keys(record);
  if (keys.length !== 4 || record['schemaVersion'] !== 1) fail();
  const revision = record['revision'];
  const rows = record['assetIds'];
  const updatedAt = record['updatedAt'];
  if (typeof revision !== 'number' || !Number.isSafeInteger(revision) || revision < 0 ||
      !Array.isArray(rows) || rows.length > MAX_FOLLOWED) fail();
  const ids: string[] = [];
  for (const row of rows) {
    if (!isStorableAssetId(row) || ids.includes(row)) fail();
    ids.push(row);
  }
  if (revision === 0 && (ids.length !== 0 || updatedAt !== null)) fail();
  if (revision !== 0 && typeof updatedAt !== 'string') fail();
  return Object.freeze({revision, assetIds: Object.freeze(ids) as readonly string[]});
}

function mutationId(): string {
  return globalThis.crypto.randomUUID();
}

/**
 * The signed-in account's real followed list.
 *
 * Deliberately simpler than the sample watchlist session: no local durability,
 * no cross-tab lock and no offline queue, because this list changes rarely from
 * one place and a real asset must never be invented offline. What it does share
 * is the hardened request path and the revision discipline.
 *
 * Keeping an asset records a name someone chose to keep. It is not an approval,
 * a holding, a price or permission to trade.
 */
export class FollowedStocksStore {
  private readonly http: BoundHttp;
  private current: Snapshot = EMPTY;
  private loaded = false;
  private view: FollowedStocksView;
  private status: FollowedStocksStatus = 'idle';
  private errorCode: string | null = null;
  private readonly listeners = new Set<() => void>();
  private closed = false;

  constructor(options: BoundHttpOptions) {
    // The shared conflict parser validates against the fixed sample catalog, so
    // it would reject a real followed list. This store re-reads instead.
    this.http = new BoundHttp(options, false);
    this.view = this.build();
  }

  readonly getSnapshot = (): FollowedStocksView => this.view;

  readonly subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  };

  close(): void {
    this.closed = true;
    this.http.close();
  }

  isFollowing(assetId: string): boolean {
    return this.current.assetIds.includes(assetId);
  }

  /** Reads the list. Nothing is fetched until something asks. */
  async refresh(): Promise<void> {
    await this.run('loading', async () => {
      this.current = snapshot(await this.http.request('GET', FOLLOWING_PATH));
      this.loaded = true;
    });
  }

  async follow(assetId: string): Promise<void> {
    if (!isStorableAssetId(assetId)) return this.report('FOLLOWING_INVALID_INPUT');
    await this.rewrite(list => {
      if (list.includes(assetId)) return null;
      if (list.length >= MAX_FOLLOWED) fail('FOLLOWING_LIST_FULL');
      return [...list, assetId];
    });
  }

  async unfollow(assetId: string): Promise<void> {
    await this.rewrite(list => (list.includes(assetId) ? list.filter(id => id !== assetId) : null));
  }

  /**
   * Applies `change` at the revision last seen. A refusal means someone else
   * changed the list first, so it is reloaded and the same change reapplied
   * once: their change survives and this one is not silently lost.
   */
  private async rewrite(change: (list: readonly string[]) => string[] | null): Promise<void> {
    await this.run('saving', async () => {
      for (let attempt = 0; attempt < 2; attempt++) {
        if (!this.loaded) {
          // Never write a list this client has not actually seen.
          this.current = snapshot(await this.http.request('GET', FOLLOWING_PATH));
          this.loaded = true;
        }
        const next = change(this.current.assetIds);
        if (next === null) return;
        try {
          this.current = snapshot(await this.http.request('PUT', FOLLOWING_PATH, {
            schemaVersion: 1, mutationId: mutationId(),
            baseRevision: this.current.revision, assetIds: next,
          }));
          this.loaded = true;
          return;
        } catch (error) {
          const conflict = error instanceof WatchlistSyncError && error.code === 'WATCHLIST_REVISION_CONFLICT';
          if (!conflict || attempt === 1) throw error;
          this.current = snapshot(await this.http.request('GET', FOLLOWING_PATH));
          this.loaded = true;
        }
      }
    });
  }

  private async run(active: FollowedStocksStatus, work: () => Promise<void>): Promise<void> {
    if (this.closed) return;
    if (this.status === 'loading' || this.status === 'saving') return this.report('FOLLOWING_BUSY');
    this.status = active;
    this.errorCode = null;
    this.publish();
    try {
      await work();
      this.status = 'ready';
    } catch (error) {
      this.status = 'error';
      this.errorCode = error instanceof WatchlistSyncError ? error.code : 'FOLLOWING_UNAVAILABLE';
    }
    this.publish();
  }

  private report(code: string): void {
    this.errorCode = code;
    this.status = 'error';
    this.publish();
  }

  private build(): FollowedStocksView {
    return Object.freeze({
      assetIds: this.current.assetIds,
      revision: this.current.revision,
      status: this.status,
      errorCode: this.errorCode,
      full: this.current.assetIds.length >= MAX_FOLLOWED,
    });
  }

  private publish(): void {
    if (this.closed) return;
    this.view = this.build();
    for (const listener of this.listeners) listener();
  }
}
