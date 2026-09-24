/**
 * Pure, deterministic decoding of Solana `getMultipleAccounts` (base64) observations
 * into reviewable state for the stock-swap reviewer. No RPC, no clock, no caching.
 *
 * What this module does NOT verify:
 * - Network or freshness: nothing here knows which cluster, slot or commitment an
 *   observation came from, or whether the account has changed since.
 * - Program ownership authenticity: `owner` and `executable` are taken from the RPC
 *   response as-is. A dishonest RPC can claim any owner; this module only decodes.
 * - Program semantics: a transfer-hook program address is reported, never inspected.
 *   Extension flags are decoded from bytes; they do not prove how the program behaves.
 * - Rent, associated-token-account existence, or swap eligibility.
 * All TLV discriminators and layouts come from the pinned generated decoders in
 * `@solana-program/token-2022` and `@solana-program/token`; nothing is hand-parsed.
 */
import {createHash} from 'node:crypto';
import {address, unwrapOption} from '@solana/kit';
import type {Address, Decoder, Encoder, Option} from '@solana/kit';
import {
  getMintDecoder as getLegacyMintDecoder,
  getMintEncoder as getLegacyMintEncoder,
  getTokenDecoder as getLegacyTokenDecoder,
  getTokenEncoder as getLegacyTokenEncoder,
} from '@solana-program/token';
import {
  findAssociatedTokenPda,
  getMintDecoder,
  getMintEncoder,
  getTokenDecoder,
  getTokenEncoder,
} from '@solana-program/token-2022';
import type {Extension} from '@solana-program/token-2022';

export const TOKEN_PROGRAM_ADDRESS = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
export const TOKEN_2022_PROGRAM_ADDRESS = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
export const ASSOCIATED_TOKEN_PROGRAM_ADDRESS = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
export const SYSTEM_PROGRAM_ADDRESS = '11111111111111111111111111111111';
export const NATIVE_MINT_ADDRESS = 'So11111111111111111111111111111111111111112';
const LOOKUP_TABLE_PROGRAM_ADDRESS = 'AddressLookupTab1e1111111111111111111111111';
/** Token-2022 `OptionalNonZeroPubkey` fields encode "none" as the all-zero key. */
const ZERO_ADDRESS = '11111111111111111111111111111111';

/** Solana's MAX_PERMITTED_DATA_LENGTH (10 MiB); larger observations are rejected. */
const MAX_ACCOUNT_DATA_BYTES = 10_485_760;
const MAX_BASE64_LENGTH = Math.ceil(MAX_ACCOUNT_DATA_BYTES / 3) * 4;
const U64_MAX = 18_446_744_073_709_551_615n;
const MINT_LENGTH = 82;
const TOKEN_ACCOUNT_LENGTH = 165;
/** Token-2022 rejects `Multisig::LEN` bytes as a mint or token account, so do we. */
const MULTISIG_LENGTH = 355;
/** Token-2022 account-type byte at offset 165 when extensions are present. */
const ACCOUNT_TYPE_MINT = 1;
const ACCOUNT_TYPE_TOKEN_ACCOUNT = 2;
const BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const RPC_ACCOUNT_KEYS = ['lamports', 'owner', 'executable', 'data', 'rentEpoch', 'space'] as const;
const RPC_REQUIRED_KEYS = ['lamports', 'owner', 'executable', 'data'] as const;

export type AccountStateErrorCode = 'ACCOUNT_OBSERVATION_INVALID' | 'ACCOUNT_DATA_INVALID';

/** Fixed message: never carries account bytes, addresses or decoder details. */
export class AccountStateError extends Error {
  constructor(readonly code: AccountStateErrorCode) {
    super('The Solana account observation could not be decoded.');
    this.name = 'AccountStateError';
  }
}

/** One raw RPC observation, already parsed from JSON. `data` is the decoded base64 bytes. */
export interface ObservedAccount {
  readonly address: string;
  readonly exists: boolean;
  readonly lamports: bigint;
  readonly owner: string | null;
  readonly executable: boolean;
  readonly data: Uint8Array;
}

export interface ObservedAccountSummary {
  readonly address: string;
  readonly exists: boolean;
  readonly lamports: string;
  readonly owner: string | null;
  readonly executable: boolean;
  readonly dataLengthBytes: number;
  readonly dataSha256: string;
}

export type TokenProgramKind = 'token' | 'token_2022';
export type TokenAccountState = 'uninitialized' | 'initialized' | 'frozen';

export type DecodedAccountState =
  | {kind: 'missing'; address: string}
  | {kind: 'system'; address: string; lamports: bigint}
  | {kind: 'program'; address: string; owner: string; executable: true}
  | {kind: 'token_account'; address: string; tokenProgram: TokenProgramKind; mint: string; owner: string;
      amount: bigint; delegate: string | null; delegatedAmount: bigint; state: TokenAccountState;
      isNative: boolean; nativeRentExemptReserve: bigint | null; closeAuthority: string | null;
      extensions: readonly string[]; immutableOwner: boolean; cpiGuard: boolean; memoTransferRequired: boolean;
      nonTransferable: boolean; transferHookTransferring: boolean; lamports: bigint}
  | {kind: 'mint'; address: string; tokenProgram: TokenProgramKind; decimals: number; supply: bigint;
      isInitialized: boolean; mintAuthority: string | null; freezeAuthority: string | null;
      extensions: readonly string[]; defaultAccountState: 'initialized' | 'frozen' | null; paused: boolean | null;
      transferHookProgram: string | null; transferHookAuthority: string | null; permanentDelegate: string | null;
      transferFee: {readonly basisPoints: number; readonly maximumFee: bigint} | null;
      scaledUiAmount: {readonly multiplier: number; readonly newMultiplier: number;
        readonly newMultiplierEffectiveTimestamp: bigint} | null;
      nonTransferable: boolean; confidentialTransfer: boolean; mintCloseAuthority: string | null; lamports: bigint}
  | {kind: 'lookup_table'; address: string}
  | {kind: 'other'; address: string; owner: string; dataLengthBytes: number};

const fail = (code: AccountStateErrorCode): never => {
  throw new AccountStateError(code);
};

function canonicalAddress(value: unknown, code: AccountStateErrorCode = 'ACCOUNT_OBSERVATION_INVALID'): Address {
  try {
    if (typeof value !== 'string' || value.length < 32 || value.length > 44) return fail(code);
    const checked = address(value);
    if (checked !== value) return fail(code);
    return checked;
  } catch (error) {
    if (error instanceof AccountStateError) throw error;
    return fail(code);
  }
}

function ownRecord(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return fail('ACCOUNT_OBSERVATION_INVALID');
  const proto: unknown = Object.getPrototypeOf(value);
  if (proto !== Object.prototype && proto !== null) return fail('ACCOUNT_OBSERVATION_INVALID');
  const copy: Record<string, unknown> = {};
  for (const key of Reflect.ownKeys(value)) {
    const descriptor = typeof key === 'string' ? Object.getOwnPropertyDescriptor(value, key) : undefined;
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) return fail('ACCOUNT_OBSERVATION_INVALID');
    copy[key as string] = descriptor.value;
  }
  return copy;
}

function canonicalBase64(value: unknown): Uint8Array {
  if (typeof value !== 'string' || value.length > MAX_BASE64_LENGTH || value.length % 4 !== 0 || !BASE64.test(value)) {
    return fail('ACCOUNT_OBSERVATION_INVALID');
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.toString('base64') !== value || bytes.byteLength > MAX_ACCOUNT_DATA_BYTES) {
    return fail('ACCOUNT_OBSERVATION_INVALID');
  }
  return new Uint8Array(bytes);
}

/**
 * Validates one element of a `getMultipleAccounts` (base64 encoding) `value` array.
 * `null` means the address has no account. Any other shape is rejected as a whole.
 * `lamports` must be a safe JSON integer; `space`, when present, must match the data length.
 */
export function parseObservedAccount(address: string, rpcValue: unknown): ObservedAccount {
  const accountAddress = canonicalAddress(address);
  if (rpcValue === null) {
    return Object.freeze({address: accountAddress, exists: false, lamports: 0n, owner: null, executable: false,
      data: new Uint8Array(0)});
  }
  const value = ownRecord(rpcValue);
  const keys = Object.keys(value);
  if (keys.some(key => !(RPC_ACCOUNT_KEYS as readonly string[]).includes(key)) ||
      RPC_REQUIRED_KEYS.some(key => !Object.hasOwn(value, key))) return fail('ACCOUNT_OBSERVATION_INVALID');
  const lamports = value['lamports'];
  const executable = value['executable'];
  const data = value['data'];
  const rentEpoch = value['rentEpoch'];
  const space = value['space'];
  if (typeof lamports !== 'number' || !Number.isSafeInteger(lamports) || lamports < 0 ||
      typeof executable !== 'boolean' || !Array.isArray(data) || data.length !== 2 || data[1] !== 'base64' ||
      (rentEpoch !== undefined && (typeof rentEpoch !== 'number' || !Number.isInteger(rentEpoch) || rentEpoch < 0))) {
    return fail('ACCOUNT_OBSERVATION_INVALID');
  }
  const owner = canonicalAddress(value['owner']);
  const bytes = canonicalBase64(data[0]);
  if (space !== undefined && (!Number.isSafeInteger(space) || space !== bytes.byteLength)) {
    return fail('ACCOUNT_OBSERVATION_INVALID');
  }
  return Object.freeze({address: accountAddress, exists: true, lamports: BigInt(lamports), owner, executable,
    data: bytes});
}

/** Re-validates an `ObservedAccount` before use so hand-built inputs cannot skip the checks. */
function observed(account: ObservedAccount): ObservedAccount {
  if (account === null || typeof account !== 'object' || typeof account.exists !== 'boolean' ||
      typeof account.lamports !== 'bigint' || account.lamports < 0n || account.lamports > U64_MAX ||
      typeof account.executable !== 'boolean' || !(account.data instanceof Uint8Array) ||
      account.data.byteLength > MAX_ACCOUNT_DATA_BYTES || (account.owner !== null && typeof account.owner !== 'string')) {
    return fail('ACCOUNT_OBSERVATION_INVALID');
  }
  canonicalAddress(account.address);
  if (account.exists) {
    canonicalAddress(account.owner);
  } else if (account.lamports !== 0n || account.owner !== null || account.executable || account.data.byteLength !== 0) {
    return fail('ACCOUNT_OBSERVATION_INVALID');
  }
  return account;
}

export function summarizeObservedAccount(account: ObservedAccount): ObservedAccountSummary {
  const value = observed(account);
  return Object.freeze({address: value.address, exists: value.exists, lamports: value.lamports.toString(),
    owner: value.owner, executable: value.executable, dataLengthBytes: value.data.byteLength,
    dataSha256: createHash('sha256').update(value.data).digest('hex')});
}

/**
 * Decodes and re-encodes; any decoder error, trailing bytes or non-canonical encoding
 * (permissive booleans, options, padding) is reported as ACCOUNT_DATA_INVALID.
 */
function strictDecode<TArgs, T extends TArgs>(decoder: Decoder<T>, encoder: Encoder<TArgs>, bytes: Uint8Array): T {
  try {
    const [value, end] = decoder.read(bytes, 0);
    if (end !== bytes.byteLength || !Buffer.from(encoder.encode(value)).equals(Buffer.from(bytes))) {
      return fail('ACCOUNT_DATA_INVALID');
    }
    return value;
  } catch (error) {
    if (error instanceof AccountStateError) throw error;
    return fail('ACCOUNT_DATA_INVALID');
  }
}

type ExtensionKind = Extension['__kind'];

function findExtension<K extends ExtensionKind>(extensions: readonly Extension[], kind: K):
  Extract<Extension, {__kind: K}> | undefined {
  return extensions.find((item): item is Extract<Extension, {__kind: K}> => item.__kind === kind);
}

/** Lists extension kinds; `Uninitialized` TLV slots are padding, duplicates are malformed. */
function extensionKinds(extensions: readonly Extension[]): readonly string[] {
  const kinds = extensions.map(item => item.__kind).filter(kind => kind !== 'Uninitialized');
  if (new Set(kinds).size !== kinds.length) return fail('ACCOUNT_DATA_INVALID');
  return Object.freeze(kinds);
}

function nonZeroAddress(value: Address): string | null {
  return value === ZERO_ADDRESS ? null : value;
}

function accountState(state: number): TokenAccountState {
  if (state === 0) return 'uninitialized';
  if (state === 1) return 'initialized';
  if (state === 2) return 'frozen';
  return fail('ACCOUNT_DATA_INVALID');
}

interface MintBase {
  readonly mintAuthority: Option<Address>;
  readonly supply: bigint;
  readonly decimals: number;
  readonly isInitialized: boolean;
  readonly freezeAuthority: Option<Address>;
}

interface TokenBase {
  readonly mint: Address;
  readonly owner: Address;
  readonly amount: bigint;
  readonly delegate: Option<Address>;
  readonly state: number;
  readonly isNative: Option<bigint>;
  readonly delegatedAmount: bigint;
  readonly closeAuthority: Option<Address>;
}

function mintState(account: ObservedAccount, tokenProgram: TokenProgramKind, mint: MintBase,
  extensions: readonly Extension[]): DecodedAccountState {
  const kinds = extensionKinds(extensions);
  const pausable = findExtension(extensions, 'PausableConfig');
  const defaultState = findExtension(extensions, 'DefaultAccountState');
  const hook = findExtension(extensions, 'TransferHook');
  const permanentDelegate = findExtension(extensions, 'PermanentDelegate');
  const fee = findExtension(extensions, 'TransferFeeConfig');
  const scaled = findExtension(extensions, 'ScaledUiAmountConfig');
  const close = findExtension(extensions, 'MintCloseAuthority');
  const defaultAccountState = defaultState ? accountState(Number(defaultState.state)) : null;
  if (defaultAccountState === 'uninitialized') return fail('ACCOUNT_DATA_INVALID');
  return Object.freeze({
    kind: 'mint', address: account.address, tokenProgram, decimals: mint.decimals, supply: mint.supply,
    isInitialized: mint.isInitialized, mintAuthority: unwrapOption(mint.mintAuthority),
    freezeAuthority: unwrapOption(mint.freezeAuthority), extensions: kinds, defaultAccountState,
    paused: pausable ? pausable.paused : null,
    transferHookProgram: hook ? nonZeroAddress(hook.programId) : null,
    transferHookAuthority: hook ? nonZeroAddress(hook.authority) : null,
    permanentDelegate: permanentDelegate ? nonZeroAddress(permanentDelegate.delegate) : null,
    // The newer fee schedule is reported; which one is active depends on the current epoch (not known here).
    transferFee: fee ? Object.freeze({basisPoints: fee.newerTransferFee.transferFeeBasisPoints,
      maximumFee: fee.newerTransferFee.maximumFee}) : null,
    scaledUiAmount: scaled ? Object.freeze({multiplier: scaled.multiplier, newMultiplier: scaled.newMultiplier,
      newMultiplierEffectiveTimestamp: scaled.newMultiplierEffectiveTimestamp}) : null,
    nonTransferable: kinds.includes('NonTransferable'),
    confidentialTransfer: kinds.includes('ConfidentialTransferMint'),
    mintCloseAuthority: close ? nonZeroAddress(close.closeAuthority) : null,
    lamports: account.lamports,
  });
}

function tokenAccountState(account: ObservedAccount, tokenProgram: TokenProgramKind, token: TokenBase,
  extensions: readonly Extension[]): DecodedAccountState {
  const kinds = extensionKinds(extensions);
  const cpiGuard = findExtension(extensions, 'CpiGuard');
  const memo = findExtension(extensions, 'MemoTransfer');
  const hookAccount = findExtension(extensions, 'TransferHookAccount');
  const nativeReserve = unwrapOption(token.isNative);
  return Object.freeze({
    kind: 'token_account', address: account.address, tokenProgram, mint: token.mint, owner: token.owner,
    amount: token.amount, delegate: unwrapOption(token.delegate), delegatedAmount: token.delegatedAmount,
    state: accountState(Number(token.state)), isNative: nativeReserve !== null,
    nativeRentExemptReserve: nativeReserve, closeAuthority: unwrapOption(token.closeAuthority), extensions: kinds,
    immutableOwner: kinds.includes('ImmutableOwner'), cpiGuard: cpiGuard?.lockCpi ?? false,
    memoTransferRequired: memo?.requireIncomingTransferMemos ?? false,
    nonTransferable: kinds.includes('NonTransferableAccount'),
    transferHookTransferring: hookAccount?.transferring ?? false, lamports: account.lamports,
  });
}

/**
 * Legacy program: exactly 165 bytes is a token account, exactly 82 a mint.
 * Token-2022: the same exact sizes have no extensions; longer accounts carry the
 * account-type byte at offset 165 (1 = mint after 83 zero padding bytes, 2 = token
 * account) followed by TLV extensions, exactly as the generated codecs expect.
 */
function tokenProgramAccount(account: ObservedAccount, tokenProgram: TokenProgramKind): DecodedAccountState {
  const bytes = account.data;
  const length = bytes.byteLength;
  if (tokenProgram === 'token') {
    if (length === TOKEN_ACCOUNT_LENGTH) {
      return tokenAccountState(account, tokenProgram,
        strictDecode(getLegacyTokenDecoder(), getLegacyTokenEncoder(), bytes), []);
    }
    if (length === MINT_LENGTH) {
      return mintState(account, tokenProgram, strictDecode(getLegacyMintDecoder(), getLegacyMintEncoder(), bytes), []);
    }
    return fail('ACCOUNT_DATA_INVALID');
  }
  const accountType = length === MINT_LENGTH ? ACCOUNT_TYPE_MINT :
    length === TOKEN_ACCOUNT_LENGTH ? ACCOUNT_TYPE_TOKEN_ACCOUNT :
    length > TOKEN_ACCOUNT_LENGTH && length !== MULTISIG_LENGTH ? bytes[TOKEN_ACCOUNT_LENGTH] : undefined;
  if (accountType === ACCOUNT_TYPE_MINT) {
    const mint = strictDecode(getMintDecoder(), getMintEncoder(), bytes);
    return mintState(account, tokenProgram, mint, unwrapOption(mint.extensions) ?? []);
  }
  if (accountType === ACCOUNT_TYPE_TOKEN_ACCOUNT) {
    const token = strictDecode(getTokenDecoder(), getTokenEncoder(), bytes);
    return tokenAccountState(account, tokenProgram, token, unwrapOption(token.extensions) ?? []);
  }
  return fail('ACCOUNT_DATA_INVALID');
}

/**
 * Classifies one observation. Throws ACCOUNT_DATA_INVALID only for accounts owned by a
 * token program whose bytes do not decode canonically as a token account or mint.
 * Executable accounts are reported as programs whatever their loader; the owner is echoed, not verified.
 */
export function decodeAccountState(account: ObservedAccount): DecodedAccountState {
  const value = observed(account);
  if (!value.exists || value.owner === null) return Object.freeze({kind: 'missing', address: value.address});
  if (value.executable) {
    return Object.freeze({kind: 'program', address: value.address, owner: value.owner, executable: true});
  }
  if (value.owner === SYSTEM_PROGRAM_ADDRESS && value.data.byteLength === 0) {
    return Object.freeze({kind: 'system', address: value.address, lamports: value.lamports});
  }
  if (value.owner === TOKEN_PROGRAM_ADDRESS) return tokenProgramAccount(value, 'token');
  if (value.owner === TOKEN_2022_PROGRAM_ADDRESS) return tokenProgramAccount(value, 'token_2022');
  if (value.owner === LOOKUP_TABLE_PROGRAM_ADDRESS) return Object.freeze({kind: 'lookup_table', address: value.address});
  return Object.freeze({kind: 'other', address: value.address, owner: value.owner,
    dataLengthBytes: value.data.byteLength});
}

/** Associated token address: PDA of [owner, token program, mint] under the associated-token program. */
export async function deriveAssociatedTokenAddress(owner: string, mint: string,
  tokenProgram: TokenProgramKind): Promise<string> {
  const ownerAddress = canonicalAddress(owner);
  const mintAddress = canonicalAddress(mint);
  const programAddress = tokenProgram === 'token' ? TOKEN_PROGRAM_ADDRESS :
    tokenProgram === 'token_2022' ? TOKEN_2022_PROGRAM_ADDRESS : fail('ACCOUNT_OBSERVATION_INVALID');
  try {
    const [derived] = await findAssociatedTokenPda(
      {owner: ownerAddress, tokenProgram: address(programAddress), mint: mintAddress},
      {programAddress: address(ASSOCIATED_TOKEN_PROGRAM_ADDRESS)});
    return derived;
  } catch {
    return fail('ACCOUNT_OBSERVATION_INVALID');
  }
}
