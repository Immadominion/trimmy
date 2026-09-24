import assert from 'node:assert/strict';
import {it} from 'node:test';
import {TokensStockFacts, StockFactsError} from '../src/stock-facts.js';
import {buildApp} from '../src/app.js';
const mint = 'XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB';
const now = Date.parse('2026-09-24T12:00:00Z');
const market = {price: 380, priceChange24hPercent: -1.2, holder: 40701, volume24hUSD: 100000,
  liquidity: 2000000, marketCap: 64000000, lastFetchedAt: now - 30000};
function reader(options: {chart?: Record<string, unknown>; noChart?: boolean; noMetrics?: boolean} = {}) {
  const calls: URL[] = [];
  let clock = now;
  const api = new TokensStockFacts({apiKey: 'test-not-live', now: () => clock, wait: async ms => { clock += ms; },
    fetch: async input => {
      const url = new URL(String(input)); calls.push(url);
      if (!url.pathname.endsWith('/ohlcv')) return Response.json({asset: {assetId: 'tesla', category: 'equity',
        description: 'Tesla makes electric vehicles.', canonicalMarket: {marketCap: 1.5e12},
        primaryVariant: {mint, symbol: 'TSLAx', market: options.noMetrics ? {} : market}}});
      if (options.noChart) return new Response('', {status: 503});
      return Response.json({assetId: 'tesla', mint, interval: url.searchParams.get('interval'),
        candles: [{time: now / 1000 - 900, close: 378}, {time: now / 1000, close: 380}], ...options.chart});
    }});
  return {api, calls};
}
it('reads a mint-specific chart and separates token cap from company cap', async () => {
  const {api, calls} = reader();
  const data = await api.insight({assetId: 'tesla', mint, period: 'day'});
  assert.equal(data.holders, 40701); assert.equal(data.priceUsd, 380);
  assert.equal(data.asOfUnixSeconds, (now - 30000) / 1000);
  assert.equal(data.tokenMarketCapUsd, 64000000); assert.equal(data.stockMarketCapUsd, 1.5e12);
  assert.equal(data.changePercent24h, -1.2); assert.equal(data.points.length, 2);
  assert.equal(calls[1]!.pathname, '/v1/assets/tesla/ohlcv');
  assert.equal(calls[1]!.searchParams.get('mint'), mint);
  assert.equal(calls[1]!.searchParams.get('interval'), '1H');
  await api.insight({assetId: 'tesla', mint, period: 'day'});
  assert.equal(calls.length, 2, 'cached repeat avoids provider reads');
});
it('chart identity errors and outages preserve facts but never show the wrong chart', async () => {
  for (const options of [{noChart: true}, {chart: {mint: 'other'}}, {chart: {assetId: 'apple'}},
    {chart: {candles: [{time: now / 1000, close: 1}, {time: now / 1000, close: 2}]}}]) {
    const data = await reader(options).api.insight({assetId: 'tesla', mint, period: 'week'});
    assert.equal(data.holders, 40701); assert.equal(data.chartStatus, 'unavailable');
    assert.deepEqual(data.points, []);
  }
});
it('missing metrics remain null; zero is data; another asset mint is rejected', async () => {
  const data = await reader({noMetrics: true, chart: {candles: []}}).api.insight({assetId: 'tesla', mint, period: 'month'});
  assert.equal(data.priceUsd, null); assert.equal(data.holders, null); assert.equal(data.chartStatus, 'empty');
  await assert.rejects(reader().api.insight({assetId: 'tesla', mint: 'So11111111111111111111111111111111111111112', period: 'day'}),
    (error: unknown) => error instanceof StockFactsError && error.code === 'STOCK_FACTS_INPUT_INVALID');
});
it('validates the public insight route and never changes execution capability', async () => {
  const {api} = reader(); const app = buildApp({logger: false, stockFacts: api});
  try {
    const response = await app.inject(`/v1/markets/stocks/insight?assetId=tesla&mint=${mint}&period=year`);
    assert.equal(response.statusCode, 200); assert.equal(response.json().executionEnabled, false);
    assert.equal(response.json().period, 'year');
    assert.equal((await app.inject(`/v1/markets/stocks/insight?assetId=tesla&mint=${mint}&period=bogus`)).statusCode, 400);
    assert.equal((await app.inject('/v1/markets/stocks/insight?assetId=tesla')).statusCode, 400);
  } finally { await app.close(); }
});
