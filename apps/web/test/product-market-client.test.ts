import assert from 'node:assert/strict';
import test from 'node:test';
import {ProductMarketClient, ProductMarketError, parseStockCatalogPage, parseStockCardsPage, parseStockFacts,
  parseStockInsight} from '../src/product/market-client.js';
import {searchFixture, variantsFixture} from '../src/markets/fixtures.test-support.js';
import {parseStockSearchPage} from '../src/markets/discovery.js';
import {RESEARCH_AAPLX_MINT, RESEARCH_USDC_MINT} from '../src/markets/estimate.js';

const now = Date.parse('2026-09-24T12:00:00.000Z');
const common = () => ({schemaVersion: 1, provider: 'tokens-xyz-v1', requestedAt: new Date(now).toISOString(),
  observedAt: new Date(now + 1000).toISOString(), refreshAfter: new Date(now + 60000).toISOString(),
  displayOnly: true, executionEnabled: false, eligibility: 'unverified'});
const card = () => ({assetId: 'apple', name: 'Apple', symbol: 'AAPL', imageUrl: null,
  stock: {priceUsd: 251.25, changePercent24h: -0.5, asOfUnixSeconds: now / 1000},
  primaryVariant: {mint: RESEARCH_AAPLX_MINT, symbol: 'AAPLx', logoUrl: null, priceUsd: 250.75, changePercent24h: -0.3}});
const catalog = () => ({discovery: searchFixture('catalog', 20), cards: [card()], offset: 0, total: 61, nextOffset: 20});
const cards = (query = 'Apple', limit = 20) => ({...common(), sourceUrl: 'https://api.tokens.xyz/v1/assets/search?q=Apple',
  query, limit, completeCatalog: false, results: [card()]});
const facts = () => ({...common(), sourceUrls: ['https://api.tokens.xyz/v1/assets/apple'], assetId: 'apple',
  name: 'Apple', symbol: 'AAPL', imageUrl: null, description: 'Apple makes computers.', stock: card().stock,
  sparkline: null, sparklineStatus: 'unavailable'});
const insight = () => ({...common(), assetId: 'apple', mint: RESEARCH_AAPLX_MINT, period: 'day', symbol: 'AAPLx',
  description: 'Apple makes computers.', priceUsd: 250.75, changePercent24h: -0.3, asOfUnixSeconds: now / 1000,
  volume24hUsd: 1000, liquidityUsd: 2000, tokenMarketCapUsd: 100000, stockMarketCapUsd: 100000000000,
  holders: 37, points: [{unixSeconds: now / 1000 - 3600, close: 250}, {unixSeconds: now / 1000, close: 250.75}],
  chartStatus: 'observed'});
const client = (fetch: typeof globalThis.fetch, timeoutMs = 1000) => new ProductMarketClient({baseUrl: '/api', fetch, timeoutMs});
const deferred = <T>() => {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => {resolve = done;}); return {promise, resolve};
};

test('catalog preserves provider offsets and card/token/underlying-stock distinctions', () => {
  const wire = catalog(), result = parseStockCatalogPage(wire);
  assert.equal(result.cards.length, 1); assert.equal(result.nextOffset, 20); assert.equal(result.total, 61);
  assert.equal(result.discovery.completeCatalog, false);
  assert.equal(result.cards[0]!.stock!.priceUsd, 251.25);
  assert.equal(result.cards[0]!.primaryVariant!.priceUsd, 250.75);
  wire.cards[0]!.stock!.priceUsd = 999; wire.cards.length = 0;
  assert.equal(result.cards[0]!.stock!.priceUsd, 251.25);
  assert.ok(Object.isFrozen(result.cards[0]!.primaryVariant));
  const filtered = {...catalog(), cards: [], discovery: {...searchFixture('catalog', 20), results: []}};
  assert.equal(parseStockCatalogPage(filtered).nextOffset, 20, 'empty equity page must not end provider pagination');
  assert.equal(parseStockCatalogPage({...filtered, total: 0, nextOffset: null}).nextOffset, null);
});

test('catalog rejects mismatched enrichment, token identity, pagination and execution claims', () => {
  const wrongAsset = catalog(); wrongAsset.cards[0]!.assetId = 'tesla';
  const wrongToken = catalog(); wrongToken.cards[0]!.primaryVariant!.mint = RESEARCH_USDC_MINT;
  for (const value of [wrongAsset, wrongToken, {...catalog(), nextOffset: 1}, {...catalog(), nextOffset: 80},
    {...catalog(), offset: 1}, {...catalog(), cards: []}, {...catalog(), discovery: {...searchFixture('catalog', 20), executionEnabled: true}}]) {
    assert.throws(() => parseStockCatalogPage(value), {code: 'STOCK_RESPONSE_INVALID'});
  }
});

test('facts/cards retain null as missing and zero as a measured value', () => {
  const value = cards(); value.results[0]!.stock = {priceUsd: 0, changePercent24h: 0, asOfUnixSeconds: 0};
  const result = parseStockCardsPage(value); assert.equal(result.results[0]!.stock!.priceUsd, 0);
  const missing = {...facts(), stock: null, imageUrl: null, description: null};
  const parsed = parseStockFacts(missing); assert.equal(parsed.stock, null); assert.equal(parsed.sparkline, null);
  assert.equal(parsed.sparklineStatus, 'unavailable'); assert.equal(parsed.description, null);
  for (const price of [-1, Infinity, NaN, '250']) {
    assert.throws(() => parseStockCardsPage({...cards(), results: [{...card(), stock: {...card().stock, priceUsd: price}}]}));
  }
});

test('image allowlist rejects embedded credentials and arbitrary remote image hosts', () => {
  for (const url of ['https://evil.example/image.png', 'data:image/svg+xml,hello', 'javascript:alert(1)',
    'https://secret@api.tokens.xyz/image.png', 'https://api.tokens.xyz/image.png?private=1']) {
    assert.throws(() => parseStockCardsPage({...cards(), results: [{...card(), imageUrl: url}]}), {code: 'STOCK_RESPONSE_INVALID'});
  }
  const logo = `https://storage.googleapis.com/tokens-asset-logos-prd/solana/${RESEARCH_AAPLX_MINT}.webp`;
  assert.equal(parseStockCardsPage({...cards(), results: [{...card(), imageUrl: logo}]}).results[0]!.imageUrl, logo);
});

test('selected-mint insight retains exact sample timestamps, token cap and company cap separately', () => {
  const wire = insight(), result = parseStockInsight(wire);
  assert.equal(result.mint, RESEARCH_AAPLX_MINT); assert.equal(result.tokenMarketCapUsd, 100000);
  assert.equal(result.stockMarketCapUsd, 100000000000); assert.equal(result.points[0]!.unixSeconds, now / 1000 - 3600);
  wire.points[0]!.close = 100; assert.equal(result.points[0]!.close, 250); assert.ok(Object.isFrozen(result.points[0]));
  for (const status of ['empty', 'unavailable']) {
    const absent = parseStockInsight({...insight(), chartStatus: status, points: [], priceUsd: null, holders: null});
    assert.deepEqual(absent.points, []); assert.equal(absent.priceUsd, null); assert.equal(absent.chartStatus, status);
  }
});

test('chart parsers refuse reordered, duplicate, future and invented observed points', () => {
  const first = insight().points[0]!;
  for (const value of [{...insight(), points: [first, first]}, {...insight(), points: insight().points.reverse()},
    {...insight(), points: [{unixSeconds: now / 1000 + 100, close: 4}]}, {...insight(), points: []},
    {...insight(), chartStatus: 'empty'}, {...insight(), chartStatus: 'unavailable'}, {...insight(), holders: 1.5}]) {
    assert.throws(() => parseStockInsight(value), {code: 'STOCK_RESPONSE_INVALID'});
  }
  const sparkline = {interval: '4H', fromUnixSeconds: now / 1000 - 7 * 86400, toUnixSeconds: now / 1000,
    points: [{unixSeconds: now / 1000, close: 251.25}]};
  assert.equal(parseStockFacts({...facts(), sparkline, sparklineStatus: 'observed'}).sparkline!.points.length, 1);
  assert.throws(() => parseStockFacts({...facts(), sparkline, sparklineStatus: 'unavailable'}));
});

test('new product endpoints are fixed public GETs via explicit same-origin relay', async () => {
  const paths: string[] = [];
  const api = client(async (input, options) => {
    const url = new URL(String(input), 'https://web.example'); paths.push(url.pathname);
    assert.equal(options?.method, 'GET'); assert.equal(options?.credentials, 'omit'); assert.equal(options?.cache, 'no-store');
    assert.equal(options?.redirect, 'error'); assert.equal(options?.referrerPolicy, 'no-referrer'); assert.equal(options?.body, undefined);
    assert.deepEqual([...new Headers(options?.headers)], [['accept', 'application/json']]);
    const data = url.pathname.endsWith('/catalog') ? catalog() : url.pathname.endsWith('/cards') ? cards() :
      url.pathname.endsWith('/facts') ? facts() : url.pathname.endsWith('/insight') ? insight() :
      url.pathname.endsWith('/variants') ? variantsFixture() : searchFixture('Apple', 20);
    return Response.json(data);
  });
  await api.catalog(); await api.cards('Apple'); await api.facts('apple');
  await api.insight({assetId: 'apple', mint: RESEARCH_AAPLX_MINT, period: 'day'}); await api.variants('apple'); await api.search('Apple');
  assert.deepEqual(paths, ['catalog', 'cards', 'facts', 'insight', 'variants', 'search'].map(path => `/api/v1/markets/stocks/${path}`));
});

test('configured HTTPS origins work and noncanonical/credential/path bases fail before dispatch', async () => {
  let calls = 0;
  const fetch: typeof globalThis.fetch = async input => {calls++; assert.equal(String(input), 'https://api.example/v1/markets/stocks/catalog?offset=0&schema=2'); return Response.json(catalog());};
  await new ProductMarketClient({baseUrl: 'https://api.example', fetch}).catalog();
  for (const baseUrl of ['http://localhost:8080', '//evil.example', '/api/', '/api?key=secret', 'https://api.example/',
    'https://api.example/path', 'https://secret@api.example', 'HTTPS://API.EXAMPLE', 'https://api.example:443', 'https://api.example#x']) {
    assert.throws(() => new ProductMarketClient({baseUrl, fetch}), {code: 'STOCK_INVALID_CONFIGURATION'});
  }
  assert.equal(calls, 1);
});

test('request fields are bounded before fetch, including catalogue offset and arbitrary insight extras', async () => {
  let calls = 0; const api = client(async () => {calls++; return Response.json({});});
  for (const offset of [-1, 1, 19, 10020, Infinity]) await assert.rejects(api.catalog(offset), {code: 'STOCK_INPUT_INVALID'});
  for (const query of ['', ' Apple', 'Apple\n', 'x'.repeat(81)]) await assert.rejects(api.cards(query), {code: 'STOCK_INPUT_INVALID'});
  await assert.rejects(api.search('Apple', {limit: 21}), {code: 'STOCK_INPUT_INVALID'});
  await assert.rejects(api.facts('../users'), {code: 'STOCK_INPUT_INVALID'});
  await assert.rejects(api.insight({assetId: 'apple', mint: RESEARCH_AAPLX_MINT, period: 'wrong'} as never), {code: 'STOCK_INPUT_INVALID'});
  await assert.rejects(api.insight({assetId: 'apple', mint: RESEARCH_AAPLX_MINT, period: 'day', wallet: 'extra'} as never), {code: 'STOCK_INPUT_INVALID'});
  assert.equal(calls, 0);
});

test('response identities bind catalogue offset, query, asset, mint and period to each request', async () => {
  await assert.rejects(client(async () => Response.json(catalog())).catalog(20), {code: 'STOCK_RESPONSE_INVALID'});
  await assert.rejects(client(async () => Response.json(cards('Tesla'))).cards('Apple'), {code: 'STOCK_RESPONSE_INVALID'});
  await assert.rejects(client(async () => Response.json(facts())).facts('tesla'), {code: 'STOCK_RESPONSE_INVALID'});
  await assert.rejects(client(async () => Response.json(insight())).insight({assetId: 'apple', mint: RESEARCH_USDC_MINT, period: 'day'}), {code: 'STOCK_RESPONSE_INVALID'});
  await assert.rejects(client(async () => Response.json(insight())).insight({assetId: 'apple', mint: RESEARCH_AAPLX_MINT, period: 'week'}), {code: 'STOCK_RESPONSE_INVALID'});
});

test('caller mutation during a pending insight read cannot rebind the response', async () => {
  const pending = deferred<Response>(), api = client(async () => pending.promise);
  const request = {assetId: 'apple', mint: RESEARCH_AAPLX_MINT, period: 'day'} as const;
  const result = api.insight(request); Object.assign(request, {assetId: 'tesla', mint: RESEARCH_USDC_MINT});
  pending.resolve(Response.json(insight())); assert.equal((await result).assetId, 'apple');
});

test('timeouts cover a fetch that ignores abort and a body that never finishes', async () => {
  await assert.rejects(client(async () => new Promise<Response>(() => {}), 15).catalog(), {code: 'STOCK_TIMEOUT'});
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({start(controller) {controller.enqueue(new TextEncoder().encode('{'));}, cancel() {cancelled = true;}});
  await assert.rejects(client(async () => new Response(body, {headers: {'content-type': 'application/json'}}), 15).catalog(), {code: 'STOCK_TIMEOUT'});
  assert.equal(cancelled, true);
});

test('close and caller cancellation retire in-flight work without any automatic retry', async () => {
  const pending = deferred<Response>(); let calls = 0;
  const api = client(async () => {calls++; return pending.promise;}); const result = api.catalog(); api.close();
  await assert.rejects(result, {code: 'STOCK_CANCELLED'}); pending.resolve(Response.json(catalog()));
  await assert.rejects(api.catalog(), {code: 'STOCK_CANCELLED'}); assert.equal(calls, 1);
  const cancelled = new AbortController(); cancelled.abort();
  await assert.rejects(client(async () => {calls++; return Response.json(catalog());}).catalog(0, {signal: cancelled.signal}), {code: 'STOCK_CANCELLED'});
  assert.equal(calls, 1);
  const active = new AbortController(); const work = client(async () => new Promise<Response>(() => {})).cards('Apple', {signal: active.signal});
  active.abort(); await assert.rejects(work, {code: 'STOCK_CANCELLED'});
});

test('transport rejects redirected identities, non-JSON, invalid UTF-8 and oversized bodies', async () => {
  const wrongUrl = Response.json(catalog()); Object.defineProperty(wrongUrl, 'url', {value: 'https://evil.example/catalog'});
  for (const [response, code] of [[wrongUrl, 'STOCK_REDIRECT_REJECTED'],
    [new Response(null, {status: 302}), 'STOCK_REDIRECT_REJECTED'],
    [new Response('{}', {headers: {'content-type': 'text/plain'}}), 'STOCK_RESPONSE_INVALID'],
    [new Response(new Uint8Array([0xc3, 0x28]), {headers: {'content-type': 'application/json'}}), 'STOCK_RESPONSE_INVALID'],
    [new Response('{}', {headers: {'content-type': 'application/json', 'content-length': '1048577'}}), 'STOCK_RESPONSE_TOO_LARGE'],
    [new Response(' '.repeat(1048577), {headers: {'content-type': 'application/json'}}), 'STOCK_RESPONSE_TOO_LARGE']] as const) {
    await assert.rejects(client(async () => response).catalog(), {code});
  }
});

test('only known endpoint/status error codes cross the transport boundary', async () => {
  const failure = (status: number, code: string) => client(async () => Response.json({error: {code, message: 'Server text is not display copy.', requestId: 'fixture'}}, {status}));
  await assert.rejects(failure(429, 'STOCK_FACTS_RATE_LIMITED').facts('apple'), {code: 'STOCK_FACTS_RATE_LIMITED'});
  await assert.rejects(failure(503, 'STOCK_DISCOVERY_UNAVAILABLE').catalog(), {code: 'STOCK_DISCOVERY_UNAVAILABLE'});
  await assert.rejects(failure(503, 'PRIVATE_SECRET').facts('apple'), {code: 'STOCK_SERVICE_UNAVAILABLE'});
  await assert.rejects(failure(503, 'STOCK_RATE_LIMITED').catalog(), {code: 'STOCK_SERVICE_UNAVAILABLE'});
  const result = failure(503, 'STOCK_FACTS_UNAVAILABLE').cards('Apple');
  await assert.rejects(result, error => error instanceof ProductMarketError && error.message === 'STOCK_FACTS_UNAVAILABLE');
});

test('catalog, search and cards ask for funds and commodities (schema 2) and fall back once for an older server', async () => {
  const seen: string[] = [];
  let modern = true;
  const etf = {...searchFixture('catalog', 20).results[0]!, assetId: 'sp500', name: 'SPDR S&P 500 ETF', symbol: 'SPY', category: 'etf'};
  const gold = {...searchFixture('catalog', 20).results[0]!, assetId: 'gold', name: 'Gold', symbol: 'XAU', category: 'commodity',
    providerPrimaryVariantMint: 'Xsv9hRk1z5ystj9MhnA7Lq4vjSsLwzL2nxrwmwtD3re', variants: [{...searchFixture().results[0]!.variants[0]!, variantId: 'gold-x', mint: 'Xsv9hRk1z5ystj9MhnA7Lq4vjSsLwzL2nxrwmwtD3re'}]};
  const api = client(async input => {
    const url = new URL(String(input), 'https://web.example'); seen.push(`${url.pathname}${url.search}`);
    if (url.searchParams.get('schema') === '2' && !modern) return Response.json({error: {code: 'STOCK_INPUT_INVALID', message: 'Unknown field.', requestId: 'r'}}, {status: 400});
    if (url.pathname.endsWith('/catalog')) {
      const discovery = {...searchFixture('catalog', 20), results: modern ? [etf, gold] : [searchFixture().results[0]!]};
      return Response.json({discovery, cards: discovery.results.map(row => ({assetId: row.assetId, name: row.name, symbol: row.symbol, imageUrl: null, stock: null, primaryVariant: null})),
        offset: Number(url.searchParams.get('offset')), total: 300, nextOffset: Number(url.searchParams.get('offset')) + 40});
    }
    return Response.json({...searchFixture(url.searchParams.get('query')!, 20), results: modern ? [etf] : searchFixture().results});
  });
  const page = await api.catalog(20);
  assert.deepEqual(page.discovery.results.map(row => row.category), ['etf', 'commodity']);
  assert.equal(page.cards.length, 2, 'a schema 2 page may hold fewer than 20 rows'); assert.equal(page.nextOffset, 60, 'paging follows nextOffset');
  assert.equal((await api.search('SPY')).results[0]?.category, 'etf');
  assert.deepEqual(seen, ['/api/v1/markets/stocks/catalog?offset=20&schema=2', '/api/v1/markets/stocks/search?query=SPY&limit=20&schema=2']);
  modern = false; seen.length = 0;
  const older = client(async input => {
    const url = new URL(String(input), 'https://web.example'); seen.push(`${url.pathname}${url.search}`);
    if (url.searchParams.get('schema') === '2') return Response.json({error: {code: 'STOCK_INPUT_INVALID', message: 'Unknown field.', requestId: 'r'}}, {status: 400});
    return Response.json(searchFixture(url.searchParams.get('query')!, 20));
  });
  assert.equal((await older.search('Apple')).results[0]?.category, 'equity');
  await older.search('Apple');
  assert.deepEqual(seen, ['/api/v1/markets/stocks/search?query=Apple&limit=20&schema=2', '/api/v1/markets/stocks/search?query=Apple&limit=20',
    '/api/v1/markets/stocks/search?query=Apple&limit=20'], 'the fallback is remembered');
  assert.throws(() => parseStockSearchPage({...searchFixture(), results: [{...searchFixture().results[0]!, category: 'crypto'}]}));
});

test('the default fetch is bound to the global, as browsers require', async () => {
  const original = globalThis.fetch;
  // Emulates Chrome's receiver check: fetch invoked as a method of another object throws.
  globalThis.fetch = function (this: unknown, ...args: Parameters<typeof fetch>) {
    if (this !== undefined && this !== globalThis) throw new TypeError("Failed to execute 'fetch' on 'Window': Illegal invocation");
    return original(...args);
  } as typeof fetch;
  try {
    const client = new ProductMarketClient({baseUrl: 'https://api.example'});
    await assert.rejects(client.catalog(0, {signal: AbortSignal.abort()}), {code: 'STOCK_CANCELLED'});
    globalThis.fetch = function (this: unknown) {
      if (this !== undefined && this !== globalThis) throw new TypeError('Illegal invocation');
      return Promise.resolve(new Response('{}', {status: 503, headers: {'content-type': 'application/json'}}));
    } as typeof fetch;
    const bound = new ProductMarketClient({baseUrl: 'https://api.example'});
    await assert.rejects(bound.catalog(0), (error: {code?: string}) => error.code !== 'STOCK_NETWORK_ERROR', 'the request reaches fetch instead of failing as a network error');
  } finally {globalThis.fetch = original;}
});

test('holding prices ask for each held mint once and accept only trusted prices for them', async () => {
  const other = 'XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB';
  const urls: string[] = [];
  const api = new ProductMarketClient({baseUrl: 'https://api.example', fetch: async input => {
    urls.push(String(input));
    return Response.json({schema: 1, observedAt: '2026-09-28T17:40:00.000Z', prices: [
      {mint: RESEARCH_AAPLX_MINT, usdPerShare: 339.97, source: 'issuer', asOf: '2026-09-28T17:35:00.000Z'}]});
  }, timeoutMs: 1000});
  const prices = await api.prices([other, RESEARCH_AAPLX_MINT, RESEARCH_AAPLX_MINT]);
  assert.deepEqual([...prices], [[RESEARCH_AAPLX_MINT, 339.97]]);
  assert.equal(urls.length, 1);
  assert.equal(new URL(urls[0]!).searchParams.get('mints'), [RESEARCH_AAPLX_MINT, other].sort().join(','));
  await assert.rejects(api.prices(['not a mint']), {code: 'STOCK_INPUT_INVALID'});
  for (const row of [{mint: other, usdPerShare: 1, source: 'issuer'}, {mint: RESEARCH_AAPLX_MINT, usdPerShare: 0, source: 'issuer'},
    {mint: RESEARCH_AAPLX_MINT, usdPerShare: 1, source: 'trade'}]) {
    const strict = client(async () => Response.json({schema: 1, prices: [row]}));
    await assert.rejects(strict.prices([RESEARCH_AAPLX_MINT]), {code: 'STOCK_RESPONSE_INVALID'});
  }
});
