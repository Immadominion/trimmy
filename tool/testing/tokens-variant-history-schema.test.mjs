import assert from 'node:assert/strict';
import test from 'node:test';
import { AAPLX_MINT, ASSET_ID, INTERVAL, inspectHistoryPayload, runTokensVariantHistorySchema } from './tokens-variant-history-schema.mjs';

const NOW = Date.UTC(2026, 8, 14, 18, 0, 0);
const TO = Math.floor(NOW / 1000), FROM = TO - 7 * 24 * 60 * 60;
const request = {assetId: ASSET_ID, mint: AAPLX_MINT, interval: INTERVAL, from: FROM, to: TO};
const bytes = value => Buffer.from(JSON.stringify(value));

test('schema observation retains structure but omits candle prices and volumes', () => {
  const payload = {...request, candles: [
    {t: FROM, o: 123.456789, h: 125.25, l: 121.5, c: 124.75, v: 987654.321},
    {t: FROM + 3600, o: 124.75, h: 126, l: 124, c: 125.5, v: null},
  ]};
  const result = inspectHistoryPayload(payload, request, bytes(payload));
  assert.deepEqual(result.candles.itemKinds, ['object']);
  assert.deepEqual(result.candles.distinctKeySets, ['c,h,l,o,t,v']);
  assert.deepEqual(result.candles.fields.find(field => field.name === 'v'),
    {name: 'v', presentCount: 2, types: ['null', 'number']});
  assert.deepEqual(result.candles.timeFields, [{field: 't', establishedUnit: 'unix_seconds',
    minimum: String(FROM), maximum: String(FROM + 3600), ordering: 'strictly_ascending', unique: true}]);
  const serialized = JSON.stringify(result);
  for (const privateValue of ['123.456789', '987654.321', '125.25']) assert.equal(serialized.includes(privateValue), false);
  assert.match(result.rawBodySha256, /^[a-f0-9]{64}$/u);
  assert.match(result.structuralSha256, /^[a-f0-9]{64}$/u);
});

test('milliseconds can be established only by the requested range', () => {
  const payload = {...request, candles: [{timestamp: FROM * 1000}, {timestamp: (FROM + 3600) * 1000}]};
  const result = inspectHistoryPayload(payload, request, bytes(payload));
  assert.equal(result.candles.timeFields[0].establishedUnit, 'unix_milliseconds');
  assert.equal(result.candles.timeFields[0].minimum, String(FROM * 1000));
});

test('unknown or mixed candle structures fail closed without revealing values', () => {
  for (const payload of [null, {candles: 'private'}, {candles: [{'bad-field': 1}]},
    {candles: [{t: FROM}, [FROM, 1, 2, 3, 4, 5]]}, {candles: Array(20_001).fill({t: FROM})}]) {
    assert.throws(() => inspectHistoryPayload(payload, request, bytes(payload)), {name: 'TokensHistorySchemaError'});
  }
});

test('one-read runner sends one exact GET and never emits the injected key or raw response', async () => {
  const secret = 'fixture-private-key';
  const payload = {...request, candles: [{t: FROM, o: 91.234567, h: 92, l: 90, c: 91, v: 12}]};
  let calls = 0;
  const report = await runTokensVariantHistorySchema({now: () => NOW, readApiKey: () => secret,
    fetchImpl: async (url, init) => {
      calls++;
      assert.equal(url.origin, 'https://api.tokens.xyz');
      assert.equal(url.pathname, '/v1/assets/apple/ohlcv');
      assert.deepEqual(Object.fromEntries(url.searchParams), {mint: AAPLX_MINT, interval: INTERVAL,
        from: String(FROM), to: String(TO)});
      assert.equal(init.method, 'GET'); assert.equal(init.redirect, 'error');
      assert.equal(init.headers['x-api-key'], secret);
      return new Response(JSON.stringify(payload), {status: 200, headers: {'content-type': 'application/json'}});
    }});
  assert.equal(calls, 1); assert.equal(report.providerCalls, 1); assert.equal(report.passed, true);
  assert.equal(report.financialMutation, false); assert.equal(report.transactionBroadcast, false);
  const serialized = JSON.stringify(report);
  assert.equal(serialized.includes(secret), false); assert.equal(serialized.includes('91.234567'), false);
});

test('runner records only a safe code for provider or transport failures', async () => {
  const auth = await runTokensVariantHistorySchema({now: () => NOW, readApiKey: () => 'fixture-key',
    fetchImpl: async () => new Response('{"error":{"message":"private diagnostic"}}',
      {status: 401, headers: {'content-type': 'application/json'}})});
  assert.equal(auth.passed, false); assert.equal(auth.errorCode, 'PROVIDER_AUTH_FAILED');
  assert.equal(JSON.stringify(auth).includes('private diagnostic'), false);
  const failed = await runTokensVariantHistorySchema({now: () => NOW, readApiKey: () => 'fixture-key',
    fetchImpl: async () => { throw new Error('private transport diagnostic'); }});
  assert.equal(failed.errorCode, 'READ_FAILED');
  assert.equal(JSON.stringify(failed).includes('private transport diagnostic'), false);
});

test('deadline wins when fetch or body cancellation ignores abort', async () => {
  const start = Date.now();
  const ignoredFetch = await runTokensVariantHistorySchema({now: () => NOW, timeoutMs: 5,
    readApiKey: () => 'fixture-key', fetchImpl: () => new Promise(() => {})});
  assert.equal(ignoredFetch.errorCode, 'READ_TIMEOUT');
  const stream = new ReadableStream({start(controller) {
    controller.enqueue(new TextEncoder().encode('{'));
  }, cancel: () => new Promise(() => {})});
  const ignoredCancel = await runTokensVariantHistorySchema({now: () => NOW, timeoutMs: 5,
    readApiKey: () => 'fixture-key', fetchImpl: async () => new Response(stream,
      {headers: {'content-type': 'application/json'}})});
  assert.equal(ignoredCancel.errorCode, 'READ_TIMEOUT');
  assert.ok(Date.now() - start < 500);
});
