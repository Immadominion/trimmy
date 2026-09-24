import type {StockResearchClient} from './client.js';
import type {StockSearchPage, StockVariantsPage} from './discovery.js';
import {RESEARCH_AAPLX_MINT, type StockEstimate} from './estimate.js';
import type {StockHistoryPage} from './history.js';
import type {RaydiumStockQuote} from './raydium.js';
import {StockResearchError} from './validation.js';

/**
 * Read-only live research state for the workspace. Nothing loads until a
 * person asks: every read spends provider quota and is single-flighted per
 * slice, aborted on replacement or close, and reported with its own freshness.
 * There is no venue choice, no price, no wallet and no order anywhere here.
 */
export type ResearchPhase = 'idle' | 'loading' | 'ready' | 'error' | 'offline';

export interface ResearchSlice<T> {
  readonly phase: ResearchPhase;
  readonly value: T | null;
  readonly code: string | null;
  /** Set only while a value is retained after a failed refresh. */
  readonly retained: boolean;
}

export interface LiveResearchState {
  readonly query: string;
  readonly search: ResearchSlice<StockSearchPage>;
  readonly variants: ResearchSlice<StockVariantsPage>;
  readonly history: ResearchSlice<StockHistoryPage>;
  readonly jupiter: ResearchSlice<StockEstimate>;
  readonly raydium: ResearchSlice<RaydiumStockQuote>;
}

export const RESEARCH_AMOUNT_RAW = '10000000';
export const RESEARCH_HISTORY_SECONDS = 24 * 60 * 60;

const empty = <T>(): ResearchSlice<T> => Object.freeze({phase: 'idle', value: null, code: null, retained: false});
type SliceKey = 'search' | 'variants' | 'history' | 'jupiter' | 'raydium';

export function researchIsStale(refreshAfter: string, now: number): boolean {
  const deadline = Date.parse(refreshAfter);
  return !Number.isFinite(deadline) || now >= deadline;
}

export class LiveResearchStore {
  readonly #client: StockResearchClient;
  readonly #now: () => number;
  readonly #online: () => boolean;
  readonly #listeners = new Set<() => void>();
  readonly #inflight = new Map<SliceKey, AbortController>();
  #state: LiveResearchState;
  #closed = false;

  constructor(options: {client: StockResearchClient; now?: () => number; online?: () => boolean}) {
    this.#client = options.client;
    this.#now = options.now ?? Date.now;
    this.#online = options.online ?? (() => typeof navigator === 'undefined' || navigator.onLine !== false);
    this.#state = Object.freeze({
      query: '', search: empty<StockSearchPage>(), variants: empty<StockVariantsPage>(), history: empty<StockHistoryPage>(),
      jupiter: empty<StockEstimate>(), raydium: empty<RaydiumStockQuote>(),
    });
  }

  getSnapshot(): LiveResearchState { return this.#state; }
  subscribe(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => { this.#listeners.delete(listener); };
  }
  now(): number { return this.#now(); }

  /** Searches listed equities. An empty query clears results without a request. */
  search(query: string): Promise<void> {
    const trimmed = query.trim();
    if (trimmed.length === 0) {
      this.#abort('search'); this.#abort('variants');
      this.#patch({query: '', search: empty<StockSearchPage>(), variants: empty<StockVariantsPage>()});
      return Promise.resolve();
    }
    this.#patch({query: trimmed, variants: empty<StockVariantsPage>()});
    return this.#run('search', signal => this.#client.search(trimmed, {limit: 8, signal}), {keepValue: false});
  }

  variants(assetId: string): Promise<void> {
    return this.#run('variants', signal => this.#client.variants(assetId, {signal}), {keepValue: false});
  }

  /** AAPLx hourly mint history for the last day. Not canonical equity history. */
  history(): Promise<void> {
    // Hourly candles start on hour boundaries; ask for an aligned window so the
    // strict page check can match every candle to the request.
    const to = Math.floor(this.#now() / 1000 / 3600) * 3600;
    const from = to - RESEARCH_HISTORY_SECONDS;
    return this.#run('history', signal => this.#client.history({
      assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, interval: '1H', fromUnixSeconds: String(from), toUnixSeconds: String(to),
    }, {signal}), {keepValue: true});
  }

  /** Two independent indicative reads for the same fixed 10 USDC buy. Neither is executable. */
  estimates(): Promise<void> {
    const request = {assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, side: 'buy', amountRaw: RESEARCH_AMOUNT_RAW} as const;
    return Promise.all([
      this.#run('jupiter', signal => this.#client.estimate(request, {signal}), {keepValue: true}),
      this.#run('raydium', signal => this.#client.raydiumQuote(request, {signal}), {keepValue: true}),
    ]).then(() => undefined);
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    for (const key of [...this.#inflight.keys()]) this.#abort(key);
    this.#client.close();
    this.#listeners.clear();
  }

  async #run<T>(key: SliceKey, read: (signal: AbortSignal) => Promise<T>, options: {keepValue: boolean}): Promise<void> {
    if (this.#closed) return;
    this.#abort(key);
    const previous = this.#state[key] as ResearchSlice<T>;
    const retainedValue = options.keepValue ? previous.value : null;
    if (!this.#online()) {
      this.#set(key, {phase: 'offline', value: retainedValue, code: 'STOCK_OFFLINE', retained: retainedValue !== null});
      return;
    }
    const controller = new AbortController();
    this.#inflight.set(key, controller);
    this.#set(key, {phase: 'loading', value: retainedValue, code: null, retained: retainedValue !== null});
    try {
      const value = await read(controller.signal);
      if (this.#inflight.get(key) !== controller || this.#closed) return;
      this.#set(key, {phase: 'ready', value, code: null, retained: false});
    } catch (error) {
      if (this.#inflight.get(key) !== controller || this.#closed) return;
      const code = error instanceof StockResearchError ? error.message : 'STOCK_SERVICE_UNAVAILABLE';
      if (code === 'STOCK_CANCELLED') return;
      this.#set(key, {phase: 'error', value: retainedValue, code, retained: retainedValue !== null});
    } finally {
      if (this.#inflight.get(key) === controller) this.#inflight.delete(key);
    }
  }

  #abort(key: SliceKey): void {
    const active = this.#inflight.get(key);
    if (!active) return;
    this.#inflight.delete(key);
    active.abort();
  }

  #set<T>(key: SliceKey, slice: ResearchSlice<T>): void {
    this.#patch({[key]: Object.freeze(slice)} as Partial<LiveResearchState>);
  }

  #patch(partial: Partial<LiveResearchState>): void {
    if (this.#closed) return;
    this.#state = Object.freeze({...this.#state, ...partial});
    for (const listener of [...this.#listeners]) listener();
  }
}

/** Plain-language reasons for the fixed client and server codes. */
export function researchIssueMessage(code: string | null): string {
  switch (code) {
    case null: return '';
    case 'STOCK_OFFLINE': return "You're offline. Nothing was checked.";
    case 'STOCK_INPUT_INVALID': return 'Enter a company name or symbol.';
    case 'STOCK_DISCOVERY_UNAVAILABLE':
    case 'STOCK_HISTORY_UNAVAILABLE':
    case 'MARKET_UNAVAILABLE': return 'Not available on this server.';
    case 'STOCK_RATE_LIMITED':
    case 'STOCK_HISTORY_RATE_LIMITED':
    case 'MARKET_RATE_LIMITED': return 'Too many checks. Try again in a minute.';
    case 'STOCK_TIMEOUT':
    case 'STOCK_HISTORY_TIMEOUT':
    case 'MARKET_TIMEOUT': return 'This took too long. Check again.';
    case 'STOCK_PROVIDER_AUTH_FAILED':
    case 'STOCK_HISTORY_PROVIDER_AUTH_FAILED':
    case 'MARKET_PROVIDER_AUTH_FAILED': return 'The server could not reach its data provider.';
    case 'MARKET_ESTIMATE_STALE': return 'This estimate is out of date. Check again.';
    default: return 'This could not be checked.';
  }
}
