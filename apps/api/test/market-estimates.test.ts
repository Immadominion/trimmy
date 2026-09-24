import assert from 'node:assert/strict';
import { it } from 'node:test';
import { buildApp } from '../src/app.js';
import { JupiterMarketEstimates, MarketEstimateError, RESEARCH_MARKET_ASSETS, readMarketEstimates } from '../src/market-estimates.js';
import type { MarketEstimateInput } from '../src/market-estimates.js';
const input: MarketEstimateInput = {inputAsset: 'SOL', outputAsset: 'USDC', amountRaw: '10000000'};
const started = Date.parse('2026-09-14T12:00:00.000Z');
function fixture(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {inputMint: RESEARCH_MARKET_ASSETS.SOL.mint, outputMint: RESEARCH_MARKET_ASSETS.USDC.mint,
    inAmount: '10000000', outAmount: '1000000', otherAmountThreshold: '995000', swapMode: 'ExactIn',
    slippageBps: 50, feeBps: 2, feeMint: RESEARCH_MARKET_ASSETS.SOL.mint, router: 'metis',
    transaction: null, taker: null, ...overrides};
}
function client(payload = fixture(), options: {fetch?: typeof fetch; now?: () => number; timeoutMs?: number} = {}) {
  return new JupiterMarketEstimates({access: {kind: 'keyless_research'},
    now: () => started, fetch: async () => Response.json(payload), ...options});
}
const codeIs = (code: string) => (e: unknown) => e instanceof MarketEstimateError && e.code === code;

it('makes a fixed-origin no-taker GET and returns detached indicative values only', async () => {
  const response = fixture({requestId: 'must-not-expose-provider-execution-id', routePlan: [{anything: 'ignored'}], signatureFeeLamports: 0});
  const api = client(response, {fetch: async (url, options) => {
    const u = new URL(String(url));
    assert.equal(u.origin + u.pathname, 'https://api.jup.ag/swap/v2/order');
    assert.deepEqual([...u.searchParams.keys()].sort(), ['amount', 'inputMint', 'outputMint', 'slippageBps']);
    assert.equal(u.searchParams.get('amount'), input.amountRaw);
    // A fixed research tolerance makes the quoted minimum a real floor.
    assert.equal(u.searchParams.get('slippageBps'), '50');
    assert.equal(options?.method, 'GET'); assert.equal(options.redirect, 'error');
    assert.equal(new Headers(options.headers).get('x-api-key'), null);
    return Response.json(response);
  }});
  const quote = await api.estimate(input);
  assert.equal(quote.executable, false); assert.equal(quote.walletChecked, false); assert.equal(quote.networkFees, null);
  assert.equal(quote.output.estimatedAmountRaw, '1000000');
  assert.equal(quote.input.decimals, 9); assert.equal(quote.output.decimals, 6);
  assert.equal(quote.refreshAfter, '2026-09-14T12:00:10.000Z');
  assert.equal(quote.providerExpiresAt, null);
  assert.ok(!JSON.stringify(quote).includes('requestId')); assert.ok(!JSON.stringify(quote).includes('transaction'));
  assert.ok(Object.isFrozen(quote) && Object.isFrozen(quote.output));
});
it('preserves raw u64 output above Number.MAX_SAFE_INTEGER without rounding', async () => {
  const q = await client(fixture({outAmount: '9007199254740993', otherAmountThreshold: '9007199254740993'})).estimate(input);
  assert.equal(q.output.estimatedAmountRaw, '9007199254740993');
});
it('supports the reverse pinned pair with its own decimals and input bound', async () => {
  const q = await client(fixture({inputMint: RESEARCH_MARKET_ASSETS.USDC.mint, outputMint: RESEARCH_MARKET_ASSETS.SOL.mint,
    inAmount: '1000000', feeMint: RESEARCH_MARKET_ASSETS.USDC.mint})).estimate({inputAsset: 'USDC', outputAsset: 'SOL', amountRaw: '1000000'});
  assert.equal(q.input.symbol, 'USDC'); assert.equal(q.input.decimals, 6); assert.equal(q.output.decimals, 9);
});
it('rejects unsupported, noncanonical, zero and oversized inputs before network access', async () => {
  let calls = 0; const api = client(fixture(), {fetch: async () => { calls++; return Response.json(fixture()); }});
  for (const change of [{inputAsset: 'ASTER'}, {outputAsset: 'SOL'}, {amountRaw: '0'}, {amountRaw: '01'},
    {amountRaw: '1.5'}, {amountRaw: '1e7'}, {amountRaw: '1000000001'}, {amountRaw: '1\n'}]) {
    await assert.rejects(api.estimate({...input, ...change} as MarketEstimateInput), codeIs('MARKET_INPUT_INVALID'));
  }
  assert.equal(calls, 0);
});
it('rejects mismatched echoed pair, amount or swap mode', async () => {
  for (const change of [{inputMint: RESEARCH_MARKET_ASSETS.USDC.mint}, {outputMint: 'unknown'}, {inAmount: '10000001'}, {swapMode: 'ExactOut'}]) {
    await assert.rejects(client(fixture(change)).estimate(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
});
it('never accepts an assembled transaction, taker, or provider error as a usable estimate', async () => {
  for (const change of [{transaction: 'unsigned-tx'}, {transaction: ''}, {transaction: undefined}, {taker: 'some-wallet'},
    {errorCode: 1}, {errorMessage: 'private-upstream-details'}, {error: 'failure'}]) {
    await assert.rejects(client(fixture(change)).estimate(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
});
it('requires valid exact amounts, coherent thresholds, bounded fees and known routers', async () => {
  for (const change of [{outAmount: '0'}, {outAmount: 1000000}, {outAmount: '1e6'}, {outAmount: '18446744073709551616'},
    {otherAmountThreshold: '1000001'}, {otherAmountThreshold: '1'}, {outAmount: '1000000\n'}, {slippageBps: 0.5},
    {slippageBps: 10001}, {slippageBps: 0}, {slippageBps: 100}, {feeBps: -1}, {feeBps: '2'}, {feeMint: 'another-mint'},
    {router: 'unknown'}]) {
    await assert.rejects(client(fixture(change)).estimate(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
});
it('shortens local display lifetime to RFQ expiry and rejects stale or invalid times', async () => {
  const q = await client(fixture({router: 'jupiterz', expireAt: '2026-09-14T12:00:03Z'})).estimate(input);
  assert.equal(q.refreshAfter, '2026-09-14T12:00:03.000Z');
  for (const expireAt of ['2026-09-14T11:59:59Z', '2026-09-14T12:00:00Z']) {
    await assert.rejects(client(fixture({expireAt})).estimate(input), codeIs('MARKET_ESTIMATE_STALE'));
  }
  for (const expireAt of [123, 'bad', '2027-02-31T12:00:00Z']) {
    await assert.rejects(client(fixture({expireAt})).estimate(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
  let now = started;
  await assert.rejects(client(fixture(), {now: () => now, fetch: async () => { now += 10_000; return Response.json(fixture()); }}).estimate(input), codeIs('MARKET_ESTIMATE_STALE'));
});
it('paces successive and concurrent calls without automatic network retries', async () => {
  let calls = 0; let now = started;
  const api = client(fixture(), {now: () => now, fetch: async () => { calls++; return Response.json(fixture()); }});
  const pending = api.estimate(input);
  await assert.rejects(api.estimate(input), codeIs('MARKET_RATE_LIMITED'));
  await pending;
  await assert.rejects(api.estimate(input), codeIs('MARKET_RATE_LIMITED'));
  now += 2100; await api.estimate(input); assert.equal(calls, 2);
});
it('honours provider throttling with a cooldown and no keyless fallback from failed credentials', async () => {
  let calls = 0; let now = started;
  const api = client(fixture(), {now: () => now, fetch: async () => { calls++; return Response.json({secret: 'never-expose'}, {status: 429}); }});
  await assert.rejects(api.estimate(input), codeIs('MARKET_RATE_LIMITED'));
  now += 3000; await assert.rejects(api.estimate(input), codeIs('MARKET_RATE_LIMITED')); assert.equal(calls, 1);
  let authCalls = 0;
  const auth = new JupiterMarketEstimates({access: {kind: 'api_key', apiKey: 'test-server-only-key'}, fetch: async (_url, options) => {
    authCalls++; assert.equal(new Headers(options?.headers).get('x-api-key'), 'test-server-only-key');
    return Response.json({error: 'test-server-only-key'}, {status: 401});
  }});
  await assert.rejects(auth.estimate(input), codeIs('MARKET_PROVIDER_AUTH_FAILED')); assert.equal(authCalls, 1);
});
it('bounds response size with and without Content-Length and rejects malformed JSON/content', async () => {
  for (const response of [new Response('x', {headers: {'content-type': 'application/json', 'content-length': '262145'}}),
    new Response(' '.repeat(262145), {headers: {'content-type': 'application/json'}}), new Response('<html>upstream</html>'),
    new Response('{', {headers: {'content-type': 'application/json'}}), Response.json([])]) {
    await assert.rejects(client(fixture(), {fetch: async () => response}).estimate(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
});
it('times out slow transport and does not return raw network errors', async () => {
  const api = client(fixture(), {timeoutMs: 10, fetch: async (_url, options) => new Promise((_resolve, reject) => {
    options?.signal?.addEventListener('abort', () => reject(new Error('private-internal-url')), {once: true});
  })});
  await assert.rejects(api.estimate(input), codeIs('MARKET_TIMEOUT'));
  await assert.rejects(client(fixture(), {fetch: async () => { throw new Error('private-api-key'); }}).estimate(input),
    (e: unknown) => e instanceof MarketEstimateError && !e.message.includes('private-api-key'));
});
it('requires an explicit access mode and rejects ambiguous or malformed key configuration', () => {
  assert.equal(readMarketEstimates({}), undefined);
  assert.equal(readMarketEstimates({JUPITER_API_KEY: 'unrelated-key'}), undefined);
  assert.ok(readMarketEstimates({TRIMMY_MARKET_QUOTES: 'keyless_research'}));
  assert.ok(readMarketEstimates({TRIMMY_MARKET_QUOTES: 'api_key', JUPITER_API_KEY: 'valid-test-key'}));
  for (const env of [{TRIMMY_MARKET_QUOTES: 'true'}, {TRIMMY_MARKET_QUOTES: 'api_key'},
    {TRIMMY_MARKET_QUOTES: 'keyless_research', JUPITER_API_KEY: 'ambiguous'},
    {TRIMMY_MARKET_QUOTES: 'api_key', JUPITER_API_KEY: 'valid-key\n'}]) {
    assert.throws(() => readMarketEstimates(env), codeIs('MARKET_UNAVAILABLE'));
  }
});
it('serves the real quote contract through HTTP while all financial mutations stay disabled', async () => {
  const app = buildApp({logger: false, marketEstimates: client()});
  try {
    const r = await app.inject('/v1/markets/estimate?inputAsset=SOL&outputAsset=USDC&amountRaw=10000000');
    assert.equal(r.statusCode, 200); assert.equal(r.json().executable, false); assert.equal(r.headers['cache-control'], 'no-store');
    const cfg = (await app.inject('/v1/config')).json();
    assert.equal(cfg.marketEstimatesEnabled, true); assert.equal(cfg.capabilities.swapsEnabled, false);
    assert.deepEqual((await app.inject('/v1/catalog')).json().assets, []);
    for (const url of ['/v1/markets/estimate', '/v1/execute', '/v1/swaps', '/v1/gifts']) {
      assert.equal((await app.inject({method: 'POST', url, payload: {transaction: 'fake'}})).statusCode, 503);
    }
    assert.equal((await app.inject({method: 'HEAD', url: '/v1/markets/estimate?inputAsset=SOL&outputAsset=USDC&amountRaw=10000000'})).statusCode, 404);
  } finally { await app.close(); }
});
it('HTTP validates all fields and does not pass wallet or arbitrary mint inputs upstream', async () => {
  let calls = 0;
  const app = buildApp({logger: false, marketEstimates: client(fixture(), {fetch: async () => { calls++; return Response.json(fixture()); }})});
  try {
    for (const suffix of ['', '?inputAsset=SOL&outputAsset=USDC&amountRaw=0',
      '?inputAsset=SOL&outputAsset=ASTER&amountRaw=1', '?inputAsset=SOL&outputAsset=USDC&amountRaw=01',
      '?inputAsset=SOL&outputAsset=USDC&amountRaw=1&taker=private-wallet',
      '?inputAsset=SOL&outputAsset=USDC&amountRaw=1&amountRaw=2']) {
      const r = await app.inject('/v1/markets/estimate'+suffix); assert.equal(r.statusCode, 400); assert.ok(!r.body.includes('private-wallet'));
    }
    assert.equal(calls, 0);
  } finally { await app.close(); }
});
it('HTTP reports missing configuration and sanitized provider errors', async () => {
  const app = buildApp({logger: false});
  try {
    const r = await app.inject('/v1/markets/estimate?inputAsset=SOL&outputAsset=USDC&amountRaw=1');
    assert.equal(r.statusCode, 503); assert.equal(r.json().error.code, 'MARKET_UNAVAILABLE');
    assert.equal((await app.inject('/v1/config')).json().marketEstimatesEnabled, false);
  } finally { await app.close(); }
  const failed = buildApp({logger: false, marketEstimates: {estimate: async () => { throw new Error('provider-secret'); }}});
  try {
    const r = await failed.inject('/v1/markets/estimate?inputAsset=SOL&outputAsset=USDC&amountRaw=1');
    assert.equal(r.statusCode, 502); assert.ok(!r.body.includes('provider-secret'));
  } finally { await failed.close(); }
});
it('permits only configured browser origins and GET preflight for estimate queries', async () => {
  const app = buildApp({logger: false, browserOrigins: ['https://trimmy.example'], marketEstimates: client()});
  const url = '/v1/markets/estimate?inputAsset=SOL&outputAsset=USDC&amountRaw=10000000';
  try {
    const preflight = await app.inject({method: 'OPTIONS', url, headers: {origin: 'https://trimmy.example', 'access-control-request-method': 'GET'}});
    assert.equal(preflight.statusCode, 204); assert.equal(preflight.headers['access-control-allow-methods'], 'GET');
    const denied = await app.inject({url, headers: {origin: 'https://unlisted.example'}}); assert.equal(denied.statusCode, 403);
    const allowed = await app.inject({url, headers: {origin: 'https://trimmy.example'}}); assert.equal(allowed.statusCode, 200);
    assert.equal(allowed.headers['access-control-allow-origin'], 'https://trimmy.example');
  } finally { await app.close(); }
});
