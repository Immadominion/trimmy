import assert from 'node:assert/strict';
import { createHash, createPrivateKey, createPublicKey } from 'node:crypto';
import { describe, it } from 'node:test';
import { address, getAddressDecoder, getCompiledTransactionMessageEncoder, getTransactionEncoder } from '@solana/kit';
import type { Address, CompiledTransactionMessage, TransactionMessageBytes } from '@solana/kit';
import { AccountState, getMintEncoder, getTokenEncoder,
  getCreateAssociatedTokenIdempotentInstructionDataEncoder } from '@solana-program/token-2022';
import type { ExtensionArgs } from '@solana-program/token-2022';
import { getMintEncoder as getLegacyMintEncoder, getTokenEncoder as getLegacyTokenEncoder,
  AccountState as LegacyAccountState } from '@solana-program/token';
import { getSetComputeUnitLimitInstructionDataEncoder,
  getSetComputeUnitPriceInstructionDataEncoder } from '@solana-program/compute-budget';
import { JUPITER_QUOTE_ASSETS } from '../src/jupiter-quote-reader.js';
import { STOCK_TRADING_ASSETS } from '../src/stock-trading-catalog.js';
import { STOCK_ESTIMATE_ASSET } from '../src/stock-estimates.js';
import type { StockEstimate } from '../src/stock-estimates.js';
import { KNOWN_PROGRAMS } from '../src/solana-instruction-decoders.js';
import { deriveAssociatedTokenAddress } from '../src/solana-account-state.js';
import { bindStockOrderDraft, inspectStockDraftStructure, admitStockDraftForSimulation,
  assertStockDraftReadyForSimulation, StockOrderDraftError, STOCK_DRAFT_MAINNET_GENESIS } from '../src/stock-order-draft.js';
import type { StockDraftBinding, StockOrderDraft, StockOrderDraftContext,
  StockDraftStructuralInspection } from '../src/stock-order-draft.js';
import type { ResolvedStockTransactionAccounts } from '../src/stock-order-lookup-resolver.js';
import type { VerifiedStockOrderLifetime } from '../src/stock-order-lifetime-verifier.js';
import { SolanaMainnetStockOrderSemanticsReader, StockOrderSemanticsError } from '../src/stock-order-semantics.js';
import { reconcileStockOrderTerms, reconciliationDigest,
  StockOrderReconciliationError } from '../src/stock-order-terms-reconciliation.js';
import { SolanaMainnetStockOrderSimulator, StockOrderSimulationError } from '../src/stock-order-simulation.js';
import { reviewStockOrder, reviewedIntentUsable, REVIEW_VALIDITY_MS,
  StockOrderReviewError } from '../src/stock-order-review.js';

// Deterministic on-curve keys. No private key is used to sign a transaction.
function key(label: string): Address {
  const seed = createHash('sha256').update(`trimmy-review-${label}`).digest();
  const pkcs8 = Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]);
  const spki = createPublicKey(createPrivateKey({key: pkcs8, format: 'der', type: 'pkcs8'}))
    .export({format: 'der', type: 'spki'});
  return getAddressDecoder().decode(Uint8Array.from(spki.subarray(spki.length - 32)));
}
const taker = key('taker');
const eventAuthority = address('D8cy77BBepLMngZx6ZukaTff5hCt1HrWyKk3Hnd9oitf');
const poolAccount = key('pool');
const usdcMint = address(JUPITER_QUOTE_ASSETS.USDC.mint);
const aaplxMint = address(STOCK_ESTIMATE_ASSET.variantMint);
// The reviewed swap must use the taker's own canonical associated accounts, so
// the fixtures derive them exactly as the review gates do.
const sourceAta = await deriveAssociatedTokenAddress(taker, JUPITER_QUOTE_ASSETS.USDC.mint, 'token');
const destinationAta = await deriveAssociatedTokenAddress(taker, STOCK_ESTIMATE_ASSET.variantMint, 'token_2022');
const userId = '12345678-1234-4567-8123-123456789abc';
const at = (seconds: number) => `2026-09-15T09:00:${String(seconds).padStart(2, '0')}.000Z`;
const INPUT_RAW = 10_000_000n;
const QUOTED_OUT = 2_972_350n;
const SLIPPAGE_BPS = 50;
const MINIMUM_OUT = QUOTED_OUT - (QUOTED_OUT * BigInt(SLIPPAGE_BPS)) / 10_000n;
const sha256 = (value: Uint8Array | string) => createHash('sha256').update(value).digest('hex');

function u32(value: number): number[] { return [value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >>> 24) & 0xff]; }
function u64(value: bigint): number[] {
  const out: number[] = [];
  let rest = value;
  for (let index = 0; index < 8; index += 1) { out.push(Number(rest & 0xffn)); rest >>= 8n; }
  return out;
}
function anchor(name: string): number[] {
  return [...createHash('sha256').update(`global:${name}`).digest().subarray(0, 8)];
}
function routeData(options: {inAmount?: bigint; quotedOut?: bigint; slippageBps?: number; feeBps?: number;
  name?: string} = {}): Uint8Array {
  return Uint8Array.from([
    ...anchor(options.name ?? 'route'), ...u32(1), 0, 0, 0, 0, 0,
    ...u64(options.inAmount ?? INPUT_RAW), ...u64(options.quotedOut ?? QUOTED_OUT),
    (options.slippageBps ?? SLIPPAGE_BPS) & 0xff, ((options.slippageBps ?? SLIPPAGE_BPS) >> 8) & 0xff,
    options.feeBps ?? 0,
  ]);
}

/**
 * A realistic unsigned v0 Jupiter swap: compute budget limit and price, an
 * idempotent associated-account create for the output mint, then the route.
 */
const STATIC_ACCOUNTS: readonly Address[] = [
  taker,                                    // 0 fee payer and signer
  address(sourceAta),                       // 1 taker USDC associated account
  address(destinationAta),                  // 2 taker AAPLx associated account
  poolAccount,                              // 3
  address(KNOWN_PROGRAMS.computeBudget),    // 4
  address(KNOWN_PROGRAMS.associatedToken),  // 5
  address(KNOWN_PROGRAMS.jupiterV6),        // 6
  address(KNOWN_PROGRAMS.token),            // 7
  address(KNOWN_PROGRAMS.system),           // 8
  usdcMint,                                 // 9
  aaplxMint,                                // 10
  eventAuthority,                           // 11
  address(KNOWN_PROGRAMS.token2022),        // 12
];
const COMPUTE_LIMIT = 420_000;
// A liquidity pool account owned by some other program decodes as unclassified state.
const POOL_PROGRAM = 'whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc';

function swapMessage(overrides: {instructions?: CompiledTransactionMessage['instructions']} = {}):
CompiledTransactionMessage & {lifetimeToken: string} {
  const instructions = overrides.instructions ?? [
    {programAddressIndex: 4, accountIndices: [], data: Uint8Array.from(
      getSetComputeUnitLimitInstructionDataEncoder().encode({units: COMPUTE_LIMIT}))},
    {programAddressIndex: 4, accountIndices: [], data: Uint8Array.from(
      getSetComputeUnitPriceInstructionDataEncoder().encode({microLamports: 1_000n}))},
    {programAddressIndex: 5, accountIndices: [0, 2, 0, 10, 8, 12], data: Uint8Array.from(
      getCreateAssociatedTokenIdempotentInstructionDataEncoder().encode({}))},
    {programAddressIndex: 6, accountIndices: [7, 0, 1, 2, 6, 10, 6, 11, 6, 3], data: routeData()},
  ];
  return {
    version: 0,
    header: {numSignerAccounts: 1, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 9},
    staticAccounts: [...STATIC_ACCOUNTS],
    lifetimeToken: getAddressDecoder().decode(new Uint8Array(32).fill(9)),
    instructions, addressTableLookups: [],
  } as unknown as CompiledTransactionMessage & {lifetimeToken: string};
}

function wire(message = swapMessage()): Buffer {
  const messageBytes = getCompiledTransactionMessageEncoder().encode(message) as TransactionMessageBytes;
  return Buffer.from(getTransactionEncoder().encode({messageBytes, signatures: {[taker]: null}}));
}

function estimate(): StockEstimate {
  return {
    schemaVersion: 1, kind: 'indicative', network: 'solana:mainnet-beta', provider: 'jupiter-swap-v2',
    executable: false, walletChecked: false, networkFees: null,
    input: {symbol: 'USDC', mint: JUPITER_QUOTE_ASSETS.USDC.mint, decimals: 6, amountRaw: INPUT_RAW.toString()},
    output: {symbol: 'AAPLx', mint: STOCK_ESTIMATE_ASSET.variantMint, decimals: 8,
      estimatedAmountRaw: QUOTED_OUT.toString(), quotedMinimumAmountRaw: MINIMUM_OUT.toString()},
    slippageBps: SLIPPAGE_BPS, swapFee: {basisPoints: 10, mint: JUPITER_QUOTE_ASSETS.USDC.mint}, router: 'metis',
    requestedAt: at(0), receivedAt: at(1), refreshAfter: at(10), providerExpiresAt: null,
    assetId: 'apple', variantMint: STOCK_ESTIMATE_ASSET.variantMint, side: 'buy', executionEnabled: false,
    eligibility: 'unverified', amountUnits: 'raw_token_units',
  };
}

function context(clock: {now: number}): StockOrderDraftContext {
  const observation = {genesisHash: STOCK_DRAFT_MAINNET_GENESIS, blockHeight: '1000', observedAt: at(3)} as const;
  return {
    authenticatedUserId: userId, verifiedTaker: taker, expected: estimate(), requestStartedAt: at(2),
    chainObservation: observation,
    validityAuthority: {
      now: () => clock.now,
      readChainObservation: async () => ({...observation, blockHeight: '1001',
        observedAt: new Date(clock.now).toISOString()}),
    },
  };
}

function payload(changes: Record<string, unknown> = {}, message = swapMessage()): Record<string, unknown> {
  const quote = estimate();
  return {
    inputMint: quote.input.mint, outputMint: quote.output.mint, inAmount: quote.input.amountRaw,
    outAmount: quote.output.estimatedAmountRaw, otherAmountThreshold: quote.output.quotedMinimumAmountRaw,
    swapMode: 'ExactIn', slippageBps: quote.slippageBps, feeBps: quote.swapFee.basisPoints,
    feeMint: quote.swapFee.mint, router: quote.router, mode: 'manual', taker,
    transaction: wire(message).toString('base64'), requestId: 'order-review-1',
    lastValidBlockHeight: '1150', ...changes,
  };
}

function binding(draft: StockOrderDraft, changes: Partial<StockDraftBinding> = {}): StockDraftBinding {
  return {
    authenticatedUserId: userId, verifiedTaker: taker, requestId: draft.summary.requestId,
    transactionMessageHash: draft.summary.transactionMessageHash, bindingHash: draft.summary.bindingHash, ...changes,
  };
}

/** Static-only account map, exactly what the lookup resolver returns for this message. */
function resolvedAccounts(structure: StockDraftStructuralInspection, staticAccounts = STATIC_ACCOUNTS): ResolvedStockTransactionAccounts {
  const accountIndexMap = staticAccounts.map((value, accountIndex) => Object.freeze({
    accountIndex, address: value as string, signer: accountIndex === 0,
    writable: accountIndex <= 3, source: 'static' as const, staticAccountIndex: accountIndex,
  }));
  return Object.freeze({
    schemaVersion: 1, kind: 'solana_v0_resolved_account_indexes', network: 'solana:mainnet-beta',
    genesisHash: STOCK_DRAFT_MAINNET_GENESIS, commitment: 'finalized',
    transactionHash: structure.transactionHash, transactionMessageHash: structure.transactionMessageHash,
    resolutionStartedAt: at(3), observedAt: at(3), firstObservationSlot: null, secondObservationSlot: null,
    accountIndexMap: Object.freeze(accountIndexMap), lookupTables: Object.freeze([]),
    provenance: Object.freeze({
      rpcMethods: Object.freeze(['getGenesisHash'] as const), tableAddressesRequested: Object.freeze([]),
      tableReadCount: 0 as const, rpcApiVersion: '3.1.10', retries: 0 as const, cacheUsed: false as const,
      observationsStable: true as const, digestSha256: sha256('resolved'),
    }),
    assessment: Object.freeze({
      status: 'account_indexes_resolved_but_incomplete', clusterGenesis: 'verified',
      lookupTableAccounts: 'not_applicable', lookupTableFreshness: 'point_in_time_only', revalidationRequired: true,
      accountIndexResolution: 'complete', recentBlockhash: 'unverified', programOwnership: 'unverified',
      instructionSemantics: 'unverified', accountState: 'unverified', transactionTerms: 'unverified',
      simulation: 'not_run', approvable: false, readyForSimulation: false, signingEnabled: false,
      broadcastEnabled: false, financialOperationsEnabled: false,
    }),
  }) as ResolvedStockTransactionAccounts;
}

function lifetimeEvidence(structure: StockDraftStructuralInspection): VerifiedStockOrderLifetime {
  return Object.freeze({
    schemaVersion: 1, kind: 'solana_recent_blockhash_lifetime_evidence', network: 'solana:mainnet-beta',
    genesisHash: STOCK_DRAFT_MAINNET_GENESIS, commitment: 'finalized',
    transactionHash: structure.transactionHash, transactionMessageHash: structure.transactionMessageHash,
    draftBindingHash: structure.draftBindingHash, candidateTermsHash: structure.candidateTermsHash,
    verificationStartedAt: at(3), observedAt: at(3),
    lifetime: Object.freeze({
      token: structure.lifetimeToken.value, tokenSha256: sha256(structure.lifetimeToken.value),
      semanticKind: 'verified_recent_blockhash', mainnetRecency: 'verified_stable_finalized',
      admittedAtBlockHeight: '1000', providerLastValidBlockHeight: '1150', firstObservedBlockHeight: '1001',
      secondObservedBlockHeight: '1001', remainingBlocksAtSecondObservation: '149',
      providerHeightAssociation: 'bound_not_rpc_derived',
    }),
  }) as unknown as VerifiedStockOrderLifetime;
}

// Account fixtures for the three reviewed accounts plus both mints.
function rpcAccount(data: Uint8Array, owner: string, lamports: number, executable = false) {
  return {data: [Buffer.from(data).toString('base64'), 'base64'], executable, lamports, owner,
    rentEpoch: 0, space: data.byteLength};
}
const AAPLX_EXTENSIONS: ExtensionArgs[] = [
  {__kind: 'PausableConfig', authority: key('pause-authority'), paused: false},
  {__kind: 'DefaultAccountState', state: AccountState.Initialized},
  {__kind: 'TransferHook', authority: key('hook-authority'), programId: address(KNOWN_PROGRAMS.system)},
  {__kind: 'PermanentDelegate', delegate: key('permanent-delegate')},
];
function accountValues(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const base: Record<string, unknown> = {
    [taker]: rpcAccount(new Uint8Array(), KNOWN_PROGRAMS.system, 40_000_000),
    [sourceAta]: rpcAccount(Uint8Array.from(getLegacyTokenEncoder().encode({
      mint: usdcMint, owner: taker, amount: 25_000_000n, delegate: null, state: LegacyAccountState.Initialized,
      isNative: null, delegatedAmount: 0n, closeAuthority: null,
    })), KNOWN_PROGRAMS.token, 2_039_280),
    [destinationAta]: rpcAccount(Uint8Array.from(getTokenEncoder().encode({
      mint: aaplxMint, owner: taker, amount: 0n, delegate: null, state: AccountState.Initialized,
      isNative: null, delegatedAmount: 0n, closeAuthority: null, extensions: [{__kind: 'ImmutableOwner'}],
    })), KNOWN_PROGRAMS.token2022, 2_157_600),
    [usdcMint]: rpcAccount(Uint8Array.from(getLegacyMintEncoder().encode({
      mintAuthority: key('usdc-authority'), supply: 5_000_000_000n, decimals: 6, isInitialized: true,
      freezeAuthority: key('usdc-freeze'),
    })), KNOWN_PROGRAMS.token, 1_461_600),
    [aaplxMint]: rpcAccount(Uint8Array.from(getMintEncoder().encode({
      mintAuthority: key('aaplx-authority'), supply: 15_376_355_897_326n, decimals: 8, isInitialized: true,
      freezeAuthority: key('aaplx-freeze'), extensions: AAPLX_EXTENSIONS,
    })), KNOWN_PROGRAMS.token2022, 4_000_000),
    [poolAccount]: rpcAccount(new Uint8Array(64), POOL_PROGRAM, 5_000_000),
    [eventAuthority]: rpcAccount(new Uint8Array(), KNOWN_PROGRAMS.system, 0),
  };
  for (const program of [KNOWN_PROGRAMS.computeBudget, KNOWN_PROGRAMS.associatedToken, KNOWN_PROGRAMS.jupiterV6,
    KNOWN_PROGRAMS.token, KNOWN_PROGRAMS.system]) {
    base[program] = rpcAccount(new Uint8Array(36), 'BPFLoaderUpgradeab1e11111111111111111111111', 1_000_000, true);
  }
  base[KNOWN_PROGRAMS.token2022] = rpcAccount(new Uint8Array(36),
    'BPFLoaderUpgradeab1e11111111111111111111111', 1_000_000, true);
  return {...base, ...overrides};
}

interface RpcCall { readonly method: string; readonly params: readonly unknown[] }

function semanticsFetch(options: {values?: Record<string, unknown>; slot?: number; genesis?: string;
  calls?: RpcCall[]} = {}): typeof globalThis.fetch {
  const values = options.values ?? accountValues();
  return (async (_url: string | URL, init?: {body?: string}) => {
    const request = JSON.parse(String(init?.body)) as {id: string; method: string; params: unknown[]};
    options.calls?.push({method: request.method, params: request.params});
    const body = request.method === 'getGenesisHash'
      ? {jsonrpc: '2.0', id: request.id, result: options.genesis ?? STOCK_DRAFT_MAINNET_GENESIS}
      : {jsonrpc: '2.0', id: request.id, result: {
        context: {slot: options.slot ?? 447_100_000, apiVersion: '3.1.10'},
        value: (request.params[0] as string[]).map(item => values[item] ?? null),
      }};
    return new Response(JSON.stringify(body), {status: 200, headers: {'content-type': 'application/json'}});
  }) as unknown as typeof globalThis.fetch;
}

function simulationFetch(options: {postTaker?: number; postSource?: bigint; postDestination?: bigint;
  err?: unknown; unitsConsumed?: number; slot?: number; genesis?: string; calls?: RpcCall[]; stockMint?: Address} = {}): typeof globalThis.fetch {
  return (async (_url: string | URL, init?: {body?: string}) => {
    const request = JSON.parse(String(init?.body)) as {id: string; method: string; params: unknown[]};
    options.calls?.push({method: request.method, params: request.params});
    if (request.method === 'getGenesisHash') {
      return new Response(JSON.stringify({jsonrpc: '2.0', id: request.id,
        result: options.genesis ?? STOCK_DRAFT_MAINNET_GENESIS}),
      {status: 200, headers: {'content-type': 'application/json'}});
    }
    const accounts = [
      rpcAccount(new Uint8Array(), KNOWN_PROGRAMS.system, options.postTaker ?? 39_995_000),
      rpcAccount(Uint8Array.from(getLegacyTokenEncoder().encode({
        mint: usdcMint, owner: taker, amount: options.postSource ?? 15_000_000n, delegate: null,
        state: LegacyAccountState.Initialized, isNative: null, delegatedAmount: 0n, closeAuthority: null,
      })), KNOWN_PROGRAMS.token, 2_039_280),
      rpcAccount(Uint8Array.from(getTokenEncoder().encode({
        mint: options.stockMint ?? aaplxMint, owner: taker, amount: options.postDestination ?? QUOTED_OUT, delegate: null,
        state: AccountState.Initialized, isNative: null, delegatedAmount: 0n, closeAuthority: null,
        extensions: [{__kind: 'ImmutableOwner'}],
      })), KNOWN_PROGRAMS.token2022, 2_157_600),
    ];
    return new Response(JSON.stringify({jsonrpc: '2.0', id: request.id, result: {
      context: {slot: options.slot ?? 447_100_005, apiVersion: '3.1.10'},
      value: {err: options.err ?? null, logs: ['Program log: ok'], unitsConsumed: options.unitsConsumed ?? 180_000,
        accounts, returnData: null},
    }}), {status: 200, headers: {'content-type': 'application/json'}});
  }) as unknown as typeof globalThis.fetch;
}

function prepared(overrides: {message?: CompiledTransactionMessage & {lifetimeToken: string}} = {}) {
  const clock = {now: Date.parse(at(3))};
  const draft = bindStockOrderDraft(payload({}, overrides.message ?? swapMessage()), context(clock));
  const bound = binding(draft);
  const structure = inspectStockDraftStructure(draft, bound);
  return {clock, draft, binding: bound, structure, resolved: resolvedAccounts(structure)};
}

const semanticsReader = (fetch: typeof globalThis.fetch, clock: {now: number}) =>
  new SolanaMainnetStockOrderSemanticsReader({rpcUrl: 'https://rpc.example', fetch, now: () => clock.now});
const simulator = (fetch: typeof globalThis.fetch, clock: {now: number}) =>
  new SolanaMainnetStockOrderSimulator({rpcUrl: 'https://rpc.example', fetch, now: () => clock.now});

describe('gate 5: semantics', () => {
  it('decodes every instruction, observes every account and bounds the fee', async () => {
    const calls: RpcCall[] = [];
    const base = prepared();
    const semantics = await semanticsReader(semanticsFetch({calls}), base.clock)
      .read({draft: base.draft, binding: base.binding, structure: base.structure, resolvedAccounts: base.resolved});
    assert.equal(semantics.kind, 'solana_stock_order_semantics');
    assert.equal(semantics.transactionMessageHash, base.draft.summary.transactionMessageHash);
    assert.equal(semantics.observationSlot, '447100000');
    assert.equal(semantics.rpcApiVersion, '3.1.10');
    assert.deepEqual(calls.map(call => call.method), ['getGenesisHash', 'getMultipleAccounts']);
    // The reader cannot express a simulation or a send.
    assert.deepEqual(semantics.provenance.rpcMethods, ['getGenesisHash', 'getMultipleAccounts']);

    assert.deepEqual(semantics.instructions.map(item => item.programName),
      ['computeBudget', 'computeBudget', 'associatedToken', 'jupiterV6']);
    const route = semantics.instructions[3]!.decoded;
    assert.equal(route.program, 'jupiter_v6');
    assert.equal(route.program === 'jupiter_v6' ? route.userTransferAuthority : null, taker);
    assert.equal(route.program === 'jupiter_v6' ? route.inAmount : null, INPUT_RAW.toString());
    assert.equal(route.program === 'jupiter_v6' ? route.destinationMint : null, aaplxMint);
    assert.equal(semantics.computeBudget.unitLimit, COMPUTE_LIMIT);
    assert.equal(semantics.computeBudget.unitPriceMicroLamports, '1000');
    assert.equal(semantics.feeEstimate.baseLamports, '5000');
    assert.equal(semantics.feeEstimate.priorityLamportsUpperBound, '420');
    assert.equal(semantics.feeEstimate.totalLamportsUpperBound, '5420');

    assert.equal(semantics.candidate.takerInputAssociatedAccount.length > 0, true);
    assert.equal(semantics.programs.length, 3);
    for (const program of semantics.programs) assert.equal(program.owner, 'BPFLoaderUpgradeab1e11111111111111111111111');
    const destination = semantics.accounts.find(item => item.address === destinationAta);
    assert.equal(destination?.state.kind, 'token_account');
    assert.equal(semantics.assessment.status, 'semantics_decoded_but_unreconciled');
    assert.equal(semantics.assessment.readyForSimulation, false);
    assert.equal(semantics.assessment.signingEnabled, false);
    assert.equal(semantics.assessment.transactionTerms, 'unverified');
    assert.ok(Object.isFrozen(semantics) && Object.isFrozen(semantics.instructions));
    // No instruction bytes leave the reader.
    const serialized = JSON.stringify(semantics);
    assert.ok(!serialized.includes(Buffer.from(routeData()).toString('base64')));
  });

  it('refuses a mismatched report, the wrong cluster and an unsupported program', async () => {
    const base = prepared();
    const reader = semanticsReader(semanticsFetch(), base.clock);
    await assert.rejects(reader.read({draft: base.draft, binding: base.binding, structure: base.structure,
      resolvedAccounts: {...base.resolved, transactionMessageHash: '0'.repeat(64)} as ResolvedStockTransactionAccounts}),
    (error: unknown) => error instanceof StockOrderSemanticsError && error.code === 'SEMANTICS_STRUCTURE_MISMATCH');
    const wrongCluster = semanticsReader(semanticsFetch({genesis: 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG'}), base.clock);
    await assert.rejects(wrongCluster.read({draft: base.draft, binding: base.binding, structure: base.structure,
      resolvedAccounts: base.resolved}),
    (error: unknown) => error instanceof StockOrderSemanticsError && error.code === 'SEMANTICS_WRONG_NETWORK');

    // A memo-free but unknown program in the message is refused by name.
    const unknownProgram = prepared({message: swapMessage({instructions: [
      {programAddressIndex: 3, accountIndices: [], data: Uint8Array.from([1])},
    ]})});
    await assert.rejects(semanticsReader(semanticsFetch(), unknownProgram.clock).read({
      draft: unknownProgram.draft, binding: unknownProgram.binding, structure: unknownProgram.structure,
      resolvedAccounts: resolvedAccounts(unknownProgram.structure),
    }), (error: unknown) => error instanceof StockOrderSemanticsError && error.code === 'SEMANTICS_PROGRAM_UNSUPPORTED');
  });

  it('refuses a program account that is not executable and an expired draft', async () => {
    const base = prepared();
    const values = accountValues({[KNOWN_PROGRAMS.jupiterV6]:
      rpcAccount(new Uint8Array(36), 'BPFLoaderUpgradeab1e11111111111111111111111', 1_000_000, false)});
    await assert.rejects(semanticsReader(semanticsFetch({values}), base.clock).read({
      draft: base.draft, binding: base.binding, structure: base.structure, resolvedAccounts: base.resolved,
    }), (error: unknown) => error instanceof StockOrderSemanticsError && error.code === 'SEMANTICS_PROGRAM_NOT_EXECUTABLE');

    const expired = prepared();
    expired.clock.now = Date.parse(expired.draft.summary.notAfter);
    await assert.rejects(semanticsReader(semanticsFetch(), expired.clock).read({
      draft: expired.draft, binding: expired.binding, structure: expired.structure,
      resolvedAccounts: expired.resolved,
    }), (error: unknown) => error instanceof StockOrderSemanticsError && error.code === 'SEMANTICS_DRAFT_EXPIRED');
  });
});

describe('gate 6: terms reconciliation', () => {
  async function semanticsFor(base = prepared(), fetch = semanticsFetch()) {
    return {base, semantics: await semanticsReader(fetch, base.clock).read({
      draft: base.draft, binding: base.binding, structure: base.structure, resolvedAccounts: base.resolved})};
  }

  it('proves the decoded swap preserves the approved candidate', async () => {
    const {base, semantics} = await semanticsFor();
    const report = reconcileStockOrderTerms({summary: base.draft.summary, semantics, now: base.clock.now});
    assert.equal(report.kind, 'stock_order_terms_reconciliation');
    assert.equal(report.swap.variant, 'route');
    assert.equal(report.swap.taker, taker);
    assert.equal(report.swap.inputAmountRaw, INPUT_RAW.toString());
    assert.equal(report.swap.minimumOutputAmountRaw, MINIMUM_OUT.toString());
    assert.equal(report.swap.slippageBps, SLIPPAGE_BPS);
    assert.equal(report.swap.platformFeeBps, 0);
    assert.equal(report.candidate.minimumOutputFloorRaw, MINIMUM_OUT.toString());
    assert.equal(report.accountState.source.amountRaw, '25000000');
    assert.equal(report.accountState.destination.exists, true);
    assert.equal(report.accountState.outputMint.decimals, 8);
    assert.equal(report.accountState.outputMint.paused, false);
    assert.deepEqual(report.effects.createdAccounts, []);
    assert.equal(report.cost.feeLamportsUpperBound, '5420');
    assert.equal(report.cost.rentLamportsUpperBound, '0');
    // The issuer's extensions stay visible as explicit review flags.
    assert.deepEqual([...report.reviewFlags].sort(), ['output_mint_pausable', 'output_mint_permanent_delegate',
      'output_mint_transfer_hook_extension'].sort());
    assert.ok(report.checks.length >= 8);
    assert.ok(report.checks.every(check => check.passed));
    assert.equal(report.assessment.status, 'terms_reconciled_but_unsimulated');
    assert.equal(report.assessment.readyForSimulation, true);
    assert.equal(report.assessment.approvable, false);
    assert.equal(report.assessment.signingEnabled, false);
    assert.equal(report.assessment.simulation, 'not_run');
    assert.match(reconciliationDigest(report), /^[0-9a-f]{64}$/);
  });

  it('refuses an insufficient balance, an insufficient SOL reserve and a frozen source', async () => {
    const short = await semanticsFor(prepared(), semanticsFetch({values: accountValues({
      [sourceAta]: rpcAccount(Uint8Array.from(getLegacyTokenEncoder().encode({
        mint: usdcMint, owner: taker, amount: 1n, delegate: null, state: LegacyAccountState.Initialized,
        isNative: null, delegatedAmount: 0n, closeAuthority: null,
      })), KNOWN_PROGRAMS.token, 2_039_280),
    })}));
    assert.throws(() => reconcileStockOrderTerms({summary: short.base.draft.summary, semantics: short.semantics,
      now: short.base.clock.now}), (error: unknown) => error instanceof StockOrderReconciliationError &&
      error.code === 'RECONCILIATION_SOURCE_BALANCE_INSUFFICIENT');

    const poor = await semanticsFor(prepared(), semanticsFetch({values: accountValues({
      [taker]: rpcAccount(new Uint8Array(), KNOWN_PROGRAMS.system, 100),
    })}));
    assert.throws(() => reconcileStockOrderTerms({summary: poor.base.draft.summary, semantics: poor.semantics,
      now: poor.base.clock.now}), (error: unknown) => error instanceof StockOrderReconciliationError &&
      error.code === 'RECONCILIATION_TAKER_SOL_INSUFFICIENT');

    const frozen = await semanticsFor(prepared(), semanticsFetch({values: accountValues({
      [sourceAta]: rpcAccount(Uint8Array.from(getLegacyTokenEncoder().encode({
        mint: usdcMint, owner: taker, amount: 25_000_000n, delegate: null, state: LegacyAccountState.Frozen,
        isNative: null, delegatedAmount: 0n, closeAuthority: null,
      })), KNOWN_PROGRAMS.token, 2_039_280),
    })}));
    assert.throws(() => reconcileStockOrderTerms({summary: frozen.base.draft.summary, semantics: frozen.semantics,
      now: frozen.base.clock.now}), (error: unknown) => error instanceof StockOrderReconciliationError &&
      error.code === 'RECONCILIATION_SOURCE_ACCOUNT_STATE_INVALID');
  });

  it('refuses a paused output mint and a swap that pays a stranger', async () => {
    const paused = await semanticsFor(prepared(), semanticsFetch({values: accountValues({
      [aaplxMint]: rpcAccount(Uint8Array.from(getMintEncoder().encode({
        mintAuthority: key('aaplx-authority'), supply: 1n, decimals: 8, isInitialized: true,
        freezeAuthority: key('aaplx-freeze'),
        extensions: [{__kind: 'PausableConfig', authority: key('pause-authority'), paused: true}],
      })), KNOWN_PROGRAMS.token2022, 4_000_000),
    })}));
    assert.throws(() => reconcileStockOrderTerms({summary: paused.base.draft.summary, semantics: paused.semantics,
      now: paused.base.clock.now}), (error: unknown) => error instanceof StockOrderReconciliationError &&
      error.code === 'RECONCILIATION_MINT_STATE_INVALID');

    // The route pays a destination account that is not the taker's own.
    const stranger = prepared({message: swapMessage({instructions: [
      {programAddressIndex: 6, accountIndices: [7, 0, 1, 3, 6, 10, 6, 11, 6], data: routeData()},
    ]})});
    const strangerSemantics = await semanticsFor(stranger);
    assert.throws(() => reconcileStockOrderTerms({summary: stranger.draft.summary,
      semantics: strangerSemantics.semantics, now: stranger.clock.now}),
    (error: unknown) => error instanceof StockOrderReconciliationError &&
      error.code === 'RECONCILIATION_DESTINATION_ACCOUNT_MISMATCH');
  });

  it('refuses a widened slippage, a raised fee and an unexpected token movement', async () => {
    for (const [changes, code] of [
      [{slippageBps: 900}, 'RECONCILIATION_SLIPPAGE_EXCEEDED'],
      [{feeBps: 200}, 'RECONCILIATION_FEE_CAP_EXCEEDED'],
      [{inAmount: 9_000_000n}, 'RECONCILIATION_INPUT_AMOUNT_MISMATCH'],
      [{quotedOut: 100n}, 'RECONCILIATION_OUTPUT_FLOOR_VIOLATED'],
    ] as const) {
      const base = prepared({message: swapMessage({instructions: [
        {programAddressIndex: 6, accountIndices: [7, 0, 1, 2, 6, 10, 6, 11, 6], data: routeData(changes)},
      ]})});
      const semantics = await semanticsFor(base);
      assert.throws(() => reconcileStockOrderTerms({summary: base.draft.summary, semantics: semantics.semantics,
        now: base.clock.now}), (error: unknown) => error instanceof StockOrderReconciliationError &&
        error.code === code, Object.keys(changes).join());
    }
    // A top-level token transfer beside the swap is never admitted.
    const withTransfer = prepared({message: swapMessage({instructions: [
      {programAddressIndex: 7, accountIndices: [1, 3, 0], data: Uint8Array.from([3, ...u64(1n)])},
      {programAddressIndex: 6, accountIndices: [7, 0, 1, 2, 6, 10, 6, 11, 6], data: routeData()},
    ]})});
    const semantics = await semanticsFor(withTransfer);
    assert.throws(() => reconcileStockOrderTerms({summary: withTransfer.draft.summary,
      semantics: semantics.semantics, now: withTransfer.clock.now}),
    (error: unknown) => error instanceof StockOrderReconciliationError &&
      error.code === 'RECONCILIATION_UNEXPECTED_MOVEMENT');
  });

  it('refuses a missing swap, two swaps and an expired candidate', async () => {
    const none = prepared({message: swapMessage({instructions: [
      {programAddressIndex: 4, accountIndices: [], data: Uint8Array.from(
        getSetComputeUnitLimitInstructionDataEncoder().encode({units: 1_000}))},
    ]})});
    const noneSemantics = await semanticsFor(none);
    assert.throws(() => reconcileStockOrderTerms({summary: none.draft.summary, semantics: noneSemantics.semantics,
      now: none.clock.now}), (error: unknown) => error instanceof StockOrderReconciliationError &&
      error.code === 'RECONCILIATION_SWAP_INSTRUCTION_MISSING');

    const two = prepared({message: swapMessage({instructions: [
      {programAddressIndex: 6, accountIndices: [7, 0, 1, 2, 6, 10, 6, 11, 6], data: routeData()},
      {programAddressIndex: 6, accountIndices: [7, 0, 1, 2, 6, 10, 6, 11, 6], data: routeData()},
    ]})});
    const twoSemantics = await semanticsFor(two);
    assert.throws(() => reconcileStockOrderTerms({summary: two.draft.summary, semantics: twoSemantics.semantics,
      now: two.clock.now}), (error: unknown) => error instanceof StockOrderReconciliationError &&
      error.code === 'RECONCILIATION_MULTIPLE_SWAPS');

    const base = prepared();
    const semantics = await semanticsFor(base);
    assert.throws(() => reconcileStockOrderTerms({summary: base.draft.summary, semantics: semantics.semantics,
      now: Date.parse(base.draft.summary.notAfter)}),
    (error: unknown) => error instanceof StockOrderReconciliationError && error.code === 'RECONCILIATION_EXPIRED');
  });
});

describe('gate 7: isolated simulation', () => {
  async function reconciled() {
    const base = prepared();
    const semantics = await semanticsReader(semanticsFetch(), base.clock).read({
      draft: base.draft, binding: base.binding, structure: base.structure, resolvedAccounts: base.resolved});
    const reconciliation = reconcileStockOrderTerms({summary: base.draft.summary, semantics, now: base.clock.now});
    return {base, semantics, reconciliation};
  }

  it('never signs or sends, and requires the reconciliation to admit the draft', async () => {
    const {base, semantics, reconciliation} = await reconciled();
    // Without evidence the draft still refuses to become simulation ready.
    assert.throws(() => assertStockDraftReadyForSimulation(base.draft),
      (error: unknown) => error instanceof StockOrderDraftError && error.code === 'STOCK_DRAFT_REVIEW_REQUIRED');
    await assert.rejects(admitStockDraftForSimulation(base.draft, base.binding, {
      transactionMessageHash: reconciliation.transactionMessageHash, draftBindingHash: reconciliation.draftBindingHash,
      candidateTermsHash: reconciliation.candidateTermsHash, status: 'terms_reconciled_but_unsimulated',
      readyForSimulation: false as unknown as true,
    }), (error: unknown) => error instanceof StockOrderDraftError && error.code === 'STOCK_DRAFT_REVIEW_REQUIRED');

    const calls: RpcCall[] = [];
    const simulation = await simulator(simulationFetch({calls}), base.clock)
      .simulate({draft: base.draft, binding: base.binding, semantics, reconciliation});
    assert.deepEqual(calls.map(call => call.method), ['getGenesisHash', 'simulateTransaction']);
    const config = calls[1]!.params[1] as Record<string, unknown>;
    assert.equal(config['sigVerify'], false);
    assert.equal(config['replaceRecentBlockhash'], false);
    assert.equal(config['commitment'], 'finalized');
    assert.deepEqual((config['accounts'] as {addresses: string[]}).addresses, [taker, sourceAta, destinationAta]);
    assert.deepEqual(simulation.provenance.rpcMethods, ['getGenesisHash', 'simulateTransaction']);
    assert.equal(simulation.outcome.error, null);
    assert.equal(simulation.outcome.unitsConsumed, '180000');
    assert.equal(simulation.outcome.computeUnitLimit, COMPUTE_LIMIT);
    assert.equal(simulation.effects.inputSpentRaw, INPUT_RAW.toString());
    assert.equal(simulation.effects.outputReceivedRaw, QUOTED_OUT.toString());
    assert.equal(simulation.effects.takerLamportsSpent, '5000');
    assert.equal(simulation.assessment.status, 'simulated_effects_match_reviewed_terms');
    assert.equal(simulation.assessment.userApproval, 'required');
    assert.equal(simulation.assessment.approvable, false);
    assert.equal(simulation.assessment.signingEnabled, false);
    assert.equal(simulation.assessment.broadcastEnabled, false);
    assert.equal(simulation.reconciliationDigestSha256, reconciliationDigest(reconciliation));
  });

  it('refuses a failed simulation, a stale slot and effects that miss the reviewed terms', async () => {
    for (const [options, code] of [
      [{err: {InstructionError: [3, {Custom: 6001}]}}, 'SIMULATION_TRANSACTION_FAILED'],
      [{err: 'BlockhashNotFound'}, 'SIMULATION_BLOCKHASH_EXPIRED'],
      [{slot: 1}, 'SIMULATION_OBSERVATION_STALE'],
      [{postDestination: MINIMUM_OUT - 1n}, 'SIMULATION_EFFECTS_MISMATCH'],
      [{postSource: 20_000_000n}, 'SIMULATION_EFFECTS_MISMATCH'],
      [{postTaker: 1_000}, 'SIMULATION_EFFECTS_MISMATCH'],
      [{unitsConsumed: COMPUTE_LIMIT + 1}, 'SIMULATION_COMPUTE_EXCEEDED'],
      [{genesis: 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG'}, 'SIMULATION_WRONG_NETWORK'],
    ] as const) {
      const {base, semantics, reconciliation} = await reconciled();
      await assert.rejects(simulator(simulationFetch(options), base.clock)
        .simulate({draft: base.draft, binding: base.binding, semantics, reconciliation}),
      (error: unknown) => error instanceof StockOrderSimulationError && error.code === code, Object.keys(options).join());
    }
  });

  it('keeps provider failure detail out of the error', async () => {
    const {base, semantics, reconciliation} = await reconciled();
    try {
      await simulator(simulationFetch({err: {InstructionError: [3, {Custom: 6001}]}}), base.clock)
        .simulate({draft: base.draft, binding: base.binding, semantics, reconciliation});
      assert.fail('expected a simulation failure');
    } catch (error) {
      assert.ok(error instanceof StockOrderSimulationError);
      assert.equal(error.message, 'The stock order simulation did not confirm the reviewed terms.');
      assert.deepEqual(error.failure, {kind: 'InstructionError:Custom', instructionIndex: 3, customCode: 6001});
    }
  });
});

describe('composed review', () => {
  function stages(base: ReturnType<typeof prepared>, overrides: {semanticsFetchOptions?: Parameters<typeof semanticsFetch>[0];
    simulationFetchOptions?: Parameters<typeof simulationFetch>[0]} = {}) {
    return {
      lookupResolver: {resolve: async () => resolvedAccounts(base.structure)},
      lifetimeVerifier: {verify: async () => lifetimeEvidence(base.structure)},
      semanticsReader: semanticsReader(semanticsFetch(overrides.semanticsFetchOptions ?? {}), base.clock),
      simulator: simulator(simulationFetch(overrides.simulationFetchOptions ?? {}), base.clock),
      now: () => base.clock.now,
    };
  }

  it('produces one expiring reviewed intent bound to every stage', async () => {
    const base = prepared();
    const {intent, evidence} = await reviewStockOrder(base.draft, base.binding, stages(base));
    assert.equal(intent.kind, 'reviewed_stock_order_intent');
    assert.equal(intent.userId, userId);
    assert.equal(intent.taker, taker);
    assert.equal(intent.transactionMessageHash, base.draft.summary.transactionMessageHash);
    assert.equal(intent.candidateTermsHash, base.draft.summary.userApproval.candidateTermsHash);
    assert.deepEqual(intent.assessment.stagesCompleted,
      ['structure', 'lookup_tables', 'lifetime', 'semantics', 'reconciliation', 'simulation']);
    assert.equal(intent.assessment.status, 'reviewed_pending_approval');
    assert.equal(intent.assessment.signingEnabled, false);
    assert.equal(intent.assessment.broadcastEnabled, false);
    assert.equal(intent.assessment.financialOperationsEnabled, false);
    assert.equal(intent.approval.status, 'required');
    assert.equal(intent.approval.walletPossession, 'required_before_signing');
    assert.equal(intent.terms.inputAmountRaw, INPUT_RAW.toString());
    assert.equal(intent.terms.minimumOutputAmountRaw, MINIMUM_OUT.toString());
    assert.equal(intent.terms.simulatedOutputReceivedRaw, QUOTED_OUT.toString());
    assert.match(intent.reviewDigestSha256, /^[0-9a-f]{64}$/);
    assert.equal(intent.evidence.semanticsSha256, evidence.semantics.provenance.digestSha256);
    assert.equal(intent.evidence.simulationSha256, evidence.simulation.provenance.digestSha256);
    assert.equal(intent.evidence.lastValidBlockHeight, '1150');
    // The validity window never outlives the draft's own cutoff.
    const expires = Date.parse(intent.expiresAt);
    assert.ok(expires <= Date.parse(base.draft.summary.notAfter));
    assert.ok(expires <= base.clock.now + REVIEW_VALIDITY_MS);
    assert.equal(reviewedIntentUsable(intent, base.clock.now), true);
    assert.equal(reviewedIntentUsable(intent, expires), false);
    // No raw transaction bytes are anywhere in the intent.
    const serialized = JSON.stringify(intent);
    assert.ok(!serialized.includes(wire().toString('base64')));
    assert.ok(Object.isFrozen(intent) && Object.isFrozen(evidence));
  });

  it('refuses when a stage reports a different transaction and when the draft expired', async () => {
    const base = prepared();
    const mismatched = {...stages(base), lifetimeVerifier: {verify: async () =>
      ({...lifetimeEvidence(base.structure), transactionMessageHash: '0'.repeat(64)}) as VerifiedStockOrderLifetime}};
    await assert.rejects(reviewStockOrder(base.draft, base.binding, mismatched),
      (error: unknown) => error instanceof StockOrderReviewError && error.code === 'REVIEW_EVIDENCE_MISMATCH');

    const expired = prepared();
    const expiredStages = stages(expired);
    expired.clock.now = Date.parse(expired.draft.summary.notAfter);
    await assert.rejects(reviewStockOrder(expired.draft, expired.binding, expiredStages),
      (error: unknown) => error instanceof StockOrderReviewError && error.code === 'REVIEW_EXPIRED');
  });

  it('refuses a binding that does not belong to the draft', async () => {
    const base = prepared();
    await assert.rejects(reviewStockOrder(base.draft, binding(base.draft, {verifiedTaker: poolAccount}), stages(base)),
      (error: unknown) => error instanceof StockOrderReviewError && error.code === 'REVIEW_EVIDENCE_MISMATCH');
  });

  it('stops at the failing gate instead of returning a partial review', async () => {
    const base = prepared();
    await assert.rejects(reviewStockOrder(base.draft, base.binding,
      stages(base, {simulationFetchOptions: {err: 'AccountNotFound'}})),
    (error: unknown) => error instanceof StockOrderSimulationError && error.code === 'SIMULATION_TRANSACTION_FAILED');
  });
});

describe('current Jupiter order regressions', () => {
  it('reviews V2 terms with a real-sized executable account response and rejects changed mints, output programs and excessive fees', async () => {
    const instructions = [...swapMessage().instructions];
    instructions[3] = {programAddressIndex: 6, accountIndices: [0, 1, 2, 9, 10, 7, 12, 6, 11, 6, 3],
      data: Uint8Array.from([...anchor('route_v2'), ...u64(INPUT_RAW), ...u64(QUOTED_OUT), 50, 0, 0, 0, 0, 0, ...u32(1), 0, 16, 39, 0, 1])};
    const base = prepared({message: swapMessage({instructions})});
    const values = accountValues({[KNOWN_PROGRAMS.associatedToken]:
      rpcAccount(new Uint8Array(220_000), 'BPFLoader2111111111111111111111111111111111', 1_000_000, true)});
    const semantics = await semanticsReader(semanticsFetch({values}), base.clock).read({
      draft: base.draft, binding: base.binding, structure: base.structure, resolvedAccounts: base.resolved});
    const args = {summary: base.draft.summary, semantics, now: base.clock.now};
    assert.equal(reconcileStockOrderTerms(args).swap.variant, 'route_v2');
    for (const [mutation, code] of [
      [{sourceMint: aaplxMint}, 'RECONCILIATION_MINT_MISMATCH'],
      [{destinationTokenProgram: KNOWN_PROGRAMS.token}, 'RECONCILIATION_TOKEN_PROGRAM_MISMATCH'],
      [{platformFeeBps: 300}, 'RECONCILIATION_FEE_CAP_EXCEEDED'],
    ] as const) {
      const changed = {...semantics, instructions: semantics.instructions.map(i => i.decoded.program === 'jupiter_v6'
        ? {...i, decoded: {...i.decoded, ...mutation}} : i)};
      assert.throws(() => reconcileStockOrderTerms({...args, semantics: changed}),
        (e: unknown) => e instanceof StockOrderReconciliationError && e.code === code);
    }
  });

  it('admits only a fresh canonical intermediate WSOL account closed back to its owner', async () => {
    const base = prepared();
    const semantics = await semanticsReader(semanticsFetch(), base.clock).read({
      draft: base.draft, binding: base.binding, structure: base.structure, resolvedAccounts: base.resolved});
    const wrapped = semantics.candidate.takerWrappedSolAssociatedAccount;
    const create = {...semantics.instructions[2]!, decoded: {program: 'associated_token' as const, kind: 'create_idempotent' as const,
      payer: taker, owner: taker, associatedAccount: wrapped, mint: JUPITER_QUOTE_ASSETS.SOL.mint, tokenProgram: KNOWN_PROGRAMS.token}};
    const close = {...semantics.instructions[2]!, decoded: {program: 'token' as const, kind: 'close_account' as const,
      account: wrapped, destination: taker, authority: taker}};
    const instructions = [create, ...semantics.instructions, close];
    const args = {summary: base.draft.summary, now: base.clock.now, semantics: {...semantics, instructions}};
    const report = reconcileStockOrderTerms(args);
    assert.deepEqual(report.effects.closedAccounts, [wrapped]);
    assert.equal(report.cost.rentLamportsUpperBound, '2039280');
    for (const changedInstructions of [instructions.slice(0, -1), [...instructions.slice(0, -1), {...close,
      decoded: {...close.decoded, destination: poolAccount}}], [{...create, decoded: {...create.decoded, associatedAccount: poolAccount}}, ...instructions.slice(1)]]) {
      assert.throws(() => reconcileStockOrderTerms({...args, semantics: {...semantics, instructions: changedInstructions}}),
        (e: unknown) => e instanceof StockOrderReconciliationError && e.code === 'RECONCILIATION_UNEXPECTED_MOVEMENT');
    }
    const existing = {...semantics.accounts.find(a => a.address === sourceAta)!, address: wrapped};
    assert.throws(() => reconcileStockOrderTerms({...args, semantics: {...args.semantics, accounts: [...semantics.accounts, existing]}}),
      (e: unknown) => e instanceof StockOrderReconciliationError && e.code === 'RECONCILIATION_UNEXPECTED_MOVEMENT');
  });
});


describe('multi-stock composed review', () => {
  it('reviews every pinned mint with canonical account derivation and exact simulated outputs', async () => {
    for (const stock of STOCK_TRADING_ASSETS.slice(1)) {
      const stockMint = address(stock.mint);
      const stockAta = await deriveAssociatedTokenAddress(taker, stock.mint, stock.tokenProgram);
      const original = swapMessage();
      const message = {...original, staticAccounts: original.staticAccounts.map(item =>
        item === aaplxMint ? stockMint : item === destinationAta ? address(stockAta) : item)};
      const ref = estimate();
      const quote: StockEstimate = {...ref, assetId: stock.assetId, variantMint: stock.mint,
        output: {...ref.output, symbol: stock.symbol, mint: stock.mint}};
      const clock = {now: Date.parse(at(3))};
      const draft = bindStockOrderDraft(payload({outputMint: stock.mint}, message), {...context(clock), expected: quote});
      const bound = binding(draft);
      const structure = inspectStockDraftStructure(draft, bound);
      const values = accountValues();
      values[stockMint] = values[aaplxMint]; delete values[aaplxMint];
      delete values[destinationAta];
      values[stockAta] = rpcAccount(Uint8Array.from(getTokenEncoder().encode({
        mint: stockMint, owner: taker, amount: 0n, delegate: null, state: AccountState.Initialized,
        isNative: null, delegatedAmount: 0n, closeAuthority: null, extensions: [{__kind: 'ImmutableOwner'}],
      })), KNOWN_PROGRAMS.token2022, 2_157_600);
      const {intent} = await reviewStockOrder(draft, bound, {
        lookupResolver: {resolve: async () => resolvedAccounts(structure, message.staticAccounts)},
        lifetimeVerifier: {verify: async () => lifetimeEvidence(structure)},
        semanticsReader: semanticsReader(semanticsFetch({values}), clock),
        simulator: simulator(simulationFetch({stockMint}), clock), now: () => clock.now,
      });
      assert.equal(intent.terms.outputMint, stock.mint);
      assert.equal(intent.terms.simulatedOutputReceivedRaw, QUOTED_OUT.toString());
      assert.equal(intent.approval.status, 'required');
    }
  });
});
