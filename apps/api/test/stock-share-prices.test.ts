import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { jupiterSharePrices, unpricedMints, withSharePrices } from '../src/stock-share-prices.js';
import { StockTokenDirectory, withCatalogSnapshot } from '../src/stock-token-directory.js';
import type { StockCatalogPage, StockDiscovery } from '../src/stock-discovery.js';

// Fixture mints: valid base58, not real tokens.
const FUND = 'Fund111111111111111111111111111111111111111';
const STOCK = 'Stok111111111111111111111111111111111111111';
const now = Date.parse('2026-09-28T13:00:00Z');

function catalog(): StockCatalogPage {
  return {
    discovery: {results: [
      {assetId: 'some-fund', category: 'etf', variants: [{mint: FUND}]},
      {assetId: 'some-stock', category: 'equity', variants: [{mint: STOCK}]},
    ]},
    cards: [
      {assetId: 'some-fund', name: 'Some Fund', symbol: 'SFND', imageUrl: null, stock: {priceUsd: null, changePercent24h: null, asOfUnixSeconds: null}, primaryVariant: null},
      {assetId: 'some-stock', name: 'Some Stock', symbol: 'STK', imageUrl: null, stock: null,
        primaryVariant: {mint: STOCK, symbol: 'STKx', logoUrl: null, priceUsd: 12.5, changePercent24h: 1}},
    ],
    offset: 0, total: 2, nextOffset: null,
  } as unknown as StockCatalogPage;
}
function jupiter(rows: Record<string, unknown>, calls: string[] = []) {
  return (async (url: string | URL) => {
    calls.push(String(url));
    return new Response(JSON.stringify(rows), {status: 200, headers: {'content-type': 'application/json'}});
  }) as unknown as typeof globalThis.fetch;
}

describe('share prices for unpriced Market cards', () => {
  it('asks only for the tokens of cards with no price at all', () => {
    assert.deepEqual(unpricedMints(catalog()), [FUND]);
  });

  it('reads the underlying share price, never the token price, and only while recent', async () => {
    const read = jupiterSharePrices({now: () => now, fetch: jupiter({
      [FUND]: {usdPrice: 999, stockData: {id: 'ondo', price: 104.11, updatedAt: '2026-09-28T12:59:00Z'}},
      [STOCK]: {usdPrice: 12.5, stockData: {price: 12.4, updatedAt: '2026-09-20T12:00:00Z'}},
    })});
    const prices = await read([FUND, STOCK]);
    assert.deepEqual(prices.get(FUND), {priceUsd: 104.11, asOfUnixSeconds: Date.parse('2026-09-28T12:59:00Z') / 1000});
    assert.equal(prices.has(STOCK), false, 'an eight-day-old reference is not shown');
  });

  it('ignores malformed rows and failed reads instead of failing', async () => {
    const odd = await jupiterSharePrices({now: () => now, fetch: jupiter({[FUND]: {stockData: {price: '104', updatedAt: 'soon'}}})})([FUND]);
    assert.equal(odd.size, 0);
    const down = await jupiterSharePrices({now: () => now, fetch: (async () => new Response('busy', {status: 429})) as unknown as typeof globalThis.fetch})([FUND]);
    assert.equal(down.size, 0);
  });

  it('asks for at most 50 tokens at a time and skips anything that is not a mint', async () => {
    const calls: string[] = [];
    const base58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    const mints = Array.from({length: 51}, (_, index) => `Fund${base58[index % 58]}${base58[Math.floor(index / 58)]}${'1'.repeat(37)}`);
    await jupiterSharePrices({now: () => now, fetch: jupiter({}, calls)})([...mints, 'not a mint']);
    assert.equal(calls.length, 2);
    assert.equal(new URL(calls[0]!).searchParams.get('ids')!.split(',').length, 50);
    assert.ok(!calls.join().includes('not a mint'));
  });

  it('fills only the unpriced card, as a share price with no invented day change', () => {
    const page = withSharePrices(catalog(), new Map([[FUND, {priceUsd: 104.11, asOfUnixSeconds: 1}], [STOCK, {priceUsd: 1, asOfUnixSeconds: 1}]]));
    assert.deepEqual(page.cards[0]!.stock, {priceUsd: 104.11, changePercent24h: null, asOfUnixSeconds: 1});
    assert.equal(page.cards[1]!.stock, null, 'a card with a token price keeps it and gains nothing');
    assert.equal(page.cards[1]!.primaryVariant!.priceUsd, 12.5);
    const same = catalog();
    assert.equal(withSharePrices(same, new Map()), same);
  });

  it('serves swept Market pages with those share prices, and still sweeps when the prices fail', async () => {
    const rpc = (async (_url: string | URL, init?: {body?: string}) => {
      const request = JSON.parse(String(init?.body)) as {id: string; params: [string[]]};
      return Response.json({jsonrpc: '2.0', id: request.id, result: {context: {slot: 7}, value: request.params[0].map(() => null)}});
    }) as unknown as typeof globalThis.fetch;
    const discovery = {search: async () => { throw new Error('unused'); }, variants: async () => { throw new Error('unused'); },
      catalog: async () => catalog()} as unknown as StockDiscovery;
    const asked: string[][] = [];
    const directory = new StockTokenDirectory({rpcUrl: 'https://rpc.example', discovery, fetch: rpc, now: () => now,
      sharePrices: async mints => { asked.push([...mints]); return new Map([[FUND, {priceUsd: 104.11, asOfUnixSeconds: 1}]]); }});
    await directory.refresh();
    assert.deepEqual(asked, [[FUND]]);
    assert.equal((await withCatalogSnapshot(discovery, directory).catalog!(0, 2)).cards[0]!.stock?.priceUsd, 104.11);
    const failing = new StockTokenDirectory({rpcUrl: 'https://rpc.example', discovery, fetch: rpc, now: () => now,
      sharePrices: async () => { throw new Error('down'); }});
    await failing.refresh();
    assert.equal((await withCatalogSnapshot(discovery, failing).catalog!(0, 2)).cards[0]!.stock?.priceUsd, null);
  });
});
