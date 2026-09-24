import {address, getAddressEncoder, isOffCurveAddress} from '@solana/kit';
import type {FastifyInstance, FastifyReply, FastifyRequest} from 'fastify';
import {JUPITER_QUOTE_ASSETS} from './jupiter-quote-reader.js';
import {parsePracticeIdentity} from './practice-identity.js';
import type {PracticeIdentity} from './practice-identity.js';
import {parsePracticeUserId} from './practice-repository.js';
import {PracticeAuthenticationUnavailable} from './practice-session-routes.js';
import type {ExistingPracticeAccountAuthentication} from './practice-session-routes.js';
import {
  PrivyLinkedIdentityError,
} from './privy-linked-identities.js';
import type {
  PrivyLinkedIdentityErrorCode,
  PrivyLinkedIdentityResolution,
} from './privy-linked-identities.js';
import {
  admitServerVerifiedStockOwner,
  STOCK_HOLDINGS_MAINNET_GENESIS,
  STOCK_HOLDINGS_TOKEN_PROGRAMS,
  StockHoldingsError,
} from './stock-holdings.js';
import type {
  ServerVerifiedStockOwner,
  StockHoldingsErrorCode,
  StockHoldingsSnapshot,
  StockTokenAccountTopology,
} from './stock-holdings.js';

export const ACCOUNT_HOLDINGS_ROUTE = '/v1/account/holdings';

export interface AccountHoldingsIdentityResolver {
  resolve(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution>;
}

export interface AccountHoldingsReader {
  read(owner: ServerVerifiedStockOwner): Promise<StockHoldingsSnapshot>;
}

export interface AccountHoldingsAdapters {
  /** Verifier plus existing-account lookup only; this must never provision. */
  readonly authenticate: (request: FastifyRequest) =>
    Promise<ExistingPracticeAccountAuthentication | null>;
  readonly linkedIdentities: AccountHoldingsIdentityResolver;
  readonly holdings: AccountHoldingsReader;
}

export function accountHoldingsEnabled(value?: AccountHoldingsAdapters): value is AccountHoldingsAdapters {
  return typeof value?.authenticate === 'function' &&
    typeof value.linkedIdentities?.resolve === 'function' &&
    typeof value.holdings?.read === 'function';
}

export interface AccountHoldingsTokenBalance {
  readonly symbol: 'USDC' | 'AAPLx';
  readonly mint: string;
  readonly decimals: 6 | 8;
  readonly amountRaw: string;
  readonly amountUnits: 'raw_token_units';
  readonly observedSlot: number;
  readonly accountCount: number;
  readonly accountTopology: StockTokenAccountTopology;
  readonly aggregation: 'all_valid_owner_token_accounts';
  readonly hasFrozenAccounts: boolean;
}

export interface AccountHoldingsResponse {
  readonly schemaVersion: 1;
  readonly userId: string;
  readonly wallet: Readonly<{
    address: string;
    source: 'privy_embedded_wallet_same_subject';
    /** No separate wallet-signature possession proof is performed by this GET. */
    possessionSignatureVerified: false;
  }>;
  readonly holdings: Readonly<{
    network: 'solana:mainnet-beta';
    genesisHash: typeof STOCK_HOLDINGS_MAINNET_GENESIS;
    commitment: 'confirmed';
    observedAt: string;
    readOnly: true;
    transactionBuilt: false;
    transactionSigned: false;
    transactionBroadcast: false;
    balances: Readonly<{
      nativeSol: Readonly<{
        symbol: 'SOL';
        decimals: 9;
        amountRaw: string;
        amountUnits: 'lamports';
        observedSlot: number;
      }>;
      usdc: AccountHoldingsTokenBalance & Readonly<{symbol: 'USDC'; decimals: 6}>;
      aaplx: AccountHoldingsTokenBalance & Readonly<{
        symbol: 'AAPLx';
        decimals: 8;
        displayResolution: 'token_2022_scaled_ui_unresolved';
        displayAmount: null;
        shareAmount: null;
        eligibility: 'unverified';
        executionEnabled: false;
      }>;
    }>;
    consistency: Readonly<{
      kind: 'independent_confirmed_reads';
      atomic: false;
      slots: Readonly<{nativeSol: number; usdc: number; aaplx: number}>;
    }>;
  }>;
}

const rawAmountSchema = {type: 'string', pattern: '^(?:0|[1-9][0-9]{0,19})$', maxLength: 20} as const;
const slotSchema = {type: 'integer', minimum: 0} as const;
const topologySchema = {type: 'string', enum: [
  'none', 'associated_only', 'associated_with_ancillary', 'ancillary_only', 'multiple_ancillary',
]} as const;
const tokenProperties = {
  mint: {type: 'string'}, amountRaw: rawAmountSchema, amountUnits: {const: 'raw_token_units'},
  observedSlot: slotSchema, accountCount: {type: 'integer', minimum: 0, maximum: 128},
  accountTopology: topologySchema, aggregation: {const: 'all_valid_owner_token_accounts'},
  hasFrozenAccounts: {type: 'boolean'},
} as const;
const responseSchema = {
  type: 'object', additionalProperties: false, required: ['schemaVersion', 'userId', 'wallet', 'holdings'],
  properties: {
    schemaVersion: {const: 1}, userId: {type: 'string'},
    wallet: {type: 'object', additionalProperties: false,
      required: ['address', 'source', 'possessionSignatureVerified'], properties: {
        address: {type: 'string'}, source: {const: 'privy_embedded_wallet_same_subject'},
        possessionSignatureVerified: {const: false},
      }},
    holdings: {type: 'object', additionalProperties: false,
      required: ['network', 'genesisHash', 'commitment', 'observedAt', 'readOnly', 'transactionBuilt',
        'transactionSigned', 'transactionBroadcast', 'balances', 'consistency'], properties: {
        network: {const: 'solana:mainnet-beta'}, genesisHash: {const: STOCK_HOLDINGS_MAINNET_GENESIS},
        commitment: {const: 'confirmed'}, observedAt: {type: 'string'}, readOnly: {const: true},
        transactionBuilt: {const: false}, transactionSigned: {const: false}, transactionBroadcast: {const: false},
        balances: {type: 'object', additionalProperties: false, required: ['nativeSol', 'usdc', 'aaplx'],
          properties: {
            nativeSol: {type: 'object', additionalProperties: false,
              required: ['symbol', 'decimals', 'amountRaw', 'amountUnits', 'observedSlot'], properties: {
                symbol: {const: 'SOL'}, decimals: {const: 9}, amountRaw: rawAmountSchema,
                amountUnits: {const: 'lamports'}, observedSlot: slotSchema,
              }},
            usdc: {type: 'object', additionalProperties: false,
              required: ['symbol', 'mint', 'decimals', 'amountRaw', 'amountUnits', 'observedSlot',
                'accountCount', 'accountTopology', 'aggregation', 'hasFrozenAccounts'], properties: {
                symbol: {const: 'USDC'}, decimals: {const: 6}, ...tokenProperties,
              }},
            aaplx: {type: 'object', additionalProperties: false,
              required: ['symbol', 'mint', 'decimals', 'amountRaw', 'amountUnits', 'observedSlot',
                'accountCount', 'accountTopology', 'aggregation', 'hasFrozenAccounts', 'displayResolution',
                'displayAmount', 'shareAmount', 'eligibility', 'executionEnabled'], properties: {
                symbol: {const: 'AAPLx'}, decimals: {const: 8}, ...tokenProperties,
                displayResolution: {const: 'token_2022_scaled_ui_unresolved'}, displayAmount: {type: 'null'},
                shareAmount: {type: 'null'}, eligibility: {const: 'unverified'}, executionEnabled: {const: false},
              }},
          }},
        consistency: {type: 'object', additionalProperties: false, required: ['kind', 'atomic', 'slots'], properties: {
          kind: {const: 'independent_confirmed_reads'}, atomic: {const: false},
          slots: {type: 'object', additionalProperties: false, required: ['nativeSol', 'usdc', 'aaplx'],
            properties: {nativeSol: slotSchema, usdc: slotSchema, aaplx: slotSchema}},
        }},
      }},
  },
} as const;

class AccountHoldingsWalletStateError extends Error {
  constructor(readonly code: 'ACCOUNT_HOLDINGS_WALLET_MISSING' | 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS') {
    super(code === 'ACCOUNT_HOLDINGS_WALLET_MISSING'
      ? 'Connect one embedded Solana wallet to view holdings.'
      : 'Holdings are unavailable while more than one embedded Solana wallet is linked.');
    this.name = 'AccountHoldingsWalletStateError';
  }
}

function ownData(record: Record<string, unknown>, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(record, key);
  return descriptor?.enumerable && Object.hasOwn(descriptor, 'value') ? descriptor.value : undefined;
}

function plainRecord(value: unknown): Record<string, unknown> | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const prototype: unknown = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null ? value as Record<string, unknown> : undefined;
}

function validOwnerAddress(value: unknown): value is string {
  if (typeof value !== 'string' || value.length < 32 || value.length > 44) return false;
  try {
    const parsed = address(value);
    return parsed === value && !isOffCurveAddress(parsed) &&
      !getAddressEncoder().encode(parsed).every(byte => byte === 0);
  } catch { return false; }
}

function validAddress(value: unknown): value is string {
  if (typeof value !== 'string' || value.length < 32 || value.length > 44) return false;
  try { return address(value) === value; } catch { return false; }
}

function positiveUnixSeconds(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;
}

function linkedWallet(value: unknown, expectedSubject: string): string {
  const resolution = plainRecord(value);
  if (!resolution || ownData(resolution, 'provider') !== 'privy' ||
      ownData(resolution, 'subject') !== expectedSubject) {
    throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID');
  }
  const wallet = plainRecord(ownData(resolution, 'embeddedSolanaWallet'));
  const status = wallet && ownData(wallet, 'status');
  if (status === 'missing') throw new AccountHoldingsWalletStateError('ACCOUNT_HOLDINGS_WALLET_MISSING');
  if (status === 'ambiguous') throw new AccountHoldingsWalletStateError('ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS');
  const walletAddress = wallet && ownData(wallet, 'address');
  if (status !== 'candidate' || !validOwnerAddress(walletAddress) ||
      !positiveUnixSeconds(wallet && ownData(wallet, 'verifiedAtUnixSeconds'))) {
    throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID');
  }
  return walletAddress;
}

function rawU64(value: unknown): string | undefined {
  if (typeof value !== 'string' || /^(?:0|[1-9][0-9]{0,19})$/.exec(value)?.[0] !== value) return undefined;
  try { return BigInt(value) <= (1n << 64n) - 1n ? value : undefined; } catch { return undefined; }
}

function slot(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? value : undefined;
}

function canonicalDate(value: unknown): string | undefined {
  if (typeof value !== 'string' || value.length < 20 || value.length > 24 ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)) return undefined;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && new Date(parsed).toISOString() === value ? value : undefined;
}

function responseInvalid(): never {
  throw new StockHoldingsError('STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
}

function projectNativeBalance(value: unknown): AccountHoldingsResponse['holdings']['balances']['nativeSol'] {
  const balance = plainRecord(value);
  const amountRaw = balance && rawU64(ownData(balance, 'amountRaw'));
  const observedSlot = balance && slot(ownData(balance, 'observedSlot'));
  if (!balance || ownData(balance, 'kind') !== 'native' || ownData(balance, 'symbol') !== 'SOL' ||
      ownData(balance, 'decimals') !== 9 || ownData(balance, 'amountUnits') !== 'lamports' ||
      amountRaw === undefined || BigInt(amountRaw) > BigInt(Number.MAX_SAFE_INTEGER) || observedSlot === undefined) {
    return responseInvalid();
  }
  return Object.freeze({symbol: 'SOL', decimals: 9, amountRaw, amountUnits: 'lamports', observedSlot});
}

interface TokenProjectionExpectation {
  readonly symbol: 'USDC' | 'AAPLx';
  readonly mint: string;
  readonly decimals: 6 | 8;
  readonly tokenProgram: string;
}

function derivedTopology(accountCount: number, associatedCount: number): StockTokenAccountTopology {
  if (accountCount === 0) return 'none';
  if (associatedCount === 1 && accountCount === 1) return 'associated_only';
  if (associatedCount === 1) return 'associated_with_ancillary';
  return accountCount === 1 ? 'ancillary_only' : 'multiple_ancillary';
}

function projectTokenBalance(value: unknown, expected: TokenProjectionExpectation): AccountHoldingsTokenBalance {
  const balance = plainRecord(value);
  if (!balance || ownData(balance, 'kind') !== 'spl_token' || ownData(balance, 'symbol') !== expected.symbol ||
      ownData(balance, 'mint') !== expected.mint || ownData(balance, 'tokenProgram') !== expected.tokenProgram ||
      ownData(balance, 'decimals') !== expected.decimals || ownData(balance, 'amountUnits') !== 'raw_token_units' ||
      ownData(balance, 'aggregation') !== 'all_valid_owner_token_accounts') return responseInvalid();
  const amountRaw = rawU64(ownData(balance, 'amountRaw'));
  const observedSlot = slot(ownData(balance, 'observedSlot'));
  const accounts = ownData(balance, 'accounts');
  const associated = plainRecord(ownData(balance, 'associatedTokenAccount'));
  const associatedAddress = associated && ownData(associated, 'address');
  const associatedStatus = associated && ownData(associated, 'status');
  if (amountRaw === undefined || observedSlot === undefined || !Array.isArray(accounts) || accounts.length > 128 ||
      !validAddress(associatedAddress) || (associatedStatus !== 'present' && associatedStatus !== 'absent')) {
    return responseInvalid();
  }
  let sum = 0n;
  let associatedCount = 0;
  let frozenCount = 0;
  let previousAddress = '';
  const seen = new Set<string>();
  for (const item of accounts) {
    const account = plainRecord(item);
    const accountAddress = account && ownData(account, 'address');
    const accountRaw = account && rawU64(ownData(account, 'amountRaw'));
    const state = account && ownData(account, 'state');
    const isAssociated = account && ownData(account, 'associated');
    if (!account || !validAddress(accountAddress) || accountRaw === undefined ||
        (state !== 'initialized' && state !== 'frozen') || typeof isAssociated !== 'boolean' ||
        seen.has(accountAddress) || previousAddress && previousAddress.localeCompare(accountAddress) >= 0 ||
        isAssociated && accountAddress !== associatedAddress) return responseInvalid();
    seen.add(accountAddress);
    previousAddress = accountAddress;
    sum += BigInt(accountRaw);
    if (sum > (1n << 64n) - 1n) return responseInvalid();
    if (isAssociated) associatedCount += 1;
    if (state === 'frozen') frozenCount += 1;
  }
  const topology = derivedTopology(accounts.length, associatedCount);
  if (sum.toString() !== amountRaw || associatedCount > 1 ||
      (associatedStatus === 'present') !== (associatedCount === 1) ||
      ownData(balance, 'accountTopology') !== topology ||
      ownData(balance, 'hasFrozenAccounts') !== (frozenCount > 0)) return responseInvalid();
  return Object.freeze({
    symbol: expected.symbol, mint: expected.mint, decimals: expected.decimals,
    amountRaw, amountUnits: 'raw_token_units', observedSlot, accountCount: accounts.length,
    accountTopology: topology, aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: frozenCount > 0,
  });
}

function projectSnapshot(value: unknown, expectedOwner: string): AccountHoldingsResponse['holdings'] {
  const snapshot = plainRecord(value);
  const observedAt = snapshot && canonicalDate(ownData(snapshot, 'observedAt'));
  const balances = snapshot && plainRecord(ownData(snapshot, 'balances'));
  const consistency = snapshot && plainRecord(ownData(snapshot, 'consistency'));
  const consistencySlots = consistency && plainRecord(ownData(consistency, 'slots'));
  if (!snapshot || ownData(snapshot, 'schemaVersion') !== 1 || ownData(snapshot, 'network') !== 'solana:mainnet-beta' ||
      ownData(snapshot, 'genesisHash') !== STOCK_HOLDINGS_MAINNET_GENESIS || ownData(snapshot, 'commitment') !== 'confirmed' ||
      ownData(snapshot, 'owner') !== expectedOwner || ownData(snapshot, 'ownerBinding') !== 'trusted_server_capability' ||
      observedAt === undefined || ownData(snapshot, 'readOnly') !== true || ownData(snapshot, 'transactionBuilt') !== false ||
      ownData(snapshot, 'transactionSigned') !== false || ownData(snapshot, 'transactionBroadcast') !== false ||
      !balances || !consistency || ownData(consistency, 'kind') !== 'independent_confirmed_reads' ||
      ownData(consistency, 'atomic') !== false || !consistencySlots) return responseInvalid();
  const nativeSol = projectNativeBalance(ownData(balances, 'nativeSol'));
  const usdc = projectTokenBalance(ownData(balances, 'usdc'), {
    symbol: 'USDC', mint: JUPITER_QUOTE_ASSETS.USDC.mint, decimals: 6,
    tokenProgram: STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy,
  }) as AccountHoldingsResponse['holdings']['balances']['usdc'];
  const rawAaplx = ownData(balances, 'aaplx');
  const aaplxRecord = plainRecord(rawAaplx);
  const baseAaplx = projectTokenBalance(rawAaplx, {
    symbol: 'AAPLx', mint: JUPITER_QUOTE_ASSETS.AAPLx.mint, decimals: 8,
    tokenProgram: STOCK_HOLDINGS_TOKEN_PROGRAMS.token2022,
  });
  if (!aaplxRecord || ownData(aaplxRecord, 'displayResolution') !== 'token_2022_scaled_ui_unresolved' ||
      ownData(aaplxRecord, 'displayAmount') !== null || ownData(aaplxRecord, 'shareAmount') !== null ||
      ownData(aaplxRecord, 'eligibility') !== 'unverified' || ownData(aaplxRecord, 'executionEnabled') !== false) {
    return responseInvalid();
  }
  const aaplx = Object.freeze({...baseAaplx, symbol: 'AAPLx' as const, decimals: 8 as const,
    displayResolution: 'token_2022_scaled_ui_unresolved' as const, displayAmount: null, shareAmount: null,
    eligibility: 'unverified' as const, executionEnabled: false as const});
  const slots = Object.freeze({
    nativeSol: slot(ownData(consistencySlots, 'nativeSol')),
    usdc: slot(ownData(consistencySlots, 'usdc')),
    aaplx: slot(ownData(consistencySlots, 'aaplx')),
  });
  if (slots.nativeSol === undefined || slots.usdc === undefined || slots.aaplx === undefined ||
      slots.nativeSol !== nativeSol.observedSlot || slots.usdc !== usdc.observedSlot ||
      slots.aaplx !== aaplx.observedSlot) return responseInvalid();
  return Object.freeze({
    network: 'solana:mainnet-beta', genesisHash: STOCK_HOLDINGS_MAINNET_GENESIS, commitment: 'confirmed', observedAt,
    readOnly: true, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false,
    balances: Object.freeze({nativeSol, usdc, aaplx}),
    consistency: Object.freeze({kind: 'independent_confirmed_reads', atomic: false,
      slots: slots as {nativeSol: number; usdc: number; aaplx: number}}),
  });
}

function problem(request: FastifyRequest, reply: FastifyReply,
  status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}

const unavailable = (request: FastifyRequest, reply: FastifyReply) =>
  problem(request, reply, 503, 'ACCOUNT_HOLDINGS_UNAVAILABLE', 'Account holdings are unavailable.');
const unauthenticated = (request: FastifyRequest, reply: FastifyReply) =>
  problem(request, reply, 401, 'ACCOUNT_HOLDINGS_UNAUTHENTICATED', 'A verified existing account is required.');

function identityFailure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  if (error instanceof AccountHoldingsWalletStateError) return problem(request, reply, 409, error.code, error.message);
  const statuses: Readonly<Record<PrivyLinkedIdentityErrorCode, number>> = Object.freeze({
    PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED: 503,
    PRIVY_VERIFIED_IDENTITY_INVALID: 503,
    PRIVY_USER_RESPONSE_INVALID: 502,
    PRIVY_USER_UNAVAILABLE: 502,
    PRIVY_USER_TIMEOUT: 504,
    PRIVY_USER_RATE_LIMITED: 429,
  });
  const safe = error instanceof PrivyLinkedIdentityError && Object.hasOwn(statuses, error.code)
    ? new PrivyLinkedIdentityError(error.code)
    : new PrivyLinkedIdentityError('PRIVY_USER_UNAVAILABLE');
  return problem(request, reply, statuses[safe.code], safe.code, safe.message);
}

function holdingsFailure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  const statuses: Readonly<Record<StockHoldingsErrorCode, number>> = Object.freeze({
    STOCK_HOLDINGS_OWNER_INVALID: 502,
    STOCK_HOLDINGS_OWNER_UNVERIFIED: 502,
    STOCK_HOLDINGS_CONFIGURATION_INVALID: 503,
    STOCK_HOLDINGS_RPC_UNAVAILABLE: 502,
    STOCK_HOLDINGS_RPC_TIMEOUT: 504,
    STOCK_HOLDINGS_RPC_RESPONSE_INVALID: 502,
    STOCK_HOLDINGS_WRONG_NETWORK: 503,
    STOCK_HOLDINGS_RATE_LIMITED: 429,
  });
  const safe = error instanceof StockHoldingsError && Object.hasOwn(statuses, error.code)
    ? new StockHoldingsError(error.code)
    : new StockHoldingsError('STOCK_HOLDINGS_RPC_UNAVAILABLE');
  return problem(request, reply, statuses[safe.code], safe.code, safe.message);
}

/**
 * Existing-account bearer authentication and the linked-wallet lookup bind one
 * Privy subject to one embedded Solana address. This read does not perform a
 * separate wallet signature, provision an account, or expose a wallet input.
 */
export function registerAccountHoldingsRoute(app: FastifyInstance, options?: AccountHoldingsAdapters): void {
  const adapters = accountHoldingsEnabled(options) ? options : undefined;
  const authenticated = new WeakMap<FastifyRequest, ExistingPracticeAccountAuthentication>();
  app.get(ACCOUNT_HOLDINGS_ROUTE, {
    exposeHeadRoute: false,
    schema: {
      querystring: {type: 'object', additionalProperties: false, properties: {}},
      response: {200: responseSchema},
    },
    onRequest: async (request, reply) => {
      reply.header('cache-control', 'no-store');
      if (!adapters) return unavailable(request, reply);
      if (request.raw.url !== ACCOUNT_HOLDINGS_ROUTE ||
          request.headers['transfer-encoding'] !== undefined ||
          request.headers['content-length'] !== undefined && request.headers['content-length'] !== '0') {
        return problem(request, reply, 400, 'ACCOUNT_HOLDINGS_INVALID_REQUEST',
          'Account holdings accepts no query or request body.');
      }
      try {
        const result = await adapters.authenticate(request);
        if (!result) return unauthenticated(request, reply);
        authenticated.set(request, Object.freeze({
          userId: parsePracticeUserId(result.userId),
          identity: parsePracticeIdentity(result.identity),
        }));
      } catch (error) {
        return error instanceof PracticeAuthenticationUnavailable
          ? unavailable(request, reply) : unauthenticated(request, reply);
      }
    },
  }, async (request, reply): Promise<AccountHoldingsResponse | FastifyReply> => {
    if (!adapters) return unavailable(request, reply);
    const account = authenticated.get(request);
    if (!account) return unauthenticated(request, reply);
    let walletAddress: string;
    try {
      walletAddress = linkedWallet(
        await adapters.linkedIdentities.resolve(account.identity), account.identity.subject);
    } catch (error) {
      return identityFailure(error, request, reply);
    }
    try {
      const owner = admitServerVerifiedStockOwner({
        authenticatedUserId: account.userId,
        address: walletAddress,
        verification: 'authenticated_privy_embedded_wallet',
      });
      const holdings = projectSnapshot(await adapters.holdings.read(owner), walletAddress);
      return Object.freeze({
        schemaVersion: 1,
        userId: account.userId,
        wallet: Object.freeze({
          address: walletAddress,
          source: 'privy_embedded_wallet_same_subject',
          possessionSignatureVerified: false,
        }),
        holdings,
      });
    } catch (error) {
      return holdingsFailure(error, request, reply);
    }
  });
}
