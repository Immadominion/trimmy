import assert from 'node:assert/strict';
import { it } from 'node:test';
import Fastify from 'fastify';
import { MarketEstimateError } from '../src/jupiter-quote-reader.js';
import { registerRaydiumStockQuoteRoute, RAYDIUM_STOCK_QUOTE_ROUTE } from '../src/raydium-stock-quote-route.js';
import { RAYDIUM_STOCK_QUOTE_CONFIGURATION, RaydiumStockQuoteReader, readRaydiumStockQuotes } from '../src/raydium-stock-quotes.js';
import type { RaydiumStockQuotes } from '../src/raydium-stock-quotes.js';
import { STOCK_TRADING_ASSETS } from '../src/stock-trading-catalog.js';
import { STOCK_ESTIMATE_ASSET } from '../src/stock-estimates.js';
import type { StockEstimateInput } from '../src/stock-estimates.js';

const start = Date.parse('2026-09-14T18:00:00.000Z');
const usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const aaplx = STOCK_ESTIMATE_ASSET.variantMint;
const directPool = 'ApniVWuZbZoruTAJdyJcLBA4AVw4DKGdV5fHxo6qrAZT';
const remaining = 'EsY5gY7EqTqsmCdCvRNjSDSdJDopBNzCH1qd84YRuUQ2';
const alternatePool = '58oQChx4yWmvKdwLLZzBi4ChoCc2fqCUWBkwMihLYQo2';
const sol = 'So11111111111111111111111111111111111111112';
const input: StockEstimateInput = {
  assetId: 'apple', variantMint: aaplx, side: 'buy', amountRaw: '10000000',
};
const codeIs = (code: string) => (error: unknown) =>
  error instanceof MarketEstimateError && error.code === code;

function route(side: 'buy' | 'sell' = 'buy', overrides: Record<string, unknown> = {}) {
  const inputMint = side === 'buy' ? usdc : aaplx;
  const outputMint = side === 'buy' ? aaplx : usdc;
  return {
    poolId: directPool, inputMint, outputMint, feeMint: inputMint,
    feeRate: 10, feeAmount: side === 'buy' ? '10000' : '2979',
    remainingAccounts: [remaining], lastPoolPriceX64: '33781693798854148406', ...overrides,
  };
}

function fixture(side: 'buy' | 'sell' = 'buy', overrides: Record<string, unknown> = {}) {
  const inputMint = side === 'buy' ? usdc : aaplx;
  const outputMint = side === 'buy' ? aaplx : usdc;
  return {
    id: '0e8c5e20-96c9-42c9-9cfa-adfa349f2e59', success: true, version: 'V1',
    data: {
      swapType: 'BaseIn', inputMint, inputAmount: '10000000', outputMint,
      outputAmount: '2978849', otherAmountThreshold: '2963954', slippageBps: 50,
      priceImpactPct: 0, referrerAmount: '0', actualInputAmount: '10000000',
      routePlan: [route(side)], ...overrides,
    },
  };
}

function client(payload: unknown = fixture(), options: {
  fetch?: typeof fetch; now?: () => number; timeoutMs?: number;
} = {}) {
  return new RaydiumStockQuoteReader({
    now: () => start,
    fetch: async () => Response.json(payload),
    ...options,
  });
}

function testApp(quotes?: RaydiumStockQuotes) {
  const app = Fastify({logger: false, ajv: {customOptions: {
    removeAdditional: false, coerceTypes: false, useDefaults: false,
  }}});
  registerRaydiumStockQuoteRoute(app, quotes ? {quotes} : {});
  return app;
}

function query(change: Record<string, string> = {}) {
  return RAYDIUM_STOCK_QUOTE_ROUTE + '?' + new URLSearchParams({...input, ...change});
}

it('sends only the pinned BaseIn V0 compute GET and projects a non-executable comparison', async () => {
  const payload = fixture('buy', {providerInternal: 'discard-me'});
  const quotes = client(payload, {fetch: async (rawUrl, options) => {
    const url = new URL(String(rawUrl));
    assert.equal(url.origin + url.pathname, RAYDIUM_STOCK_QUOTE_CONFIGURATION.endpoint);
    assert.deepEqual(Object.fromEntries(url.searchParams), {
      inputMint: usdc, outputMint: aaplx, amount: '10000000', slippageBps: '50', txVersion: 'V0',
    });
    assert.equal(options?.method, 'GET');
    assert.equal(options?.redirect, 'error');
    const headers = new Headers(options?.headers);
    assert.equal(headers.get('authorization'), null);
    assert.equal(headers.get('x-api-key'), null);
    assert.match(headers.get('user-agent') ?? '', /^Trimmy-ReadOnly-Research/);
    return Response.json(payload);
  }});
  const quote = await quotes.quote(input);
  assert.equal(quote.provider, 'raydium-trade-api');
  assert.equal(quote.providerEndpoint, 'compute/swap-base-in');
  assert.equal(quote.quoteMode, 'BaseIn');
  assert.equal(quote.transactionVersionRequested, 'V0');
  assert.equal(quote.comparisonOnly, true);
  assert.equal(quote.executionEnabled, false);
  assert.equal(quote.executable, false);
  assert.equal(quote.eligibility, 'unverified');
  assert.equal(quote.walletChecked, false);
  assert.equal(quote.networkFees, null);
  assert.equal(quote.input.amountRaw, '10000000');
  assert.equal(quote.input.providerActualAmountRaw, '10000000');
  assert.equal(quote.output.estimatedAmountRaw, '2978849');
  assert.equal(quote.output.quotedMinimumAmountRaw, '2963954');
  assert.equal(quote.route.hopCount, 1);
  assert.equal(quote.route.hops[0]?.poolId, directPool);
  assert.equal(quote.route.hops[0]?.fee.providerRateRaw, 10);
  assert.equal(quote.route.hops[0]?.fee.rateUnit, 'provider_integer_unverified');
  assert.equal(quote.refreshAfter, '2026-09-14T18:00:10.000Z');
  assert.equal(quote.providerExpiresAt, null);
  assert.ok(Object.isFrozen(quote) && Object.isFrozen(quote.route.hops));
  const serialized = JSON.stringify(quote);
  assert.ok(!serialized.includes('0e8c5e20-96c9-42c9-9cfa-adfa349f2e59'));
  assert.ok(!serialized.includes('discard-me'));
  assert.ok(!serialized.includes(remaining));
  assert.ok(!serialized.includes('lastPoolPriceX64'));
});

it('quotes the reverse pinned pair with raw AAPLx input and USDC output', async () => {
  const quote = await client(fixture('sell', {
    inputAmount: '2978849', outputAmount: '9988901', otherAmountThreshold: '9938956',
    actualInputAmount: '2978849',
  })).quote({...input, side: 'sell', amountRaw: '2978849'});
  assert.equal(quote.input.symbol, 'AAPLx');
  assert.equal(quote.input.decimals, 8);
  assert.equal(quote.output.symbol, 'USDC');
  assert.equal(quote.output.decimals, 6);
  assert.equal(quote.route.hops[0]?.fee.mint, aaplx);
});

it('validates the stock identity, side and capped canonical raw input before fetching', async () => {
  let calls = 0;
  const quotes = client(fixture(), {fetch: async () => { calls += 1; return Response.json(fixture()); }});
  for (const bad of [
    {assetId: 'tesla'}, {variantMint: sol}, {side: 'Buy'}, {amountRaw: '0'}, {amountRaw: '01'},
    {amountRaw: '1\n'}, {amountRaw: '-1'}, {amountRaw: '1.2'}, {amountRaw: '1e7'},
    {amountRaw: '100000001'}, {amountRaw: '18446744073709551616'}, {wallet: directPool},
  ]) {
    await assert.rejects(quotes.quote({...input, ...bad} as StockEstimateInput), codeIs('MARKET_INPUT_INVALID'));
  }
  assert.equal(calls, 0);
});

it('preserves u64 output and fee amounts as strings without Number rounding', async () => {
  const quote = await client(fixture('buy', {
    outputAmount: '9007199254740993', otherAmountThreshold: '9007199254740993',
    routePlan: [route('buy', {feeMint: aaplx, feeAmount: '9007199254740993'})],
  })).quote(input);
  assert.equal(quote.output.estimatedAmountRaw, '9007199254740993');
  assert.equal(quote.route.hops[0]?.fee.amountRaw, '9007199254740993');
});

it('requires the successful V1 UUID envelope and maps logical failures to unavailable', async () => {
  await assert.rejects(client({
    id: '0e8c5e20-96c9-42c9-9cfa-adfa349f2e59', success: false, version: 'V1',
    msg: 'No route found', data: null,
  }).quote(input), (error: unknown) => codeIs('MARKET_PROVIDER_UNAVAILABLE')(error) &&
    error instanceof Error && !error.message.includes('No route found'));
  for (const payload of [[], null, {...fixture(), id: 'not-a-uuid'}, {...fixture(), success: 'true'},
    {...fixture(), version: 'V2'}, {...fixture(), data: null}, {...fixture(), extraEnvelopeField: true},
    {id: 'bad', success: false, version: 'V1', msg: 'No route found'},
    {id: '0e8c5e20-96c9-42c9-9cfa-adfa349f2e59', success: false, version: 'V1',
      msg: 'No route found', data: {transaction: 'never-accept'}},
  ]) {
    await assert.rejects(client(payload).quote(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
});

it('rejects mismatched quote identity, mode, slippage, referral and actual input', async () => {
  for (const change of [
    {inputMint: aaplx}, {outputMint: usdc}, {inputAmount: '10000001'}, {swapType: 'BaseOut'},
    {slippageBps: 49}, {slippageBps: '50'}, {referrerAmount: '1'}, {referrerAmount: 0},
    {actualInputAmount: '10000001'}, {actualInputAmount: '0'},
  ]) {
    await assert.rejects(client(fixture('buy', change)).quote(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
  const omitted = await client(fixture('buy', {actualInputAmount: undefined})).quote(input);
  assert.equal(omitted.input.providerActualAmountRaw, null);
});

it('requires positive u64 amounts, finite price impact and a coherent minimum', async () => {
  for (const change of [
    {outputAmount: '0'}, {outputAmount: 1}, {outputAmount: '1e6'},
    {outputAmount: '18446744073709551616'}, {outputAmount: '1000000\n'},
    {otherAmountThreshold: '0'}, {otherAmountThreshold: '2978850'}, {otherAmountThreshold: '1'},
    {priceImpactPct: '0'}, {priceImpactPct: -1}, {priceImpactPct: 101}, {priceImpactPct: Number.NaN},
  ]) {
    await assert.rejects(client(fixture('buy', change)).quote(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
});

it('accepts one bounded continuous path and rejects duplicate, cyclic or malformed routes', async () => {
  const multiHop = [
    route('buy', {poolId: directPool, outputMint: sol}),
    route('buy', {poolId: alternatePool, inputMint: sol, outputMint: aaplx, feeMint: sol, feeAmount: '100'}),
  ];
  assert.equal((await client(fixture('buy', {routePlan: multiHop})).quote(input)).route.hopCount, 2);
  const tooMany = Array.from({length: 5}, (_, index) => route('buy', {
    poolId: index % 2 === 0 ? directPool : alternatePool,
  }));
  for (const routePlan of [
    [], tooMany,
    [route('buy', {poolId: zeroAddress()})],
    [route('buy', {outputMint: sol})],
    [route('buy'), route('buy')],
    [route('buy', {inputMint: sol})],
    [route('buy', {inputMint: usdc, outputMint: usdc})],
    [route('buy', {feeMint: sol})],
    [route('buy', {remainingAccounts: [remaining, remaining]})],
  ]) {
    await assert.rejects(client(fixture('buy', {routePlan})).quote(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
});

it('bounds every route fee and optional route observation', async () => {
  for (const change of [
    {feeRate: -1}, {feeRate: 10.5}, {feeRate: 10001}, {feeRate: '10'},
    {feeAmount: '-1'}, {feeAmount: '18446744073709551616'}, {feeAmount: '10000001'},
    {remainingAccounts: Array.from({length: 33}, () => remaining)},
    {lastPoolPriceX64: '-1'}, {lastPoolPriceX64: String(1n << 128n)},
  ]) {
    await assert.rejects(client(fixture('buy', {routePlan: [route('buy', change)]})).quote(input),
      codeIs('MARKET_RESPONSE_INVALID'));
  }
});

it('rejects transaction, wallet and signing material at any response depth', async () => {
  for (const change of [
    {transaction: 'base64'}, {transactions: []}, {wallet: directPool},
    {nested: {swapResponse: fixture()}}, {nested: [{addressLookupTableAddresses: []}]},
    {nested: {signature: 'anything'}},
  ]) {
    await assert.rejects(client(fixture('buy', change)).quote(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
});

it('rejects stale results and invalid or regressing server clocks', async () => {
  let now = start;
  await assert.rejects(client(fixture(), {
    now: () => now,
    fetch: async () => { now += 10_000; return Response.json(fixture()); },
  }).quote(input), codeIs('MARKET_ESTIMATE_STALE'));
  now = start;
  await assert.rejects(client(fixture(), {
    now: () => now,
    fetch: async () => { now -= 1; return Response.json(fixture()); },
  }).quote(input), codeIs('MARKET_ESTIMATE_STALE'));
  await assert.rejects(client(fixture(), {now: () => Number.NaN}).quote(input), codeIs('MARKET_UNAVAILABLE'));
});

it('paces starts, rejects concurrency, honors 429 cooldown and never retries', async () => {
  let now = start;
  let calls = 0;
  let resolveFirst: ((response: Response) => void) | undefined;
  const quotes = client(fixture(), {now: () => now, fetch: async () => {
    calls += 1;
    return new Promise<Response>((resolve) => { resolveFirst = resolve; });
  }});
  const first = quotes.quote(input);
  await assert.rejects(quotes.quote(input), codeIs('MARKET_RATE_LIMITED'));
  resolveFirst?.(Response.json(fixture()));
  await first;
  await assert.rejects(quotes.quote(input), codeIs('MARKET_RATE_LIMITED'));
  assert.equal(calls, 1);

  let limitedCalls = 0;
  const limited = client(fixture(), {now: () => now, fetch: async () => {
    limitedCalls += 1;
    return Response.json({secret: 'never-return'}, {status: 429});
  }});
  await assert.rejects(limited.quote(input), codeIs('MARKET_RATE_LIMITED'));
  now += 59_999;
  await assert.rejects(limited.quote(input), codeIs('MARKET_RATE_LIMITED'));
  assert.equal(limitedCalls, 1);
});

it('bounds headers, body, fetch, body reads and cancellation under one deadline', async () => {
  const badResponses = [
    new Response('<html>no</html>', {headers: {'content-type': 'text/html'}}),
    new Response('{', {headers: {'content-type': 'application/json'}}),
    new Response('{}', {headers: {'content-type': 'application/json', 'content-length': '065536'}}),
    new Response('{}', {headers: {'content-type': 'application/json', 'content-length': '65537'}}),
  ];
  for (const response of badResponses) {
    await assert.rejects(client(fixture(), {fetch: async () => response}).quote(input), codeIs('MARKET_RESPONSE_INVALID'));
  }
  const oversized = new ReadableStream<Uint8Array>({
    start(controller) { controller.enqueue(new Uint8Array(65_537)); },
    cancel: () => new Promise<void>(() => undefined),
  });
  await assert.rejects(client(fixture(), {timeoutMs: 10, fetch: async () =>
    new Response(oversized, {headers: {'content-type': 'application/json'}})}).quote(input),
  codeIs('MARKET_RESPONSE_INVALID'));
  const stalled = new ReadableStream<Uint8Array>({
    pull: () => new Promise<void>(() => undefined), cancel: () => new Promise<void>(() => undefined),
  });
  await assert.rejects(client(fixture(), {timeoutMs: 10, fetch: async () =>
    new Response(stalled, {headers: {'content-type': 'application/json'}})}).quote(input),
  codeIs('MARKET_TIMEOUT'));
  await assert.rejects(client(fixture(), {timeoutMs: 10, fetch: async () => new Promise<Response>(() => undefined)}).quote(input),
    codeIs('MARKET_TIMEOUT'));
});

it('rejects redirects and a mismatched final response origin or path', async () => {
  function identifiedResponse(url: string, redirected = false): Response {
    const response = Response.json(fixture());
    Object.defineProperty(response, 'url', {value: url});
    Object.defineProperty(response, 'redirected', {value: redirected});
    return response;
  }
  for (const response of [
    identifiedResponse(RAYDIUM_STOCK_QUOTE_CONFIGURATION.endpoint, true),
    identifiedResponse('https://example.test/compute/swap-base-in'),
    identifiedResponse('https://transaction-v1.raydium.io/transaction/swap-base-in'),
    identifiedResponse('not-a-url'),
  ]) {
    await assert.rejects(client(fixture(), {fetch: async () => response}).quote(input),
      codeIs('MARKET_RESPONSE_INVALID'));
  }
  const accepted = await client(fixture(), {fetch: async () =>
    identifiedResponse(RAYDIUM_STOCK_QUOTE_CONFIGURATION.endpoint + '?provider=kept-private')}).quote(input);
  assert.equal(accepted.providerEndpoint, 'compute/swap-base-in');
});

it('sanitizes transport and HTTP failures without attempting a fallback', async () => {
  let calls = 0;
  await assert.rejects(client(fixture(), {fetch: async () => {
    calls += 1;
    throw new Error('private-upstream-details');
  }}).quote(input), (error: unknown) => error instanceof MarketEstimateError &&
    error.code === 'MARKET_PROVIDER_UNAVAILABLE' && !error.message.includes('private-upstream-details'));
  assert.equal(calls, 1);
  for (const status of [400, 401, 403, 500]) {
    await assert.rejects(client(fixture(), {fetch: async () => Response.json({private: 'body'}, {status})}).quote(input),
      codeIs('MARKET_PROVIDER_UNAVAILABLE'));
  }
});

it('is disabled by default and accepts only explicit keyless read-only configuration', () => {
  assert.equal(readRaydiumStockQuotes({}), undefined);
  assert.equal(readRaydiumStockQuotes({TRIMMY_RAYDIUM_STOCK_QUOTES: 'disabled'}), undefined);
  assert.ok(readRaydiumStockQuotes({TRIMMY_RAYDIUM_STOCK_QUOTES: 'read_only'}));
  for (const env of [
    {TRIMMY_RAYDIUM_STOCK_QUOTES: 'true'},
    {TRIMMY_RAYDIUM_STOCK_QUOTES: 'read_only', RAYDIUM_API_KEY: 'unwanted'},
    {TRIMMY_RAYDIUM_STOCK_QUOTES: 'read_only', RAYDIUM_API_URL: 'https://example.test'},
  ]) assert.throws(() => readRaydiumStockQuotes(env), codeIs('MARKET_UNAVAILABLE'));
  assert.throws(() => new RaydiumStockQuoteReader({timeoutMs: 8_001}), codeIs('MARKET_UNAVAILABLE'));
});

it('serves a separate no-store GET and refuses HEAD, extras and repeated values', async () => {
  let calls = 0;
  const app = testApp({quote: async (candidate) => {
    calls += 1;
    return client().quote(candidate);
  }});
  try {
    for (const url of [
      RAYDIUM_STOCK_QUOTE_ROUTE, query({amountRaw: '0'}), query({amountRaw: '100000001'}),
      query({side: 'buy\n'}), query({wallet: directPool}), query() + '&amountRaw=1',
    ]) assert.equal((await app.inject(url)).statusCode, 400, url);
    assert.equal((await app.inject({method: 'HEAD', url: query()})).statusCode, 404);
    assert.equal(calls, 0);
    const response = await app.inject(query());
    assert.equal(response.statusCode, 200);
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.equal(response.json().executionEnabled, false);
    assert.equal(calls, 1);
  } finally {
    await app.close();
  }
});

it('maps route errors explicitly and never exposes thrown provider details', async () => {
  const cases: Array<[RaydiumStockQuotes | undefined, number, string]> = [
    [undefined, 503, 'MARKET_UNAVAILABLE'],
    [{quote: async () => { throw new MarketEstimateError('MARKET_RATE_LIMITED'); }}, 429, 'MARKET_RATE_LIMITED'],
    [{quote: async () => { throw new MarketEstimateError('MARKET_TIMEOUT'); }}, 504, 'MARKET_TIMEOUT'],
    [{quote: async () => { throw new MarketEstimateError('MARKET_ESTIMATE_STALE'); }}, 504, 'MARKET_ESTIMATE_STALE'],
    [{quote: async () => { throw new MarketEstimateError('MARKET_RESPONSE_INVALID'); }}, 502, 'MARKET_RESPONSE_INVALID'],
    [{quote: async () => { throw new Error('provider-secret'); }}, 502, 'MARKET_PROVIDER_UNAVAILABLE'],
  ];
  for (const [quotes, status, code] of cases) {
    const app = testApp(quotes);
    try {
      const response = await app.inject(query());
      assert.equal(response.statusCode, status);
      assert.equal(response.json().error.code, code);
      assert.ok(!response.body.includes('provider-secret'));
      assert.equal(typeof response.json().error.requestId, 'string');
      assert.ok(response.json().error.requestId.length > 0);
    } finally {
      await app.close();
    }
  }
});

function zeroAddress(): string {
  return '11111111111111111111111111111111';
}


it('comparison HTTP quotes preserve each admitted stock identity in both directions', async () => {
  for (const stock of STOCK_TRADING_ASSETS.slice(1)) for (const side of ['buy', 'sell'] as const) {
    const pair = side === 'buy' ? {inputMint: usdc, outputMint: stock.mint} : {inputMint: stock.mint, outputMint: usdc};
    const payload = fixture(side, {...pair, routePlan: [route(side, {...pair, feeMint: pair.inputMint})]});
    const app = testApp(client(payload, {fetch: async rawUrl => {
      const url = new URL(String(rawUrl));
      assert.equal(url.searchParams.get('inputMint'), pair.inputMint);
      assert.equal(url.searchParams.get('outputMint'), pair.outputMint);
      return Response.json(payload);
    }}));
    try {
      const result = await app.inject(query({assetId: stock.assetId, variantMint: stock.mint, side}));
      assert.equal(result.statusCode, 200);
      assert.equal(result.json().assetId, stock.assetId);
      assert.equal(side === 'buy' ? result.json().output.symbol : result.json().input.symbol, stock.symbol);
    } finally {await app.close();}
  }
});
