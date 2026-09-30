import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import Fastify from 'fastify';
import { orderPriceAcceptable } from '../src/stock-order-price.js';
import { registerStockPriceRoutes } from '../src/stock-price-routes.js';
import { JupiterTokenPrices, holdingPrice, orderReferencePrices, parseTokenPrice } from '../src/stock-token-prices.js';
import { stockTradingAssets } from '../src/stock-trading-catalog.js';

const now = Date.parse('2026-09-28T17:40:00Z');
// Shapes Jupiter's price data returned on 28 Sept 2026.
const PYPLX = {liquidity: 0.0515, usdPrice: 248953.97, decimals: 8,
  stockData: {id: 'xstocks', price: 54.235, updatedAt: '2026-09-28T17:35:20.786Z'},
  scaledUiConfig: {multiplier: 1.002299929594, newMultiplier: 1.0040286411936261, newMultiplierEffectiveAt: '2026-09-04T00:30:00Z'}};
const NFLXX = {liquidity: 2437.77, usdPrice: 70.5126, decimals: 8,
  stockData: {id: 'xstocks', price: 69.55, updatedAt: '2026-09-28T17:37:04.448Z'},
  scaledUiConfig: {multiplier: 1, newMultiplier: 10, newMultiplierEffectiveAt: '2025-11-16T23:55:00Z'}};
const SKHY = {liquidity: 2115818.39, usdPrice: 182.7417, decimals: 6,
  stockData: {id: 'backpack', price: 182.85, updatedAt: '2026-09-28T17:35:42.923Z'}};

const parse = (row: unknown) => parseTokenPrice(row, now);

describe('trusted token prices', () => {
  it('values a share at the issuer price, never an illiquid trade', () => {
    const pypl = parseTokenPrice(PYPLX, now);
    assert.deepEqual(holdingPrice(pypl), {usdPerShare: 54.235, source: 'issuer', asOf: Date.parse('2026-09-28T17:35:20.786Z')});
    // Without the issuer price, a trade on $0.05 of liquidity is not a price.
    assert.equal(holdingPrice(parseTokenPrice({...PYPLX, stockData: undefined}, now)), null);
    assert.equal(holdingPrice(parseTokenPrice({...SKHY, stockData: undefined}, now))?.source, 'market');
    // A deep market is what a holder could sell for, ahead of the issuer's mark.
    assert.deepEqual(holdingPrice(parse(SKHY)), {usdPerShare: 182.7417, source: 'market', asOf: null});
    assert.equal(holdingPrice(parse({...SKHY, liquidity: 50_000}))?.source, 'issuer');
    // An issuer price older than four days is not used.
    assert.equal(holdingPrice(parseTokenPrice({...NFLXX, stockData: {...NFLXX.stockData, updatedAt: '2026-09-23T00:00:00Z'}}, now)), null);
  });

  it('judges orders per raw token, with the current share multiplier', () => {
    const nflx = parseTokenPrice(NFLXX, now);
    assert.equal(nflx?.multiplier, 10);
    // Illiquid: only the issuer price, times ten shares per whole token.
    assert.deepEqual(orderReferencePrices(nflx, 10), [695.5]);
    assert.deepEqual(orderReferencePrices(nflx, 2), [139.1], 'on-chain multiplier wins over the feed');
    assert.deepEqual(orderReferencePrices(nflx, NaN), []);
    assert.deepEqual(orderReferencePrices(parseTokenPrice(SKHY, now), 1), [182.7417]);
    // Before a multiplier change takes effect, the old one applies.
    assert.equal(parseTokenPrice({...NFLXX, scaledUiConfig: {...NFLXX.scaledUiConfig, newMultiplierEffectiveAt: '2026-10-01T00:00:00Z'}}, now)?.multiplier, 1);
    assert.deepEqual(orderReferencePrices(parseTokenPrice({...NFLXX, scaledUiConfig: {multiplier: 'x'}}, now), 10), [695.5]);
  });

  it('uses one valuation policy when issuer and deep market disagree', () => {
    const p=parse({...SKHY, usdPrice:200, stockData:{...SKHY.stockData,price:100}});
    assert.deepEqual(orderReferencePrices(p,1),[200]);
    const base={buying:false,inputRaw:'100000000',outputRaw:'100000000',decimals:8,transferFeeBps:0,swapFeeBps:0};
    assert.equal(orderPriceAcceptable({...base,referencesUsd:orderReferencePrices(p,1)}),false);
  });

  it('refuses a PYPLx buy at sixty times the share price', () => {
    const references = orderReferencePrices(parseTokenPrice(PYPLX, now), 1.0040286411936261);
    // $100 for 0.03 PYPLx, about $3,337 a share: the illiquid market price no longer excuses it.
    const order = {buying: true, inputRaw: '100000000', outputRaw: '3000000', decimals: 8, transferFeeBps: 0, swapFeeBps: 10,
      priceImpactPct: '0'} as const;
    assert.equal(orderPriceAcceptable({...order, referencesUsd: references}), false);
    // About $54.40 a share passes.
    assert.equal(orderPriceAcceptable({...order, outputRaw: String(Math.round(100 / 54.4 / 1.004 * 1e8)), referencesUsd: references}), true);
  });

  it('caches reads, bounds a failing provider, and never throws', async () => {
    let calls = 0, clock = now, fail = false;
    const mint = stockTradingAssets()[0]!.mint;
    const prices = new JupiterTokenPrices({now: () => clock, fetch: (async (url: string) => {
      calls += 1;
      assert.match(url, /lite-api\.jup\.ag\/price\/v3\?ids=/);
      if (fail) throw new Error('offline');
      return Response.json({[mint]: SKHY});
    }) as unknown as typeof fetch});
    assert.equal((await prices.read([mint, mint, 'not a mint'])).size, 1);
    await prices.read([mint]);
    assert.equal(calls, 1);
    fail = true;
    clock += 60_000;
    assert.equal((await prices.read([mint])).size, 1, 'the last read serves briefly');
    assert.equal((await prices.readForOrder([mint])).size, 0, 'failed refresh cannot authorize trading from stale holdings data');
    clock += 5 * 60_000;
    assert.equal((await prices.read([mint])).size, 0, 'then nothing');
  });
});

describe('holding prices route', () => {
  it('prices Trimmy stock tokens per displayed share and leaves the rest out', async () => {
    const [first, second] = stockTradingAssets();
    const app = Fastify();
    registerStockPriceRoutes(app, {read: async mints => new Map(mints.map(mint =>
      [mint, parseTokenPrice(mint === first!.mint ? SKHY : PYPLX, now)!]))}, () => now);
    const unknown = '1'.repeat(32);
    const response = await app.inject({method: 'GET', url: `/v1/markets/stocks/prices?mints=${first!.mint},${second!.mint},${unknown}`});
    assert.equal(response.statusCode, 200);
    assert.equal(response.headers['cache-control'], 'public, max-age=30');
    assert.deepEqual(response.json(), {schema: 1, observedAt: '2026-09-28T17:40:00.000Z', prices: [
      {mint: first!.mint, usdPerShare: 182.7417, source: 'market', asOf: null},
      {mint: second!.mint, usdPerShare: 54.235, source: 'issuer', asOf: '2026-09-28T17:35:20.786Z'},
    ]});
    assert.equal((await app.inject({method: 'GET', url: '/v1/markets/stocks/prices?mints=bad'})).statusCode, 400);
    const many = Array.from({length: 51}, () => first!.mint).join(',');
    assert.equal((await app.inject({method: 'GET', url: `/v1/markets/stocks/prices?mints=${many}`})).statusCode, 400);
    const off = Fastify();
    registerStockPriceRoutes(off);
    assert.equal((await off.inject({method: 'GET', url: `/v1/markets/stocks/prices?mints=${first!.mint}`})).statusCode, 503);
  });
});
