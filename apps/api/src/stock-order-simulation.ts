import { createHash } from 'node:crypto';
import { BoundedSolanaRpc } from './solana-rpc-client.js';
import { AccountStateError, decodeAccountState, parseObservedAccount } from './solana-account-state.js';
import { KNOWN_PROGRAMS } from './solana-instruction-decoders.js';
import { STOCK_DRAFT_MAINNET_GENESIS, StockOrderDraftError, admitStockDraftForSimulation } from './stock-order-draft.js';
import type { StockDraftBinding, StockOrderDraft } from './stock-order-draft.js';
import type { StockOrderSemantics } from './stock-order-semantics.js';
import type { ReconciledStockOrderTerms } from './stock-order-terms-reconciliation.js';
import { reconciliationDigest } from './stock-order-terms-reconciliation.js';

/**
 * Gate 7 of the unsigned stock-order review: an isolated simulation boundary.
 * The unsigned bytes are submitted to `simulateTransaction` with signature
 * verification off and the bound blockhash kept, at confirmed commitment no
 * older than the reconciled wallet snapshot, and the returned post-state of
 * the taker, the source account and the destination account is compared with
 * the reconciled terms. The RPC allowlist is exactly `getGenesisHash` and
 * `simulateTransaction`; the class cannot express `sendTransaction`. A passing
 * simulation is evidence about a point in time, not consent, approval or
 * settlement, and it enables no signing.
 */
export type StockOrderSimulationErrorCode =
  | 'SIMULATION_CONFIGURATION_INVALID'
  | 'SIMULATION_INPUT_INVALID'
  | 'SIMULATION_EVIDENCE_MISMATCH'
  | 'SIMULATION_DRAFT_EXPIRED'
  | 'SIMULATION_WRONG_NETWORK'
  | 'SIMULATION_RPC_TIMEOUT'
  | 'SIMULATION_RPC_UNAVAILABLE'
  | 'SIMULATION_RPC_RESPONSE_INVALID'
  | 'SIMULATION_BLOCKHASH_EXPIRED'
  | 'SIMULATION_TRANSACTION_FAILED'
  | 'SIMULATION_COMPUTE_EXCEEDED'
  | 'SIMULATION_STATE_UNREADABLE'
  | 'SIMULATION_EFFECTS_MISMATCH'
  | 'SIMULATION_OBSERVATION_STALE';

export class StockOrderSimulationError extends Error {
  constructor(readonly code: StockOrderSimulationErrorCode, readonly failure: SimulationFailureSummary | null = null) {
    super('The stock order simulation did not confirm the reviewed terms.');
    this.name = 'StockOrderSimulationError';
  }
}
const fail = (code: StockOrderSimulationErrorCode, failure: SimulationFailureSummary | null = null): never => {
  throw new StockOrderSimulationError(code, failure);
};

/** Sanitized shape of a simulation error: kind and instruction index only, never log text. */
export interface SimulationFailureSummary {
  readonly kind: string;
  readonly instructionIndex: number | null;
  readonly customCode: number | null;
}

export interface StockOrderSimulation {
  readonly schemaVersion: 1;
  readonly kind: 'solana_stock_order_simulation';
  readonly network: 'solana:mainnet-beta';
  readonly genesisHash: typeof STOCK_DRAFT_MAINNET_GENESIS;
  readonly commitment: 'confirmed';
  readonly transactionHash: string;
  readonly transactionMessageHash: string;
  readonly draftBindingHash: string;
  readonly candidateTermsHash: string;
  readonly reconciliationDigestSha256: string;
  readonly simulationStartedAt: string;
  readonly observedAt: string;
  readonly simulationSlot: string;
  readonly rpcApiVersion: string | null;
  readonly request: Readonly<{
    readonly sigVerify: false;
    readonly replaceRecentBlockhash: false;
    readonly innerInstructions: false;
    /** Taker, source and destination, then the taker's preserved accounts and a closed wrapped-SOL account. */
    readonly accountAddresses: readonly string[];
    readonly minContextSlot: string;
  }>;
  readonly outcome: Readonly<{
    /** Null when the whole transaction ran; otherwise only the market maker's pending delivery (see settlement). */
    readonly error: SimulationFailureSummary | null;
    /** 'simulated': every reviewed effect ran. 'maker_delivers_at_fill': an RFQ maker that mints just
     * in time could not yet cover the fill; everything up to its transfer ran and the fill is atomic. */
    readonly settlement: 'simulated' | 'maker_delivers_at_fill';
    readonly unitsConsumed: string;
    readonly computeUnitLimit: number | null;
    readonly logLineCount: number;
    readonly logsSha256: string;
    readonly returnDataPresent: boolean;
  }>;
  readonly effects: Readonly<{
    readonly takerLamportsBefore: string;
    readonly takerLamportsAfter: string;
    readonly takerLamportsSpent: string;
    readonly sourceAmountBefore: string;
    readonly sourceAmountAfter: string;
    readonly inputSpentRaw: string;
    readonly destinationAmountBefore: string;
    readonly destinationAmountAfter: string;
    readonly outputReceivedRaw: string;
    readonly destinationCreated: boolean;
    readonly preservedAccountsUnchanged: number;
    readonly wrappedSolAccountClosed: boolean;
  }>;
  readonly terms: Readonly<{
    readonly inputAmountRaw: string;
    readonly minimumOutputAmountRaw: string;
    readonly totalLamportsUpperBound: string;
    readonly takerLamportsReturnUpperBound: string;
  }>;
  readonly provenance: Readonly<{
    readonly rpcMethods: readonly ['getGenesisHash', 'simulateTransaction'];
    readonly retries: 0;
    readonly cacheUsed: false;
    readonly digestSha256: string;
  }>;
  readonly assessment: Readonly<{
    readonly status: 'simulated_effects_match_reviewed_terms';
    readonly simulation: 'passed_point_in_time';
    readonly effectsMatchReviewedTerms: true;
    readonly revalidationRequired: true;
    readonly approvable: false;
    readonly userApproval: 'required';
    readonly signingEnabled: false;
    readonly broadcastEnabled: false;
    readonly financialOperationsEnabled: false;
  }>;
}

export interface StockOrderSimulationInput {
  readonly draft: StockOrderDraft;
  readonly binding: StockDraftBinding;
  readonly semantics: StockOrderSemantics;
  readonly reconciliation: ReconciledStockOrderTerms;
}

export interface StockOrderSimulatorOptions {
  readonly rpcUrl: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
}

type RpcMethod = 'getGenesisHash' | 'simulateTransaction';
const RPC_ERRORS = Object.freeze({
  configuration: () => new StockOrderSimulationError('SIMULATION_CONFIGURATION_INVALID'),
  timeout: () => new StockOrderSimulationError('SIMULATION_RPC_TIMEOUT'),
  unavailable: () => new StockOrderSimulationError('SIMULATION_RPC_UNAVAILABLE'),
  responseInvalid: () => new StockOrderSimulationError('SIMULATION_RPC_RESPONSE_INVALID'),
  methodNotAllowed: () => new StockOrderSimulationError('SIMULATION_CONFIGURATION_INVALID'),
});
const MAX_LOG_LINES = 10_000;
const sha256 = (value: string) => createHash('sha256').update(value).digest('hex');

function record(value: unknown): Record<string, unknown> | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const proto: unknown = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null ? value as Record<string, unknown> : null;
}

/** Reduces an RPC transaction error to a fixed, log-safe summary. */
function summarizeFailure(error: unknown): SimulationFailureSummary {
  if (typeof error === 'string' && /^[A-Za-z]{1,64}$/.test(error)) return Object.freeze({kind: error, instructionIndex: null, customCode: null});
  const wrapper = record(error);
  const instructionError = wrapper?.['InstructionError'];
  if (Array.isArray(instructionError) && instructionError.length === 2 && Number.isInteger(instructionError[0])) {
    const detail = instructionError[1];
    if (typeof detail === 'string' && /^[A-Za-z]{1,64}$/.test(detail)) {
      return Object.freeze({kind: `InstructionError:${detail}`, instructionIndex: instructionError[0] as number, customCode: null});
    }
    const custom = record(detail)?.['Custom'];
    if (Number.isInteger(custom)) {
      return Object.freeze({kind: 'InstructionError:Custom', instructionIndex: instructionError[0] as number, customCode: custom as number});
    }
    return Object.freeze({kind: 'InstructionError', instructionIndex: instructionError[0] as number, customCode: null});
  }
  return Object.freeze({kind: 'Unknown', instructionIndex: null, customCode: null});
}

function amount(value: string): bigint {
  if (!/^(?:0|[1-9][0-9]{0,38})$/.test(value)) return fail('SIMULATION_INPUT_INVALID');
  return BigInt(value);
}

function simulatedState(address: string, value: unknown) {
  try { return decodeAccountState(parseObservedAccount(address, value)); }
  catch (error) {
    if (error instanceof AccountStateError) return fail('SIMULATION_STATE_UNREADABLE');
    throw error;
  }
}

/**
 * Market makers for Ondo's tokens mint just in time: the maker creates the shares
 * only after the user has signed, so until then its output account cannot cover
 * the fill. Such a simulation is accepted only when it proves everything else:
 * the failure is the reviewed fill instruction, the taker's own transfer ran to
 * completion, and the one failure is the maker's transfer of the output for
 * insufficient funds, with nothing after it, while the observed maker account
 * holds less than the fill. The fill is atomic, so on chain the user receives
 * exactly the reviewed output or nothing moves.
 */
function makerDeliveryPending(semantics: StockOrderSemantics, reconciliation: ReconciledStockOrderTerms,
  failure: SimulationFailureSummary, logs: readonly string[]): {readonly outputAmount: bigint} | null {
  if (reconciliation.swap.variant !== 'rfq_fill' || failure.kind !== 'InstructionError:Custom' || failure.customCode !== 1 ||
      failure.instructionIndex !== reconciliation.swap.instructionIndex || reconciliation.effects.preservedAccounts.length > 0 ||
      reconciliation.effects.unwrappedWrappedSol !== null) return null;
  const fill = semantics.instructions.find(item => item.instructionIndex === reconciliation.swap.instructionIndex)?.decoded;
  if (fill === undefined || fill.program !== 'order_engine' || fill.taker !== reconciliation.swap.taker ||
      fill.outputAmount !== reconciliation.swap.quotedOutputAmountRaw || fill.inputAmount !== reconciliation.swap.inputAmountRaw) return null;
  const makerOutput = semantics.accounts.find(account => account.address === fill.makerOutputTokenAccount)?.state;
  if (makerOutput === undefined || makerOutput.kind !== 'token_account' || makerOutput.owner !== fill.maker ||
      makerOutput.mint !== fill.outputMint || BigInt(makerOutput.amount) >= BigInt(fill.outputAmount)) return null;
  const engine = KNOWN_PROGRAMS.orderEngine;
  const start = logs.indexOf(`Program ${engine} invoke [1]`);
  if (start < 0 || logs.lastIndexOf(`Program ${engine} invoke [1]`) !== start || logs[start + 1] !== 'Program log: Instruction: Fill') return null;
  let index = start + 2;
  // One token-program call at depth 2: its log lines, and whether it succeeded.
  const call = (program: string): {readonly ok: boolean; readonly lines: readonly string[]} | null => {
    if (logs[index] !== `Program ${program} invoke [2]`) return null;
    const lines: string[] = [];
    for (index += 1; index < logs.length; index += 1) {
      const line = logs[index]!;
      if (line === `Program ${program} success`) { index += 1; return {ok: true, lines}; }
      lines.push(line);
      if (line.startsWith(`Program ${program} failed: `)) { index += 1; return {ok: false, lines}; }
      if (!line.startsWith('Program log: ') && !line.startsWith(`Program ${program} consumed `)) return null;
    }
    return null;
  };
  const takerTransfer = call(fill.inputTokenProgram);
  if (takerTransfer === null || !takerTransfer.ok) return null;
  const makerTransfer = call(fill.outputTokenProgram);
  if (makerTransfer === null || makerTransfer.ok || !makerTransfer.lines.includes('Program log: Error: insufficient funds') ||
      makerTransfer.lines.at(-1) !== `Program ${fill.outputTokenProgram} failed: custom program error: 0x1`) return null;
  const rest = logs.slice(index);
  const engineFailed = `Program ${engine} failed: custom program error: 0x1`;
  if (!(rest.length === 1 && rest[0] === engineFailed) &&
      !(rest.length === 2 && rest[0]!.startsWith(`Program ${engine} consumed `) && rest[1] === engineFailed)) return null;
  return {outputAmount: BigInt(fill.outputAmount)};
}

/** Simulation reports an account closed in the transaction as an empty, zero-lamport system account. */
function closedAfterSimulation(state: ReturnType<typeof simulatedState>): boolean {
  return state.kind === 'missing' || (state.kind === 'system' && state.lamports === 0n);
}

function tokenAmount(address: string, value: unknown, expectedMint: string, expectedOwner: string,
  allowMissing: boolean): {readonly amount: bigint; readonly exists: boolean} {
  const state = simulatedState(address, value);
  if (allowMissing && closedAfterSimulation(state)) return {amount: 0n, exists: false};
  if (state.kind === 'missing') return fail('SIMULATION_STATE_UNREADABLE');
  if (state.kind !== 'token_account' || state.mint !== expectedMint || state.owner !== expectedOwner || state.state !== 'initialized') {
    return fail('SIMULATION_EFFECTS_MISMATCH');
  }
  return {amount: state.amount, exists: true};
}

export class SolanaMainnetStockOrderSimulator {
  readonly #rpc: BoundedSolanaRpc<RpcMethod, StockOrderSimulationError>;
  readonly #now: () => number;

  constructor(options: StockOrderSimulatorOptions) {
    if (options === null || typeof options !== 'object' || (options.now !== undefined && typeof options.now !== 'function')) {
      fail('SIMULATION_CONFIGURATION_INVALID');
    }
    this.#rpc = new BoundedSolanaRpc<RpcMethod, StockOrderSimulationError>({
      rpcUrl: options.rpcUrl, methods: ['getGenesisHash', 'simulateTransaction'], errors: RPC_ERRORS,
      ...(options.fetch ? {fetch: options.fetch} : {}), ...(options.timeoutMs !== undefined ? {timeoutMs: options.timeoutMs} : {}),
    });
    this.#now = options.now ?? Date.now;
  }

  async simulate(input: StockOrderSimulationInput): Promise<StockOrderSimulation> {
    if (input === null || typeof input !== 'object') return fail('SIMULATION_INPUT_INVALID');
    const {draft, binding, semantics, reconciliation} = input;
    if (draft?.summary?.kind !== 'stock_order_draft' || reconciliation?.kind !== 'stock_order_terms_reconciliation' ||
        semantics?.kind !== 'solana_stock_order_semantics' || binding === null || typeof binding !== 'object') {
      return fail('SIMULATION_INPUT_INVALID');
    }
    if (semantics.commitment !== 'confirmed' || semantics.identityCommitment !== 'finalized' ||
        reconciliation.semanticsDigestSha256 !== semantics.provenance.digestSha256 ||
        semantics.transactionMessageHash !== reconciliation.transactionMessageHash) {
      return fail('SIMULATION_EVIDENCE_MISMATCH');
    }
    const summary = draft.summary;
    if (reconciliation.transactionMessageHash !== summary.transactionMessageHash || reconciliation.transactionHash !== summary.transactionHash ||
        reconciliation.draftBindingHash !== summary.bindingHash || reconciliation.candidateTermsHash !== summary.userApproval.candidateTermsHash ||
        reconciliation.assessment.status !== 'terms_reconciled_but_unsimulated' || reconciliation.assessment.readyForSimulation !== true ||
        reconciliation.assessment.signingEnabled !== false || reconciliation.swap.taker !== summary.taker) {
      return fail('SIMULATION_EVIDENCE_MISMATCH');
    }
    const digest = reconciliationDigest(reconciliation);
    const simulationStartedAt = new Date(this.#now()).toISOString();
    let bytes: Uint8Array;
    try {
      bytes = await admitStockDraftForSimulation(draft, binding, {
        transactionMessageHash: reconciliation.transactionMessageHash, draftBindingHash: reconciliation.draftBindingHash,
        candidateTermsHash: reconciliation.candidateTermsHash, status: reconciliation.assessment.status,
        readyForSimulation: reconciliation.assessment.readyForSimulation,
      });
    } catch (error) {
      if (error instanceof StockOrderDraftError && error.code === 'STOCK_DRAFT_EXPIRED') return fail('SIMULATION_DRAFT_EXPIRED');
      return fail('SIMULATION_EVIDENCE_MISMATCH');
    }
    const taker = summary.taker;
    const source = reconciliation.swap.sourceTokenAccount;
    const destination = reconciliation.swap.destinationTokenAccount;
    const preserved = reconciliation.effects.preservedAccounts;
    const unwrapped = reconciliation.effects.unwrappedWrappedSol;
    const accountAddresses = Object.freeze([taker, source, destination, ...preserved.map(item => item.address),
      ...(unwrapped === null ? [] : [unwrapped.address])]);
    const minContextSlot = reconciliation.observationSlot;

    const genesis = await this.#rpc.call('getGenesisHash', []);
    if (genesis.result !== STOCK_DRAFT_MAINNET_GENESIS) return fail('SIMULATION_WRONG_NETWORK');
    const outcome = await this.#rpc.call('simulateTransaction', [Buffer.from(bytes).toString('base64'), {
      sigVerify: false, replaceRecentBlockhash: false, commitment: 'confirmed', encoding: 'base64',
      minContextSlot: Number(minContextSlot), innerInstructions: false,
      accounts: {encoding: 'base64', addresses: [...accountAddresses]},
    }]);
    const observedAt = new Date(this.#now()).toISOString();
    const result = record(outcome.result);
    const value = result === null ? null : record(result['value']);
    if (value === null || outcome.contextSlot === null || !Object.hasOwn(value, 'err')) return fail('SIMULATION_RPC_RESPONSE_INVALID');
    if (BigInt(outcome.contextSlot) < BigInt(minContextSlot)) return fail('SIMULATION_OBSERVATION_STALE');
    const logs = value['logs'];
    if (logs !== null && logs !== undefined && (!Array.isArray(logs) || logs.length > MAX_LOG_LINES || logs.some(line => typeof line !== 'string'))) {
      return fail('SIMULATION_RPC_RESPONSE_INVALID');
    }
    const logLines = Array.isArray(logs) ? logs as string[] : [];
    let failure: SimulationFailureSummary | null = null;
    let pendingDelivery: {readonly outputAmount: bigint} | null = null;
    if (value['err'] !== null) {
      failure = summarizeFailure(value['err']);
      if (failure.kind === 'BlockhashNotFound') return fail('SIMULATION_BLOCKHASH_EXPIRED', failure);
      pendingDelivery = makerDeliveryPending(semantics, reconciliation, failure, logLines);
      if (pendingDelivery === null) return fail('SIMULATION_TRANSACTION_FAILED', failure);
    }
    const unitsRaw = value['unitsConsumed'];
    const unitsConsumed = typeof unitsRaw === 'number' && Number.isSafeInteger(unitsRaw) && unitsRaw >= 0 ? BigInt(unitsRaw)
      : fail('SIMULATION_RPC_RESPONSE_INVALID');
    const computeUnitLimit = semantics.computeBudget.unitLimit;
    if (computeUnitLimit !== null && unitsConsumed > BigInt(computeUnitLimit)) return fail('SIMULATION_COMPUTE_EXCEEDED');
    const takerBefore = amount(reconciliation.accountState.taker.lamports);
    const sourceBefore = amount(reconciliation.accountState.source.amountRaw);
    const destinationBefore = reconciliation.accountState.destination.amountRaw === null ? 0n : amount(reconciliation.accountState.destination.amountRaw);
    const inputAmount = amount(reconciliation.swap.inputAmountRaw);
    const minimumOutput = amount(reconciliation.swap.minimumOutputAmountRaw);
    const totalUpperBound = amount(reconciliation.cost.totalLamportsUpperBound);
    const returnUpperBound = amount(reconciliation.cost.takerLamportsReturnUpperBound);
    if ((unwrapped === null) !== (returnUpperBound === 0n)) return fail('SIMULATION_EVIDENCE_MISMATCH');

    let takerAfter: bigint;
    let sourceAfter: bigint;
    let destinationAfter: bigint;
    if (pendingDelivery !== null) {
      // Nothing settled in simulation: the reviewed fill fixes both token amounts,
      // and the taker's SOL is held to the reviewed upper bound.
      takerAfter = takerBefore - totalUpperBound;
      sourceAfter = sourceBefore - inputAmount;
      destinationAfter = destinationBefore + pendingDelivery.outputAmount;
    } else {
      const accounts = value['accounts'];
      if (!Array.isArray(accounts) || accounts.length !== accountAddresses.length) return fail('SIMULATION_RPC_RESPONSE_INVALID');
      // Post-state of the accounts that carry the reviewed effects.
      try {
        const takerState = decodeAccountState(parseObservedAccount(taker, accounts[0]));
        if (takerState.kind !== 'system') return fail('SIMULATION_EFFECTS_MISMATCH');
        takerAfter = takerState.lamports;
      } catch (error) {
        if (error instanceof AccountStateError) return fail('SIMULATION_STATE_UNREADABLE');
        throw error;
      }
      sourceAfter = tokenAmount(source, accounts[1], reconciliation.swap.inputMint, taker, false).amount;
      destinationAfter = tokenAmount(destination, accounts[2], reconciliation.swap.outputMint, taker, false).amount;
      // A route may pass through the taker's other token accounts, never draw on them.
      preserved.forEach((item, index) => {
        if (tokenAmount(item.address, accounts[3 + index], item.mint, taker, true).amount !== amount(item.amountRaw)) {
          fail('SIMULATION_EFFECTS_MISMATCH');
        }
      });
      // The taker's existing wrapped SOL comes back as SOL: its account must be closed.
      if (unwrapped !== null && !closedAfterSimulation(simulatedState(unwrapped.address, accounts[accounts.length - 1]))) {
        return fail('SIMULATION_EFFECTS_MISMATCH');
      }
    }
    const inputSpent = sourceBefore - sourceAfter;
    const outputReceived = destinationAfter - destinationBefore;
    const takerSpent = takerBefore - takerAfter;
    // Closing an existing wrapped-SOL account returns all of it: the taker may end
    // with more SOL, but never less than its wrapped SOL minus the fee and rent bound.
    if (inputSpent !== inputAmount || outputReceived < minimumOutput || takerSpent < -returnUpperBound ||
        takerSpent > totalUpperBound - returnUpperBound) {
      return fail('SIMULATION_EFFECTS_MISMATCH');
    }

    const digestInput = JSON.stringify({
      transactionMessageHash: summary.transactionMessageHash, reconciliation: digest, slot: outcome.contextSlot,
      unitsConsumed: unitsConsumed.toString(), inputSpent: inputSpent.toString(), outputReceived: outputReceived.toString(),
      takerSpent: takerSpent.toString(), settlement: pendingDelivery === null ? 'simulated' : 'maker_delivers_at_fill',
    });
    return Object.freeze({
      schemaVersion: 1, kind: 'solana_stock_order_simulation', network: 'solana:mainnet-beta',
      genesisHash: STOCK_DRAFT_MAINNET_GENESIS, commitment: 'confirmed',
      transactionHash: summary.transactionHash, transactionMessageHash: summary.transactionMessageHash,
      draftBindingHash: summary.bindingHash, candidateTermsHash: summary.userApproval.candidateTermsHash,
      reconciliationDigestSha256: digest, simulationStartedAt, observedAt, simulationSlot: outcome.contextSlot,
      rpcApiVersion: outcome.apiVersion,
      request: Object.freeze({sigVerify: false, replaceRecentBlockhash: false, innerInstructions: false, accountAddresses, minContextSlot}),
      outcome: Object.freeze({
        error: failure, settlement: pendingDelivery === null ? 'simulated' as const : 'maker_delivers_at_fill' as const, unitsConsumed: unitsConsumed.toString(), computeUnitLimit, logLineCount: logLines.length,
        logsSha256: sha256(logLines.join('\n')), returnDataPresent: value['returnData'] !== null && value['returnData'] !== undefined,
      }),
      effects: Object.freeze({
        takerLamportsBefore: takerBefore.toString(), takerLamportsAfter: takerAfter.toString(), takerLamportsSpent: takerSpent.toString(),
        sourceAmountBefore: sourceBefore.toString(), sourceAmountAfter: sourceAfter.toString(), inputSpentRaw: inputSpent.toString(),
        destinationAmountBefore: destinationBefore.toString(), destinationAmountAfter: destinationAfter.toString(),
        outputReceivedRaw: outputReceived.toString(), destinationCreated: !reconciliation.accountState.destination.exists,
        preservedAccountsUnchanged: preserved.length, wrappedSolAccountClosed: unwrapped !== null,
      }),
      terms: Object.freeze({
        inputAmountRaw: inputAmount.toString(), minimumOutputAmountRaw: minimumOutput.toString(), totalLamportsUpperBound: totalUpperBound.toString(),
        takerLamportsReturnUpperBound: returnUpperBound.toString(),
      }),
      provenance: Object.freeze({rpcMethods: Object.freeze(['getGenesisHash', 'simulateTransaction'] as const), retries: 0, cacheUsed: false,
        digestSha256: sha256(digestInput)}),
      assessment: Object.freeze({
        status: 'simulated_effects_match_reviewed_terms', simulation: 'passed_point_in_time', effectsMatchReviewedTerms: true,
        revalidationRequired: true, approvable: false, userApproval: 'required', signingEnabled: false, broadcastEnabled: false,
        financialOperationsEnabled: false,
      }),
    });
  }
}
