import {parseStockSearchPage, parseStockVariantsPage} from '../markets/discovery.js';
import type {StockSearchPage, StockVariantsPage} from '../markets/discovery.js';
import {assetId, integer, invalid, list, metric, mint, optionalText, record, schema, sourceUrl,
  StockResearchError, text, timestamp, unique} from '../markets/validation.js';

export type {StockDiscoveryAsset, StockVariant, StockSearchPage, StockVariantsPage} from '../markets/discovery.js';
export {StockResearchError as ProductMarketError} from '../markets/validation.js';

export interface StockSessionSnapshot {
  /** Underlying listed stock. Never substituted for the selected token's price. */
  readonly priceUsd: number | null;
  readonly changePercent24h: number | null;
  readonly asOfUnixSeconds: number | null;
}
export interface StockCardVariant {
  readonly mint: string; readonly symbol: string | null; readonly logoUrl: string | null;
  readonly priceUsd: number | null; readonly changePercent24h: number | null;
}
export interface StockCard {
  readonly assetId: string; readonly name: string | null; readonly symbol: string | null;
  readonly imageUrl: string | null; readonly stock: StockSessionSnapshot | null;
  readonly primaryVariant: StockCardVariant | null;
}
export interface FactsProvenance {
  readonly schemaVersion: 1; readonly provider: 'tokens-xyz-v1';
  readonly requestedAt: string; readonly observedAt: string; readonly refreshAfter: string;
  readonly displayOnly: true; readonly executionEnabled: false; readonly eligibility: 'unverified';
}
export interface StockCatalogPage {
  readonly discovery: StockSearchPage; readonly cards: readonly StockCard[];
  /** Provider offsets include filtered non-equities; never advance by cards.length. */
  readonly offset: number; readonly total: number; readonly nextOffset: number | null;
}
export interface StockCardsPage extends FactsProvenance {
  readonly sourceUrl: string; readonly query: string; readonly limit: number;
  readonly completeCatalog: false; readonly results: readonly StockCard[];
}
export interface StockSparklinePoint {readonly unixSeconds: number; readonly close: number}
export interface StockSparkline {
  readonly interval: '4H'; readonly fromUnixSeconds: number; readonly toUnixSeconds: number;
  readonly points: readonly StockSparklinePoint[];
}
export interface StockFacts extends FactsProvenance {
  readonly sourceUrls: readonly string[]; readonly assetId: string;
  readonly name: string | null; readonly symbol: string | null; readonly imageUrl: string | null;
  readonly description: string | null; readonly stock: StockSessionSnapshot | null;
  readonly sparkline: StockSparkline | null; readonly sparklineStatus: ChartStatus;
}
export type StockInsightPeriod = 'day' | 'week' | 'month' | 'year';
export type ChartStatus = 'observed' | 'empty' | 'unavailable';
export interface StockInsightInput {readonly assetId: string; readonly mint: string; readonly period: StockInsightPeriod}
export interface StockInsight extends FactsProvenance, StockInsightInput {
  readonly symbol: string | null; readonly description: string | null;
  readonly priceUsd: number | null; readonly changePercent24h: number | null;
  readonly asOfUnixSeconds: number | null; readonly volume24hUsd: number | null;
  readonly liquidityUsd: number | null; readonly tokenMarketCapUsd: number | null;
  readonly stockMarketCapUsd: number | null; readonly holders: number | null;
  readonly points: readonly StockSparklinePoint[]; readonly chartStatus: ChartStatus;
}
export interface ProductMarketOptions {
  /** Explicit same-origin relay, or a canonical HTTPS API origin. No credentials. */
  readonly baseUrl: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly timeoutMs?: number;
}
export interface MarketReadOptions {readonly signal?: AbortSignal}
export interface MarketSearchOptions extends MarketReadOptions {readonly limit?: number}

const factsKeys = ['schemaVersion', 'provider', 'requestedAt', 'observedAt', 'refreshAfter',
  'displayOnly', 'executionEnabled', 'eligibility'];
const unix = (value: unknown): number => integer(value, 0, 8_640_000_000_000);
const optionalUnix = (value: unknown): number | null => value === null ? null : unix(value);
function change(value: unknown): number | null {
  if (value === null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || Math.abs(value) > 1_000_000) invalid();
  return value;
}
function imageUrl(value: unknown): string | null {
  if (value === null) return null;
  const result = sourceUrl(value), url = new URL(result);
  if (url.search || url.port || !(new Set(['api.tokens.xyz', 'xstocks-metadata.backed.fi', 'cdn.ondo.finance']).has(url.hostname) ||
      url.hostname === 'storage.googleapis.com' && /^\/tokens-asset-logos-prd\/solana\/[1-9A-HJ-NP-Za-km-z]{32,44}\.webp$/u.test(url.pathname))) invalid();
  return result;
}
function session(value: unknown): StockSessionSnapshot | null {
  if (value === null) return null;
  const data = record(value, ['priceUsd', 'changePercent24h', 'asOfUnixSeconds']);
  return Object.freeze({priceUsd: metric(data['priceUsd']), changePercent24h: change(data['changePercent24h']),
    asOfUnixSeconds: optionalUnix(data['asOfUnixSeconds'])});
}
function cardVariant(value: unknown): StockCardVariant | null {
  if (value === null) return null;
  const data = record(value, ['mint', 'symbol', 'logoUrl', 'priceUsd', 'changePercent24h']);
  return Object.freeze({mint: mint(data['mint']), symbol: optionalText(data['symbol'], 40), logoUrl: imageUrl(data['logoUrl']),
    priceUsd: metric(data['priceUsd']), changePercent24h: change(data['changePercent24h'])});
}
export function parseStockCard(value: unknown): StockCard {
  const data = record(value, ['assetId', 'name', 'symbol', 'imageUrl', 'stock', 'primaryVariant']);
  return Object.freeze({assetId: assetId(data['assetId']), name: optionalText(data['name'], 200),
    symbol: optionalText(data['symbol'], 40), imageUrl: imageUrl(data['imageUrl']), stock: session(data['stock']),
    primaryVariant: cardVariant(data['primaryVariant'])});
}
function provenance(data: Record<string, unknown>): FactsProvenance {
  schema(data['schemaVersion']);
  if (data['provider'] !== 'tokens-xyz-v1' || data['displayOnly'] !== true ||
      data['executionEnabled'] !== false || data['eligibility'] !== 'unverified') invalid();
  const requestedAt = timestamp(data['requestedAt']), observedAt = timestamp(data['observedAt']), refreshAfter = timestamp(data['refreshAfter']);
  if (Date.parse(observedAt) < Date.parse(requestedAt) || Date.parse(refreshAfter) <= Date.parse(observedAt) ||
      Date.parse(refreshAfter) - Date.parse(requestedAt) > 60_000) invalid();
  return Object.freeze({schemaVersion: 1, provider: 'tokens-xyz-v1', requestedAt, observedAt, refreshAfter,
    displayOnly: true, executionEnabled: false, eligibility: 'unverified'});
}
export function parseStockCatalogPage(value: unknown): StockCatalogPage {
  const data = record(value, ['discovery', 'cards', 'offset', 'total', 'nextOffset']);
  const discovery = parseStockSearchPage(data['discovery']);
  const cards = list(data['cards'], 20, parseStockCard);
  const offset = integer(data['offset'], 0, 10000), total = integer(data['total'], 0, 10000);
  const nextOffset = data['nextOffset'] === null ? null : integer(data['nextOffset'], 20, 10000);
  if (offset % 20 !== 0 || discovery.query !== 'catalog' || discovery.limit !== 20 || cards.length !== discovery.results.length ||
      nextOffset !== null && (nextOffset !== offset + 20 || nextOffset >= total)) invalid();
  for (let i = 0; i < cards.length; i++) {
    const card = cards[i]!, row = discovery.results[i]!;
    if (card.assetId !== row.assetId || card.primaryVariant !== null &&
        (card.primaryVariant.mint !== row.providerPrimaryVariantMint || !row.variants.some(variant => variant.mint === card.primaryVariant!.mint))) invalid();
  }
  return Object.freeze({discovery, cards, offset, total, nextOffset});
}
export function parseStockCardsPage(value: unknown): StockCardsPage {
  const data = record(value, [...factsKeys, 'sourceUrl', 'query', 'limit', 'completeCatalog', 'results']);
  const common = provenance(data), limit = integer(data['limit'], 1, 20);
  if (data['completeCatalog'] !== false) invalid();
  const results = list(data['results'], limit, parseStockCard); unique(results.map(row => row.assetId));
  return Object.freeze({...common, sourceUrl: sourceUrl(data['sourceUrl']), query: text(data['query'], 80), limit,
    completeCatalog: false, results});
}
function points(value: unknown, max: number): readonly StockSparklinePoint[] {
  const rows = list(value, max, value => {
    const data = record(value, ['unixSeconds', 'close']), close = metric(data['close']);
    if (close === null) invalid();
    return Object.freeze({unixSeconds: unix(data['unixSeconds']), close});
  });
  for (let i = 1; i < rows.length; i++) if (rows[i]!.unixSeconds <= rows[i - 1]!.unixSeconds) invalid();
  return rows;
}
function chartStatus(value: unknown, count: number): ChartStatus {
  if (!['observed', 'empty', 'unavailable'].includes(String(value)) || (value === 'observed') !== (count > 0)) invalid();
  return value as ChartStatus;
}
export function parseStockFacts(value: unknown): StockFacts {
  const data = record(value, [...factsKeys, 'sourceUrls', 'assetId', 'name', 'symbol', 'imageUrl', 'description',
    'stock', 'sparkline', 'sparklineStatus']);
  const common = provenance(data), sources = list(data['sourceUrls'], 2, sourceUrl);
  if (!sources.length) invalid();
  let sparkline: StockSparkline | null = null;
  if (data['sparkline'] !== null) {
    const line = record(data['sparkline'], ['interval', 'fromUnixSeconds', 'toUnixSeconds', 'points']);
    const from = unix(line['fromUnixSeconds']), to = unix(line['toUnixSeconds']), rows = points(line['points'], 64);
    if (line['interval'] !== '4H' || to - from !== 7 * 86400 ||
        rows.some(row => row.unixSeconds < from - 14400 || row.unixSeconds > to + 14400)) invalid();
    sparkline = Object.freeze({interval: '4H', fromUnixSeconds: from, toUnixSeconds: to, points: rows});
  }
  const status = chartStatus(data['sparklineStatus'], sparkline?.points.length ?? 0);
  if (status !== 'observed' && sparkline !== null) invalid();
  return Object.freeze({...common, sourceUrls: sources, assetId: assetId(data['assetId']), name: optionalText(data['name'], 200),
    symbol: optionalText(data['symbol'], 40), imageUrl: imageUrl(data['imageUrl']), description: optionalText(data['description'], 401),
    stock: session(data['stock']), sparkline, sparklineStatus: status});
}
function insightIdentity(value: unknown): StockInsightInput {
  const data = record(value, ['assetId', 'mint', 'period']);
  if (!['day', 'week', 'month', 'year'].includes(String(data['period']))) invalid();
  return Object.freeze({assetId: assetId(data['assetId']), mint: mint(data['mint']), period: data['period'] as StockInsightPeriod});
}
export function parseStockInsight(value: unknown): StockInsight {
  const data = record(value, [...factsKeys, 'assetId', 'mint', 'period', 'symbol', 'description', 'priceUsd', 'changePercent24h',
    'asOfUnixSeconds', 'volume24hUsd', 'liquidityUsd', 'tokenMarketCapUsd', 'stockMarketCapUsd', 'holders', 'points', 'chartStatus']);
  const common = provenance(data), identity = insightIdentity({assetId: data['assetId'], mint: data['mint'], period: data['period']});
  const rows = points(data['points'], 400), status = chartStatus(data['chartStatus'], rows.length);
  const days = {day: 1, week: 7, month: 30, year: 365}[identity.period];
  const interval = {day: 3600, week: 3600, month: 14400, year: 86400}[identity.period];
  const observed = Date.parse(common.observedAt) / 1000;
  if (rows.some(row => row.unixSeconds > observed || row.unixSeconds < Date.parse(common.requestedAt) / 1000 - days * 86400 - interval)) invalid();
  return Object.freeze({...common, ...identity, symbol: optionalText(data['symbol'], 40), description: optionalText(data['description'], 401),
    priceUsd: metric(data['priceUsd']), changePercent24h: change(data['changePercent24h']), asOfUnixSeconds: optionalUnix(data['asOfUnixSeconds']),
    volume24hUsd: metric(data['volume24hUsd']), liquidityUsd: metric(data['liquidityUsd']), tokenMarketCapUsd: metric(data['tokenMarketCapUsd']),
    stockMarketCapUsd: metric(data['stockMarketCapUsd']), holders: data['holders'] === null ? null : integer(data['holders'], 0, Number.MAX_SAFE_INTEGER),
    points: rows, chartStatus: status});
}

function input<T>(read: () => T): T {
  try { return read(); } catch { throw new StockResearchError('STOCK_INPUT_INVALID'); }
}
function baseUrl(value: unknown): string {
  if (value === '/api') return value;
  if (typeof value !== 'string' || value.length > 2048) throw new StockResearchError('STOCK_INVALID_CONFIGURATION');
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || !url.hostname || url.hostname.endsWith('.') || url.username || url.password ||
        url.search || url.hash || url.pathname !== '/' || value !== url.origin) throw new Error();
    return value;
  } catch { throw new StockResearchError('STOCK_INVALID_CONFIGURATION'); }
}

/** Public, bounded GET reads. No provider secrets, account tokens, writes or automatic retries. */
export class ProductMarketClient {
  readonly #base: string; readonly #fetch: typeof globalThis.fetch; readonly #timeout: number;
  readonly #active = new Set<() => void>(); #closed = false;
  constructor(options: ProductMarketOptions) {
    this.#base = baseUrl(options.baseUrl); this.#fetch = options.fetch ?? globalThis.fetch; this.#timeout = options.timeoutMs ?? 12000;
    if (typeof this.#fetch !== 'function' || !Number.isInteger(this.#timeout) || this.#timeout < 1 || this.#timeout > 30000)
      throw new StockResearchError('STOCK_INVALID_CONFIGURATION');
  }
  async catalog(offset = 0, options: MarketReadOptions = {}): Promise<StockCatalogPage> {
    input(() => { integer(offset, 0, 10000); if (offset % 20) invalid(); });
    const result = parseStockCatalogPage(await this.#get('catalog', {offset: String(offset)}, options.signal));
    if (result.offset !== offset) invalid(); return result;
  }
  async search(query: string, options: MarketSearchOptions = {}): Promise<StockSearchPage> {
    const limit = options.limit ?? 20; input(() => {text(query, 80); integer(limit, 1, 20);});
    const result = parseStockSearchPage(await this.#get('search', {query, limit: String(limit)}, options.signal));
    if (result.query !== query || result.limit !== limit) invalid(); return result;
  }
  async cards(query: string, options: MarketSearchOptions = {}): Promise<StockCardsPage> {
    const limit = options.limit ?? 20; input(() => {text(query, 80); integer(limit, 1, 20);});
    const result = parseStockCardsPage(await this.#get('cards', {query, limit: String(limit)}, options.signal));
    if (result.query !== query || result.limit !== limit) invalid(); return result;
  }
  async variants(id: string, options: MarketReadOptions = {}): Promise<StockVariantsPage> {
    input(() => assetId(id));
    const result = parseStockVariantsPage(await this.#get('variants', {assetId: id}, options.signal));
    if (result.assetId !== id) invalid(); return result;
  }
  async facts(id: string, options: MarketReadOptions = {}): Promise<StockFacts> {
    input(() => assetId(id));
    const result = parseStockFacts(await this.#get('facts', {assetId: id}, options.signal));
    if (result.assetId !== id) invalid(); return result;
  }
  async insight(request: StockInsightInput, options: MarketReadOptions = {}): Promise<StockInsight> {
    const identity = input(() => insightIdentity(request));
    const result = parseStockInsight(await this.#get('insight', {...identity}, options.signal));
    if (result.assetId !== identity.assetId || result.mint !== identity.mint || result.period !== identity.period) invalid();
    return result;
  }
  close(): void { this.#closed = true; for (const cancel of [...this.#active]) cancel(); }
  async #get(endpoint: string, query: Record<string, string>, signal: AbortSignal | undefined): Promise<unknown> {
    if (this.#closed || signal?.aborted) throw new StockResearchError('STOCK_CANCELLED');
    const url = `${this.#base}/v1/markets/stocks/${endpoint}?${new URLSearchParams(query)}`;
    const expectedUrl = this.#base === '/api'
      ? typeof globalThis.location === 'undefined' ? null : new URL(url, globalThis.location.href).href : url;
    const controller = new AbortController(); let failure: StockResearchError | undefined;
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let responseBody: ReadableStream<Uint8Array> | null = null;
    let rejectStopped!: (error: StockResearchError) => void;
    const stopped = new Promise<never>((_, reject) => {rejectStopped = reject;});
    const stop = (code: string): void => {
      if (failure) return; failure = new StockResearchError(code); controller.abort();
      void reader?.cancel().catch(() => {}); rejectStopped(failure);
    };
    const cancel = (): void => stop('STOCK_CANCELLED');
    this.#active.add(cancel); signal?.addEventListener('abort', cancel, {once: true});
    const timer = setTimeout(() => stop('STOCK_TIMEOUT'), this.#timeout);
    const perform = async (): Promise<unknown> => {
      try {
        const response = await this.#fetch(url, {method: 'GET', headers: {accept: 'application/json'}, credentials: 'omit',
          cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer', signal: controller.signal});
        responseBody = response.body;
        if (failure) throw failure;
        if (response.redirected || response.status >= 300 && response.status < 400 ||
            response.url && response.url !== expectedUrl) throw new StockResearchError('STOCK_REDIRECT_REJECTED');
        const maxBytes = 1_048_576, declared = response.headers.get('content-length');
        if (declared !== null && (!/^(0|[1-9][0-9]*)$/u.test(declared) || Number(declared) > maxBytes))
          throw new StockResearchError('STOCK_RESPONSE_TOO_LARGE');
        const type = response.headers.get('content-type')?.toLowerCase().split(';').map(part => part.trim());
        if (!type || type[0] !== 'application/json' || type.slice(1).some(part => !['charset=utf-8', 'charset="utf-8"'].includes(part)) || !response.body) invalid();
        reader = response.body.getReader(); const chunks: Uint8Array[] = []; let count = 0;
        while (true) {
          const next = await reader.read(); if (failure) throw failure;
          if (next.done) break; count += next.value.byteLength;
          if (count > maxBytes) throw new StockResearchError('STOCK_RESPONSE_TOO_LARGE'); chunks.push(next.value);
        }
        reader.releaseLock(); reader = undefined;
        const bytes = new Uint8Array(count); let offset = 0;
        for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.byteLength;}
        let value: unknown; try { value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)); } catch { invalid(); }
        if (response.status !== 200) serverFailure(response.status, value, ['cards', 'facts', 'insight'].includes(endpoint));
        return value;
      } catch (error) {
        controller.abort();
        if (reader) void reader.cancel().catch(() => {}); else void responseBody?.cancel().catch(() => {});
        if (failure) throw failure; if (error instanceof StockResearchError) throw error;
        throw new StockResearchError('STOCK_NETWORK_ERROR');
      }
    };
    try { return await Promise.race([perform(), stopped]); }
    finally {clearTimeout(timer); signal?.removeEventListener('abort', cancel); this.#active.delete(cancel);}
  }
}
function serverFailure(status: number, value: unknown, facts: boolean): never {
  const prefix = facts ? 'STOCK_FACTS_' : 'STOCK_';
  const byStatus: Record<number, readonly string[]> = {
    400: ['INPUT_INVALID'], 429: ['RATE_LIMITED'], 502: ['PROVIDER_UNAVAILABLE', 'RESPONSE_INVALID'],
    503: [facts ? 'UNAVAILABLE' : 'DISCOVERY_UNAVAILABLE', 'PROVIDER_AUTH_FAILED'], 504: ['TIMEOUT'],
  };
  let code: string | null = null;
  try {
    const envelope = record(value, ['error']), error = record(envelope['error'], ['code', 'message', 'requestId']);
    code = text(error['code'], 100); text(error['message'], 1024); text(error['requestId'], 128);
  } catch { /* Unknown response details are never rendered. */ }
  if (code !== null && byStatus[status]?.some(suffix => code === prefix + suffix)) throw new StockResearchError(code);
  throw new StockResearchError('STOCK_SERVICE_UNAVAILABLE');
}
