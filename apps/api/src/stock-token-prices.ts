import { STOCK_MINT_PATTERN } from './stock-trading-catalog.js';

/**
 * Stock token prices from Jupiter's price data, and which of them to trust.
 *
 * `stockData.price` is the issuer's own price for the underlying share or fund
 * (xStocks, Ondo, Backpack, PreStocks), per displayed share. `usdPrice` is the
 * token's last traded price: sound when the token has real liquidity, and
 * meaningless when it has almost none. On 28 Sept 2026 PYPLx traded at $248,954
 * per share on $0.05 of liquidity while the share was $54.
 */
export interface TokenPrice {
  /** The issuer's price per displayed share, when under four days old. */
  readonly referenceUsd: number | null;
  readonly referenceAt: number | null;
  /** The token's last traded price per displayed share. */
  readonly marketUsd: number | null;
  readonly liquidityUsd: number;
  /**
   * Displayed shares per whole token in raw units now (the Token-2022 scaled UI
   * amount; 1 without one). Null when Jupiter's figure is unusable.
   */
  readonly multiplier: number | null;
}

/** Below this much liquidity a token's traded price is not used. */
export const LIQUID_MARKET_USD = 10_000;
/**
 * With this much liquidity the traded price is what a holder could sell for,
 * and it values holdings ahead of the issuer's price. Pre-IPO issuers' prices are
 * marks: on 28 Sept 2026 Tessera's tOpenAI mark was 18% below its $820k market.
 */
export const DEEP_MARKET_USD = 100_000;
/** Markets close at weekends and on holidays; older issuer prices are not used. */
const MAX_REFERENCE_AGE_MS = 4 * 86_400_000;
const MAX_IDS = 50;
const MAX_CACHED_MS = 5 * 60_000;
const MAX_BODY_CHARS = 1_000_000;

const record = (value: unknown): Record<string, unknown> | null =>
  value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null;
const positive = (value: unknown, max = 1e9): number | null =>
  typeof value === 'number' && Number.isFinite(value) && value > 0 && value <= max ? value : null;

export function parseTokenPrice(value: unknown, now: number): TokenPrice | null {
  const row = record(value);
  if (!row) return null;
  const stock = record(row['stockData']);
  let referenceUsd = positive(stock?.['price']);
  let referenceAt: number | null = typeof stock?.['updatedAt'] === 'string' ? Date.parse(stock['updatedAt']) : NaN;
  if (referenceUsd === null || !Number.isFinite(referenceAt) || referenceAt > now + 5 * 60_000 || now - referenceAt > MAX_REFERENCE_AGE_MS) {
    referenceUsd = null;
    referenceAt = null;
  }
  const scaled = row['scaledUiConfig'];
  let multiplier: number | null = 1;
  if (scaled !== undefined && scaled !== null) {
    const config = record(scaled);
    const effectiveAt = typeof config?.['newMultiplierEffectiveAt'] === 'string' ? Date.parse(config['newMultiplierEffectiveAt']) : NaN;
    const current = Number.isFinite(effectiveAt) && effectiveAt <= now ? config?.['newMultiplier'] : config?.['multiplier'];
    multiplier = positive(current, 1e6);
    if (multiplier !== null && multiplier < 1e-6) multiplier = null;
  }
  const marketUsd = positive(row['usdPrice']);
  if (referenceUsd === null && marketUsd === null) return null;
  return Object.freeze({referenceUsd, referenceAt, marketUsd, liquidityUsd: positive(row['liquidity'], 1e15) ?? 0, multiplier});
}

export interface HoldingPrice {
  /** Price per displayed share, so it multiplies the wallet's display amount. */
  readonly usdPerShare: number;
  readonly source: 'issuer' | 'market';
  readonly asOf: number | null;
}

/**
 * What one displayed share is worth: a deep market's price, else the issuer's,
 * else a liquid market's; otherwise unknown.
 */
export function holdingPrice(price: TokenPrice | null | undefined): HoldingPrice | null {
  if (!price) return null;
  if (price.marketUsd !== null && price.liquidityUsd >= DEEP_MARKET_USD) {
    return Object.freeze({usdPerShare: price.marketUsd, source: 'market', asOf: null});
  }
  if (price.referenceUsd !== null) return Object.freeze({usdPerShare: price.referenceUsd, source: 'issuer', asOf: price.referenceAt});
  if (price.marketUsd !== null && price.liquidityUsd >= LIQUID_MARKET_USD) {
    return Object.freeze({usdPerShare: price.marketUsd, source: 'market', asOf: null});
  }
  return null;
}

/** Select one reference using the holdings valuation policy: deep market,
 * issuer, then liquid market. Never choose whichever lets the quote pass.
 * The multiplier must come from the reviewed on-chain mint, not this feed. */
export function orderReferencePrices(price: TokenPrice | null | undefined, onChainMultiplier: number): number[] {
  if (!Number.isFinite(onChainMultiplier) || onChainMultiplier<=0) return [];
  const selected=holdingPrice(price);
  if (!selected) return [];
  const reference=selected.usdPerShare*onChainMultiplier;
  return Number.isFinite(reference) && reference>0 ? [reference] : [];
}

/** Cached reads of Jupiter's price data for stock token mints. `read` never throws. */
export class JupiterTokenPrices {
  readonly #fetch: typeof globalThis.fetch;
  readonly #url: string;
  readonly #headers: Record<string, string>;
  readonly #now: () => number;
  readonly #ttlMs: number;
  readonly #timeoutMs: number;
  readonly #cache = new Map<string, {readonly at: number; readonly price: TokenPrice | null}>();

  constructor(options: {fetch?: typeof globalThis.fetch; apiKey?: string; now?: () => number; ttlMs?: number; timeoutMs?: number} = {}) {
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#url = options.apiKey ? 'https://api.jup.ag/price/v3' : 'https://lite-api.jup.ag/price/v3';
    this.#headers = {accept: 'application/json', ...(options.apiKey ? {'x-api-key': options.apiKey} : {})};
    this.#now = options.now ?? Date.now;
    this.#ttlMs = options.ttlMs ?? 30_000;
    this.#timeoutMs = options.timeoutMs ?? 6_000;
  }

  async read(mints: readonly string[]): Promise<ReadonlyMap<string, TokenPrice>> {
    return this.#read(mints, MAX_CACHED_MS);
  }

  /** Orders cannot use the stale-on-error grace period intended for holdings. */
  async readForOrder(mints: readonly string[]): Promise<ReadonlyMap<string, TokenPrice>> {
    return this.#read(mints, Math.min(this.#ttlMs, 30_000));
  }

  async #read(mints: readonly string[], maxAgeMs: number): Promise<ReadonlyMap<string, TokenPrice>> {
    const ids = [...new Set(mints)].filter(mint => STOCK_MINT_PATTERN.test(mint));
    const now = this.#now();
    const stale = ids.filter(mint => {
      const cached = this.#cache.get(mint);
      return !cached || now - cached.at >= Math.min(this.#ttlMs,maxAgeMs);
    });
    const parts: string[][] = [];
    for (let index = 0; index < stale.length; index += MAX_IDS) parts.push(stale.slice(index, index + MAX_IDS));
    await Promise.all(parts.map(part => this.#load(part)));
    const prices = new Map<string, TokenPrice>();
    for (const mint of ids) {
      const cached = this.#cache.get(mint);
      // After a failed refresh the last read serves for a few minutes, never longer.
      if (cached?.price && this.#now() - cached.at >= 0 && this.#now() - cached.at < maxAgeMs) prices.set(mint, cached.price);
    }
    return prices;
  }

  async #load(mints: readonly string[]): Promise<void> {
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), this.#timeoutMs);
    try {
      const response = await this.#fetch(`${this.#url}?ids=${mints.join(',')}`, {method: 'GET', headers: this.#headers,
        signal: abort.signal, redirect: 'error'});
      if (!response.ok) return;
      const text = await response.text();
      if (text.length > MAX_BODY_CHARS) return;
      const body = record(JSON.parse(text));
      if (!body) return;
      const at = this.#now();
      if (this.#cache.size > 5_000) this.#cache.clear();
      for (const mint of mints) this.#cache.set(mint, {at, price: parseTokenPrice(body[mint], at)});
    } catch {
      // A failed read leaves earlier prices in place; nothing new is trusted.
    } finally {
      clearTimeout(timer);
    }
  }
}
