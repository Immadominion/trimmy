/** Server-owned execution identities: every stock token Trimmy can trade.
 * The registry seeds the directory with tokens proven before admission became
 * automatic. The token directory
 * (stock-token-directory.ts) adds every other token its sources list whose
 * on-chain identity proves a supported issuer, without anyone approving it by
 * hand. Every order independently re-reads mint/account state and must pass
 * transaction reconciliation, simulation and a market price check.
 */
import {STOCK_ISSUERS, isStockIssuerId, stockIssuerOffered} from './stock-issuers.js';
import type {StockIssuerId} from './stock-issuers.js';
import {STOCK_TRADING_REGISTRY} from './stock-trading-registry.generated.js';

export const STOCK_TOKEN_PROGRAM = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
/** 100 USDC at 6 decimals; the per-order buy ceiling for every asset. */
export const STOCK_MAX_BUY_INPUT_RAW = '100000000';
/** Sells are bounded by what the wallet holds and each order's market price check. */
export const STOCK_MAX_SELL_INPUT_RAW = '18446744073709551615';

type RegistryEntry = (typeof STOCK_TRADING_REGISTRY)[number];
export type StockTradingAssetId = string;
export type StockTradingSymbol = string;
export type StockTradingStatus = 'active' | 'suspended';

export interface StockTradingIdentity {
  readonly assetId: StockTradingAssetId;
  readonly symbol: StockTradingSymbol;
  readonly name: string;
  readonly mint: string;
  readonly issuerId: StockIssuerId;
  readonly decimals: number;
  readonly tokenProgram: 'token_2022';
  readonly tokenProgramAddress: typeof STOCK_TOKEN_PROGRAM;
  readonly maxBuyInputRaw: typeof STOCK_MAX_BUY_INPUT_RAW;
  readonly maxSellInputRaw: string;
  /** The per-token sell cap older apps display (they show a limit line); the server no longer enforces it. */
  readonly installedAppSellCapRaw?: string;
  /** Token-2022 transfer fee charged by the issuer on every transfer, in basis points. */
  readonly transferFeeBps: number;
  readonly status: StockTradingStatus;
  readonly admittedAt: string;
  readonly admissionSlot: number;
  /** Where this mint's identity was proven. */
  readonly issuerUrl: string;
  /** The one route orders use: Jupiter's aggregator, or JupiterZ market makers (RFQ). */
  readonly route: 'aggregator' | 'rfq';
}
export type StockTradingAsset = StockTradingIdentity & {readonly status: 'active'};

export const STOCK_MINT_PATTERN = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
export const STOCK_ASSET_ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const BASE58 = STOCK_MINT_PATTERN;
const SLUG = STOCK_ASSET_ID_PATTERN;
const RAW = /^[1-9][0-9]{0,19}$/;
/** Quote-asset keys (jupiter-quote-reader.ts) a stock symbol must never shadow. */
const RESERVED_SYMBOLS = new Set(['sol', 'usdc']);

/** Where an issuer's tokens are listed, for display next to a token's identity. */
export function stockIdentitySource(issuerId: StockIssuerId, symbol: string): string {
  const registry = STOCK_ISSUERS[issuerId].identity.registry;
  if (registry.kind === 'xstocks_api') return registry.url + symbol;
  if (registry.kind === 'issuer_metadata') return STOCK_ISSUERS[issuerId].identity.metadataUriPrefixes[0]!;
  return registry.url;
}
const identitySource = (entry: RegistryEntry) => stockIdentitySource(entry.issuerId, entry.symbol);

function load(): readonly StockTradingIdentity[] {
  const mints = new Set<string>(), symbols = new Set<string>();
  return Object.freeze(STOCK_TRADING_REGISTRY.map(entry => {
    const issuer = isStockIssuerId(entry.issuerId) ? STOCK_ISSUERS[entry.issuerId] : undefined;
    if (!issuer || !BASE58.test(entry.mint) || !SLUG.test(entry.assetId) || entry.assetId.length > 100 ||
        typeof entry.symbol !== 'string' || !/^[A-Za-z0-9.]{1,32}$/.test(entry.symbol) ||
        typeof entry.name !== 'string' || entry.name.length < 1 || entry.name.length > 160 ||
        entry.decimals !== issuer.identity.decimals || !RAW.test(entry.maxSellInputRaw) ||
        !Number.isInteger(entry.transferFeeBps) || entry.transferFeeBps < 0 ||
        entry.transferFeeBps > issuer.identity.maxTransferFeeBps ||
        (entry.status !== 'active' && entry.status !== 'suspended') ||
        !/^\d{4}-\d\d-\d\d$/.test(entry.admittedAt) || !Number.isSafeInteger(entry.admissionSlot) || entry.admissionSlot < 1 ||
        mints.has(entry.mint) || symbols.has(entry.symbol.toLowerCase()) || RESERVED_SYMBOLS.has(entry.symbol.toLowerCase())) {
      throw new Error(`Invalid stock trading registry entry: ${String(entry.mint)}`);
    }
    // An entry may pin its own route (admission found liquidity only there); otherwise the issuer's.
    const route = 'route' in entry ? (entry as {route: unknown}).route : issuer.identity.route;
    if (route !== 'aggregator' && route !== 'rfq') throw new Error(`Invalid stock trading registry entry: ${String(entry.mint)}`);
    mints.add(entry.mint); symbols.add(entry.symbol.toLowerCase());
    return Object.freeze({
      assetId: entry.assetId, symbol: entry.symbol, name: entry.name, mint: entry.mint, issuerId: entry.issuerId,
      decimals: entry.decimals, tokenProgram: 'token_2022' as const, tokenProgramAddress: STOCK_TOKEN_PROGRAM,
      maxBuyInputRaw: STOCK_MAX_BUY_INPUT_RAW, maxSellInputRaw: STOCK_MAX_SELL_INPUT_RAW, installedAppSellCapRaw: entry.maxSellInputRaw,
      transferFeeBps: entry.transferFeeBps, status: entry.status, admittedAt: entry.admittedAt,
      admissionSlot: entry.admissionSlot, issuerUrl: identitySource(entry), route,
    });
  }));
}

/** The seed: identities proven at admission, including suspended ones. */
export const STOCK_TRADING_IDENTITIES: readonly StockTradingIdentity[] = load();

/** Active and from an issuer Trimmy offers. Withdrawing an issuer's offer stops
 * trading in all of its tokens without deleting their identities. */
const tradeable = (asset: StockTradingIdentity): asset is StockTradingAsset =>
  asset.status === 'active' && stockIssuerOffered(asset.issuerId);

/** Seed identities that may be traded. Installed apps' version 1 capabilities read these. */
export const STOCK_TRADING_ASSETS: readonly StockTradingAsset[] = Object.freeze(STOCK_TRADING_IDENTITIES.filter(tradeable));

const byMint = new Map<string, StockTradingIdentity>(STOCK_TRADING_IDENTITIES.map(asset => [asset.mint, asset]));
let identitiesView: readonly StockTradingIdentity[] = STOCK_TRADING_IDENTITIES;
let assetsView: readonly StockTradingAsset[] = STOCK_TRADING_ASSETS;

/** Every recognized identity now: the seed plus tokens the directory found. */
export function stockTradingIdentities(): readonly StockTradingIdentity[] { return identitiesView; }

/** Every identity that may be quoted and traded now. */
export function stockTradingAssets(): readonly StockTradingAsset[] { return assetsView; }

/**
 * Adds an identity the token directory proved. A mint is never replaced: the
 * first identity recorded for it stands. Returns whether it was added.
 */
export function registerStockTradingIdentity(identity: StockTradingIdentity): boolean {
  const issuer = isStockIssuerId(identity.issuerId) ? STOCK_ISSUERS[identity.issuerId] : undefined;
  if (byMint.has(identity.mint)) return false;
  if (!issuer || !BASE58.test(identity.mint) || !SLUG.test(identity.assetId) || identity.assetId.length > 100 ||
      !/^[A-Za-z0-9.]{1,32}$/.test(identity.symbol) || RESERVED_SYMBOLS.has(identity.symbol.toLowerCase()) ||
      identity.name.length < 1 || identity.name.length > 160 || identity.decimals !== issuer.identity.decimals ||
      !Number.isInteger(identity.transferFeeBps) || identity.transferFeeBps < 0 ||
      identity.transferFeeBps > issuer.identity.maxTransferFeeBps || (identity.route !== 'aggregator' && identity.route !== 'rfq') ||
      (identity.status !== 'active' && identity.status !== 'suspended')) {
    throw new Error(`Invalid stock trading identity: ${String(identity.mint)}`);
  }
  const frozen = Object.freeze({...identity});
  byMint.set(frozen.mint, frozen);
  identitiesView = Object.freeze([...identitiesView, frozen]);
  if (tradeable(frozen)) assetsView = Object.freeze([...assetsView, frozen]);
  return true;
}

/** Tokens from a user's past orders that no source lists any more: display only, never traded. */
const recalled = new Map<string, StockTradingIdentity>();

/** Remembers a past order's token for display. It never becomes tradeable this way. */
export function recallStockIdentity(identity: StockTradingIdentity): void {
  if (byMint.has(identity.mint) || recalled.has(identity.mint)) return;
  recalled.set(identity.mint, Object.freeze({...identity, status: 'suspended' as const}));
}

/** A tradeable asset bound to both its company and exact mint. */
export function findStockTradingAsset(assetId: unknown, mint: unknown): StockTradingAsset | undefined {
  if (typeof mint !== 'string') return undefined;
  const asset = byMint.get(mint);
  return asset && tradeable(asset) && asset.assetId === assetId ? asset : undefined;
}

/** Any recognized identity, active or suspended, for display and reconciliation of what a wallet holds or did. */
export function findStockTradingAssetByMint(mint: unknown): StockTradingIdentity | undefined {
  return typeof mint === 'string' ? byMint.get(mint) ?? recalled.get(mint) : undefined;
}
