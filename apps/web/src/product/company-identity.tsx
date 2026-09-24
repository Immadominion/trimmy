import {useEffect, useMemo, useState} from 'react';
import type {ProductMarketClient} from './market-client.js';

/** Display metadata is keyed by the server's asset identity, never a token ticker. */
export interface CompanyIdentity {
  readonly assetId: string;
  readonly name: string | null;
  readonly symbol: string | null;
  readonly imageUrl: string | null;
}
export type CompanyIdentityClient = Pick<ProductMarketClient, 'facts'> & Partial<Pick<ProductMarketClient, 'cards'>>;

const CACHE_MS = 15 * 60_000;
const MAX_CACHED_COMPANIES = 128;
const MAX_CONCURRENT_READS = 4;
const empty: ReadonlyMap<string, CompanyIdentity> = new Map();

/** Public company identity only. No prices, portfolio data or account credentials. */
export class CompanyIdentityCache {
  readonly #rows = new Map<string, {identity: CompanyIdentity; expiresAt: number}>();
  constructor(readonly client: CompanyIdentityClient, readonly now: () => number = Date.now) {}

  peek(assetId: string): CompanyIdentity | undefined {
    const row = this.#rows.get(assetId);
    if (!row) return undefined;
    if (row.expiresAt <= this.now()) {this.#rows.delete(assetId); return undefined;}
    return row.identity;
  }

  async read(assetId: string, signal: AbortSignal): Promise<CompanyIdentity> {
    signal.throwIfAborted();
    const cached = this.peek(assetId);
    if (cached) return cached;
    let identity: CompanyIdentity | undefined, failure: unknown;
    try {
      const facts = await this.client.facts(assetId, {signal});
      signal.throwIfAborted();
      // ProductMarketClient checks this too; keep the display cache safe for other adapters.
      if (facts.assetId !== assetId) throw new Error('Company identity does not match the requested asset.');
      identity = {assetId, name: facts.name, symbol: facts.symbol, imageUrl: facts.imageUrl};
    } catch (error) {signal.throwIfAborted(); failure = error;}
    if (!identity?.imageUrl && this.client.cards) {
      try {
        const page = await this.client.cards(assetId.replaceAll('-', ' '), {limit: 20, signal});
        signal.throwIfAborted();
        // Match mobile's catalog fallback. Search order and shared symbols are not identities.
        const card = page.results.find(row => row.assetId === assetId);
        if (card) identity = {assetId, name: identity?.name ?? card.name, symbol: identity?.symbol ?? card.symbol,
          imageUrl: card.imageUrl ?? card.primaryVariant?.logoUrl ?? null};
      } catch (error) {signal.throwIfAborted(); failure ??= error;}
    }
    signal.throwIfAborted();
    if (!identity) throw failure ?? new Error('Company identity is unavailable.');
    identity = Object.freeze(identity);
    // A missing image may arrive on the next portfolio refresh, as on mobile.
    if (identity.imageUrl) {
      this.#rows.delete(assetId);
      this.#rows.set(assetId, {identity, expiresAt: this.now() + CACHE_MS});
      if (this.#rows.size > MAX_CACHED_COMPANIES) this.#rows.delete(this.#rows.keys().next().value!);
    }
    return identity;
  }
}

const caches = new WeakMap<CompanyIdentityClient, CompanyIdentityCache>();
function cacheFor(client: CompanyIdentityClient): CompanyIdentityCache {
  let cache = caches.get(client);
  if (!cache) {cache = new CompanyIdentityCache(client); caches.set(client, cache);}
  return cache;
}

/**
 * Optional images fill in independently of balances. A refreshed portfolio can be
 * supplied as refreshKey to retry unavailable metadata without polling separately.
 */
export function useCompanyIdentities(client: CompanyIdentityClient, assetIds: readonly string[], refreshKey?: unknown): ReadonlyMap<string, CompanyIdentity> {
  const key = JSON.stringify([...new Set(assetIds)].sort());
  const ids = useMemo(() => JSON.parse(key) as string[], [key]);
  const cache = useMemo(() => cacheFor(client), [client]);
  const [resolved, setResolved] = useState<{cache: CompanyIdentityCache; key: string; rows: ReadonlyMap<string, CompanyIdentity>} | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    const rows = new Map<string, CompanyIdentity>();
    const missing: string[] = [];
    for (const id of ids) {
      const identity = cache.peek(id);
      if (identity) rows.set(id, identity); else missing.push(id);
    }
    setResolved({cache, key, rows: new Map(rows)});
    let cursor = 0;
    async function resolveNext() {
      while (!controller.signal.aborted) {
        const id = missing[cursor++];
        if (id === undefined) return;
        try {
          const identity = await cache.read(id, controller.signal);
          if (controller.signal.aborted) return;
          rows.set(id, identity);
          setResolved({cache, key, rows: new Map(rows)});
        } catch {
          // Initials remain honest when the optional provider image cannot load.
        }
      }
    }
    for (let i = 0; i < Math.min(MAX_CONCURRENT_READS, missing.length); i++) void resolveNext();
    return () => controller.abort();
  }, [cache, ids, key, refreshKey]);

  // Never display a previous account's/request's rows during an effect transition.
  return resolved?.cache === cache && resolved.key === key ? resolved.rows : empty;
}
