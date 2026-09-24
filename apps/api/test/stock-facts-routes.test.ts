import assert from 'node:assert/strict';
import { it } from 'node:test';
import { buildApp } from '../src/app.js';
import { StockFactsError } from '../src/stock-facts.js';
import type { StockFactsReader } from '../src/stock-facts.js';

const common = {schemaVersion: 1, provider: 'tokens-xyz-v1', requestedAt: '2026-09-20T15:00:00.000Z',
  observedAt: '2026-09-20T15:00:00.000Z', refreshAfter: '2026-09-20T15:01:00.000Z', displayOnly: true,
  executionEnabled: false, eligibility: 'unverified'} as const;
const reader = (): StockFactsReader => ({
  cards: async ({query, limit = 10}) => ({...common, sourceUrl: 'https://api.tokens.xyz/v1/assets/search', query, limit,
    completeCatalog: false, results: []}),
  facts: async ({assetId}) => ({...common, sourceUrls: ['https://api.tokens.xyz/v1/assets/' + assetId], assetId, name: null,
    symbol: null, imageUrl: null, description: null, stock: null, sparkline: null, sparklineStatus: 'unavailable'}),
});
const cards = '/v1/markets/stocks/cards';
const facts = '/v1/markets/stocks/facts';

it('serves cards and facts as reading material with the capability flag and no money authority', async () => {
  const app = buildApp({logger: false, stockFacts: reader()});
  try {
    const page = await app.inject(cards + '?query=Apple&limit=3');
    assert.equal(page.statusCode, 200);
    assert.deepEqual(page.json(), {...common, sourceUrl: 'https://api.tokens.xyz/v1/assets/search', query: 'Apple', limit: 3,
      completeCatalog: false, results: []});
    assert.equal(page.headers['cache-control'], 'no-store');
    const detail = await app.inject(facts + '?assetId=apple');
    assert.equal(detail.statusCode, 200);
    assert.equal(detail.json().assetId, 'apple'); assert.equal(detail.json().sparklineStatus, 'unavailable');
    const config = (await app.inject('/v1/config')).json();
    assert.equal(config.stockFactsEnabled, true); assert.equal(config.stockDiscoveryEnabled, false);
    assert.equal(config.capabilities.swapsEnabled, false);
    for (const url of [cards, facts]) {
      assert.equal((await app.inject({method: 'POST', url, payload: {enable: true}})).statusCode, 503);
    }
  } finally { await app.close(); }
});
it('rejects bad inputs before the reader and reports a missing reader as unavailable', async () => {
  let calls = 0;
  const api = reader();
  const app = buildApp({logger: false, stockFacts: {
    cards: async input => { calls++; return api.cards(input); },
    facts: async input => { calls++; return api.facts(input); },
  }});
  try {
    for (const url of [cards, cards + '?query=', cards + '?query=%20Apple', cards + '?query=Apple&limit=0',
      cards + '?query=Apple&limit=21', cards + '?query=Apple&wallet=private-wallet', facts, facts + '?assetId=../apple',
      facts + '?assetId=Apple', facts + '?assetId=apple&recipient=private-wallet']) {
      const response = await app.inject(url);
      assert.equal(response.statusCode, 400, url);
      assert.ok(!response.body.includes('private-'));
    }
    assert.equal(calls, 0);
  } finally { await app.close(); }
  const disabled = buildApp({logger: false});
  try {
    assert.equal((await disabled.inject(cards + '?query=Apple')).statusCode, 503);
    assert.equal((await disabled.inject(facts + '?assetId=apple')).statusCode, 503);
    assert.equal((await disabled.inject('/v1/config')).json().stockFactsEnabled, false);
  } finally { await disabled.close(); }
});
it('maps reader failures to bounded statuses without provider detail', async () => {
  const failing = (code: ConstructorParameters<typeof StockFactsError>[0]): StockFactsReader => ({
    cards: async () => { throw new StockFactsError(code); }, facts: async () => { throw new StockFactsError(code); },
  });
  for (const [code, status] of [['STOCK_FACTS_RATE_LIMITED', 429], ['STOCK_FACTS_TIMEOUT', 504],
    ['STOCK_FACTS_PROVIDER_AUTH_FAILED', 503], ['STOCK_FACTS_PROVIDER_UNAVAILABLE', 502], ['STOCK_FACTS_RESPONSE_INVALID', 502]] as const) {
    const app = buildApp({logger: false, stockFacts: failing(code)});
    try {
      const response = await app.inject(facts + '?assetId=apple');
      assert.equal(response.statusCode, status, code);
      assert.equal(response.json().error.code, code);
    } finally { await app.close(); }
  }
  const crashing = buildApp({logger: false, stockFacts: {cards: async () => { throw new Error('provider secret'); },
    facts: async () => { throw new Error('provider secret'); }}});
  try {
    const response = await crashing.inject(cards + '?query=Apple');
    assert.equal(response.statusCode, 502); assert.ok(!response.body.includes('secret'));
  } finally { await crashing.close(); }
});
