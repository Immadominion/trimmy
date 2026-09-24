import assert from 'node:assert/strict';
import { it } from 'node:test';
import { buildApp } from '../src/app.js';
import { HttpPreStocks, PreStocksError, readPreStocks } from '../src/prestocks-reader.js';
import type { PreStocksReaderOptions } from '../src/prestocks-reader.js';
import { PRESTOCKS_ROUTE } from '../src/prestocks-route.js';

const now = Date.parse('2026-09-15T15:00:00.000Z');
// Real public PreStocks mints, used only as encoding fixtures here.
const anduril = 'PresTj4Yc2bAR197Er7wz4UUKSfqt6FryBEdAriBoQB';
const other = 'So11111111111111111111111111111111111111112';
const codeIs = (code: string) => (error: unknown) => error instanceof PreStocksError && error.code === code;

function row(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    name: 'Anduril PreStocks', symbol: 'ANDURIL',
    description: 'Anduril builds AI-driven defense systems.\n\nBacked 1:1 by SPV exposure.',
    image: 'https://www.prestocks.com/logos/anduril.png', external_url: 'https://www.prestocks.com/anduril',
    contract_address: anduril, markPrice: 153.08544444, markValuation: 124426543782,
    tokenPrice: 160.0797154335478, impliedValuation: 130111427601, supply: 11805.98739435, ...overrides,
  };
}
function client(payload: unknown = [row()], options: Partial<PreStocksReaderOptions> = {}) {
  return new HttpPreStocks({now: () => now, fetch: async () => Response.json(payload), ...options});
}

it('reads the keyless public listing and returns an indicative, non-executable catalog', async () => {
  let requested: {url: string; method: string | undefined; hasKey: boolean} | null = null;
  const api = client([row()], {fetch: async (url, opts) => {
    requested = {url: String(url), method: opts?.method, hasKey: new Headers(opts?.headers).has('x-api-key')};
    assert.equal(opts?.redirect, 'error');
    return Response.json([row()]);
  }});
  const catalog = await api.catalog();
  assert.equal(requested!.url, 'https://prestocks.com/api/prestocks');
  assert.equal(requested!.method, 'GET');
  assert.equal(requested!.hasKey, false);
  assert.equal(catalog.kind, 'prestocks_catalog');
  assert.equal(catalog.provider, 'prestocks-v1');
  assert.equal(catalog.priceKind, 'indicative');
  assert.equal(catalog.executionEnabled, false);
  assert.equal(catalog.eligibility, 'unverified');
  assert.equal(catalog.mintVerification, 'not_checked');
  assert.equal(catalog.providerFreshness, 'not_verified');
  assert.ok(catalog.notice.includes('No buying or selling'));
  assert.equal(catalog.requestedAt, '2026-09-15T15:00:00.000Z');
  assert.equal(catalog.refreshAfter, '2026-09-15T15:01:00.000Z');
  assert.equal(catalog.listings.length, 1);
  const listing = catalog.listings[0]!;
  assert.equal(listing.symbol, 'ANDURIL');
  assert.equal(listing.contractAddress, anduril);
  // Figures stay as exact strings, never rounded floats.
  assert.equal(listing.markPrice, '153.08544444');
  assert.equal(listing.tokenPrice, '160.0797154335478');
  assert.equal(listing.markValuation, '124426543782');
  assert.equal(listing.supply, '11805.98739435');
  // Premium = (160.0797.. - 153.0854..) / 153.0854.. in bps.
  assert.equal(listing.premiumBasisPoints, 457);
  assert.ok(Object.isFrozen(catalog) && Object.isFrozen(catalog.listings) && Object.isFrozen(listing));
});

it('reports no premium when the mark price is not positive', async () => {
  const catalog = await client([row({markPrice: 0, tokenPrice: 10})]).catalog();
  assert.equal(catalog.listings[0]!.premiumBasisPoints, null);
  assert.equal(catalog.listings[0]!.markPrice, '0');
});

it('accepts several distinct listings', async () => {
  const catalog = await client([row(), row({symbol: 'OPENAI', name: 'OpenAI PreStocks', contract_address: other,
    external_url: 'https://www.prestocks.com/openai', image: 'https://www.prestocks.com/logos/openai.png'})]).catalog();
  assert.deepEqual(catalog.listings.map(item => item.symbol), ['ANDURIL', 'OPENAI']);
});

it('refuses duplicate symbols or mints, an empty list and an oversized list', async () => {
  await assert.rejects(client([row(), row({contract_address: other})]).catalog(), codeIs('PRESTOCKS_RESPONSE_INVALID'));
  await assert.rejects(client([row(), row({symbol: 'OTHER'})]).catalog(), codeIs('PRESTOCKS_RESPONSE_INVALID'));
  await assert.rejects(client([]).catalog(), codeIs('PRESTOCKS_RESPONSE_INVALID'));
  await assert.rejects(client({not: 'an array'}).catalog(), codeIs('PRESTOCKS_RESPONSE_INVALID'));
});

it('validates every field of a listing', async () => {
  for (const bad of [
    {symbol: 'lower'}, {symbol: ''}, {symbol: 'WITH SPACE'}, {symbol: 'A'.repeat(17)},
    {name: ''}, {name: 'x'.repeat(121)}, {name: 'hascontrol'},
    {contract_address: 'too-short'}, {contract_address: `${anduril}extralongtail`},
    {image: 'http://insecure.example/logo.png'}, {image: 'not a url'}, {external_url: 'ftp://x.example'},
    {markPrice: -1}, {markPrice: 'NaN'}, {markPrice: Number.NaN}, {markPrice: Infinity},
    {supply: -0.1}, {impliedValuation: 2e15},
  ]) {
    await assert.rejects(client([row(bad)]).catalog(), codeIs('PRESTOCKS_RESPONSE_INVALID'), JSON.stringify(bad));
  }
});

it('maps provider status, content type, size and redirects to fixed codes', async () => {
  const make = (fetch: NonNullable<PreStocksReaderOptions['fetch']>) => new HttpPreStocks({now: () => now, fetch});
  await assert.rejects(make(async () => new Response('[]', {status: 429, headers: {'content-type': 'application/json'}}))
    .catalog(), codeIs('PRESTOCKS_RATE_LIMITED'));
  await assert.rejects(make(async () => new Response('[]', {status: 500, headers: {'content-type': 'application/json'}}))
    .catalog(), codeIs('PRESTOCKS_PROVIDER_UNAVAILABLE'));
  await assert.rejects(make(async () => new Response('not json', {status: 200, headers: {'content-type': 'text/html'}}))
    .catalog(), codeIs('PRESTOCKS_RESPONSE_INVALID'));
  await assert.rejects(make(async () => new Response('not json', {status: 200, headers: {'content-type': 'application/json'}}))
    .catalog(), codeIs('PRESTOCKS_RESPONSE_INVALID'));
  await assert.rejects(make(async () => Response.json([row()], {status: 200, headers: {'content-length': String(2 * 1024 * 1024)}}))
    .catalog(), codeIs('PRESTOCKS_RESPONSE_INVALID'));
  const redirected = new Response(JSON.stringify([row()]), {status: 200, headers: {'content-type': 'application/json'}});
  Object.defineProperty(redirected, 'redirected', {value: true});
  await assert.rejects(make(async () => redirected).catalog(), codeIs('PRESTOCKS_RESPONSE_INVALID'));
});

it('times out and refuses a second in-flight or too-soon request', async () => {
  const slow = new HttpPreStocks({now: () => now, timeoutMs: 10,
    fetch: (_url, opts) => new Promise((_resolve, reject) => {
      opts?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')));
    })});
  await assert.rejects(slow.catalog(), codeIs('PRESTOCKS_TIMEOUT'));
  // A monotonic clock that never advances past the spacing window rejects the next call.
  let calls = 0;
  const spaced = new HttpPreStocks({now: () => now, fetch: async () => { calls += 1; return Response.json([row()]); }});
  await spaced.catalog();
  await assert.rejects(spaced.catalog(), codeIs('PRESTOCKS_RATE_LIMITED'));
  assert.equal(calls, 1);
});

it('is disabled unless explicitly configured public', () => {
  assert.equal(readPreStocks({}), undefined);
  assert.equal(readPreStocks({TRIMMY_PRESTOCKS: ''}), undefined);
  assert.equal(readPreStocks({TRIMMY_PRESTOCKS: 'disabled'}), undefined);
  assert.ok(readPreStocks({TRIMMY_PRESTOCKS: 'public'}) instanceof HttpPreStocks);
  assert.throws(() => readPreStocks({TRIMMY_PRESTOCKS: 'yes'}), codeIs('PRESTOCKS_UNAVAILABLE'));
});

it('serves the route only when configured and never as a mutation', async () => {
  const bare = buildApp({logger: false});
  try {
    const off = await bare.inject(PRESTOCKS_ROUTE);
    assert.equal(off.statusCode, 503);
    assert.equal(off.json().error.code, 'PRESTOCKS_UNAVAILABLE');
    assert.equal((await bare.inject('/v1/config')).json().preStocksEnabled, false);
    // A POST to the read route is refused by the financial gate.
    const post = await bare.inject({method: 'POST', url: PRESTOCKS_ROUTE, payload: {}});
    assert.equal(post.statusCode, 503);
    assert.equal(post.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
  } finally { await bare.close(); }

  const instance = buildApp({logger: false, preStocks: {catalog: async () => (await client().catalog())}});
  try {
    assert.equal((await instance.inject('/v1/config')).json().preStocksEnabled, true);
    const response = await instance.inject(PRESTOCKS_ROUTE);
    assert.equal(response.statusCode, 200);
    assert.equal(response.headers['cache-control'], 'no-store');
    const body = response.json();
    assert.equal(body.kind, 'prestocks_catalog');
    assert.equal(body.executionEnabled, false);
    assert.equal(body.listings[0].symbol, 'ANDURIL');
    const query = await instance.inject(`${PRESTOCKS_ROUTE}?symbol=ANDURIL`);
    assert.equal(query.statusCode, 400);
  } finally { await instance.close(); }
});

it('maps a reader failure to its status through the route', async () => {
  const instance = buildApp({logger: false, preStocks: {
    catalog: async () => { throw new PreStocksError('PRESTOCKS_RATE_LIMITED'); }}});
  try {
    const response = await instance.inject(PRESTOCKS_ROUTE);
    assert.equal(response.statusCode, 429);
    assert.equal(response.json().error.code, 'PRESTOCKS_RATE_LIMITED');
  } finally { await instance.close(); }
});
