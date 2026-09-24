import assert from 'node:assert/strict';
import { it } from 'node:test';
import Fastify from 'fastify';
import { JupiterQuoteReader, MarketEstimateError, JUPITER_QUOTE_ASSETS, readJupiterQuoteReader } from '../src/jupiter-quote-reader.js';
import type { JupiterEstimateAccess } from '../src/jupiter-quote-reader.js';
import { JupiterMarketEstimates } from '../src/market-estimates.js';
import { JupiterStockEstimates, STOCK_ESTIMATE_ASSET, readStockEstimates } from '../src/stock-estimates.js';
import type { StockEstimateInput, StockEstimates } from '../src/stock-estimates.js';
import { registerStockEstimateRoute, STOCK_ESTIMATE_ROUTE } from '../src/stock-estimate-route.js';

const start = Date.parse('2026-09-14T12:00:00Z');
const input: StockEstimateInput = {assetId: 'apple', variantMint: STOCK_ESTIMATE_ASSET.variantMint, side: 'buy', amountRaw: '10000000'};
const codeIs = (code: string) => (error: unknown) => error instanceof MarketEstimateError && error.code === code;
function fixture(side: 'buy' | 'sell' = 'buy', overrides: Record<string, unknown> = {}) {
  return {inputMint: side === 'buy' ? JUPITER_QUOTE_ASSETS.USDC.mint : STOCK_ESTIMATE_ASSET.variantMint,
    outputMint: side === 'buy' ? STOCK_ESTIMATE_ASSET.variantMint : JUPITER_QUOTE_ASSETS.USDC.mint,
    inAmount: '10000000', outAmount: '4153214', otherAmountThreshold: '4132447', swapMode: 'ExactIn',
    slippageBps: 50, feeBps: 2, feeMint: JUPITER_QUOTE_ASSETS.USDC.mint, router: 'metis', transaction: null, taker: null, ...overrides};
}
function client(payload = fixture(), options: {fetch?: typeof fetch; timeoutMs?: number; now?: () => number} = {}) {
  return new JupiterStockEstimates({access: {kind: 'keyless_research'}, now: () => start, fetch: async () => Response.json(payload), ...options});
}
function testApp(estimates?: StockEstimates) {
  const app = Fastify({logger: false, ajv: {customOptions: {removeAdditional: false, coerceTypes: false, useDefaults: false}}});
  registerStockEstimateRoute(app, estimates ? {stockEstimates: estimates} : {});
  return app;
}
function query(change: Record<string, string> = {}) {
  return STOCK_ESTIMATE_ROUTE + '?' + new URLSearchParams({...input, ...change});
}

it('quotes exactly 10 USDC into the pinned Apple issuer variant without a wallet or transaction input', async () => {
  const api = client(fixture('buy', {requestId: 'execution-id-not-returned', multiplier: 99}), {fetch: async (rawUrl, options) => {
    const url = new URL(String(rawUrl));
    assert.equal(url.origin + url.pathname, 'https://api.jup.ag/swap/v2/order');
    assert.deepEqual(Object.fromEntries(url.searchParams), {inputMint: JUPITER_QUOTE_ASSETS.USDC.mint,
      outputMint: STOCK_ESTIMATE_ASSET.variantMint, amount: '10000000', slippageBps: '50'});
    assert.equal(options?.method, 'GET'); assert.equal(options?.redirect, 'error');
    return Response.json(fixture());
  }});
  const result = await api.estimate(input);
  assert.equal(result.assetId, 'apple'); assert.equal(result.variantMint, STOCK_ESTIMATE_ASSET.variantMint);
  assert.equal(result.side, 'buy'); assert.equal(result.input.symbol, 'USDC'); assert.equal(result.input.decimals, 6);
  assert.equal(result.output.symbol, 'AAPLx'); assert.equal(result.output.decimals, 8);
  assert.equal(result.output.estimatedAmountRaw, '4153214'); assert.equal(result.output.quotedMinimumAmountRaw, '4132447');
  assert.equal(result.executionEnabled, false); assert.equal(result.executable, false); assert.equal(result.eligibility, 'unverified');
  assert.equal(result.walletChecked, false); assert.equal(result.networkFees, null); assert.equal(result.amountUnits, 'raw_token_units');
  assert.equal(result.providerExpiresAt, null); assert.equal(result.refreshAfter, '2026-09-14T12:00:10.000Z');
  assert.ok(Object.isFrozen(result) && Object.isFrozen(result.input));
  assert.ok(!JSON.stringify(result).includes('multiplier')); assert.ok(!JSON.stringify(result).includes('requestId'));
});
it('sell uses raw AAPLx input and USDC output without treating decimals as scaled shares', async () => {
  const result = await client(fixture('sell')).estimate({...input, side: 'sell'});
  assert.equal(result.input.symbol, 'AAPLx'); assert.equal(result.input.decimals, 8);
  assert.equal(result.output.symbol, 'USDC'); assert.equal(result.output.decimals, 6);
  assert.equal(result.swapFee.mint, JUPITER_QUOTE_ASSETS.USDC.mint);
});
it('validates asset, issuer mint, side and raw input bounds before any request', async () => {
  let calls = 0;
  const api = client(fixture(), {fetch: async () => { calls++; return Response.json(fixture()); }});
  for (const bad of [{assetId: 'apple-other'}, {variantMint: JUPITER_QUOTE_ASSETS.SOL.mint}, {side: 'Buy'},
    {amountRaw: '0'}, {amountRaw: '01'}, {amountRaw: '1\n'}, {amountRaw: '-1'}, {amountRaw: '1.2'},
    {amountRaw: '1e7'}, {amountRaw: '100000001'}, {amountRaw: '18446744073709551616'}, {taker: 'unwanted'}]) {
    await assert.rejects(api.estimate({...input, ...bad} as StockEstimateInput), codeIs('MARKET_INPUT_INVALID'));
  }
  await assert.rejects(api.estimate({...input, side: 'sell', amountRaw: '100000001'}), codeIs('MARKET_INPUT_INVALID'));
  assert.equal(calls, 0);
});
it('accepts each exact research cap and preserves large u64 outputs as strings', async () => {
  for (const side of ['buy', 'sell'] as const) {
    const q = await client(fixture(side, {inAmount: '100000000', outAmount: '9007199254740993', otherAmountThreshold: '9007199254740993'}))
      .estimate({...input, side, amountRaw: '100000000'});
    assert.equal(q.output.estimatedAmountRaw, '9007199254740993');
  }
});
it('rejects wrong pair, output, threshold, expiry and execution-bearing provider responses', async () => {
  for (const bad of [{outputMint: JUPITER_QUOTE_ASSETS.SOL.mint}, {inputMint: STOCK_ESTIMATE_ASSET.variantMint},
    {inAmount: '10000001'}, {otherAmountThreshold: '1'}, {outAmount: '1\n'}, {feeMint: JUPITER_QUOTE_ASSETS.SOL.mint},
    {transaction: 'unsigned'}, {taker: 'wallet'}, {expireAt: '2027-02-31T12:00:00Z'}, {error: 'no-route-upstream'}]) {
    await assert.rejects(client(fixture('buy', bad)).estimate(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
});
it('does not turn a no-route provider error into fabricated zero-priced stock', async () => {
  let calls = 0;
  await assert.rejects(client(fixture(), {fetch: async () => {
    calls++; return Response.json({error: 'Could not find any route', requestId: 'not-returned'}, {status: 400});
  }}).estimate(input), codeIs('MARKET_PROVIDER_UNAVAILABLE'));
  assert.equal(calls, 1);
});
it('SOL and stock adapters share one in-flight/start budget and provider cooldown', async () => {
  let now = start; let calls = 0; let throttled = false;
  const reader = new JupiterQuoteReader({access: {kind: 'keyless_research'}, now: () => now, fetch: async (rawUrl) => {
    calls++; const url = new URL(String(rawUrl));
    if (throttled) return Response.json({}, {status: 429});
    return Response.json(fixture('buy', {inputMint: url.searchParams.get('inputMint'), outputMint: url.searchParams.get('outputMint')}));
  }});
  const stock = new JupiterStockEstimates(reader); const market = new JupiterMarketEstimates(reader);
  const active = stock.estimate(input);
  await assert.rejects(market.estimate({inputAsset: 'SOL', outputAsset: 'USDC', amountRaw: input.amountRaw}), codeIs('MARKET_RATE_LIMITED'));
  await active;
  await assert.rejects(market.estimate({inputAsset: 'SOL', outputAsset: 'USDC', amountRaw: input.amountRaw}), codeIs('MARKET_RATE_LIMITED'));
  now += 2100; throttled = true;
  await assert.rejects(stock.estimate(input), codeIs('MARKET_RATE_LIMITED'));
  now += 2100;
  await assert.rejects(market.estimate({inputAsset: 'SOL', outputAsset: 'USDC', amountRaw: input.amountRaw}), codeIs('MARKET_RATE_LIMITED'));
  assert.equal(calls, 2);
});
it('a noncooperative fetch cannot exceed the deadline or leave the pacing guard stuck', async () => {
  let now = start;
  const api = client(fixture(), {timeoutMs: 10, now: () => now, fetch: async () => new Promise<Response>(() => undefined)});
  await assert.rejects(api.estimate(input), codeIs('MARKET_TIMEOUT'));
  now += 2100;
  await assert.rejects(api.estimate(input), codeIs('MARKET_TIMEOUT'));
});
it('a stalled body read or cancellation cannot delay timeout or successful response', async () => {
  const stalled = new ReadableStream<Uint8Array>({pull: () => new Promise<void>(() => undefined), cancel: () => new Promise<void>(() => undefined)});
  await assert.rejects(client(fixture(), {timeoutMs: 10, fetch: async () => new Response(stalled, {headers: {'content-type': 'application/json'}})})
    .estimate(input), codeIs('MARKET_TIMEOUT'));
  const oversized = new ReadableStream<Uint8Array>({start(controller) { controller.enqueue(new Uint8Array(262145)); }, cancel: () => new Promise<void>(() => undefined)});
  await assert.rejects(client(fixture(), {timeoutMs: 10, fetch: async () => new Response(oversized, {headers: {'content-type': 'application/json'}})})
    .estimate(input), codeIs('MARKET_RESPONSE_INVALID'));
});
it('requires explicit configuration with no failed-key fallback', async () => {
  assert.equal(readStockEstimates({}), undefined);
  assert.equal(readJupiterQuoteReader({TRIMMY_MARKET_QUOTES: 'disabled'}), undefined);
  assert.ok(readStockEstimates({TRIMMY_MARKET_QUOTES: 'keyless_research'}));
  assert.throws(() => readStockEstimates({TRIMMY_MARKET_QUOTES: 'api_key'}), codeIs('MARKET_UNAVAILABLE'));
  assert.throws(() => new JupiterQuoteReader({access: {kind: 'api_key', apiKey: undefined} as unknown as JupiterEstimateAccess}), codeIs('MARKET_UNAVAILABLE'));
  let calls = 0;
  const api = new JupiterStockEstimates({access: {kind: 'api_key', apiKey: 'server-only-test-key'}, fetch: async (_url, options) => {
    calls++; assert.equal(new Headers(options?.headers).get('x-api-key'), 'server-only-test-key');
    return Response.json({error: 'server-only-test-key'}, {status: 403});
  }});
  await assert.rejects(api.estimate(input), (e: unknown) => codeIs('MARKET_PROVIDER_AUTH_FAILED')(e) && e instanceof Error && !e.message.includes('server-only-test-key'));
  assert.equal(calls, 1);
});
it('HTTP rejects extras, repeated params, bad caps/newlines and HEAD before an injected adapter', async () => {
  let calls = 0;
  const api = testApp({estimate: async (i) => { calls++; return client().estimate(i); }});
  try {
    for (const url of [STOCK_ESTIMATE_ROUTE, query({amountRaw: '1\n'}), query({amountRaw: '100000001'}),
      query({side: 'buy\n'}), query({assetId: 'apple\n'}), query({taker: 'private-wallet'}), query() + '&amountRaw=1']) {
      assert.equal((await api.inject(url)).statusCode, 400, url);
    }
    assert.equal((await api.inject({method: 'HEAD', url: query()})).statusCode, 404);
    assert.equal(calls, 0);
    const response = await api.inject(query()); assert.equal(response.statusCode, 200);
    assert.equal(response.json().executionEnabled, false); assert.equal(response.headers['cache-control'], 'no-store');
  } finally { await api.close(); }
});
it('HTTP returns sanitized unavailable, provider failure and timeout states', async () => {
  for (const [error, status] of [[undefined, 503], [new Error('private-provider-key'), 502],
    [new MarketEstimateError('MARKET_TIMEOUT'), 504], [new MarketEstimateError('MARKET_RATE_LIMITED'), 429]] as const) {
    const api = error ? testApp({estimate: async () => { throw error; }}) : testApp();
    try { const response = await api.inject(query()); assert.equal(response.statusCode, status); assert.ok(!response.body.includes('private-provider-key')); }
    finally { await api.close(); }
  }
});
