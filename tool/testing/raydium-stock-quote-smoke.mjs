/**
 * Explicit keyless read-only Raydium AAPLx/USDC quote smoke.
 * It can issue at most two compute GETs and has no transaction-builder URL.
 */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { setTimeout as pause } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import Fastify from 'fastify';
import { registerRaydiumStockQuoteRoute, RAYDIUM_STOCK_QUOTE_ROUTE } from '../../apps/api/src/raydium-stock-quote-route.ts';
import { RAYDIUM_STOCK_QUOTE_CONFIGURATION, RaydiumStockQuoteReader } from '../../apps/api/src/raydium-stock-quotes.ts';
import { STOCK_ESTIMATE_ASSET } from '../../apps/api/src/stock-estimates.ts';

if (process.argv.length !== 3 || process.argv[2] !== '--live-read-only') {
  console.error('Use --live-read-only for at most two keyless compute GETs. No transaction is requested.');
  process.exitCode = 1;
} else {
  const record = {
    schemaVersion: 1,
    startedAt: new Date().toISOString(),
    provider: 'raydium-trade-api',
    providerNetwork: 'solana:mainnet-beta',
    endpoint: 'compute/swap-base-in',
    transactionVersionRequested: 'V0',
    assetId: 'apple',
    variantMint: STOCK_ESTIMATE_ASSET.variantMint,
    inputCapsRaw: {
      buyUsdc: STOCK_ESTIMATE_ASSET.maxBuyInputRaw,
      sellAaplx: STOCK_ESTIMATE_ASSET.maxSellInputRaw,
    },
    localHttp: true,
    walletUsed: false,
    credentialsUsed: false,
    transactionRequested: false,
    transactionSigned: false,
    transactionSimulated: false,
    transactionBroadcast: false,
    executionEnabled: false,
    eligibility: 'unverified',
    providerRequests: [],
    buy: {outcome: 'not_attempted'},
    sell: {outcome: 'not_attempted'},
    checksPassed: false,
  };
  let app;
  try {
    const reader = new RaydiumStockQuoteReader({fetch: async (rawUrl, options) => {
      const url = new URL(String(rawUrl));
      assert.equal(url.origin + url.pathname, RAYDIUM_STOCK_QUOTE_CONFIGURATION.endpoint);
      assert.equal(options?.method, 'GET');
      assert.equal(options?.redirect, 'error');
      assert.deepEqual([...url.searchParams.keys()].sort(),
        ['amount', 'inputMint', 'outputMint', 'slippageBps', 'txVersion']);
      assert.equal(url.searchParams.get('slippageBps'), '50');
      assert.equal(url.searchParams.get('txVersion'), 'V0');
      assert.equal(url.searchParams.has('wallet'), false);
      assert.equal(url.searchParams.has('referrer'), false);
      const headers = new Headers(options?.headers);
      assert.equal(headers.has('authorization'), false);
      assert.equal(headers.has('x-api-key'), false);
      const observation = {
        startedAt: new Date().toISOString(),
        inputMint: url.searchParams.get('inputMint'),
        outputMint: url.searchParams.get('outputMint'),
        amountRaw: url.searchParams.get('amount'),
      };
      record.providerRequests.push(observation);
      const response = await fetch(url, options);
      observation.httpStatus = response.status;
      return response;
    }});
    app = Fastify({logger: false, ajv: {customOptions: {
      removeAdditional: false, coerceTypes: false, useDefaults: false,
    }}});
    registerRaydiumStockQuoteRoute(app, {quotes: reader});
    const origin = await app.listen({host: '127.0.0.1', port: 0});
    const path = (side, amountRaw) => RAYDIUM_STOCK_QUOTE_ROUTE + '?' + new URLSearchParams({
      assetId: 'apple', variantMint: STOCK_ESTIMATE_ASSET.variantMint, side, amountRaw,
    });
    assert.equal((await fetch(origin + path('buy', '10000000'), {method: 'HEAD'})).status, 404);
    assert.equal(record.providerRequests.length, 0);
    const quote = async (side, amountRaw) => {
      const response = await fetch(origin + path(side, amountRaw), {signal: AbortSignal.timeout(10_000)});
      const body = await response.json();
      const result = {httpStatus: response.status, outcome: response.status === 200 ? 'quote_available' : 'unavailable'};
      if (response.status === 200) {
        assert.equal(body.provider, 'raydium-trade-api');
        assert.equal(body.providerEndpoint, 'compute/swap-base-in');
        assert.equal(body.comparisonOnly, true);
        assert.equal(body.executionEnabled, false);
        assert.equal(body.executable, false);
        assert.equal(body.eligibility, 'unverified');
        assert.equal(body.walletChecked, false);
        assert.equal(body.networkFees, null);
        assert.equal(body.input.amountRaw, amountRaw);
        assert.equal(body.side, side);
        assert.equal(body.variantMint, STOCK_ESTIMATE_ASSET.variantMint);
        assert.ok(Date.parse(body.refreshAfter) > Date.now());
        result.quote = body;
      } else {
        assert.ok([429, 502, 503, 504].includes(response.status));
        assert.match(body.error.code, /^MARKET_[A-Z_]+$/);
        result.errorCode = body.error.code;
      }
      return result;
    };
    record.buy = await quote('buy', '10000000');
    const sellInput = record.buy.quote?.output?.estimatedAmountRaw;
    if (typeof sellInput === 'string' && BigInt(sellInput) > 0n &&
        BigInt(sellInput) <= BigInt(STOCK_ESTIMATE_ASSET.maxSellInputRaw)) {
      await pause(1_200);
      record.sell = await quote('sell', sellInput);
    } else {
      record.sell.reason = 'A usable bounded buy output was unavailable.';
    }
    assert.ok(record.providerRequests.length <= 2);
    record.checksPassed = true;
  } catch {
    record.errorCode = 'RAYDIUM_STOCK_QUOTE_SMOKE_FAILED';
    process.exitCode = 1;
  } finally {
    if (app) await app.close();
    record.finishedAt = new Date().toISOString();
    record.sourceSha256 = {};
    for (const path of [
      'apps/api/src/raydium-stock-quotes.ts',
      'apps/api/src/raydium-stock-quote-route.ts',
      'tool/testing/raydium-stock-quote-smoke.mjs',
    ]) {
      record.sourceSha256[path] = createHash('sha256')
        .update(await readFile(new URL('../../' + path, import.meta.url))).digest('hex');
    }
    const output = new URL('../../artifacts/verification/RAYDIUM_STOCK_QUOTE_SMOKE.json', import.meta.url);
    await mkdir(new URL('.', output), {recursive: true});
    await writeFile(output, JSON.stringify(record, null, 2) + '\n');
    console.log(JSON.stringify({
      checksPassed: record.checksPassed,
      buy: record.buy.outcome,
      sell: record.sell.outcome,
      providerRequests: record.providerRequests.length,
      transactionBroadcast: false,
      record: fileURLToPath(output),
    }));
  }
}
