/** Server-owned execution identities. Each entry in the generated registry was
 * proven by tool/testing/stock-admission.mjs: issuer source of truth, pinned
 * on-chain authorities, finalized mint policy, Jupiter routes and an unsigned
 * order that passed the full review and simulation below.
 * Discovery metadata never adds an executable asset. Every order independently
 * re-reads mint/account state and must pass transaction reconciliation + simulation.
 * Verification: tool/testing/stock-admission.mjs --read-only
 */
import {STOCK_ISSUERS, isStockIssuerId, stockIssuerOffered} from './stock-issuers.js';
import type {StockIssuerId} from './stock-issuers.js';
import {STOCK_TRADING_REGISTRY} from './stock-trading-registry.generated.js';

export const STOCK_TOKEN_PROGRAM = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
/** 100 USDC at 6 decimals; the per-order buy ceiling for every asset. */
export const STOCK_MAX_BUY_INPUT_RAW = '100000000';

type RegistryEntry = (typeof STOCK_TRADING_REGISTRY)[number];
export type StockTradingAssetId = RegistryEntry['assetId'];
export type StockTradingSymbol = RegistryEntry['symbol'];
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
  /** Token-2022 transfer fee charged by the issuer on every transfer, in basis points. */
  readonly transferFeeBps: number;
  readonly status: StockTradingStatus;
  readonly admittedAt: string;
  readonly admissionSlot: number;
  /** Where the admission tool proved this mint's identity. */
  readonly issuerUrl: string;
  /** The one route orders use: Jupiter's aggregator, or JupiterZ market makers (RFQ). */
  readonly route: 'aggregator' | 'rfq';
}
export type StockTradingAsset = StockTradingIdentity & {readonly status: 'active'};

const BASE58 = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const RAW = /^[1-9][0-9]{0,19}$/;
/** Quote-asset keys (jupiter-quote-reader.ts) a stock symbol must never shadow. */
const RESERVED_SYMBOLS = new Set(['sol', 'usdc']);

function identitySource(entry: RegistryEntry): string {
  const registry = STOCK_ISSUERS[entry.issuerId].identity.registry;
  if (registry.kind === 'xstocks_api') return registry.url + entry.symbol;
  if (registry.kind === 'issuer_metadata') return STOCK_ISSUERS[entry.issuerId].identity.metadataUriPrefixes[0]!;
  return registry.url;
}

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
      maxBuyInputRaw: STOCK_MAX_BUY_INPUT_RAW, maxSellInputRaw: entry.maxSellInputRaw,
      transferFeeBps: entry.transferFeeBps, status: entry.status, admittedAt: entry.admittedAt,
      admissionSlot: entry.admissionSlot, issuerUrl: identitySource(entry), route,
    });
  }));
}

/** Every identity ever admitted, including suspended ones. Use for holdings and history recognition. */
export const STOCK_TRADING_IDENTITIES: readonly StockTradingIdentity[] = load();

/** Active and from an issuer Trimmy offers. Withdrawing an issuer's offer stops
 * trading in all of its tokens without deleting their identities. */
const tradeable = (asset: StockTradingIdentity): asset is StockTradingAsset =>
  asset.status === 'active' && stockIssuerOffered(asset.issuerId);

/** Identities that may be quoted and traded now. */
export const STOCK_TRADING_ASSETS: readonly StockTradingAsset[] = Object.freeze(STOCK_TRADING_IDENTITIES.filter(tradeable));

const byMint = new Map(STOCK_TRADING_IDENTITIES.map(asset => [asset.mint, asset]));

/** A tradeable asset bound to both its company and exact mint. */
export function findStockTradingAsset(assetId: unknown, mint: unknown): StockTradingAsset | undefined {
  if (typeof mint !== 'string') return undefined;
  const asset = byMint.get(mint);
  return asset && tradeable(asset) && asset.assetId === assetId ? asset : undefined;
}

/** Any admitted identity, active or suspended, for display and reconciliation of what a wallet holds or did. */
export function findStockTradingAssetByMint(mint: unknown): StockTradingIdentity | undefined {
  return typeof mint === 'string' ? byMint.get(mint) : undefined;
}
