/** Why a Market variant cannot be traded, so the app can say so plainly instead
 * of implying every listed token is buyable. Tradeable assets come only from the
 * registry (stock-trading-catalog.ts); this module never enables trading. */
import {STOCK_ISSUERS, isStockIssuerId, stockIssuerOffered} from './stock-issuers.js';
import type {StockIssuerId} from './stock-issuers.js';
import {STOCK_TRADING_ASSETS, STOCK_TRADING_IDENTITIES} from './stock-trading-catalog.js';
import {STOCK_MARKET_ATTRIBUTION} from './stock-market-attribution.generated.js';
import type {StockMarketStateOf} from './stock-market-state.js';

export const STOCK_UNAVAILABLE_REASONS = Object.freeze(['issuer_not_offered', 'identity_unverified', 'token_restricted',
  'low_liquidity', 'no_reviewed_route', 'price_off_market', 'held_back', 'not_reviewed',
  // Market makers quote many tokens only while US markets are open.
  'market_closed', 'no_market_maker_quote',
  // Refused only because its market was closed, and open now: checked at the next admission run.
  'awaiting_review'] as const);
export type StockUnavailableReason = (typeof STOCK_UNAVAILABLE_REASONS)[number];
export interface StockUnavailableVariant {
  readonly mint: string;
  readonly issuerId: StockIssuerId | null;
  readonly reason: StockUnavailableReason;
  /** The token symbol when admission recorded it (Ondo's live status is keyed by symbol). */
  readonly symbol: string | null;
}

const BASE58 = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
const isReason = (value: unknown): value is StockUnavailableReason =>
  typeof value === 'string' && (STOCK_UNAVAILABLE_REASONS as readonly string[]).includes(value);

function load(): readonly StockUnavailableVariant[] {
  const tradeable = new Set(STOCK_TRADING_ASSETS.map(asset => asset.mint));
  const out = new Map<string, StockUnavailableVariant>();
  // Admitted identities that are not tradeable now: the issuer policy wins over the entry status.
  for (const asset of STOCK_TRADING_IDENTITIES) {
    if (tradeable.has(asset.mint)) continue;
    out.set(asset.mint, Object.freeze({mint: asset.mint, issuerId: asset.issuerId,
      reason: stockIssuerOffered(asset.issuerId) ? 'held_back' as const : 'issuer_not_offered' as const, symbol: asset.symbol}));
  }
  for (const row of STOCK_MARKET_ATTRIBUTION) {
    const entry = row as typeof row & {readonly symbol?: unknown};
    if (!BASE58.test(entry.mint) || (entry.issuerId !== null && !isStockIssuerId(entry.issuerId)) || !isReason(entry.reason) ||
        (entry.symbol !== undefined && (typeof entry.symbol !== 'string' || !/^[A-Za-z0-9.-]{1,32}$/.test(entry.symbol)))) {
      throw new Error(`Invalid market attribution entry: ${String(entry.mint)}`);
    }
    if (tradeable.has(entry.mint) || out.has(entry.mint)) continue;
    const issuerId = entry.issuerId as StockIssuerId | null;
    // Issuer policy is read now, so a changed offer never shows a stale reason.
    const reason: StockUnavailableReason = issuerId !== null && !stockIssuerOffered(issuerId) ? 'issuer_not_offered'
      : entry.reason === 'issuer_not_offered' ? 'not_reviewed' : entry.reason;
    out.set(entry.mint, Object.freeze({mint: entry.mint, issuerId, reason, symbol: typeof entry.symbol === 'string' ? entry.symbol : null}));
  }
  return Object.freeze([...out.values()]);
}

export const STOCK_UNAVAILABLE_VARIANTS: readonly StockUnavailableVariant[] = load();

/**
 * The unavailable list as of now. An Ondo token refused only because its market
 * was closed carries its market state, so the app can say when it opens; while
 * its market is open it reads as awaiting review until the next admission run.
 */
export function unavailableVariantsNow(stateOf: StockMarketStateOf) {
  return STOCK_UNAVAILABLE_VARIANTS.map(variant => {
    if (variant.issuerId !== 'ondo' || variant.symbol === null ||
        (variant.reason !== 'market_closed' && variant.reason !== 'no_market_maker_quote')) return variant;
    const market = stateOf('ondo', variant.symbol, variant.mint);
    return {...variant, reason: market.status === 'open' ? 'awaiting_review' as const : 'market_closed' as const, market};
  });
}

/** Every issuer's disclosure with whether Trimmy offers its tokens. */
export function stockIssuerCapabilities() {
  return Object.values(STOCK_ISSUERS).map(issuer => ({...issuer.disclosure, offered: issuer.offer.status === 'offered',
    notOfferedReason: issuer.offer.status === 'offered' ? null : issuer.offer.reason,
    // 'rfq': fills come from market makers; the transaction id is the maker's signature.
    route: issuer.identity.route}));
}
