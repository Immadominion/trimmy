import {parseStockResearchConfig} from './config.js';
import {parseStockSearchPage, parseStockVariantsPage} from './discovery.js';
import type {StockSearchPage, StockVariantsPage} from './discovery.js';
import {parseStockEstimate, parseStockEstimateRequest} from './estimate.js';
import type {StockEstimate, StockEstimateRequest} from './estimate.js';
import {parseStockHistoryPage, parseStockHistoryRequest} from './history.js';
import type {StockHistoryPage, StockHistoryRequest} from './history.js';
import {parseRaydiumStockQuote, parseRaydiumStockQuoteRequest} from './raydium.js';
import type {RaydiumStockQuote, RaydiumStockQuoteRequest} from './raydium.js';
import {assetId as validAssetId, integer, invalid, record, text, StockResearchError} from './validation.js';
import {parsePreStocksCatalog} from './prestocks.js';
import type {PreStocksCatalog} from './prestocks.js';

export interface StockReadOptions {readonly signal?: AbortSignal}
export interface StockResearchClientOptions {
  readonly apiOrigin: string; readonly fetch?: typeof globalThis.fetch; readonly timeoutMs?: number;
  readonly allowLoopbackForTests?: boolean; readonly now?: () => number;
}
type StockEndpoint = 'discovery' | 'estimate' | 'raydium' | 'history' | 'prestocks';
const MAX_BYTES_BY_ENDPOINT: Readonly<Record<StockEndpoint, number>> = Object.freeze({
  discovery: 1_048_576, estimate: 262_144, raydium: 65_536, history: 1_048_576, prestocks: 1_048_576,
});
const TIMEOUT_CODE_BY_ENDPOINT: Readonly<Record<StockEndpoint, string>> = Object.freeze({
  discovery: 'STOCK_TIMEOUT', estimate: 'MARKET_TIMEOUT', raydium: 'MARKET_TIMEOUT', history: 'STOCK_HISTORY_TIMEOUT',
  prestocks: 'PRESTOCKS_TIMEOUT',
});
const ERROR_CODES_BY_ENDPOINT: Readonly<Record<StockEndpoint,
  Readonly<Partial<Record<number, readonly string[]>>>>> = Object.freeze({
    discovery: Object.freeze({
      400: Object.freeze(['STOCK_INPUT_INVALID']),
      429: Object.freeze(['STOCK_RATE_LIMITED']),
      502: Object.freeze(['STOCK_PROVIDER_UNAVAILABLE', 'STOCK_RESPONSE_INVALID']),
      503: Object.freeze(['STOCK_DISCOVERY_UNAVAILABLE', 'STOCK_PROVIDER_AUTH_FAILED']),
      504: Object.freeze(['STOCK_TIMEOUT']),
    }),
    estimate: Object.freeze({
      400: Object.freeze(['MARKET_INPUT_INVALID']),
      429: Object.freeze(['MARKET_RATE_LIMITED']),
      502: Object.freeze(['MARKET_PROVIDER_UNAVAILABLE', 'MARKET_RESPONSE_INVALID']),
      503: Object.freeze(['MARKET_UNAVAILABLE', 'MARKET_PROVIDER_AUTH_FAILED']),
      504: Object.freeze(['MARKET_TIMEOUT', 'MARKET_ESTIMATE_STALE']),
    }),
    raydium: Object.freeze({
      400: Object.freeze(['MARKET_INPUT_INVALID']),
      429: Object.freeze(['MARKET_RATE_LIMITED']),
      502: Object.freeze(['MARKET_PROVIDER_AUTH_FAILED', 'MARKET_PROVIDER_UNAVAILABLE', 'MARKET_RESPONSE_INVALID']),
      503: Object.freeze(['MARKET_UNAVAILABLE']),
      504: Object.freeze(['MARKET_TIMEOUT', 'MARKET_ESTIMATE_STALE']),
    }),
    history: Object.freeze({
      400: Object.freeze(['STOCK_HISTORY_INPUT_INVALID']),
      429: Object.freeze(['STOCK_HISTORY_RATE_LIMITED']),
      502: Object.freeze(['STOCK_HISTORY_PROVIDER_UNAVAILABLE', 'STOCK_HISTORY_RESPONSE_INVALID']),
      503: Object.freeze(['STOCK_HISTORY_UNAVAILABLE', 'STOCK_HISTORY_PROVIDER_AUTH_FAILED']),
      504: Object.freeze(['STOCK_HISTORY_TIMEOUT']),
    }),
    prestocks: Object.freeze({
      429: Object.freeze(['PRESTOCKS_RATE_LIMITED']),
      502: Object.freeze(['PRESTOCKS_PROVIDER_UNAVAILABLE', 'PRESTOCKS_RESPONSE_INVALID']),
      503: Object.freeze(['PRESTOCKS_UNAVAILABLE']),
      504: Object.freeze(['PRESTOCKS_TIMEOUT']),
    }),
  });

/** Fixed GET routes. No account state, credentials, cache, retries or mutations. */
export class StockResearchClient {
  readonly #origin: string; readonly #fetch: typeof globalThis.fetch; readonly #timeout: number; readonly #now: () => number;
  readonly #active = new Set<() => void>(); #closed = false;
  constructor(options: StockResearchClientOptions) {
    const config = parseStockResearchConfig(options.apiOrigin, {allowLoopbackForTests: options.allowLoopbackForTests ?? false});
    const timeout = options.timeoutMs ?? 10000;
    const fetch = options.fetch ?? globalThis.fetch, now = options.now ?? Date.now;
    if (config.kind !== 'enabled' || typeof fetch !== 'function' || typeof now !== 'function' ||
        !Number.isInteger(timeout) || timeout < 1 || timeout > 30000) throw new StockResearchError('STOCK_INVALID_CONFIGURATION');
    this.#origin = config.apiOrigin; this.#fetch = fetch; this.#timeout = timeout; this.#now = now;
  }
  async search(query: string, options: StockReadOptions & {readonly limit?: number} = {}): Promise<StockSearchPage> {
    const limit = options.limit ?? 10;
    try { text(query, 80); integer(limit, 1, 20); } catch { throw new StockResearchError('STOCK_INPUT_INVALID'); }
    const result = parseStockSearchPage(await this.#get('/v1/markets/stocks/search', {query, limit: String(limit)}, 'discovery', options.signal));
    if (result.query !== query || result.limit !== limit) invalid(); this.#check(options.signal); return result;
  }
  async variants(assetId: string, options: StockReadOptions = {}): Promise<StockVariantsPage> {
    try { validAssetId(assetId); } catch { throw new StockResearchError('STOCK_INPUT_INVALID'); }
    const result = parseStockVariantsPage(await this.#get('/v1/markets/stocks/variants', {assetId}, 'discovery', options.signal));
    if (result.assetId !== assetId) invalid(); this.#check(options.signal); return result;
  }
  async estimate(input: StockEstimateRequest, options: StockReadOptions = {}): Promise<StockEstimate> {
    const request = parseStockEstimateRequest(input); // Clone before await: later caller mutations cannot change the command.
    const result = parseStockEstimate(await this.#get('/v1/markets/stocks/estimate', {...request}, 'estimate', options.signal));
    if (result.assetId !== request.assetId || result.variantMint !== request.variantMint || result.side !== request.side ||
        result.input.amountRaw !== request.amountRaw) invalid(); this.#check(options.signal); return result;
  }
  /** Separate Raydium comparison read. It is never selected as an execution venue. */
  async raydiumQuote(input: RaydiumStockQuoteRequest, options: StockReadOptions = {}): Promise<RaydiumStockQuote> {
    const request = parseRaydiumStockQuoteRequest(input);
    this.#clock(); // Reject a broken injected clock before dispatching a time-sensitive quote read.
    const result = parseRaydiumStockQuote(await this.#get('/v1/markets/stocks/quotes/raydium', {...request}, 'raydium', options.signal));
    if (result.assetId !== request.assetId || result.variantMint !== request.variantMint || result.side !== request.side ||
        result.input.amountRaw !== request.amountRaw) invalid();
    this.#assertFresh(result.receivedAt, result.refreshAfter, 'MARKET_ESTIMATE_STALE');
    this.#check(options.signal); return result;
  }
  /** Mint-specific Tokens.xyz history. This does not represent canonical Apple equity history. */
  async history(input: StockHistoryRequest, options: StockReadOptions = {}): Promise<StockHistoryPage> {
    const request = parseStockHistoryRequest(input, Math.floor(this.#clock() / 1000));
    const result = parseStockHistoryPage(await this.#get('/v1/markets/stocks/history', {...request}, 'history', options.signal), request);
    if (result.assetId !== request.assetId || result.variantMint !== request.variantMint || result.interval !== request.interval ||
        result.fromUnixSeconds !== request.fromUnixSeconds || result.toUnixSeconds !== request.toUnixSeconds) invalid();
    this.#assertFresh(result.provenance.observedAt, result.provenance.refreshAfter, 'STOCK_HISTORY_RESPONSE_INVALID');
    this.#check(options.signal); return result;
  }
  /** Read-only pre-IPO catalog. No account, amount or execution input exists. */
  async preStocks(options: StockReadOptions = {}): Promise<PreStocksCatalog> {
    const result = parsePreStocksCatalog(await this.#get('/v1/markets/prestocks', {}, 'prestocks', options.signal));
    this.#assertFresh(result.observedAt, result.refreshAfter, 'PRESTOCKS_TIMEOUT');
    this.#check(options.signal); return result;
  }
  close(): void { this.#closed = true; for (const cancel of [...this.#active]) cancel(); }
  #check(signal: AbortSignal | undefined): void {
    if (this.#closed || signal?.aborted) throw new StockResearchError('STOCK_CANCELLED');
  }
  #clock(): number {
    let now: number;
    try { now = this.#now(); } catch { throw new StockResearchError('STOCK_INVALID_CONFIGURATION'); }
    if (!Number.isSafeInteger(now) || now < 0 || now > 8_639_999_999_000_000) {
      throw new StockResearchError('STOCK_INVALID_CONFIGURATION');
    }
    return now;
  }
  #assertFresh(observedAt: string, refreshAfter: string, staleCode: string): void {
    const now = this.#clock(), observed = Date.parse(observedAt), refresh = Date.parse(refreshAfter);
    if (!Number.isFinite(observed) || !Number.isFinite(refresh) || observed > now + 60_000) invalid();
    if (now >= refresh) throw new StockResearchError(staleCode);
  }
  async #get(path: string, query: Record<string, string>, endpoint: StockEndpoint,
    signal: AbortSignal | undefined): Promise<unknown> {
    this.#check(signal);
    const controller = new AbortController();
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let body: ReadableStream<Uint8Array> | undefined;
    let failure: StockResearchError | undefined;
    let rejectStop!: (error: StockResearchError) => void;
    const stopped = new Promise<never>((_, reject) => { rejectStop = reject; });
    const stop = (code: string): void => {
      if (failure) return; failure = new StockResearchError(code);
      controller.abort(); void reader?.cancel().catch(() => {}); rejectStop(failure);
    };
    const cancel = (): void => stop('STOCK_CANCELLED');
    this.#active.add(cancel); signal?.addEventListener('abort', cancel, {once: true});
    const timer = setTimeout(() => stop(TIMEOUT_CODE_BY_ENDPOINT[endpoint]), this.#timeout);
    const perform = async (): Promise<unknown> => {
      try {
        const url = new URL(path, this.#origin); url.search = new URLSearchParams(query).toString();
        const maximumBytes = MAX_BYTES_BY_ENDPOINT[endpoint];
        const response = await this.#fetch(url, {method: 'GET', headers: {accept: 'application/json'},
          credentials: 'omit', cache: 'no-store', redirect: 'error', signal: controller.signal});
        if (failure) { void response.body?.cancel().catch(() => {}); throw failure; }
        body = response.body ?? undefined;
        if (response.redirected || response.status >= 300 && response.status < 400) throw new StockResearchError('STOCK_REDIRECT_REJECTED');
        if (response.url !== '') {
          let finalUrl: URL;
          try { finalUrl = new URL(response.url); } catch { throw new StockResearchError('STOCK_REDIRECT_REJECTED'); }
          if (finalUrl.origin !== this.#origin || finalUrl.href !== url.href) {
            throw new StockResearchError('STOCK_REDIRECT_REJECTED');
          }
        }
        const length = response.headers.get('content-length');
        if (length !== null && (!/^(0|[1-9]\d*)$/u.test(length) || Number(length) > maximumBytes)) {
          throw new StockResearchError('STOCK_RESPONSE_TOO_LARGE');
        }
        if (!response.body) invalid();
        const contentType = response.headers.get('content-type')?.toLowerCase().split(';').map(part => part.trim());
        if (!contentType || contentType[0] !== 'application/json' ||
            contentType.slice(1).some(part => part !== 'charset=utf-8' && part !== 'charset="utf-8"')) invalid();
        reader = response.body.getReader();
        const chunks: Uint8Array[] = []; let size = 0;
        while (true) {
          const next = await reader.read(); if (failure) throw failure;
          if (next.done) break; size += next.value.byteLength;
          if (size > maximumBytes) throw new StockResearchError('STOCK_RESPONSE_TOO_LARGE'); chunks.push(next.value);
        }
        reader.releaseLock(); reader = undefined;
        const bytes = new Uint8Array(size); let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
        let value: unknown;
        try { value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)); } catch { invalid(); }
        if (response.status !== 200) serverFailure(endpoint, response.status, value);
        return value;
      } catch (error) {
        controller.abort();
        if (reader) void reader.cancel().catch(() => {});
        else void body?.cancel().catch(() => {});
        if (failure) throw failure; if (error instanceof StockResearchError) throw error;
        throw new StockResearchError('STOCK_NETWORK_ERROR');
      }
    };
    try { return await Promise.race([perform(), stopped]); }
    finally { clearTimeout(timer); signal?.removeEventListener('abort', cancel); this.#active.delete(cancel); }
  }
}
function safeErrorCode(value: unknown): string | undefined {
  try {
    const envelope = record(value, ['error']);
    const error = record(envelope.error, ['code', 'message', 'requestId']);
    if (typeof error.code !== 'string' || typeof error.message !== 'string' || error.message.length > 1024 ||
        typeof error.requestId !== 'string' || error.requestId.length < 1 || error.requestId.length > 128) return undefined;
    return error.code;
  } catch { return undefined; }
}
function serverFailure(endpoint: StockEndpoint, status: number, value: unknown): never {
  const code = safeErrorCode(value);
  if (code !== undefined && ERROR_CODES_BY_ENDPOINT[endpoint][status]?.includes(code)) throw new StockResearchError(code);
  throw new StockResearchError('STOCK_SERVICE_UNAVAILABLE');
}
