import { createHash } from 'node:crypto';
import { getCompiledTransactionMessageDecoder, getTransactionDecoder } from '@solana/kit';
import type { ReadonlyUint8Array } from '@solana/kit';
import { findStockTradingAssetByMint } from './stock-trading-catalog.js';
import { JUPITER_QUOTE_ASSETS } from './jupiter-quote-reader.js';
import { BoundedSolanaRpc } from './solana-rpc-client.js';
import { decodeInstruction, InstructionDecodeError, KNOWN_PROGRAMS } from './solana-instruction-decoders.js';
import type { DecodableInstruction, DecodedInstruction } from './solana-instruction-decoders.js';
import { AccountStateError, decodeAccountState, deriveAssociatedTokenAddress, parseObservedAccount,
  summarizeObservedAccount } from './solana-account-state.js';
import type { DecodedAccountState, ObservedAccount, ObservedAccountSummary, TokenProgramKind } from './solana-account-state.js';
import { STOCK_DRAFT_MAINNET_GENESIS, StockOrderDraftError, copyStockDraftBytesForReview } from './stock-order-draft.js';
import type { StockDraftBinding, StockDraftStructuralInspection, StockOrderDraft } from './stock-order-draft.js';
import type { ResolvedStockTransactionAccounts } from './stock-order-lookup-resolver.js';

/**
 * Gate 5 of the unsigned stock-order review: identify every program, decode
 * every top-level instruction and observe mint/program identities at finalized
 * commitment, then refresh the taker's balances at confirmed commitment. The
 * result describes what the transaction would do and
 * what the accounts look like right now. It makes no judgement about whether
 * those effects match the approved candidate (gate 6), runs no simulation,
 * signs nothing and sends nothing. The RPC allowlist is exactly
 * `getGenesisHash` and `getMultipleAccounts`.
 */
export type StockOrderSemanticsErrorCode =
  | 'SEMANTICS_CONFIGURATION_INVALID'
  | 'SEMANTICS_INPUT_INVALID'
  | 'SEMANTICS_STRUCTURE_MISMATCH'
  | 'SEMANTICS_DRAFT_EXPIRED'
  | 'SEMANTICS_WRONG_NETWORK'
  | 'SEMANTICS_RPC_TIMEOUT'
  | 'SEMANTICS_RPC_UNAVAILABLE'
  | 'SEMANTICS_RPC_RESPONSE_INVALID'
  | 'SEMANTICS_PROGRAM_UNSUPPORTED'
  | 'SEMANTICS_INSTRUCTION_UNSUPPORTED'
  | 'SEMANTICS_INSTRUCTION_INVALID'
  | 'SEMANTICS_PROGRAM_NOT_EXECUTABLE'
  | 'SEMANTICS_ACCOUNT_STATE_INVALID'
  | 'SEMANTICS_OBSERVATION_INCONSISTENT';

export class StockOrderSemanticsError extends Error {
  constructor(readonly code: StockOrderSemanticsErrorCode) {
    super('The stock order semantics could not be reviewed.');
    this.name = 'StockOrderSemanticsError';
  }
}
const fail = (code: StockOrderSemanticsErrorCode): never => { throw new StockOrderSemanticsError(code); };

/** JSON-safe shadow of a decoder result: every bigint becomes a decimal string. */
export type JsonSafe<T> = T extends bigint ? string
  : T extends readonly (infer U)[] ? readonly JsonSafe<U>[]
  : T extends object ? {readonly [K in keyof T]: JsonSafe<T[K]>}
  : T;
export type ReviewableInstruction = JsonSafe<DecodedInstruction>;
export type ReviewableAccountState = JsonSafe<DecodedAccountState>;

export interface StockOrderSemanticInstruction {
  readonly instructionIndex: number;
  readonly programAddress: string;
  readonly programName: keyof typeof KNOWN_PROGRAMS;
  readonly accountAddresses: readonly string[];
  readonly dataLengthBytes: number;
  readonly dataSha256: string;
  readonly decoded: ReviewableInstruction;
}

export interface StockOrderSemanticAccount {
  readonly accountIndex: number;
  readonly address: string;
  readonly signer: boolean;
  readonly writable: boolean;
  readonly source: 'static' | 'lookup_table';
  readonly observation: ObservedAccountSummary;
  readonly state: ReviewableAccountState;
}

export interface StockOrderCandidateAccounts {
  readonly taker: string;
  readonly inputMint: string;
  readonly outputMint: string;
  readonly inputTokenProgram: TokenProgramKind;
  readonly outputTokenProgram: TokenProgramKind;
  readonly takerInputAssociatedAccount: string;
  readonly takerOutputAssociatedAccount: string;
  readonly takerWrappedSolAssociatedAccount: string;
}

export interface StockOrderSemantics {
  readonly schemaVersion: 1;
  readonly kind: 'solana_stock_order_semantics';
  readonly network: 'solana:mainnet-beta';
  readonly genesisHash: typeof STOCK_DRAFT_MAINNET_GENESIS;
  /** Commitment of the wallet balances used for reconciliation and simulation. */
  readonly commitment: 'confirmed';
  readonly identityCommitment: 'finalized';
  readonly identityObservationSlot: string;
  readonly transactionHash: string;
  readonly transactionMessageHash: string;
  readonly draftBindingHash: string;
  readonly candidateTermsHash: string;
  readonly readStartedAt: string;
  readonly observedAt: string;
  readonly observationSlot: string;
  readonly rpcApiVersion: string | null;
  readonly candidate: StockOrderCandidateAccounts;
  readonly instructions: readonly StockOrderSemanticInstruction[];
  readonly accounts: readonly StockOrderSemanticAccount[];
  readonly programs: readonly {readonly address: string; readonly name: keyof typeof KNOWN_PROGRAMS; readonly owner: string}[];
  readonly computeBudget: Readonly<{
    readonly unitLimit: number | null;
    readonly unitPriceMicroLamports: string | null;
    readonly heapFrameBytes: number | null;
    readonly loadedAccountsDataSizeLimitBytes: number | null;
  }>;
  readonly feeEstimate: Readonly<{
    readonly signatureCount: 1;
    readonly baseLamports: '5000';
    readonly priorityLamportsUpperBound: string;
    readonly computeUnitsAssumed: number;
    readonly totalLamportsUpperBound: string;
    readonly basis: 'base_fee_plus_priority_upper_bound_excluding_rent';
  }>;
  readonly provenance: Readonly<{
    readonly rpcMethods: readonly string[];
    readonly accountReadChunks: number;
    readonly accountsObserved: number;
    readonly retries: 0;
    readonly cacheUsed: false;
    readonly digestSha256: string;
  }>;
  readonly assessment: Readonly<{
    readonly status: 'semantics_decoded_but_unreconciled';
    readonly clusterGenesis: 'verified';
    readonly programOwnership: 'verified_executable';
    readonly instructionSemantics: 'decoded';
    readonly accountState: 'observed_point_in_time';
    readonly accountStateFreshness: 'point_in_time_only';
    readonly revalidationRequired: true;
    readonly transactionTerms: 'unverified';
    readonly simulation: 'not_run';
    readonly approvable: false;
    readonly readyForSimulation: false;
    readonly signingEnabled: false;
    readonly broadcastEnabled: false;
    readonly financialOperationsEnabled: false;
  }>;
}

export interface StockOrderSemanticsInput {
  readonly draft: StockOrderDraft;
  readonly binding: StockDraftBinding;
  readonly structure: StockDraftStructuralInspection;
  readonly resolvedAccounts: ResolvedStockTransactionAccounts;
  /** Server-observed confirmed slot; never a client-supplied balance assertion. */
  readonly minContextSlot?: number;
}

export interface StockOrderSemanticsReaderOptions {
  readonly rpcUrl: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
}

type RpcMethod = 'getGenesisHash' | 'getMultipleAccounts';
const RPC_ERRORS = Object.freeze({
  configuration: () => new StockOrderSemanticsError('SEMANTICS_CONFIGURATION_INVALID'),
  timeout: () => new StockOrderSemanticsError('SEMANTICS_RPC_TIMEOUT'),
  unavailable: () => new StockOrderSemanticsError('SEMANTICS_RPC_UNAVAILABLE'),
  responseInvalid: () => new StockOrderSemanticsError('SEMANTICS_RPC_RESPONSE_INVALID'),
  methodNotAllowed: () => new StockOrderSemanticsError('SEMANTICS_CONFIGURATION_INVALID'),
});
const ACCOUNTS_PER_READ = 100;
const BASE_FEE_LAMPORTS = 5_000n;
const DEFAULT_COMPUTE_UNITS_PER_INSTRUCTION = 200_000;
const MAX_COMPUTE_UNITS = 1_400_000;
const sha256 = (value: Uint8Array | string) => createHash('sha256').update(value).digest('hex');

function jsonSafe<T>(value: T): JsonSafe<T> {
  if (typeof value === 'bigint') return value.toString() as JsonSafe<T>;
  if (Array.isArray(value)) return Object.freeze(value.map(item => jsonSafe(item))) as JsonSafe<T>;
  if (value !== null && typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value)) out[key] = jsonSafe(item);
    return Object.freeze(out) as JsonSafe<T>;
  }
  return value as JsonSafe<T>;
}

function programName(address: string): keyof typeof KNOWN_PROGRAMS {
  for (const [name, known] of Object.entries(KNOWN_PROGRAMS)) {
    if (known === address) return name as keyof typeof KNOWN_PROGRAMS;
  }
  return fail('SEMANTICS_PROGRAM_UNSUPPORTED');
}

function tokenProgramFor(mint: string): TokenProgramKind {
  const stock = findStockTradingAssetByMint(mint);
  if (stock) return stock.tokenProgram;
  if (mint === JUPITER_QUOTE_ASSETS.USDC.mint || mint === JUPITER_QUOTE_ASSETS.SOL.mint) return 'token';
  return fail('SEMANTICS_INPUT_INVALID');
}

function chunk<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let index = 0; index < items.length; index += size) out.push(items.slice(index, index + size));
  return out;
}

export class SolanaMainnetStockOrderSemanticsReader {
  readonly #rpc: BoundedSolanaRpc<RpcMethod, StockOrderSemanticsError>;
  readonly #now: () => number;

  constructor(options: StockOrderSemanticsReaderOptions) {
    if (options === null || typeof options !== 'object' || (options.now !== undefined && typeof options.now !== 'function')) {
      fail('SEMANTICS_CONFIGURATION_INVALID');
    }
    this.#rpc = new BoundedSolanaRpc<RpcMethod, StockOrderSemanticsError>({
      rpcUrl: options.rpcUrl, methods: ['getGenesisHash', 'getMultipleAccounts'], errors: RPC_ERRORS,
      // Real routes include executable ATA/Memo binaries; their base64 data alone exceeds 256 KiB.
      maxBodyBytes: 1_048_576,
      ...(options.fetch ? {fetch: options.fetch} : {}), ...(options.timeoutMs !== undefined ? {timeoutMs: options.timeoutMs} : {}),
    });
    this.#now = options.now ?? Date.now;
  }

  async read(input: StockOrderSemanticsInput): Promise<StockOrderSemantics> {
    const {draft, binding, structure, resolvedAccounts, minContextSlot} = validateInput(input);
    const summary = draft.summary;
    const readStartedAt = new Date(this.#now()).toISOString();
    // Re-checks account, exact identity and both expiry constraints; a stale draft never reaches RPC.
    let bytes: Uint8Array;
    try {
      bytes = await copyStockDraftBytesForReview(draft, binding);
    } catch (error) {
      if (error instanceof StockOrderDraftError && error.code === 'STOCK_DRAFT_EXPIRED') return fail('SEMANTICS_DRAFT_EXPIRED');
      return fail('SEMANTICS_STRUCTURE_MISMATCH');
    }
    const addressOf = new Map<number, string>();
    for (const entry of resolvedAccounts.accountIndexMap) addressOf.set(entry.accountIndex, entry.address);
    const decodable = decodeCompiledInstructions(bytes, structure, addressOf);
    const instructions = decodable.map((instruction, instructionIndex): StockOrderSemanticInstruction => {
      const name = programName(instruction.programAddress);
      let decoded: DecodedInstruction;
      try {
        decoded = decodeInstruction(instruction);
      } catch (error) {
        if (error instanceof InstructionDecodeError) {
          return fail(error.code === 'UNSUPPORTED_PROGRAM' ? 'SEMANTICS_PROGRAM_UNSUPPORTED'
            : error.code === 'UNSUPPORTED_INSTRUCTION' ? 'SEMANTICS_INSTRUCTION_UNSUPPORTED' : 'SEMANTICS_INSTRUCTION_INVALID');
        }
        return fail('SEMANTICS_INSTRUCTION_INVALID');
      }
      const structural = structure.instructions[instructionIndex];
      if (structural === undefined) return fail('SEMANTICS_STRUCTURE_MISMATCH');
      return Object.freeze({
        instructionIndex, programAddress: instruction.programAddress, programName: name,
        accountAddresses: Object.freeze([...instruction.accountAddresses]),
        dataLengthBytes: structural.dataLengthBytes, dataSha256: structural.dataSha256, decoded: jsonSafe(decoded),
      });
    });

    const candidate = await candidateAccounts(summary.taker, summary.input.mint, summary.output.mint);
    const addresses = [...new Set([
      ...resolvedAccounts.accountIndexMap.map(entry => entry.address),
      candidate.takerInputAssociatedAccount, candidate.takerOutputAssociatedAccount,
      candidate.inputMint, candidate.outputMint,
    ])];

    const genesis = await this.#rpc.call('getGenesisHash', []);
    if (genesis.result !== STOCK_DRAFT_MAINNET_GENESIS) return fail('SEMANTICS_WRONG_NETWORK');
    const observed = new Map<string, ObservedAccount>();
    let observationSlot: string | null = null;
    let apiVersion: string | null = null;
    const chunks = chunk(addresses, ACCOUNTS_PER_READ);
    for (const part of chunks) {
      const configuration: Record<string, unknown> = {encoding: 'base64', commitment: 'finalized'};
      if (observationSlot !== null) configuration['minContextSlot'] = Number(observationSlot);
      const outcome = await this.#rpc.call('getMultipleAccounts', [part, configuration]);
      const record = outcome.result as {value?: unknown};
      const values = record !== null && typeof record === 'object' ? record.value : undefined;
      if (!Array.isArray(values) || values.length !== part.length || outcome.contextSlot === null) {
        return fail('SEMANTICS_RPC_RESPONSE_INVALID');
      }
      if (observationSlot !== null && BigInt(outcome.contextSlot) < BigInt(observationSlot)) return fail('SEMANTICS_OBSERVATION_INCONSISTENT');
      observationSlot = outcome.contextSlot; apiVersion = outcome.apiVersion;
      part.forEach((address, index) => {
        try { observed.set(address, parseObservedAccount(address, values[index])); }
        catch (error) {
          if (error instanceof AccountStateError) return fail('SEMANTICS_RPC_RESPONSE_INVALID');
          throw error;
        }
      });
    }
    if (observationSlot === null) return fail('SEMANTICS_RPC_RESPONSE_INVALID');
    const identityObservationSlot = observationSlot;
    // A just-confirmed buy may not exist in finalized state yet. Refresh only
    // the taker's canonical accounts; issuer mints and program identities retain
    // their finalized observations. Reconciliation still validates every owner,
    // mint, freeze state, delegate, movement, amount and fee as before.
    const walletAddresses = [...new Set([candidate.taker, candidate.takerInputAssociatedAccount,
      candidate.takerOutputAssociatedAccount, candidate.takerWrappedSolAssociatedAccount])]
      .filter(address => addresses.includes(address));
    const walletFloor = Math.max(Number(identityObservationSlot), minContextSlot ?? 0);
    const walletOutcome = await this.#rpc.call('getMultipleAccounts', [walletAddresses,
      {encoding: 'base64', commitment: 'confirmed', minContextSlot: walletFloor}]);
    const walletValues = (walletOutcome.result as {value?: unknown} | null)?.value;
    if (!Array.isArray(walletValues) || walletValues.length !== walletAddresses.length || walletOutcome.contextSlot === null) {
      return fail('SEMANTICS_RPC_RESPONSE_INVALID');
    }
    if (BigInt(walletOutcome.contextSlot) < BigInt(walletFloor)) return fail('SEMANTICS_OBSERVATION_INCONSISTENT');
    walletAddresses.forEach((address, index) => {
      try { observed.set(address, parseObservedAccount(address, walletValues[index])); }
      catch (error) {
        if (error instanceof AccountStateError) return fail('SEMANTICS_RPC_RESPONSE_INVALID');
        throw error;
      }
    });
    observationSlot = walletOutcome.contextSlot; apiVersion = walletOutcome.apiVersion;
    const observedAt = new Date(this.#now()).toISOString();

    const states = new Map<string, DecodedAccountState>();
    for (const [address, account] of observed) {
      try { states.set(address, decodeAccountState(account)); }
      catch (error) {
        if (error instanceof AccountStateError) return fail('SEMANTICS_ACCOUNT_STATE_INVALID');
        throw error;
      }
    }
    const programs = [...new Set(instructions.map(instruction => instruction.programAddress))].map(address => {
      const state = states.get(address);
      if (state === undefined || state.kind !== 'program') return fail('SEMANTICS_PROGRAM_NOT_EXECUTABLE');
      return Object.freeze({address, name: programName(address), owner: state.owner});
    });
    const accounts = resolvedAccounts.accountIndexMap.map((entry): StockOrderSemanticAccount => {
      const account = observed.get(entry.address);
      const state = states.get(entry.address);
      if (account === undefined || state === undefined) return fail('SEMANTICS_OBSERVATION_INCONSISTENT');
      return Object.freeze({
        accountIndex: entry.accountIndex, address: entry.address, signer: entry.signer, writable: entry.writable,
        source: entry.source, observation: summarizeObservedAccount(account), state: jsonSafe(state),
      });
    });
    const extra = [candidate.takerInputAssociatedAccount, candidate.takerOutputAssociatedAccount, candidate.inputMint, candidate.outputMint]
      .filter(address => !resolvedAccounts.accountIndexMap.some(entry => entry.address === address));
    const supplementalAccounts = extra.map((address, offset): StockOrderSemanticAccount => {
      const account = observed.get(address);
      const state = states.get(address);
      if (account === undefined || state === undefined) return fail('SEMANTICS_OBSERVATION_INCONSISTENT');
      return Object.freeze({
        accountIndex: resolvedAccounts.accountIndexMap.length + offset, address, signer: false, writable: false,
        source: 'static' as const, observation: summarizeObservedAccount(account), state: jsonSafe(state),
      });
    });

    const computeBudget = readComputeBudget(instructions);
    const feeEstimate = estimateFee(computeBudget, instructions.length);
    const digestInput = JSON.stringify({
      transactionMessageHash: structure.transactionMessageHash, identityObservationSlot, observationSlot,
      identityCommitment: 'finalized', commitment: 'confirmed', instructions, accounts, supplementalAccounts, programs,
    });
    return Object.freeze({
      schemaVersion: 1, kind: 'solana_stock_order_semantics', network: 'solana:mainnet-beta',
      genesisHash: STOCK_DRAFT_MAINNET_GENESIS, commitment: 'confirmed', identityCommitment: 'finalized', identityObservationSlot,
      transactionHash: structure.transactionHash, transactionMessageHash: structure.transactionMessageHash,
      draftBindingHash: structure.draftBindingHash, candidateTermsHash: structure.candidateTermsHash,
      readStartedAt, observedAt, observationSlot, rpcApiVersion: apiVersion, candidate,
      instructions: Object.freeze(instructions), accounts: Object.freeze([...accounts, ...supplementalAccounts]),
      programs: Object.freeze(programs), computeBudget, feeEstimate,
      provenance: Object.freeze({
        rpcMethods: Object.freeze(['getGenesisHash', ...chunks.map(() => 'getMultipleAccounts'), 'getMultipleAccounts']),
        accountReadChunks: chunks.length + 1, accountsObserved: addresses.length, retries: 0, cacheUsed: false,
        digestSha256: sha256(digestInput),
      }),
      assessment: Object.freeze({
        status: 'semantics_decoded_but_unreconciled', clusterGenesis: 'verified', programOwnership: 'verified_executable',
        instructionSemantics: 'decoded', accountState: 'observed_point_in_time', accountStateFreshness: 'point_in_time_only',
        revalidationRequired: true, transactionTerms: 'unverified', simulation: 'not_run', approvable: false,
        readyForSimulation: false, signingEnabled: false, broadcastEnabled: false, financialOperationsEnabled: false,
      }),
    });
  }
}

function validateInput(input: StockOrderSemanticsInput): StockOrderSemanticsInput {
  if (input === null || typeof input !== 'object') return fail('SEMANTICS_INPUT_INVALID');
  if (input.minContextSlot !== undefined && (!Number.isSafeInteger(input.minContextSlot) || input.minContextSlot < 1)) {
    return fail('SEMANTICS_INPUT_INVALID');
  }
  const {draft, binding, structure, resolvedAccounts} = input;
  if (draft === null || typeof draft !== 'object' || binding === null || typeof binding !== 'object' ||
      structure === null || typeof structure !== 'object' || resolvedAccounts === null || typeof resolvedAccounts !== 'object') {
    return fail('SEMANTICS_INPUT_INVALID');
  }
  const summary = draft.summary;
  if (summary?.kind !== 'stock_order_draft' || structure.kind !== 'unsigned_solana_v0_structure' ||
      resolvedAccounts.kind !== 'solana_v0_resolved_account_indexes') {
    return fail('SEMANTICS_INPUT_INVALID');
  }
  if (structure.transactionMessageHash !== summary.transactionMessageHash ||
      structure.transactionHash !== summary.transactionHash ||
      structure.draftBindingHash !== summary.bindingHash ||
      structure.candidateTermsHash !== summary.userApproval.candidateTermsHash ||
      structure.requiredSigner.address !== summary.taker ||
      resolvedAccounts.transactionMessageHash !== summary.transactionMessageHash ||
      resolvedAccounts.transactionHash !== summary.transactionHash ||
      resolvedAccounts.assessment.status !== 'account_indexes_resolved_but_incomplete' ||
      resolvedAccounts.genesisHash !== STOCK_DRAFT_MAINNET_GENESIS ||
      resolvedAccounts.accountIndexMap.length !== structure.accountIndexSpace.total ||
      resolvedAccounts.accountIndexMap.some((entry, index) => entry.accountIndex !== index) ||
      binding.transactionMessageHash !== summary.transactionMessageHash || binding.bindingHash !== summary.bindingHash) {
    return fail('SEMANTICS_STRUCTURE_MISMATCH');
  }
  return input;
}

function decodeCompiledInstructions(bytes: Uint8Array, structure: StockDraftStructuralInspection,
  addressOf: ReadonlyMap<number, string>): DecodableInstruction[] {
  let compiled: {readonly instructions: readonly {readonly programAddressIndex: number;
    readonly accountIndices?: readonly number[] | undefined;
    readonly data?: ReadonlyUint8Array | undefined}[]};
  try {
    const transaction = getTransactionDecoder().decode(bytes);
    compiled = getCompiledTransactionMessageDecoder().decode(transaction.messageBytes);
  } catch {
    return fail('SEMANTICS_STRUCTURE_MISMATCH');
  }
  if (compiled.instructions.length !== structure.instructions.length) return fail('SEMANTICS_STRUCTURE_MISMATCH');
  return compiled.instructions.map((instruction, index) => {
    const structural = structure.instructions[index];
    const data = Uint8Array.from(instruction.data ?? new Uint8Array());
    const accountIndices = instruction.accountIndices ?? [];
    if (structural === undefined || structural.programAddressIndex !== instruction.programAddressIndex ||
        structural.dataLengthBytes !== data.byteLength || structural.dataSha256 !== sha256(data) ||
        structural.accountIndices.length !== accountIndices.length ||
        structural.accountIndices.some((value, position) => value !== accountIndices[position])) {
      return fail('SEMANTICS_STRUCTURE_MISMATCH');
    }
    const programAddress = addressOf.get(instruction.programAddressIndex);
    const accountAddresses = accountIndices.map(accountIndex => addressOf.get(accountIndex));
    if (programAddress === undefined || accountAddresses.some(address => address === undefined)) {
      return fail('SEMANTICS_STRUCTURE_MISMATCH');
    }
    return Object.freeze({programAddress, accountAddresses: Object.freeze(accountAddresses as string[]), data: Uint8Array.from(data)});
  });
}

async function candidateAccounts(taker: string, inputMint: string, outputMint: string): Promise<StockOrderCandidateAccounts> {
  const inputTokenProgram = tokenProgramFor(inputMint);
  const outputTokenProgram = tokenProgramFor(outputMint);
  try {
    const [takerInputAssociatedAccount, takerOutputAssociatedAccount, takerWrappedSolAssociatedAccount] = await Promise.all([
      deriveAssociatedTokenAddress(taker, inputMint, inputTokenProgram),
      deriveAssociatedTokenAddress(taker, outputMint, outputTokenProgram),
      deriveAssociatedTokenAddress(taker, JUPITER_QUOTE_ASSETS.SOL.mint, 'token'),
    ]);
    return Object.freeze({taker, inputMint, outputMint, inputTokenProgram, outputTokenProgram,
      takerInputAssociatedAccount, takerOutputAssociatedAccount, takerWrappedSolAssociatedAccount});
  } catch {
    return fail('SEMANTICS_INPUT_INVALID');
  }
}

function readComputeBudget(instructions: readonly StockOrderSemanticInstruction[]): StockOrderSemantics['computeBudget'] {
  let unitLimit: number | null = null;
  let unitPriceMicroLamports: string | null = null;
  let heapFrameBytes: number | null = null;
  let loadedAccountsDataSizeLimitBytes: number | null = null;
  for (const instruction of instructions) {
    const decoded = instruction.decoded;
    if (decoded.program !== 'compute_budget') continue;
    // The runtime rejects duplicate compute-budget instructions; so does this review.
    if (decoded.kind === 'set_compute_unit_limit') {
      if (unitLimit !== null) return fail('SEMANTICS_INSTRUCTION_INVALID');
      unitLimit = decoded.units;
    } else if (decoded.kind === 'set_compute_unit_price') {
      if (unitPriceMicroLamports !== null) return fail('SEMANTICS_INSTRUCTION_INVALID');
      unitPriceMicroLamports = decoded.microLamports;
    } else if (decoded.kind === 'request_heap_frame') {
      if (heapFrameBytes !== null) return fail('SEMANTICS_INSTRUCTION_INVALID');
      heapFrameBytes = decoded.bytes;
    } else if (decoded.kind === 'set_loaded_accounts_data_size_limit') {
      if (loadedAccountsDataSizeLimitBytes !== null) return fail('SEMANTICS_INSTRUCTION_INVALID');
      loadedAccountsDataSizeLimitBytes = decoded.bytes;
    }
  }
  return Object.freeze({unitLimit, unitPriceMicroLamports, heapFrameBytes, loadedAccountsDataSizeLimitBytes});
}

function estimateFee(computeBudget: StockOrderSemantics['computeBudget'], instructionCount: number): StockOrderSemantics['feeEstimate'] {
  const computeUnitsAssumed = computeBudget.unitLimit ??
    Math.min(MAX_COMPUTE_UNITS, DEFAULT_COMPUTE_UNITS_PER_INSTRUCTION * Math.max(1, instructionCount));
  const price = computeBudget.unitPriceMicroLamports === null ? 0n : BigInt(computeBudget.unitPriceMicroLamports);
  const priority = (BigInt(computeUnitsAssumed) * price + 999_999n) / 1_000_000n;
  return Object.freeze({
    signatureCount: 1, baseLamports: '5000', priorityLamportsUpperBound: priority.toString(), computeUnitsAssumed,
    totalLamportsUpperBound: (BASE_FEE_LAMPORTS + priority).toString(),
    basis: 'base_fee_plus_priority_upper_bound_excluding_rent',
  });
}
