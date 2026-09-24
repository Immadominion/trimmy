import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as tick} from 'node:timers/promises';
import {StockResearchClient, RESEARCH_AAPLX_MINT} from './index.js';
import {estimateFixture, searchFixture, variantsFixture} from './fixtures.test-support.js';

const response = (value: unknown, status = 200) => new Response(JSON.stringify(value), {status, headers: {'content-type': 'application/json'}});
const serverError = (code: string, status: number) => response({error: {
  code, message: 'private upstream details', requestId: 'aaaaaaaa-1234-5678-aaaa-123456789abc',
}}, status);
const client = (fetch: typeof globalThis.fetch, timeoutMs = 1000) => new StockResearchClient({apiOrigin: 'https://research.example', fetch, timeoutMs});
const buy = {assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, side: 'buy', amountRaw: '10000000'} as const;
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(done => {resolve = done;}); return {promise, resolve}; }
function countingAbortSignal() {
  const listeners = new Set<EventListenerOrEventListenerObject>();
  const signal = {
    aborted: false,
    addEventListener(type: string, listener: EventListenerOrEventListenerObject) {
      if (type === 'abort') listeners.add(listener);
    },
    removeEventListener(type: string, listener: EventListenerOrEventListenerObject) {
      if (type === 'abort') listeners.delete(listener);
    },
  } as unknown as AbortSignal;
  return {signal, listeners};
}

test('only public GET routes are dispatched, with credentials and HTTP caching omitted', async () => {
  const urls: URL[] = [];
  const api = client(async (input, options) => {
    const url = new URL(String(input)); urls.push(url);
    assert.equal(url.origin, 'https://research.example'); assert.equal(options?.method, 'GET');
    assert.equal(options.credentials, 'omit'); assert.equal(options.cache, 'no-store'); assert.equal(options.redirect, 'error');
    assert.deepEqual(options.headers, {accept: 'application/json'}); assert.equal(options.body, undefined);
    if (url.pathname.endsWith('/search')) return response(searchFixture('Apple & Co', 2));
    if (url.pathname.endsWith('/variants')) return response(variantsFixture());
    return response(estimateFixture());
  });
  await api.search('Apple & Co', {limit: 2}); await api.variants('apple'); const estimate = await api.estimate(buy);
  assert.deepEqual(Object.fromEntries(urls[0]!.searchParams), {query: 'Apple & Co', limit: '2'});
  assert.equal(urls[1]!.pathname, '/v1/markets/stocks/variants'); assert.equal(urls[2]!.pathname, '/v1/markets/stocks/estimate');
  assert.deepEqual(Object.fromEntries(urls[2]!.searchParams), buy);
  assert.equal(estimate.output.estimatedAmountRaw, '18446744073709551615');
});

test('input validation and cancellation happen before any network request', async () => {
  let calls = 0; const api = client(async () => {calls++; return response({});});
  await assert.rejects(api.search('Apple\n'), {code: 'STOCK_INPUT_INVALID'});
  await assert.rejects(api.search('Apple', {limit: 21}), {code: 'STOCK_INPUT_INVALID'});
  await assert.rejects(api.variants('../apple'), {code: 'STOCK_INPUT_INVALID'});
  await assert.rejects(api.estimate({...buy, amountRaw: '100000001'}), {code: 'MARKET_INPUT_INVALID'});
  await assert.rejects(api.estimate(Object.assign({}, buy, {wallet: 'must-not-send'})), {code: 'MARKET_INPUT_INVALID'});
  const abort = new AbortController(); abort.abort();
  await assert.rejects(api.search('Apple', {signal: abort.signal}), {code: 'STOCK_CANCELLED'});
  assert.equal(calls, 0);
  assert.throws(() => new StockResearchClient({apiOrigin: 'http://research.example'}), {code: 'STOCK_INVALID_CONFIGURATION'});
});

test('response echoes bind search, variants, side and exact amount to their requests', async () => {
  await assert.rejects(client(async () => response(searchFixture('Tesla'))).search('Apple'), {code: 'STOCK_RESPONSE_INVALID'});
  await assert.rejects(client(async () => response(variantsFixture('tesla'))).variants('apple'), {code: 'STOCK_RESPONSE_INVALID'});
  for (const value of [estimateFixture('buy', '10000001'), estimateFixture('sell')]) {
    await assert.rejects(client(async () => response(value)).estimate(buy), {code: 'STOCK_RESPONSE_INVALID'});
  }
});

test('an estimate request is cloned before await so caller mutation cannot change response binding', async () => {
  const pending = deferred<Response>(); const request = {...buy, amountRaw: String(buy.amountRaw)};
  const api = client(async () => pending.promise); const result = api.estimate(request);
  request.amountRaw = '10000001'; pending.resolve(response(estimateFixture()));
  assert.equal((await result).input.amountRaw, '10000000');
});

test('redirects, declared and streamed body limits, wrong media and malformed UTF8 fail closed', async () => {
  const cases: [Response, string][] = [
    [new Response('', {status: 302, headers: {location: 'https://elsewhere.example'}}), 'STOCK_REDIRECT_REJECTED'],
    [new Response('{}', {headers: {'content-type': 'text/html'}}), 'STOCK_RESPONSE_INVALID'],
    [new Response(new Uint8Array([255]), {headers: {'content-type': 'application/json'}}), 'STOCK_RESPONSE_INVALID'],
    [new Response('{', {headers: {'content-type': 'application/json'}}), 'STOCK_RESPONSE_INVALID'],
    [new Response(' '.repeat(1048577), {headers: {'content-type': 'application/json'}}), 'STOCK_RESPONSE_TOO_LARGE'],
  ];
  for (const [body, code] of cases) await assert.rejects(client(async () => body).search('Apple'), {code});
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({cancel() {cancelled = true;}});
  await assert.rejects(client(async () => new Response(body, {headers: {'content-type': 'application/json', 'content-length': '1048577'}})).search('Apple'), {code: 'STOCK_RESPONSE_TOO_LARGE'});
  await tick(); assert.equal(cancelled, true);
});

test('safe server codes survive but provider messages and unknown diagnostics never escape', async () => {
  await assert.rejects(client(async () => response({error: {code: 'STOCK_RATE_LIMITED', message: 'secret provider text', requestId: 'id'}}, 429)).search('Apple'),
    {code: 'STOCK_RATE_LIMITED', message: 'STOCK_RATE_LIMITED'});
  await assert.rejects(client(async () => response({error: {code: 'secret', message: 'secret'}}, 500)).search('Apple'),
    {code: 'STOCK_SERVICE_UNAVAILABLE', message: 'STOCK_SERVICE_UNAVAILABLE'});
  await assert.rejects(client(async () => {throw new Error('private URL');}).search('Apple'),
    {code: 'STOCK_NETWORK_ERROR', message: 'STOCK_NETWORK_ERROR'});
});

test('server codes require their exact endpoint and HTTP status', async () => {
  const matrices = {
    discovery: new Map<number, readonly string[]>([
      [400, ['STOCK_INPUT_INVALID']],
      [429, ['STOCK_RATE_LIMITED']],
      [502, ['STOCK_PROVIDER_UNAVAILABLE', 'STOCK_RESPONSE_INVALID']],
      [503, ['STOCK_DISCOVERY_UNAVAILABLE', 'STOCK_PROVIDER_AUTH_FAILED']],
      [504, ['STOCK_TIMEOUT']],
    ]),
    estimate: new Map<number, readonly string[]>([
      [400, ['MARKET_INPUT_INVALID']],
      [429, ['MARKET_RATE_LIMITED']],
      [502, ['MARKET_PROVIDER_UNAVAILABLE', 'MARKET_RESPONSE_INVALID']],
      [503, ['MARKET_UNAVAILABLE', 'MARKET_PROVIDER_AUTH_FAILED']],
      [504, ['MARKET_TIMEOUT', 'MARKET_ESTIMATE_STALE']],
    ]),
  } as const;
  for (const [status, codes] of matrices.discovery) {
    for (const code of codes) {
      await assert.rejects(client(async () => serverError(code, status)).search('Apple'), {code});
    }
  }
  for (const [status, codes] of matrices.estimate) {
    for (const code of codes) {
      await assert.rejects(client(async () => serverError(code, status)).estimate(buy), {code});
    }
  }
  const mismatches = [
    [502, 'STOCK_TIMEOUT', 'discovery'],
    [504, 'MARKET_TIMEOUT', 'discovery'],
    [502, 'MARKET_TIMEOUT', 'estimate'],
    [504, 'STOCK_TIMEOUT', 'estimate'],
  ] as const;
  for (const [status, code, endpoint] of mismatches) {
    const api = client(async () => serverError(code, status));
    const request = endpoint === 'estimate' ? api.estimate(buy) : api.search('Apple');
    await assert.rejects(request, {code: 'STOCK_SERVICE_UNAVAILABLE'});
  }
});

test('a reusable external abort signal detaches every settled request listener', async () => {
  const cancellation = countingAbortSignal(); let calls = 0;
  const api = client(async () => {calls++; assert.equal(cancellation.listeners.size, 1); return response(searchFixture());});
  for (let index = 0; index < 25; index++) {
    await api.search('Apple', {signal: cancellation.signal});
    assert.equal(cancellation.listeners.size, 0);
  }
  assert.equal(calls, 25);
});

test('timeout remains bounded when fetch ignores abort and cancels the eventual late body', async () => {
  const pending = deferred<Response>(); let signal: AbortSignal | null | undefined;
  const api = client(async (_, options) => {signal = options?.signal; return pending.promise;}, 10);
  await assert.rejects(api.search('Apple'), {code: 'STOCK_TIMEOUT'}); assert.equal(signal?.aborted, true);
  let cancelled = false;
  pending.resolve(new Response(new ReadableStream({cancel() {cancelled = true;}})));
  await tick(); assert.equal(cancelled, true);
});

test('explicit cancellation and deadline independently cancel stalled response streams', async () => {
  for (const mode of ['cancel', 'timeout'] as const) {
    let cancelled = false; const started = deferred<void>(); const abort = new AbortController();
    const body = new ReadableStream<Uint8Array>({start(controller) {controller.enqueue(new TextEncoder().encode('{'));}, cancel() {cancelled = true;}});
    const api = client(async () => {started.resolve(); return new Response(body, {headers: {'content-type': 'application/json'}});}, mode === 'timeout' ? 10 : 1000);
    const result = assert.rejects(api.search('Apple', {signal: abort.signal}), {code: mode === 'cancel' ? 'STOCK_CANCELLED' : 'STOCK_TIMEOUT'});
    await started.promise; await tick(); if (mode === 'cancel') abort.abort();
    await result; assert.equal(cancelled, true);
  }
});

test('close aborts all active reads and prevents another request without retries', async () => {
  const pending = deferred<Response>(); let calls = 0;
  const api = client(async () => {calls++; return pending.promise;});
  const result = assert.rejects(api.variants('apple'), {code: 'STOCK_CANCELLED'});
  api.close(); await result;
  await assert.rejects(api.search('Apple'), {code: 'STOCK_CANCELLED'});
  pending.resolve(response(variantsFixture())); await tick(); assert.equal(calls, 1);
});
