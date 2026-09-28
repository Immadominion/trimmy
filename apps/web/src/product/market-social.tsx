import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {PracticeError, normalizePracticeApiBase} from './practice-client';
import type {PracticeAccountProof} from './practice-client';
import type {PracticeStorage} from './practice-session';
import {read} from './product-api';
import type {ProductApiClient} from './product-api';
import type {StockCard} from './market-client';
import {CompanyLogo} from './ui';

/* Mobile's Market extras: Following (GET/PUT /v1/following, the real followed
 * list; /v1/watchlist is the fixed sample list), sorting, list tabs and recents. */

export interface FollowingSnapshot {readonly revision: number; readonly assetIds: readonly string[]}
const ASSET = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
export const MAX_FOLLOWED = 50;
export function parseFollowing(value: unknown): FollowingSnapshot {
  const v = read.record(value, ['schemaVersion', 'revision', 'assetIds', 'updatedAt']);
  if (v['schemaVersion'] !== 1) read.invalid();
  const revision = read.integer(v['revision']);
  const ids = read.array(v['assetIds'], MAX_FOLLOWED).map(item => {const id = read.string(item, 100); if (!ASSET.test(id)) read.invalid(); return id;});
  if (new Set(ids).size !== ids.length || (revision === 0) !== (v['updatedAt'] === null) || (revision === 0 && ids.length)) read.invalid();
  if (revision !== 0) read.instant(v['updatedAt']);
  return Object.freeze({revision, assetIds: Object.freeze(ids)});
}
export interface FollowingState {
  readonly assetIds: readonly string[] | null; readonly busy: boolean; readonly signedIn: boolean;
  isFollowing(assetId: string): boolean;
  /** Returns mobile's notice for the change, and whether sign-in is the next step. */
  toggle(assetId: string, name: string): Promise<{readonly message: string; readonly signIn: boolean}>;
}
/** Account-only, like mobile's followedStocksController. Guests are asked to sign in. */
export function useFollowing(api: ProductApiClient | null, account: PracticeAccountProof | null): FollowingState {
  const [snapshot, setSnapshot] = useState<FollowingSnapshot | null>(null), [busy, setBusy] = useState(false);
  const latest = useRef(snapshot); latest.current = snapshot;
  const accountRef = useRef(account); accountRef.current = account;
  const signedIn = account !== null;
  useEffect(() => {
    setSnapshot(null);
    const current = accountRef.current;
    if (!api || !current) return;
    const controller = new AbortController();
    void api.request({path: '/v1/following', identity: current, signal: controller.signal, parse: parseFollowing})
      .then(value => {if (!controller.signal.aborted) setSnapshot(value);}, () => undefined);
    return () => controller.abort();
  }, [api, signedIn]);
  const toggle = useCallback(async (assetId: string, name: string) => {
    const current = accountRef.current;
    if (!api || !current) return {message: 'Sign in to save your watchlist.', signIn: true};
    if (busy) return {message: 'Following did not change. Try again.', signIn: false};
    setBusy(true);
    try {
      let base = latest.current ?? await api.request({path: '/v1/following', identity: current, parse: parseFollowing});
      const wasFollowing = base.assetIds.includes(assetId);
      for (let attempt = 0; attempt < 2; attempt++) {
        const next = wasFollowing ? base.assetIds.filter(id => id !== assetId) : base.assetIds.includes(assetId) ? [...base.assetIds] : [...base.assetIds, assetId];
        if (!wasFollowing && next.length > MAX_FOLLOWED) return {message: 'Your watchlist is full. Remove a company first.', signIn: false};
        try {
          const saved = await api.request({path: '/v1/following', method: 'PUT', identity: current, parse: parseFollowing,
            body: {schemaVersion: 1, mutationId: crypto.randomUUID(), baseRevision: base.revision, assetIds: next}});
          setSnapshot(saved);
          return {message: wasFollowing ? `${name} removed from Following.` : `${name} added to Following.`, signIn: false};
        } catch (error) {
          // Someone else changed the list first: reload and reapply once, keeping their change.
          if (!(error instanceof PracticeError && error.code === 'WATCHLIST_REVISION_CONFLICT') || attempt === 1) throw error;
          base = await api.request({path: '/v1/following', identity: current, parse: parseFollowing}); setSnapshot(base);
        }
      }
      return {message: 'Following did not change. Try again.', signIn: false};
    } catch (error) {
      if (error instanceof PracticeError && error.status === 401) return {message: 'Sign in to save your watchlist.', signIn: true};
      return {message: 'Following did not change. Try again.', signIn: false};
    } finally {setBusy(false);}
  }, [api, busy]);
  return {assetIds: snapshot?.assetIds ?? null, busy, signedIn, isFollowing: id => snapshot?.assetIds.includes(id) ?? false, toggle};
}

/**
 * Schema 2 catalogs mix equities, ETFs and commodities. The shared market parser
 * owns `category`; this only reads it when present, so nothing here assumes an equity.
 */
export type MarketCategory = 'equity' | 'etf' | 'commodity';
export function categoryOf(item: object): MarketCategory | null {
  const value = (item as {category?: unknown}).category;
  return value === 'equity' || value === 'etf' || value === 'commodity' ? value : null;
}
export function categoryLabel(category: MarketCategory | null): string {return category === 'etf' ? 'ETF' : category === 'commodity' ? 'Commodity' : 'Stock';}
/**
 * One row's price and day change from a single source: the listed session when the
 * item has one, otherwise its primary token (ETFs and commodities may have no session).
 * Mobile never mixes one source's price with another's change.
 */
export function marketFigures(card: StockCard): {readonly price: number | null; readonly change: number | null} {
  return card.stock ? {price: card.stock.priceUsd, change: card.stock.changePercent24h}
    : {price: card.primaryVariant?.priceUsd ?? null, change: card.primaryVariant?.changePercent24h ?? null};
}
export type MarketSort = 'featured' | 'name' | 'price' | 'gains' | 'drops';
export const sortLabels: Record<MarketSort, string> = {featured: 'Featured', name: 'Name', price: 'Highest price', gains: 'Biggest gains', drops: 'Biggest drops'};
export function availableSorts(cards: readonly StockCard[]): MarketSort[] {
  return ['featured', 'name', 'price', ...(cards.some(card => marketFigures(card).change !== null) ? ['gains', 'drops'] as const : [])];
}
/** Mobile's MarketSort over the loaded rows. Missing values sort last; ties keep the featured order. */
export function sortCards(cards: readonly StockCard[], sort: MarketSort): StockCard[] {
  const rows = [...cards], name = (card: StockCard) => card.name ?? card.assetId;
  if (sort === 'name') rows.sort((a, b) => name(a).localeCompare(name(b)));
  const price = (card: StockCard) => marketFigures(card).price, change = (card: StockCard) => marketFigures(card).change;
  if (sort === 'price') rows.sort((a, b) => (price(b) ?? -1) - (price(a) ?? -1));
  if (sort === 'gains') rows.sort((a, b) => (change(b) ?? -Infinity) - (change(a) ?? -Infinity));
  if (sort === 'drops') rows.sort((a, b) => (change(a) ?? Infinity) - (change(b) ?? Infinity));
  return rows;
}

export interface RecentCompany {readonly assetId: string; readonly name: string | null; readonly symbol: string | null; readonly imageUrl: string | null; readonly category: MarketCategory | null}
/** Mobile's MarketRecentsController (eight, newest first), kept on this browser. Public names only. */
export function useSearchRecents(storage: PracticeStorage | null, apiBase: string | null) {
  const key = useMemo(() => {try {return apiBase ? `trimmy.market.recents.v1:${encodeURIComponent(normalizePracticeApiBase(apiBase))}` : null;} catch {return null;}}, [apiBase]);
  const load = useCallback((): RecentCompany[] => {
    if (!storage || !key) return [];
    try {
      const value: unknown = JSON.parse(storage.getItem(key) ?? '[]');
      if (!Array.isArray(value)) return [];
      return value.slice(0, 8).flatMap(item => {
        const row = item as Record<string, unknown>;
        const text = (field: unknown, max: number) => typeof field === 'string' && field.length > 0 && field.length <= max && !/[\u0000-\u001f]/u.test(field) ? field : null;
        const assetId = text(row?.['assetId'], 100);
        const image = text(row?.['imageUrl'], 2048);
        return assetId && ASSET.test(assetId) ? [{assetId, name: text(row['name'], 200), symbol: text(row['symbol'], 40), imageUrl: image?.startsWith('https://') ? image : null,
          category: categoryOf(row)}] : [];
      });
    } catch {return [];}
  }, [storage, key]);
  const [recents, setRecents] = useState<RecentCompany[]>(load);
  useEffect(() => setRecents(load()), [load]);
  const save = (rows: RecentCompany[]) => {setRecents(rows); try {if (storage && key) storage.setItem(key, JSON.stringify(rows));} catch { /* Recents are a convenience. */ }};
  const record = (card: StockCard) => save([{assetId: card.assetId, name: card.name, symbol: card.symbol, imageUrl: card.imageUrl, category: categoryOf(card)},
    ...recents.filter(row => row.assetId !== card.assetId)].slice(0, 8));
  return {recents, record, clear: () => save([])};
}
export type SearchRecents = ReturnType<typeof useSearchRecents>;

export function FollowButton({card, following, onNotice}: {card: StockCard; following: FollowingState; onNotice: (message: string, signIn: boolean) => void}) {
  const followed = following.isFollowing(card.assetId), name = card.name ?? card.assetId;
  return <button className={`follow-button${followed ? ' following' : ''}`} aria-pressed={followed} disabled={following.busy}
    aria-label={followed ? `Unfollow ${name}` : `Follow ${name}`}
    onClick={async () => {const result = await following.toggle(card.assetId, name); onNotice(result.message, result.signIn);}}>{followed ? 'Following' : '+ Follow'}</button>;
}
export function RecentsStrip({recents, onOpen}: {recents: SearchRecents; onOpen: (company: RecentCompany) => void}) {
  if (!recents.recents.length) return null;
  return <section className="market-recents" aria-label="Recently viewed"><div className="section-line"><h2>Recently viewed</h2><button className="text-button" onClick={recents.clear}>Clear</button></div>
    <div className="market-recents-list">{recents.recents.map(company => <button key={company.assetId} className="market-recent" onClick={() => onOpen(company)}>
      <CompanyLogo name={company.name ?? company.assetId} url={company.imageUrl} size={30}/><span><strong>{company.name ?? company.assetId}</strong><small>{company.symbol ?? categoryLabel(company.category)}</small></span></button>)}</div></section>;
}

export type MarketList = 'all' | 'following';
export function MarketControls({list, onList, sort, sorts, onSort}: {list: MarketList; onList: (list: MarketList) => void; sort: MarketSort; sorts: readonly MarketSort[]; onSort: (sort: MarketSort) => void}) {
  return <div className="market-controls">
    <div className="market-lists" role="tablist" aria-label="Stock lists">{(['all', 'following'] as const).map(item => <button key={item} role="tab" aria-selected={list === item}
      className={list === item ? 'active' : ''} onClick={() => onList(item)}>{item === 'all' ? 'All stocks' : 'Following'}</button>)}</div>
    <label className="market-sort"><span>Sort: </span><select aria-label="Sort stocks" value={sorts.includes(sort) ? sort : 'featured'} onChange={event => onSort(event.target.value as MarketSort)}>
      {sorts.map(item => <option key={item} value={item}>{sortLabels[item]}</option>)}</select></label>
  </div>;
}
/** Followed companies not on a loaded page are read once from public facts (never invented). */
export function useFollowedCards(client: {facts: (assetId: string, options?: {signal?: AbortSignal}) => Promise<{assetId: string; name: string | null; symbol: string | null; imageUrl: string | null; stock: StockCard['stock']}>},
  ids: readonly string[] | null, loaded: readonly StockCard[], enabled: boolean): {cards: StockCard[]; loading: boolean} {
  const [resolved, setResolved] = useState<ReadonlyMap<string, StockCard>>(new Map()), [loading, setLoading] = useState(false);
  const missing = useMemo(() => enabled && ids ? ids.filter(id => !loaded.some(card => card.assetId === id) && !resolved.has(id)) : [], [enabled, ids, loaded, resolved]);
  const key = missing.join(',');
  useEffect(() => {
    if (!key) return;
    const controller = new AbortController(); setLoading(true);
    void Promise.allSettled(key.split(',').map(id => client.facts(id, {signal: controller.signal}))).then(results => {
      if (controller.signal.aborted) return;
      setResolved(prior => {
        const next = new Map(prior);
        for (const result of results) if (result.status === 'fulfilled') next.set(result.value.assetId, {assetId: result.value.assetId, name: result.value.name,
          symbol: result.value.symbol, imageUrl: result.value.imageUrl, stock: result.value.stock, primaryVariant: null});
        return next;
      });
      setLoading(false);
    });
    return () => controller.abort();
  }, [client, key]);
  const cards = (ids ?? []).flatMap(id => {const card = loaded.find(row => row.assetId === id) ?? resolved.get(id); return card ? [card] : [];});
  return {cards, loading: loading || missing.length > 0};
}
