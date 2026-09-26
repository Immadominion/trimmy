import { address, getAddressEncoder, getProgramDerivedAddress } from '@solana/kit';
import type { Address } from '@solana/kit';
import {BoundedProviderRead} from './bounded-provider-read.js';
import { JUPITER_QUOTE_ASSETS } from './jupiter-quote-reader.js';
import {STOCK_TRADING_ASSETS} from './stock-trading-catalog.js';

export const STOCK_HOLDINGS_MAINNET_GENESIS = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
export const STOCK_HOLDINGS_TOKEN_PROGRAMS = Object.freeze({
  legacy: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
  token2022: 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb',
  associated: 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL',
});

const MAX_JSON_BYTES = 262_144;
const MAX_TOKEN_ACCOUNTS = 128;
const MAX_TOKEN_ACCOUNT_BYTES = 65_536;
const MAX_U64 = (1n << 64n) - 1n;
const verifiedOwners = new WeakSet<object>();
const DEFAULT_CACHE_TTL_MS = 3_000;
const DEFAULT_RATE_LIMIT_WINDOW_MS = 60_000;
const DEFAULT_PER_USER_LIMIT = 6;
const DEFAULT_GLOBAL_LIMIT = 120;
const DEFAULT_MAX_TRACKED_USERS = 2_048;
const DEFAULT_MAX_CACHED_ADDRESSES = 512;
const DEFAULT_MAX_CONCURRENT_READS = 8;

export interface ServerVerifiedStockOwner {
  readonly kind: 'server_verified_stock_owner';
  readonly authenticatedUserId: string;
  readonly address: Address;
  readonly verification: 'authenticated_privy_embedded_wallet';
}

export interface AdmitServerVerifiedStockOwnerInput {
  readonly authenticatedUserId: string;
  readonly address: string;
  readonly verification: 'authenticated_privy_embedded_wallet';
}

export interface StockTokenAccountBalance {
  readonly address: Address;
  readonly amountRaw: string;
  readonly state: 'initialized' | 'frozen';
  readonly associated: boolean;
  /** v2 only: RPC's mint-adjusted UI amount, never a transaction input. */
  readonly displayAmount?: string | null;
}

export type StockTokenAccountTopology =
  | 'none'
  | 'associated_only'
  | 'associated_with_ancillary'
  | 'ancillary_only'
  | 'multiple_ancillary';

export interface StockTokenHolding {
  readonly kind: 'spl_token';
  readonly symbol: string;
  readonly mint: Address;
  readonly tokenProgram: Address;
  readonly decimals: number;
  readonly amountRaw: string;
  readonly amountUnits: 'raw_token_units';
  readonly observedSlot: number;
  readonly accounts: readonly StockTokenAccountBalance[];
  readonly associatedTokenAccount: Readonly<{
    address: Address;
    status: 'present' | 'absent';
  }>;
  readonly accountTopology: StockTokenAccountTopology;
  readonly aggregation: 'all_valid_owner_token_accounts';
  readonly hasFrozenAccounts: boolean;
}

export interface StockPortfolioTokenHolding extends StockTokenHolding {
  readonly assetId: string;
  readonly name: string;
  readonly displayAmount: string | null;
  readonly displayResolution: 'rpc_ui_amount' | 'unavailable';
  readonly displayUnits: 'token_units';
}

export interface StockHoldingsSnapshot {
  readonly schemaVersion: 1;
  readonly network: 'solana:mainnet-beta';
  readonly genesisHash: typeof STOCK_HOLDINGS_MAINNET_GENESIS;
  readonly commitment: 'confirmed';
  readonly owner: Address;
  readonly ownerBinding: 'trusted_server_capability';
  readonly observedAt: string;
  readonly readOnly: true;
  readonly transactionBuilt: false;
  readonly transactionSigned: false;
  readonly transactionBroadcast: false;
  readonly balances: Readonly<{
    nativeSol: Readonly<{
      kind: 'native';
      symbol: 'SOL';
      decimals: 9;
      amountRaw: string;
      amountUnits: 'lamports';
      observedSlot: number;
    }>;
    usdc: StockTokenHolding;
    aaplx: StockTokenHolding & Readonly<{
      displayResolution: 'token_2022_scaled_ui_unresolved';
      displayAmount: null;
      shareAmount: null;
      eligibility: 'unverified';
      executionEnabled: false;
    }>;
    /** Present only when the caller opts in to holdings version 2. */
    tokens?: readonly StockPortfolioTokenHolding[];
  }>;
  readonly consistency: Readonly<{
    kind: 'independent_confirmed_reads';
    atomic: false;
    slots: Readonly<{nativeSol: number; usdc: number; aaplx: number}>;
  }>;
}

export type StockHoldingsErrorCode =
  | 'STOCK_HOLDINGS_OWNER_INVALID'
  | 'STOCK_HOLDINGS_OWNER_UNVERIFIED'
  | 'STOCK_HOLDINGS_CONFIGURATION_INVALID'
  | 'STOCK_HOLDINGS_RPC_UNAVAILABLE'
  | 'STOCK_HOLDINGS_RPC_TIMEOUT'
  | 'STOCK_HOLDINGS_RPC_RESPONSE_INVALID'
  | 'STOCK_HOLDINGS_WRONG_NETWORK'
  | 'STOCK_HOLDINGS_RATE_LIMITED';

const errorMessages: Readonly<Record<StockHoldingsErrorCode, string>> = Object.freeze({
  STOCK_HOLDINGS_OWNER_INVALID: 'The linked wallet owner is invalid.',
  STOCK_HOLDINGS_OWNER_UNVERIFIED: 'A verified linked wallet is required.',
  STOCK_HOLDINGS_CONFIGURATION_INVALID: 'Stock holdings are not configured correctly.',
  STOCK_HOLDINGS_RPC_UNAVAILABLE: 'Stock holdings are temporarily unavailable.',
  STOCK_HOLDINGS_RPC_TIMEOUT: 'The stock holdings read took too long.',
  STOCK_HOLDINGS_RPC_RESPONSE_INVALID: 'Stock holdings could not be verified.',
  STOCK_HOLDINGS_WRONG_NETWORK: 'Stock holdings are connected to the wrong network.',
  STOCK_HOLDINGS_RATE_LIMITED: 'Too many stock holdings reads. Try again shortly.',
});

export class StockHoldingsError extends Error {
  constructor(readonly code: StockHoldingsErrorCode) {
    super(errorMessages[code]);
    this.name = 'StockHoldingsError';
  }
}

function fail(code: StockHoldingsErrorCode): never {
  throw new StockHoldingsError(code);
}

function plainRecord(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
  }
  const prototype: unknown = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) {
    return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
  }
  return value as Record<string, unknown>;
}

function responseAddress(value: unknown): Address {
  try {
    if (typeof value !== 'string' || value.length > 44) return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
    return address(value);
  } catch {
    return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
  }
}

function canonicalRawU64(value: unknown): string {
  if (typeof value !== 'string' || /^(?:0|[1-9][0-9]{0,19})$/.exec(value)?.[0] !== value) {
    return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
  }
  try {
    if (BigInt(value) > MAX_U64) return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
    return value;
  } catch {
    return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
  }
}

function contextSlot(value: unknown): number {
  const result = plainRecord(value);
  const slot = result['slot'];
  if (typeof slot !== 'number' || !Number.isSafeInteger(slot) || slot < 0) {
    return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
  }
  return slot;
}

/**
 * Creates an in-process capability after server-side identity and linked-wallet
 * ownership verification. Do not call this with request body/query values.
 * Serialized or reconstructed objects cannot be used with the reader.
 */
export function admitServerVerifiedStockOwner(input: AdmitServerVerifiedStockOwnerInput): ServerVerifiedStockOwner {
  try {
    if (input === null || typeof input !== 'object' || Array.isArray(input)) {
      return fail('STOCK_HOLDINGS_OWNER_INVALID');
    }
    const prototype: unknown = Object.getPrototypeOf(input);
    const keys = Reflect.ownKeys(input);
    if ((prototype !== Object.prototype && prototype !== null) || keys.length !== 3 ||
        keys.some((key) => typeof key !== 'string' ||
          !['authenticatedUserId', 'address', 'verification'].includes(key))) {
      return fail('STOCK_HOLDINGS_OWNER_INVALID');
    }
    const values: Record<string, unknown> = {};
    for (const key of keys) {
      const descriptor = Object.getOwnPropertyDescriptor(input, key);
      if (typeof key !== 'string' || !descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) {
        return fail('STOCK_HOLDINGS_OWNER_INVALID');
      }
      values[key] = descriptor.value;
    }
    const userId = values['authenticatedUserId'];
    const walletAddress = values['address'];
    if (typeof userId !== 'string' ||
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.exec(userId)?.[0] !== userId ||
        values['verification'] !== 'authenticated_privy_embedded_wallet' ||
        typeof walletAddress !== 'string' || walletAddress.length > 44) {
      return fail('STOCK_HOLDINGS_OWNER_INVALID');
    }
    const owner = Object.freeze({
      kind: 'server_verified_stock_owner' as const,
      authenticatedUserId: userId,
      address: address(walletAddress),
      verification: 'authenticated_privy_embedded_wallet' as const,
    });
    verifiedOwners.add(owner);
    return owner;
  } catch (error) {
    if (error instanceof StockHoldingsError) throw error;
    return fail('STOCK_HOLDINGS_OWNER_INVALID');
  }
}

type RpcMethod = 'getGenesisHash' | 'getBalance' | 'getTokenAccountsByOwner';

interface RpcClientOptions {
  readonly rpcUrl: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly timeoutMs?: number;
}

class ReadOnlyHoldingsRpc {
  readonly #url!: URL;
  readonly #fetch!: typeof globalThis.fetch;
  readonly #timeoutMs!: number;
  #requestId = 0;

  constructor(options: RpcClientOptions) {
    try {
      if (options === null || typeof options !== 'object' || Array.isArray(options) ||
          typeof options.rpcUrl !== 'string' || options.rpcUrl.length < 1 || options.rpcUrl.length > 2048 ||
          /[\u0000-\u0020\u007f]/.test(options.rpcUrl) ||
          (options.fetch !== undefined && typeof options.fetch !== 'function')) {
        return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
      }
      const url = new URL(options.rpcUrl);
      if (url.protocol !== 'https:' || url.username !== '' || url.password !== '' || url.hash !== '') {
        return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
      }
      const timeoutMs = options.timeoutMs ?? 6_000;
      if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 8_000) {
        return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
      }
      this.#url = url;
      this.#fetch = options.fetch ?? globalThis.fetch;
      this.#timeoutMs = timeoutMs;
    } catch (error) {
      if (error instanceof StockHoldingsError) throw error;
      return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
    }
  }

  async call(method: RpcMethod, params: readonly unknown[]): Promise<unknown> {
    const id = ++this.#requestId;
    if (!Number.isSafeInteger(id)) return fail('STOCK_HOLDINGS_RPC_UNAVAILABLE');
    const controller = new AbortController();
    let timedOut = false;
    let rejectDeadline: (error: Error) => void = () => undefined;
    const deadline = new Promise<never>((_resolve, reject) => { rejectDeadline = reject; });
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
      rejectDeadline(new StockHoldingsError('STOCK_HOLDINGS_RPC_TIMEOUT'));
    }, this.#timeoutMs);
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let response: Response | undefined;
    try {
      const pending = this.#fetch(this.#url, {
        method: 'POST',
        headers: {'content-type': 'application/json', accept: 'application/json'},
        redirect: 'error',
        signal: controller.signal,
        body: JSON.stringify({jsonrpc: '2.0', id, method, params}),
      });
      void pending.then((late) => {
        if (controller.signal.aborted) void late.body?.cancel().catch(() => undefined);
      }, () => undefined);
      response = await Promise.race([pending, deadline]);
      if (!response.ok || response.redirected) return fail('STOCK_HOLDINGS_RPC_UNAVAILABLE');
      if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body) {
        return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
      }
      const declared = response.headers.get('content-length');
      if (declared !== null && (declared.length > 20 || /^(?:0|[1-9][0-9]*)$/.exec(declared)?.[0] !== declared ||
          BigInt(declared) > BigInt(MAX_JSON_BYTES))) {
        return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
      }
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      while (true) {
        const part = await Promise.race([reader.read(), deadline]);
        if (part.done) break;
        bytes += part.value.byteLength;
        if (bytes > MAX_JSON_BYTES) return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
        chunks.push(part.value);
      }
      let payload: unknown;
      try {
        payload = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
      } catch {
        return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
      }
      const envelope = plainRecord(payload);
      if (envelope['jsonrpc'] !== '2.0' || envelope['id'] !== id || !Object.hasOwn(envelope, 'result') ||
          Object.hasOwn(envelope, 'error')) {
        return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
      }
      return envelope['result'];
    } catch (error) {
      if (timedOut || controller.signal.aborted) return fail('STOCK_HOLDINGS_RPC_TIMEOUT');
      if (error instanceof StockHoldingsError) throw error;
      return fail('STOCK_HOLDINGS_RPC_UNAVAILABLE');
    } finally {
      clearTimeout(timer);
      controller.abort();
      if (reader) void reader.cancel().catch(() => undefined);
      else if (response?.body) void response.body.cancel().catch(() => undefined);
    }
  }
}

interface TokenDefinition {
  readonly symbol: string;
  readonly mint: Address;
  readonly decimals: number;
  readonly tokenProgram: Address;
  readonly parsedProgram: 'spl-token' | 'spl-token-2022';
}

const USDC: TokenDefinition = Object.freeze({
  symbol: 'USDC', mint: address(JUPITER_QUOTE_ASSETS.USDC.mint), decimals: 6,
  tokenProgram: address(STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy), parsedProgram: 'spl-token',
});
const AAPLX: TokenDefinition = Object.freeze({
  symbol: 'AAPLx', mint: address(JUPITER_QUOTE_ASSETS.AAPLx.mint), decimals: 8,
  tokenProgram: address(STOCK_HOLDINGS_TOKEN_PROGRAMS.token2022), parsedProgram: 'spl-token-2022',
});

async function associatedTokenAddress(owner: Address, token: TokenDefinition): Promise<Address> {
  try {
    const encoder = getAddressEncoder();
    const [derived] = await getProgramDerivedAddress({
      programAddress: address(STOCK_HOLDINGS_TOKEN_PROGRAMS.associated),
      seeds: [encoder.encode(owner), encoder.encode(token.tokenProgram), encoder.encode(token.mint)],
    });
    return derived;
  } catch {
    return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
  }
}

function accountTopology(accounts: readonly StockTokenAccountBalance[]): StockTokenAccountTopology {
  const associatedCount = accounts.filter((item) => item.associated).length;
  if (accounts.length === 0) return 'none';
  if (associatedCount === 1 && accounts.length === 1) return 'associated_only';
  if (associatedCount === 1) return 'associated_with_ancillary';
  return accounts.length === 1 ? 'ancillary_only' : 'multiple_ancillary';
}

function tokenHolding(result: unknown, owner: Address, token: TokenDefinition,
  associatedAddress: Address, includeDisplay = false): StockTokenHolding {
  const response = plainRecord(result);
  const slot = contextSlot(response['context']);
  const values = response['value'];
  if (!Array.isArray(values) || values.length > MAX_TOKEN_ACCOUNTS) {
    return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
  }
  const seen = new Set<string>();
  const accounts: StockTokenAccountBalance[] = [];
  let total = 0n;
  for (const item of values) {
    const entry = plainRecord(item);
    const accountAddress = responseAddress(entry['pubkey']);
    if (seen.has(accountAddress)) return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
    seen.add(accountAddress);
    const account = plainRecord(entry['account']);
    const data = plainRecord(account['data']);
    const parsed = plainRecord(data['parsed']);
    const info = plainRecord(parsed['info']);
    const tokenAmount = plainRecord(info['tokenAmount']);
    const space = data['space'];
    const outerSpace = account['space'];
    if (account['owner'] !== token.tokenProgram || account['executable'] !== false ||
        data['program'] !== token.parsedProgram || parsed['type'] !== 'account' ||
        info['mint'] !== token.mint || info['owner'] !== owner || info['isNative'] !== false ||
        (info['state'] !== 'initialized' && info['state'] !== 'frozen') ||
        tokenAmount['decimals'] !== token.decimals || typeof space !== 'number' ||
        !Number.isSafeInteger(space) || space < 165 || space > MAX_TOKEN_ACCOUNT_BYTES ||
        (outerSpace !== undefined && outerSpace !== space) ||
        (token.tokenProgram === USDC.tokenProgram && space !== 165)) {
      return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
    }
    const amountRaw = canonicalRawU64(tokenAmount['amount']);
    total += BigInt(amountRaw);
    if (total > MAX_U64) return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
    accounts.push(Object.freeze({
      address: accountAddress,
      amountRaw,
      state: info['state'] as 'initialized' | 'frozen',
      associated: accountAddress === associatedAddress,
      ...(includeDisplay ? {displayAmount: canonicalTokenDisplayAmount(tokenAmount['uiAmountString'], token.decimals,
        amountRaw)} : {}),
    }));
  }
  accounts.sort((left, right) => left.address.localeCompare(right.address));
  const frozenAccounts = Object.freeze(accounts);
  const topology = accountTopology(frozenAccounts);
  return Object.freeze({
    kind: 'spl_token', symbol: token.symbol, mint: token.mint, tokenProgram: token.tokenProgram,
    decimals: token.decimals, amountRaw: total.toString(), amountUnits: 'raw_token_units', observedSlot: slot,
    accounts: frozenAccounts,
    associatedTokenAccount: Object.freeze({
      address: associatedAddress,
      status: frozenAccounts.some((item) => item.associated) ? 'present' : 'absent',
    }),
    accountTopology: topology,
    aggregation: 'all_valid_owner_token_accounts',
    hasFrozenAccounts: frozenAccounts.some((item) => item.state === 'frozen'),
  });
}

/**
 * Solana's jsonParsed UI amount applies the mint's current scaled-UI multiplier.
 * Keep it separate from integer transaction amounts. Truncate to mint precision,
 * as recommended by the scaled-UI integration guide; never use floating point.
 */
export function canonicalTokenDisplayAmount(value: unknown, decimals: number, amountRaw?: string): string | null {
  if (typeof value !== 'string' || value.length > 80 ||
      !/^(?:0|[1-9][0-9]{0,39})(?:\.[0-9]{1,36})?$/.test(value) ||
      !Number.isInteger(decimals) || decimals < 0 || decimals > 18) return null;
  const [whole = '0', fraction = ''] = value.split('.');
  const scaled = BigInt(whole) * 10n ** BigInt(decimals) +
    BigInt(fraction.slice(0, decimals).padEnd(decimals, '0') || '0');
  if (amountRaw === '0' && scaled !== 0n) return null;
  return decimalUnits(scaled, decimals);
}

function decimalUnits(amount: bigint, decimals: number): string {
  if (decimals === 0) return amount.toString();
  const text = amount.toString().padStart(decimals + 1, '0');
  const fraction = text.slice(-decimals).replace(/0+$/, '');
  return `${text.slice(0, -decimals)}${fraction ? `.${fraction}` : ''}`;
}

export function sumTokenDisplayAmounts(values: readonly (string | null | undefined)[], decimals: number): string | null {
  let total = 0n;
  for (const value of values) {
    const canonical = canonicalTokenDisplayAmount(value, decimals);
    if (canonical === null) return null;
    const [whole = '0', fraction = ''] = canonical.split('.');
    total += BigInt(whole) * 10n ** BigInt(decimals) + BigInt(fraction.padEnd(decimals, '0') || '0');
  }
  return decimalUnits(total, decimals);
}

function programTokenAccounts(result: unknown, owner: Address, tokenProgram: Address): Readonly<{
  context: unknown; byMint: ReadonlyMap<string, readonly unknown[]>;
}> {
  const response = plainRecord(result);
  contextSlot(response['context']);
  const values = response['value'];
  if (!Array.isArray(values) || values.length > MAX_TOKEN_ACCOUNTS) return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
  const seen = new Set<string>();
  const byMint = new Map<string, unknown[]>();
  for (const value of values) {
    const entry = plainRecord(value);
    const pubkey = responseAddress(entry['pubkey']);
    const account = plainRecord(entry['account']);
    const data = plainRecord(account['data']);
    const parsed = plainRecord(data['parsed']);
    const info = plainRecord(parsed['info']);
    const mint = responseAddress(info['mint']);
    if (seen.has(pubkey) || account['owner'] !== tokenProgram || account['executable'] !== false ||
        parsed['type'] !== 'account' || info['owner'] !== owner ||
        data['program'] !== (tokenProgram === STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy ? 'spl-token' : 'spl-token-2022')) {
      return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
    }
    seen.add(pubkey);
    const accounts = byMint.get(mint) ?? [];
    accounts.push(value);
    byMint.set(mint, accounts);
  }
  return {context: response['context'], byMint};
}

function nativeBalance(result: unknown): StockHoldingsSnapshot['balances']['nativeSol'] {
  const response = plainRecord(result);
  const slot = contextSlot(response['context']);
  const value = response['value'];
  // Solana returns lamports as a JSON number. Reject unsafe values instead of
  // silently rounding a u64 before converting it to a string.
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
  }
  return Object.freeze({
    kind: 'native', symbol: 'SOL', decimals: 9, amountRaw: String(value), amountUnits: 'lamports', observedSlot: slot,
  });
}

export interface StockHoldingsReaderOptions extends RpcClientOptions {
  readonly now?: () => number;
  readonly cacheTtlMs?: number;
  readonly rateLimitWindowMs?: number;
  readonly perUserLimit?: number;
  readonly globalLimit?: number;
  readonly maxTrackedUsers?: number;
  readonly maxCachedAddresses?: number;
  readonly maxConcurrentReads?: number;
}

export function readSolanaStockHoldingsReader(
  env: Readonly<Record<string, string | undefined>>,
  overrides: Readonly<Pick<StockHoldingsReaderOptions, 'fetch' | 'timeoutMs' | 'now' |
    'cacheTtlMs' | 'rateLimitWindowMs' | 'perUserLimit' | 'globalLimit' |
    'maxTrackedUsers' | 'maxCachedAddresses' | 'maxConcurrentReads'>> = {},
): SolanaStockHoldingsReader | undefined {
  const mode = env['TRIMMY_STOCK_HOLDINGS'];
  if (mode === undefined || mode === '' || mode === 'disabled') return undefined;
  const rpcUrl = env['SOLANA_MAINNET_RPC_URL'];
  if (mode !== 'solana_mainnet' || !rpcUrl) return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
  return new SolanaStockHoldingsReader({rpcUrl, ...overrides});
}

/** Mainnet-bound, read-only owner balance reader. It has no write RPC methods. */
export class SolanaStockHoldingsReader {
  readonly #rpc!: ReadOnlyHoldingsRpc;
  readonly #protectedRead!: BoundedProviderRead<StockHoldingsSnapshot>;

  constructor(options: StockHoldingsReaderOptions) {
    if (options === null || typeof options !== 'object' || Array.isArray(options) ||
        (options.now !== undefined && typeof options.now !== 'function')) {
      return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
    }
    this.#rpc = new ReadOnlyHoldingsRpc(options);
    this.#protectedRead = new BoundedProviderRead({
      now: options.now ?? Date.now,
      cacheTtlMs: options.cacheTtlMs ?? DEFAULT_CACHE_TTL_MS,
      rateLimitWindowMs: options.rateLimitWindowMs ?? DEFAULT_RATE_LIMIT_WINDOW_MS,
      perKeyLimit: options.perUserLimit ?? DEFAULT_PER_USER_LIMIT,
      globalLimit: options.globalLimit ?? DEFAULT_GLOBAL_LIMIT,
      maxTrackedKeys: options.maxTrackedUsers ?? DEFAULT_MAX_TRACKED_USERS,
      maxCacheEntries: options.maxCachedAddresses ?? DEFAULT_MAX_CACHED_ADDRESSES,
      maxConcurrentReads: options.maxConcurrentReads ?? DEFAULT_MAX_CONCURRENT_READS,
    }, {
      configurationInvalid: () => new StockHoldingsError('STOCK_HOLDINGS_CONFIGURATION_INVALID'),
      rateLimited: () => new StockHoldingsError('STOCK_HOLDINGS_RATE_LIMITED'),
    });
  }

  async #load(owner: ServerVerifiedStockOwner, observed: number, version: 1 | 2, minContextSlot?: number): Promise<StockHoldingsSnapshot> {
    const genesis = await this.#rpc.call('getGenesisHash', []);
    if (genesis !== STOCK_HOLDINGS_MAINNET_GENESIS) return fail('STOCK_HOLDINGS_WRONG_NETWORK');
    if (version === 2) return this.#loadPortfolio(owner, observed, minContextSlot);
    const freshness = minContextSlot === undefined ? {} : {minContextSlot};
    const [usdcAssociated, aaplxAssociated] = await Promise.all([
      associatedTokenAddress(owner.address, USDC), associatedTokenAddress(owner.address, AAPLX),
    ]);
    const [solResult, usdcResult, aaplxResult] = await Promise.all([
      this.#rpc.call('getBalance', [owner.address, {commitment: 'confirmed', ...freshness}]),
      this.#rpc.call('getTokenAccountsByOwner', [owner.address, {mint: USDC.mint},
        {encoding: 'jsonParsed', commitment: 'confirmed', ...freshness}]),
      this.#rpc.call('getTokenAccountsByOwner', [owner.address, {mint: AAPLX.mint},
        {encoding: 'jsonParsed', commitment: 'confirmed', ...freshness}]),
    ]);
    const nativeSol = nativeBalance(solResult);
    const usdc = tokenHolding(usdcResult, owner.address, USDC, usdcAssociated);
    const rawAaplx = tokenHolding(aaplxResult, owner.address, AAPLX, aaplxAssociated);
    const aaplx = Object.freeze({
      ...rawAaplx,
      displayResolution: 'token_2022_scaled_ui_unresolved' as const,
      displayAmount: null,
      shareAmount: null,
      eligibility: 'unverified' as const,
      executionEnabled: false as const,
    });
    const slots = Object.freeze({nativeSol: nativeSol.observedSlot, usdc: usdc.observedSlot, aaplx: aaplx.observedSlot});
    return Object.freeze({
      schemaVersion: 1,
      network: 'solana:mainnet-beta',
      genesisHash: STOCK_HOLDINGS_MAINNET_GENESIS,
      commitment: 'confirmed',
      owner: owner.address,
      ownerBinding: 'trusted_server_capability',
      observedAt: new Date(observed).toISOString(),
      readOnly: true,
      transactionBuilt: false,
      transactionSigned: false,
      transactionBroadcast: false,
      balances: Object.freeze({nativeSol, usdc, aaplx}),
      consistency: Object.freeze({kind: 'independent_confirmed_reads', atomic: false, slots}),
    });
  }

  async #loadPortfolio(owner: ServerVerifiedStockOwner, observed: number, minContextSlot?: number): Promise<StockHoldingsSnapshot> {
    const freshness = minContextSlot === undefined ? {} : {minContextSlot};
    const [solResult, legacyResult, token2022Result] = await Promise.all([
      this.#rpc.call('getBalance', [owner.address, {commitment: 'confirmed', ...freshness}]),
      this.#rpc.call('getTokenAccountsByOwner', [owner.address, {programId: STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy},
        {encoding: 'jsonParsed', commitment: 'confirmed', ...freshness}]),
      this.#rpc.call('getTokenAccountsByOwner', [owner.address, {programId: STOCK_HOLDINGS_TOKEN_PROGRAMS.token2022},
        {encoding: 'jsonParsed', commitment: 'confirmed', ...freshness}]),
    ]);
    const nativeSol = nativeBalance(solResult);
    const legacy = programTokenAccounts(legacyResult, owner.address, address(STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy));
    const token2022 = programTokenAccounts(token2022Result, owner.address, address(STOCK_HOLDINGS_TOKEN_PROGRAMS.token2022));
    const usdc = tokenHolding({context: legacy.context, value: legacy.byMint.get(USDC.mint) ?? []},
      owner.address, USDC, await associatedTokenAddress(owner.address, USDC));
    const allStocks = await Promise.all(STOCK_TRADING_ASSETS.map(async asset => {
      const token: TokenDefinition = {
        symbol: asset.symbol, mint: address(asset.mint), decimals: asset.decimals,
        tokenProgram: address(asset.tokenProgramAddress),
        parsedProgram: asset.tokenProgram === 'token_2022' ? 'spl-token-2022' : 'spl-token',
      };
      const program = asset.tokenProgram === 'token_2022' ? token2022 : legacy;
      const holding = tokenHolding({context: program.context, value: program.byMint.get(asset.mint) ?? []},
        owner.address, token, await associatedTokenAddress(owner.address, token), true);
      const displayAmount = sumTokenDisplayAmounts(holding.accounts.map(account => account.displayAmount), asset.decimals);
      return Object.freeze({...holding, assetId: asset.assetId, name: asset.name, displayAmount,
        displayResolution: displayAmount === null ? 'unavailable' as const : 'rpc_ui_amount' as const,
        displayUnits: 'token_units' as const});
    }));
    const rawAaplx = allStocks.find(token => token.mint === AAPLX.mint);
    if (!rawAaplx) return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
    // Keep the exact legacy alias contract. New consumers use tokens, not its
    // historical execution/display flags, which are not trading capability data.
    const aaplx = Object.freeze({...rawAaplx,
      displayResolution: 'token_2022_scaled_ui_unresolved' as const, displayAmount: null, shareAmount: null,
      eligibility: 'unverified' as const, executionEnabled: false as const});
    const tokens = Object.freeze(allStocks.filter(token => token.amountRaw !== '0'));
    return Object.freeze({
      schemaVersion: 1, network: 'solana:mainnet-beta', genesisHash: STOCK_HOLDINGS_MAINNET_GENESIS,
      commitment: 'confirmed', owner: owner.address, ownerBinding: 'trusted_server_capability',
      observedAt: new Date(observed).toISOString(), readOnly: true,
      transactionBuilt: false, transactionSigned: false, transactionBroadcast: false,
      balances: Object.freeze({nativeSol, usdc, aaplx, tokens}),
      consistency: Object.freeze({kind: 'independent_confirmed_reads', atomic: false,
        slots: Object.freeze({nativeSol: nativeSol.observedSlot, usdc: usdc.observedSlot, aaplx: aaplx.observedSlot})}),
    });
  }

  async read(owner: ServerVerifiedStockOwner, version: 1 | 2 = 1, minContextSlot?: number): Promise<StockHoldingsSnapshot> {
    if (owner === null || typeof owner !== 'object' || !verifiedOwners.has(owner)) {
      return fail('STOCK_HOLDINGS_OWNER_UNVERIFIED');
    }
    if (version !== 1 && version !== 2) return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
    if (minContextSlot !== undefined && (!Number.isSafeInteger(minContextSlot) || minContextSlot < 1)) {
      return fail('STOCK_HOLDINGS_CONFIGURATION_INVALID');
    }
    // A confirmed trade supplies its observed slot. Neither the pre-trade cache
    // nor an older in-flight request may satisfy this stricter read. It still
    // shares the same account/global rate budget and bounded cache capacity.
    const freshnessKey = minContextSlot === undefined ? '' : `:after:${minContextSlot}`;
    return this.#protectedRead.read(`${owner.address}:${version}${freshnessKey}`, owner.authenticatedUserId,
      async observed => {
        const snapshot = await this.#load(owner, observed, version, minContextSlot);
        if (minContextSlot !== undefined && Object.values(snapshot.consistency.slots).some(slot => slot < minContextSlot)) {
          return fail('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
        }
        return snapshot;
      });
  }
}
