import assert from 'node:assert/strict';
import { it } from 'node:test';
import { readStockDiscovery, StockDiscoveryError, TokensStockDiscovery } from '../src/stock-discovery.js';
import type { StockSearchInput, StockVariantsInput, TokensStockDiscoveryOptions } from '../src/stock-discovery.js';

const now = Date.parse('2026-09-14T16:00:00.000Z');
// Schema fixtures only: these public mints do not represent the invented company/issuers.
const mintA = 'So11111111111111111111111111111111111111112';
const mintB = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const mintC = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU';
const input = {query: 'Example Company', limit: 5};
const codeIs = (code: string) => (error: unknown) => error instanceof StockDiscoveryError && error.code === code;
function market(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {price: 101.25, liquidity: 8000, volume24hUSD: 1000, decimals: 9,
    source: 'clickhouse_trades', metricsSource: 'clickhouse_trades', asOf: 1789380000,
    lastFetchedAt: 1789380050000, lastTradeAt: 1789379999, ...overrides};
}
function variant(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {variantId: 'fixture-issuer-a', mint: mintA, kind: 'tokenized_equity', issuer: 'Fixture Issuer A',
    label: 'Fixture A', name: 'Example Company A', symbol: 'EX-A', stockVariantTier: 'cash_redeemable',
    advisory: null, market: market(), ...overrides};
}
function asset(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  const a = variant();
  const b = variant({variantId: 'fixture-issuer-b', mint: mintB, issuer: 'Fixture Issuer B', symbol: 'EX-B',
    label: 'Fixture B', market: market({price: 98, liquidity: 500, decimals: 6})});
  return {assetId: 'example-company', name: 'Example Company', symbol: 'EX', category: 'equity',
    primaryVariant: a, variants: [a, b], advisories: [], ...overrides};
}
function search(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {query: input.query, category: 'equity', primaryVariantStrategy: 'liquidity', results: [asset()], ...overrides};
}
function client(payload: unknown = search(), options: Partial<TokensStockDiscoveryOptions> = {}) {
  return new TokensStockDiscovery({apiKey: 'server-test-key-not-live', now: () => now,
    fetch: async () => Response.json(payload), ...options});
}

it('uses the fixed keyed GET, binds search, and preserves separate issuer variants without financial approval', async () => {
  const payload = search();
  const api = client(payload, {fetch: async (url, options) => {
    const parsed = new URL(String(url));
    assert.equal(parsed.origin + parsed.pathname, 'https://api.tokens.xyz/v1/assets/search');
    assert.deepEqual(Object.fromEntries(parsed.searchParams), {q: input.query, category: 'equity', variants: 'all',
      primaryVariantStrategy: 'liquidity', limit: '5'});
    assert.equal(options?.method, 'GET'); assert.equal(options.redirect, 'error');
    assert.equal(new Headers(options.headers).get('x-api-key'), 'server-test-key-not-live');
    assert.equal(options.body, undefined);
    return Response.json(payload);
  }});
  const result = await api.search(input);
  assert.equal(result.executionEnabled, false); assert.equal(result.eligibility, 'unverified');
  assert.equal(result.mintVerification, 'not_checked'); assert.equal(result.completeCatalog, false);
  assert.equal(result.providerAsOf, null); assert.equal(result.providerFreshness, 'not_verified');
  assert.equal(result.observedAt, '2026-09-14T16:00:00.000Z'); assert.equal(result.refreshAfter, '2026-09-14T16:01:00.000Z');
  assert.deepEqual(result.results[0]?.variants.map(row => [row.mint, row.issuer, row.market?.priceUsd]),
    [[mintA, 'Fixture Issuer A', 101.25], [mintB, 'Fixture Issuer B', 98]]);
  assert.equal(result.results[0]?.providerPrimaryVariantMint, mintA);
  assert.equal(JSON.stringify(result).includes('server-test-key'), false);
  assert.ok(Object.isFrozen(result.results[0]?.variants[0]?.market?.providerTimestamps));
  assert.ok(Object.isFrozen(result) && Object.isFrozen(result.results) && Object.isFrozen(result.results[0]?.variants));
});
it('direct variant lookup preserves a blocked mint and its warning, with an exact asset binding', async () => {
  const blocked = variant({advisory: {status: 'blocked', reason: 'Fixture issuer incident', url: 'https://untrusted.example', since: now - 1000}});
  const api = client({assetId: 'example-company', sortBy: 'liquidity', variants: [blocked]}, {fetch: async (url) => {
    const parsed = new URL(String(url));
    assert.equal(parsed.origin + parsed.pathname, 'https://api.tokens.xyz/v1/assets/example-company/variants');
    assert.deepEqual(Object.fromEntries(parsed.searchParams), {variantsMode: 'all', sortBy: 'liquidity'});
    return Response.json({assetId: 'example-company', sortBy: 'liquidity', variants: [blocked]});
  }});
  const result = await api.variants({assetId: 'example-company'});
  assert.equal(result.variants[0]?.advisory?.status, 'blocked');
  assert.equal(result.variants[0]?.advisory?.since, '2026-09-14T15:59:59.000Z');
  assert.equal(JSON.stringify(result).includes('https://untrusted.example'), false);
  await assert.rejects(client({assetId: 'other-company', sortBy: 'liquidity', variants: []}).variants({assetId: 'example-company'}), codeIs('STOCK_RESPONSE_INVALID'));
});
it('keeps flagged siblings omitted from search variants and degrades new advisory statuses to a warning', async () => {
  const result = await client(search({results: [asset({advisories: [{mint: mintC, variantId: 'hidden-variant',
    status: 'future_status', reason: 'Provider caution', since: now}]})]})).search(input);
  assert.equal(result.results[0]?.variants.length, 2);
  assert.equal(result.results[0]?.advisories[0]?.status, 'unknown');
  assert.equal(result.results[0]?.advisories[0]?.providerStatus, 'future_status');
});
it('does not invent issuers, prices, source dates or redemption rights for missing metadata', async () => {
  const row = variant({issuer: undefined, stockVariantTier: undefined, market: market({price: null, liquidity: 0,
    asOf: undefined, lastFetchedAt: null, lastTradeAt: undefined})});
  const result = await client(search({results: [asset({primaryVariant: row, variants: [row]})]})).search(input);
  const v = result.results[0]?.variants[0];
  assert.equal(v?.issuer, null); assert.equal(v?.providerRedemptionTier, null);
  assert.equal(v?.market?.priceUsd, null); assert.equal(v?.market?.liquidityUsd, 0);
  assert.deepEqual(v?.market?.providerTimestamps, {asOf: null, lastFetchedAt: null, lastTradeAt: null, unit: 'not_declared'});
  const withTimestamp = (await client().search(input)).results[0]?.variants[0]?.market?.providerTimestamps;
  assert.equal(withTimestamp?.asOf, 1789380000); assert.equal(withTimestamp?.lastFetchedAt, 1789380050000);
  assert.equal(withTimestamp?.unit, 'not_declared');
});
it('validates query, limits and canonical IDs before making a network request', async () => {
  let calls = 0; const api = client(undefined, {fetch: async () => { calls++; return Response.json(search()); }});
  for (const value of [{query: ''}, {query: ' foo'}, {query: 'foo\n'}, {query: 'x'.repeat(81)}, {query: 'foo', limit: 0},
    {query: 'foo', limit: 21}, {query: 'foo', limit: 1.5}, {query: 'foo', wallet: mintA}]) {
    await assert.rejects(api.search(value as StockSearchInput), codeIs('STOCK_INPUT_INVALID'));
  }
  for (const value of [{assetId: '../users'}, {assetId: 'tesla?mint=x'}, {assetId: 'tesla\n'}, {assetId: 'TESLA'},
    {assetId: 'tesla', baseUrl: 'https://evil.example'}]) {
    await assert.rejects(api.variants(value as StockVariantsInput), codeIs('STOCK_INPUT_INVALID'));
  }
  assert.equal(calls, 0);
});
it('rejects changed search identity/category/strategy, duplicated assets and undeclared variant truncation', async () => {
  for (const payload of [search({query: 'another-query'}), search({category: 'crypto'}), search({primaryVariantStrategy: 'execution_quality'}),
    search({results: [asset(), asset()]}), search({results: [asset({variants: undefined})]}),
    search({results: [asset({category: 'crypto'})]}), search({results: Array.from({length: 6}, () => asset())})]) {
    await assert.rejects(client(payload).search(input), codeIs('STOCK_RESPONSE_INVALID'));
  }
});
it('rejects duplicate or wrong-length mints, changed chain, inconsistent primary and erased warnings', async () => {
  const flag = {status: 'compromised', reason: 'Fixture issue', since: now};
  for (const row of [asset({variants: [variant(), variant()]}), asset({primaryVariant: variant({mint: mintC})}),
    asset({primaryVariant: null, variants: [variant({mint: '1'.repeat(33)})]}),
    asset({primaryVariant: null, variants: [variant({chain: 'ethereum'})]}),
    asset({primaryVariant: null, variants: [variant({advisory: undefined})]}),
    asset({primaryVariant: null, variants: [variant({advisory: flag})], advisories: []}),
    asset({advisories: [{mint: mintA, variantId: 'fixture-issuer-a', ...flag}]})]) {
    await assert.rejects(client(search({results: [row]})).search(input), codeIs('STOCK_RESPONSE_INVALID'));
  }
});
it('rejects invalid market quantities while allowing an explicitly missing market', async () => {
  for (const delta of [{price: -1}, {liquidity: 1e30}, {volume24hUSD: '100'}, {decimals: 1.5}, {decimals: 256},
    {asOf: -1}, {lastFetchedAt: 1.5}, {source: 'source\n'}]) {
    const row = variant({market: market(delta)});
    await assert.rejects(client(search({results: [asset({primaryVariant: row, variants: [row]})]})).search(input), codeIs('STOCK_RESPONSE_INVALID'));
  }
  const row = variant({market: null});
  assert.equal((await client(search({results: [asset({primaryVariant: row, variants: [row]})]})).search(input)).results[0]?.variants[0]?.market, null);
});
it('never falls back to keyless or leaks provider diagnostics on auth/scope/service failures', async () => {
  for (const status of [401, 403, 500]) {
    let calls = 0;
    const api = client(undefined, {fetch: async (_url, options) => {
      calls++; assert.equal(new Headers(options?.headers).get('x-api-key'), 'server-test-key-not-live');
      return Response.json({error: {message: 'sensitive-provider-diagnostic'}}, {status});
    }});
    await assert.rejects(api.search(input), error => error instanceof StockDiscoveryError &&
      error.code === (status === 500 ? 'STOCK_PROVIDER_UNAVAILABLE' : 'STOCK_PROVIDER_AUTH_FAILED') && !error.message.includes('sensitive'));
    assert.equal(calls, 1);
  }
});
it('singleflights and briefly caches an exact request without caching unsanitized failures', async () => {
  let calls = 0;
  let clock = now;
  let finish!: (response: Response) => void;
  const response = new Promise<Response>(resolve => { finish = resolve; });
  const api = client(undefined, {now: () => clock, fetch: async () => {
    calls++;
    return calls === 1 ? response : Response.json(search());
  }});
  const first = api.search(input);
  const joined = api.search(input);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls, 1);
  finish(Response.json(search()));
  const [one, two] = await Promise.all([first, joined]);
  assert.equal(one, two);
  assert.equal(await api.search(input), one);
  assert.equal(calls, 1);
  clock += 5_000;
  assert.notEqual(await api.search(input), one);
  assert.equal(calls, 2);

  let invalidCalls = 0;
  let invalidClock = now;
  const invalid = client(undefined, {fetch: async () => {
    invalidCalls++;
    return Response.json(invalidCalls === 1 ? search({category: 'crypto'}) : search());
  }, now: () => invalidClock, paceMs: 1, wait: async durationMs => { invalidClock += durationMs; }});
  await assert.rejects(invalid.search(input), codeIs('STOCK_RESPONSE_INVALID'));
  assert.equal((await invalid.search(input)).results[0]?.assetId, 'example-company');
  assert.equal(invalidCalls, 2);
});
it('paces distinct provider reads through a bounded queue instead of rejecting ordinary overlap', async () => {
  let clock = now;
  const waits: number[] = [];
  const starts: number[] = [];
  const api = client(undefined, {
    now: () => clock,
    wait: async durationMs => { waits.push(durationMs); clock += durationMs; },
    fetch: async url => {
      starts.push(clock);
      return String(url).includes('/variants')
        ? Response.json({assetId: 'example-company', sortBy: 'liquidity', variants: [variant()]})
        : Response.json(search());
    },
  });
  const [found, foundVariants] = await Promise.all([
    api.search(input),
    api.variants({assetId: 'example-company'}),
  ]);
  assert.equal(found.results[0]?.assetId, 'example-company');
  assert.equal(foundVariants.variants[0]?.mint, mintA);
  assert.deepEqual(starts, [now, now + 1000]);
  assert.deepEqual(waits, [1000]);

  let release!: () => void;
  const blocked = new Promise<void>(resolve => { release = resolve; });
  let boundedClock = now;
  const bounded = client(undefined, {
    protection: {maxConcurrentReads: 2},
    now: () => boundedClock,
    paceMs: 1,
    wait: async durationMs => { boundedClock += durationMs; },
    fetch: async url => {
      await blocked;
      const parsed = new URL(String(url));
      const query = parsed.searchParams.get('q') ?? '';
      return Response.json(search({query}));
    },
  });
  const first = bounded.search({query: 'One'});
  const second = bounded.search({query: 'Two'});
  await assert.rejects(bounded.search({query: 'Three'}), codeIs('STOCK_RATE_LIMITED'));
  release();
  await Promise.all([first, second]);
});
it('enforces a provider 429 cooldown while retaining cached safe results', async () => {
  let clock = now;
  let calls = 0;
  const api = client(undefined, {
    now: () => clock,
    protection: {cacheTtlMs: 10_000},
    wait: async durationMs => { clock += durationMs; },
    fetch: async url => {
      calls++;
      if (calls === 2) return Response.json({}, {status: 429});
      const query = new URL(String(url)).searchParams.get('q') ?? input.query;
      return Response.json(search({query}));
    },
  });
  const cached = await api.search(input);
  await assert.rejects(api.search({query: 'Another Company'}), codeIs('STOCK_RATE_LIMITED'));
  clock += 4_000;
  assert.equal(await api.search(input), cached);
  await assert.rejects(api.search({query: 'Third Company'}), codeIs('STOCK_RATE_LIMITED'));
  assert.equal(calls, 2);
  clock += 56_000;
  assert.equal((await api.search({query: 'Third Company'})).query, 'Third Company');
  assert.equal(calls, 3);
});
it('bounds response bytes and rejects malformed JSON, non-JSON, UTF-8 and redirects', async () => {
  const responses = [new Response('{}', {headers: {'content-type': 'application/json', 'content-length': '1048577'}}),
    new Response(' '.repeat(1_048_577), {headers: {'content-type': 'application/json'}}),
    new Response('{', {headers: {'content-type': 'application/json'}}), new Response('<html>error</html>'),
    new Response(new Uint8Array([0xc3, 0x28]), {headers: {'content-type': 'application/json'}}), Response.json([])];
  const redirect = Response.json(search()); Object.defineProperty(redirect, 'redirected', {value: true}); responses.push(redirect);
  for (const response of responses) {
    await assert.rejects(client(undefined, {fetch: async () => response}).search(input), codeIs('STOCK_RESPONSE_INVALID'));
  }
});
it('aborts a slow request, rejects backwards clocks and requires explicit valid server configuration', async () => {
  const api = client(undefined, {timeoutMs: 5, fetch: async (_url, options) => new Promise((_resolve, reject) => {
    options?.signal?.addEventListener('abort', () => reject(new Error('private-provider-url')), {once: true});
  })});
  await assert.rejects(api.search(input), codeIs('STOCK_TIMEOUT'));
  let clock = now;
  await assert.rejects(client(undefined, {now: () => clock, fetch: async () => { clock--; return Response.json(search()); }}).search(input), codeIs('STOCK_TIMEOUT'));
  assert.equal(readStockDiscovery({}), undefined); assert.equal(readStockDiscovery({TOKENS_API_KEY: 'unused-server-key'}), undefined);
  assert.ok(readStockDiscovery({TRIMMY_STOCK_DISCOVERY: 'tokens_xyz', TOKENS_API_KEY: 'test-server-key'}));
  for (const env of [{TRIMMY_STOCK_DISCOVERY: 'keyless'}, {TRIMMY_STOCK_DISCOVERY: 'tokens_xyz'},
    {TRIMMY_STOCK_DISCOVERY: 'tokens_xyz', TOKENS_API_KEY: 'key\nsecret'}]) {
    assert.throws(() => readStockDiscovery(env), codeIs('STOCK_DISCOVERY_UNAVAILABLE'));
  }
});
it('returns on deadline even when an injected fetch ignores abort and never settles', {timeout: 1000}, async () => {
  const api = client(undefined, {timeoutMs: 5, fetch: async () => new Promise<Response>(() => {})});
  await assert.rejects(api.search(input), codeIs('STOCK_TIMEOUT'));
});
it('bounds stalled body reads and cancellation, then permits a later fresh request', {timeout: 1000}, async () => {
  let clock = now; let calls = 0;
  const api = client(undefined, {timeoutMs: 5, now: () => clock, fetch: async () => {
    calls++;
    if (calls > 1) return Response.json(search());
    return new Response(new ReadableStream<Uint8Array>({
      pull: () => new Promise<void>(() => {}), cancel: () => new Promise<void>(() => {}),
    }), {headers: {'content-type': 'application/json'}});
  }});
  await assert.rejects(api.search(input), codeIs('STOCK_TIMEOUT'));
  clock += 1000;
  assert.equal((await api.search(input)).results[0]?.assetId, 'example-company');
  assert.equal(calls, 2);
});

it('catalog reads paginated stock assets with facts and filters non-equities without losing offsets', async () => {
  const payload = {listId: 'stocks', primaryVariantStrategy: 'liquidity',
    pagination: {offset: 20, limit: 20, total: 45, hasMore: true, nextOffset: 40},
    assets: [asset(), asset({assetId: 'oil', category: 'commodity'})]};
  const api = client(payload, {fetch: async url => {
    const parsed = new URL(String(url));
    assert.equal(parsed.pathname, '/v1/assets/curated');
    assert.equal(parsed.searchParams.get('list'), 'stocks');
    assert.equal(parsed.searchParams.get('offset'), '20');
    assert.equal(parsed.searchParams.get('variants'), 'all');
    return Response.json(payload);
  }});
  const page = await api.catalog(20);
  assert.equal(page.discovery.results.length, 1);
  assert.equal(page.cards[0]?.assetId, page.discovery.results[0]?.assetId);
  assert.equal(page.nextOffset, 40);
  assert.equal(page.discovery.executionEnabled, false);
  assert.equal(page.discovery.results[0]?.variants[0]?.market?.priceUsd, 101.25);
});
it('catalog rejects invalid offsets and inconsistent provider pagination', async () => {
  for (const offset of [-1, 1, 10001, NaN, Infinity]) {
    await assert.rejects(client().catalog(offset), codeIs('STOCK_INPUT_INVALID'));
  }
  for (const nextOffset of [0, 19, 40, null]) {
    await assert.rejects(client({listId: 'stocks', primaryVariantStrategy: 'liquidity',
      pagination: {offset: 0, limit: 20, total: 45, hasMore: true, nextOffset}, assets: [asset()]})
      .catalog(), codeIs('STOCK_RESPONSE_INVALID'));
  }
});
