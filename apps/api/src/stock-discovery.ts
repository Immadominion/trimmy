import { stockCard } from './stock-facts.js';
import type { StockCard } from './stock-facts.js';
import { BoundedProviderRead } from './bounded-provider-read.js';
import type { BoundedProviderReadConfiguration } from './bounded-provider-read.js';

/** Read-only Tokens.xyz discovery. Metadata is never an execution allowlist.
 * https://docs.tokens.xyz/v1/endpoints/assets
 * https://docs.tokens.xyz/v1/endpoints/asset-by-id
 */
export interface StockSearchInput { readonly query: string; readonly limit?: number }
export interface StockVariantsInput { readonly assetId: string }
export interface StockAdvisory {
  readonly status: 'caution' | 'compromised' | 'blocked' | 'unknown';
  readonly providerStatus: string;
  readonly reason: string;
  /** Documentation explicitly declares this field to be Unix milliseconds. */
  readonly since: string;
}
export interface StockAssetAdvisory extends StockAdvisory { readonly mint: string; readonly variantId: string }
export interface StockVariantMarket {
  readonly displayOnly: true;
  readonly priceUsd: number | null;
  readonly liquidityUsd: number | null;
  readonly volume24hUsd: number | null;
  readonly decimals: number | null;
  readonly source: string | null;
  readonly metricsSource: string | null;
  /** These variant-market timestamp units are not specified in the v1 schema.
   * Preserve raw values rather than silently treating seconds as milliseconds. */
  readonly providerTimestamps: {
    readonly asOf: number | null;
    readonly lastFetchedAt: number | null;
    readonly lastTradeAt: number | null;
    readonly unit: 'not_declared';
  };
}
export interface StockVariant {
  readonly variantId: string;
  readonly mint: string;
  readonly chain: 'solana';
  readonly kind: string;
  readonly issuer: string | null;
  readonly label: string | null;
  readonly name: string | null;
  readonly symbol: string | null;
  /** Provider description only, never interpreted as user redemption rights. */
  readonly providerRedemptionTier: string | null;
  readonly advisory: StockAdvisory | null;
  readonly market: StockVariantMarket | null;
}
export interface StockDiscoveryAsset {
  readonly assetId: string;
  readonly name: string | null;
  readonly symbol: string | null;
  readonly category: 'equity';
  readonly providerPrimaryVariantMint: string | null;
  readonly variants: readonly StockVariant[];
  /** Includes flagged siblings omitted by upstream search filtering. */
  readonly advisories: readonly StockAssetAdvisory[];
}
interface DiscoveryProvenance {
  readonly schemaVersion: 1;
  readonly provider: 'tokens-xyz-v1';
  readonly sourceUrl: string;
  readonly requestedAt: string;
  readonly observedAt: string;
  readonly providerAsOf: null;
  readonly providerFreshness: 'not_verified';
  readonly refreshAfter: string;
  readonly executionEnabled: false;
  readonly eligibility: 'unverified';
  readonly mintVerification: 'not_checked';
}
export interface StockDiscoveryPage extends DiscoveryProvenance {
  readonly query: string;
  readonly limit: number;
  /** Search is bounded, not an exhaustive issuer catalog. */
  readonly completeCatalog: false;
  readonly results: readonly StockDiscoveryAsset[];
}
export interface StockVariantsPage extends DiscoveryProvenance {
  readonly assetId: string;
  readonly variants: readonly StockVariant[];
}
export interface StockCatalogPage {
  readonly discovery: StockDiscoveryPage;
  readonly cards: readonly StockCard[];
  readonly offset: number;
  readonly total: number;
  readonly nextOffset: number | null;
}
export interface StockDiscovery {
  catalog?(offset?: number): Promise<StockCatalogPage>;
  search(input: StockSearchInput): Promise<StockDiscoveryPage>;
  variants(input: StockVariantsInput): Promise<StockVariantsPage>;
}
export type StockDiscoveryErrorCode = 'STOCK_INPUT_INVALID' | 'STOCK_DISCOVERY_UNAVAILABLE' |
  'STOCK_PROVIDER_AUTH_FAILED' | 'STOCK_PROVIDER_UNAVAILABLE' | 'STOCK_RATE_LIMITED' |
  'STOCK_RESPONSE_INVALID' | 'STOCK_TIMEOUT';
const messages: Record<StockDiscoveryErrorCode, string> = {
  STOCK_INPUT_INVALID: 'Enter a valid stock search or asset identifier.',
  STOCK_DISCOVERY_UNAVAILABLE: 'Stock discovery is not configured.',
  STOCK_PROVIDER_AUTH_FAILED: 'The stock data provider requires a valid key with read access.',
  STOCK_PROVIDER_UNAVAILABLE: 'Stock data is unavailable. Try again later.',
  STOCK_RATE_LIMITED: 'Wait before requesting stock data again.',
  STOCK_RESPONSE_INVALID: 'The stock provider returned unusable data.',
  STOCK_TIMEOUT: 'The stock data request took too long.',
};
export class StockDiscoveryError extends Error {
  constructor(readonly code: StockDiscoveryErrorCode) { super(messages[code]); this.name = 'StockDiscoveryError'; }
}
function invalid(): never { throw new StockDiscoveryError('STOCK_RESPONSE_INVALID'); }
function badInput(): never { throw new StockDiscoveryError('STOCK_INPUT_INVALID'); }
function record(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
}
function text(value: unknown, max = 160): string {
  if (typeof value !== 'string' || !value.length || value.length > max || value.trim() !== value || /[\u0000-\u001f\u007f]/u.test(value)) invalid();
  return value;
}
function optionalText(value: unknown, max = 160): string | null {
  return value === undefined || value === null ? null : text(value, max);
}
const isSlug = (value: unknown): value is string => typeof value === 'string' && value.length <= 100 &&
  /^[a-z0-9]+(?:-[a-z0-9]+)*$/u.exec(value)?.[0] === value;
function assetId(value: unknown): string { if (!isSlug(value)) invalid(); return value; }
function variantId(value: unknown): string {
  const id = text(value);
  if (/^[A-Za-z0-9][A-Za-z0-9._:-]*$/u.exec(id)?.[0] !== id) invalid();
  return id;
}
/** Encoding/length validation only; does not inspect mint ownership or extensions. */
function mint(value: unknown): string {
  if (typeof value !== 'string' || value.length < 32 || value.length > 44) invalid();
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  let decoded = 0n;
  for (const char of value) {
    const digit = alphabet.indexOf(char);
    if (digit < 0) invalid();
    decoded = decoded * 58n + BigInt(digit);
  }
  let bytes = 0;
  while (decoded > 0n) { bytes++; decoded >>= 8n; }
  const leadingZeroes = value.match(/^1*/u)?.[0].length ?? 0;
  if (bytes + leadingZeroes !== 32) invalid();
  return value;
}
function nullableNumber(value: unknown, optional = false): number | null {
  if (value === null || optional && value === undefined) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > Number.MAX_SAFE_INTEGER) invalid();
  return value;
}
function nullableTimestamp(value: unknown): number | null {
  const result = nullableNumber(value, true);
  if (result !== null && !Number.isSafeInteger(result)) invalid();
  return result;
}
function advisory(value: unknown): StockAdvisory | null {
  if (value === null) return null;
  const data = record(value);
  const status = text(data['status'], 60);
  const since = nullableNumber(data['since']);
  if (since === null || !Number.isSafeInteger(since) || since > 8_640_000_000_000_000) invalid();
  return Object.freeze({
    status: ['caution', 'compromised', 'blocked'].includes(status) ? status as StockAdvisory['status'] : 'unknown',
    providerStatus: status, reason: text(data['reason'], 1000), since: new Date(since).toISOString(),
  });
}
function market(value: unknown): StockVariantMarket | null {
  if (value === null) return null;
  const data = record(value);
  const decimals = nullableNumber(data['decimals']);
  if (decimals !== null && (!Number.isInteger(decimals) || decimals > 255)) invalid();
  return Object.freeze({
    displayOnly: true, priceUsd: nullableNumber(data['price']), liquidityUsd: nullableNumber(data['liquidity']),
    volume24hUsd: nullableNumber(data['volume24hUSD']), decimals,
    source: optionalText(data['source'], 80), metricsSource: optionalText(data['metricsSource'], 80),
    providerTimestamps: Object.freeze({asOf: nullableTimestamp(data['asOf']),
      lastFetchedAt: nullableTimestamp(data['lastFetchedAt']), lastTradeAt: nullableTimestamp(data['lastTradeAt']), unit: 'not_declared'}),
  });
}
function variant(value: unknown): StockVariant {
  const data = record(value);
  if (data['chain'] !== undefined && data['chain'] !== 'solana') invalid();
  return Object.freeze({variantId: variantId(data['variantId']), mint: mint(data['mint']), chain: 'solana',
    kind: text(data['kind'], 60), issuer: optionalText(data['issuer']), label: optionalText(data['label']),
    name: optionalText(data['name']), symbol: optionalText(data['symbol'], 40),
    providerRedemptionTier: optionalText(data['stockVariantTier'], 80),
    advisory: advisory(data['advisory']), market: market(data['market'])});
}
function variants(value: unknown): readonly StockVariant[] {
  if (!Array.isArray(value) || value.length > 64) invalid();
  const result = value.map(variant);
  if (new Set(result.map(row => row.mint)).size !== result.length ||
    new Set(result.map(row => row.variantId)).size !== result.length) invalid();
  return Object.freeze(result);
}
function asset(value: unknown): StockDiscoveryAsset {
  const data = record(value);
  if (data['category'] !== 'equity') invalid();
  const all = variants(data['variants']);
  const primary = data['primaryVariant'] === null ? null : variant(data['primaryVariant']);
  if (primary !== null && !all.some(row => JSON.stringify(row) === JSON.stringify(primary))) invalid();
  const flags = data['advisories'];
  if (!Array.isArray(flags) || flags.length > 64) invalid();
  const advisories = flags.map(value => {
    const flag = record(value);
    const parsed = advisory(flag);
    if (parsed === null) invalid();
    return Object.freeze({...parsed, mint: mint(flag['mint']), variantId: variantId(flag['variantId'])});
  });
  if (new Set(advisories.map(flag => flag.mint)).size !== advisories.length) invalid();
  for (const row of all) {
    const flag = advisories.find(value => value.mint === row.mint);
    if ((row.advisory !== null) !== (flag !== undefined) || flag &&
      (flag.variantId !== row.variantId || flag.providerStatus !== row.advisory?.providerStatus ||
        flag.reason !== row.advisory.reason || flag.since !== row.advisory.since)) invalid();
  }
  return Object.freeze({assetId: assetId(data['assetId']), name: optionalText(data['name']),
    symbol: optionalText(data['symbol'], 40), category: 'equity', providerPrimaryVariantMint: primary?.mint ?? null,
    variants: all, advisories: Object.freeze(advisories)});
}
function searchInput(value: StockSearchInput): {query: string; limit: number} {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
    Object.keys(value).some(key => !['query', 'limit'].includes(key))) badInput();
  const query = value.query;
  if (typeof query !== 'string' || query.trim() !== query || query.length < 1 || query.length > 80 || /[\u0000-\u001f\u007f]/u.test(query)) badInput();
  const limit = value.limit ?? 10;
  if (!Number.isInteger(limit) || limit < 1 || limit > 20) badInput();
  return {query, limit};
}

export interface TokensStockDiscoveryOptions {
  readonly apiKey: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
  /** Testable provider pacing. Production starts at most one request each second. */
  readonly paceMs?: number;
  readonly wait?: (durationMs: number) => Promise<void>;
  readonly protection?: Partial<Omit<BoundedProviderReadConfiguration, 'now'>>;
}
const origin = 'https://api.tokens.xyz';
const byteLimit = 1_048_576;
const freshnessMs = 60_000;
type StockDiscoveryResult = StockDiscoveryPage | StockVariantsPage | StockCatalogPage;
/** Explicit server key; never reads credentials itself or falls back to keyless. */
export class TokensStockDiscovery implements StockDiscovery {
  readonly #key: string;
  readonly #fetch: typeof globalThis.fetch;
  readonly #now: () => number;
  readonly #timeout: number;
  readonly #pace: number;
  readonly #wait: (durationMs: number) => Promise<void>;
  readonly #reads: BoundedProviderRead<StockDiscoveryResult>;
  #nextRequestAt = 0;
  #providerRetryAt = 0;
  #dispatchTail: Promise<void> = Promise.resolve();
  constructor(options: TokensStockDiscoveryOptions) {
    if (!options || typeof options.apiKey !== 'string' || options.apiKey.length < 8 || options.apiKey.length > 512 ||
      /^[\x21-\x7e]+$/u.exec(options.apiKey)?.[0] !== options.apiKey) throw new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE');
    this.#key = options.apiKey; this.#fetch = options.fetch ?? globalThis.fetch; this.#now = options.now ?? Date.now;
    this.#timeout = options.timeoutMs ?? 6000;
    this.#pace = options.paceMs ?? 1000;
    this.#wait = options.wait ?? (durationMs => new Promise(resolve => setTimeout(resolve, durationMs)));
    if (!Number.isInteger(this.#timeout) || this.#timeout < 1 || this.#timeout > 8000) throw new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE');
    if (!Number.isInteger(this.#pace) || this.#pace < 1 || this.#pace > 10_000 || typeof this.#wait !== 'function') {
      throw new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE');
    }
    this.#reads = new BoundedProviderRead<StockDiscoveryResult>({
      cacheTtlMs: 5_000,
      rateLimitWindowMs: 60_000,
      perKeyLimit: 12,
      globalLimit: 60,
      maxTrackedKeys: 128,
      maxCacheEntries: 128,
      maxConcurrentReads: 6,
      ...options.protection,
      now: this.#now,
    }, {
      configurationInvalid: () => new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE'),
      rateLimited: () => new StockDiscoveryError('STOCK_RATE_LIMITED'),
    });
  }
  async search(input: StockSearchInput): Promise<StockDiscoveryPage> {
    const request = searchInput(input);
    const url = new URL('/v1/assets/search', origin);
    url.search = new URLSearchParams({q: request.query, category: 'equity', variants: 'all',
      primaryVariantStrategy: 'liquidity', limit: String(request.limit)}).toString();
    const result = await this.#reads.read(`search:${request.limit}:${request.query}`, `search:${request.query}`, async () => {
      const received = await this.#schedule(() => this.#get(url));
      const data = record(received.payload);
      if (data['query'] !== request.query || data['category'] !== 'equity' || data['primaryVariantStrategy'] !== 'liquidity' ||
        !Array.isArray(data['results']) || data['results'].length > request.limit) invalid();
      const rows = data['results'].map(asset);
      if (new Set(rows.map(row => row.assetId)).size !== rows.length) invalid();
      const mints = rows.flatMap(row => row.variants.map(variant => variant.mint));
      if (new Set(mints).size !== mints.length) invalid();
      return Object.freeze({...received.provenance, ...request, completeCatalog: false,
        results: Object.freeze(rows)}) as StockDiscoveryPage;
    });
    return result as StockDiscoveryPage;
  }
  async catalog(offset = 0): Promise<StockCatalogPage> {
    if (!Number.isSafeInteger(offset) || offset < 0 || offset > 10000 || offset % 20 !== 0) badInput();
    const limit = 20;
    const url = new URL('/v1/assets/curated', origin);
    url.search = new URLSearchParams({list: 'stocks', groupBy: 'asset', variants: 'all',
      primaryVariantStrategy: 'liquidity', limit: String(limit), offset: String(offset)}).toString();
    return await this.#reads.read(`catalog:${offset}`, `catalog:${offset}`, async () => {
      const received = await this.#schedule(() => this.#get(url));
      const data = record(received.payload);
      const pagination = record(data['pagination']);
      const total = pagination['total'];
      const next = pagination['nextOffset'];
      if (data['listId'] !== 'stocks' || data['primaryVariantStrategy'] !== 'liquidity' ||
          !Array.isArray(data['assets']) || data['assets'].length > limit ||
          pagination['offset'] !== offset || pagination['limit'] !== limit ||
          typeof total !== 'number' || !Number.isSafeInteger(total) || total < 0 || total > 10000 ||
          typeof pagination['hasMore'] !== 'boolean' ||
          (pagination['hasMore'] ? next !== offset + limit || next >= total : next !== null)) invalid();
      // The provider's stocks list also contains ETFs/commodities. This
      // equity contract keeps them out without corrupting provider offsets.
      const equities = data['assets'].filter(row => record(row)['category'] === 'equity');
      const rows = equities.map(asset);
      if (new Set(rows.map(row => row.assetId)).size !== rows.length) invalid();
      return Object.freeze({
        discovery: Object.freeze({...received.provenance, query: 'catalog', limit, completeCatalog: false,
          results: Object.freeze(rows)}),
        cards: Object.freeze(equities.map(stockCard)), offset, total, nextOffset: next,
      }) as StockCatalogPage;
    }) as StockCatalogPage;
  }
  async variants(input: StockVariantsInput): Promise<StockVariantsPage> {
    if (!input || typeof input !== 'object' || Array.isArray(input) || Object.keys(input).some(key => key !== 'assetId') || !isSlug(input.assetId)) badInput();
    const requestedId = input.assetId;
    const url = new URL(`/v1/assets/${encodeURIComponent(requestedId)}/variants`, origin);
    url.search = new URLSearchParams({variantsMode: 'all', sortBy: 'liquidity'}).toString();
    const result = await this.#reads.read(`variants:${requestedId}`, `variants:${requestedId}`, async () => {
      const received = await this.#schedule(() => this.#get(url));
      const data = record(received.payload);
      if (data['assetId'] !== requestedId || data['sortBy'] !== 'liquidity') invalid();
      return Object.freeze({...received.provenance, assetId: requestedId,
        variants: variants(data['variants'])}) as StockVariantsPage;
    });
    return result as StockVariantsPage;
  }
  #timestamp(): number {
    let value: number;
    try { value = this.#now(); }
    catch { throw new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE'); }
    if (!Number.isSafeInteger(value) || value < 0 || value > 8_639_999_999_000_000) {
      throw new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE');
    }
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
      if (current < this.#providerRetryAt) throw new StockDiscoveryError('STOCK_RATE_LIMITED');
      for (let waits = 0; current < this.#nextRequestAt; waits++) {
        if (waits >= 3) throw new StockDiscoveryError('STOCK_PROVIDER_UNAVAILABLE');
        try { await this.#wait(this.#nextRequestAt - current); }
        catch { throw new StockDiscoveryError('STOCK_PROVIDER_UNAVAILABLE'); }
        current = this.#timestamp();
        if (current < this.#providerRetryAt) throw new StockDiscoveryError('STOCK_RATE_LIMITED');
      }
      this.#nextRequestAt = Math.max(current, this.#nextRequestAt) + this.#pace;
      pending = load();
    } catch (error) {
      release();
      if (error instanceof StockDiscoveryError) throw error;
      throw new StockDiscoveryError('STOCK_PROVIDER_UNAVAILABLE');
    }
    release();
    return pending;
  }
  async #get(url: URL): Promise<{payload: unknown; provenance: DiscoveryProvenance}> {
    const started = this.#timestamp();
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new StockDiscoveryError('STOCK_TIMEOUT')); }, this.#timeout);
    });
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
      const pendingResponse = this.#fetch(url, {method: 'GET', headers: {accept: 'application/json', 'x-api-key': this.#key},
        redirect: 'error', signal: controller.signal});
      // A custom transport may ignore AbortSignal. Dispose any late body without
      // allowing it to restart parsing or delay this request's deadline.
      void pendingResponse.then(response => {
        if (controller.signal.aborted) { try { void response.body?.cancel().catch(() => {}); } catch { /* disposal only */ } }
      }, () => {});
      const response = await Promise.race([pendingResponse, deadline]);
      if (response.redirected || response.url && new URL(response.url).origin !== origin) invalid();
      if (response.status === 401 || response.status === 403) throw new StockDiscoveryError('STOCK_PROVIDER_AUTH_FAILED');
      if (response.status === 429) {
        this.#providerRetryAt = Math.max(this.#providerRetryAt, this.#timestamp() + 60_000);
        throw new StockDiscoveryError('STOCK_RATE_LIMITED');
      }
      if (!response.ok) throw new StockDiscoveryError('STOCK_PROVIDER_UNAVAILABLE');
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
      if (controller.signal.aborted) throw new StockDiscoveryError('STOCK_TIMEOUT');
      const ended = this.#timestamp();
      if (!Number.isSafeInteger(ended) || ended < started || ended >= started + freshnessMs) throw new StockDiscoveryError('STOCK_TIMEOUT');
      return {payload, provenance: Object.freeze({schemaVersion: 1, provider: 'tokens-xyz-v1', sourceUrl: url.href,
        requestedAt: new Date(started).toISOString(), observedAt: new Date(ended).toISOString(), providerAsOf: null,
        providerFreshness: 'not_verified', refreshAfter: new Date(started + freshnessMs).toISOString(),
        executionEnabled: false, eligibility: 'unverified', mintVerification: 'not_checked'})};
    } catch (error) {
      if (controller.signal.aborted) throw new StockDiscoveryError('STOCK_TIMEOUT');
      if (error instanceof StockDiscoveryError) throw error;
      if (error instanceof SyntaxError || error instanceof TypeError && reader !== undefined) invalid();
      throw new StockDiscoveryError('STOCK_PROVIDER_UNAVAILABLE');
    } finally {
      clearTimeout(timer); controller.abort();
      if (reader) { try { void reader.cancel().catch(() => {}); } catch { /* disposal only */ } }
    }
  }
}
export function readStockDiscovery(env: Readonly<Record<string, string | undefined>>): TokensStockDiscovery | undefined {
  const mode = env['TRIMMY_STOCK_DISCOVERY'];
  if (mode === undefined || mode === '' || mode === 'disabled') return undefined;
  if (mode !== 'tokens_xyz' || !env['TOKENS_API_KEY']) throw new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE');
  return new TokensStockDiscovery({apiKey: env['TOKENS_API_KEY']});
}
