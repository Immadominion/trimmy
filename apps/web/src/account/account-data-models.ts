export const ACCOUNT_DATA_MAINNET_GENESIS = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
export const ACCOUNT_DATA_USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
export const ACCOUNT_DATA_AAPLX_MINT = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';

export type AccountDataErrorCode =
  | 'ACCOUNT_DATA_INVALID_CONFIGURATION'
  | 'ACCOUNT_DATA_TOKEN_UNAVAILABLE'
  | 'ACCOUNT_DATA_ACCOUNT_CHANGED'
  | 'ACCOUNT_DATA_CANCELLED'
  | 'ACCOUNT_DATA_CLOSED'
  | 'ACCOUNT_DATA_TIMEOUT'
  | 'ACCOUNT_DATA_REDIRECT_REJECTED'
  | 'ACCOUNT_DATA_RESPONSE_TOO_LARGE'
  | 'ACCOUNT_DATA_RESPONSE_INVALID'
  | 'ACCOUNT_DATA_NETWORK_ERROR'
  | 'ACCOUNT_CONTEXT_INVALID_REQUEST'
  | 'ACCOUNT_CONTEXT_UNAUTHENTICATED'
  | 'ACCOUNT_CONTEXT_UNAVAILABLE'
  | 'ACCOUNT_HOLDINGS_INVALID_REQUEST'
  | 'ACCOUNT_HOLDINGS_UNAUTHENTICATED'
  | 'ACCOUNT_HOLDINGS_UNAVAILABLE'
  | 'ACCOUNT_HOLDINGS_WALLET_MISSING'
  | 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS'
  | 'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED'
  | 'PRIVY_VERIFIED_IDENTITY_INVALID'
  | 'PRIVY_USER_RESPONSE_INVALID'
  | 'PRIVY_USER_UNAVAILABLE'
  | 'PRIVY_USER_TIMEOUT'
  | 'PRIVY_USER_RATE_LIMITED'
  | 'STOCK_HOLDINGS_OWNER_INVALID'
  | 'STOCK_HOLDINGS_OWNER_UNVERIFIED'
  | 'STOCK_HOLDINGS_CONFIGURATION_INVALID'
  | 'STOCK_HOLDINGS_RPC_UNAVAILABLE'
  | 'STOCK_HOLDINGS_RPC_TIMEOUT'
  | 'STOCK_HOLDINGS_RPC_RESPONSE_INVALID'
  | 'STOCK_HOLDINGS_WRONG_NETWORK'
  | 'STOCK_HOLDINGS_RATE_LIMITED'
  | 'BROWSER_ORIGIN_DENIED'
  | 'BROWSER_PREFLIGHT_DENIED'
  | 'INVALID_REQUEST'
  | 'NOT_FOUND'
  | 'PAYLOAD_TOO_LARGE'
  | 'UNSUPPORTED_MEDIA_TYPE'
  | 'INTERNAL_ERROR';

/** Carries a fixed local/API code only; response bodies and provider details are discarded. */
export class AccountDataError extends Error {
  constructor(readonly code: AccountDataErrorCode) {
    super(code);
    this.name = 'AccountDataError';
  }
}

export type AccountXIdentity =
  | Readonly<{status: 'missing' | 'ambiguous'}>
  | Readonly<{status: 'verified'; subject: string; usernameSnapshot: string; verifiedAtUnixSeconds: number}>;

export type EmbeddedSolanaWallet =
  | Readonly<{status: 'missing' | 'ambiguous'}>
  | Readonly<{status: 'candidate'; address: string; verifiedAtUnixSeconds: number}>;

export interface AccountContextSnapshot {
  readonly schemaVersion: 1;
  readonly userId: string;
  readonly xIdentity: AccountXIdentity;
  readonly embeddedSolanaWallet: EmbeddedSolanaWallet;
}

export type TokenAccountTopology =
  | 'none'
  | 'associated_only'
  | 'associated_with_ancillary'
  | 'ancillary_only'
  | 'multiple_ancillary';

export interface AccountNativeSolBalance {
  readonly symbol: 'SOL';
  readonly decimals: 9;
  readonly amountRaw: string;
  readonly amountUnits: 'lamports';
  readonly observedSlot: number;
}

export interface AccountTokenBalance {
  readonly symbol: 'USDC' | 'AAPLx';
  readonly mint: string;
  readonly decimals: 6 | 8;
  readonly amountRaw: string;
  readonly amountUnits: 'raw_token_units';
  readonly observedSlot: number;
  readonly accountCount: number;
  readonly accountTopology: TokenAccountTopology;
  readonly aggregation: 'all_valid_owner_token_accounts';
  readonly hasFrozenAccounts: boolean;
}

export interface AccountAaplxBalance extends AccountTokenBalance {
  readonly symbol: 'AAPLx';
  readonly decimals: 8;
  readonly displayResolution: 'token_2022_scaled_ui_unresolved';
  readonly displayAmount: null;
  readonly shareAmount: null;
  readonly eligibility: 'unverified';
  readonly executionEnabled: false;
}

export interface AccountHoldingsSnapshot {
  readonly schemaVersion: 1;
  readonly userId: string;
  readonly wallet: Readonly<{
    address: string;
    source: 'privy_embedded_wallet_same_subject';
    possessionSignatureVerified: false;
  }>;
  readonly holdings: Readonly<{
    network: 'solana:mainnet-beta';
    genesisHash: typeof ACCOUNT_DATA_MAINNET_GENESIS;
    commitment: 'confirmed';
    observedAt: string;
    readOnly: true;
    transactionBuilt: false;
    transactionSigned: false;
    transactionBroadcast: false;
    balances: Readonly<{
      nativeSol: AccountNativeSolBalance;
      usdc: AccountTokenBalance & Readonly<{symbol: 'USDC'; decimals: 6}>;
      aaplx: AccountAaplxBalance;
    }>;
    consistency: Readonly<{
      kind: 'independent_confirmed_reads';
      atomic: false;
      slots: Readonly<{nativeSol: number; usdc: number; aaplx: number}>;
    }>;
  }>;
}

const MAX_U64 = 18_446_744_073_709_551_615n;
const MAX_SAFE_INTEGER_BIGINT = BigInt(Number.MAX_SAFE_INTEGER);

function invalid(): never { throw new AccountDataError('ACCOUNT_DATA_RESPONSE_INVALID'); }

function object(value: unknown, fields: readonly string[]): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) invalid();
  const keys = Reflect.ownKeys(value);
  if (keys.length !== fields.length || keys.some(key => typeof key !== 'string' || !fields.includes(key))) invalid();
  const copy: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  for (const field of fields) {
    const descriptor = Object.getOwnPropertyDescriptor(value, field);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    copy[field] = descriptor.value;
  }
  return copy;
}

export function canonicalAccountId(value: unknown): string {
  if (typeof value !== 'string' ||
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.exec(value)?.[0] !== value) invalid();
  return value;
}

function rawUnsigned(value: unknown, maximum = MAX_U64): string {
  if (typeof value !== 'string' || /^(?:0|[1-9][0-9]{0,19})$/u.exec(value)?.[0] !== value) invalid();
  try { if (BigInt(value) > maximum) invalid(); } catch { invalid(); }
  return value;
}

function safeInteger(value: unknown, positive = false): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < (positive ? 1 : 0)) invalid();
  return value;
}

function canonicalTimestamp(value: unknown): string {
  if (typeof value !== 'string' ||
      /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/u.exec(value)?.[0] !== value) invalid();
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed) || new Date(parsed).toISOString() !== value) invalid();
  return value;
}

/** A canonical, nonzero 32-byte base58 Solana public key. */
export function solanaAddress(value: unknown): string {
  if (typeof value !== 'string' || value.length < 32 || value.length > 44) invalid();
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  let number = 0n;
  let leadingZeroes = 0;
  for (let index = 0; index < value.length; index++) {
    const digit = alphabet.indexOf(value[index]!);
    if (digit < 0) invalid();
    number = number * 58n + BigInt(digit);
    if (index === leadingZeroes && digit === 0) leadingZeroes++;
  }
  let decodedBytes = 0;
  const nonzero = number;
  while (number > 0n) { decodedBytes++; number >>= 8n; }
  if (decodedBytes + leadingZeroes !== 32 || nonzero === 0n) invalid();
  return value;
}

function xIdentity(value: unknown): AccountXIdentity {
  const possible = value !== null && typeof value === 'object' && !Array.isArray(value)
    ? Object.getOwnPropertyDescriptor(value, 'status')?.value : undefined;
  if (possible === 'missing' || possible === 'ambiguous') {
    object(value, ['status']);
    return Object.freeze({status: possible});
  }
  const data = object(value, ['status', 'subject', 'usernameSnapshot', 'verifiedAtUnixSeconds']);
  const subject = rawUnsigned(data['subject']);
  if (data['status'] !== 'verified' || subject === '0' || typeof data['usernameSnapshot'] !== 'string' ||
      /^[a-z0-9_]{1,15}$/u.exec(data['usernameSnapshot'])?.[0] !== data['usernameSnapshot']) invalid();
  return Object.freeze({status: 'verified', subject, usernameSnapshot: data['usernameSnapshot'],
    verifiedAtUnixSeconds: safeInteger(data['verifiedAtUnixSeconds'], true)});
}

function embeddedWallet(value: unknown): EmbeddedSolanaWallet {
  const possible = value !== null && typeof value === 'object' && !Array.isArray(value)
    ? Object.getOwnPropertyDescriptor(value, 'status')?.value : undefined;
  if (possible === 'missing' || possible === 'ambiguous') {
    object(value, ['status']);
    return Object.freeze({status: possible});
  }
  const data = object(value, ['status', 'address', 'verifiedAtUnixSeconds']);
  if (data['status'] !== 'candidate') invalid();
  return Object.freeze({status: 'candidate', address: solanaAddress(data['address']),
    verifiedAtUnixSeconds: safeInteger(data['verifiedAtUnixSeconds'], true)});
}

export function parseAccountContext(value: unknown, expectedUserId?: string): AccountContextSnapshot {
  const data = object(value, ['schemaVersion', 'userId', 'xIdentity', 'embeddedSolanaWallet']);
  if (data['schemaVersion'] !== 1) invalid();
  const userId = canonicalAccountId(data['userId']);
  if (expectedUserId !== undefined && userId !== canonicalAccountId(expectedUserId)) {
    throw new AccountDataError('ACCOUNT_DATA_ACCOUNT_CHANGED');
  }
  return Object.freeze({schemaVersion: 1, userId, xIdentity: xIdentity(data['xIdentity']),
    embeddedSolanaWallet: embeddedWallet(data['embeddedSolanaWallet'])});
}

function topology(value: unknown, count: number): TokenAccountTopology {
  if (typeof value !== 'string' || !['none', 'associated_only', 'associated_with_ancillary',
    'ancillary_only', 'multiple_ancillary'].includes(value)) invalid();
  if (value === 'none' && count !== 0 ||
      (value === 'associated_only' || value === 'ancillary_only') && count !== 1 ||
      (value === 'associated_with_ancillary' || value === 'multiple_ancillary') && count < 2) invalid();
  return value as TokenAccountTopology;
}

function nativeSol(value: unknown): AccountNativeSolBalance {
  const data = object(value, ['symbol', 'decimals', 'amountRaw', 'amountUnits', 'observedSlot']);
  if (data['symbol'] !== 'SOL' || data['decimals'] !== 9 || data['amountUnits'] !== 'lamports') invalid();
  return Object.freeze({symbol: 'SOL', decimals: 9, amountRaw: rawUnsigned(data['amountRaw'], MAX_SAFE_INTEGER_BIGINT),
    amountUnits: 'lamports', observedSlot: safeInteger(data['observedSlot'])});
}

function tokenBalance(value: unknown, expected: Readonly<{symbol: 'USDC' | 'AAPLx'; mint: string; decimals: 6 | 8}>,
  aaplx: boolean): AccountTokenBalance | AccountAaplxBalance {
  const base = ['symbol', 'mint', 'decimals', 'amountRaw', 'amountUnits', 'observedSlot', 'accountCount',
    'accountTopology', 'aggregation', 'hasFrozenAccounts'];
  const data = object(value, aaplx ? [...base, 'displayResolution', 'displayAmount', 'shareAmount',
    'eligibility', 'executionEnabled'] : base);
  if (data['symbol'] !== expected.symbol || data['mint'] !== expected.mint || data['decimals'] !== expected.decimals ||
      data['amountUnits'] !== 'raw_token_units' || data['aggregation'] !== 'all_valid_owner_token_accounts' ||
      typeof data['hasFrozenAccounts'] !== 'boolean') invalid();
  const amountRaw = rawUnsigned(data['amountRaw']);
  const accountCount = safeInteger(data['accountCount']);
  if (accountCount > 128 || accountCount === 0 && (amountRaw !== '0' || data['hasFrozenAccounts'] !== false)) invalid();
  const common = {symbol: expected.symbol, mint: expected.mint, decimals: expected.decimals, amountRaw,
    amountUnits: 'raw_token_units' as const, observedSlot: safeInteger(data['observedSlot']), accountCount,
    accountTopology: topology(data['accountTopology'], accountCount), aggregation: 'all_valid_owner_token_accounts' as const,
    hasFrozenAccounts: data['hasFrozenAccounts']};
  if (!aaplx) return Object.freeze(common) as AccountTokenBalance;
  if (data['displayResolution'] !== 'token_2022_scaled_ui_unresolved' || data['displayAmount'] !== null ||
      data['shareAmount'] !== null || data['eligibility'] !== 'unverified' || data['executionEnabled'] !== false) invalid();
  return Object.freeze({...common, symbol: 'AAPLx', decimals: 8, displayResolution: 'token_2022_scaled_ui_unresolved',
    displayAmount: null, shareAmount: null, eligibility: 'unverified', executionEnabled: false}) as AccountAaplxBalance;
}

export function parseAccountHoldings(value: unknown, expectedUserId: string): AccountHoldingsSnapshot {
  const envelope = object(value, ['schemaVersion', 'userId', 'wallet', 'holdings']);
  if (envelope['schemaVersion'] !== 1) invalid();
  const userId = canonicalAccountId(envelope['userId']);
  if (userId !== canonicalAccountId(expectedUserId)) throw new AccountDataError('ACCOUNT_DATA_ACCOUNT_CHANGED');
  const walletData = object(envelope['wallet'], ['address', 'source', 'possessionSignatureVerified']);
  if (walletData['source'] !== 'privy_embedded_wallet_same_subject' || walletData['possessionSignatureVerified'] !== false) invalid();
  const wallet = Object.freeze({address: solanaAddress(walletData['address']),
    source: 'privy_embedded_wallet_same_subject' as const, possessionSignatureVerified: false as const});
  const data = object(envelope['holdings'], ['network', 'genesisHash', 'commitment', 'observedAt', 'readOnly',
    'transactionBuilt', 'transactionSigned', 'transactionBroadcast', 'balances', 'consistency']);
  if (data['network'] !== 'solana:mainnet-beta' || data['genesisHash'] !== ACCOUNT_DATA_MAINNET_GENESIS ||
      data['commitment'] !== 'confirmed' || data['readOnly'] !== true || data['transactionBuilt'] !== false ||
      data['transactionSigned'] !== false || data['transactionBroadcast'] !== false) invalid();
  const balancesData = object(data['balances'], ['nativeSol', 'usdc', 'aaplx']);
  const sol = nativeSol(balancesData['nativeSol']);
  const usdc = tokenBalance(balancesData['usdc'], {symbol: 'USDC', mint: ACCOUNT_DATA_USDC_MINT, decimals: 6}, false) as
    AccountTokenBalance & Readonly<{symbol: 'USDC'; decimals: 6}>;
  const aaplx = tokenBalance(balancesData['aaplx'], {symbol: 'AAPLx', mint: ACCOUNT_DATA_AAPLX_MINT, decimals: 8}, true) as AccountAaplxBalance;
  const consistencyData = object(data['consistency'], ['kind', 'atomic', 'slots']);
  const slotsData = object(consistencyData['slots'], ['nativeSol', 'usdc', 'aaplx']);
  if (consistencyData['kind'] !== 'independent_confirmed_reads' || consistencyData['atomic'] !== false) invalid();
  const slots = Object.freeze({nativeSol: safeInteger(slotsData['nativeSol']), usdc: safeInteger(slotsData['usdc']),
    aaplx: safeInteger(slotsData['aaplx'])});
  if (slots.nativeSol !== sol.observedSlot || slots.usdc !== usdc.observedSlot || slots.aaplx !== aaplx.observedSlot) invalid();
  const holdings = Object.freeze({network: 'solana:mainnet-beta' as const, genesisHash: ACCOUNT_DATA_MAINNET_GENESIS,
    commitment: 'confirmed' as const, observedAt: canonicalTimestamp(data['observedAt']), readOnly: true as const,
    transactionBuilt: false as const, transactionSigned: false as const, transactionBroadcast: false as const,
    balances: Object.freeze({nativeSol: sol, usdc, aaplx}), consistency: Object.freeze({
      kind: 'independent_confirmed_reads' as const, atomic: false as const, slots,
    })});
  return Object.freeze({schemaVersion: 1, userId, wallet, holdings});
}
