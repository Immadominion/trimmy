import assert from 'node:assert/strict';
import test from 'node:test';
import Fastify from 'fastify';
import {STOCK_TRADING_ASSETS, STOCK_TOKEN_PROGRAM, findStockTradingAsset, findStockTradingAssetByMint} from '../src/stock-trading-catalog.js';
import {JupiterStockEstimates} from '../src/stock-estimates.js';
import type {StockEstimateInput} from '../src/stock-estimates.js';
import {JUPITER_QUOTE_ASSETS} from '../src/jupiter-quote-reader.js';
import {registerLiveStockRoutes} from '../src/live-stock-orders.js';
import {registerStockEstimateRoute} from '../src/stock-estimate-route.js';

const now = Date.parse('2026-09-25T10:00:00Z');
test('execution catalog pins unique issuer identities, programs and conservative caps', () => {
  assert.equal(STOCK_TRADING_ASSETS.length, 14);
  assert.equal(new Set(STOCK_TRADING_ASSETS.map(asset => asset.mint)).size, STOCK_TRADING_ASSETS.length);
  assert.equal(new Set(STOCK_TRADING_ASSETS.map(asset => asset.assetId)).size, STOCK_TRADING_ASSETS.length);
  for (const asset of STOCK_TRADING_ASSETS) {
    assert.ok(Object.isFrozen(asset));
    assert.equal(asset.decimals, 8);
    assert.equal(asset.tokenProgramAddress, STOCK_TOKEN_PROGRAM);
    assert.equal(asset.maxBuyInputRaw, '100000000');
    assert.equal(asset.maxSellInputRaw, '100000000');
    assert.equal(findStockTradingAsset(asset.assetId, asset.mint), asset);
    assert.equal(findStockTradingAssetByMint(asset.mint), asset);
    assert.equal(findStockTradingAsset(asset.assetId, JUPITER_QUOTE_ASSETS.USDC.mint), undefined);
  }
  assert.equal(findStockTradingAssetByMint('__proto__'), undefined);
  assert.equal(findStockTradingAsset('constructor', 'constructor'), undefined);
});

test('every catalog stock quotes both directions with its own mint and raw decimals', async () => {
  for (const asset of STOCK_TRADING_ASSETS) for (const side of ['buy', 'sell'] as const) {
    const buying = side === 'buy';
    const inputMint = buying ? JUPITER_QUOTE_ASSETS.USDC.mint : asset.mint;
    const outputMint = buying ? asset.mint : JUPITER_QUOTE_ASSETS.USDC.mint;
    const reader = new JupiterStockEstimates({access: {kind: 'keyless_research'}, now: () => now,
      fetch: async (rawUrl) => {
        const url = new URL(String(rawUrl));
        assert.equal(url.searchParams.get('inputMint'), inputMint);
        assert.equal(url.searchParams.get('outputMint'), outputMint);
        assert.equal(url.searchParams.get('taker'), null);
        return Response.json({inputMint, outputMint, inAmount: '1000000', outAmount: '200000', otherAmountThreshold: '199000',
          swapMode: 'ExactIn', slippageBps: 50, feeBps: 0, feeMint: inputMint, router: 'metis', transaction: null, taker: null});
      }});
    const quote = await reader.estimate({assetId: asset.assetId, variantMint: asset.mint, side, amountRaw: '1000000'});
    assert.equal(quote.assetId, asset.assetId);
    assert.equal(quote.input.mint, inputMint);
    assert.equal(quote.output.mint, outputMint);
    assert.equal(buying ? quote.output.symbol : quote.input.symbol, asset.symbol);
    assert.equal(buying ? quote.output.decimals : quote.input.decimals, 8);
    assert.equal(quote.amountUnits, 'raw_token_units');
  }
});

test('a valid mint paired with a different company is rejected before provider reads', async () => {
  let reads = 0;
  const reader = new JupiterStockEstimates({access: {kind: 'keyless_research'}, fetch: async () => {reads++; throw new Error('unexpected');}});
  for (const asset of STOCK_TRADING_ASSETS.slice(1)) {
    await assert.rejects(reader.estimate({assetId: 'apple', variantMint: asset.mint, side: 'buy', amountRaw: '1'}),
      {code: 'MARKET_INPUT_INVALID'});
  }
  const apple = STOCK_TRADING_ASSETS[0]!;
  for (const side of ['buy', 'sell'] as const) {
    for (const amountRaw of ['0', '01', '1.0', '1e6', '100000001']) {
      await assert.rejects(reader.estimate({assetId: apple.assetId, variantMint: apple.mint, side, amountRaw}), {code: 'MARKET_INPUT_INVALID'});
    }
  }
  assert.equal(reads, 0);
});

test('capabilities publish all admitted identities and limits even when deployment is disabled', async () => {
  const app = Fastify(); registerLiveStockRoutes(app);
  try {
    const result = await app.inject('/v1/trading/capabilities');
    assert.equal(result.statusCode, 200);
    const body = result.json();
    assert.equal(body.enabled, false);
    assert.equal(body.assets.length, STOCK_TRADING_ASSETS.length);
    for (const asset of STOCK_TRADING_ASSETS) {
      const actual = body.assets.find((item: {mint: string}) => item.mint === asset.mint);
      assert.equal(actual.assetId, asset.assetId);
      assert.equal(actual.maxSellInputRaw, asset.maxSellInputRaw);
    }
  } finally {await app.close();}
});

test('estimate HTTP boundary accepts Tesla and rejects cross-paired catalog identities', async () => {
  const asset = STOCK_TRADING_ASSETS.find(item => item.assetId === 'tesla')!;
  let passed: StockEstimateInput | undefined;
  const app = Fastify();
  registerStockEstimateRoute(app, {stockEstimates: {estimate: async input => {passed = input; throw Object.assign(new Error(), {code: 'test'});}}});
  try {
    const query = {assetId: asset.assetId, variantMint: asset.mint, side: 'buy', amountRaw: '1'};
    await app.inject('/v1/markets/stocks/estimate?' + new URLSearchParams(query));
    assert.deepEqual({...passed}, query);
    passed = undefined;
    const result = await app.inject('/v1/markets/stocks/estimate?' + new URLSearchParams({...query, assetId: 'apple'}));
    assert.equal(result.statusCode, 400);
    assert.equal(passed, undefined);
  } finally {await app.close();}
});
