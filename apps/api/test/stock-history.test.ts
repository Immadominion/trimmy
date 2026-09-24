import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import {test} from 'node:test';
import {
  readStockHistory,
  STOCK_HISTORY_ASSET,
  StockHistoryError,
  TokensStockHistory,
  parseTokensVariantHistory,
  validateStockHistoryInput,
} from '../src/stock-history.js';
import type {StockHistoryInput} from '../src/stock-history.js';

const NOW = Date.UTC(2026, 8, 14, 20, 0, 0);
const FROM = Math.floor(Date.UTC(2026, 8, 7, 18, 0, 0) / 1000);
const TO = FROM + 7 * 86_400;
const input: StockHistoryInput = {assetId: STOCK_HISTORY_ASSET.assetId,
  variantMint: STOCK_HISTORY_ASSET.variantMint, interval: '1H',
  fromUnixSeconds: String(FROM), toUnixSeconds: String(TO)};
const payload = (candles = '[{"time":1788804000,"open":101.2300,"high":105.5,"low":99.900,"close":104.250,"volume":1.2300e3},{"time":1788811200,"open":104.25,"high":106,"low":103,"close":105,"volume":0}]') =>
  `{"assetId":"apple","mint":"${STOCK_HISTORY_ASSET.variantMint}","interval":"1H","from":${FROM},"to":${TO},"candles":${candles}}`;
const validated = () => validateStockHistoryInput(input, Math.floor(NOW / 1000));
const response = (body = payload(), status = 200, headers: Record<string, string> = {}) =>
  new Response(body, {status, headers: {'content-type': 'application/json', ...headers}});

test('sanitized one-request evidence pins the strict provider shape without retaining values', async () => {
  const path = new URL('./fixtures/tokens-variant-history-schema.json', import.meta.url);
  const source = await readFile(path, 'utf8'); const evidence = JSON.parse(source);
  assert.equal(evidence.passed, true); assert.equal(evidence.httpStatus, 200); assert.equal(evidence.providerCalls, 1);
  assert.equal(evidence.credentialSource.valueStored, false); assert.equal(evidence.financialMutation, false);
  assert.deepEqual(evidence.observation.topLevel.map((field: {name: string}) => field.name),
    ['assetId', 'candles', 'from', 'interval', 'mint', 'to']);
  assert.deepEqual(evidence.observation.candles.distinctKeySets, ['close,high,low,open,time,volume']);
  assert.deepEqual(evidence.observation.candles.timeFields.map((field: {field: string; establishedUnit: string}) =>
    [field.field, field.establishedUnit]), [['time', 'unix_seconds']]);
  assert.equal(/tok_[A-Za-z0-9]+/u.test(source), false);
});

test('strict parser preserves provider decimal lexemes and labels mint history honestly', () => {
  const page = parseTokensVariantHistory(payload(), validated(), {
    sourceUrl: 'https://api.tokens.xyz/v1/assets/apple/ohlcv?public=request', requestedAt: NOW, observedAt: NOW + 20,
  });
  assert.deepEqual(page.candles[0], {startUnixSeconds: '1788804000', openRaw: '101.2300', highRaw: '105.5',
    lowRaw: '99.900', closeRaw: '104.250', volumeRaw: '1.2300e3'});
  assert.equal(page.historyKind, 'solana_mint_variant'); assert.equal(page.canonicalEquityHistory, false);
  assert.equal(page.providerContract, 'observed_not_execution_qualified');
  assert.equal(page.numericEncoding, 'exact_provider_json_number_lexemes');
  assert.equal(page.priceUnit, 'provider_not_declared'); assert.equal(page.volumeUnit, 'provider_not_declared');
  assert.equal(page.provenance.providerAsOf, null); assert.equal(page.provenance.providerFreshness, 'not_reported');
  assert.equal(page.provenance.providerCandleSource, 'not_exposed'); assert.equal(page.executionEnabled, false);
  assert.throws(() => { (page.candles as unknown[]).push({}); }, TypeError);
});

test('empty cached response remains explicit instead of becoming a fabricated series', () => {
  const page = parseTokensVariantHistory(payload('[]'), validated(), {
    sourceUrl: 'https://api.tokens.xyz/v1/assets/apple/ohlcv', requestedAt: NOW, observedAt: NOW,
  });
  assert.deepEqual(page.candles, []); assert.equal(page.dataStatus, 'empty_provider_cache_or_no_trades');
});

test('input binds one observed asset/mint, bounded past windows, and low-frequency intervals', () => {
  assert.deepEqual(validateStockHistoryInput(input, Math.floor(NOW / 1000)), {...input, from: FROM, to: TO});
  const changes: Partial<StockHistoryInput>[] = [
    {assetId: 'tesla' as 'apple'}, {variantMint: 'So11111111111111111111111111111111111111112' as typeof input.variantMint},
    {interval: '1m' as '1H'}, {fromUnixSeconds: `0${FROM}`}, {fromUnixSeconds: String(TO)},
    {toUnixSeconds: String(FROM + 32 * 86_400)}, {toUnixSeconds: String(Math.floor(NOW / 1000) + 61)},
  ];
  for (const change of changes) assert.throws(() => validateStockHistoryInput({...input, ...change}, Math.floor(NOW / 1000)),
    {code: 'STOCK_HISTORY_INPUT_INVALID'});
  assert.throws(() => validateStockHistoryInput({...input, unexpected: 'x'} as StockHistoryInput, Math.floor(NOW / 1000)),
    {code: 'STOCK_HISTORY_INPUT_INVALID'});
});

test('provider response identity, complete shape, timestamps and candle invariants fail closed', () => {
  const substitutions = [
    payload().replace('"assetId":"apple"', '"assetId":"tesla"'),
    payload().replace('"interval":"1H"', '"interval":"4H"'),
    payload().replace(`"from":${FROM}`, `"from":${FROM + 1}`),
    payload().replace('"candles":', '"extra":true,"candles":'),
    payload().replace('"volume":1.2300e3', '"note":"private","volume":1.2300e3'),
    payload('[{"time":1788804001,"open":1,"high":2,"low":1,"close":1,"volume":0}]'),
    payload('[{"time":1788811200,"open":1,"high":2,"low":1,"close":1,"volume":0},{"time":1788804000,"open":1,"high":2,"low":1,"close":1,"volume":0}]'),
    payload('[{"time":1788804000,"open":5,"high":4,"low":1,"close":2,"volume":0}]'),
    payload('[{"time":1788804000,"open":2,"high":4,"low":3,"close":2,"volume":0}]'),
    payload('[{"time":1788804000,"open":0,"high":1,"low":0,"close":1,"volume":0}]'),
    payload('[{"time":1788804000,"open":1,"high":1,"low":1,"close":1,"volume":-1}]'),
    payload('[{"time":1788804000,"open":1e101,"high":1e101,"low":1,"close":1,"volume":0}]'),
    payload().replace('"assetId":"apple"', '"assetId":"apple","assetId":"apple"'),
    payload() + '\u00a0',
  ];
  for (const body of substitutions) assert.throws(() => parseTokensVariantHistory(body, validated(), {
    sourceUrl: 'https://api.tokens.xyz', requestedAt: NOW, observedAt: NOW,
  }), {code: 'STOCK_HISTORY_RESPONSE_INVALID'});
});

test('reader sends one exact GET and projects no credential or provider extras', async () => {
  const secret = 'fixture-history-secret'; let calls = 0;
  const reader = new TokensStockHistory({apiKey: secret, now: () => NOW, fetch: async (url, init) => {
    calls++;
    const parsedUrl = new URL(typeof url === 'string' ? url : url instanceof URL ? url.href : url.url);
    assert.equal(parsedUrl.origin + parsedUrl.pathname, 'https://api.tokens.xyz/v1/assets/apple/ohlcv');
    assert.deepEqual(Object.fromEntries(parsedUrl.searchParams), {mint: STOCK_HISTORY_ASSET.variantMint,
      interval: '1H', from: String(FROM), to: String(TO)});
    assert.equal(init?.method, 'GET'); assert.equal(init?.redirect, 'error');
    assert.equal((init?.headers as Record<string, string>)['x-api-key'], secret);
    return response(payload().replace('"candles":', '"candles":'));
  }});
  const page = await reader.history(input);
  assert.equal(calls, 1); assert.equal(page.candles.length, 2);
  assert.equal(inspect(page).includes(secret), false);
});

test('cache and singleflight share sanitized pages while failures consume bounded budget', async () => {
  let calls = 0; let complete: ((response: Response) => void) | undefined;
  const pending = new Promise<Response>(resolve => { complete = resolve; });
  const reader = new TokensStockHistory({apiKey: 'fixture-key', now: () => NOW, fetch: async () => { calls++; return pending; }});
  const first = reader.history(input), second = reader.history(input);
  assert.equal(calls, 1); complete?.(response());
  const [a, b] = await Promise.all([first, second]); assert.equal(a, b);
  assert.equal(await reader.history(input), a); assert.equal(calls, 1);

  let clock = NOW, attempts = 0;
  const bounded = new TokensStockHistory({apiKey: 'fixture-key', now: () => clock,
    protection: {cacheTtlMs: 1, perKeyLimit: 1}, fetch: async () => { attempts++; return response(); }});
  await bounded.history(input); clock += 2;
  await assert.rejects(bounded.history(input), {code: 'STOCK_HISTORY_RATE_LIMITED'});
  assert.equal(attempts, 1);

  let failures = 0;
  const failing = new TokensStockHistory({apiKey: 'fixture-key', now: () => NOW,
    protection: {perKeyLimit: 1}, fetch: async () => { failures++; throw new Error('private upstream detail'); }});
  await assert.rejects(failing.history(input), {code: 'STOCK_HISTORY_PROVIDER_UNAVAILABLE'});
  await assert.rejects(failing.history(input), {code: 'STOCK_HISTORY_RATE_LIMITED'});
  assert.equal(failures, 1);
});

test('transport bounds, status mapping and deadlines expose reconstructed errors only', async () => {
  const cases = [
    [401, 'STOCK_HISTORY_PROVIDER_AUTH_FAILED'], [403, 'STOCK_HISTORY_PROVIDER_AUTH_FAILED'],
    [429, 'STOCK_HISTORY_RATE_LIMITED'], [500, 'STOCK_HISTORY_PROVIDER_UNAVAILABLE'],
  ] as const;
  for (const [status, code] of cases) {
    const reader = new TokensStockHistory({apiKey: 'fixture-key', now: () => NOW,
      fetch: async () => response('{"private":"diagnostic"}', status)});
    await assert.rejects(reader.history(input), (error: unknown) => {
      assert.ok(error instanceof StockHistoryError); assert.equal(error.code, code);
      assert.equal(inspect(error).includes('diagnostic'), false); return true;
    });
  }
  for (const make of [
    () => new Response(payload(), {headers: {'content-type': 'text/html'}}),
    () => response(payload(), 200, {'content-length': '1048577'}),
    () => response('{bad json'),
  ]) await assert.rejects(new TokensStockHistory({apiKey: 'fixture-key', now: () => NOW,
    fetch: async () => make()}).history(input), {code: 'STOCK_HISTORY_RESPONSE_INVALID'});

  await assert.rejects(new TokensStockHistory({apiKey: 'fixture-key', now: () => NOW, timeoutMs: 5,
    fetch: () => new Promise(() => {})}).history(input), {code: 'STOCK_HISTORY_TIMEOUT'});
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({start(controller) {
    controller.enqueue(new TextEncoder().encode('{'));
  }, cancel() { cancelled = true; }});
  await assert.rejects(new TokensStockHistory({apiKey: 'fixture-key', now: () => NOW, timeoutMs: 5,
    fetch: async () => new Response(stream, {headers: {'content-type': 'application/json'}})}).history(input),
  {code: 'STOCK_HISTORY_TIMEOUT'});
  assert.equal(cancelled, true);
});

test('provider 429 starts a local cooldown before another window can reach upstream', async () => {
  let clock = NOW, calls = 0;
  const reader = new TokensStockHistory({apiKey: 'fixture-key', now: () => clock, fetch: async () => {
    calls++; return response('{"error":{"message":"private quota detail"}}', 429);
  }});
  await assert.rejects(reader.history(input), {code: 'STOCK_HISTORY_RATE_LIMITED'});
  const adjacent = {...input, fromUnixSeconds: String(FROM + 3_600)};
  await assert.rejects(reader.history(adjacent), {code: 'STOCK_HISTORY_RATE_LIMITED'});
  assert.equal(calls, 1);
  clock += 60_000;
  await assert.rejects(reader.history(adjacent), {code: 'STOCK_HISTORY_RATE_LIMITED'});
  assert.equal(calls, 2);
});

test('runtime is disabled by default and never accepts partial or malformed provider configuration', () => {
  for (const env of [{}, {TRIMMY_STOCK_HISTORY: ''}, {TRIMMY_STOCK_HISTORY: 'disabled'}]) {
    assert.equal(readStockHistory(env), undefined);
  }
  for (const env of [{TRIMMY_STOCK_HISTORY: 'tokens_xyz'},
    {TRIMMY_STOCK_HISTORY: 'other', TOKENS_API_KEY: 'fixture-key'}]) {
    assert.throws(() => readStockHistory(env), {code: 'STOCK_HISTORY_UNAVAILABLE'});
  }
  assert.ok(readStockHistory({TRIMMY_STOCK_HISTORY: 'tokens_xyz', TOKENS_API_KEY: 'fixture-key'}));
});
