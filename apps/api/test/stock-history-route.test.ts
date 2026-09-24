import assert from 'node:assert/strict';
import Fastify from 'fastify';
import {test} from 'node:test';
import {registerStockHistoryRoute, STOCK_HISTORY_ROUTE} from '../src/stock-history-route.js';
import {STOCK_HISTORY_ASSET, StockHistoryError} from '../src/stock-history.js';
import type {StockHistory, StockHistoryInput, StockHistoryPage} from '../src/stock-history.js';

const now = Math.floor(Date.now() / 1000);
const input: StockHistoryInput = {assetId: STOCK_HISTORY_ASSET.assetId, variantMint: STOCK_HISTORY_ASSET.variantMint,
  interval: '1H', fromUnixSeconds: String(now - 86_400), toUnixSeconds: String(now - 60)};
const url = (value: StockHistoryInput = input) =>
  `${STOCK_HISTORY_ROUTE}?${new URLSearchParams(Object.entries(value)).toString()}`;
const page = Object.freeze({schemaVersion: 1, provider: 'tokens-xyz-v1',
  providerContract: 'observed_not_execution_qualified', historyKind: 'solana_mint_variant',
  canonicalEquityHistory: false, ...input, candles: [], dataStatus: 'empty_provider_cache_or_no_trades',
  numericEncoding: 'exact_provider_json_number_lexemes', priceUnit: 'provider_not_declared',
  volumeUnit: 'provider_not_declared', provenance: {sourceUrl: 'https://api.tokens.xyz/v1/assets/apple/ohlcv',
    requestedAt: new Date().toISOString(), observedAt: new Date().toISOString(), providerAsOf: null,
    providerFreshness: 'not_reported', providerCandleSource: 'not_exposed', refreshAfter: new Date().toISOString(),
    cachedUpstreamData: true}, executionEnabled: false, eligibility: 'unverified'}) as StockHistoryPage;

async function app(history?: StockHistory) {
  const instance = Fastify({ajv: {customOptions: {coerceTypes: false, removeAdditional: false, useDefaults: false}}});
  registerStockHistoryRoute(instance, history); await instance.ready(); return instance;
}

test('public route returns the strict read-only variant page and exact input', async () => {
  let received: StockHistoryInput | undefined;
  const instance = await app({history: async value => { received = value; return page; }});
  try {
    const response = await instance.inject(url());
    assert.equal(response.statusCode, 200, response.body); assert.deepEqual({...received}, input);
    assert.equal(response.json().canonicalEquityHistory, false); assert.equal(response.json().executionEnabled, false);
    assert.equal(response.headers['cache-control'], 'no-store');
  } finally { await instance.close(); }
});

test('disabled and provider failures map to stable statuses without leaking diagnostics', async () => {
  const disabled = await app();
  try {
    const response = await disabled.inject(url()); assert.equal(response.statusCode, 503);
    assert.equal(response.json().error.code, 'STOCK_HISTORY_UNAVAILABLE');
  } finally { await disabled.close(); }
  for (const [code, status] of [
    ['STOCK_HISTORY_INPUT_INVALID', 400], ['STOCK_HISTORY_RATE_LIMITED', 429],
    ['STOCK_HISTORY_TIMEOUT', 504], ['STOCK_HISTORY_PROVIDER_AUTH_FAILED', 503],
    ['STOCK_HISTORY_RESPONSE_INVALID', 502], ['STOCK_HISTORY_PROVIDER_UNAVAILABLE', 502],
  ] as const) {
    const error = new StockHistoryError(code); error.message = 'private provider diagnostic';
    const instance = await app({history: async () => { throw error; }});
    try {
      const response = await instance.inject(url()); assert.equal(response.statusCode, status);
      assert.equal(response.json().error.code, code); assert.equal(response.body.includes('private provider diagnostic'), false);
    } finally { await instance.close(); }
  }
});

test('schema and semantic rejection happen before any adapter read', async () => {
  let calls = 0; const instance = await app({history: async () => { calls++; return page; }});
  try {
    for (const target of [STOCK_HISTORY_ROUTE, `${url()}&secret=private`,
      url({...input, interval: '1m' as '1H'}), url({...input, toUnixSeconds: String(now + 120)}),
      url({...input, fromUnixSeconds: input.toUnixSeconds})]) {
      assert.equal((await instance.inject(target)).statusCode, 400);
    }
    assert.equal(calls, 0);
    assert.equal((await instance.inject({method: 'HEAD', url: url()})).statusCode, 404);
    assert.equal((await instance.inject({method: 'POST', url: STOCK_HISTORY_ROUTE, payload: {}})).statusCode, 404);
  } finally { await instance.close(); }
});
