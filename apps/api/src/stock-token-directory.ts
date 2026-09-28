import { BoundedSolanaRpc } from './solana-rpc-client.js';
import { STOCK_ISSUER_IDS, STOCK_ISSUERS, stockIssuerOffered } from './stock-issuers.js';
import type { StockIssuerId } from './stock-issuers.js';
import type { StockDiscovery } from './stock-discovery.js';
import {
  STOCK_ASSET_ID_PATTERN, STOCK_MAX_BUY_INPUT_RAW, STOCK_MAX_SELL_INPUT_RAW, STOCK_MINT_PATTERN, STOCK_TOKEN_PROGRAM,
  findStockTradingAsset, findStockTradingAssetByMint, recallStockIdentity, registerStockTradingIdentity, stockIdentitySource,
} from './stock-trading-catalog.js';
import type { StockTradingAsset, StockTradingIdentity } from './stock-trading-catalog.js';

/**
 * Every stock token Trimmy can trade, found automatically: nobody approves a
 * token by hand. A token qualifies when two independent sources agree:
 *
 * 1. The Market's curated source (Tokens.xyz) lists it as a stock, fund or
 *    commodity token. On-chain keys alone can be copied onto a lookalike mint,
 *    so a curated listing is required.
 * 2. Its mint carries the pinned identity of a supported issuer (metadata,
 *    mint, freeze and delegate authorities, metadata host, decimals), and its
 *    rules allow ordinary transfers.
 *
 * Tokens are checked in sweeps over the Market's catalog and the moment an
 * order names one. Every order is still reviewed, simulated and priced
 * against the market before anyone signs.
 */
export type StockTokenRefusal = 'identity_unverified' | 'token_restricted' | 'issuer_not_offered';

export interface StockTokenRefused {
  readonly mint: string;
  readonly issuerId: StockIssuerId | null;
  readonly reason: StockTokenRefusal;
  readonly symbol: string | null;
  /** Internal check that failed; never user-facing. */
  readonly detail: string;
}

export type StockTokenCheck =
  | {readonly ok: true; readonly identity: StockTradingIdentity}
  | {readonly ok: false; readonly refused: StockTokenRefused};

interface ParsedExtension { readonly extension?: unknown; readonly state?: unknown }
const record = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
const byUpdateAuthority = new Map(STOCK_ISSUER_IDS.map(id => [STOCK_ISSUERS[id].identity.metadataUpdateAuthority, id]));
const CONTROL_CHARACTERS = new RegExp('[\\u0000-\\u001f\\u007f\\u2028\\u2029]');
const RESTRICTIONS = new Set(['DEFAULT_FROZEN', 'TRANSFER_HOOK_PROGRAM', 'NON_TRANSFERABLE', 'TRANSFER_FEE_ABOVE_ISSUER_CAP']);

/** Checks one mint read with `jsonParsed` encoding against the issuers Trimmy supports. */
export function checkStockMint(mint: string, value: unknown, source: {readonly assetId: string; readonly slot: number; readonly now: number}): StockTokenCheck {
  const account = record(value);
  const data = record(account['data']);
  const parsed = record(data['parsed']);
  const info = record(parsed['info']);
  const extensions = new Map<string, Record<string, unknown>>();
  for (const item of Array.isArray(info['extensions']) ? info['extensions'] as ParsedExtension[] : []) {
    if (typeof item?.extension === 'string') extensions.set(item.extension, record(item.state));
  }
  const metadata = extensions.get('tokenMetadata') ?? {};
  const symbol = typeof metadata['symbol'] === 'string' ? metadata['symbol'] : null;
  const name = typeof metadata['name'] === 'string' ? metadata['name'].trim() : '';
  const issuerId = byUpdateAuthority.get(metadata['updateAuthority'] as string) ?? null;
  const refuse = (reason: StockTokenRefusal, detail: string): StockTokenCheck =>
    ({ok: false, refused: Object.freeze({mint, issuerId, reason, symbol: symbol && /^[A-Za-z0-9.-]{1,32}$/.test(symbol) ? symbol : null, detail})});
  if (issuerId === null) return refuse('identity_unverified', 'NO_ISSUER_FINGERPRINT');
  const identity = STOCK_ISSUERS[issuerId].identity;
  const fee = extensions.get('transferFeeConfig');
  const feeBps = fee ? Math.max(Number(record(fee['newerTransferFee'])['transferFeeBasisPoints'] ?? 0),
    Number(record(fee['olderTransferFee'])['transferFeeBasisPoints'] ?? 0)) : 0;
  const uri = metadata['uri'];
  const checks: readonly (readonly [boolean, string])[] = [
    [account['owner'] === STOCK_TOKEN_PROGRAM && parsed['type'] === 'mint', 'TOKEN_PROGRAM'],
    [info['isInitialized'] === true, 'NOT_INITIALIZED'],
    [info['decimals'] === identity.decimals, 'DECIMALS'],
    [identity.mintAuthority === null || info['mintAuthority'] === identity.mintAuthority, 'MINT_AUTHORITY'],
    [identity.freezeAuthorities.includes(info['freezeAuthority'] as string), 'FREEZE_AUTHORITY'],
    [(extensions.get('permanentDelegate')?.['delegate'] ?? null) === identity.permanentDelegate, 'PERMANENT_DELEGATE'],
    [typeof uri === 'string' && identity.metadataUriPrefixes.some(prefix => uri.startsWith(prefix)), 'METADATA_HOST'],
    [symbol !== null && /^[A-Za-z0-9.]{1,32}$/.test(symbol) && !['sol', 'usdc'].includes(symbol.toLowerCase()), 'SYMBOL_FORMAT'],
    [name.length > 0 && name.length <= 160 && !CONTROL_CHARACTERS.test(name), 'NAME_FORMAT'],
    [STOCK_ASSET_ID_PATTERN.test(source.assetId) && source.assetId.length <= 100, 'ASSET_ID_FORMAT'],
    [!extensions.has('defaultAccountState') || extensions.get('defaultAccountState')!['accountState'] === 'initialized', 'DEFAULT_FROZEN'],
    [!extensions.has('transferHook') || extensions.get('transferHook')!['programId'] == null, 'TRANSFER_HOOK_PROGRAM'],
    [!extensions.has('nonTransferable'), 'NON_TRANSFERABLE'],
    [Number.isInteger(feeBps) && feeBps >= 0 && feeBps <= identity.maxTransferFeeBps, 'TRANSFER_FEE_ABOVE_ISSUER_CAP'],
  ];
  const failed = checks.find(([ok]) => !ok);
  if (failed) return refuse(RESTRICTIONS.has(failed[1]) ? 'token_restricted' : 'identity_unverified', failed[1]);
  if (!stockIssuerOffered(issuerId)) return refuse('issuer_not_offered', 'ISSUER_NOT_OFFERED');
  // A paused mint stays listed: its market state says so, and orders wait until it resumes.
  return {ok: true, identity: Object.freeze({
    assetId: source.assetId, symbol: symbol!, name, mint, issuerId, decimals: identity.decimals,
    tokenProgram: 'token_2022' as const, tokenProgramAddress: STOCK_TOKEN_PROGRAM,
    maxBuyInputRaw: STOCK_MAX_BUY_INPUT_RAW, maxSellInputRaw: STOCK_MAX_SELL_INPUT_RAW, transferFeeBps: feeBps,
    status: 'active' as const, admittedAt: new Date(source.now).toISOString().slice(0, 10), admissionSlot: source.slot,
    issuerUrl: stockIdentitySource(issuerId, symbol!), route: identity.route,
  })};
}

class DirectoryReadError extends Error {}
const RPC_ERRORS = Object.freeze({
  configuration: () => new DirectoryReadError('configuration'), timeout: () => new DirectoryReadError('timeout'),
  unavailable: () => new DirectoryReadError('unavailable'), responseInvalid: () => new DirectoryReadError('response'),
  methodNotAllowed: () => new DirectoryReadError('method'),
});
const LISTED_CATEGORIES = new Set(['equity', 'etf', 'commodity']);
const REFUSAL_RETRY_MS = 30 * 60_000;

export interface StockTokenDirectoryOptions {
  readonly rpcUrl: string;
  /** The Market's catalog source; without it only the seed trades. */
  readonly discovery?: StockDiscovery;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly refreshMs?: number;
}

export class StockTokenDirectory {
  readonly #rpc: BoundedSolanaRpc<'getMultipleAccounts', DirectoryReadError>;
  readonly #discovery: StockDiscovery | undefined;
  readonly #now: () => number;
  readonly #refreshMs: number;
  /** Mint to the company the catalog lists it under, from the last sweep. */
  #listed = new Map<string, string>();
  readonly #refused = new Map<string, {readonly refused: StockTokenRefused; readonly at: number}>();
  #sweep: Promise<void> | null = null;
  #lastSweep = Number.NEGATIVE_INFINITY;
  #timer: ReturnType<typeof setInterval> | null = null;

  constructor(options: StockTokenDirectoryOptions) {
    this.#rpc = new BoundedSolanaRpc({rpcUrl: options.rpcUrl, methods: ['getMultipleAccounts'], errors: RPC_ERRORS,
      maxBodyBytes: 4_194_304, timeoutMs: 8_000, ...(options.fetch ? {fetch: options.fetch} : {})});
    this.#discovery = options.discovery;
    this.#now = options.now ?? Date.now;
    this.#refreshMs = options.refreshMs ?? 30 * 60_000;
  }

  /** Sweeps now and then on a timer. Failures are retried at the next sweep. */
  start(): void {
    if (this.#timer !== null) return;
    void this.refresh().catch(() => undefined);
    this.#timer = setInterval(() => { void this.refresh().catch(() => undefined); }, this.#refreshMs);
    this.#timer.unref?.();
  }

  stop(): void {
    if (this.#timer !== null) clearInterval(this.#timer);
    this.#timer = null;
  }

  /** Tokens the directory checked and refused, for the Market to explain. */
  refusals(): readonly StockTokenRefused[] {
    return [...this.#refused.values()].map(item => item.refused);
  }

  /** Reads every catalog page and checks each token not yet known. */
  refresh(): Promise<void> {
    this.#sweep ??= this.#refresh().finally(() => { this.#sweep = null; });
    return this.#sweep;
  }

  async #refresh(): Promise<void> {
    if (!this.#discovery?.catalog) return;
    const listed = new Map<string, string>();
    for (let offset: number | null = 0, pages = 0; offset !== null && pages < 500; pages++) {
      const page = await this.#discovery.catalog(offset, 2);
      for (const asset of page.discovery.results) {
        if (!LISTED_CATEGORIES.has(asset.category)) continue;
        for (const variant of asset.variants) if (!listed.has(variant.mint)) listed.set(variant.mint, asset.assetId);
      }
      offset = page.nextOffset;
    }
    this.#listed = listed;
    this.#lastSweep = this.#now();
    await this.#check([...listed].filter(([mint]) => !this.#known(mint)).map(([mint, assetId]) => ({mint, assetId})));
  }

  /** The tradeable token an order names, checking it first when it is new. */
  async ensure(assetId: string, mint: string): Promise<StockTradingAsset | undefined> {
    const known = findStockTradingAsset(assetId, mint);
    if (known || this.#known(mint)) return known;
    if (!STOCK_MINT_PATTERN.test(mint) || !STOCK_ASSET_ID_PATTERN.test(assetId)) return undefined;
    // The curated source must list this token under this company.
    let listedUnder = this.#listed.get(mint);
    if (listedUnder === undefined && this.#discovery) {
      try {
        const page = await this.#discovery.variants({assetId});
        if (page.variants.some(variant => variant.mint === mint)) listedUnder = assetId;
      } catch { return undefined; }
    }
    if (listedUnder !== assetId) return undefined;
    await this.#check([{mint, assetId}]);
    return findStockTradingAsset(assetId, mint);
  }

  #known(mint: string): boolean {
    if (findStockTradingAssetByMint(mint)) return true;
    const refused = this.#refused.get(mint);
    return refused !== undefined && this.#now() - refused.at < REFUSAL_RETRY_MS;
  }

  async #check(tokens: readonly {readonly mint: string; readonly assetId: string}[]): Promise<void> {
    for (let index = 0; index < tokens.length; index += 100) {
      const part = tokens.slice(index, index + 100);
      let outcome;
      try {
        outcome = await this.#rpc.call('getMultipleAccounts', [part.map(token => token.mint), {encoding: 'jsonParsed', commitment: 'confirmed'}]);
      } catch { continue; }
      const values = (outcome.result as {value?: unknown} | null)?.value;
      if (!Array.isArray(values) || values.length !== part.length) continue;
      const slot = Number(outcome.contextSlot ?? 0);
      part.forEach((token, position) => {
        const result = checkStockMint(token.mint, values[position], {assetId: token.assetId, slot, now: this.#now()});
        if (result.ok) {
          try { registerStockTradingIdentity(result.identity); this.#refused.delete(token.mint); }
          catch { this.#refused.set(token.mint, {refused: {mint: token.mint, issuerId: result.identity.issuerId,
            reason: 'identity_unverified', symbol: result.identity.symbol, detail: 'REGISTRY_REJECTED'}, at: this.#now()}); }
        } else {
          this.#refused.set(token.mint, {refused: result.refused, at: this.#now()});
        }
      });
    }
  }

  /**
   * Recognizes tokens from a user's past orders for display, when no current source
   * lists them. The issuer fingerprint must still match; they never become tradeable.
   */
  async recall(mints: readonly string[]): Promise<void> {
    const unknown = [...new Set(mints)].filter(mint => STOCK_MINT_PATTERN.test(mint) && !findStockTradingAssetByMint(mint));
    for (let index = 0; index < unknown.length; index += 100) {
      const part = unknown.slice(index, index + 100);
      let outcome;
      try { outcome = await this.#rpc.call('getMultipleAccounts', [part, {encoding: 'jsonParsed', commitment: 'confirmed'}]); }
      catch { continue; }
      const values = (outcome.result as {value?: unknown} | null)?.value;
      if (!Array.isArray(values) || values.length !== part.length) continue;
      part.forEach((mint, position) => {
        const result = checkStockMint(mint, values[position], {assetId: 'unlisted', slot: Number(outcome.contextSlot ?? 0), now: this.#now()});
        if (result.ok) recallStockIdentity(result.identity);
      });
    }
  }

  /** When the last full sweep finished, for status reporting. */
  get lastSweepAt(): number | null { return Number.isFinite(this.#lastSweep) ? this.#lastSweep : null; }
}
