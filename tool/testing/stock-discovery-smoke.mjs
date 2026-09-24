/** Explicit keyed provider read through a real temporary loopback HTTP API. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { setTimeout as pause } from 'node:timers/promises';
import { buildApp } from '../../apps/api/src/app.ts';
import { readStockDiscovery } from '../../apps/api/src/stock-discovery.ts';

const args = process.argv.slice(2);
if (args.length !== 1 || args[0] !== '--api-key') {
  console.error('Use --api-key with a server-only TOKENS_API_KEY. This performs stock metadata reads only.');
  process.exitCode = 1;
} else {
  const evidence = {schemaVersion: 1, startedAt: new Date().toISOString(), provider: 'tokens-xyz-v1',
    localHttp: true, query: 'Apple', walletUsed: false, transactionBroadcast: false,
    providerCalls: 0, passed: false};
  let app;
  try {
    const stockDiscovery = readStockDiscovery({TRIMMY_STOCK_DISCOVERY: 'tokens_xyz', TOKENS_API_KEY: process.env.TOKENS_API_KEY});
    app = buildApp({logger: false, stockDiscovery});
    const origin = await app.listen({host: '127.0.0.1', port: 0});
    evidence.providerCalls++;
    const search = await fetch(origin + '/v1/markets/stocks/search?query=Apple&limit=3', {signal: AbortSignal.timeout(10000)});
    evidence.searchStatus = search.status;
    const page = await search.json();
    if (search.status !== 200) {
      evidence.errorCode = typeof page?.error?.code === 'string' ? page.error.code : 'STOCK_SMOKE_FAILED';
      throw new Error('STOCK_SMOKE_FAILED');
    }
    assert.equal(page.executionEnabled, false); assert.equal(page.eligibility, 'unverified');
    assert.equal(page.mintVerification, 'not_checked'); assert.equal(page.provider, 'tokens-xyz-v1');
    evidence.resultCount = page.results.length;
    evidence.assets = page.results.map(asset => ({assetId: asset.assetId,
      variantCount: asset.variants.length, advisoryCount: asset.advisories.length}));
    if (page.results.length > 0) {
      await pause(1100);
      const assetId = page.results[0].assetId;
      evidence.providerCalls++;
      const variants = await fetch(origin + '/v1/markets/stocks/variants?assetId=' + encodeURIComponent(assetId),
        {signal: AbortSignal.timeout(10000)});
      evidence.variantsStatus = variants.status;
      const result = await variants.json();
      if (variants.status !== 200) {
        evidence.errorCode = typeof result?.error?.code === 'string' ? result.error.code : 'STOCK_SMOKE_FAILED';
        throw new Error('STOCK_SMOKE_FAILED');
      }
      assert.equal(result.assetId, assetId); assert.equal(result.executionEnabled, false);
      evidence.variantCount = result.variants.length;
    }
    const config = await (await fetch(origin + '/v1/config')).json();
    assert.equal(config.stockDiscoveryEnabled, true); assert.equal(config.capabilities.swapsEnabled, false);
    assert.deepEqual((await (await fetch(origin + '/v1/catalog')).json()).assets, []);
    const execute = await fetch(origin + '/v1/execute', {method: 'POST', headers: {'content-type': 'application/json'}, body: '{}'});
    assert.equal(execute.status, 503);
    evidence.financialMutationStatus = execute.status; evidence.passed = true;
  } catch {
    evidence.errorCode ??= 'STOCK_SMOKE_CONFIGURATION_OR_REQUEST_FAILED';
    process.exitCode = 1;
  } finally {
    if (app) await app.close();
    evidence.finishedAt = new Date().toISOString();
    const output = new URL('../../artifacts/verification/STOCK_DISCOVERY_SMOKE.json', import.meta.url);
    await mkdir(new URL('.', output), {recursive: true});
    await writeFile(output, JSON.stringify(evidence, null, 2) + '\n');
    console.log(JSON.stringify(evidence));
  }
}
