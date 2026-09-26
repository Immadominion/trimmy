import { createHash } from 'node:crypto';
import { JUPITER_QUOTE_ASSETS } from './jupiter-quote-reader.js';
import type { StockDraftSummary } from './stock-order-draft.js';
import type { ReviewableAccountState, ReviewableInstruction, StockOrderSemantics } from './stock-order-semantics.js';

/**
 * Gate 6 of the unsigned stock-order review: prove that the decoded
 * instructions and the observed account state preserve the exact approved
 * candidate. Pure and deterministic over the gate 5 report; no RPC, no clock
 * beyond the supplied instant, no simulation, no signing. A passing result is
 * the only thing that may admit a draft to the simulation boundary, and even
 * then it is not approval, consent or settlement.
 */
export type StockOrderReconciliationErrorCode =
  | 'RECONCILIATION_INPUT_INVALID'
  | 'RECONCILIATION_EVIDENCE_MISMATCH'
  | 'RECONCILIATION_EXPIRED'
  | 'RECONCILIATION_SWAP_INSTRUCTION_MISSING'
  | 'RECONCILIATION_MULTIPLE_SWAPS'
  | 'RECONCILIATION_PROGRAM_UNEXPECTED'
  | 'RECONCILIATION_UNEXPECTED_MOVEMENT'
  | 'RECONCILIATION_AUTHORITY_MISMATCH'
  | 'RECONCILIATION_SOURCE_ACCOUNT_MISMATCH'
  | 'RECONCILIATION_DESTINATION_ACCOUNT_MISMATCH'
  | 'RECONCILIATION_MINT_MISMATCH'
  | 'RECONCILIATION_TOKEN_PROGRAM_MISMATCH'
  | 'RECONCILIATION_INPUT_AMOUNT_MISMATCH'
  | 'RECONCILIATION_OUTPUT_FLOOR_VIOLATED'
  | 'RECONCILIATION_SLIPPAGE_EXCEEDED'
  | 'RECONCILIATION_FEE_CAP_EXCEEDED'
  | 'RECONCILIATION_TAKER_STATE_INVALID'
  | 'RECONCILIATION_SOURCE_ACCOUNT_STATE_INVALID'
  | 'RECONCILIATION_SOURCE_BALANCE_INSUFFICIENT'
  | 'RECONCILIATION_DESTINATION_ACCOUNT_STATE_INVALID'
  | 'RECONCILIATION_MINT_STATE_INVALID'
  | 'RECONCILIATION_TAKER_SOL_INSUFFICIENT';

export class StockOrderReconciliationError extends Error {
  constructor(readonly code: StockOrderReconciliationErrorCode) {
    super('The stock order terms could not be reconciled with the approved candidate.');
    this.name = 'StockOrderReconciliationError';
  }
}
const fail = (code: StockOrderReconciliationErrorCode): never => { throw new StockOrderReconciliationError(code); };

export interface StockOrderReconciliationCheck {
  readonly name: string;
  readonly passed: true;
  readonly observed: string;
  readonly expected: string;
}

export interface ReconciledStockOrderTerms {
  readonly schemaVersion: 1;
  readonly kind: 'stock_order_terms_reconciliation';
  readonly network: 'solana:mainnet-beta';
  readonly transactionHash: string;
  readonly transactionMessageHash: string;
  readonly draftBindingHash: string;
  readonly candidateTermsHash: string;
  readonly semanticsDigestSha256: string;
  readonly observationSlot: string;
  readonly reconciledAt: string;
  readonly swap: Readonly<{
    readonly instructionIndex: number;
    readonly variant: 'route' | 'shared_accounts_route' | 'route_v2';
    readonly taker: string;
    readonly sourceTokenAccount: string;
    readonly destinationTokenAccount: string;
    readonly inputMint: string;
    readonly outputMint: string;
    readonly tokenProgram: string;
    readonly inputAmountRaw: string;
    readonly quotedOutputAmountRaw: string;
    readonly slippageBps: number;
    readonly minimumOutputAmountRaw: string;
    readonly platformFeeBps: number;
    readonly platformFeeAccount: string | null;
    readonly routePlanStepCount: number;
  }>;
  readonly candidate: Readonly<{
    readonly inputAmountRaw: string;
    readonly minimumOutputFloorRaw: string;
    readonly quotedMinimumAmountRaw: string;
    readonly maximumFeeBasisPoints: number;
    readonly slippageBps: number;
    readonly notAfter: string;
  }>;
  readonly accountState: Readonly<{
    readonly taker: Readonly<{readonly address: string; readonly lamports: string}>;
    readonly source: Readonly<{readonly address: string; readonly amountRaw: string; readonly state: string; readonly delegate: string | null}>;
    readonly destination: Readonly<{readonly address: string; readonly exists: boolean; readonly createdInTransaction: boolean;
      readonly state: string | null; readonly amountRaw: string | null}>;
    readonly inputMint: MintReview;
    readonly outputMint: MintReview;
  }>;
  readonly effects: Readonly<{
    readonly createdAccounts: readonly {readonly address: string; readonly mint: string; readonly rentLamportsUpperBound: string}[];
    readonly closedAccounts: readonly string[];
    readonly memoInstructions: number;
    readonly computeBudgetInstructions: number;
  }>;
  readonly cost: Readonly<{
    readonly feeLamportsUpperBound: string;
    readonly rentLamportsUpperBound: string;
    readonly totalLamportsUpperBound: string;
    readonly takerLamportsObserved: string;
  }>;
  readonly reviewFlags: readonly string[];
  readonly checks: readonly StockOrderReconciliationCheck[];
  readonly assessment: Readonly<{
    readonly status: 'terms_reconciled_but_unsimulated';
    readonly transactionTerms: 'verified_against_candidate';
    readonly accountState: 'verified_point_in_time';
    readonly accountStateFreshness: 'point_in_time_only';
    readonly revalidationRequired: true;
    readonly simulation: 'not_run';
    readonly approvable: false;
    readonly readyForSimulation: true;
    readonly signingEnabled: false;
    readonly broadcastEnabled: false;
    readonly financialOperationsEnabled: false;
  }>;
}

export interface MintReview {
  readonly address: string;
  readonly tokenProgram: 'token' | 'token_2022';
  readonly decimals: number;
  readonly paused: boolean | null;
  readonly defaultAccountState: string | null;
  readonly transferHookProgram: string | null;
  readonly permanentDelegate: string | null;
  readonly transferFeeBasisPoints: number | null;
  readonly scaledUiAmount: boolean;
  readonly nonTransferable: boolean;
  readonly extensions: readonly string[];
}

export interface StockOrderReconciliationInput {
  readonly summary: StockDraftSummary;
  readonly semantics: StockOrderSemantics;
  readonly now: number;
}

const LAMPORTS_PER_BYTE_YEAR = 3_480n;
const RENT_EXEMPTION_YEARS = 2n;
const ACCOUNT_STORAGE_OVERHEAD = 128n;
const LEGACY_TOKEN_ACCOUNT_BYTES = 165n;
const TOKEN_2022_ACCOUNT_TYPE_BYTE = 1n;
const TLV_HEADER_BYTES = 4n;
const sha256 = (value: string) => createHash('sha256').update(value).digest('hex');

type SwapInstruction = Extract<ReviewableInstruction, {program: 'jupiter_v6'}>;
type AccountByAddress = ReadonlyMap<string, {readonly state: ReviewableAccountState; readonly lamports: string}>;

function rentExemptLamports(dataBytes: bigint): bigint {
  return (dataBytes + ACCOUNT_STORAGE_OVERHEAD) * LAMPORTS_PER_BYTE_YEAR * RENT_EXEMPTION_YEARS;
}

/** Upper bound for a fresh associated token account of this mint, including the
 * account extensions Token-2022 adds automatically for the mint's extensions. */
function associatedAccountRentUpperBound(mint: MintReview): bigint {
  if (mint.tokenProgram === 'token') return rentExemptLamports(LEGACY_TOKEN_ACCOUNT_BYTES);
  let bytes = LEGACY_TOKEN_ACCOUNT_BYTES + TOKEN_2022_ACCOUNT_TYPE_BYTE + TLV_HEADER_BYTES; // ImmutableOwner
  if (mint.transferHookProgram !== null || mint.extensions.includes('TransferHook')) bytes += TLV_HEADER_BYTES + 1n;
  if (mint.transferFeeBasisPoints !== null) bytes += TLV_HEADER_BYTES + 8n;
  if (mint.nonTransferable) bytes += TLV_HEADER_BYTES;
  if (mint.paused !== null) bytes += TLV_HEADER_BYTES; // PausableAccount
  return rentExemptLamports(bytes);
}

function mintReview(address: string, accounts: AccountByAddress, expectedProgram: 'token' | 'token_2022'): MintReview {
  const entry = accounts.get(address);
  if (entry === undefined || entry.state.kind !== 'mint') return fail('RECONCILIATION_MINT_STATE_INVALID');
  const mint = entry.state;
  if (mint.tokenProgram !== expectedProgram || !mint.isInitialized) return fail('RECONCILIATION_MINT_STATE_INVALID');
  if (mint.paused === true || mint.nonTransferable) return fail('RECONCILIATION_MINT_STATE_INVALID');
  return Object.freeze({
    address, tokenProgram: mint.tokenProgram, decimals: mint.decimals, paused: mint.paused,
    defaultAccountState: mint.defaultAccountState, transferHookProgram: mint.transferHookProgram,
    permanentDelegate: mint.permanentDelegate,
    transferFeeBasisPoints: mint.transferFee === null ? null : mint.transferFee.basisPoints,
    scaledUiAmount: mint.scaledUiAmount !== null, nonTransferable: mint.nonTransferable,
    extensions: Object.freeze([...mint.extensions]),
  });
}

function parseAmount(value: string, code: StockOrderReconciliationErrorCode): bigint {
  if (!/^(?:0|[1-9][0-9]{0,38})$/.test(value)) return fail(code);
  return BigInt(value);
}

export function reconcileStockOrderTerms(input: StockOrderReconciliationInput): ReconciledStockOrderTerms {
  if (input === null || typeof input !== 'object' || typeof input.now !== 'number' || !Number.isFinite(input.now)) {
    return fail('RECONCILIATION_INPUT_INVALID');
  }
  const {summary, semantics, now} = input;
  if (summary?.kind !== 'stock_order_draft' || semantics?.kind !== 'solana_stock_order_semantics') return fail('RECONCILIATION_INPUT_INVALID');
  if (semantics.commitment !== 'confirmed' || semantics.identityCommitment !== 'finalized' ||
      semantics.transactionMessageHash !== summary.transactionMessageHash || semantics.transactionHash !== summary.transactionHash ||
      semantics.draftBindingHash !== summary.bindingHash || semantics.candidateTermsHash !== summary.userApproval.candidateTermsHash ||
      semantics.assessment.status !== 'semantics_decoded_but_unreconciled' || semantics.candidate.taker !== summary.taker ||
      semantics.candidate.inputMint !== summary.input.mint || semantics.candidate.outputMint !== summary.output.mint ||
      summary.readyForSimulation !== false || summary.signingEnabled !== false || summary.executionEnabled !== false) {
    return fail('RECONCILIATION_EVIDENCE_MISMATCH');
  }
  const notAfter = Date.parse(summary.notAfter);
  if (!Number.isFinite(notAfter) || now >= notAfter || now < Date.parse(summary.receivedAt)) return fail('RECONCILIATION_EXPIRED');

  const checks: StockOrderReconciliationCheck[] = [];
  const check = (name: string, passed: boolean, observed: string, expected: string, code: StockOrderReconciliationErrorCode) => {
    if (!passed) return fail(code);
    checks.push(Object.freeze({name, passed: true, observed, expected}));
  };

  const accounts = new Map<string, {state: ReviewableAccountState; lamports: string}>();
  for (const account of semantics.accounts) accounts.set(account.address, {state: account.state, lamports: account.observation.lamports});
  const candidate = semantics.candidate;
  const taker = summary.taker;

  // Program set: only the programs a Jupiter swap needs. The names are the
  // KNOWN_PROGRAMS keys the semantics gate reports.
  const admittedPrograms: readonly string[] = ['computeBudget', 'associatedToken', 'jupiterV6', 'token',
    'token2022', 'system', 'memo'];
  for (const program of semantics.programs) {
    if (!admittedPrograms.includes(program.name)) return fail('RECONCILIATION_PROGRAM_UNEXPECTED');
  }

  const inputMint = mintReview(candidate.inputMint, accounts, candidate.inputTokenProgram);
  const outputMint = mintReview(candidate.outputMint, accounts, candidate.outputTokenProgram);
  check('input mint decimals', inputMint.decimals === summary.input.decimals, String(inputMint.decimals), String(summary.input.decimals), 'RECONCILIATION_MINT_STATE_INVALID');
  check('output mint decimals', outputMint.decimals === summary.output.decimals, String(outputMint.decimals), String(summary.output.decimals), 'RECONCILIATION_MINT_STATE_INVALID');

  // Walk every top-level instruction and admit only the expected shapes.
  let swap: {readonly instructionIndex: number; readonly decoded: SwapInstruction} | null = null;
  const createdAccounts: {address: string; mint: string; rentLamportsUpperBound: string}[] = [];
  const closedAccounts: string[] = [];
  let memoInstructions = 0;
  let computeBudgetInstructions = 0;
  const nativeInput = candidate.inputMint === JUPITER_QUOTE_ASSETS.SOL.mint;
  for (const instruction of semantics.instructions) {
    const decoded = instruction.decoded;
    switch (decoded.program) {
      case 'compute_budget':
        computeBudgetInstructions += 1;
        continue;
      case 'memo':
        memoInstructions += 1;
        continue;
      case 'associated_token': {
        const forInput = decoded.mint === candidate.inputMint;
        const forOutput = decoded.mint === candidate.outputMint;
        const forIntermediateSol = !forInput && !forOutput && decoded.mint === JUPITER_QUOTE_ASSETS.SOL.mint;
        const expectedAccount = forIntermediateSol ? candidate.takerWrappedSolAssociatedAccount : forInput ? candidate.takerInputAssociatedAccount : forOutput ? candidate.takerOutputAssociatedAccount : null;
        const expectedProgram = forIntermediateSol ? 'token' : forInput ? candidate.inputTokenProgram : candidate.outputTokenProgram;
        const programAddress = expectedProgram === 'token' ? 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA' : 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
        if (expectedAccount === null || decoded.payer !== taker || decoded.owner !== taker ||
            decoded.associatedAccount !== expectedAccount || decoded.tokenProgram !== programAddress) {
          return fail('RECONCILIATION_UNEXPECTED_MOVEMENT');
        }
        const existing = accounts.get(expectedAccount);
        // Only allow a newly created, empty intermediate WSOL account. Never close existing holdings.
        if (forIntermediateSol && existing !== undefined && existing.state.kind !== 'missing') return fail('RECONCILIATION_UNEXPECTED_MOVEMENT');
        if (existing === undefined || existing.state.kind === 'missing') {
          if (forIntermediateSol) {
            createdAccounts.push({address: expectedAccount, mint: decoded.mint, rentLamportsUpperBound: rentExemptLamports(LEGACY_TOKEN_ACCOUNT_BYTES).toString()});
            continue;
          }
          const review = forInput ? inputMint : outputMint;
          createdAccounts.push({address: expectedAccount, mint: decoded.mint, rentLamportsUpperBound: associatedAccountRentUpperBound(review).toString()});
        }
        continue;
      }
      case 'system': {
        // Only wrapping SOL into the taker's own native account is a legitimate SOL movement.
        if (decoded.kind !== 'transfer' || !nativeInput || decoded.from !== taker || decoded.to !== candidate.takerInputAssociatedAccount) {
          return fail('RECONCILIATION_UNEXPECTED_MOVEMENT');
        }
        continue;
      }
      case 'token':
      case 'token_2022': {
        if (decoded.kind === 'sync_native') {
          if (!nativeInput || decoded.account !== candidate.takerInputAssociatedAccount) return fail('RECONCILIATION_UNEXPECTED_MOVEMENT');
          continue;
        }
        if (decoded.kind === 'close_account') {
          const wrapped = (decoded.account === candidate.takerInputAssociatedAccount && nativeInput) ||
            (decoded.account === candidate.takerWrappedSolAssociatedAccount &&
              createdAccounts.some(item => item.address === decoded.account && item.mint === JUPITER_QUOTE_ASSETS.SOL.mint));
          if (!wrapped || decoded.destination !== taker || decoded.authority !== taker) return fail('RECONCILIATION_UNEXPECTED_MOVEMENT');
          closedAccounts.push(decoded.account);
          continue;
        }
        if (decoded.kind === 'initialize_account' || decoded.kind === 'initialize_immutable_owner') {
          const own = decoded.account === candidate.takerInputAssociatedAccount || decoded.account === candidate.takerOutputAssociatedAccount;
          if (!own || (decoded.kind === 'initialize_account' && decoded.owner !== taker)) return fail('RECONCILIATION_UNEXPECTED_MOVEMENT');
          continue;
        }
        // Top-level transfers, approvals and revocations move or delegate funds outside the reviewed swap.
        return fail('RECONCILIATION_UNEXPECTED_MOVEMENT');
      }
      case 'jupiter_v6': {
        if (swap !== null) return fail('RECONCILIATION_MULTIPLE_SWAPS');
        swap = {instructionIndex: instruction.instructionIndex, decoded};
        continue;
      }
      default:
        return fail('RECONCILIATION_PROGRAM_UNEXPECTED');
    }
  }
  for (const item of createdAccounts) {
    if (item.mint === JUPITER_QUOTE_ASSETS.SOL.mint && !nativeInput && !closedAccounts.includes(item.address)) return fail('RECONCILIATION_UNEXPECTED_MOVEMENT');
  }
  if (swap === null) return fail('RECONCILIATION_SWAP_INSTRUCTION_MISSING');
  const route = swap.decoded;

  // Terms: authority, accounts, mints, program, amounts, slippage and fees.
  check('swap authority', route.userTransferAuthority === taker, route.userTransferAuthority, taker, 'RECONCILIATION_AUTHORITY_MISMATCH');
  check('swap source account', route.userSourceTokenAccount === candidate.takerInputAssociatedAccount,
    route.userSourceTokenAccount, candidate.takerInputAssociatedAccount, 'RECONCILIATION_SOURCE_ACCOUNT_MISMATCH');
  check('swap destination account', route.userDestinationTokenAccount === candidate.takerOutputAssociatedAccount,
    route.userDestinationTokenAccount, candidate.takerOutputAssociatedAccount, 'RECONCILIATION_DESTINATION_ACCOUNT_MISMATCH');
  check('swap destination mint', route.destinationMint === candidate.outputMint, route.destinationMint, candidate.outputMint, 'RECONCILIATION_MINT_MISMATCH');
  if (route.sourceMint !== null) {
    check('swap source mint', route.sourceMint === candidate.inputMint, String(route.sourceMint), candidate.inputMint, 'RECONCILIATION_MINT_MISMATCH');
  }
  const inputProgramAddress = candidate.inputTokenProgram === 'token' ? 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA' : 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
  check('swap token program', route.tokenProgram === inputProgramAddress, route.tokenProgram, inputProgramAddress, 'RECONCILIATION_TOKEN_PROGRAM_MISMATCH');
  if (route.kind === 'route_v2') {
    const outputProgramAddress = candidate.outputTokenProgram === 'token' ? 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA' : 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
    check('swap destination token program', route.destinationTokenProgram === outputProgramAddress, String(route.destinationTokenProgram), outputProgramAddress, 'RECONCILIATION_TOKEN_PROGRAM_MISMATCH');
  }
  const inputAmount = parseAmount(route.inAmount, 'RECONCILIATION_INPUT_AMOUNT_MISMATCH');
  const candidateInput = parseAmount(summary.input.amountRaw, 'RECONCILIATION_INPUT_INVALID');
  check('input amount', inputAmount === candidateInput, inputAmount.toString(), candidateInput.toString(), 'RECONCILIATION_INPUT_AMOUNT_MISMATCH');
  const quotedOut = parseAmount(route.quotedOutAmount, 'RECONCILIATION_OUTPUT_FLOOR_VIOLATED');
  if (!Number.isInteger(route.slippageBps) || route.slippageBps < 0 || route.slippageBps > 10_000) return fail('RECONCILIATION_SLIPPAGE_EXCEEDED');
  check('slippage', route.slippageBps <= summary.slippageBps, String(route.slippageBps), `<= ${summary.slippageBps}`, 'RECONCILIATION_SLIPPAGE_EXCEEDED');
  const minimumOut = quotedOut - (quotedOut * BigInt(route.slippageBps)) / 10_000n;
  const floor = parseAmount(summary.approvalPolicy.minimumOutputAmountRaw, 'RECONCILIATION_INPUT_INVALID');
  const quotedMinimum = parseAmount(summary.output.quotedMinimumAmountRaw, 'RECONCILIATION_INPUT_INVALID');
  check('minimum output floor', minimumOut >= floor && minimumOut > 0n, minimumOut.toString(), `>= ${floor}`, 'RECONCILIATION_OUTPUT_FLOOR_VIOLATED');
  check('quoted minimum consistency', minimumOut >= quotedMinimum, minimumOut.toString(), `>= ${quotedMinimum}`, 'RECONCILIATION_OUTPUT_FLOOR_VIOLATED');
  check('platform fee cap', route.platformFeeBps <= summary.approvalPolicy.maximumFeeBasisPoints,
    String(route.platformFeeBps), `<= ${summary.approvalPolicy.maximumFeeBasisPoints}`, 'RECONCILIATION_FEE_CAP_EXCEEDED');
  if (route.platformFeeBps > 0 && route.platformFeeAccount === null) return fail('RECONCILIATION_FEE_CAP_EXCEEDED');

  // Account state at the observation slot.
  const takerEntry = accounts.get(taker);
  if (takerEntry === undefined || takerEntry.state.kind !== 'system') return fail('RECONCILIATION_TAKER_STATE_INVALID');
  const takerLamports = parseAmount(takerEntry.lamports, 'RECONCILIATION_TAKER_STATE_INVALID');
  const sourceEntry = accounts.get(candidate.takerInputAssociatedAccount);
  if (sourceEntry === undefined || sourceEntry.state.kind !== 'token_account') return fail('RECONCILIATION_SOURCE_ACCOUNT_STATE_INVALID');
  const source = sourceEntry.state;
  if (source.owner !== taker || source.mint !== candidate.inputMint || source.state !== 'initialized' ||
      source.tokenProgram !== candidate.inputTokenProgram) {
    return fail('RECONCILIATION_SOURCE_ACCOUNT_STATE_INVALID');
  }
  const sourceAmount = parseAmount(source.amount, 'RECONCILIATION_SOURCE_ACCOUNT_STATE_INVALID');
  check('source balance', sourceAmount >= inputAmount, sourceAmount.toString(), `>= ${inputAmount}`, 'RECONCILIATION_SOURCE_BALANCE_INSUFFICIENT');
  const destinationEntry = accounts.get(candidate.takerOutputAssociatedAccount);
  const destinationCreated = createdAccounts.some(item => item.address === candidate.takerOutputAssociatedAccount);
  let destination: ReconciledStockOrderTerms['accountState']['destination'];
  if (destinationEntry !== undefined && destinationEntry.state.kind === 'token_account') {
    const state = destinationEntry.state;
    if (state.owner !== taker || state.mint !== candidate.outputMint || state.state !== 'initialized' ||
        state.tokenProgram !== candidate.outputTokenProgram) {
      return fail('RECONCILIATION_DESTINATION_ACCOUNT_STATE_INVALID');
    }
    destination = Object.freeze({address: candidate.takerOutputAssociatedAccount, exists: true, createdInTransaction: destinationCreated,
      state: state.state, amountRaw: state.amount});
  } else if (destinationEntry === undefined || destinationEntry.state.kind === 'missing') {
    if (!destinationCreated) return fail('RECONCILIATION_DESTINATION_ACCOUNT_STATE_INVALID');
    // A mint whose new accounts start frozen would strand the output until the issuer thaws it.
    if (outputMint.defaultAccountState === 'frozen') return fail('RECONCILIATION_DESTINATION_ACCOUNT_STATE_INVALID');
    destination = Object.freeze({address: candidate.takerOutputAssociatedAccount, exists: false, createdInTransaction: true, state: null, amountRaw: null});
  } else {
    return fail('RECONCILIATION_DESTINATION_ACCOUNT_STATE_INVALID');
  }

  // SOL cost: fees plus rent for any account this transaction creates (plus the wrapped input for SOL).
  const feeUpperBound = parseAmount(semantics.feeEstimate.totalLamportsUpperBound, 'RECONCILIATION_INPUT_INVALID');
  const rentUpperBound = createdAccounts.reduce((total, item) => total + BigInt(item.rentLamportsUpperBound), 0n);
  const totalCost = feeUpperBound + rentUpperBound + (nativeInput ? inputAmount : 0n);
  check('taker SOL for fees and rent', takerLamports >= totalCost, takerLamports.toString(), `>= ${totalCost}`, 'RECONCILIATION_TAKER_SOL_INSUFFICIENT');

  const reviewFlags: string[] = [];
  // A set hook program runs on every transfer; the bare extension means the
  // issuer can set one later, which a later review must observe again.
  if (outputMint.transferHookProgram !== null) reviewFlags.push('output_mint_transfer_hook');
  else if (outputMint.extensions.includes('TransferHook')) reviewFlags.push('output_mint_transfer_hook_extension');
  if (outputMint.permanentDelegate !== null) reviewFlags.push('output_mint_permanent_delegate');
  if (outputMint.transferFeeBasisPoints !== null) reviewFlags.push('output_mint_transfer_fee');
  if (outputMint.scaledUiAmount) reviewFlags.push('output_mint_scaled_ui_amount');
  if (outputMint.paused === false) reviewFlags.push('output_mint_pausable');
  if (inputMint.transferFeeBasisPoints !== null) reviewFlags.push('input_mint_transfer_fee');
  if (source.delegate !== null) reviewFlags.push('source_account_has_delegate');
  if (route.platformFeeAccount !== null) reviewFlags.push('platform_fee_account_present');

  return Object.freeze({
    schemaVersion: 1, kind: 'stock_order_terms_reconciliation', network: 'solana:mainnet-beta',
    transactionHash: summary.transactionHash, transactionMessageHash: summary.transactionMessageHash,
    draftBindingHash: summary.bindingHash, candidateTermsHash: summary.userApproval.candidateTermsHash,
    semanticsDigestSha256: semantics.provenance.digestSha256, observationSlot: semantics.observationSlot,
    reconciledAt: new Date(now).toISOString(),
    swap: Object.freeze({
      instructionIndex: swap.instructionIndex, variant: route.kind, taker,
      sourceTokenAccount: route.userSourceTokenAccount, destinationTokenAccount: route.userDestinationTokenAccount,
      inputMint: candidate.inputMint, outputMint: candidate.outputMint, tokenProgram: route.tokenProgram,
      inputAmountRaw: inputAmount.toString(), quotedOutputAmountRaw: quotedOut.toString(), slippageBps: route.slippageBps,
      minimumOutputAmountRaw: minimumOut.toString(), platformFeeBps: route.platformFeeBps,
      platformFeeAccount: route.platformFeeAccount, routePlanStepCount: route.routePlanStepCount,
    }),
    candidate: Object.freeze({
      inputAmountRaw: candidateInput.toString(), minimumOutputFloorRaw: floor.toString(), quotedMinimumAmountRaw: quotedMinimum.toString(),
      maximumFeeBasisPoints: summary.approvalPolicy.maximumFeeBasisPoints, slippageBps: summary.slippageBps, notAfter: summary.notAfter,
    }),
    accountState: Object.freeze({
      taker: Object.freeze({address: taker, lamports: takerLamports.toString()}),
      source: Object.freeze({address: candidate.takerInputAssociatedAccount, amountRaw: sourceAmount.toString(), state: source.state, delegate: source.delegate}),
      destination, inputMint, outputMint,
    }),
    effects: Object.freeze({
      createdAccounts: Object.freeze(createdAccounts.map(item => Object.freeze({...item}))),
      closedAccounts: Object.freeze(closedAccounts), memoInstructions, computeBudgetInstructions,
    }),
    cost: Object.freeze({
      feeLamportsUpperBound: feeUpperBound.toString(), rentLamportsUpperBound: rentUpperBound.toString(),
      totalLamportsUpperBound: totalCost.toString(), takerLamportsObserved: takerLamports.toString(),
    }),
    reviewFlags: Object.freeze(reviewFlags),
    checks: Object.freeze(checks),
    assessment: Object.freeze({
      status: 'terms_reconciled_but_unsimulated', transactionTerms: 'verified_against_candidate', accountState: 'verified_point_in_time',
      accountStateFreshness: 'point_in_time_only', revalidationRequired: true, simulation: 'not_run', approvable: false,
      readyForSimulation: true, signingEnabled: false, broadcastEnabled: false, financialOperationsEnabled: false,
    }),
  });
}

/** Stable digest of a reconciliation report for later stages to bind against. */
export function reconciliationDigest(report: ReconciledStockOrderTerms): string {
  return sha256(JSON.stringify(report));
}
