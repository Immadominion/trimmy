import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {it} from 'node:test';
import {
  address,
  getAddressDecoder,
  getCompiledTransactionMessageEncoder,
  getTransactionEncoder,
} from '@solana/kit';
import type {CompiledTransactionMessage, TransactionMessageBytes} from '@solana/kit';
import {JUPITER_QUOTE_ASSETS} from '../src/jupiter-quote-reader.js';
import {STOCK_ESTIMATE_ASSET} from '../src/stock-estimates.js';
import type {StockEstimate} from '../src/stock-estimates.js';
import {
  bindStockOrderDraft,
  inspectStockDraftStructure,
  STOCK_DRAFT_MAINNET_GENESIS,
} from '../src/stock-order-draft.js';
import type {
  StockDraftBinding,
  StockDraftStructuralInspection,
  StockOrderDraft,
  StockOrderDraftContext,
} from '../src/stock-order-draft.js';
import {
  SolanaMainnetStockOrderLifetimeVerifier,
  StockOrderLifetimeVerificationError,
} from '../src/stock-order-lifetime-verifier.js';

const rpcUrl = 'https://rpc.example.test/mainnet?server-key=not-returned';
const shortTruncatedGenesis = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp';
const wallet = getAddressDecoder().decode(Buffer.from(
  'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', 'hex'));
const program = address('11111111111111111111111111111111');
const lifetime = getAddressDecoder().decode(new Uint8Array(32).fill(9));
const owner = '12345678-1234-4567-8123-123456789abc';
const at = (seconds: number) => `2026-09-14T12:00:${String(seconds).padStart(2, '0')}.000Z`;
const errorIs = (code: string) => (error: unknown) =>
  error instanceof StockOrderLifetimeVerificationError && error.code === code &&
  !error.message.includes('server-key') && !error.message.includes('private-upstream');

function estimate(): StockEstimate {
  return {schemaVersion: 1, kind: 'indicative', network: 'solana:mainnet-beta', provider: 'jupiter-swap-v2',
    executable: false, walletChecked: false, networkFees: null,
    input: {symbol: 'USDC', mint: JUPITER_QUOTE_ASSETS.USDC.mint, decimals: 6, amountRaw: '10000000'},
    output: {symbol: 'AAPLx', mint: STOCK_ESTIMATE_ASSET.variantMint, decimals: 8,
      estimatedAmountRaw: '2972350', quotedMinimumAmountRaw: '2957488'},
    slippageBps: 50, swapFee: {basisPoints: 10, mint: JUPITER_QUOTE_ASSETS.USDC.mint}, router: 'metis',
    requestedAt: at(0), receivedAt: at(1), refreshAfter: at(10), providerExpiresAt: null,
    assetId: 'apple', variantMint: STOCK_ESTIMATE_ASSET.variantMint, side: 'buy', executionEnabled: false,
    eligibility: 'unverified', amountUnits: 'raw_token_units'};
}

function message(): CompiledTransactionMessage & {lifetimeToken: string} {
  return {version: 0,
    header: {numSignerAccounts: 1, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 1},
    staticAccounts: [wallet, program], lifetimeToken: lifetime,
    instructions: [{programAddressIndex: 1, accountIndices: [0], data: new Uint8Array([1, 2, 3])}],
    addressTableLookups: []} as CompiledTransactionMessage & {lifetimeToken: string};
}

function wire(): Buffer {
  const messageBytes = getCompiledTransactionMessageEncoder().encode(message()) as TransactionMessageBytes;
  return Buffer.from(getTransactionEncoder().encode({messageBytes, signatures: {[wallet]: null}}));
}

function fixture(changes: Readonly<{lastValidBlockHeight?: string | null}> = {}): Readonly<{
  draft: StockOrderDraft;
  binding: StockDraftBinding;
  report: StockDraftStructuralInspection;
  raw: Buffer;
}> {
  const expected = estimate();
  const state = {now: Date.parse(at(3)), blockHeight: '1001', observedAt: at(3)};
  const context: StockOrderDraftContext = {authenticatedUserId: owner, verifiedTaker: wallet, expected,
    requestStartedAt: at(2), chainObservation: {genesisHash: STOCK_DRAFT_MAINNET_GENESIS,
      blockHeight: '1000', observedAt: at(3)}, validityAuthority: {now: () => state.now,
      readChainObservation: async () => ({genesisHash: STOCK_DRAFT_MAINNET_GENESIS,
        blockHeight: state.blockHeight, observedAt: state.observedAt})}};
  const raw = wire();
  const payload: Record<string, unknown> = {inputMint: expected.input.mint, outputMint: expected.output.mint,
    inAmount: expected.input.amountRaw, outAmount: expected.output.estimatedAmountRaw,
    otherAmountThreshold: expected.output.quotedMinimumAmountRaw, swapMode: 'ExactIn',
    slippageBps: expected.slippageBps, feeBps: expected.swapFee.basisPoints, feeMint: expected.swapFee.mint,
    router: expected.router, mode: 'manual', taker: wallet, transaction: raw.toString('base64'),
    requestId: 'order-lifetime-test-1', lastValidBlockHeight: '1050'};
  if (Object.hasOwn(changes, 'lastValidBlockHeight')) payload['lastValidBlockHeight'] = changes.lastValidBlockHeight;
  if (changes.lastValidBlockHeight === null) {
    delete payload['lastValidBlockHeight'];
    payload['expireAt'] = at(8);
    delete (context as {chainObservation?: unknown}).chainObservation;
  }
  const draft = bindStockOrderDraft(payload, context);
  const binding: StockDraftBinding = {authenticatedUserId: owner, verifiedTaker: wallet,
    requestId: draft.summary.requestId, transactionMessageHash: draft.summary.transactionMessageHash,
    bindingHash: draft.summary.bindingHash};
  return {draft, binding, report: inspectStockDraftStructure(draft, binding), raw};
}

interface RpcRequest {
  readonly jsonrpc: string;
  readonly id: number;
  readonly method: string;
  readonly params?: readonly unknown[];
}

interface TransportOptions {
  readonly genesis?: unknown;
  readonly validities?: readonly unknown[];
  readonly heights?: readonly unknown[];
  readonly envelope?: (request: RpcRequest, result: unknown, call: number) => unknown;
  readonly response?: (payload: unknown, request: RpcRequest, call: number) => Response;
  readonly beforeFirstResponse?: () => Promise<void>;
}

function transport(options: TransportOptions = {}): Readonly<{
  fetch: typeof globalThis.fetch;
  calls: RpcRequest[];
}> {
  const calls: RpcRequest[] = [];
  let validityReads = 0;
  let heightReads = 0;
  const fetch: typeof globalThis.fetch = async (input, init) => {
    assert.equal(String(input), rpcUrl);
    assert.equal(init?.method, 'POST');
    assert.equal(init?.redirect, 'error');
    assert.equal(new Headers(init?.headers).get('content-type'), 'application/json');
    assert.equal(new Headers(init?.headers).get('accept'), 'application/json');
    const request = JSON.parse(String(init?.body)) as RpcRequest;
    calls.push(request);
    if (calls.length === 1) await options.beforeFirstResponse?.();
    let result: unknown;
    if (request.method === 'getGenesisHash') {
      result = Object.hasOwn(options, 'genesis') ? options.genesis : STOCK_DRAFT_MAINNET_GENESIS;
    } else if (request.method === 'isBlockhashValid') {
      const defaults = [{context: {slot: 500, apiVersion: '3.1.8'}, value: true},
        {context: {slot: 501, apiVersion: '3.1.8'}, value: true}];
      result = options.validities !== undefined && validityReads < options.validities.length ?
        options.validities[validityReads] : defaults[validityReads];
      validityReads += 1;
    } else if (request.method === 'getBlockHeight') {
      const defaults = [1001, 1002];
      result = options.heights !== undefined && heightReads < options.heights.length ?
        options.heights[heightReads] : defaults[heightReads];
      heightReads += 1;
    } else {
      throw new Error('Unexpected write or generic RPC method.');
    }
    const payload = options.envelope?.(request, result, calls.length) ??
      {jsonrpc: '2.0', id: request.id, result};
    return options.response?.(payload, request, calls.length) ?? Response.json(payload);
  };
  return {fetch, calls};
}

function verifier(fetch: typeof globalThis.fetch, changes: Readonly<{
  now?: () => number;
  timeoutMs?: number;
  maxConcurrentVerifications?: number;
}> = {}): SolanaMainnetStockOrderLifetimeVerifier {
  return new SolanaMainnetStockOrderLifetimeVerifier({rpcUrl, fetch,
    now: () => Date.parse(at(4)), ...changes});
}

it('verifies two stable finalized observations for the exact bound lifetime and height window', async () => {
  const rpc = transport();
  const candidate = fixture();
  const result = await verifier(rpc.fetch).verify(candidate.draft, candidate.binding, candidate.report);

  assert.deepEqual(rpc.calls.map(call => [call.id, call.method]), [
    [1, 'getGenesisHash'], [2, 'isBlockhashValid'], [3, 'getBlockHeight'],
    [4, 'isBlockhashValid'], [5, 'getBlockHeight'],
  ]);
  assert.deepEqual(Object.keys(rpc.calls[0] ?? {}), ['jsonrpc', 'id', 'method']);
  assert.deepEqual(rpc.calls[1]?.params, [lifetime, {commitment: 'finalized'}]);
  assert.deepEqual(rpc.calls[2]?.params, [{commitment: 'finalized', minContextSlot: 500}]);
  assert.deepEqual(rpc.calls[3]?.params, [lifetime, {commitment: 'finalized', minContextSlot: 500}]);
  assert.deepEqual(rpc.calls[4]?.params, [{commitment: 'finalized', minContextSlot: 501}]);
  assert.equal(result.genesisHash, STOCK_DRAFT_MAINNET_GENESIS);
  assert.equal(result.commitment, 'finalized');
  assert.equal(result.transactionHash, candidate.report.transactionHash);
  assert.equal(result.transactionMessageHash, candidate.report.transactionMessageHash);
  assert.equal(result.draftBindingHash, candidate.report.draftBindingHash);
  assert.equal(result.candidateTermsHash, candidate.report.candidateTermsHash);
  assert.equal(result.lifetime.token, lifetime);
  assert.equal(result.lifetime.tokenSha256.length, 64);
  assert.equal(result.lifetime.admittedAtBlockHeight, '1000');
  assert.equal(result.lifetime.providerLastValidBlockHeight, '1050');
  assert.equal(result.lifetime.firstObservedBlockHeight, '1001');
  assert.equal(result.lifetime.secondObservedBlockHeight, '1002');
  assert.equal(result.lifetime.remainingBlocksAtSecondObservation, '48');
  assert.equal(result.lifetime.providerHeightAssociation, 'bound_not_rpc_derived');
  assert.deepEqual(result.provenance.rpcMethods, ['getGenesisHash', 'isBlockhashValid', 'getBlockHeight',
    'isBlockhashValid', 'getBlockHeight']);
  assert.deepEqual(result.provenance.minimumContextSlots, {firstValidity: null, firstBlockHeight: '500',
    secondValidity: '500', secondBlockHeight: '501'});
  assert.equal(result.provenance.rpcApiVersion, '3.1.8');
  assert.equal(result.provenance.retries, 0);
  assert.equal(result.provenance.cacheUsed, false);
  assert.equal(result.provenance.observationsStable, true);
  assert.match(result.provenance.digestSha256, /^[0-9a-f]{64}$/);
  assert.equal(result.assessment.status, 'recent_blockhash_verified_but_incomplete');
  assert.equal(result.assessment.structuralLifetimeBinding, 'verified');
  assert.equal(result.assessment.admittedChainObservationBinding, 'verified');
  assert.equal(result.assessment.blockhashValidity, 'verified_stable_finalized');
  assert.equal(result.assessment.currentHeightWithinProviderBound, 'verified');
  assert.equal(result.assessment.programOwnership, 'unverified');
  assert.equal(result.assessment.instructionSemantics, 'unverified');
  assert.equal(result.assessment.accountState, 'unverified');
  assert.equal(result.assessment.transactionTerms, 'unverified');
  assert.equal(result.assessment.simulation, 'not_run');
  assert.equal(result.assessment.approvable, false);
  assert.equal(result.assessment.readyForSimulation, false);
  assert.equal(result.assessment.signingEnabled, false);
  assert.equal(result.assessment.broadcastEnabled, false);
  assert.equal(result.assessment.financialOperationsEnabled, false);
  assert.ok(Object.isFrozen(result) && Object.isFrozen(result.lifetime) &&
    Object.isFrozen(result.provenance) && Object.isFrozen(result.provenance.rpcMethods) &&
    Object.isFrozen(result.provenance.minimumContextSlots) && Object.isFrozen(result.assessment));
  const serialized = JSON.stringify(result);
  assert.ok(!serialized.includes(candidate.raw.toString('base64')) &&
    !serialized.includes(candidate.raw.toString('hex')) && !serialized.includes('AQID'));
});

it('pins the full canonical mainnet genesis and rejects the commonly truncated prefix before lifetime reads', async () => {
  assert.equal(STOCK_DRAFT_MAINNET_GENESIS, '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d');
  for (const genesis of [shortTruncatedGenesis, 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1', '']) {
    const rpc = transport({genesis});
    const candidate = fixture();
    await assert.rejects(verifier(rpc.fetch).verify(candidate.draft, candidate.binding, candidate.report),
      errorIs('LIFETIME_WRONG_NETWORK'));
    assert.deepEqual(rpc.calls.map(call => call.method), ['getGenesisHash']);
  }
  const invalid = transport({genesis: 7});
  const candidate = fixture();
  await assert.rejects(verifier(invalid.fetch).verify(candidate.draft, candidate.binding, candidate.report),
    errorIs('LIFETIME_RPC_RESPONSE_INVALID'));
});

it('distinguishes an initially invalid blockhash from a validity observation that changes', async () => {
  const candidate = fixture();
  const falseFirst = transport({validities: [{context: {slot: 500, apiVersion: '3.1.8'}, value: false}]});
  await assert.rejects(verifier(falseFirst.fetch).verify(candidate.draft, candidate.binding, candidate.report),
    errorIs('LIFETIME_BLOCKHASH_INVALID'));
  assert.deepEqual(falseFirst.calls.map(call => call.method), ['getGenesisHash', 'isBlockhashValid']);

  for (const second of [
    {context: {slot: 501, apiVersion: '3.1.8'}, value: false},
    {context: {slot: 499, apiVersion: '3.1.8'}, value: true},
  ]) {
    const changed = transport({validities: [
      {context: {slot: 500, apiVersion: '3.1.8'}, value: true}, second,
    ]});
    await assert.rejects(verifier(changed.fetch).verify(candidate.draft, candidate.binding, candidate.report),
      errorIs('LIFETIME_OBSERVATION_CHANGED'));
  }
});

it('rejects stale/regressing heights and equality with or passage beyond the provider bound', async () => {
  const candidate = fixture();
  for (const heights of [[999, 1001], [1001, 1000]]) {
    const rpc = transport({heights});
    await assert.rejects(verifier(rpc.fetch).verify(candidate.draft, candidate.binding, candidate.report),
      errorIs('LIFETIME_OBSERVATION_CHANGED'));
  }
  for (const heights of [[1050, 1050], [1049, 1050], [1051, 1052]]) {
    const rpc = transport({heights});
    await assert.rejects(verifier(rpc.fetch).verify(candidate.draft, candidate.binding, candidate.report),
      errorIs('LIFETIME_EXPIRED'));
  }
});

it('requires a height-backed draft and the exact original structural lifetime/binding', async () => {
  const noHeight = fixture({lastValidBlockHeight: null});
  let reads = 0;
  await assert.rejects(verifier(async () => { reads += 1; return Response.json({}); })
    .verify(noHeight.draft, noHeight.binding, noHeight.report), errorIs('LIFETIME_DRAFT_INVALID'));
  assert.equal(reads, 0);

  const candidate = fixture();
  for (const reportChange of [
    {lifetimeToken: {...candidate.report.lifetimeToken, value: getAddressDecoder().decode(new Uint8Array(32).fill(8))}},
    {draftBindingHash: '0'.repeat(64)},
    {candidateTermsHash: 'f'.repeat(64)},
    {networkContext: 'solana:devnet'},
    {header: {...candidate.report.header, numReadonlyNonSignerAccounts: 0}},
  ]) {
    const altered = {...candidate.report, ...reportChange} as unknown as StockDraftStructuralInspection;
    await assert.rejects(verifier(transport().fetch).verify(candidate.draft, candidate.binding, altered),
      errorIs('LIFETIME_BINDING_MISMATCH'));
  }
  await assert.rejects(verifier(transport().fetch).verify(candidate.draft,
    {...candidate.binding, requestId: 'changed'}, candidate.report), errorIs('LIFETIME_BINDING_MISMATCH'));
});

it('copies binding and structural lifetime values before the first async RPC turn', async () => {
  let release!: () => void;
  let entered!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const started = new Promise<void>(resolve => { entered = resolve; });
  const rpc = transport({beforeFirstResponse: async () => { entered(); await gate; }});
  const candidate = fixture();
  const binding = {...candidate.binding};
  const report = structuredClone(candidate.report) as StockDraftStructuralInspection;
  const pending = verifier(rpc.fetch).verify(candidate.draft, binding, report);
  await started;
  (binding as {requestId: string}).requestId = 'changed-after-start';
  (report.lifetimeToken as {value: string}).value = getAddressDecoder().decode(new Uint8Array(32).fill(8));
  (report as {transactionHash: string}).transactionHash = '0'.repeat(64);
  release();
  const result = await pending;
  assert.equal(result.lifetime.token, lifetime);
  assert.equal(result.transactionHash, candidate.draft.summary.transactionHash);
});

it('rejects accessor-bearing inputs without invoking their accessors', async () => {
  const candidate = fixture();
  let reads = 0;
  const report = {...candidate.report};
  Object.defineProperty(report, 'lifetimeToken', {enumerable: true, get() { reads += 1; return candidate.report.lifetimeToken; }});
  await assert.rejects(verifier(transport().fetch).verify(candidate.draft, candidate.binding,
    report as StockDraftStructuralInspection), errorIs('LIFETIME_BINDING_MISMATCH'));
  assert.equal(reads, 0);
});

it('strictly validates JSON-RPC envelope, response identity, content and bounded body', async () => {
  const candidate = fixture();
  const cases: readonly [TransportOptions, string][] = [
    [{envelope: (request, result) => ({jsonrpc: '2.0', id: request.id + 1, result})},
      'LIFETIME_RPC_RESPONSE_INVALID'],
    [{envelope: (request, result) => ({jsonrpc: '1.0', id: request.id, result})},
      'LIFETIME_RPC_RESPONSE_INVALID'],
    [{envelope: request => ({jsonrpc: '2.0', id: request.id, error: {message: 'private-upstream'}})},
      'LIFETIME_RPC_RESPONSE_INVALID'],
    [{envelope: (request, result) => ({jsonrpc: '2.0', id: request.id, result, extra: true})},
      'LIFETIME_RPC_RESPONSE_INVALID'],
    [{response: payload => new Response(JSON.stringify(payload), {status: 503,
      headers: {'content-type': 'application/json'}})}, 'LIFETIME_RPC_UNAVAILABLE'],
    [{response: payload => new Response(JSON.stringify(payload), {headers: {'content-type': 'text/plain'}})},
      'LIFETIME_RPC_RESPONSE_INVALID'],
    [{response: payload => {
      const response = Response.json(payload);
      Object.defineProperty(response, 'redirected', {value: true});
      return response;
    }}, 'LIFETIME_RPC_RESPONSE_INVALID'],
    [{response: payload => {
      const response = Response.json(payload);
      Object.defineProperty(response, 'url', {value: 'https://other.example.test/'});
      return response;
    }}, 'LIFETIME_RPC_RESPONSE_INVALID'],
    [{response: () => new Response('{', {headers: {'content-type': 'application/json'}})},
      'LIFETIME_RPC_RESPONSE_INVALID'],
    [{response: () => new Response(JSON.stringify({private: 'x'.repeat(33_000)}),
      {headers: {'content-type': 'application/json'}})}, 'LIFETIME_RPC_RESPONSE_INVALID'],
  ];
  for (const [options, code] of cases) {
    await assert.rejects(verifier(transport(options).fetch).verify(candidate.draft, candidate.binding,
      candidate.report), errorIs(code));
  }
  await assert.rejects(verifier(async () => ({}) as Response).verify(candidate.draft, candidate.binding,
    candidate.report), errorIs('LIFETIME_RPC_RESPONSE_INVALID'));
});

it('rejects malformed validity contexts and non-exact block heights', async () => {
  const candidate = fixture();
  for (const validity of [
    {context: {slot: 0, apiVersion: '3.1.8'}, value: true},
    {context: {slot: 500, apiVersion: 'private-upstream'}, value: true},
    {context: {slot: 500, apiVersion: '3.1.8', extra: true}, value: true},
    {context: {slot: 500}, value: 'true'},
    {context: {slot: 500}, value: true, extra: true},
  ]) {
    const rpc = transport({validities: [validity]});
    await assert.rejects(verifier(rpc.fetch).verify(candidate.draft, candidate.binding, candidate.report),
      errorIs('LIFETIME_RPC_RESPONSE_INVALID'));
  }
  for (const height of [0, -1, 1001.5, '1001', null, Number.MAX_SAFE_INTEGER + 1]) {
    const rpc = transport({heights: [height]});
    await assert.rejects(verifier(rpc.fetch).verify(candidate.draft, candidate.binding, candidate.report),
      errorIs('LIFETIME_RPC_RESPONSE_INVALID'));
  }
});

it('enforces one total deadline and releases its concurrency slot after timeout', async () => {
  const candidate = fixture();
  const never: typeof globalThis.fetch = async () => new Promise<Response>(() => undefined);
  const instance = verifier(never, {timeoutMs: 10, maxConcurrentVerifications: 1});
  const first = instance.verify(candidate.draft, candidate.binding, candidate.report);
  await Promise.resolve();
  await assert.rejects(instance.verify(candidate.draft, candidate.binding, candidate.report),
    errorIs('LIFETIME_CONCURRENCY_LIMITED'));
  await assert.rejects(first, errorIs('LIFETIME_RPC_TIMEOUT'));

  const rpc = transport();
  const recovered = verifier(rpc.fetch, {timeoutMs: 20, maxConcurrentVerifications: 1});
  await recovered.verify(candidate.draft, candidate.binding, candidate.report);
});

it('releases its concurrency slot when timer creation fails synchronously', async () => {
  const candidate = fixture();
  const rpc = transport();
  const instance = verifier(rpc.fetch, {maxConcurrentVerifications: 1});
  const original = globalThis.setTimeout;
  globalThis.setTimeout = (() => { throw new Error('private-timer'); }) as unknown as typeof setTimeout;
  try {
    await assert.rejects(instance.verify(candidate.draft, candidate.binding, candidate.report),
      errorIs('LIFETIME_CONFIGURATION_INVALID'));
  } finally {
    globalThis.setTimeout = original;
  }
  await instance.verify(candidate.draft, candidate.binding, candidate.report);
});

it('releases its concurrency slot when timer cleanup throws', async () => {
  const candidate = fixture();
  const rpc = transport({
    validities: [
      {context: {slot: 500, apiVersion: '3.1.8'}, value: true},
      {context: {slot: 501, apiVersion: '3.1.8'}, value: true},
      {context: {slot: 502, apiVersion: '3.1.8'}, value: true},
      {context: {slot: 503, apiVersion: '3.1.8'}, value: true},
    ],
    heights: [1001, 1002, 1003, 1004],
  });
  const instance = verifier(rpc.fetch, {maxConcurrentVerifications: 1});
  const original = globalThis.clearTimeout;
  globalThis.clearTimeout = ((handle: Parameters<typeof clearTimeout>[0]) => {
    original(handle);
    throw new Error('private-clear-timer');
  }) as typeof clearTimeout;
  try {
    await instance.verify(candidate.draft, candidate.binding, candidate.report);
  } finally {
    globalThis.clearTimeout = original;
  }
  await instance.verify(candidate.draft, candidate.binding, candidate.report);
});

it('rejects clock regression, clock expiry and elapsed time beyond the configured total deadline', async () => {
  const candidate = fixture();
  for (const now of [() => Number.NaN, () => { throw new Error('private-clock'); }, () => Date.parse(at(2))]) {
    await assert.rejects(verifier(transport().fetch, {now}).verify(candidate.draft, candidate.binding,
      candidate.report), errorIs('LIFETIME_CONFIGURATION_INVALID'));
  }
  await assert.rejects(verifier(transport().fetch, {now: () => Date.parse(at(13))})
    .verify(candidate.draft, candidate.binding, candidate.report), errorIs('LIFETIME_EXPIRED'));
  let calls = 0;
  await assert.rejects(verifier(transport().fetch, {timeoutMs: 5, now: () => {
    calls += 1;
    return calls === 1 ? Date.parse(at(4)) : Date.parse(at(3));
  }}).verify(candidate.draft, candidate.binding, candidate.report), errorIs('LIFETIME_CONFIGURATION_INVALID'));
  calls = 0;
  await assert.rejects(verifier(transport().fetch, {timeoutMs: 5, now: () => {
    calls += 1;
    return Date.parse(at(4)) + (calls === 1 ? 0 : 5);
  }}).verify(candidate.draft, candidate.binding, candidate.report), errorIs('LIFETIME_RPC_TIMEOUT'));
});

it('rejects unsafe configuration and extra fields before any network work', () => {
  const invalid: unknown[] = [
    {}, {rpcUrl: 'http://rpc.example.test'}, {rpcUrl: 'https://user:pass@rpc.example.test'},
    {rpcUrl: 'https://rpc.example.test/#fragment'}, {rpcUrl: rpcUrl + '\n'},
    {rpcUrl, timeoutMs: 0}, {rpcUrl, timeoutMs: 8001}, {rpcUrl, maxConcurrentVerifications: 0},
    {rpcUrl, maxConcurrentVerifications: 9}, {rpcUrl, fetch: 1}, {rpcUrl, now: 1},
    {rpcUrl, privateProviderToken: 'private-upstream'},
  ];
  for (const options of invalid) {
    assert.throws(() => new SolanaMainnetStockOrderLifetimeVerifier(
      options as ConstructorParameters<typeof SolanaMainnetStockOrderLifetimeVerifier>[0]),
    errorIs('LIFETIME_CONFIGURATION_INVALID'));
  }
});

it('exports no simulation, signing, sending, broadcasting, route or environment capability', async () => {
  const instance = verifier(transport().fetch);
  assert.deepEqual(Object.getOwnPropertyNames(SolanaMainnetStockOrderLifetimeVerifier.prototype),
    ['constructor', 'verify']);
  for (const capability of ['simulate', 'sign', 'send', 'sendTransaction', 'broadcast', 'approve',
    'markReviewed', 'route', 'fromEnv']) {
    assert.equal((instance as unknown as Record<string, unknown>)[capability], undefined);
  }
  const source = await readFile(new URL('../src/stock-order-lifetime-verifier.ts', import.meta.url), 'utf8');
  for (const forbidden of ['sendTransaction', 'simulateTransaction', 'signTransaction', 'process.env']) {
    assert.equal(source.includes(forbidden), false);
  }
});

it('accepts mixed RPC software versions while enforcing finalized validity and monotonic heights', async () => {
  const candidate = fixture();
  const rpc = transport({validities: [
    {context: {slot: 500, apiVersion: '3.1.8'}, value: true},
    {context: {slot: 501, apiVersion: '4.3.0-rc.1'}, value: true},
  ]});
  const report = await verifier(rpc.fetch).verify(candidate.draft, candidate.binding, candidate.report);
  assert.equal(report.provenance.rpcApiVersion, '4.3.0-rc.1');
});
