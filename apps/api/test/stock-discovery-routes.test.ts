import assert from 'node:assert/strict';
import { it } from 'node:test';
import { buildApp } from '../src/app.js';
import { StockDiscoveryError } from '../src/stock-discovery.js';
import type { StockDiscovery } from '../src/stock-discovery.js';

const common = {schemaVersion: 1, provider: 'tokens-xyz-v1', observedAt: '2026-09-14T18:00:00.000Z',
  requestedAt: '2026-09-14T18:00:00.000Z', sourceUrl: 'https://api.tokens.xyz/v1/assets/search', providerFreshness: 'not_verified',
  providerAsOf: null, refreshAfter: '2026-09-14T18:01:00.000Z', executionEnabled: false,
  eligibility: 'unverified', mintVerification: 'not_checked'} as const;
const adapter = (): StockDiscovery => ({
  search: async ({query, limit = 10}) => ({...common, query, limit, completeCatalog: false, results: []}),
  variants: async ({assetId}) => ({...common, assetId, variants: []}),
});
const search = '/v1/markets/stocks/search';
const variants = '/v1/markets/stocks/variants';

it('serves discovery separately from an approved asset catalog and execution', async () => {
  const app = buildApp({logger: false, stockDiscovery: adapter()});
  try {
    const response = await app.inject(search + '?query=Apple&limit=2');
    assert.equal(response.statusCode, 200);
    assert.deepEqual(response.json(), {...common, query: 'Apple', limit: 2, completeCatalog: false, results: []});
    assert.equal(response.headers['cache-control'], 'no-store');
    const detail = await app.inject(variants + '?assetId=apple');
    assert.equal(detail.statusCode, 200);
    assert.deepEqual(detail.json(), {...common, assetId: 'apple', variants: []});
    const config = (await app.inject('/v1/config')).json();
    assert.equal(config.stockDiscoveryEnabled, true);
    assert.equal(config.capabilities.liveWalletsEnabled, false);
    assert.equal(config.capabilities.swapsEnabled, false);
    assert.deepEqual((await app.inject('/v1/catalog')).json().assets, []);
    for (const url of [search, variants, '/v1/execute', '/v1/gifts']) {
      assert.equal((await app.inject({method: 'POST', url, payload: {enable: true}})).statusCode, 503);
    }
  } finally { await app.close(); }
});

it('rejects extra fields, duplicate parameters, limits and wallet inputs before adapter access', async () => {
  let calls = 0;
  const api = adapter();
  const app = buildApp({logger: false, stockDiscovery: {
    search: async input => { calls++; return api.search(input); },
    variants: async input => { calls++; return api.variants(input); },
  }});
  try {
    for (const url of [search, search + '?query=', search + '?query=Apple&query=Tesla',
      search + '?query=%20Apple', search + '?query=Apple%0A', search + '?query=Ap%00ple',
      search + '?query=Apple%E2%80%A8',
      ...['0', '21', '01', '-1', '1e1', '1%0A'].map(limit => search + '?query=Apple&limit=' + limit),
      search + '?query=Apple&taker=private-wallet', search + '?query=Apple&apiKey=private-key',
      variants, variants + '?assetId=apple&assetId=tesla', variants + '?assetId=../apple',
      variants + '?assetId=apple&recipient=private-wallet']) {
      const response = await app.inject(url);
      assert.equal(response.statusCode, 400, url);
      assert.ok(!response.body.includes('private-'));
    }
    assert.equal(calls, 0);
  } finally { await app.close(); }
});

it('does not spend upstream quota on HEAD or denied browser requests', async () => {
  let calls = 0;
  const api = adapter();
  const app = buildApp({logger: false, browserOrigins: ['https://trimmy.example'], stockDiscovery: {
    search: async input => { calls++; return api.search(input); }, variants: api.variants,
  }});
  try {
    const url = search + '?query=Apple';
    assert.equal((await app.inject({method: 'HEAD', url})).statusCode, 404);
    assert.equal((await app.inject({url, headers: {origin: 'https://unlisted.example'}})).statusCode, 403);
    for (const path of [url, variants + '?assetId=apple']) {
      const headers = {origin: 'https://trimmy.example', 'access-control-request-method': 'GET'};
      assert.equal((await app.inject({method: 'OPTIONS', url: path, headers})).statusCode, 204);
      assert.equal((await app.inject({method: 'OPTIONS', url: path,
        headers: {...headers, 'access-control-request-method': 'POST'}})).statusCode, 403);
    }
    assert.equal(calls, 0);
    const allowed = await app.inject({url, headers: {origin: 'https://trimmy.example'}});
    assert.equal(allowed.statusCode, 200);
    assert.equal(allowed.headers['access-control-allow-origin'], 'https://trimmy.example');
    assert.equal(calls, 1);
  } finally { await app.close(); }
});

it('reports disabled discovery and sanitizes provider failures with their correct status', async () => {
  const disabled = buildApp({logger: false});
  try {
    assert.equal((await disabled.inject('/v1/config')).json().stockDiscoveryEnabled, false);
    for (const url of [search + '?query=Apple', variants + '?assetId=apple']) {
      const response = await disabled.inject(url);
      assert.equal(response.statusCode, 503);
      assert.equal(response.json().error.code, 'STOCK_DISCOVERY_UNAVAILABLE');
    }
  } finally { await disabled.close(); }
  const cases = [
    [new StockDiscoveryError('STOCK_PROVIDER_AUTH_FAILED'), 503],
    [new StockDiscoveryError('STOCK_RATE_LIMITED'), 429],
    [new StockDiscoveryError('STOCK_TIMEOUT'), 504],
    [new StockDiscoveryError('STOCK_RESPONSE_INVALID'), 502],
    [new Error('secret-provider-body'), 502],
  ] as const;
  for (const [error, status] of cases) {
    const app = buildApp({logger: false, stockDiscovery: {
      search: async () => { throw error; }, variants: async () => { throw error; },
    }});
    try {
      const response = await app.inject(search + '?query=Apple');
      assert.equal(response.statusCode, status);
      assert.ok(!response.body.includes('secret-provider-body'));
    } finally { await app.close(); }
  }
});
