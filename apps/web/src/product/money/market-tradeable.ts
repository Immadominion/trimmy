/**
 * The honest Market in Real mode: which companies can be traded right now,
 * read from the trading capabilities and matched to discovery's own tokens.
 */
import type {StockCard} from '../market-client.js';
import type {DiscoveryVariantRef, TradingCapabilities} from './live-trading.js';

export type DiscoveryIndex = ReadonlyMap<string, readonly DiscoveryVariantRef[]>;

export function companyTradeable(caps: TradingCapabilities | null, assetId: string, discovery?: DiscoveryIndex): boolean {
  return caps !== null && caps.companyTradeable(assetId, discovery?.get(assetId));
}

/**
 * One row per company with a token tradeable now, straight from the
 * capabilities (never a hard-coded list). Rows use the Market's card when it is
 * already loaded, otherwise the token's own name and symbol.
 */
export function tradeableCompanies(caps: TradingCapabilities, known: ReadonlyMap<string, StockCard>, discovery?: DiscoveryIndex): StockCard[] {
  const rows = new Map<string, StockCard>();
  for (const asset of caps.tradeableAssets) {
    if (rows.has(asset.assetId) || !caps.tradeableNow(asset) || !companyTradeable(caps, asset.assetId, discovery)) continue;
    rows.set(asset.assetId, known.get(asset.assetId) ?? Object.freeze({assetId: asset.assetId, name: asset.name, symbol: asset.symbol,
      imageUrl: null, stock: null, primaryVariant: null}));
  }
  return [...rows.values()];
}

export function discoveryRefs(variants: readonly {mint: string; issuer: string | null; label: string | null; symbol: string | null;
  market: {liquidityUsd: number | null} | null}[]): DiscoveryVariantRef[] {
  return variants.map(variant => ({mint: variant.mint, issuer: variant.issuer, label: variant.label, symbol: variant.symbol,
    liquidityUsd: variant.market?.liquidityUsd ?? null}));
}
