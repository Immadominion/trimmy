import assert from 'node:assert/strict';
import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, sign } from 'node:crypto';
import { describe, it } from 'node:test';
import { address, getAddressDecoder, getCompiledTransactionMessageEncoder, getTransactionEncoder } from '@solana/kit';
import type { Address, CompiledTransactionMessage, TransactionMessageBytes } from '@solana/kit';
import { AccountState, getMintEncoder, getTokenEncoder,
  getCreateAssociatedTokenIdempotentInstructionDataEncoder, getTransferCheckedInstructionDataEncoder } from '@solana-program/token-2022';
import type { ExtensionArgs } from '@solana-program/token-2022';
import { getMintEncoder as getLegacyMintEncoder, getTokenEncoder as getLegacyTokenEncoder,
  AccountState as LegacyAccountState } from '@solana-program/token';
import { getSetComputeUnitLimitInstructionDataEncoder,
  getSetComputeUnitPriceInstructionDataEncoder } from '@solana-program/compute-budget';
import { STOCK_TRADING_ASSETS } from '../src/stock-trading-catalog.js';
import { JUPITER_QUOTE_ASSETS, orderSlippageBps, parseEstimate, stockQuoteAsset } from '../src/jupiter-quote-reader.js';
import { STOCK_ESTIMATE_ASSET } from '../src/stock-estimates.js';
import type { StockEstimate } from '../src/stock-estimates.js';
import { KNOWN_PROGRAMS } from '../src/solana-instruction-decoders.js';
import { deriveAssociatedTokenAddress } from '../src/solana-account-state.js';
import { bindStockOrderDraft, inspectStockDraftStructure, StockOrderDraftError,
  STOCK_DRAFT_MAINNET_GENESIS } from '../src/stock-order-draft.js';
import type { StockDraftBinding, StockOrderDraft, StockOrderDraftContext,
  StockDraftStructuralInspection } from '../src/stock-order-draft.js';
import type { ResolvedStockTransactionAccounts } from '../src/stock-order-lookup-resolver.js';
import type { VerifiedStockOrderLifetime } from '../src/stock-order-lifetime-verifier.js';
import { SolanaMainnetStockOrderSemanticsReader } from '../src/stock-order-semantics.js';
import { reconcileStockOrderTerms, StockOrderReconciliationError } from '../src/stock-order-terms-reconciliation.js';
import { SolanaMainnetStockOrderSimulator } from '../src/stock-order-simulation.js';
import { reviewStockOrder } from '../src/stock-order-review.js';
import { inspectUnsignedV0TransactionStructure, StockTransactionStructureError } from '../src/stock-order-transaction-inspector.js';
import { LiveStockOrders, verifyReviewedSignature } from '../src/live-stock-orders.js';
import type { LiveOrder, LiveOrderStore } from '../src/live-stock-orders.js';
import type { ReviewedStockOrderIntent } from '../src/stock-order-review.js';

// Deterministic on-curve keys; nothing here signs a transaction for a real wallet.
function key(label: string): Address {
  const seed = createHash('sha256').update(`trimmy-rfq-${label}`).digest();
  const pkcs8 = Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]);
  const spki = createPublicKey(createPrivateKey({key: pkcs8, format: 'der', type: 'pkcs8'}))
    .export({format: 'der', type: 'spki'});
  return getAddressDecoder().decode(Uint8Array.from(spki.subarray(spki.length - 32)));
}
const taker = key('taker');
const maker = key('maker');
const usdcMint = address(JUPITER_QUOTE_ASSETS.USDC.mint);
const stockMint = address(STOCK_ESTIMATE_ASSET.variantMint);
const sourceAta = address(await deriveAssociatedTokenAddress(taker, usdcMint, 'token'));
const destinationAta = address(await deriveAssociatedTokenAddress(taker, stockMint, 'token_2022'));
const makerInput = key('maker-usdc');
const makerOutput = key('maker-stock');
const userId = '12345678-1234-4567-8123-123456789abc';
const at = (seconds: number) => `2026-09-15T09:00:${String(seconds).padStart(2, '0')}.000Z`;
const NOW = Date.parse(at(3));
const EXPIRE_AT = BigInt(Math.floor(NOW / 1000) + 55);
const INPUT_RAW = 10_000_000n;
const OUTPUT_RAW = 2_972_350n;
const sha256 = (value: Uint8Array | string) => createHash('sha256').update(value).digest('hex');
const u64 = (value: bigint) => { const out: number[] = []; let rest = value; for (let i = 0; i < 8; i += 1) { out.push(Number(rest & 0xffn)); rest >>= 8n; } return out; };
const fillDiscriminator = [...createHash('sha256').update('global:fill').digest().subarray(0, 8)];
const fillData = (options: {input?: bigint; output?: bigint; expireAt?: bigint; feeBps?: number} = {}) => Uint8Array.from([
  ...fillDiscriminator, ...u64(options.input ?? INPUT_RAW), ...u64(options.output ?? OUTPUT_RAW), ...u64(options.expireAt ?? EXPIRE_AT),
  (options.feeBps ?? 10) & 0xff, ((options.feeBps ?? 10) >> 8) & 0xff, 0, 0, 0]);

/** A JupiterZ-shaped unsigned v0 order: maker pays the fee and signs first, the taker second. */
const STATIC: readonly Address[] = [
  maker, taker, sourceAta, makerInput, destinationAta, makerOutput,       // 0-5 signers and writable accounts
  address(KNOWN_PROGRAMS.computeBudget), address(KNOWN_PROGRAMS.associatedToken), address(KNOWN_PROGRAMS.orderEngine), // 6-8
  address(KNOWN_PROGRAMS.token), address(KNOWN_PROGRAMS.system), usdcMint, stockMint, address(KNOWN_PROGRAMS.token2022), // 9-13
];
type Message = CompiledTransactionMessage & {lifetimeToken: string};
function rfqMessage(options: {fill?: Uint8Array; fillAccounts?: number[]; extra?: CompiledTransactionMessage['instructions'];
  staticAccounts?: readonly Address[]; signers?: number} = {}): Message {
  return {
    version: 0,
    header: {numSignerAccounts: options.signers ?? 2, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 8},
    staticAccounts: [...(options.staticAccounts ?? STATIC)],
    lifetimeToken: getAddressDecoder().decode(new Uint8Array(32).fill(9)),
    instructions: [
      {programAddressIndex: 6, accountIndices: [], data: Uint8Array.from(getSetComputeUnitPriceInstructionDataEncoder().encode({microLamports: 1_000n}))},
      {programAddressIndex: 6, accountIndices: [], data: Uint8Array.from(getSetComputeUnitLimitInstructionDataEncoder().encode({units: 200_000}))},
      {programAddressIndex: 7, accountIndices: [1, 4, 1, 12, 10, 13], data: Uint8Array.from(getCreateAssociatedTokenIdempotentInstructionDataEncoder().encode({}))},
      {programAddressIndex: 8, accountIndices: options.fillAccounts ?? [1, 0, 2, 3, 4, 5, 11, 9, 12, 13, 10], data: options.fill ?? fillData()},
      ...(options.extra ?? []),
    ],
    addressTableLookups: [],
  } as unknown as Message;
}
function wire(message: Message, signed: Record<string, Uint8Array | null> = {}): Buffer {
  const messageBytes = getCompiledTransactionMessageEncoder().encode(message) as TransactionMessageBytes;
  const signers = message.staticAccounts.slice(0, message.header.numSignerAccounts);
  return Buffer.from(getTransactionEncoder().encode({messageBytes,
    signatures: Object.fromEntries(signers.map(signer => [signer, signed[signer] ?? null]))} as never));
}

function estimate(): StockEstimate {
  return {
    schemaVersion: 1, kind: 'indicative', network: 'solana:mainnet-beta', provider: 'jupiter-swap-v2',
    executable: false, walletChecked: false, networkFees: null,
    input: {symbol: 'USDC', mint: usdcMint, decimals: 6, amountRaw: INPUT_RAW.toString()},
    output: {symbol: 'AAPLx', mint: stockMint, decimals: 8, estimatedAmountRaw: OUTPUT_RAW.toString(), quotedMinimumAmountRaw: OUTPUT_RAW.toString()},
    slippageBps: 0, swapFee: {basisPoints: 10, mint: usdcMint}, router: 'jupiterz',
    requestedAt: at(0), receivedAt: at(1), refreshAfter: at(10), providerExpiresAt: new Date(Number(EXPIRE_AT) * 1000).toISOString(),
    assetId: 'apple', variantMint: stockMint, side: 'buy', executionEnabled: false, eligibility: 'unverified', amountUnits: 'raw_token_units',
  };
}
function context(clock: {now: number}): StockOrderDraftContext {
  const observation = {genesisHash: STOCK_DRAFT_MAINNET_GENESIS, blockHeight: '1000', observedAt: at(3)} as const;
  return {authenticatedUserId: userId, verifiedTaker: taker, expected: estimate(), requestStartedAt: at(2), chainObservation: observation,
    validityAuthority: {now: () => clock.now, readChainObservation: async () => ({...observation, blockHeight: '1001', observedAt: new Date(clock.now).toISOString()})}};
}
function payload(changes: Record<string, unknown> = {}, message = rfqMessage()): Record<string, unknown> {
  return {
    inputMint: usdcMint, outputMint: stockMint, inAmount: INPUT_RAW.toString(), outAmount: OUTPUT_RAW.toString(),
    otherAmountThreshold: OUTPUT_RAW.toString(), swapMode: 'ExactIn', slippageBps: 0, feeBps: 10, feeMint: usdcMint,
    router: 'jupiterz', swapType: 'rfq', mode: 'manual', taker, maker, gasless: true, signatureFeePayer: maker,
    prioritizationFeePayer: maker, rentFeePayer: taker, expireAt: EXPIRE_AT.toString(),
    transaction: wire(message).toString('base64'), requestId: 'rfq-order-1', ...changes,
  };
}
const binding = (draft: StockOrderDraft): StockDraftBinding => ({authenticatedUserId: userId, verifiedTaker: taker,
  requestId: draft.summary.requestId, transactionMessageHash: draft.summary.transactionMessageHash, bindingHash: draft.summary.bindingHash});
function resolved(structure: StockDraftStructuralInspection, staticAccounts: readonly Address[] = STATIC): ResolvedStockTransactionAccounts {
  return Object.freeze({
    schemaVersion: 1, kind: 'solana_v0_resolved_account_indexes', network: 'solana:mainnet-beta', genesisHash: STOCK_DRAFT_MAINNET_GENESIS,
    commitment: 'finalized', transactionHash: structure.transactionHash, transactionMessageHash: structure.transactionMessageHash,
    resolutionStartedAt: at(3), observedAt: at(3), firstObservationSlot: null, secondObservationSlot: null,
    accountIndexMap: Object.freeze(staticAccounts.map((value, accountIndex) => Object.freeze({accountIndex, address: value as string,
      signer: accountIndex < 2, writable: accountIndex <= 5, source: 'static' as const, staticAccountIndex: accountIndex}))),
    lookupTables: Object.freeze([]),
    provenance: Object.freeze({rpcMethods: Object.freeze(['getGenesisHash'] as const), tableAddressesRequested: Object.freeze([]), tableReadCount: 0 as const,
      rpcApiVersion: '3.1.10', retries: 0 as const, cacheUsed: false as const, observationsStable: true as const, digestSha256: sha256('resolved')}),
    assessment: Object.freeze({status: 'account_indexes_resolved_but_incomplete', clusterGenesis: 'verified', lookupTableAccounts: 'not_applicable',
      lookupTableFreshness: 'point_in_time_only', revalidationRequired: true, accountIndexResolution: 'complete', recentBlockhash: 'unverified',
      programOwnership: 'unverified', instructionSemantics: 'unverified', accountState: 'unverified', transactionTerms: 'unverified',
      simulation: 'not_run', approvable: false, readyForSimulation: false, signingEnabled: false, broadcastEnabled: false, financialOperationsEnabled: false}),
  }) as ResolvedStockTransactionAccounts;
}
const lifetime = (structure: StockDraftStructuralInspection): VerifiedStockOrderLifetime => Object.freeze({
  schemaVersion: 1, kind: 'solana_recent_blockhash_lifetime_evidence', network: 'solana:mainnet-beta', genesisHash: STOCK_DRAFT_MAINNET_GENESIS,
  commitment: 'finalized', transactionHash: structure.transactionHash, transactionMessageHash: structure.transactionMessageHash,
  draftBindingHash: structure.draftBindingHash, candidateTermsHash: structure.candidateTermsHash, verificationStartedAt: at(3), observedAt: at(3),
  lifetime: Object.freeze({token: structure.lifetimeToken.value, tokenSha256: sha256(structure.lifetimeToken.value), semanticKind: 'verified_recent_blockhash',
    mainnetRecency: 'verified_stable_finalized', admittedAtBlockHeight: '1000', providerLastValidBlockHeight: '1150', firstObservedBlockHeight: '1001',
    secondObservedBlockHeight: '1001', remainingBlocksAtSecondObservation: '149', providerHeightAssociation: 'bound_not_rpc_derived'}),
}) as unknown as VerifiedStockOrderLifetime;

const rpcAccount = (data: Uint8Array, owner: string, lamports: number, executable = false) =>
  ({data: [Buffer.from(data).toString('base64'), 'base64'], executable, lamports, owner, rentEpoch: 0, space: data.byteLength});
const STOCK_EXTENSIONS: ExtensionArgs[] = [
  {__kind: 'PausableConfig', authority: key('pause'), paused: false},
  {__kind: 'DefaultAccountState', state: AccountState.Initialized},
];
const legacyToken = (mint: Address, owner: Address, amount: bigint) => Uint8Array.from(getLegacyTokenEncoder().encode({mint, owner, amount,
  delegate: null, state: LegacyAccountState.Initialized, isNative: null, delegatedAmount: 0n, closeAuthority: null}));
const stockToken = (owner: Address, amount: bigint) => Uint8Array.from(getTokenEncoder().encode({mint: stockMint, owner, amount, delegate: null,
  state: AccountState.Initialized, isNative: null, delegatedAmount: 0n, closeAuthority: null, extensions: [{__kind: 'ImmutableOwner'}]}));
function values(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const base: Record<string, unknown> = {
    [taker]: rpcAccount(new Uint8Array(), KNOWN_PROGRAMS.system, 40_000_000),
    [maker]: rpcAccount(new Uint8Array(), KNOWN_PROGRAMS.system, 90_000_000),
    [sourceAta]: rpcAccount(legacyToken(usdcMint, taker, 25_000_000n), KNOWN_PROGRAMS.token, 2_039_280),
    [makerInput]: rpcAccount(legacyToken(usdcMint, maker, 500_000_000n), KNOWN_PROGRAMS.token, 2_039_280),
    [destinationAta]: rpcAccount(stockToken(taker, 0n), KNOWN_PROGRAMS.token2022, 2_157_600),
    [makerOutput]: rpcAccount(stockToken(maker, 900_000_000n), KNOWN_PROGRAMS.token2022, 2_157_600),
    [usdcMint]: rpcAccount(Uint8Array.from(getLegacyMintEncoder().encode({mintAuthority: key('usdc-authority'), supply: 5_000_000_000n,
      decimals: 6, isInitialized: true, freezeAuthority: key('usdc-freeze')})), KNOWN_PROGRAMS.token, 1_461_600),
    [stockMint]: rpcAccount(Uint8Array.from(getMintEncoder().encode({mintAuthority: key('stock-authority'), supply: 15_000_000_000n,
      decimals: 8, isInitialized: true, freezeAuthority: key('stock-freeze'), extensions: STOCK_EXTENSIONS})), KNOWN_PROGRAMS.token2022, 4_000_000),
  };
  for (const program of [KNOWN_PROGRAMS.computeBudget, KNOWN_PROGRAMS.associatedToken, KNOWN_PROGRAMS.orderEngine,
    KNOWN_PROGRAMS.token, KNOWN_PROGRAMS.system, KNOWN_PROGRAMS.token2022]) {
    base[program] = rpcAccount(new Uint8Array(36), 'BPFLoaderUpgradeab1e11111111111111111111111', 1_000_000, true);
  }
  return {...base, ...overrides};
}
function semanticsFetch(accountValues = values()): typeof fetch {
  return (async (_url: string | URL, init?: {body?: string}) => {
    const request = JSON.parse(String(init?.body)) as {id: string; method: string; params: unknown[]};
    const result = request.method === 'getGenesisHash' ? STOCK_DRAFT_MAINNET_GENESIS
      : {context: {slot: 447_100_000, apiVersion: '3.1.10'}, value: (request.params[0] as string[]).map(item => accountValues[item] ?? null)};
    return new Response(JSON.stringify({jsonrpc: '2.0', id: request.id, result}), {status: 200, headers: {'content-type': 'application/json'}});
  }) as unknown as typeof fetch;
}
function simulationFetch(options: {postTaker?: number; postDestination?: bigint} = {}): typeof fetch {
  return (async (_url: string | URL, init?: {body?: string}) => {
    const request = JSON.parse(String(init?.body)) as {id: string; method: string};
    if (request.method === 'getGenesisHash') {
      return new Response(JSON.stringify({jsonrpc: '2.0', id: request.id, result: STOCK_DRAFT_MAINNET_GENESIS}), {status: 200, headers: {'content-type': 'application/json'}});
    }
    const accounts = [rpcAccount(new Uint8Array(), KNOWN_PROGRAMS.system, options.postTaker ?? 40_000_000),
      rpcAccount(legacyToken(usdcMint, taker, 15_000_000n), KNOWN_PROGRAMS.token, 2_039_280),
      rpcAccount(stockToken(taker, options.postDestination ?? OUTPUT_RAW), KNOWN_PROGRAMS.token2022, 2_157_600)];
    return new Response(JSON.stringify({jsonrpc: '2.0', id: request.id, result: {context: {slot: 447_100_005, apiVersion: '3.1.10'},
      value: {err: null, logs: ['Program log: fill'], unitsConsumed: 60_000, accounts, returnData: null}}}), {status: 200, headers: {'content-type': 'application/json'}});
  }) as unknown as typeof fetch;
}
function prepared(message = rfqMessage(), changes: Record<string, unknown> = {}) {
  const clock = {now: NOW};
  const draft = bindStockOrderDraft(payload(changes, message), context(clock));
  const bound = binding(draft);
  const structure = inspectStockDraftStructure(draft, bound);
  return {clock, draft, bound, structure};
}
async function review(message = rfqMessage(), options: {accountValues?: Record<string, unknown>; postTaker?: number} = {}) {
  const {clock, draft, bound, structure} = prepared(message);
  return reviewStockOrder(draft, bound, {
    lookupResolver: {resolve: async () => resolved(structure, message.staticAccounts as Address[])},
    lifetimeVerifier: {verify: async () => lifetime(structure)},
    semanticsReader: new SolanaMainnetStockOrderSemanticsReader({rpcUrl: 'https://rpc.example', fetch: semanticsFetch(options.accountValues), now: () => clock.now}),
    simulator: new SolanaMainnetStockOrderSimulator({rpcUrl: 'https://rpc.example', fetch: simulationFetch(options.postTaker === undefined ? {} : {postTaker: options.postTaker}), now: () => clock.now}),
    now: () => clock.now,
  });
}
const reconcileFails = async (code: string, message: Message, options: {accountValues?: Record<string, unknown>} = {}) => {
  const {clock, draft, bound, structure} = prepared(message);
  const semantics = await new SolanaMainnetStockOrderSemanticsReader({rpcUrl: 'https://rpc.example', fetch: semanticsFetch(options.accountValues),
    now: () => clock.now}).read({draft, binding: bound, structure, resolvedAccounts: resolved(structure, message.staticAccounts as Address[])});
  assert.throws(() => reconcileStockOrderTerms({summary: draft.summary, semantics, now: clock.now}),
    (error: unknown) => error instanceof StockOrderReconciliationError && error.code === code);
};

describe('JupiterZ RFQ orders', () => {
  it('binds the market maker as fee payer and the taker as second signer', () => {
    const {draft, structure} = prepared();
    assert.equal(draft.summary.route, 'rfq');
    assert.equal(draft.summary.marketMaker, maker);
    assert.equal(draft.summary.slippageBps, 0);
    assert.equal(draft.summary.lastValidBlockHeight, '1150');
    assert.equal(draft.summary.providerExpiresAt, new Date(Number(EXPIRE_AT) * 1000).toISOString());
    assert.deepEqual(structure.coSigner, {address: maker, accountIndex: 0, role: 'fee_payer_market_maker'});
    assert.deepEqual(structure.requiredSigner, {address: taker, accountIndex: 1, role: 'taker'});
    assert.deepEqual(structure.signatures, {required: 2, present: 0, absent: 2, unsigned: true});
  });

  it('reviews and simulates a fixed-price fill: zero network fee for the taker, exact amounts, rfq route', async () => {
    const {intent, evidence} = await review();
    assert.equal(intent.terms.route, 'rfq');
    assert.equal(intent.terms.inputAmountRaw, INPUT_RAW.toString());
    assert.equal(intent.terms.quotedOutputAmountRaw, OUTPUT_RAW.toString());
    assert.equal(intent.terms.minimumOutputAmountRaw, OUTPUT_RAW.toString());
    assert.equal(intent.terms.slippageBps, 0);
    assert.equal(intent.terms.platformFeeBps, 10);
    assert.equal(intent.terms.totalLamportsUpperBound, '0');
    assert.equal(evidence.semantics.feeEstimate.feePayer, 'market_maker');
    assert.equal(evidence.semantics.feeEstimate.takerLamportsUpperBound, '0');
    assert.equal(evidence.reconciliation.swap.variant, 'rfq_fill');
    assert.ok(evidence.reconciliation.reviewFlags.includes('rfq_market_maker_fill'));
  });

  it('refuses a taker lamport change: the market maker must pay the network fee', async () => {
    await assert.rejects(review(rfqMessage(), {postTaker: 39_995_000}), {code: 'SIMULATION_EFFECTS_MISMATCH'});
  });

  it('refuses sponsored rent, a missing or mismatched maker, a provider block height and aggregator fields', () => {
    const clock = {now: NOW};
    for (const changes of [{rentFeePayer: maker}, {rentFeePayer: key('jupiter-gas')}, {signatureFeePayer: taker}, {gasless: false},
      {maker: taker}, {maker: key('other-maker')}, {prioritizationFeePayer: taker}]) {
      assert.throws(() => bindStockOrderDraft(payload(changes), context(clock)),
        (error: unknown) => error instanceof StockOrderDraftError && error.code === 'STOCK_DRAFT_SIGNER_MISMATCH', JSON.stringify(changes));
    }
    for (const changes of [{lastValidBlockHeight: '1150'}, {expireAt: undefined}, {expireAt: '2026-09-15T09:00:58.000Z'},
      {expireAt: String(Math.floor(NOW / 1000) + 3600)}]) {
      assert.throws(() => bindStockOrderDraft(payload(changes), context(clock)),
        (error: unknown) => error instanceof StockOrderDraftError && error.code === 'STOCK_DRAFT_VALIDITY_INVALID', JSON.stringify(changes));
    }
    assert.throws(() => bindStockOrderDraft(payload({swapType: 'aggregator'}), context(clock)),
      (error: unknown) => error instanceof StockOrderDraftError && error.code === 'STOCK_DRAFT_TERMS_MISMATCH');
    assert.throws(() => bindStockOrderDraft(payload({router: 'metis', swapType: 'rfq'}), context(clock)),
      (error: unknown) => error instanceof StockOrderDraftError);
  });

  it('refuses swapped signer order, a signed slot, a third signer and a single-signer message', () => {
    const swapped = [...STATIC]; [swapped[0], swapped[1]] = [swapped[1]!, swapped[0]!];
    const bytes = (message: Message, signed: Record<string, Uint8Array | null> = {}) => Uint8Array.from(wire(message, signed));
    const inspect = (value: Uint8Array) => inspectUnsignedV0TransactionStructure(value, taker, maker);
    const mismatch = (error: unknown) => error instanceof StockTransactionStructureError && error.code === 'SIGNER_MISMATCH';
    assert.throws(() => inspect(bytes(rfqMessage({staticAccounts: swapped}))), mismatch);
    assert.throws(() => inspect(bytes(rfqMessage(), {[maker]: new Uint8Array(64).fill(1)})), mismatch);
    assert.throws(() => inspect(bytes(rfqMessage({signers: 3}))), mismatch);
    assert.throws(() => inspect(bytes(rfqMessage({signers: 1}))), mismatch);
    assert.throws(() => inspectUnsignedV0TransactionStructure(bytes(rfqMessage()), taker), mismatch);
    assert.throws(() => inspectUnsignedV0TransactionStructure(bytes(rfqMessage()), taker, taker), mismatch);
  });

  it('refuses a fill for another maker, the taker as maker account, changed amounts, a high fee and an expired quote', async () => {
    const otherMaker = key('other-maker');
    const withOtherMaker = [...STATIC]; withOtherMaker[0] = otherMaker;
    await assert.rejects(review(rfqMessage({staticAccounts: withOtherMaker})), (error: unknown) => error instanceof StockOrderDraftError);
    // The maker's receiving account is the taker's own USDC account.
    await reconcileFails('RECONCILIATION_UNEXPECTED_MOVEMENT', rfqMessage(), {accountValues: values({[makerInput]:
      rpcAccount(legacyToken(usdcMint, taker, 1n), KNOWN_PROGRAMS.token, 2_039_280)})});
    await reconcileFails('RECONCILIATION_UNEXPECTED_MOVEMENT', rfqMessage(), {accountValues: values({[makerOutput]:
      rpcAccount(stockToken(key('stranger'), 900_000_000n), KNOWN_PROGRAMS.token2022, 2_157_600)})});
    await reconcileFails('RECONCILIATION_INPUT_AMOUNT_MISMATCH', rfqMessage({fill: fillData({input: INPUT_RAW + 1n})}));
    await reconcileFails('RECONCILIATION_OUTPUT_FLOOR_VIOLATED', rfqMessage({fill: fillData({output: OUTPUT_RAW - 1n})}));
    await reconcileFails('RECONCILIATION_FEE_CAP_EXCEEDED', rfqMessage({fill: fillData({feeBps: 11})}));
    await reconcileFails('RECONCILIATION_EXPIRED', rfqMessage({fill: fillData({expireAt: BigInt(Math.floor(NOW / 1000))})}));
    await reconcileFails('RECONCILIATION_EXPIRED', rfqMessage({fill: fillData({expireAt: BigInt(Math.floor(NOW / 1000) + 900)})}));
    // Output routed to an account that is not the taker's canonical associated account.
    await reconcileFails('RECONCILIATION_DESTINATION_ACCOUNT_MISMATCH', rfqMessage({fillAccounts: [1, 0, 2, 3, 5, 4, 11, 9, 12, 13, 10]}));
  });

  it('refuses any extra token movement beside the fill', async () => {
    const transfer = {programAddressIndex: 9, accountIndices: [2, 11, 3, 1], data: Uint8Array.from(
      getTransferCheckedInstructionDataEncoder().encode({amount: 1n, decimals: 6}))};
    await reconcileFails('RECONCILIATION_UNEXPECTED_MOVEMENT', rfqMessage({extra: [transfer]}));
  });
});

// What a just-in-time market maker's fill looks like in simulation before it has
// minted: the taker's transfer runs, the maker's transfer of the output cannot.
const ENGINE = KNOWN_PROGRAMS.orderEngine;
const JIT_LOGS: readonly string[] = [
  `Program ${KNOWN_PROGRAMS.computeBudget} invoke [1]`, `Program ${KNOWN_PROGRAMS.computeBudget} success`,
  `Program ${KNOWN_PROGRAMS.computeBudget} invoke [1]`, `Program ${KNOWN_PROGRAMS.computeBudget} success`,
  `Program ${KNOWN_PROGRAMS.associatedToken} invoke [1]`, 'Program log: CreateIdempotent', `Program ${KNOWN_PROGRAMS.associatedToken} success`,
  `Program ${ENGINE} invoke [1]`, 'Program log: Instruction: Fill',
  `Program ${KNOWN_PROGRAMS.token} invoke [2]`, `Program ${KNOWN_PROGRAMS.token} consumed 76 of 185761 compute units`,
  `Program ${KNOWN_PROGRAMS.token} success`,
  `Program ${KNOWN_PROGRAMS.token2022} invoke [2]`, 'Program log: Instruction: TransferChecked', 'Program log: Error: insufficient funds',
  `Program ${KNOWN_PROGRAMS.token2022} consumed 1414 of 182405 compute units`,
  `Program ${KNOWN_PROGRAMS.token2022} failed: custom program error: 0x1`,
  `Program ${ENGINE} consumed 12852 of 193843 compute units`, `Program ${ENGINE} failed: custom program error: 0x1`,
];
function failedSimulationFetch(logs: readonly string[] = JIT_LOGS, err: unknown = {InstructionError: [3, {Custom: 1}]}): typeof fetch {
  return (async (_url: string | URL, init?: {body?: string}) => {
    const request = JSON.parse(String(init?.body)) as {id: string; method: string};
    const result = request.method === 'getGenesisHash' ? STOCK_DRAFT_MAINNET_GENESIS
      : {context: {slot: 447_100_005, apiVersion: '3.1.10'}, value: {err, logs, unitsConsumed: 25_000, accounts: [null, null, null], returnData: null}};
    return new Response(JSON.stringify({jsonrpc: '2.0', id: request.id, result}), {status: 200, headers: {'content-type': 'application/json'}});
  }) as unknown as typeof fetch;
}
async function reviewSimulatedWith(simulation: typeof fetch, accountValues = values({
  [makerOutput]: rpcAccount(stockToken(maker, 1n), KNOWN_PROGRAMS.token2022, 2_157_600)})) {
  const message = rfqMessage();
  const {clock, draft, bound, structure} = prepared(message);
  return reviewStockOrder(draft, bound, {
    lookupResolver: {resolve: async () => resolved(structure, message.staticAccounts as Address[])},
    lifetimeVerifier: {verify: async () => lifetime(structure)},
    semanticsReader: new SolanaMainnetStockOrderSemanticsReader({rpcUrl: 'https://rpc.example', fetch: semanticsFetch(accountValues), now: () => clock.now}),
    simulator: new SolanaMainnetStockOrderSimulator({rpcUrl: 'https://rpc.example', fetch: simulation, now: () => clock.now}),
    now: () => clock.now,
  });
}

describe('just-in-time market makers', () => {
  it('accepts a fill whose only failure is the maker\'s undelivered output, and says so', async () => {
    const {intent, evidence} = await reviewSimulatedWith(failedSimulationFetch());
    assert.equal(intent.terms.settlement, 'maker_delivers_at_fill');
    assert.ok(intent.reviewFlags.includes('rfq_maker_delivers_at_fill'));
    assert.equal(intent.terms.simulatedOutputReceivedRaw, OUTPUT_RAW.toString());
    assert.equal(intent.terms.totalLamportsUpperBound, '0');
    assert.equal(evidence.simulation.outcome.settlement, 'maker_delivers_at_fill');
    assert.deepEqual(evidence.simulation.outcome.error, {kind: 'InstructionError:Custom', instructionIndex: 3, customCode: 1});
    assert.equal(evidence.simulation.effects.inputSpentRaw, INPUT_RAW.toString());
    // A fully simulated fill stays 'simulated'.
    assert.equal((await review()).intent.terms.settlement, 'simulated');
  });

  it('refuses every other failure, including a maker that already holds the shares', async () => {
    const takerShort = JIT_LOGS.map(line => line === `Program ${KNOWN_PROGRAMS.token} success`
      ? `Program ${KNOWN_PROGRAMS.token} failed: custom program error: 0x1` : line);
    const index = JIT_LOGS.indexOf(`Program ${ENGINE} consumed 12852 of 193843 compute units`);
    const extraCall = [...JIT_LOGS.slice(0, 12), `Program ${KNOWN_PROGRAMS.token} invoke [2]`, `Program ${KNOWN_PROGRAMS.token} success`, ...JIT_LOGS.slice(12)];
    for (const [label, simulation, accountValues] of [
      ['maker holds enough', failedSimulationFetch(), values()],
      ['taker transfer failed', failedSimulationFetch(takerShort), undefined],
      ['another instruction failed', failedSimulationFetch(JIT_LOGS, {InstructionError: [2, {Custom: 1}]}), undefined],
      ['another error code', failedSimulationFetch(JIT_LOGS, {InstructionError: [3, {Custom: 3}]}), undefined],
      ['a program ran after the failure', failedSimulationFetch([...JIT_LOGS, `Program ${KNOWN_PROGRAMS.system} invoke [1]`]), undefined],
      ['an extra token call', failedSimulationFetch(extraCall), undefined],
      ['truncated logs', failedSimulationFetch(JIT_LOGS.slice(0, index)), undefined],
      ['no insufficient-funds log', failedSimulationFetch(JIT_LOGS.filter(line => line !== 'Program log: Error: insufficient funds')), undefined],
    ] as const) {
      await assert.rejects(reviewSimulatedWith(simulation, accountValues), {code: 'SIMULATION_TRANSACTION_FAILED'}, label);
    }
  });
});

describe('RFQ quotes, signatures and settlement', () => {
  it('widens the order tolerance by a token transfer fee and parses only the tolerance requested', () => {
    assert.equal(orderSlippageBps(0), 50);
    assert.equal(orderSlippageBps(300), 350);
    const started = NOW;
    const quote = {inputMint: usdcMint, outputMint: stockMint, inAmount: '10000000', outAmount: '2972350', otherAmountThreshold: '2868318',
      swapMode: 'ExactIn', slippageBps: 350, feeBps: 10, feeMint: usdcMint, router: 'metis', transaction: null, taker: null};
    const pair = {inputAsset: 'USDC' as const, outputAsset: stockQuoteAsset(STOCK_TRADING_ASSETS[0]!), amountRaw: '10000000'};
    assert.equal(parseEstimate(quote, pair, started, started + 100, 350).slippageBps, 350);
    assert.throws(() => parseEstimate(quote, pair, started, started + 100));
    assert.throws(() => parseEstimate({...quote, slippageBps: 50}, pair, started, started + 100, 350));
    assert.throws(() => parseEstimate(quote, pair, started, started + 100, 5_000));
  });

  it('parses a fixed-price RFQ quote and refuses an RFQ quote with a tolerance', () => {
    const started = NOW;
    const quote = {inputMint: usdcMint, outputMint: stockMint, inAmount: '10000000', outAmount: '2972350', otherAmountThreshold: '2972350',
      swapMode: 'ExactIn', slippageBps: 0, feeBps: 10, feeMint: usdcMint, router: 'jupiterz', swapType: 'rfq', transaction: null, taker: null,
      expireAt: String(Math.floor(NOW / 1000) + 55)};
    const parsed = parseEstimate(quote, {inputAsset: 'USDC', outputAsset: stockQuoteAsset(STOCK_TRADING_ASSETS[0]!), amountRaw: '10000000'}, started, started + 100);
    assert.equal(parsed.slippageBps, 0);
    assert.equal(parsed.router, 'jupiterz');
    assert.equal(parsed.providerExpiresAt, new Date((Math.floor(NOW / 1000) + 55) * 1000).toISOString());
    assert.throws(() => parseEstimate({...quote, slippageBps: 50}, {inputAsset: 'USDC', outputAsset: stockQuoteAsset(STOCK_TRADING_ASSETS[0]!), amountRaw: '10000000'}, started, started + 100));
    assert.throws(() => parseEstimate({...quote, otherAmountThreshold: '2972000'}, {inputAsset: 'USDC', outputAsset: stockQuoteAsset(STOCK_TRADING_ASSETS[0]!), amountRaw: '10000000'}, started, started + 100));
  });

  function rfqOrder() {
    const keys = generateKeyPairSync('ed25519');
    const wallet = getAddressDecoder().decode(keys.publicKey.export({type: 'spki', format: 'der'}).subarray(-32));
    const message = {version: 0, header: {numSignerAccounts: 2, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 0},
      staticAccounts: [maker, wallet], lifetimeToken: '11111111111111111111111111111111', instructions: [], addressTableLookups: []};
    const messageBytes = getCompiledTransactionMessageEncoder().encode(message as unknown as CompiledTransactionMessage) as TransactionMessageBytes;
    const encode = (signatures: Record<string, Uint8Array | null>) =>
      Buffer.from(getTransactionEncoder().encode({messageBytes, signatures} as never)).toString('base64');
    const takerSignature = Uint8Array.from(sign(null, Buffer.from(messageBytes), keys.privateKey));
    const review = {reviewDigestSha256: 'a'.repeat(64), reviewedAt: new Date(Date.now() - 5_000).toISOString(),
      expiresAt: new Date(Date.now() + 30_000).toISOString(), evidence: {lastValidBlockHeight: '500', observationSlot: '501'}, requestId: 'rfq',
      terms: {route: 'rfq'}} as unknown as ReviewedStockOrderIntent;
    const order: LiveOrder = {id: 'rfq-order', user_id: 'user', wallet, review, unsignedTransaction: encode({[maker]: null, [wallet]: null}),
      expires_at: review.expiresAt, status: 'reviewed', signature: null};
    return {order, wallet, signed: encode({[maker]: null, [wallet]: takerSignature}),
      makerSigned: encode({[maker]: new Uint8Array(64).fill(7), [wallet]: takerSignature}), takerSignature};
  }

  it('accepts only the taker slot signed; the market maker signs later', () => {
    const f = rfqOrder();
    const signature = verifyReviewedSignature(f.order, f.signed);
    assert.equal(typeof signature, 'string');
    assert.throws(() => verifyReviewedSignature(f.order, f.makerSigned), {code: 'INVALID_SIGNATURE'});
  });

  it('finds the RFQ transaction by the taker signature among recent wallet transactions and settles it', async () => {
    const f = rfqOrder();
    const takerSignature = verifyReviewedSignature(f.order, f.signed);
    const txId = 'M'.repeat(88);
    const pending = {...f.order, status: 'pending' as const, signature: takerSignature};
    let resolved: string | null = null;
    let recordedSlot: number | undefined;
    const store = {read: async () => pending, resolve: async (_u: string, _i: string, status: string, slot?: number) => {resolved = status; recordedSlot = slot; return {...pending, status};}} as unknown as LiveOrderStore;
    const calls: string[] = [];
    const fake = (async (_url: unknown, options?: RequestInit) => {
      const request = JSON.parse(String(options?.body));
      calls.push(request.method);
      const result = request.method === 'getSignaturesForAddress'
        ? [{signature: 'N'.repeat(88), blockTime: Math.floor(Date.now() / 1000)}, {signature: txId, blockTime: Math.floor(Date.now() / 1000)}]
        : request.method === 'getTransaction'
          ? (request.params[0] === txId ? {slot: 777, meta: {err: null}, transaction: {signatures: [txId, takerSignature]}}
            : {slot: 776, meta: {err: null}, transaction: {signatures: ['N'.repeat(88)]}})
          : null;
      return Response.json({jsonrpc: '2.0', id: 1, result});
    }) as typeof fetch;
    const service = new LiveStockOrders({rpcUrl: 'https://rpc.example', store, fetch: fake});
    const settled = await service.status('user', 'rfq-order');
    assert.equal(resolved, 'confirmed');
    assert.equal(settled?.confirmedSlot, 777);
    assert.equal(recordedSlot, 777, 'RFQ settlement persists the observed slot too');
    assert.deepEqual(calls, ['getSignaturesForAddress', 'getTransaction', 'getTransaction']);
  });

  it('keeps an unfound RFQ order pending until the blockhash bound has passed at finalized height', async () => {
    const f = rfqOrder();
    const takerSignature = verifyReviewedSignature(f.order, f.signed);
    const pending = {...f.order, status: 'pending' as const, signature: takerSignature};
    for (const [height, valid, expected] of [[450, false, 'pending'], [501, true, 'pending'], [501, false, 'expired']] as const) {
      let resolved: string | null = null;
      const store = {read: async () => pending, resolve: async (_u: string, _i: string, status: string) => {resolved = status; return {...pending, status};}} as unknown as LiveOrderStore;
      const fake = (async (_url: unknown, options?: RequestInit) => {
        const request = JSON.parse(String(options?.body));
        const result = request.method === 'getSignaturesForAddress' ? [] : request.method === 'getGenesisHash'
          ? '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d' : request.method === 'getBlockHeight' ? height : request.method === 'isBlockhashValid' ? {value: valid, context: {slot: 502}} : null;
        return Response.json({jsonrpc: '2.0', id: 1, result});
      }) as typeof fetch;
      const service = new LiveStockOrders({rpcUrl: 'https://rpc.example', store, fetch: fake});
      const status = await service.status('user', 'rfq-order');
      assert.equal(resolved ?? status?.status, expected);
    }
  });

  it('never settles an RFQ order from a transaction that lacks the taker signature', async () => {
    const f = rfqOrder();
    const takerSignature = verifyReviewedSignature(f.order, f.signed);
    const pending = {...f.order, status: 'pending' as const, signature: takerSignature};
    const store = {read: async () => pending, resolve: async () => {throw Error('must not resolve');}} as unknown as LiveOrderStore;
    const fake = (async (_url: unknown, options?: RequestInit) => {
      const request = JSON.parse(String(options?.body));
      const result = request.method === 'getSignaturesForAddress' ? [{signature: 'Q'.repeat(88), blockTime: Math.floor(Date.now() / 1000)}]
        : request.method === 'getTransaction' ? {slot: 9, meta: {err: null}, transaction: {signatures: ['Q'.repeat(88), 'R'.repeat(88)]}}
          : request.method === 'getGenesisHash' ? '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d' : request.method === 'getBlockHeight' ? 100 : null;
      return Response.json({jsonrpc: '2.0', id: 1, result});
    }) as typeof fetch;
    const status = await new LiveStockOrders({rpcUrl: 'https://rpc.example', store, fetch: fake}).status('user', 'rfq-order');
    assert.equal(status?.status, 'pending');
  });
});
