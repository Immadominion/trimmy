import assert from 'node:assert/strict';
import test from 'node:test';
import Fastify from 'fastify';
import {STOCK_TRADING_ASSETS, STOCK_TRADING_IDENTITIES, STOCK_TOKEN_PROGRAM, findStockTradingAsset, findStockTradingAssetByMint} from '../src/stock-trading-catalog.js';
import {STOCK_ISSUERS, STOCK_ISSUER_IDS, isStockIssuerId} from '../src/stock-issuers.js';
import {STOCK_UNAVAILABLE_REASONS} from '../src/stock-market-availability.js';
import {JupiterStockEstimates} from '../src/stock-estimates.js';
import type {StockEstimateInput} from '../src/stock-estimates.js';
import {JUPITER_QUOTE_ASSETS} from '../src/jupiter-quote-reader.js';
import {registerLiveStockRoutes} from '../src/live-stock-orders.js';
import {registerStockEstimateRoute} from '../src/stock-estimate-route.js';

const now = Date.parse('2026-09-25T10:00:00Z');
/** The first admitted identities. They must never be removed or re-bound (suspend instead). */
const ORIGINAL_XSTOCKS: Readonly<Record<string, string>> = {
  apple: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', tesla: 'XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB',
  nvidia: 'Xsc9qvGR1efVDFGLrVsmkzv3qi45LTBjeUKSPmx9qEh', microsoft: 'XspzcW1PRtgf6Wj92HCiZdjzKCyFekVD8P5Ueh3dRMX',
  amazon: 'Xs3eBt7uRfJX8QUs4suhyU8p2M6DoUDrJyWBa8LLZsg', alphabet: 'XsCPL9dNWBMvFtTmwcCA5v3xWPSMEBCszbQdiLLq6aN',
  meta: 'Xsa62P5mvPszXL1krVUnU5ar38bBSVcWAB6fmPCo5Zu', coinbase: 'Xs7ZdzSHLU9ftNJsii5fCeJhoRWSC32SQGzGQtePxNu',
  robinhood: 'XsvNBAYkrDRNhA7wPHQfX3ZUXZyZLdnCQDfHZ56bzpg', netflix: 'XsEH7wWfJJu2ZT3UCFeVfALnVA6CP5ur7Ee11KmzVpL',
  amd: 'XsXcJ6GZ9kVnjqGsjBnktRcuwMBmvKWh8S93RefZ1rF', microstrategy: 'XsP7xzNPvEHS1m6qfanPUGjNmdnmsLKEoNAnHjdxxyZ',
  circle: 'XsueG8BtpquVJX9LVLLEGuViXUungE6WmK5YZ3p3bd1', palantir: 'XsoBhf2ufR8fTyNSjqfU71DYGaE6Z3SUGAidpzriAA4',
};

test('execution catalog pins unique issuer identities, programs and conservative caps', () => {
  assert.equal(new Set(STOCK_TRADING_IDENTITIES.map(asset => asset.mint)).size, STOCK_TRADING_IDENTITIES.length);
  assert.equal(new Set(STOCK_TRADING_IDENTITIES.map(asset => asset.symbol.toLowerCase())).size, STOCK_TRADING_IDENTITIES.length);
  for (const [assetId, mint] of Object.entries(ORIGINAL_XSTOCKS)) {
    const asset = findStockTradingAssetByMint(mint);
    assert.equal(asset?.assetId, assetId);
    assert.equal(asset?.issuerId, 'xstocks');
  }
  // The first registry entries keep their order; later admissions only append.
  assert.deepEqual(STOCK_TRADING_IDENTITIES.slice(0, 14).map(asset => asset.mint), Object.values(ORIGINAL_XSTOCKS));
  for (const asset of STOCK_TRADING_IDENTITIES) {
    assert.ok(Object.isFrozen(asset));
    assert.ok(isStockIssuerId(asset.issuerId));
    assert.equal(asset.decimals, STOCK_ISSUERS[asset.issuerId].identity.decimals);
    assert.equal(asset.tokenProgramAddress, STOCK_TOKEN_PROGRAM);
    assert.equal(asset.maxBuyInputRaw, '100000000');
    assert.ok(BigInt(asset.maxSellInputRaw) >= 10n ** BigInt(asset.decimals));
    assert.ok(asset.transferFeeBps >= 0 && asset.transferFeeBps <= STOCK_ISSUERS[asset.issuerId].identity.maxTransferFeeBps);
    assert.equal(findStockTradingAssetByMint(asset.mint), asset);
    assert.equal(findStockTradingAsset(asset.assetId, asset.mint), asset.status === 'active' ? asset : undefined);
    assert.equal(findStockTradingAsset(asset.assetId, JUPITER_QUOTE_ASSETS.USDC.mint), undefined);
  }
  assert.deepEqual(STOCK_TRADING_ASSETS, STOCK_TRADING_IDENTITIES.filter(asset => asset.status === 'active'));
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
    assert.equal(buying ? quote.output.decimals : quote.input.decimals, asset.decimals);
    assert.equal(quote.amountUnits, 'raw_token_units');
  }
});

test('a valid mint paired with a different company is rejected before provider reads', async () => {
  let reads = 0;
  const reader = new JupiterStockEstimates({access: {kind: 'keyless_research'}, fetch: async () => {reads++; throw new Error('unexpected');}});
  for (const asset of STOCK_TRADING_ASSETS.filter(item => item.assetId !== 'apple')) {
    await assert.rejects(reader.estimate({assetId: 'apple', variantMint: asset.mint, side: 'buy', amountRaw: '1'}),
      {code: 'MARKET_INPUT_INVALID'});
  }
  const apple = STOCK_TRADING_ASSETS[0]!;
  for (const side of ['buy', 'sell'] as const) {
    // Buys are capped at 100 USDC; sells only by holdings and each order's price check.
    for (const amountRaw of ['0', '01', '1.0', '1e6', side === 'buy' ? '100000001' : '18446744073709551616']) {
      await assert.rejects(reader.estimate({assetId: apple.assetId, variantMint: apple.mint, side, amountRaw}), {code: 'MARKET_INPUT_INVALID'});
    }
  }
  assert.equal(reads, 0);
});

test('legacy capabilities keep the installed-app contract: active xStocks only, original fields', async () => {
  // Production validation (app.ts) rejects unknown fields instead of stripping them.
  const app = Fastify({ajv: {customOptions: {removeAdditional: false, coerceTypes: false, useDefaults: false}}}); registerLiveStockRoutes(app);
  try {
    const result = await app.inject('/v1/trading/capabilities');
    assert.equal(result.statusCode, 200);
    const body = result.json();
    assert.deepEqual(Object.keys(body).sort(), ['assets', 'enabled', 'maxBuyUsdc', 'minimumSolBalanceLamports', 'network']);
    assert.equal(body.enabled, false);
    const legacy = STOCK_TRADING_ASSETS.filter(asset => asset.issuerId === 'xstocks' && asset.route === 'aggregator');
    assert.equal(body.assets.length, legacy.length);
    assert.ok(body.assets.length <= 128 && result.body.length < 64 * 1024);
    for (const asset of legacy) {
      const actual = body.assets.find((item: {mint: string}) => item.mint === asset.mint);
      assert.deepEqual(actual, {assetId: asset.assetId, mint: asset.mint, symbol: asset.symbol, name: asset.name,
        decimals: asset.decimals, maxBuyInputRaw: asset.maxBuyInputRaw, maxSellInputRaw: asset.maxSellInputRaw});
    }
    assert.equal((await app.inject('/v1/trading/capabilities?schema=4')).statusCode, 400);
    assert.equal((await app.inject('/v1/trading/capabilities?other=1')).statusCode, 400);
  } finally {await app.close();}
});

test('schema 2 capabilities publish every active identity with its issuer disclosure', async () => {
  const app = Fastify(); registerLiveStockRoutes(app);
  try {
    const result = await app.inject('/v1/trading/capabilities?schema=2');
    assert.equal(result.statusCode, 200);
    const body = result.json();
    assert.equal(body.schemaVersion, 2);
    assert.equal(body.enabled, false);
    assert.equal(body.maxBuyUsdc, '100');
    assert.equal(body.assets.length, STOCK_TRADING_ASSETS.length);
    assert.ok(body.assets.length <= 600 && result.body.length < 512 * 1024);
    // Every issuer is described, with whether Trimmy offers it, so the Market can explain refusals.
    assert.deepEqual(body.issuers.map((issuer: {issuerId: string}) => issuer.issuerId).sort(), [...STOCK_ISSUER_IDS].sort());
    for (const issuer of body.issuers) {
      const expected = STOCK_ISSUERS[issuer.issuerId as 'xstocks'];
      assert.deepEqual(issuer, JSON.parse(JSON.stringify({...expected.disclosure, offered: expected.offer.status === 'offered',
        notOfferedReason: expected.offer.status === 'offered' ? null : expected.offer.reason, route: expected.identity.route})));
    }
    for (const asset of STOCK_TRADING_ASSETS) assert.equal(STOCK_ISSUERS[asset.issuerId].offer.status, 'offered');
    const tradeable = new Set(STOCK_TRADING_ASSETS.map(asset => asset.mint));
    assert.equal(new Set(body.unavailable.map((item: {mint: string}) => item.mint)).size, body.unavailable.length);
    for (const item of body.unavailable) {
      // An Ondo token refused only for a closed market carries its market state.
      const marketAware = item.issuerId === 'ondo' && ['market_closed', 'awaiting_review'].includes(item.reason) && item.symbol !== null;
      assert.deepEqual(Object.keys(item).sort(), marketAware ? ['issuerId', 'market', 'mint', 'reason', 'symbol'] : ['issuerId', 'mint', 'reason', 'symbol']);
      if (marketAware) assert.equal(item.reason === 'awaiting_review', item.market.status === 'open');
      assert.ok(!tradeable.has(item.mint));
      assert.ok((STOCK_UNAVAILABLE_REASONS as readonly string[]).includes(item.reason));
      if (item.issuerId !== null && STOCK_ISSUERS[item.issuerId as 'xstocks'].offer.status !== 'offered') assert.equal(item.reason, 'issuer_not_offered');
    }
    assert.ok([null, 'overnight', 'premarket', 'regular', 'postmarket', 'offhours'].includes(body.usMarket.session));
    for (const asset of STOCK_TRADING_ASSETS) {
      const {market, ...actual} = body.assets.find((item: {mint: string}) => item.mint === asset.mint);
      assert.deepEqual(actual, {assetId: asset.assetId, mint: asset.mint, symbol: asset.symbol, name: asset.name, issuerId: asset.issuerId,
        decimals: asset.decimals, maxBuyInputRaw: asset.maxBuyInputRaw, maxSellInputRaw: asset.maxSellInputRaw, transferFeeBps: asset.transferFeeBps,
        route: asset.route, minBuyInputRaw: asset.route === 'rfq' ? '2000000' : '1'});
      // Without live inputs the calendar decides: around the clock, or Ondo's US sessions.
      assert.equal(market.hours, asset.issuerId === 'ondo' ? 'us_sessions' : 'always');
      assert.ok(['open', 'paused', 'closed'].includes(market.status));
      if (asset.issuerId !== 'ondo') assert.equal(market.status, 'open');
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
