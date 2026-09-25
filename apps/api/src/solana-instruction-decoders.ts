import { createHash } from 'node:crypto';
import { address, isOffCurveAddress } from '@solana/kit';
import type { Decoder, Encoder, ReadonlyUint8Array } from '@solana/kit';
import { identifySystemInstruction, SystemInstruction, getTransferSolInstructionDataDecoder,
  getTransferSolInstructionDataEncoder, getCreateAccountInstructionDataDecoder,
  getCreateAccountInstructionDataEncoder } from '@solana-program/system';
import { identifyComputeBudgetInstruction, ComputeBudgetInstruction,
  getSetComputeUnitLimitInstructionDataDecoder, getSetComputeUnitLimitInstructionDataEncoder,
  getSetComputeUnitPriceInstructionDataDecoder, getSetComputeUnitPriceInstructionDataEncoder,
  getRequestHeapFrameInstructionDataDecoder, getRequestHeapFrameInstructionDataEncoder,
  getSetLoadedAccountsDataSizeLimitInstructionDataDecoder,
  getSetLoadedAccountsDataSizeLimitInstructionDataEncoder } from '@solana-program/compute-budget';
import { identifyToken2022Instruction, Token2022Instruction, identifyAssociatedTokenInstruction,
  AssociatedTokenInstruction, getTransferInstructionDataDecoder, getTransferInstructionDataEncoder,
  getTransferCheckedInstructionDataDecoder, getTransferCheckedInstructionDataEncoder,
  getApproveInstructionDataDecoder, getApproveInstructionDataEncoder,
  getApproveCheckedInstructionDataDecoder, getApproveCheckedInstructionDataEncoder,
  getRevokeInstructionDataDecoder, getRevokeInstructionDataEncoder,
  getCloseAccountInstructionDataDecoder, getCloseAccountInstructionDataEncoder,
  getSyncNativeInstructionDataDecoder, getSyncNativeInstructionDataEncoder,
  getInitializeAccountInstructionDataDecoder, getInitializeAccountInstructionDataEncoder,
  getInitializeAccount2InstructionDataDecoder, getInitializeAccount2InstructionDataEncoder,
  getInitializeAccount3InstructionDataDecoder, getInitializeAccount3InstructionDataEncoder,
  getInitializeImmutableOwnerInstructionDataDecoder, getInitializeImmutableOwnerInstructionDataEncoder,
  getCreateAssociatedTokenInstructionDataDecoder, getCreateAssociatedTokenInstructionDataEncoder,
  getCreateAssociatedTokenIdempotentInstructionDataDecoder,
  getCreateAssociatedTokenIdempotentInstructionDataEncoder } from '@solana-program/token-2022';

/**
 * Deterministic decoder for the top-level compiled instructions of an unsigned
 * Solana v0 stock-swap transaction. It answers "what would this instruction
 * do", using the pinned official codecs for the four system-level programs and
 * the pinned Jupiter v6 account layout and argument tail for the two admitted
 * swap entry points.
 *
 * What this module does NOT verify: that the program addresses are executable
 * accounts owned by a loader, that any referenced account exists or holds the
 * state the instruction assumes, that the cluster is mainnet, that a transfer
 * hook or permanent delegate will not change the effect, or that a route plan's
 * inner instructions match its declared arguments. Those are the account-state
 * and simulation gates. Nothing here signs, sends or approves.
 */
export interface DecodableInstruction {
  readonly programAddress: string;
  readonly accountAddresses: readonly string[];
  readonly data: Uint8Array;
}

export type InstructionDecodeErrorCode = 'UNSUPPORTED_PROGRAM' | 'UNSUPPORTED_INSTRUCTION' | 'INSTRUCTION_INVALID';

export class InstructionDecodeError extends Error {
  constructor(readonly code: InstructionDecodeErrorCode) {
    super('The Solana instruction cannot be reviewed.');
    this.name = 'InstructionDecodeError';
  }
}
const fail = (code: InstructionDecodeErrorCode): never => { throw new InstructionDecodeError(code); };

export const KNOWN_PROGRAMS = Object.freeze({
  system: '11111111111111111111111111111111',
  token: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
  token2022: 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb',
  associatedToken: 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL',
  computeBudget: 'ComputeBudget111111111111111111111111111111',
  jupiterV6: 'JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4',
  memo: 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr',
} as const);

export type TokenProgramName = 'token' | 'token_2022';

export type DecodedInstruction =
  | {readonly program: 'system'; readonly kind: 'transfer'; readonly from: string; readonly to: string; readonly lamports: bigint}
  | {readonly program: 'system'; readonly kind: 'create_account'; readonly from: string; readonly newAccount: string;
      readonly lamports: bigint; readonly space: bigint; readonly owner: string}
  | {readonly program: TokenProgramName; readonly kind: 'transfer'; readonly source: string; readonly destination: string;
      readonly authority: string; readonly amount: bigint; readonly checked: boolean; readonly mint: string | null;
      readonly decimals: number | null; readonly extraAccounts: readonly string[]}
  | {readonly program: TokenProgramName; readonly kind: 'approve'; readonly source: string; readonly delegate: string;
      readonly authority: string; readonly amount: bigint; readonly checked: boolean; readonly mint: string | null;
      readonly decimals: number | null}
  | {readonly program: TokenProgramName; readonly kind: 'revoke'; readonly source: string; readonly authority: string}
  | {readonly program: TokenProgramName; readonly kind: 'close_account'; readonly account: string;
      readonly destination: string; readonly authority: string}
  | {readonly program: TokenProgramName; readonly kind: 'sync_native'; readonly account: string}
  | {readonly program: TokenProgramName; readonly kind: 'initialize_account'; readonly variant: 1 | 2 | 3;
      readonly account: string; readonly mint: string; readonly owner: string}
  | {readonly program: TokenProgramName; readonly kind: 'initialize_immutable_owner'; readonly account: string}
  | {readonly program: 'associated_token'; readonly kind: 'create' | 'create_idempotent'; readonly payer: string;
      readonly associatedAccount: string; readonly owner: string; readonly mint: string; readonly tokenProgram: string}
  | {readonly program: 'compute_budget'; readonly kind: 'set_compute_unit_limit'; readonly units: number}
  | {readonly program: 'compute_budget'; readonly kind: 'set_compute_unit_price'; readonly microLamports: bigint}
  | {readonly program: 'compute_budget'; readonly kind: 'request_heap_frame'; readonly bytes: number}
  | {readonly program: 'compute_budget'; readonly kind: 'set_loaded_accounts_data_size_limit'; readonly bytes: number}
  | {readonly program: 'jupiter_v6'; readonly kind: 'route' | 'shared_accounts_route' | 'route_v2'; readonly tokenProgram: string;
      readonly programAuthority: string | null; readonly userTransferAuthority: string;
      readonly userSourceTokenAccount: string; readonly userDestinationTokenAccount: string;
      readonly programSourceTokenAccount: string | null; readonly programDestinationTokenAccount: string | null;
      readonly sourceMint: string | null; readonly destinationMint: string; readonly platformFeeAccount: string | null;
      readonly token2022Program: string | null; readonly eventAuthority: string; readonly routeAccounts: readonly string[];
      readonly inAmount: bigint; readonly quotedOutAmount: bigint; readonly slippageBps: number;
      readonly platformFeeBps: number; readonly routePlanStepCount: number; readonly destinationTokenProgram?: string}
  | {readonly program: 'memo'; readonly kind: 'memo'; readonly byteLength: number};

const MAX_EXTRA_ACCOUNTS = 32;
const MAX_ROUTE_ACCOUNTS = 243; // Repeated references across hops, not unique transaction accounts.
const MAX_ROUTE_PLAN_STEPS = 64;
const MAX_MEMO_BYTES = 566;
const JUPITER_TAIL_BYTES = 19;

/** Anchor discriminator: the first eight bytes of sha256("global:<snake_case name>"). */
function anchorDiscriminator(name: string): Uint8Array {
  return Uint8Array.from(createHash('sha256').update(`global:${name}`).digest().subarray(0, 8));
}
const JUPITER_DISCRIMINATORS = Object.freeze({
  route: anchorDiscriminator('route'),
  route_v2: anchorDiscriminator('route_v2'),
  shared_accounts_route: anchorDiscriminator('shared_accounts_route'),
  exact_out_route: anchorDiscriminator('exact_out_route'),
  shared_accounts_exact_out_route: anchorDiscriminator('shared_accounts_exact_out_route'),
  route_with_token_ledger: anchorDiscriminator('route_with_token_ledger'),
  shared_accounts_route_with_token_ledger: anchorDiscriminator('shared_accounts_route_with_token_ledger'),
});

function checkedAddress(value: unknown): string {
  try {
    if (typeof value !== 'string' || value.length < 32 || value.length > 44) return fail('INSTRUCTION_INVALID');
    const parsed = address(value);
    if (parsed !== value) return fail('INSTRUCTION_INVALID');
    return parsed;
  } catch (error) {
    if (error instanceof InstructionDecodeError) throw error;
    return fail('INSTRUCTION_INVALID');
  }
}

/** Only an on-curve, nonzero key can be a wallet-held signer or owner. */
function walletAddress(value: string): string {
  const parsed = checkedAddress(value);
  try {
    if (parsed === KNOWN_PROGRAMS.system || isOffCurveAddress(address(parsed))) return fail('INSTRUCTION_INVALID');
  } catch (error) {
    if (error instanceof InstructionDecodeError) throw error;
    return fail('INSTRUCTION_INVALID');
  }
  return parsed;
}

function validated(instruction: DecodableInstruction): DecodableInstruction {
  if (instruction === null || typeof instruction !== 'object' || !(instruction.data instanceof Uint8Array) ||
      !Array.isArray(instruction.accountAddresses) || instruction.accountAddresses.length > 256) {
    return fail('INSTRUCTION_INVALID');
  }
  const programAddress = checkedAddress(instruction.programAddress);
  const accountAddresses = instruction.accountAddresses.map(value => checkedAddress(value));
  return {programAddress, accountAddresses, data: instruction.data};
}

/**
 * Decodes fixed-size instruction data and rejects trailing or non-canonical
 * bytes by re-encoding the decoded value and comparing it with the input.
 */
function exact<T>(decoder: Decoder<T>, encoder: Encoder<T>, data: Uint8Array): T {
  let decoded: T;
  try {
    decoded = decoder.decode(data);
  } catch {
    return fail('INSTRUCTION_INVALID');
  }
  let reencoded: ReadonlyUint8Array;
  try {
    reencoded = encoder.encode(decoded);
  } catch {
    return fail('INSTRUCTION_INVALID');
  }
  if (reencoded.length !== data.length || data.some((byte, index) => byte !== reencoded[index])) {
    return fail('INSTRUCTION_INVALID');
  }
  return decoded;
}

function accounts(list: readonly string[], count: number): readonly string[] {
  if (list.length !== count) return fail('UNSUPPORTED_INSTRUCTION');
  return list;
}

function decodeSystem(instruction: DecodableInstruction): DecodedInstruction {
  let kind: SystemInstruction;
  try { kind = identifySystemInstruction(instruction.data); }
  catch { return fail('UNSUPPORTED_INSTRUCTION'); }
  const list = instruction.accountAddresses;
  switch (kind) {
    case SystemInstruction.TransferSol: {
      const data = exact(getTransferSolInstructionDataDecoder(), getTransferSolInstructionDataEncoder(), instruction.data);
      const [from, to] = accounts(list, 2);
      return Object.freeze({program: 'system', kind: 'transfer', from: walletAddress(from!),
        to: checkedAddress(to!), lamports: data.amount} as const);
    }
    case SystemInstruction.CreateAccount: {
      const data = exact(getCreateAccountInstructionDataDecoder(), getCreateAccountInstructionDataEncoder(), instruction.data);
      const [from, newAccount] = accounts(list, 2);
      return Object.freeze({program: 'system', kind: 'create_account', from: walletAddress(from!),
        newAccount: checkedAddress(newAccount!), lamports: data.lamports, space: data.space,
        owner: checkedAddress(data.programAddress)} as const);
    }
    default:
      // Nonce, assign, allocate and seeded variants change authorities or create
      // program-owned state; none belongs in a reviewed swap.
      return fail('UNSUPPORTED_INSTRUCTION');
  }
}

function decodeComputeBudget(instruction: DecodableInstruction): DecodedInstruction {
  let kind: ComputeBudgetInstruction;
  try { kind = identifyComputeBudgetInstruction(instruction.data); }
  catch { return fail('UNSUPPORTED_INSTRUCTION'); }
  if (instruction.accountAddresses.length !== 0) return fail('INSTRUCTION_INVALID');
  switch (kind) {
    case ComputeBudgetInstruction.SetComputeUnitLimit: {
      const data = exact(getSetComputeUnitLimitInstructionDataDecoder(), getSetComputeUnitLimitInstructionDataEncoder(), instruction.data);
      return Object.freeze({program: 'compute_budget', kind: 'set_compute_unit_limit', units: data.units} as const);
    }
    case ComputeBudgetInstruction.SetComputeUnitPrice: {
      const data = exact(getSetComputeUnitPriceInstructionDataDecoder(), getSetComputeUnitPriceInstructionDataEncoder(), instruction.data);
      return Object.freeze({program: 'compute_budget', kind: 'set_compute_unit_price', microLamports: data.microLamports} as const);
    }
    case ComputeBudgetInstruction.RequestHeapFrame: {
      const data = exact(getRequestHeapFrameInstructionDataDecoder(), getRequestHeapFrameInstructionDataEncoder(), instruction.data);
      return Object.freeze({program: 'compute_budget', kind: 'request_heap_frame', bytes: data.bytes} as const);
    }
    case ComputeBudgetInstruction.SetLoadedAccountsDataSizeLimit: {
      const data = exact(getSetLoadedAccountsDataSizeLimitInstructionDataDecoder(),
        getSetLoadedAccountsDataSizeLimitInstructionDataEncoder(), instruction.data);
      return Object.freeze({program: 'compute_budget', kind: 'set_loaded_accounts_data_size_limit',
        bytes: data.accountDataSizeLimit} as const);
    }
    default:
      // RequestUnits is the deprecated combined limit/fee instruction.
      return fail('UNSUPPORTED_INSTRUCTION');
  }
}

function decodeAssociatedToken(instruction: DecodableInstruction): DecodedInstruction {
  let kind: AssociatedTokenInstruction;
  try { kind = identifyAssociatedTokenInstruction(instruction.data); }
  catch { return fail('UNSUPPORTED_INSTRUCTION'); }
  if (kind === AssociatedTokenInstruction.RecoverNestedAssociatedToken) return fail('UNSUPPORTED_INSTRUCTION');
  const idempotent = kind === AssociatedTokenInstruction.CreateAssociatedTokenIdempotent;
  if (idempotent) {
    exact(getCreateAssociatedTokenIdempotentInstructionDataDecoder(),
      getCreateAssociatedTokenIdempotentInstructionDataEncoder(), instruction.data);
  } else {
    exact(getCreateAssociatedTokenInstructionDataDecoder(), getCreateAssociatedTokenInstructionDataEncoder(), instruction.data);
  }
  const [payer, associatedAccount, owner, mint, systemProgram, tokenProgram] = accounts(instruction.accountAddresses, 6);
  if (systemProgram !== KNOWN_PROGRAMS.system) return fail('INSTRUCTION_INVALID');
  if (tokenProgram !== KNOWN_PROGRAMS.token && tokenProgram !== KNOWN_PROGRAMS.token2022) return fail('INSTRUCTION_INVALID');
  return Object.freeze({program: 'associated_token', kind: idempotent ? 'create_idempotent' : 'create',
    payer: walletAddress(payer!), associatedAccount: checkedAddress(associatedAccount!), owner: checkedAddress(owner!),
    mint: checkedAddress(mint!), tokenProgram} as const);
}

function decodeTokenProgram(instruction: DecodableInstruction, program: TokenProgramName): DecodedInstruction {
  let kind: Token2022Instruction;
  // Token-2022 is a superset of the legacy layouts for every admitted instruction.
  try { kind = identifyToken2022Instruction(instruction.data); }
  catch { return fail('UNSUPPORTED_INSTRUCTION'); }
  const list = instruction.accountAddresses;
  switch (kind) {
    case Token2022Instruction.Transfer: {
      const data = exact(getTransferInstructionDataDecoder(), getTransferInstructionDataEncoder(), instruction.data);
      const [source, destination, authority] = accounts(list, 3);
      return Object.freeze({program, kind: 'transfer', source: checkedAddress(source!),
        destination: checkedAddress(destination!), authority: checkedAddress(authority!), amount: data.amount,
        checked: false, mint: null, decimals: null, extraAccounts: Object.freeze([])} as const);
    }
    case Token2022Instruction.TransferChecked: {
      const data = exact(getTransferCheckedInstructionDataDecoder(), getTransferCheckedInstructionDataEncoder(), instruction.data);
      if (list.length < 4) return fail('UNSUPPORTED_INSTRUCTION');
      // Extra accounts are transfer-hook accounts on Token-2022. On the legacy
      // program they can only be multisig signers, which this review rejects.
      const extras = list.slice(4);
      if (extras.length > 0 && (program === 'token' || extras.length > MAX_EXTRA_ACCOUNTS)) return fail('UNSUPPORTED_INSTRUCTION');
      const [source, mint, destination, authority] = list;
      return Object.freeze({program, kind: 'transfer', source: checkedAddress(source!),
        destination: checkedAddress(destination!), authority: checkedAddress(authority!), amount: data.amount,
        checked: true, mint: checkedAddress(mint!), decimals: data.decimals,
        extraAccounts: Object.freeze(extras.map(value => checkedAddress(value)))} as const);
    }
    case Token2022Instruction.Approve: {
      const data = exact(getApproveInstructionDataDecoder(), getApproveInstructionDataEncoder(), instruction.data);
      const [source, delegate, authority] = accounts(list, 3);
      return Object.freeze({program, kind: 'approve', source: checkedAddress(source!), delegate: checkedAddress(delegate!),
        authority: checkedAddress(authority!), amount: data.amount, checked: false, mint: null, decimals: null} as const);
    }
    case Token2022Instruction.ApproveChecked: {
      const data = exact(getApproveCheckedInstructionDataDecoder(), getApproveCheckedInstructionDataEncoder(), instruction.data);
      const [source, mint, delegate, authority] = accounts(list, 4);
      return Object.freeze({program, kind: 'approve', source: checkedAddress(source!), delegate: checkedAddress(delegate!),
        authority: checkedAddress(authority!), amount: data.amount, checked: true, mint: checkedAddress(mint!),
        decimals: data.decimals} as const);
    }
    case Token2022Instruction.Revoke: {
      exact(getRevokeInstructionDataDecoder(), getRevokeInstructionDataEncoder(), instruction.data);
      const [source, authority] = accounts(list, 2);
      return Object.freeze({program, kind: 'revoke', source: checkedAddress(source!),
        authority: checkedAddress(authority!)} as const);
    }
    case Token2022Instruction.CloseAccount: {
      exact(getCloseAccountInstructionDataDecoder(), getCloseAccountInstructionDataEncoder(), instruction.data);
      const [account, destination, authority] = accounts(list, 3);
      return Object.freeze({program, kind: 'close_account', account: checkedAddress(account!),
        destination: checkedAddress(destination!), authority: checkedAddress(authority!)} as const);
    }
    case Token2022Instruction.SyncNative: {
      exact(getSyncNativeInstructionDataDecoder(), getSyncNativeInstructionDataEncoder(), instruction.data);
      const [account] = accounts(list, 1);
      return Object.freeze({program, kind: 'sync_native', account: checkedAddress(account!)} as const);
    }
    case Token2022Instruction.InitializeAccount: {
      exact(getInitializeAccountInstructionDataDecoder(), getInitializeAccountInstructionDataEncoder(), instruction.data);
      const [account, mint, owner] = accounts(list, 4);
      return Object.freeze({program, kind: 'initialize_account', variant: 1, account: checkedAddress(account!),
        mint: checkedAddress(mint!), owner: checkedAddress(owner!)} as const);
    }
    case Token2022Instruction.InitializeAccount2: {
      const data = exact(getInitializeAccount2InstructionDataDecoder(), getInitializeAccount2InstructionDataEncoder(), instruction.data);
      const [account, mint] = accounts(list, 3);
      return Object.freeze({program, kind: 'initialize_account', variant: 2, account: checkedAddress(account!),
        mint: checkedAddress(mint!), owner: checkedAddress(data.owner)} as const);
    }
    case Token2022Instruction.InitializeAccount3: {
      const data = exact(getInitializeAccount3InstructionDataDecoder(), getInitializeAccount3InstructionDataEncoder(), instruction.data);
      const [account, mint] = accounts(list, 2);
      return Object.freeze({program, kind: 'initialize_account', variant: 3, account: checkedAddress(account!),
        mint: checkedAddress(mint!), owner: checkedAddress(data.owner)} as const);
    }
    case Token2022Instruction.InitializeImmutableOwner: {
      exact(getInitializeImmutableOwnerInstructionDataDecoder(), getInitializeImmutableOwnerInstructionDataEncoder(), instruction.data);
      const [account] = accounts(list, 1);
      return Object.freeze({program, kind: 'initialize_immutable_owner', account: checkedAddress(account!)} as const);
    }
    default:
      // Minting, burning, authority changes, freezing, fee withdrawal and every
      // confidential-transfer instruction stay outside a reviewable swap.
      return fail('UNSUPPORTED_INSTRUCTION');
  }
}

function sameBytes(left: Uint8Array, right: Uint8Array): boolean {
  return left.length === right.length && left.every((byte, index) => byte === right[index]);
}

function readU64(data: Uint8Array, offset: number): bigint {
  let value = 0n;
  for (let index = 7; index >= 0; index -= 1) value = (value << 8n) | BigInt(data[offset + index]!);
  return value;
}

/**
 * Jupiter's current ExactIn layout, verified against its mainnet Anchor IDL
 * C88XWfp26heEmDkmfSzeXP7Fd7GQJ2j9dDTUsyiZbUTa (2026-09-25).
 * V2 moves amounts ahead of the route vector and widens platform fees to u16.
 * Positive-slippage fees and redirected destinations remain unsupported.
 */
function decodeJupiterRouteV2(instruction: DecodableInstruction): DecodedInstruction {
  const {data, accountAddresses: list} = instruction;
  if (data.length < 39 || list.length < 10) return fail('INSTRUCTION_INVALID');
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const inAmount = readU64(data, 8);
  const quotedOutAmount = readU64(data, 16);
  const slippageBps = view.getUint16(24, true);
  const platformFeeBps = view.getUint16(26, true);
  const positiveSlippageBps = view.getUint16(28, true);
  const routePlanStepCount = view.getUint32(30, true);
  if (inAmount <= 0n || quotedOutAmount <= 0n || slippageBps > 10_000 || platformFeeBps > 10_000 ||
      routePlanStepCount < 1 || routePlanStepCount > MAX_ROUTE_PLAN_STEPS ||
      data.length < 34 + routePlanStepCount * 5) return fail('INSTRUCTION_INVALID');
  if (positiveSlippageBps !== 0) return fail('UNSUPPORTED_INSTRUCTION');
  const [userTransferAuthority, userSourceTokenAccount, userDestinationTokenAccount, sourceMint,
    destinationMint, tokenProgram, destinationTokenProgram, alternateDestination, eventAuthority, programSlot] = list;
  if (programSlot !== KNOWN_PROGRAMS.jupiterV6 || eventAuthority !== 'D8cy77BBepLMngZx6ZukaTff5hCt1HrWyKk3Hnd9oitf' ||
      alternateDestination !== KNOWN_PROGRAMS.jupiterV6) return fail('INSTRUCTION_INVALID');
  // With a nonzero platform fee, the first remaining account is its recipient.
  const platformFeeAccount = platformFeeBps > 0 ? list[10] : null;
  if (platformFeeAccount === undefined || platformFeeAccount === KNOWN_PROGRAMS.jupiterV6) return fail('INSTRUCTION_INVALID');
  const routeAccounts = list.slice(platformFeeBps > 0 ? 11 : 10);
  if (routeAccounts.length < 1 || routeAccounts.length > MAX_ROUTE_ACCOUNTS) return fail('INSTRUCTION_INVALID');
  return Object.freeze({program: 'jupiter_v6', kind: 'route_v2',
    userTransferAuthority: walletAddress(userTransferAuthority!),
    userSourceTokenAccount: checkedAddress(userSourceTokenAccount!),
    userDestinationTokenAccount: checkedAddress(userDestinationTokenAccount!),
    sourceMint: checkedAddress(sourceMint!), destinationMint: checkedAddress(destinationMint!),
    tokenProgram: checkedAddress(tokenProgram!), destinationTokenProgram: checkedAddress(destinationTokenProgram!),
    programAuthority: null, programSourceTokenAccount: null, programDestinationTokenAccount: null,
    token2022Program: null, eventAuthority: checkedAddress(eventAuthority!), platformFeeAccount,
    routeAccounts: Object.freeze(routeAccounts), inAmount, quotedOutAmount, slippageBps, platformFeeBps, routePlanStepCount});
}

function decodeJupiter(instruction: DecodableInstruction): DecodedInstruction {
  const data = instruction.data;
  if (data.length < 8) return fail('INSTRUCTION_INVALID');
  const discriminator = data.subarray(0, 8);
  if (sameBytes(discriminator, JUPITER_DISCRIMINATORS.route_v2)) return decodeJupiterRouteV2(instruction);
  const shared = sameBytes(discriminator, JUPITER_DISCRIMINATORS.shared_accounts_route);
  if (!shared && !sameBytes(discriminator, JUPITER_DISCRIMINATORS.route)) {
    // Exact-out, token-ledger and every unknown entry point is out of scope.
    return fail('UNSUPPORTED_INSTRUCTION');
  }
  const header = shared ? 9 : 8;
  if (data.length < header + 4 + JUPITER_TAIL_BYTES) return fail('INSTRUCTION_INVALID');
  const routePlanStepCount = data[header]! | (data[header + 1]! << 8) | (data[header + 2]! << 16) | (data[header + 3]! << 24);
  if (routePlanStepCount < 1 || routePlanStepCount > MAX_ROUTE_PLAN_STEPS) return fail('INSTRUCTION_INVALID');
  // The route plan is variable length, so the four trailing arguments are read
  // from the end of the data: in_amount, quoted_out_amount, slippage, fee bps.
  const tail = data.length - JUPITER_TAIL_BYTES;
  const inAmount = readU64(data, tail);
  const quotedOutAmount = readU64(data, tail + 8);
  const slippageBps = data[tail + 16]! | (data[tail + 17]! << 8);
  const platformFeeBps = data[tail + 18]!;
  if (inAmount <= 0n || quotedOutAmount <= 0n || slippageBps > 10_000) return fail('INSTRUCTION_INVALID');

  const list = instruction.accountAddresses;
  const fixed = shared ? 13 : 9;
  if (list.length < fixed) return fail('INSTRUCTION_INVALID');
  const routeAccounts = list.slice(fixed);
  if (routeAccounts.length > MAX_ROUTE_ACCOUNTS) return fail('INSTRUCTION_INVALID');
  // An optional account is absent when its slot holds the program address itself.
  const optional = (value: string | undefined) =>
    value === undefined ? fail('INSTRUCTION_INVALID') : value === KNOWN_PROGRAMS.jupiterV6 ? null : checkedAddress(value);
  const common = {
    program: 'jupiter_v6', routeAccounts: Object.freeze(routeAccounts.map(value => checkedAddress(value))),
    inAmount, quotedOutAmount, slippageBps, platformFeeBps, routePlanStepCount,
  } as const;
  if (shared) {
    const [tokenProgram, programAuthority, userTransferAuthority, sourceTokenAccount, programSourceTokenAccount,
      programDestinationTokenAccount, destinationTokenAccount, sourceMint, destinationMint, platformFeeAccount,
      token2022Program, eventAuthority, programSlot] = list;
    if (programSlot !== KNOWN_PROGRAMS.jupiterV6) return fail('INSTRUCTION_INVALID');
    return Object.freeze({
      ...common, kind: 'shared_accounts_route', tokenProgram: checkedAddress(tokenProgram!),
      programAuthority: checkedAddress(programAuthority!), userTransferAuthority: walletAddress(userTransferAuthority!),
      userSourceTokenAccount: checkedAddress(sourceTokenAccount!),
      userDestinationTokenAccount: checkedAddress(destinationTokenAccount!),
      programSourceTokenAccount: checkedAddress(programSourceTokenAccount!),
      programDestinationTokenAccount: checkedAddress(programDestinationTokenAccount!),
      sourceMint: checkedAddress(sourceMint!), destinationMint: checkedAddress(destinationMint!),
      platformFeeAccount: optional(platformFeeAccount), token2022Program: optional(token2022Program),
      eventAuthority: checkedAddress(eventAuthority!),
    } as const);
  }
  const [tokenProgram, userTransferAuthority, userSourceTokenAccount, userDestinationTokenAccount,
    destinationTokenAccount, destinationMint, platformFeeAccount, eventAuthority, programSlot] = list;
  if (programSlot !== KNOWN_PROGRAMS.jupiterV6) return fail('INSTRUCTION_INVALID');
  void destinationTokenAccount;
  return Object.freeze({
    ...common, kind: 'route', tokenProgram: checkedAddress(tokenProgram!),
    programAuthority: null, userTransferAuthority: walletAddress(userTransferAuthority!),
    userSourceTokenAccount: checkedAddress(userSourceTokenAccount!),
    userDestinationTokenAccount: checkedAddress(userDestinationTokenAccount!),
    programSourceTokenAccount: null, programDestinationTokenAccount: null, sourceMint: null,
    destinationMint: checkedAddress(destinationMint!), platformFeeAccount: optional(platformFeeAccount),
    token2022Program: null, eventAuthority: checkedAddress(eventAuthority!),
  } as const);
}

export function decodeInstruction(instruction: DecodableInstruction): DecodedInstruction {
  const checked = validated(instruction);
  switch (checked.programAddress) {
    case KNOWN_PROGRAMS.system: return decodeSystem(checked);
    case KNOWN_PROGRAMS.computeBudget: return decodeComputeBudget(checked);
    case KNOWN_PROGRAMS.associatedToken: return decodeAssociatedToken(checked);
    case KNOWN_PROGRAMS.token: return decodeTokenProgram(checked, 'token');
    case KNOWN_PROGRAMS.token2022: return decodeTokenProgram(checked, 'token_2022');
    case KNOWN_PROGRAMS.jupiterV6: return decodeJupiter(checked);
    case KNOWN_PROGRAMS.memo: {
      if (checked.data.length < 1 || checked.data.length > MAX_MEMO_BYTES) return fail('INSTRUCTION_INVALID');
      return Object.freeze({program: 'memo', kind: 'memo', byteLength: checked.data.length} as const);
    }
    default: return fail('UNSUPPORTED_PROGRAM');
  }
}
