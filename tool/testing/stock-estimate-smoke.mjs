/** Explicit, bounded, no-wallet mainnet quote reads through the composed HTTP API.
 * This never requests, signs or broadcasts a transaction. No retry loop.
 */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { setTimeout as pause } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { buildApp } from '../../apps/api/src/app.ts';
import { JupiterQuoteReader } from '../../apps/api/src/jupiter-quote-reader.ts';
import { JupiterMarketEstimates } from '../../apps/api/src/market-estimates.ts';
import { JupiterStockEstimates, STOCK_ESTIMATE_ASSET } from '../../apps/api/src/stock-estimates.ts';

const args = process.argv.slice(2);
if (args.length !== 1 || !['--keyless-research', '--api-key'].includes(args[0])) {
  console.error('Use --keyless-research or --api-key (JUPITER_API_KEY server environment). At most two quote requests; no transaction.');
  process.exitCode = 1;
} else {
  const access = args[0] === '--keyless-research' ? {kind: 'keyless_research'} : {kind: 'api_key', apiKey: process.env.JUPITER_API_KEY};
  const record = {schemaVersion: 1, startedAt: new Date().toISOString(), accessMode: access.kind,
    providerNetwork: 'solana:mainnet-beta', localHttp: true, assetId: 'apple', variantMint: STOCK_ESTIMATE_ASSET.variantMint,
    walletUsed: false, transactionRequested: false, transactionSigned: false, transactionBroadcast: false,
    executionEnabled: false, eligibility: 'unverified', providerRequests: [], checksPassed: false,
    buy: {outcome: 'not_attempted'}, sell: {outcome: 'not_attempted'}};
  let app;
  try {
    const reader = new JupiterQuoteReader({access, fetch: async (url, options) => {
      const u = new URL(String(url));
      assert.equal(u.origin + u.pathname, 'https://api.jup.ag/swap/v2/order');
      assert.deepEqual([...u.searchParams.keys()].sort(), ['amount', 'inputMint', 'outputMint']);
      assert.equal(options.method, 'GET');
      const read = {startedAt: new Date().toISOString(), inputMint: u.searchParams.get('inputMint'),
        outputMint: u.searchParams.get('outputMint'), amountRaw: u.searchParams.get('amount')};
      record.providerRequests.push(read);
      const result = await fetch(url, options); read.httpStatus = result.status; return result;
    }});
    app = buildApp({logger: false, stockEstimates: new JupiterStockEstimates(reader), marketEstimates: new JupiterMarketEstimates(reader),
      browserOrigins: ['https://trimmy.example']});
    const origin = await app.listen({host: '127.0.0.1', port: 0});
    const path = (side, amountRaw) => '/v1/markets/stocks/estimate?' + new URLSearchParams({assetId: 'apple',
      variantMint: STOCK_ESTIMATE_ASSET.variantMint, side, amountRaw});
    assert.equal((await fetch(origin + path('buy', '10000000'), {method: 'HEAD'})).status, 404);
    assert.equal((await fetch(origin + path('buy', '10000000'), {headers: {origin: 'https://unlisted.example'}})).status, 403);
    assert.equal(record.providerRequests.length, 0);
    const quote = async (side, amountRaw) => {
      const response = await fetch(origin + path(side, amountRaw), {signal: AbortSignal.timeout(10000)});
      const body = await response.json();
      const result = {httpStatus: response.status, outcome: response.status === 200 ? 'quote_available' : 'unavailable'};
      if (response.status === 200) {
        assert.equal(body.executionEnabled, false); assert.equal(body.executable, false);
        assert.equal(body.eligibility, 'unverified'); assert.equal(body.walletChecked, false); assert.equal(body.networkFees, null);
        assert.equal(body.input.amountRaw, amountRaw); assert.equal(body.assetId, 'apple'); assert.equal(body.side, side);
        assert.equal(body.variantMint, STOCK_ESTIMATE_ASSET.variantMint); assert.equal(body.amountUnits, 'raw_token_units');
        assert.ok(Date.parse(body.refreshAfter) > Date.now()); result.quote = body;
      } else {
        assert.ok([429, 502, 503, 504].includes(response.status));
        assert.match(body.error.code, /^MARKET_[A-Z_]+$/); result.errorCode = body.error.code;
      }
      return result;
    };
    record.buy = await quote('buy', '10000000');
    if (record.buy.quote && BigInt(record.buy.quote.output.estimatedAmountRaw) <= BigInt(STOCK_ESTIMATE_ASSET.maxSellInputRaw)) {
      // Independent indicative sell, not a held balance or realized round trip.
      await pause(2200);
      record.sell = await quote('sell', record.buy.quote.output.estimatedAmountRaw);
    } else record.sell.reason = 'A usable buy amount within the bounded sell input cap was unavailable.';
    assert.ok(record.providerRequests.length <= 2);
    const config = await (await fetch(origin + '/v1/config')).json();
    assert.equal(config.stockEstimatesEnabled, true); assert.equal(config.capabilities.swapsEnabled, false);
    assert.equal(config.capabilities.liveWalletsEnabled, false);
    const mutation = await fetch(origin + '/v1/execute', {method: 'POST', headers: {'content-type': 'application/json'}, body: '{}'});
    assert.equal(mutation.status, 503); record.financialMutationStatus = mutation.status;
    assert.deepEqual((await (await fetch(origin + '/v1/catalog')).json()).assets, []);
    record.checksPassed = true;
  } catch {
    record.errorCode = 'STOCK_ESTIMATE_SMOKE_FAILED'; process.exitCode = 1;
  } finally {
    if (app) await app.close();
    record.finishedAt = new Date().toISOString();
    record.sourceSha256 = {};
    for (const path of ['apps/api/src/jupiter-quote-reader.ts', 'apps/api/src/stock-estimates.ts', 'apps/api/src/stock-estimate-route.ts',
      'apps/api/src/market-estimates.ts', 'apps/api/src/app.ts', 'apps/api/src/browser-origins.ts', 'tool/testing/stock-estimate-smoke.mjs']) {
      record.sourceSha256[path] = createHash('sha256').update(await readFile(new URL('../../' + path, import.meta.url))).digest('hex');
    }
    const output = new URL('../../artifacts/verification/STOCK_ESTIMATE_SMOKE.json', import.meta.url);
    await mkdir(new URL('.', output), {recursive: true});
    await writeFile(output, JSON.stringify(record, null, 2) + '\n');
    console.log(JSON.stringify({checksPassed: record.checksPassed, buy: record.buy.outcome, sell: record.sell.outcome,
      providerRequests: record.providerRequests.length, record: fileURLToPath(output), transactionBroadcast: false}));
  }
}
