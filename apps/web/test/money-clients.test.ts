import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {LiveOrderClient, LiveOrderError} from '../src/product/money/live-order-client.js';
import {AccountWalletClient} from '../src/product/money/wallet-client.js';
import {ACCOUNT_ID, contextJson, holdingsJson, orderJson, signer} from './support/money-fixtures.js';

const capabilities = JSON.parse(readFileSync(new URL('./fixtures/trading-capabilities-v2-2026-09-27.json', import.meta.url), 'utf8')) as unknown;
const TOKEN = 'aaa.bbb.ccc';
interface Seen {url: string; init: RequestInit}
function fetcher(reply: (url: string, init: RequestInit) => Response | Promise<Response>) {
  const seen: Seen[] = [];
  const fetch = (async (url: string | URL | Request, init: RequestInit = {}) => {seen.push({url: String(url), init}); return reply(String(url), init);}) as typeof globalThis.fetch;
  return {seen, fetch};
}
const header = (init: RequestInit, name: string) => (init.headers as Record<string, string>)[name];

test('capabilities read schema 2 first, fall back for an older server, and never carry credentials', async () => {
  const modern = fetcher(() => Response.json(capabilities));
  const client = new LiveOrderClient({baseUrl: '/api', bearer: async () => TOKEN, fetch: modern.fetch});
  assert.equal((await client.capabilities()).assets.length, 60);
  assert.equal(modern.seen[0]?.url, '/api/v1/trading/capabilities?schema=2');
  assert.equal(header(modern.seen[0]!.init, 'authorization'), undefined); assert.equal(modern.seen[0]!.init.credentials, 'omit');
  const legacy = fetcher(url => url.includes('schema') ? Response.json({code: 'INVALID'}, {status: 400}) : Response.json({enabled: false,
    network: 'solana:mainnet-beta', maxBuyUsdc: '100', minimumSolBalanceLamports: '5000', assets: []}));
  const old = await new LiveOrderClient({baseUrl: 'https://api.example.com', bearer: async () => TOKEN, fetch: legacy.fetch}).capabilities();
  assert.equal(old.legacy, true); assert.deepEqual(legacy.seen.map(item => item.url), ['https://api.example.com/v1/trading/capabilities?schema=2', 'https://api.example.com/v1/trading/capabilities']);
  await assert.rejects(new LiveOrderClient({baseUrl: '/api', bearer: async () => TOKEN, fetch: fetcher(() => Response.json({enabled: true})).fetch}).capabilities(),
    (error: LiveOrderError) => error.code === 'LIVE_UNAVAILABLE');
  assert.throws(() => new LiveOrderClient({baseUrl: 'http://api.example.com', bearer: async () => TOKEN}));
});

test('preview sends exactly the order and the accepted issuer terms, and maps every refusal to its copy', async () => {
  const wallet = (await signer()).address;
  const replies: Response[] = [Response.json({order: orderJson({wallet, transaction: 'AQID'})}),
    ...['TERMS_REQUIRED', 'MARKET_CLOSED', 'ADD_SOL', 'FEE_TOO_HIGH', 'ORDER_PENDING'].map(code => Response.json({code}, {status: 409})),
    Response.json({code: 'LIVE_BUSY'}, {status: 429}), Response.json({code: 'ACCOUNT_REQUIRED'}, {status: 401}), Response.json({code: 'SOMETHING_NEW'}, {status: 503})];
  const http = fetcher(() => replies.shift()!);
  const client = new LiveOrderClient({baseUrl: '/api', bearer: async () => TOKEN, fetch: http.fetch});
  const input = {assetId: 'apple', variantMint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', side: 'buy' as const, amountRaw: '5000000',
    termsAccepted: {issuerId: 'xstocks', version: '2026-09-27'}};
  assert.equal((await client.preview(input)).status, 'reviewed');
  assert.deepEqual(JSON.parse(String(http.seen[0]!.init.body)), input);
  assert.equal(http.seen[0]!.init.method, 'POST'); assert.equal(header(http.seen[0]!.init, 'authorization'), `Bearer ${TOKEN}`);
  assert.equal(header(http.seen[0]!.init, 'content-type'), 'application/json'); assert.equal(http.seen[0]!.init.redirect, 'error');
  const codes = [];
  for (let index = 0; index < 8; index++) codes.push(await client.preview(input).then(() => 'ok', (error: LiveOrderError) => [error.code, error.message]));
  assert.deepEqual(codes.map(entry => entry[0]), ['TERMS_REQUIRED', 'MARKET_CLOSED', 'ADD_SOL', 'FEE_TOO_HIGH', 'ORDER_PENDING', 'LIVE_BUSY', 'ACCOUNT_REQUIRED', 'LIVE_UNAVAILABLE']);
  assert.equal(codes[1]![1], 'This stock trades while US markets are open. Try again then.');
  assert.equal(codes[2]![1], 'Add SOL to cover network and account fees.');
});

test('trading calls fail closed without a bound bearer or after the identity changes, and report lost replies as uncertain', async () => {
  const http = fetcher(() => Response.json({order: null}));
  const identity = new AbortController();
  const client = new LiveOrderClient({baseUrl: '/api', bearer: async () => null, fetch: http.fetch, signal: identity.signal});
  await assert.rejects(client.order(), (error: LiveOrderError) => error.code === 'ACCOUNT_REQUIRED');
  assert.equal(http.seen.length, 0);
  const bound = new LiveOrderClient({baseUrl: '/api', bearer: async () => TOKEN, fetch: http.fetch, signal: identity.signal});
  assert.equal(await bound.order(), null);
  assert.equal(http.seen[0]?.url, '/api/v1/trading/order');
  await assert.rejects(bound.order('not-a-uuid'));
  identity.abort();
  await assert.rejects(bound.order(), (error: LiveOrderError) => error.code === 'ACCOUNT_REQUIRED');
  const lost = new LiveOrderClient({baseUrl: '/api', bearer: async () => TOKEN, fetch: (async () => {throw new TypeError('network');}) as typeof fetch});
  await assert.rejects(lost.execute({id: '44444444-4444-4444-8444-444444444444', reviewDigest: 'a'.repeat(64), signedTransaction: 'AQID'}),
    (error: LiveOrderError) => error.code === 'NETWORK_UNCERTAIN');
});

test('history pages with limit and cursor and refuses a cursor that repeats', async () => {
  const wallet = (await signer()).address;
  const row = {id: '55555555-5555-4555-8555-555555555555', wallet, status: 'confirmed', signature: '4'.repeat(88), createdAt: '2026-09-27T10:00:00.123456Z',
    updatedAt: '2026-09-27T10:00:01.123456Z', asset: {assetId: 'apple', mint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', symbol: 'AAPLx', name: 'Apple xStock', decimals: 8, route: 'aggregator'},
    terms: {side: 'buy', inputMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', outputMint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', inputAmountRaw: '5000000', quotedOutputAmountRaw: '1960000', minimumOutputAmountRaw: '1950000'},
    amountUnits: 'raw_token_units', amountsStatus: 'reviewed_quote'};
  const http = fetcher(url => Response.json({schemaVersion: 1, network: 'solana:mainnet-beta', orders: [row], nextCursor: url.includes('cursor') ? 'next' : 'next'}));
  const client = new LiveOrderClient({baseUrl: '/api', bearer: async () => TOKEN, fetch: http.fetch});
  assert.equal((await client.history()).nextCursor, 'next');
  assert.equal(http.seen[0]?.url, '/api/v1/trading/history?limit=20');
  await assert.rejects(client.history('next'), (error: LiveOrderError) => error.code === 'HISTORY_UNAVAILABLE');
  assert.equal(http.seen[1]?.url, '/api/v1/trading/history?limit=20&cursor=next');
});

test('wallet reads ask for holdings v2 with a slot floor and a fresh context only when asked', async () => {
  const wallet = (await signer()).address;
  const http = fetcher(url => Response.json(url.endsWith('/context') ? contextJson(wallet) : holdingsJson(wallet)));
  const client = new AccountWalletClient({baseUrl: '/api', accountId: ACCOUNT_ID, bearer: async () => TOKEN, fetch: http.fetch});
  assert.equal((await client.readContext()).embeddedSolanaWallet.status, 'candidate');
  await client.readContext({fresh: true});
  assert.deepEqual(http.seen.map(item => item.init.cache), ['default', 'no-store']);
  assert.equal(Object.keys(http.seen[1]!.init.headers as object).some(name => name.toLowerCase() === 'cache-control'), false,
    'the browser adds Cache-Control itself, so no preflight header is needed');
  assert.equal((await client.readHoldings({minimumObservedSlot: 812})).walletAddress, wallet);
  assert.equal(header(http.seen[2]!.init, 'x-trimmy-holdings-version'), '2');
  assert.equal(header(http.seen[2]!.init, 'x-trimmy-holdings-min-slot'), '812');
  await assert.rejects(client.readHoldings({minimumObservedSlot: 0}));
  const refused = new AccountWalletClient({baseUrl: '/api', accountId: ACCOUNT_ID, bearer: async () => TOKEN,
    fetch: fetcher(() => Response.json({error: {code: 'ACCOUNT_HOLDINGS_WALLET_MISSING', message: 'Missing', requestId: 'r'}}, {status: 409})).fetch});
  await assert.rejects(refused.readHoldings(), /ACCOUNT_HOLDINGS_WALLET_MISSING/);
  const signedOut = new AccountWalletClient({baseUrl: '/api', accountId: ACCOUNT_ID, bearer: async () => null, fetch: http.fetch});
  await assert.rejects(signedOut.readContext(), /TOKEN_UNAVAILABLE/);
});
