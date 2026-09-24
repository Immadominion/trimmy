import assert from 'node:assert/strict';
import { it } from 'node:test';
import { readStockFacts, safeImageUrl, shortDescription, StockFactsError, TokensStockFacts } from '../src/stock-facts.js';
import type { TokensStockFactsOptions } from '../src/stock-facts.js';

const now = Date.parse('2026-09-20T15:00:00.000Z');
const nowSeconds = Math.floor(now / 1000);
// Schema fixtures only: these public mints do not represent the invented company.
const mintA = 'So11111111111111111111111111111111111111112';
const codeIs = (code: string) => (error: unknown) => error instanceof StockFactsError && error.code === code;
function market(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {price: 101.25, liquidity: 8000, volume24hUSD: 1000, decimals: 9, priceChange24hPercent: -0.42,
    logoURI: 'https://xstocks-metadata.backed.fi/logos/tokens/EXx.png', source: 'clickhouse_trades', ...overrides};
}
function searchAsset(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {assetId: 'example-company', name: 'Example Company', symbol: 'EX', category: 'equity',
    imageUrl: 'https://api.tokens.xyz/logos/xstocks/EXx.png',
    canonicalMarket: {price: 102.5, priceChange24hPercent: -1.25, asOf: nowSeconds - 3600, source: 'clickhouse_stock'},
    primaryVariant: {variantId: 'fixture-a', mint: mintA, symbol: 'EXx', market: market()},
    variants: [], advisories: [], stats: {priceChange24hPercent: -0.4}, ...overrides};
}
function search(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {query: 'Example', category: 'equity', primaryVariantStrategy: 'liquidity', results: [searchAsset()], ...overrides};
}
const keptDescription = 'Example Company designs widgets. It sells them everywhere. ' +
  'A third sentence pads the text out so the description runs well past the short display limit that the cards use, ' +
  'and it keeps going with more words about factories, services, subscriptions, partnerships and long-term plans for growth. ' +
  'Yet another sentence follows to be sure the limit is exceeded by a clear margin for the test.';
function detail(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {asset: {...searchAsset(), description: keptDescription + ' One more sentence pushes the whole text past the display limit.',
    ...overrides}};
}
function chart(candles: readonly Record<string, unknown>[] = [
  {time: nowSeconds - 5 * 14_400, open: 1, high: 1, low: 1, close: 100.5, volume: 1},
  {time: nowSeconds - 3 * 14_400, open: 1, high: 1, low: 1, close: 101, volume: 1},
  {time: nowSeconds - 14_400, open: 1, high: 1, low: 1, close: 102.5, volume: 1},
], overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {assetId: 'example-company', interval: '4H', from: nowSeconds - 7 * 86_400, to: nowSeconds, candles, ...overrides};
}
type Route = (url: URL) => Response | Promise<Response>;
function client(route: Route, options: Partial<TokensStockFactsOptions> = {}) {
  // Pacing waits advance a fake clock so the second provider read is admitted.
  let clock = now;
  return new TokensStockFacts({apiKey: 'server-test-key-not-live', now: () => clock, wait: async ms => { clock += ms; },
    fetch: async url => route(new URL(String(url))), ...options});
}
const byPath = (payloads: Record<string, unknown>): Route => url => {
  const payload = payloads[url.pathname];
  return payload === undefined ? new Response('missing', {status: 404}) : Response.json(payload);
};

it('cards project daily change, logo and session snapshot from the search payload without approving anything', async () => {
  const calls: URL[] = [];
  const api = client(url => { calls.push(url); return Response.json(search()); });
  const page = await api.cards({query: 'Example', limit: 5});
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.origin + calls[0]!.pathname, 'https://api.tokens.xyz/v1/assets/search');
  assert.deepEqual(Object.fromEntries(calls[0]!.searchParams), {q: 'Example', category: 'equity', variants: 'all',
    primaryVariantStrategy: 'liquidity', limit: '5'});
  assert.equal(page.executionEnabled, false); assert.equal(page.eligibility, 'unverified'); assert.equal(page.displayOnly, true);
  assert.equal(page.completeCatalog, false); assert.equal(page.refreshAfter, '2026-09-20T15:01:00.000Z');
  const row = page.results[0]!;
  assert.deepEqual(row.stock, {priceUsd: 102.5, changePercent24h: -1.25, asOfUnixSeconds: nowSeconds - 3600});
  assert.equal(row.imageUrl, 'https://api.tokens.xyz/logos/xstocks/EXx.png');
  assert.deepEqual(row.primaryVariant, {mint: mintA, symbol: 'EXx', logoUrl: 'https://xstocks-metadata.backed.fi/logos/tokens/EXx.png',
    priceUsd: 101.25, changePercent24h: -0.42});
  assert.ok(Object.isFrozen(page) && Object.isFrozen(page.results) && Object.isFrozen(row) && Object.isFrozen(row.stock));
  assert.equal(JSON.stringify(page).includes('server-test-key'), false);
});
it('cards leave missing or untrusted facts null instead of inventing them', async () => {
  const api = client(() => Response.json(search({results: [searchAsset({imageUrl: 'https://evil.example/logo.png',
    canonicalMarket: null, primaryVariant: {mint: mintA, market: null}})]})));
  const row = (await api.cards({query: 'Example'})).results[0]!;
  assert.equal(row.imageUrl, null); assert.equal(row.stock, null); assert.equal(row.name, 'Example Company');
  assert.deepEqual(row.primaryVariant, {mint: mintA, symbol: null, logoUrl: null, priceUsd: null, changePercent24h: null});
  const bare = client(() => Response.json(search({results: [{assetId: 'bare', category: 'equity'}]})));
  const empty = (await bare.cards({query: 'Example'})).results[0]!;
  assert.deepEqual(empty, {assetId: 'bare', name: null, symbol: null, imageUrl: null, stock: null, primaryVariant: null});
});
it('cards reject a changed query, wrong category, duplicate assets, overflow, bad numbers and bad mints', async () => {
  for (const payload of [search({query: 'Other'}), search({category: 'crypto'}),
    search({results: [searchAsset(), searchAsset()]}),
    search({results: [searchAsset({canonicalMarket: {price: -1}})]}),
    search({results: [searchAsset({canonicalMarket: {priceChange24hPercent: 'down'}})]}),
    search({results: [searchAsset({primaryVariant: {mint: 'not-a-mint', market: market()}})]}),
    search({results: [searchAsset({imageUrl: 42})]}),
    search({results: [searchAsset({assetId: 'Bad Id'})]})]) {
    await assert.rejects(client(() => Response.json(payload)).cards({query: 'Example'}), codeIs('STOCK_FACTS_RESPONSE_INVALID'));
  }
  await assert.rejects(client(() => Response.json(search())).cards({query: 'Example', limit: 0}), codeIs('STOCK_FACTS_INPUT_INVALID'));
  await assert.rejects(client(() => Response.json(search({results: [searchAsset(), searchAsset({assetId: 'two'})]})))
    .cards({query: 'Example', limit: 1}), codeIs('STOCK_FACTS_RESPONSE_INVALID'));
});
it('facts read the detail then a seven-day 4H price chart, shorten the description and keep the sparkline ordered', async () => {
  const calls: URL[] = [];
  const api = client(url => { calls.push(url); return byPath({'/v1/assets/example-company': detail(),
    '/v1/assets/example-company/price-chart': chart()})(url); });
  const facts = await api.facts({assetId: 'example-company'});
  assert.deepEqual(calls.map(url => url.pathname), ['/v1/assets/example-company', '/v1/assets/example-company/price-chart']);
  assert.deepEqual(Object.fromEntries(calls[1]!.searchParams), {interval: '4H', from: String(nowSeconds - 7 * 86_400), to: String(nowSeconds)});
  assert.equal(facts.assetId, 'example-company'); assert.equal(facts.symbol, 'EX');
  assert.equal(facts.description, keptDescription);
  assert.ok(facts.description!.length <= 400);
  assert.deepEqual(facts.stock, {priceUsd: 102.5, changePercent24h: -1.25, asOfUnixSeconds: nowSeconds - 3600});
  assert.equal(facts.sparklineStatus, 'observed');
  assert.deepEqual(facts.sparkline?.points.map(point => point.close), [100.5, 101, 102.5]);
  assert.equal(facts.sparkline?.interval, '4H');
  assert.deepEqual(facts.sourceUrls.map(url => new URL(url).pathname), ['/v1/assets/example-company', '/v1/assets/example-company/price-chart']);
  assert.equal(facts.executionEnabled, false); assert.equal(facts.displayOnly, true);
});
it('facts survive a failed chart with an honest unavailable sparkline, but not an auth failure or a bad detail', async () => {
  const degraded = client(url => url.pathname.endsWith('price-chart') ? new Response('nope', {status: 500}) : Response.json(detail()));
  const facts = await degraded.facts({assetId: 'example-company'});
  assert.equal(facts.sparkline, null); assert.equal(facts.sparklineStatus, 'unavailable');
  assert.equal(facts.sourceUrls.length, 1); assert.equal(facts.stock?.changePercent24h, -1.25);
  const empty = client(byPath({'/v1/assets/example-company': detail(), '/v1/assets/example-company/price-chart': chart([])}));
  assert.equal((await empty.facts({assetId: 'example-company'})).sparklineStatus, 'empty');
  const auth = client(url => url.pathname.endsWith('price-chart') ? new Response('', {status: 403}) : Response.json(detail()));
  await assert.rejects(auth.facts({assetId: 'example-company'}), codeIs('STOCK_FACTS_PROVIDER_AUTH_FAILED'));
  await assert.rejects(client(byPath({'/v1/assets/example-company': detail({assetId: 'other-company'})}))
    .facts({assetId: 'example-company'}), codeIs('STOCK_FACTS_RESPONSE_INVALID'));
  await assert.rejects(client(byPath({'/v1/assets/example-company': detail(),
    '/v1/assets/example-company/price-chart': chart([{time: nowSeconds - 30 * 86_400, close: 1}])}))
    .facts({assetId: 'example-company'}), codeIs('STOCK_FACTS_RESPONSE_INVALID'));
  await assert.rejects(client(byPath({'/v1/assets/example-company': detail(),
    '/v1/assets/example-company/price-chart': chart([{time: nowSeconds - 14_400, close: 1}, {time: nowSeconds - 14_400, close: 2}])}))
    .facts({assetId: 'example-company'}), codeIs('STOCK_FACTS_RESPONSE_INVALID'));
  await assert.rejects(client(byPath({})).facts({assetId: '../x'}), codeIs('STOCK_FACTS_INPUT_INVALID'));
});
it('facts downsample a dense chart to at most 64 points and keep the first and last', async () => {
  const candles = Array.from({length: 200}, (_, index) => ({time: nowSeconds - 7 * 86_400 + index * 3000, close: index}));
  const api = client(byPath({'/v1/assets/example-company': detail(), '/v1/assets/example-company/price-chart': chart(candles)}));
  const points = (await api.facts({assetId: 'example-company'})).sparkline!.points;
  assert.equal(points.length, 64); assert.equal(points[0]?.close, 0); assert.equal(points[63]?.close, 199);
  for (let index = 1; index < points.length; index++) assert.ok(points[index]!.unixSeconds > points[index - 1]!.unixSeconds);
});
it('caches an exact facts read briefly and refuses keyless or malformed configuration', async () => {
  let calls = 0;
  const api = client(url => { calls++; return byPath({'/v1/assets/example-company': detail(),
    '/v1/assets/example-company/price-chart': chart()})(url); });
  await api.facts({assetId: 'example-company'}); await api.facts({assetId: 'example-company'});
  assert.equal(calls, 2);
  assert.throws(() => new TokensStockFacts({apiKey: 'short'}), codeIs('STOCK_FACTS_UNAVAILABLE'));
  assert.equal(readStockFacts({}), undefined); assert.equal(readStockFacts({TRIMMY_STOCK_DISCOVERY: 'disabled'}), undefined);
  assert.throws(() => readStockFacts({TRIMMY_STOCK_DISCOVERY: 'tokens_xyz'}), codeIs('STOCK_FACTS_UNAVAILABLE'));
  assert.ok(readStockFacts({TRIMMY_STOCK_DISCOVERY: 'tokens_xyz', TOKENS_API_KEY: 'server-test-key-not-live'}) instanceof TokensStockFacts);
});
it('maps provider auth, rate limit and non-JSON failures without leaking diagnostics', async () => {
  await assert.rejects(client(() => new Response('', {status: 401})).cards({query: 'Example'}), codeIs('STOCK_FACTS_PROVIDER_AUTH_FAILED'));
  const limited = client(() => new Response('', {status: 429}));
  await assert.rejects(limited.cards({query: 'Example'}), codeIs('STOCK_FACTS_RATE_LIMITED'));
  await assert.rejects(limited.cards({query: 'Other'}), codeIs('STOCK_FACTS_RATE_LIMITED'));
  await assert.rejects(client(() => new Response('<html>', {status: 200, headers: {'content-type': 'text/html'}})).cards({query: 'Example'}),
    codeIs('STOCK_FACTS_RESPONSE_INVALID'));
  await assert.rejects(client(() => new Response('secret provider detail', {status: 500})).cards({query: 'Example'}),
    error => error instanceof StockFactsError && !error.message.includes('secret'));
});
it('image and description helpers stay conservative', () => {
  assert.equal(safeImageUrl('https://cdn.ondo.finance/tokens/logos/aaplon_160x160.png'), 'https://cdn.ondo.finance/tokens/logos/aaplon_160x160.png');
  assert.equal(safeImageUrl('http://api.tokens.xyz/logos/x.png'), null);
  assert.equal(safeImageUrl('https://user:pw@api.tokens.xyz/logos/x.png'), null);
  assert.equal(safeImageUrl('https://api.tokens.xyz/logos/x.png?size=1'), null);
  assert.equal(safeImageUrl(''), null); assert.equal(safeImageUrl(null), null);
  assert.equal(shortDescription('  Short.  '), 'Short.');
  assert.equal(shortDescription(''), null);
  const long = 'word '.repeat(200);
  const cut = shortDescription(long)!;
  assert.ok(cut.length <= 401 && cut.endsWith('…'));
});
