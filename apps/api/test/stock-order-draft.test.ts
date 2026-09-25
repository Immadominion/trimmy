import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { inspect } from 'node:util';
import { it } from 'node:test';
import { address, getAddressDecoder, getCompiledTransactionMessageEncoder, getTransactionEncoder } from '@solana/kit';
import type { CompiledTransactionMessage, TransactionMessageBytes } from '@solana/kit';
import { JUPITER_QUOTE_ASSETS } from '../src/jupiter-quote-reader.js';
import { STOCK_TRADING_ASSETS } from '../src/stock-trading-catalog.js';
import { STOCK_ESTIMATE_ASSET } from '../src/stock-estimates.js';
import type { StockEstimate } from '../src/stock-estimates.js';
import { bindStockOrderDraft, assertStockDraftBinding, copyStockDraftBytesForReview, assertStockDraftReadyForSimulation,
  inspectStockDraftStructure, StockOrderDraftError, STOCK_DRAFT_MAINNET_GENESIS } from '../src/stock-order-draft.js';
import type { StockOrderDraftContext, StockDraftBinding, StockOrderDraft } from '../src/stock-order-draft.js';

// Public RFC8032 verification key only. No private key, signing, wallet or RPC.
const wallet = getAddressDecoder().decode(Buffer.from('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', 'hex'));
const other = getAddressDecoder().decode(Buffer.from('3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c', 'hex'));
const program = address('11111111111111111111111111111111');
const lifetime = getAddressDecoder().decode(new Uint8Array(32).fill(9));
const lookup = getAddressDecoder().decode(new Uint8Array(32).fill(7));
const lookupTwo = getAddressDecoder().decode(new Uint8Array(32).fill(8));
const owner = '12345678-1234-4567-8123-123456789abc';
const at = (seconds: number) => `2026-09-14T12:00:${String(seconds).padStart(2, '0')}.000Z`;
const errorIs = (code: string) => (e: unknown) => e instanceof StockOrderDraftError && e.code === code;
type AuthorityState = {now: number; blockHeight: string; observedAt: string; genesisHash: typeof STOCK_DRAFT_MAINNET_GENESIS};
const authorityStates = new WeakMap<object, AuthorityState>();
function expected(): StockEstimate {
  return {schemaVersion: 1, kind: 'indicative', network: 'solana:mainnet-beta', provider: 'jupiter-swap-v2',
    executable: false, walletChecked: false, networkFees: null,
    input: {symbol: 'USDC', mint: JUPITER_QUOTE_ASSETS.USDC.mint, decimals: 6, amountRaw: '10000000'},
    output: {symbol: 'AAPLx', mint: STOCK_ESTIMATE_ASSET.variantMint, decimals: 8, estimatedAmountRaw: '2972350', quotedMinimumAmountRaw: '2957488'},
    slippageBps: 50, swapFee: {basisPoints: 10, mint: JUPITER_QUOTE_ASSETS.USDC.mint}, router: 'metis',
    requestedAt: at(0), receivedAt: at(1), refreshAfter: at(10), providerExpiresAt: null,
    assetId: 'apple', variantMint: STOCK_ESTIMATE_ASSET.variantMint, side: 'buy', executionEnabled: false, eligibility: 'unverified', amountUnits: 'raw_token_units'};
}
function context(): StockOrderDraftContext {
  const state: AuthorityState = {now: Date.parse(at(3)), blockHeight: '1001', observedAt: at(3), genesisHash: STOCK_DRAFT_MAINNET_GENESIS};
  const validityAuthority = {now: () => state.now, readChainObservation: async () => ({genesisHash: state.genesisHash,
    blockHeight: state.blockHeight, observedAt: state.observedAt})};
  authorityStates.set(validityAuthority, state);
  return {authenticatedUserId: owner, verifiedTaker: wallet, expected: expected(), requestStartedAt: at(2),
    chainObservation: {genesisHash: STOCK_DRAFT_MAINNET_GENESIS, blockHeight: '1000', observedAt: at(3)}, validityAuthority};
}
function move(ctx: StockOrderDraftContext, seconds: number, changes: Partial<AuthorityState> = {}): void {
  const state = authorityStates.get(ctx.validityAuthority); assert.ok(state);
  Object.assign(state, {now: Date.parse(at(seconds)), observedAt: at(seconds), ...changes});
}
function message(changes: Partial<CompiledTransactionMessage> = {}): CompiledTransactionMessage & {lifetimeToken: string} {
  return {version: 0, header: {numSignerAccounts: 1, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 1},
    staticAccounts: [wallet, program], lifetimeToken: lifetime,
    instructions: [{programAddressIndex: 1, accountIndices: [0], data: new Uint8Array([1, 2, 3])}], addressTableLookups: [], ...changes} as CompiledTransactionMessage & {lifetimeToken: string};
}
function wire(m = message(), signers = [wallet]): Buffer {
  const messageBytes = getCompiledTransactionMessageEncoder().encode(m) as TransactionMessageBytes;
  return Buffer.from(getTransactionEncoder().encode({messageBytes, signatures: Object.fromEntries(signers.map(key => [key, null]))}));
}
function payload(changes: Record<string, unknown> = {}): Record<string, unknown> {
  const q = expected();
  return {inputMint: q.input.mint, outputMint: q.output.mint, inAmount: q.input.amountRaw,
    outAmount: q.output.estimatedAmountRaw, otherAmountThreshold: q.output.quotedMinimumAmountRaw, swapMode: 'ExactIn',
    slippageBps: q.slippageBps, feeBps: q.swapFee.basisPoints, feeMint: q.swapFee.mint, router: q.router, mode: 'manual',
    taker: wallet, transaction: wire().toString('base64'), requestId: 'order-test-1', lastValidBlockHeight: '1050', ...changes};
}
function binding(draft: StockOrderDraft, changes: Partial<StockDraftBinding> = {}): StockDraftBinding {
  return {authenticatedUserId: owner, verifiedTaker: wallet, requestId: draft.summary.requestId,
    transactionMessageHash: draft.summary.transactionMessageHash, bindingHash: draft.summary.bindingHash, ...changes};
}

it('binds exact owner, taker, quote terms and canonical unsigned v0 message hashes without readiness claims', async () => {
  const draft = bindStockOrderDraft(payload(), context()); const s = draft.summary;
  assert.equal(s.userId, owner); assert.equal(s.taker, wallet); assert.equal(s.assetId, 'apple'); assert.equal(s.side, 'buy');
  assert.equal(s.input.amountRaw, '10000000'); assert.equal(s.output.quotedMinimumAmountRaw, '2957488');
  assert.equal(s.requestId, 'order-test-1'); assert.equal(s.lastValidBlockHeight, '1050'); assert.equal(s.notAfter, at(13));
  assert.equal(s.userApproval.status, 'required'); assert.deepEqual(s.termChanges, []);
  assert.equal(s.transactionVersion, 0); assert.equal(s.transactionSizeBytes, wire().length);
  assert.equal(s.transactionMessageHash, createHash('sha256').update(Buffer.from(getCompiledTransactionMessageEncoder().encode(message()))).digest('hex'));
  assert.equal(s.transactionHash, createHash('sha256').update(wire()).digest('hex'));
  assert.equal(s.review.addressResolution, 'static_addresses_only'); assert.equal(s.review.programSemantics, 'required');
  assert.equal(s.review.blockhashVerified, false); assert.equal(s.review.instructionTermsVerified, false);
  assert.equal(s.review.simulation, 'not_run'); assert.equal(s.readyForSimulation, false); assert.equal(s.signingEnabled, false); assert.equal(s.executionEnabled, false);
  await assertStockDraftBinding(draft, binding(draft));
  assert.throws(() => assertStockDraftReadyForSimulation(draft), errorIs('STOCK_DRAFT_REVIEW_REQUIRED'));
});
it('inspects retained bytes offline and exposes only a bound, non-approvable structural report', () => {
  let clockReads = 0, chainReads = 0;
  const ctx: StockOrderDraftContext = {...context(), validityAuthority: {
    now: () => { clockReads++; return Date.parse(at(3)); },
    readChainObservation: async () => { chainReads++; return {genesisHash: STOCK_DRAFT_MAINNET_GENESIS,
      blockHeight: '1001', observedAt: at(3)}; },
  }};
  const raw = wire(); const draft = bindStockOrderDraft(payload({transaction: raw.toString('base64')}), ctx);
  clockReads = 0; chainReads = 0;
  const report = inspectStockDraftStructure(draft, binding(draft));
  assert.equal(clockReads, 0); assert.equal(chainReads, 0);
  assert.equal(report.kind, 'unsigned_solana_v0_structure'); assert.equal(report.transactionVersion, 0);
  assert.equal(report.transactionSizeBytes, raw.length); assert.equal(report.transactionHash, draft.summary.transactionHash);
  assert.equal(report.transactionMessageHash, draft.summary.transactionMessageHash);
  assert.deepEqual(report.requiredSigner, {address: wallet, accountIndex: 0, role: 'fee_payer_and_taker'});
  assert.deepEqual(report.signatures, {required: 1, present: 0, absent: 1, unsigned: true});
  assert.deepEqual(report.header, {numSignerAccounts: 1, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 1});
  assert.equal(report.lifetimeToken.value, lifetime); assert.equal(report.lifetimeToken.expectedUse, 'recent_blockhash');
  assert.equal(report.lifetimeToken.semanticKindVerified, false); assert.equal(report.lifetimeToken.mainnetRecencyVerified, false);
  assert.deepEqual(report.staticAccountKeys, [wallet, program]);
  assert.deepEqual(report.accountIndexSpace, {static: 2, lookupWritable: 0, lookupReadonly: 0, total: 2});
  assert.deepEqual(report.instructions[0], {instructionIndex: 0, programAddressIndex: 1,
    program: {kind: 'static', accountIndex: 1, address: program}, accountIndices: [0], dataLengthBytes: 3,
    dataSha256: createHash('sha256').update(new Uint8Array([1, 2, 3])).digest('hex')});
  assert.equal(report.assessment.status, 'structurally_valid_but_incomplete');
  assert.equal(report.assessment.structuralIntegrity, 'verified'); assert.equal(report.assessment.lookupTableResolution, 'not_applicable');
  assert.equal(report.assessment.recentBlockhash, 'unverified'); assert.equal(report.assessment.instructionSemantics, 'unverified');
  assert.equal(report.assessment.accountState, 'unverified'); assert.equal(report.assessment.transactionTerms, 'unverified');
  assert.equal(report.assessment.approvable, false); assert.equal(report.assessment.readyForSimulation, false);
  assert.equal(report.assessment.signingEnabled, false); assert.equal(report.assessment.broadcastEnabled, false);
  assert.equal(report.assessment.financialOperationsEnabled, false); assert.equal(report.networkContext, 'solana:mainnet-beta');
  assert.equal(report.draftBindingHash, draft.summary.bindingHash);
  assert.ok(Object.isFrozen(report) && Object.isFrozen(report.instructions) && Object.isFrozen(report.instructions[0]) &&
    Object.isFrozen(report.instructions[0]?.accountIndices) && Object.isFrozen(report.assessment));
  const serialized = JSON.stringify(report);
  assert.ok(!serialized.includes(raw.toString('base64')) && !serialized.includes(raw.toString('hex')) &&
    !serialized.includes('AQID') && !serialized.includes('010203'));
});
it('maps lookup-loaded program indexes without resolving any address table', () => {
  const transaction = wire(message({addressTableLookups: [
    {lookupTableAddress: lookup, writableIndexes: [3, 4], readonlyIndexes: [7]},
    {lookupTableAddress: lookupTwo, writableIndexes: [1], readonlyIndexes: [2, 5]},
  ], instructions: [{programAddressIndex: 6, accountIndices: [0, 2, 4, 7], data: new Uint8Array()}]}));
  const draft = bindStockOrderDraft(payload({transaction: transaction.toString('base64')}), context());
  const report = inspectStockDraftStructure(draft, binding(draft));
  assert.deepEqual(report.accountIndexSpace, {static: 2, lookupWritable: 3, lookupReadonly: 3, total: 8});
  assert.equal(report.addressTableLookups.length, 2); assert.equal(report.assessment.lookupTableResolution, 'required');
  assert.deepEqual(report.instructions[0]?.program, {kind: 'lookup', accountIndex: 6, lookupTablePosition: 1,
    lookupTableAddress: lookupTwo, lookupIndex: 2, writable: false});
  assert.deepEqual(report.instructions[0]?.accountIndices, [0, 2, 4, 7]);
  assert.equal(report.instructions[0]?.dataLengthBytes, 0);
  assert.equal(report.assessment.approvable, false); assert.equal(report.assessment.simulation, 'not_run');
});
it('requires the exact opaque draft and binding before structural details are returned', () => {
  const draft = bindStockOrderDraft(payload(), context());
  for (const change of [{authenticatedUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}, {verifiedTaker: other},
    {requestId: 'other'}, {transactionMessageHash: '0'.repeat(64)}, {bindingHash: 'f'.repeat(64)}]) {
    assert.throws(() => inspectStockDraftStructure(draft, binding(draft, change)), errorIs('STOCK_DRAFT_BINDING_MISMATCH'));
  }
  const forged = {summary: draft.summary} as StockOrderDraft;
  assert.throws(() => inspectStockDraftStructure(forged, binding(draft)), errorIs('STOCK_DRAFT_BINDING_MISMATCH'));
  assert.throws(() => inspectStockDraftStructure(draft, {...binding(draft), rawBytes: 'forbidden'} as never),
    errorIs('STOCK_DRAFT_BINDING_MISMATCH'));
});
it('keeps raw transaction bytes out of JSON/inspection and returns only defensive bound review copies', async () => {
  const p = payload(); const ctx = context(); const draft = bindStockOrderDraft(p, ctx);
  const first = await copyStockDraftBytesForReview(draft, binding(draft)); const pristine = Buffer.from(first);
  first.fill(255); p['transaction'] = 'changed'; (ctx.expected.input as {amountRaw: string}).amountRaw = '1';
  assert.ok(Buffer.from(await copyStockDraftBytesForReview(draft, binding(draft))).equals(pristine));
  assert.equal(draft.summary.input.amountRaw, '10000000');
  for (const log of [JSON.stringify(draft), inspect(draft), JSON.stringify(draft.summary)]) {
    assert.ok(!log.includes(pristine.toString('base64'))); assert.ok(!log.includes(pristine.toString('hex')));
  }
  assert.ok(Object.isFrozen(draft.summary) && Object.isFrozen(draft.summary.output) && Object.isFrozen(draft.summary.review));
});
it('rejects a changed owner, taker, request ID, hash or serialized counterfeit draft on reuse', async () => {
  const draft = bindStockOrderDraft(payload(), context());
  for (const change of [{authenticatedUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}, {verifiedTaker: other},
    {requestId: 'other'}, {transactionMessageHash: '0'.repeat(64)}, {bindingHash: 'f'.repeat(64)}]) {
    await assert.rejects(copyStockDraftBytesForReview(draft, binding(draft, change)), errorIs('STOCK_DRAFT_BINDING_MISMATCH'));
  }
  const forged = {summary: {...draft.summary, readyForSimulation: true}} as unknown as StockOrderDraft;
  assert.throws(() => assertStockDraftReadyForSimulation(forged), errorIs('STOCK_DRAFT_BINDING_MISMATCH'));
  await assert.rejects(assertStockDraftBinding(draft, null as unknown as StockDraftBinding), errorIs('STOCK_DRAFT_BINDING_MISMATCH'));
});
it('rejects changes to fixed intent, the approved output floor or fee cap', () => {
  for (const change of [{inputMint: JUPITER_QUOTE_ASSETS.SOL.mint}, {outputMint: JUPITER_QUOTE_ASSETS.USDC.mint},
    {inAmount: '9999999'}, {outAmount: '2957487'}, {otherAmountThreshold: '2957487'}, {slippageBps: 51},
    {swapMode: 'ExactOut'}, {mode: 'ultra'}, {feeBps: 11}, {feeMint: JUPITER_QUOTE_ASSETS.SOL.mint}, {router: 'unknown'},
    {receiver: other}, {referralAccount: other}, {payer: other}]) {
    assert.throws(() => bindStockOrderDraft(payload(change), context()), errorIs('STOCK_DRAFT_TERMS_MISMATCH'));
  }
  for (const change of [{taker: other}, {gasless: true}, {signatureFeePayer: other}, {rentFeePayer: other}]) {
    assert.throws(() => bindStockOrderDraft(payload(change), context()), errorIs('STOCK_DRAFT_SIGNER_MISMATCH'));
  }
});
it('captures a bounded fresh provider requote as new terms that always need approval', () => {
  const draft = bindStockOrderDraft(payload({outAmount: '3000000', otherAmountThreshold: '2985000', feeBps: 9,
    feeMint: STOCK_ESTIMATE_ASSET.variantMint, router: 'dflow', expireAt: at(7)}), context());
  const s = draft.summary;
  assert.equal(s.schemaVersion, 2); assert.equal(s.output.estimatedAmountRaw, '3000000');
  assert.equal(s.output.quotedMinimumAmountRaw, '2985000'); assert.equal(s.swapFee.basisPoints, 9);
  assert.equal(s.swapFee.mint, STOCK_ESTIMATE_ASSET.variantMint); assert.equal(s.router, 'dflow'); assert.equal(s.orderMode, 'manual');
  assert.equal(s.referenceEstimate.output.estimatedAmountRaw, '2972350');
  assert.deepEqual(s.approvalPolicy, {minimumOutputAmountRaw: '2957488', maximumFeeBasisPoints: 10});
  assert.deepEqual(s.termChanges.map(change => change.field), ['output.estimatedAmountRaw', 'output.quotedMinimumAmountRaw',
    'swapFee.basisPoints', 'swapFee.mint', 'router', 'providerExpiresAt']);
  assert.equal(s.userApproval.status, 'required'); assert.equal(s.userApproval.reason, 'fresh_provider_order');
  assert.match(s.userApproval.candidateTermsHash, /^[0-9a-f]{64}$/); assert.equal(s.notAfter, at(7));
});
it('rejects malformed/legacy/noncanonical/truncated/trailing and oversized wire data', () => {
  const good = wire();
  const noncanonicalCount = Buffer.concat([Buffer.from([0x81, 0]), good.subarray(1)]);
  const unsupportedVersion = Buffer.from(good); unsupportedVersion[65] = 0x81;
  const invalid = ['', '!!!!', good.toString('base64') + '\n', good.toString('base64').replace(/=+$/, ''),
    good.subarray(0, good.length - 1).toString('base64'), Buffer.concat([good, Buffer.from([0])]).toString('base64'),
    noncanonicalCount.toString('base64'), unsupportedVersion.toString('base64'), Buffer.alloc(1233).toString('base64'),
    wire(message({version: 'legacy'})).toString('base64')];
  for (const transaction of invalid) assert.throws(() => bindStockOrderDraft(payload({transaction}), context()), errorIs('STOCK_DRAFT_TRANSACTION_INVALID'));
});
it('rejects extra signers, a wrong fee payer, readonly payer and any preexisting signature', () => {
  const double = wire(message({header: {numSignerAccounts: 2, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 1},
    staticAccounts: [wallet, other, program], instructions: [{programAddressIndex: 2, accountIndices: [0]}]}), [wallet, other]);
  const wrong = wire(message({staticAccounts: [other, program]}), [other]);
  const readonly = wire(message({header: {numSignerAccounts: 1, numReadonlySignerAccounts: 1, numReadonlyNonSignerAccounts: 1}}));
  const signed = wire(); signed[1] = 1; // Nonzero fixture byte; no signature is produced.
  for (const bytes of [double, wrong, readonly, signed]) {
    assert.throws(() => bindStockOrderDraft(payload({transaction: bytes.toString('base64')}), context()), errorIs('STOCK_DRAFT_SIGNER_MISMATCH'));
  }
});
it('rejects invalid headers, duplicate addresses, account indexes, empty programs or null lifetime tokens', () => {
  for (const m of [message({header: {numSignerAccounts: 1, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 2}}),
    message({staticAccounts: [wallet, program, program]}), message({instructions: []}),
    message({instructions: [{programAddressIndex: 2}]}), message({instructions: [{programAddressIndex: 0}]}),
    message({instructions: [{programAddressIndex: 1, accountIndices: [2]}]}), {...message(), lifetimeToken: program}]) {
    assert.throws(() => bindStockOrderDraft(payload({transaction: wire(m).toString('base64')}), context()), errorIs('STOCK_DRAFT_TRANSACTION_INVALID'));
  }
});
it('captures unresolved lookup indexes and refuses simulation until all account/program work is implemented', () => {
  const tx = wire(message({addressTableLookups: [{lookupTableAddress: lookup, writableIndexes: [3], readonlyIndexes: [7]}],
    instructions: [{programAddressIndex: 3, accountIndices: [0, 2]}]}));
  const draft = bindStockOrderDraft(payload({transaction: tx.toString('base64')}), context());
  assert.equal(draft.summary.review.addressResolution, 'lookup_tables_required');
  assert.deepEqual(draft.summary.lookupTables[0]?.writableIndexes, [3]); assert.deepEqual(draft.summary.programAddresses, [null]);
  assert.throws(() => assertStockDraftReadyForSimulation(draft), errorIs('STOCK_DRAFT_REVIEW_REQUIRED'));
  for (const tables of [[{lookupTableAddress: lookup, writableIndexes: [3], readonlyIndexes: [3]}],
    [{lookupTableAddress: lookup, writableIndexes: [], readonlyIndexes: []}],
    [{lookupTableAddress: lookup, writableIndexes: Array.from({length: 63}, (_, i) => i), readonlyIndexes: []}]]) {
    assert.throws(() => bindStockOrderDraft(payload({transaction: wire(message({addressTableLookups: tables})).toString('base64')}), context()), errorIs('STOCK_DRAFT_TRANSACTION_INVALID'));
  }
});
it('requires a bounded provider lifetime and fresh mainnet height when a height is supplied', () => {
  for (const change of [{lastValidBlockHeight: undefined}, {lastValidBlockHeight: '0'}, {lastValidBlockHeight: '1000'},
    {lastValidBlockHeight: '1151'}, {lastValidBlockHeight: '1050\n'}, {lastValidBlockHeight: 1050}, {expireAt: '2027-02-31T12:00:00Z'},
    {expireAt: at(3)}, {expireAt: '2026-09-14T12:03:00Z'}]) {
    assert.throws(() => bindStockOrderDraft(payload(change), context()), errorIs('STOCK_DRAFT_VALIDITY_INVALID'));
  }
  for (const ctx of [{...context(), chainObservation: undefined}, {...context(), chainObservation: {genesisHash: 'devnet', blockHeight: '1000', observedAt: at(3)}},
    {...context(), chainObservation: {genesisHash: STOCK_DRAFT_MAINNET_GENESIS, blockHeight: '1000', observedAt: at(4)}}]) {
    assert.throws(() => bindStockOrderDraft(payload(), ctx as StockOrderDraftContext), errorIs('STOCK_DRAFT_VALIDITY_INVALID'));
  }
});
it('permits a bounded provider-time-only draft but still forbids simulation and respects expiry equality', async () => {
  const ctx = {...context()}; delete (ctx as {chainObservation?: unknown}).chainObservation;
  const draft = bindStockOrderDraft(payload({lastValidBlockHeight: undefined, expireAt: at(7)}), ctx);
  assert.equal(draft.summary.lastValidBlockHeight, null); assert.equal(draft.summary.notAfter, at(7));
  move(ctx, 7);
  await assert.rejects(assertStockDraftBinding(draft, binding(draft)), errorIs('STOCK_DRAFT_EXPIRED'));
  assert.throws(() => assertStockDraftReadyForSimulation(draft), errorIs('STOCK_DRAFT_REVIEW_REQUIRED'));
});
it('rechecks trusted time and fresh block height before any review copy', async () => {
  const expiredContext = context(); const expired = bindStockOrderDraft(payload(), expiredContext); move(expiredContext, 13);
  await assert.rejects(copyStockDraftBytesForReview(expired, binding(expired)), errorIs('STOCK_DRAFT_EXPIRED'));
  await assert.rejects(copyStockDraftBytesForReview(expired, {...binding(expired), now: at(4)} as unknown as StockDraftBinding),
    errorIs('STOCK_DRAFT_BINDING_MISMATCH'));

  const heightContext = context(); const heightDraft = bindStockOrderDraft(payload(), heightContext);
  move(heightContext, 4, {blockHeight: '1050'});
  await assert.rejects(copyStockDraftBytesForReview(heightDraft, binding(heightDraft)), errorIs('STOCK_DRAFT_EXPIRED'));

  const networkContext = context(); const networkDraft = bindStockOrderDraft(payload(), networkContext);
  move(networkContext, 4, {genesisHash: 'devnet' as typeof STOCK_DRAFT_MAINNET_GENESIS});
  await assert.rejects(copyStockDraftBytesForReview(networkDraft, binding(networkDraft)), errorIs('STOCK_DRAFT_VALIDITY_INVALID'));

  const regressionContext = context(); const regressionDraft = bindStockOrderDraft(payload(), regressionContext);
  move(regressionContext, 4, {blockHeight: '999'});
  await assert.rejects(copyStockDraftBytesForReview(regressionDraft, binding(regressionDraft)), errorIs('STOCK_DRAFT_VALIDITY_INVALID'));
});
it('binds the reverse raw-token direction and preserves large exact output amounts', () => {
  const q = expected();
  const reverse: StockEstimate = {...q, side: 'sell', input: {symbol: 'AAPLx', mint: STOCK_ESTIMATE_ASSET.variantMint, decimals: 8, amountRaw: '2972350'},
    output: {symbol: 'USDC', mint: JUPITER_QUOTE_ASSETS.USDC.mint, decimals: 6, estimatedAmountRaw: '9007199254740993', quotedMinimumAmountRaw: '9007199254740993'}, slippageBps: 0};
  const draft = bindStockOrderDraft(payload({inputMint: reverse.input.mint, outputMint: reverse.output.mint, inAmount: reverse.input.amountRaw,
    outAmount: reverse.output.estimatedAmountRaw, otherAmountThreshold: reverse.output.quotedMinimumAmountRaw, slippageBps: 0}), {...context(), expected: reverse});
  assert.equal(draft.summary.side, 'sell'); assert.equal(draft.summary.input.decimals, 8);
  assert.equal(draft.summary.output.estimatedAmountRaw, '9007199254740993');
});
it('rejects malformed authenticated context, stale estimate and accessors without reading them', () => {
  for (const change of [{authenticatedUserId: owner + '\n'}, {verifiedTaker: program}, {verifiedTaker: 'wallet'},
    {requestStartedAt: at(4)}, {expected: {...expected(), network: 'solana:devnet'}},
    {expected: {...expected(), input: {...expected().input, transaction: 'unwanted-opaque-data'}}},
    {expected: {...expected(), input: {...expected().input, amountRaw: '0'}}}]) {
    assert.throws(() => bindStockOrderDraft(payload(), {...context(), ...change} as StockOrderDraftContext), errorIs('STOCK_DRAFT_CONTEXT_INVALID'));
  }
  assert.throws(() => bindStockOrderDraft(payload(), {...context(), requestStartedAt: at(10)}), errorIs('STOCK_DRAFT_EXPIRED'));
  assert.throws(() => bindStockOrderDraft(payload(), {...context(), receivedAt: at(3)} as unknown as StockOrderDraftContext),
    errorIs('STOCK_DRAFT_CONTEXT_INVALID'));
  let reads = 0; const bad = {...payload()}; Object.defineProperty(bad, 'taker', {enumerable: true, get() { reads++; return wallet; }});
  assert.throws(() => bindStockOrderDraft(bad, context()), errorIs('STOCK_DRAFT_PROVIDER_ERROR')); assert.equal(reads, 0);
});
it('rejects provider errors and missing request ID using only safe static exceptions', () => {
  for (const change of [{errorCode: 1, transaction: ''}, {errorMessage: 'private provider data'}, {error: 'private provider data'},
    {requestId: ''}, {requestId: 'request\n'}, {requestId: undefined}]) {
    assert.throws(() => bindStockOrderDraft(payload(change), context()), (e: unknown) =>
      errorIs('STOCK_DRAFT_PROVIDER_ERROR')(e) && e instanceof Error && !e.message.includes('private provider data'));
  }
});


it('binds each catalog stock identity and rejects substituted company metadata', () => {
  for (const stock of STOCK_TRADING_ASSETS.slice(1)) {
    const reference = expected();
    const quote: StockEstimate = {...reference, assetId: stock.assetId, variantMint: stock.mint,
      output: {...reference.output, symbol: stock.symbol, mint: stock.mint, decimals: stock.decimals}};
    const ctx = {...context(), expected: quote};
    const candidate = payload({outputMint: stock.mint});
    const draft = bindStockOrderDraft(candidate, ctx);
    assert.equal(draft.summary.assetId, stock.assetId);
    assert.equal(draft.summary.output.mint, stock.mint);
    assert.throws(() => bindStockOrderDraft(candidate, {...ctx, expected: {...quote, assetId: 'apple'}}),
      errorIs('STOCK_DRAFT_CONTEXT_INVALID'));
    assert.throws(() => bindStockOrderDraft(candidate, {...ctx, expected: {...quote, output: {...quote.output, decimals: 6}}}),
      errorIs('STOCK_DRAFT_CONTEXT_INVALID'));
    assert.throws(() => bindStockOrderDraft(payload(), ctx), errorIs('STOCK_DRAFT_TERMS_MISMATCH'));
  }
});
