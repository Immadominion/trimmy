import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as tick} from 'node:timers/promises';
import {StockResearchClient, RESEARCH_AAPLX_MINT} from './index.js';
import {FIXED_NOW, historyRequest, raydiumQuoteFixture, stockHistoryFixture} from './read-contracts.test-support.js';

const buy = {assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, side: 'buy', amountRaw: '10000000'} as const;
function response(value: unknown, status = 200, url = '', redirected = false): Response {
  const result = new Response(JSON.stringify(value), {status, headers: {'content-type': 'application/json'}});
  if (url) Object.defineProperty(result, 'url', {value: url, configurable: true});
  if (redirected) Object.defineProperty(result, 'redirected', {value: true, configurable: true});
  return result;
}
const serverError = (code: string, status: number) => response({error: {
  code, message: 'private upstream details', requestId: 'aaaaaaaa-1234-5678-aaaa-123456789abc',
}}, status);
const client = (fetch: typeof globalThis.fetch, timeoutMs = 1_000, now = () => FIXED_NOW) =>
  new StockResearchClient({apiOrigin: 'https://research.example', fetch, timeoutMs, now});
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => {resolve = done;});
  return {promise, resolve};
}
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

test('Raydium and history dispatch as distinct inert GET reads with exact pinned query fields', async () => {
  const urls: URL[] = [];
  const api = client(async (input, options) => {
    const url = new URL(String(input)); urls.push(url);
    assert.equal(url.origin, 'https://research.example'); assert.equal(options?.method, 'GET');
    assert.equal(options?.credentials, 'omit'); assert.equal(options?.cache, 'no-store');
    assert.equal(options?.redirect, 'error'); assert.deepEqual(options?.headers, {accept: 'application/json'});
    assert.equal(options?.body, undefined);
    return url.pathname.endsWith('/history') ? response(stockHistoryFixture()) : response(raydiumQuoteFixture());
  });
  const quote = await api.raydiumQuote(buy), history = await api.history(historyRequest);
  assert.equal(urls[0]!.pathname, '/v1/markets/stocks/quotes/raydium');
  assert.deepEqual(Object.fromEntries(urls[0]!.searchParams), buy);
  assert.equal(urls[1]!.pathname, '/v1/markets/stocks/history');
  assert.deepEqual(Object.fromEntries(urls[1]!.searchParams), historyRequest);
  assert.equal(quote.provider, 'raydium-trade-api'); assert.equal(history.provider, 'tokens-xyz-v1');
  assert.equal(quote.executionEnabled, false); assert.equal(history.executionEnabled, false);
  assert.equal('bestQuote' in api, false);
});

test('both new reads reject unpinned or extra input before fetch', async () => {
  let calls = 0; const api = client(async () => {calls++; return response({});});
  await assert.rejects(api.raydiumQuote({...buy, amountRaw: '100000001'}), {code: 'MARKET_INPUT_INVALID'});
  await assert.rejects(api.raydiumQuote(Object.assign({}, buy, {wallet: 'must-not-send'})), {code: 'MARKET_INPUT_INVALID'});
  await assert.rejects(api.history({...historyRequest, variantMint: 'So11111111111111111111111111111111111111112'} as never),
    {code: 'STOCK_HISTORY_INPUT_INVALID'});
  await assert.rejects(api.history(Object.assign({}, historyRequest, {canonicalEquityHistory: true}) as never),
    {code: 'STOCK_HISTORY_INPUT_INVALID'});
  assert.equal(calls, 0);
});

test('invalid or throwing clocks fail safely before either time-sensitive network read', async () => {
  const clocks: Array<() => number> = [() => Number.NaN, () => 1.5, () => -1,
    () => { throw new Error('private clock detail'); }];
  for (const now of clocks) {
    for (const kind of ['raydium', 'history'] as const) {
      let calls = 0; const api = client(async () => {calls++; return response({});}, 1_000, now);
      const result = kind === 'raydium' ? api.raydiumQuote(buy) : api.history(historyRequest);
      await assert.rejects(result, {code: 'STOCK_INVALID_CONFIGURATION', message: 'STOCK_INVALID_CONFIGURATION'});
      assert.equal(calls, 0);
    }
  }
});

test('both commands are cloned before await so caller mutation cannot alter response binding', async () => {
  const quotePending = deferred<Response>(), quoteRequest = {...buy, amountRaw: String(buy.amountRaw)};
  const quoteResult = client(async () => quotePending.promise).raydiumQuote(quoteRequest);
  quoteRequest.amountRaw = '10000001'; quotePending.resolve(response(raydiumQuoteFixture()));
  assert.equal((await quoteResult).input.amountRaw, '10000000');

  const historyPending = deferred<Response>(), mutableHistory = {...historyRequest, toUnixSeconds: String(historyRequest.toUnixSeconds)};
  const historyResult = client(async () => historyPending.promise).history(mutableHistory);
  mutableHistory.toUnixSeconds = '1789354800'; historyPending.resolve(response(stockHistoryFixture()));
  assert.equal((await historyResult).toUnixSeconds, historyRequest.toUnixSeconds);
});

test('response identity requires the exact same HTTPS origin, path and query without redirects', async () => {
  const expected = `https://research.example/v1/markets/stocks/quotes/raydium?${new URLSearchParams(buy)}`;
  const cases = [
    response(raydiumQuoteFixture(), 200, expected, true),
    response(raydiumQuoteFixture(), 200, expected.replace('research.example', 'other.example')),
    response(raydiumQuoteFixture(), 200, expected.replace('/quotes/raydium', '/estimate')),
    response(raydiumQuoteFixture(), 200, expected + '&extra=1'),
    response(raydiumQuoteFixture(), 200, expected.replace('https:', 'http:')),
  ];
  for (const candidate of cases) {
    await assert.rejects(client(async () => candidate).raydiumQuote(buy), {code: 'STOCK_REDIRECT_REJECTED'});
  }
  assert.equal((await client(async () => response(raydiumQuoteFixture(), 200, expected)).raydiumQuote(buy)).provider,
    'raydium-trade-api');
});

test('server errors obey each route HTTP-status matrix and never expose provider messages', async () => {
  const matrices = {
    raydium: new Map<number, readonly string[]>([
      [400, ['MARKET_INPUT_INVALID']], [429, ['MARKET_RATE_LIMITED']],
      [502, ['MARKET_PROVIDER_AUTH_FAILED', 'MARKET_PROVIDER_UNAVAILABLE', 'MARKET_RESPONSE_INVALID']],
      [503, ['MARKET_UNAVAILABLE']], [504, ['MARKET_TIMEOUT', 'MARKET_ESTIMATE_STALE']],
    ]),
    history: new Map<number, readonly string[]>([
      [400, ['STOCK_HISTORY_INPUT_INVALID']], [429, ['STOCK_HISTORY_RATE_LIMITED']],
      [502, ['STOCK_HISTORY_PROVIDER_UNAVAILABLE', 'STOCK_HISTORY_RESPONSE_INVALID']],
      [503, ['STOCK_HISTORY_UNAVAILABLE', 'STOCK_HISTORY_PROVIDER_AUTH_FAILED']], [504, ['STOCK_HISTORY_TIMEOUT']],
    ]),
  };
  for (const [status, codes] of matrices.raydium) for (const code of codes) {
    await assert.rejects(client(async () => serverError(code, status)).raydiumQuote(buy), {code, message: code});
  }
  for (const [status, codes] of matrices.history) for (const code of codes) {
    await assert.rejects(client(async () => serverError(code, status)).history(historyRequest), {code, message: code});
  }
  await assert.rejects(client(async () => serverError('MARKET_UNAVAILABLE', 502)).raydiumQuote(buy),
    {code: 'STOCK_SERVICE_UNAVAILABLE'});
  await assert.rejects(client(async () => serverError('STOCK_HISTORY_TIMEOUT', 502)).history(historyRequest),
    {code: 'STOCK_SERVICE_UNAVAILABLE'});
  await assert.rejects(client(async () => response(raydiumQuoteFixture(), 201)).raydiumQuote(buy),
    {code: 'STOCK_SERVICE_UNAVAILABLE'});
  await assert.rejects(client(async () => response(stockHistoryFixture(), 201)).history(historyRequest),
    {code: 'STOCK_SERVICE_UNAVAILABLE'});
});

test('new endpoint body caps and JSON media checks fail before data can be published', async () => {
  let cancelled = false;
  const oversizedRaydium = new Response(new ReadableStream<Uint8Array>({cancel() {cancelled = true;}}),
    {headers: {'content-type': 'application/json', 'content-length': '65537'}});
  await assert.rejects(client(async () => oversizedRaydium).raydiumQuote(buy), {code: 'STOCK_RESPONSE_TOO_LARGE'});
  await tick(); assert.equal(cancelled, true);
  const oversizedHistory = new Response('{}', {headers: {'content-type': 'application/json', 'content-length': '1048577'}});
  await assert.rejects(client(async () => oversizedHistory).history(historyRequest), {code: 'STOCK_RESPONSE_TOO_LARGE'});
  await assert.rejects(client(async () => new Response('{}', {headers: {'content-type': 'text/plain'}})).history(historyRequest),
    {code: 'STOCK_RESPONSE_INVALID'});
});

test('endpoint deadlines abort once, do not retry, and cancel eventual late bodies', async () => {
  for (const kind of ['raydium', 'history'] as const) {
    const pending = deferred<Response>(); let calls = 0; let signal: AbortSignal | null | undefined;
    const api = client(async (_input, options) => {calls++; signal = options?.signal; return pending.promise;}, 10);
    const result = kind === 'raydium' ? api.raydiumQuote(buy) : api.history(historyRequest);
    await assert.rejects(result, {code: kind === 'raydium' ? 'MARKET_TIMEOUT' : 'STOCK_HISTORY_TIMEOUT'});
    assert.equal(calls, 1); assert.equal(signal?.aborted, true);
    let cancelled = false;
    pending.resolve(new Response(new ReadableStream({cancel() {cancelled = true;}})));
    await tick(); assert.equal(cancelled, true);
  }
});

test('caller cancellation aborts the new reads and settled listeners cannot trigger retries', async () => {
  for (const kind of ['raydium', 'history'] as const) {
    const abort = new AbortController(); let calls = 0; let cancelled = false;
    const body = new ReadableStream<Uint8Array>({start(controller) {controller.enqueue(new TextEncoder().encode('{'));},
      cancel() {cancelled = true;}});
    const api = client(async () => {calls++; return new Response(body, {headers: {'content-type': 'application/json'}});});
    const result = kind === 'raydium' ? api.raydiumQuote(buy, {signal: abort.signal}) :
      api.history(historyRequest, {signal: abort.signal});
    await tick(); abort.abort();
    await assert.rejects(result, {code: 'STOCK_CANCELLED'}); assert.equal(calls, 1); assert.equal(cancelled, true);
  }
});

test('reusable cancellation signals detach after success and strict-parse failure', async () => {
  for (const kind of ['raydium', 'history'] as const) {
    const cancellation = countingAbortSignal(); let valid = true;
    const api = client(async () => response(valid ? kind === 'raydium' ? raydiumQuoteFixture() : stockHistoryFixture() : {}));
    const read = () => kind === 'raydium' ? api.raydiumQuote(buy, {signal: cancellation.signal}) :
      api.history(historyRequest, {signal: cancellation.signal});
    await read(); assert.equal(cancellation.listeners.size, 0);
    valid = false; await assert.rejects(read()); assert.equal(cancellation.listeners.size, 0);
  }
});

test('request echoes and local freshness deadlines are enforced after strict parsing', async () => {
  const wrongQuote = raydiumQuoteFixture('sell');
  await assert.rejects(client(async () => response(wrongQuote)).raydiumQuote(buy), {code: 'STOCK_RESPONSE_INVALID'});
  const wrongHistory = stockHistoryFixture(); Object.assign(wrongHistory, {toUnixSeconds: '1789354800'});
  await assert.rejects(client(async () => response(wrongHistory)).history(historyRequest),
    {code: 'STOCK_HISTORY_RESPONSE_INVALID'});
  await assert.rejects(client(async () => response(raydiumQuoteFixture()), 1_000,
    () => Date.parse('2026-09-14T18:00:10.000Z')).raydiumQuote(buy), {code: 'MARKET_ESTIMATE_STALE'});
  await assert.rejects(client(async () => response(stockHistoryFixture()), 1_000,
    () => Date.parse('2026-09-14T18:00:16.000Z')).history(historyRequest), {code: 'STOCK_HISTORY_RESPONSE_INVALID'});
  const futureQuote = raydiumQuoteFixture();
  Object.assign(futureQuote, {requestedAt: '2026-09-14T18:01:03.000Z', receivedAt: '2026-09-14T18:01:04.000Z',
    refreshAfter: '2026-09-14T18:01:13.000Z'});
  await assert.rejects(client(async () => response(futureQuote)).raydiumQuote(buy), {code: 'STOCK_RESPONSE_INVALID'});
  const futureHistory = stockHistoryFixture();
  Object.assign(futureHistory.provenance, {requestedAt: '2026-09-14T18:01:03.000Z', observedAt: '2026-09-14T18:01:04.000Z',
    refreshAfter: '2026-09-14T18:01:19.000Z'});
  await assert.rejects(client(async () => response(futureHistory)).history(historyRequest), {code: 'STOCK_RESPONSE_INVALID'});
});
