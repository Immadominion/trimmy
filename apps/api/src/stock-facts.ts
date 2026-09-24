import { BoundedProviderRead } from './bounded-provider-read.js';
import type { BoundedProviderReadConfiguration } from './bounded-provider-read.js';

/**
 * Display-only company facts from Tokens.xyz for the Market cards and the
 * stock page: the underlying stock's daily change, a logo, a short company
 * description and a seven-day sparkline. Every value is a projection for
 * reading. Nothing here approves an asset, prices an order or authorizes
 * execution. Missing facts stay null; they are never invented.
 * https://docs.tokens.xyz/v1/endpoints/assets
 * https://docs.tokens.xyz/v1/endpoints/asset-by-id
 */
export interface StockCardsInput { readonly query: string; readonly limit?: number }
export interface StockFactsInput { readonly assetId: string }
export interface StockSessionSnapshot {
  /** The underlying listed stock, not the on-chain token. */
  readonly priceUsd: number | null;
  /** Percent, may be negative. Null when the provider omits it. */
  readonly changePercent24h: number | null;
  /** Provider session time in Unix seconds, or null. */
  readonly asOfUnixSeconds: number | null;
}
export interface StockCardVariant {
  readonly mint: string;
  readonly symbol: string | null;
  readonly logoUrl: string | null;
  readonly priceUsd: number | null;
  readonly changePercent24h: number | null;
}
export interface StockCard {
  readonly assetId: string;
  readonly name: string | null;
  readonly symbol: string | null;
  readonly imageUrl: string | null;
  readonly stock: StockSessionSnapshot | null;
  readonly primaryVariant: StockCardVariant | null;
}
interface FactsProvenance {
  readonly schemaVersion: 1;
  readonly provider: 'tokens-xyz-v1';
  readonly requestedAt: string;
  readonly observedAt: string;
  readonly refreshAfter: string;
  readonly displayOnly: true;
  readonly executionEnabled: false;
  readonly eligibility: 'unverified';
}
export interface StockCardsPage extends FactsProvenance {
  readonly sourceUrl: string;
  readonly query: string;
  readonly limit: number;
  readonly completeCatalog: false;
  readonly results: readonly StockCard[];
}
export interface StockSparklinePoint { readonly unixSeconds: number; readonly close: number }
export interface StockSparkline {
  readonly interval: '4H';
  readonly fromUnixSeconds: number;
  readonly toUnixSeconds: number;
  readonly points: readonly StockSparklinePoint[];
}
export interface StockFacts extends FactsProvenance {
  readonly sourceUrls: readonly string[];
  readonly assetId: string;
  readonly name: string | null;
  readonly symbol: string | null;
  readonly imageUrl: string | null;
  /** Plain company description, cut to a short readable length. */
  readonly description: string | null;
  readonly stock: StockSessionSnapshot | null;
  readonly sparkline: StockSparkline | null;
  readonly sparklineStatus: 'observed' | 'empty' | 'unavailable';
}
export type StockInsightPeriod = 'day' | 'week' | 'month' | 'year';
export interface StockInsightInput { readonly assetId: string; readonly mint: string; readonly period: StockInsightPeriod }
export interface StockInsight extends FactsProvenance {
  readonly assetId: string; readonly mint: string; readonly period: StockInsightPeriod;
  readonly symbol: string | null; readonly description: string | null;
  readonly priceUsd: number | null; readonly changePercent24h: number | null;
  readonly asOfUnixSeconds: number | null;
  readonly volume24hUsd: number | null; readonly liquidityUsd: number | null;
  readonly tokenMarketCapUsd: number | null; readonly stockMarketCapUsd: number | null;
  readonly holders: number | null;
  readonly points: readonly StockSparklinePoint[];
  readonly chartStatus: 'observed' | 'empty' | 'unavailable';
}
export interface StockFactsReader {
  insight?(input: StockInsightInput): Promise<StockInsight>;
  cards(input: StockCardsInput): Promise<StockCardsPage>;
  facts(input: StockFactsInput): Promise<StockFacts>;
}
export type StockFactsErrorCode = 'STOCK_FACTS_INPUT_INVALID' | 'STOCK_FACTS_UNAVAILABLE' |
  'STOCK_FACTS_PROVIDER_AUTH_FAILED' | 'STOCK_FACTS_PROVIDER_UNAVAILABLE' | 'STOCK_FACTS_RATE_LIMITED' |
  'STOCK_FACTS_RESPONSE_INVALID' | 'STOCK_FACTS_TIMEOUT';
const messages: Record<StockFactsErrorCode, string> = {
  STOCK_FACTS_INPUT_INVALID: 'Enter a valid stock search or asset identifier.',
  STOCK_FACTS_UNAVAILABLE: 'Company facts are not configured.',
  STOCK_FACTS_PROVIDER_AUTH_FAILED: 'The stock data provider requires a valid key with read access.',
  STOCK_FACTS_PROVIDER_UNAVAILABLE: 'Company facts are unavailable. Try again later.',
  STOCK_FACTS_RATE_LIMITED: 'Wait before requesting company facts again.',
  STOCK_FACTS_RESPONSE_INVALID: 'The stock provider returned unusable company data.',
  STOCK_FACTS_TIMEOUT: 'The company facts request took too long.',
};
export class StockFactsError extends Error {
  constructor(readonly code: StockFactsErrorCode) { super(messages[code]); this.name = 'StockFactsError'; }
}
function invalid(): never { throw new StockFactsError('STOCK_FACTS_RESPONSE_INVALID'); }
function badInput(): never { throw new StockFactsError('STOCK_FACTS_INPUT_INVALID'); }
function record(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
}
/** Absent, null or an empty string all read as "not provided". */
function optionalText(value: unknown, max: number): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || value.length > max || /[\u0000-\u001f\u007f]/u.test(value)) invalid();
  const trimmed = value.trim();
  return trimmed.length ? trimmed : null;
}
function optionalNumber(value: unknown, minimum: number, maximum: number): number | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum || value > maximum) invalid();
  return value;
}
function optionalUnixSeconds(value: unknown): number | null {
  const result = optionalNumber(value, 0, 8_640_000_000_000);
  if (result !== null && !Number.isSafeInteger(result)) invalid();
  return result;
}
const isSlug = (value: unknown): value is string => typeof value === 'string' && value.length <= 100 &&
  /^[a-z0-9]+(?:-[a-z0-9]+)*$/u.exec(value)?.[0] === value;
/** Encoding and length only; ownership and extensions are not inspected here. */
function optionalMint(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string' || value.length < 32 || value.length > 44 ||
    /^[1-9A-HJ-NP-Za-km-z]+$/u.exec(value)?.[0] !== value) invalid();
  return value;
}
/** Only issuer and provider image hosts are passed through; anything else stays null. */
const imageHosts: ReadonlySet<string> = new Set(['api.tokens.xyz', 'xstocks-metadata.backed.fi', 'cdn.ondo.finance']);
export function safeImageUrl(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') invalid();
  if (!value.length || value.length > 2048) return null;
  let url: URL;
  try { url = new URL(value); } catch { return null; }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || !(imageHosts.has(url.hostname) || url.hostname === 'storage.googleapis.com' &&
    /^\/tokens-asset-logos-prd\/solana\/[1-9A-HJ-NP-Za-km-z]{32,44}\.webp$/u.test(url.pathname))) return null;
  return url.href;
}
const maxDescription = 400;
/** Cuts a long provider description at a sentence end when one exists. */
export function shortDescription(value: string | null): string | null {
  if (value === null) return null;
  const clean = value.replace(/\s+/gu, ' ').trim();
  if (!clean.length) return null;
  if (clean.length <= maxDescription) return clean;
  const window = clean.slice(0, maxDescription);
  const sentenceEnd = Math.max(window.lastIndexOf('. '), window.lastIndexOf('.'));
  if (sentenceEnd >= 120) return window.slice(0, sentenceEnd + 1);
  const wordEnd = window.lastIndexOf(' ');
  return `${window.slice(0, wordEnd > 120 ? wordEnd : maxDescription).trimEnd()}…`;
}
const changeLimit = 1_000_000;
function session(value: unknown): StockSessionSnapshot | null {
  if (value === undefined || value === null) return null;
  const data = record(value);
  return Object.freeze({priceUsd: optionalNumber(data['price'], 0, Number.MAX_SAFE_INTEGER),
    changePercent24h: optionalNumber(data['priceChange24hPercent'], -changeLimit, changeLimit),
    asOfUnixSeconds: optionalUnixSeconds(data['asOf'])});
}
function cardVariant(value: unknown): StockCardVariant | null {
  if (value === undefined || value === null) return null;
  const data = record(value);
  const mint = optionalMint(data['mint']);
  if (mint === null) invalid();
  const market = data['market'] === undefined || data['market'] === null ? null : record(data['market']);
  return Object.freeze({mint, symbol: optionalText(data['symbol'], 40),
    logoUrl: market === null ? null : safeImageUrl(market['logoURI']),
    priceUsd: market === null ? null : optionalNumber(market['price'], 0, Number.MAX_SAFE_INTEGER),
    changePercent24h: market === null ? null : optionalNumber(market['priceChange24hPercent'], -changeLimit, changeLimit)});
}
export function stockCard(value: unknown): StockCard {
  const data = record(value);
  if (!isSlug(data['assetId']) || data['category'] !== 'equity') invalid();
  return Object.freeze({assetId: data['assetId'], name: optionalText(data['name'], 200), symbol: optionalText(data['symbol'], 40),
    imageUrl: safeImageUrl(data['imageUrl']), stock: session(data['canonicalMarket']),
    primaryVariant: cardVariant(data['primaryVariant'])});
}
function cardsInput(value: StockCardsInput): {query: string; limit: number} {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
    Object.keys(value).some(key => !['query', 'limit'].includes(key))) badInput();
  const query = value.query;
  if (typeof query !== 'string' || query.trim() !== query || query.length < 1 || query.length > 80 || /[\u0000-\u001f\u007f]/u.test(query)) badInput();
  const limit = value.limit ?? 10;
  if (!Number.isInteger(limit) || limit < 1 || limit > 20) badInput();
  return {query, limit};
}
const sparklineDays = 7;
const sparklineInterval = 4 * 3_600;
const maxSparklinePoints = 64;
function sparkline(value: unknown, from: number, to: number): {sparkline: StockSparkline | null; status: 'observed' | 'empty'} {
  const data = record(value);
  if (data['interval'] !== '4H') invalid();
  const raw = data['candles'];
  if (!Array.isArray(raw) || raw.length > 4_096) invalid();
  const points: StockSparklinePoint[] = [];
  for (const item of raw) {
    const candle = record(item);
    const unixSeconds = optionalUnixSeconds(candle['time']);
    const close = optionalNumber(candle['close'], 0, Number.MAX_SAFE_INTEGER);
    if (unixSeconds === null || close === null) invalid();
    if (unixSeconds < from - sparklineInterval || unixSeconds > to + sparklineInterval) invalid();
    points.push(Object.freeze({unixSeconds, close}));
  }
  points.sort((left, right) => left.unixSeconds - right.unixSeconds);
  for (let index = 1; index < points.length; index++) {
    if (points[index]!.unixSeconds === points[index - 1]!.unixSeconds) invalid();
  }
  if (!points.length) return {sparkline: null, status: 'empty'};
  const kept = points.length <= maxSparklinePoints ? points :
    Array.from({length: maxSparklinePoints}, (_, index) => points[Math.floor(index * (points.length - 1) / (maxSparklinePoints - 1))]!);
  return {sparkline: Object.freeze({interval: '4H', fromUnixSeconds: from, toUnixSeconds: to, points: Object.freeze(kept)}), status: 'observed'};
}

export interface TokensStockFactsOptions {
  readonly apiKey: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
  /** Production starts at most one provider request each second. */
  readonly paceMs?: number;
  readonly wait?: (durationMs: number) => Promise<void>;
  readonly protection?: Partial<Omit<BoundedProviderReadConfiguration, 'now'>>;
}
const origin = 'https://api.tokens.xyz';
const byteLimit = 1_048_576;
const freshnessMs = 60_000;
type Received = {payload: unknown; sourceUrl: string; started: number; ended: number};
/** Explicit server key; never reads credentials itself or falls back to keyless. */
export class TokensStockFacts implements StockFactsReader {
  readonly #key: string;
  readonly #fetch: typeof globalThis.fetch;
  readonly #now: () => number;
  readonly #timeout: number;
  readonly #pace: number;
  readonly #wait: (durationMs: number) => Promise<void>;
  readonly #reads: BoundedProviderRead<StockCardsPage | StockFacts | StockInsight>;
  #nextRequestAt = 0;
  #providerRetryAt = 0;
  #dispatchTail: Promise<void> = Promise.resolve();
  constructor(options: TokensStockFactsOptions) {
    if (!options || typeof options.apiKey !== 'string' || options.apiKey.length < 8 || options.apiKey.length > 512 ||
      /^[\x21-\x7e]+$/u.exec(options.apiKey)?.[0] !== options.apiKey) throw new StockFactsError('STOCK_FACTS_UNAVAILABLE');
    this.#key = options.apiKey; this.#fetch = options.fetch ?? globalThis.fetch; this.#now = options.now ?? Date.now;
    this.#timeout = options.timeoutMs ?? 6000;
    this.#pace = options.paceMs ?? 1000;
    this.#wait = options.wait ?? (durationMs => new Promise(resolve => setTimeout(resolve, durationMs)));
    if (!Number.isInteger(this.#timeout) || this.#timeout < 1 || this.#timeout > 8000) throw new StockFactsError('STOCK_FACTS_UNAVAILABLE');
    if (!Number.isInteger(this.#pace) || this.#pace < 1 || this.#pace > 10_000 || typeof this.#wait !== 'function') {
      throw new StockFactsError('STOCK_FACTS_UNAVAILABLE');
    }
    this.#reads = new BoundedProviderRead<StockCardsPage | StockFacts | StockInsight>({
      cacheTtlMs: 60_000,
      rateLimitWindowMs: 60_000,
      perKeyLimit: 12,
      globalLimit: 90,
      maxTrackedKeys: 256,
      maxCacheEntries: 256,
      maxConcurrentReads: 6,
      ...options.protection,
      now: this.#now,
    }, {
      configurationInvalid: () => new StockFactsError('STOCK_FACTS_UNAVAILABLE'),
      rateLimited: () => new StockFactsError('STOCK_FACTS_RATE_LIMITED'),
    });
  }
  async cards(input: StockCardsInput): Promise<StockCardsPage> {
    const request = cardsInput(input);
    const url = new URL('/v1/assets/search', origin);
    url.search = new URLSearchParams({q: request.query, category: 'equity', variants: 'all',
      primaryVariantStrategy: 'liquidity', limit: String(request.limit)}).toString();
    const result = await this.#reads.read(`cards:${request.limit}:${request.query}`, `cards:${request.query}`, async () => {
      const received = await this.#schedule(() => this.#get(url));
      const data = record(received.payload);
      if (data['query'] !== request.query || data['category'] !== 'equity' || !Array.isArray(data['results']) ||
        data['results'].length > request.limit) invalid();
      const rows = data['results'].map(stockCard);
      if (new Set(rows.map(row => row.assetId)).size !== rows.length) invalid();
      return Object.freeze({...this.#provenance(received), sourceUrl: received.sourceUrl, ...request, completeCatalog: false,
        results: Object.freeze(rows)}) as StockCardsPage;
    });
    return result as StockCardsPage;
  }
  async facts(input: StockFactsInput): Promise<StockFacts> {
    if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).some(key => key !== 'assetId') || !isSlug(input.assetId)) badInput();
    const requestedId = input.assetId;
    const result = await this.#reads.read(`facts:${requestedId}`, `facts:${requestedId}`, async () => {
      const detailUrl = new URL(`/v1/assets/${encodeURIComponent(requestedId)}`, origin);
      const detail = await this.#schedule(() => this.#get(detailUrl));
      const root = record(detail.payload);
      const asset = record(root['asset']);
      if (asset['assetId'] !== requestedId || asset['category'] !== 'equity') invalid();
      const identity = {name: optionalText(asset['name'], 200), symbol: optionalText(asset['symbol'], 40),
        imageUrl: safeImageUrl(asset['imageUrl']), description: shortDescription(optionalText(asset['description'], 4_096)),
        stock: session(asset['canonicalMarket'])};
      const to = Math.floor(detail.ended / 1000);
      const from = to - sparklineDays * 86_400;
      const chartUrl = new URL(`/v1/assets/${encodeURIComponent(requestedId)}/price-chart`, origin);
      chartUrl.search = new URLSearchParams({interval: '4H', from: String(from), to: String(to)}).toString();
      let chart: Received | null = null;
      try { chart = await this.#schedule(() => this.#get(chartUrl)); }
      catch (error) {
        // The description and change stay useful when only the chart failed.
        if (!(error instanceof StockFactsError) || error.code === 'STOCK_FACTS_PROVIDER_AUTH_FAILED') throw error;
      }
      let line: {sparkline: StockSparkline | null; status: StockFacts['sparklineStatus']} = {sparkline: null, status: 'unavailable'};
      if (chart !== null) {
        const chartRoot = record(chart.payload);
        if (chartRoot['assetId'] !== requestedId) invalid();
        line = sparkline(chartRoot, from, to);
      }
      const last = chart ?? detail;
      return Object.freeze({...this.#provenance({started: detail.started, ended: last.ended}), assetId: requestedId,
        sourceUrls: Object.freeze(chart ? [detail.sourceUrl, chart.sourceUrl] : [detail.sourceUrl]), ...identity,
        sparkline: line.sparkline, sparklineStatus: line.status}) as StockFacts;
    });
    return result as StockFacts;
  }
  async insight(input: StockInsightInput): Promise<StockInsight> {
    const ranges = {day: ['1H', 3600, 1], week: ['1H', 3600, 7], month: ['4H', 14400, 30], year: ['1D', 86400, 365]} as const;
    if (!input || Object.keys(input).some(key => !['assetId', 'mint', 'period'].includes(key)) ||
      !isSlug(input.assetId) || !Object.hasOwn(ranges, input.period)) badInput();
    // Validate request mints as input errors, without leaking provider bodies.
    if (typeof input.mint !== 'string' || !/^[1-9A-HJ-NP-Za-km-z]{32,44}$/u.test(input.mint)) badInput();
    const {assetId, mint, period} = input;
    return await this.#reads.read(`insight:${assetId}:${mint}:${period}`, `insight:${assetId}:${mint}`, async () => {
      const url = new URL(`/v1/assets/${encodeURIComponent(assetId)}`, origin);
      url.searchParams.set('primaryVariantStrategy', 'liquidity');
      const detail = await this.#schedule(() => this.#get(url));
      const asset = record(record(detail.payload)['asset']);
      if (asset['assetId'] !== assetId || asset['category'] !== 'equity') invalid();
      const groups = asset['variantGroups'] == null ? {} : record(asset['variantGroups']);
      const variants = [asset['primaryVariant'], ...Object.values(groups).flat(),
        ...(Array.isArray(asset['variants']) ? asset['variants'] : [])];
      const variant = variants.find(row => row && typeof row === 'object' && !Array.isArray(row) &&
        (row as Record<string, unknown>)['mint'] === mint);
      if (!variant) badInput();
      const v = record(variant);
      const market = v['market'] == null ? {} : record(v['market']);
      const stock = asset['canonicalMarket'] == null ? {} : record(asset['canonicalMarket']);
      const [interval, seconds, days] = ranges[period];
      const to = Math.floor(detail.ended / 1000); const from = to - days * 86400;
      const chartUrl = new URL(`/v1/assets/${encodeURIComponent(assetId)}/ohlcv`, origin);
      chartUrl.search = new URLSearchParams({mint, interval, from: String(from), to: String(to)}).toString();
      let points: StockSparklinePoint[] = [];
      let chartStatus: StockInsight['chartStatus'] = 'unavailable';
      let ended = detail.ended;
      try {
        const chart = await this.#schedule(() => this.#get(chartUrl)); ended = chart.ended;
        const data = record(chart.payload);
        if (data['assetId'] !== assetId || data['mint'] !== mint || data['interval'] !== interval ||
          !Array.isArray(data['candles']) || data['candles'].length > 4096) invalid();
        points = data['candles'].map(value => {
          const row = record(value); const unixSeconds = optionalUnixSeconds(row['time']);
          const close = optionalNumber(row['close'], 0, Number.MAX_SAFE_INTEGER);
          if (unixSeconds === null || close === null || unixSeconds < from - seconds || unixSeconds > to) invalid();
          return {unixSeconds, close};
        }).sort((a, b) => a.unixSeconds - b.unixSeconds);
        if (points.some((point, index) => index > 0 && point.unixSeconds === points[index - 1]!.unixSeconds)) invalid();
        // Keep actual samples and their timestamps, never interpolate prices.
        if (points.length > 400) points = Array.from({length: 400}, (_, i) => points[Math.floor(i * (points.length - 1) / 399)]!);
        chartStatus = points.length ? 'observed' : 'empty';
      } catch (error) {
        if (!(error instanceof StockFactsError) || error.code === 'STOCK_FACTS_PROVIDER_AUTH_FAILED') throw error;
        points = []; // A chart failure must not discard the useful snapshot.
      }
      const metric = (key: string) => optionalNumber(market[key], 0, Number.MAX_SAFE_INTEGER);
      const holders = metric('holder');
      if (holders !== null && !Number.isSafeInteger(holders)) invalid();
      const updatedMs = metric('lastFetchedAt');
      return Object.freeze({...this.#provenance({started: detail.started, ended}), assetId, mint, period,
        symbol: optionalText(v['symbol'], 40), description: shortDescription(optionalText(asset['description'], 4096)),
        priceUsd: metric('price'), changePercent24h: optionalNumber(market['priceChange24hPercent'], -changeLimit, changeLimit),
        asOfUnixSeconds: updatedMs === null ? null : Math.floor(updatedMs / 1000),
        volume24hUsd: metric('volume24hUSD'), liquidityUsd: metric('liquidity'), tokenMarketCapUsd: metric('marketCap'),
        stockMarketCapUsd: optionalNumber(stock['marketCap'], 0, Number.MAX_SAFE_INTEGER), holders,
        points: Object.freeze(points), chartStatus});
    }) as StockInsight;
  }
  #provenance(received: {started: number; ended: number}): FactsProvenance {
    return Object.freeze({schemaVersion: 1, provider: 'tokens-xyz-v1', requestedAt: new Date(received.started).toISOString(),
      observedAt: new Date(received.ended).toISOString(), refreshAfter: new Date(received.started + freshnessMs).toISOString(),
      displayOnly: true, executionEnabled: false, eligibility: 'unverified'});
  }
  #timestamp(): number {
    let value: number;
    try { value = this.#now(); }
    catch { throw new StockFactsError('STOCK_FACTS_UNAVAILABLE'); }
    if (!Number.isSafeInteger(value) || value < 0 || value > 8_639_999_999_000_000) throw new StockFactsError('STOCK_FACTS_UNAVAILABLE');
    return value;
  }
  async #schedule<T>(load: () => Promise<T>): Promise<T> {
    let release!: () => void;
    const turn = new Promise<void>(resolve => { release = resolve; });
    const previous = this.#dispatchTail;
    this.#dispatchTail = turn;
    await previous;
    let pending: Promise<T>;
    try {
      let current = this.#timestamp();
      if (current < this.#providerRetryAt) throw new StockFactsError('STOCK_FACTS_RATE_LIMITED');
      for (let waits = 0; current < this.#nextRequestAt; waits++) {
        if (waits >= 3) throw new StockFactsError('STOCK_FACTS_PROVIDER_UNAVAILABLE');
        try { await this.#wait(this.#nextRequestAt - current); }
        catch { throw new StockFactsError('STOCK_FACTS_PROVIDER_UNAVAILABLE'); }
        current = this.#timestamp();
        if (current < this.#providerRetryAt) throw new StockFactsError('STOCK_FACTS_RATE_LIMITED');
      }
      this.#nextRequestAt = Math.max(current, this.#nextRequestAt) + this.#pace;
      pending = load();
    } catch (error) {
      release();
      if (error instanceof StockFactsError) throw error;
      throw new StockFactsError('STOCK_FACTS_PROVIDER_UNAVAILABLE');
    }
    release();
    return pending;
  }
  async #get(url: URL): Promise<Received> {
    const started = this.#timestamp();
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new StockFactsError('STOCK_FACTS_TIMEOUT')); }, this.#timeout);
    });
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
      const pendingResponse = this.#fetch(url, {method: 'GET', headers: {accept: 'application/json', 'x-api-key': this.#key},
        redirect: 'error', signal: controller.signal});
      void pendingResponse.then(response => {
        if (controller.signal.aborted) { try { void response.body?.cancel().catch(() => {}); } catch { /* disposal only */ } }
      }, () => {});
      const response = await Promise.race([pendingResponse, deadline]);
      if (response.redirected || response.url && new URL(response.url).origin !== origin) invalid();
      if (response.status === 401 || response.status === 403) throw new StockFactsError('STOCK_FACTS_PROVIDER_AUTH_FAILED');
      if (response.status === 429) {
        this.#providerRetryAt = Math.max(this.#providerRetryAt, this.#timestamp() + 60_000);
        throw new StockFactsError('STOCK_FACTS_RATE_LIMITED');
      }
      if (!response.ok) throw new StockFactsError('STOCK_FACTS_PROVIDER_UNAVAILABLE');
      if (!/^application\/json(?:\s*;|$)/iu.test(response.headers.get('content-type') ?? '') || !response.body) invalid();
      const length = response.headers.get('content-length');
      if (length !== null && (!/^\d+$/u.test(length) || Number(length) > byteLimit)) invalid();
      reader = response.body.getReader();
      const chunks: Uint8Array[] = []; let bytes = 0;
      for (;;) {
        const part = await Promise.race([reader.read(), deadline]); if (part.done) break;
        bytes += part.value.byteLength; if (bytes > byteLimit) invalid(); chunks.push(part.value);
      }
      const payload: unknown = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
      if (controller.signal.aborted) throw new StockFactsError('STOCK_FACTS_TIMEOUT');
      const ended = this.#timestamp();
      if (!Number.isSafeInteger(ended) || ended < started || ended >= started + freshnessMs) throw new StockFactsError('STOCK_FACTS_TIMEOUT');
      return {payload, sourceUrl: url.href, started, ended};
    } catch (error) {
      if (controller.signal.aborted) throw new StockFactsError('STOCK_FACTS_TIMEOUT');
      if (error instanceof StockFactsError) throw error;
      if (error instanceof SyntaxError || error instanceof TypeError && reader !== undefined) invalid();
      throw new StockFactsError('STOCK_FACTS_PROVIDER_UNAVAILABLE');
    } finally {
      clearTimeout(timer); controller.abort();
      if (reader) { try { void reader.cancel().catch(() => {}); } catch { /* disposal only */ } }
    }
  }
}
/** Shares the discovery provider switch and key; facts are enabled exactly when discovery is. */
export function readStockFacts(env: Readonly<Record<string, string | undefined>>): TokensStockFacts | undefined {
  const mode = env['TRIMMY_STOCK_DISCOVERY'];
  if (mode === undefined || mode === '' || mode === 'disabled') return undefined;
  if (mode !== 'tokens_xyz' || !env['TOKENS_API_KEY']) throw new StockFactsError('STOCK_FACTS_UNAVAILABLE');
  return new TokensStockFacts({apiKey: env['TOKENS_API_KEY']});
}
