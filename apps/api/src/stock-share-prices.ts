import type { StockCatalogPage } from './stock-discovery.js';
import type { StockCard } from './stock-facts.js';
import { STOCK_MINT_PATTERN } from './stock-trading-catalog.js';

/**
 * Listed share prices for Market cards the curated source leaves with no price at
 * all, from Jupiter's price data: its `stockData` is the issuer's reference for the
 * underlying stock or fund, not the token. On 28 Sept 2026 this covered Ondo fund
 * tokens that nobody had traded yet, so no token price existed anywhere.
 *
 * Display only. It fills `stock` (the underlying listed share) and never a token
 * price, never prices an order, and never replaces a price the source gave.
 */
export interface SharePrice { readonly priceUsd: number; readonly asOfUnixSeconds: number }
export type SharePriceReader = (mints: readonly string[]) => Promise<ReadonlyMap<string, SharePrice>>;

const PRICE_URL = 'https://api.jup.ag/price/v3';
const MAX_IDS = 50;
const MAX_BODY_CHARS = 1_000_000;
/** Funds do not trade at weekends or on holidays; older references are not shown. */
const MAX_AGE_MS = 4 * 86_400_000;

export function jupiterSharePrices(options: {
  readonly fetch?: typeof globalThis.fetch; readonly apiKey?: string; readonly now?: () => number; readonly timeoutMs?: number;
} = {}): SharePriceReader {
  const request = options.fetch ?? globalThis.fetch, now = options.now ?? Date.now, timeoutMs = options.timeoutMs ?? 6_000;
  const headers = {accept: 'application/json', ...(options.apiKey ? {'x-api-key': options.apiKey} : {})};
  return async mints => {
    const ids = [...new Set(mints)].filter(mint => STOCK_MINT_PATTERN.test(mint));
    const prices = new Map<string, SharePrice>();
    for (let index = 0; index < ids.length; index += MAX_IDS) {
      const part = ids.slice(index, index + MAX_IDS);
      const abort = new AbortController();
      const timer = setTimeout(() => abort.abort(), timeoutMs);
      try {
        const response = await request(`${PRICE_URL}?ids=${part.join(',')}`, {method: 'GET', headers, signal: abort.signal, redirect: 'error'});
        if (!response.ok) continue;
        const text = await response.text();
        if (text.length > MAX_BODY_CHARS) continue;
        const body: unknown = JSON.parse(text);
        if (body === null || typeof body !== 'object' || Array.isArray(body)) continue;
        for (const mint of part) {
          const price = sharePrice((body as Record<string, unknown>)[mint], now());
          if (price) prices.set(mint, price);
        }
      } catch { /* A missing reference leaves the card as it was. */ }
      finally { clearTimeout(timer); }
    }
    return prices;
  };
}

function sharePrice(row: unknown, at: number): SharePrice | null {
  if (row === null || typeof row !== 'object' || Array.isArray(row)) return null;
  const stock = (row as Record<string, unknown>)['stockData'];
  if (stock === null || typeof stock !== 'object' || Array.isArray(stock)) return null;
  const price = (stock as Record<string, unknown>)['price'], updated = (stock as Record<string, unknown>)['updatedAt'];
  if (typeof price !== 'number' || !Number.isFinite(price) || price <= 0 || price > 10_000_000 || typeof updated !== 'string') return null;
  const time = Date.parse(updated);
  if (!Number.isFinite(time) || time > at + 5 * 60_000 || at - time > MAX_AGE_MS) return null;
  return Object.freeze({priceUsd: price, asOfUnixSeconds: Math.floor(time / 1000)});
}

const unpriced = (card: StockCard) => (card.stock?.priceUsd ?? null) === null && (card.primaryVariant?.priceUsd ?? null) === null;

/** Every listed token mint of the page's cards that have no price at all. */
export function unpricedMints(page: StockCatalogPage): string[] {
  const missing = new Set(page.cards.filter(unpriced).map(card => card.assetId));
  return page.discovery.results.filter(row => missing.has(row.assetId)).flatMap(row => row.variants.map(variant => variant.mint));
}

/** The page with each unpriced card given its most liquid token's share price, when one is known. */
export function withSharePrices(page: StockCatalogPage, prices: ReadonlyMap<string, SharePrice>): StockCatalogPage {
  if (!prices.size) return page;
  let changed = false;
  const cards = page.cards.map(card => {
    if (!unpriced(card)) return card;
    // Tokens of one company share one underlying stock; the first with a reference is used.
    const row = page.discovery.results.find(item => item.assetId === card.assetId);
    const price = row?.variants.map(variant => prices.get(variant.mint)).find(value => value !== undefined);
    if (!price) return card;
    changed = true;
    return Object.freeze({...card, stock: Object.freeze({priceUsd: price.priceUsd, changePercent24h: null, asOfUnixSeconds: price.asOfUnixSeconds})});
  });
  return changed ? Object.freeze({...page, cards: Object.freeze(cards)}) : page;
}
