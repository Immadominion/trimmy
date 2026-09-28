/** Why a Market variant cannot be traded, so the app can say so plainly instead
 * of implying every listed token is buyable. Tokens are admitted automatically by
 * the token directory (stock-token-directory.ts); this module never enables trading. */
import {STOCK_ISSUERS, stockIssuerOffered} from './stock-issuers.js';
import type {StockIssuerId} from './stock-issuers.js';
import {stockTradingAssets, stockTradingIdentities} from './stock-trading-catalog.js';
import type {StockTokenRefused} from './stock-token-directory.js';

/** Reasons installed apps know; the directory uses the first three. */
export const STOCK_UNAVAILABLE_REASONS = Object.freeze(['identity_unverified', 'token_restricted', 'issuer_not_offered',
  'held_back', 'low_liquidity', 'no_reviewed_route', 'price_off_market', 'not_reviewed', 'market_closed', 'no_market_maker_quote',
  'awaiting_review'] as const);
export type StockUnavailableReason = (typeof STOCK_UNAVAILABLE_REASONS)[number];
export interface StockUnavailableVariant {
  readonly mint: string;
  readonly issuerId: StockIssuerId | null;
  readonly reason: StockUnavailableReason;
  readonly symbol: string | null;
}

/**
 * Tokens that cannot be traded now: known tokens whose issuer is not offered or
 * which were suspended, and tokens the directory checked and refused.
 */
export function unavailableVariantsNow(refusals: readonly StockTokenRefused[]): readonly StockUnavailableVariant[] {
  const tradeable = new Set(stockTradingAssets().map(asset => asset.mint));
  const out = new Map<string, StockUnavailableVariant>();
  for (const asset of stockTradingIdentities()) {
    if (tradeable.has(asset.mint)) continue;
    out.set(asset.mint, Object.freeze({mint: asset.mint, issuerId: asset.issuerId, symbol: asset.symbol,
      reason: stockIssuerOffered(asset.issuerId) ? 'held_back' as const : 'issuer_not_offered' as const}));
  }
  for (const refused of refusals) {
    if (tradeable.has(refused.mint) || out.has(refused.mint)) continue;
    out.set(refused.mint, Object.freeze({mint: refused.mint, issuerId: refused.issuerId, symbol: refused.symbol, reason: refused.reason}));
  }
  return Object.freeze([...out.values()]);
}

/** Every issuer's disclosure with whether Trimmy offers its tokens. */
export function stockIssuerCapabilities() {
  return Object.values(STOCK_ISSUERS).map(issuer => ({...issuer.disclosure, offered: issuer.offer.status === 'offered',
    notOfferedReason: issuer.offer.status === 'offered' ? null : issuer.offer.reason,
    // 'rfq': fills come from market makers; the transaction id is the maker's signature.
    route: issuer.identity.route}));
}
