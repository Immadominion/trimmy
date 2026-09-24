/** Explicit read-only provider smoke through a real temporary loopback HTTP API. */
import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { buildApp } from '../../apps/api/src/app.ts';
import { readMarketEstimates } from '../../apps/api/src/market-estimates.ts';
const args = process.argv.slice(2);
if (args.length !== 1 || !['--keyless-research', '--api-key'].includes(args[0])) {
  console.error('Use --keyless-research for one public quote, or --api-key with JUPITER_API_KEY in the server environment.');
  process.exitCode = 1;
} else {
  const mode = args[0] === '--api-key' ? 'api_key' : 'keyless_research';
  const access = {TRIMMY_MARKET_QUOTES: mode, ...(mode === 'api_key' ? {JUPITER_API_KEY: process.env.JUPITER_API_KEY} : {})};
  const startedAt = new Date().toISOString();
  const record = {schemaVersion: 1, startedAt, mode, inputAsset: 'SOL', outputAsset: 'USDC', inputAmountRaw: '10000000',
    providerNetwork: 'solana:mainnet-beta', localHttp: true, walletUsed: false, transactionRequested: false,
    transactionSigned: false, transactionBroadcast: false, passed: false};
  let app;
  try {
    const marketEstimates = readMarketEstimates(access);
    app = buildApp({logger: false, marketEstimates});
    const origin = await app.listen({host: '127.0.0.1', port: 0});
    const response = await fetch(origin + '/v1/markets/estimate?inputAsset=SOL&outputAsset=USDC&amountRaw=10000000', {signal: AbortSignal.timeout(10000)});
    record.httpStatus = response.status;
    const body = await response.json();
    if (response.status !== 200) {
      record.errorCode = typeof body?.error?.code === 'string' ? body.error.code : 'MARKET_SMOKE_FAILED';
      throw new Error('MARKET_SMOKE_FAILED');
    }
    assert.equal(body.executable, false); assert.equal(body.walletChecked, false); assert.equal(body.networkFees, null);
    assert.equal(body.input.amountRaw, '10000000'); assert.equal(body.output.symbol, 'USDC');
    assert.ok(Date.parse(body.refreshAfter) > Date.now());
    const config = await (await fetch(origin + '/v1/config')).json();
    assert.equal(config.marketEstimatesEnabled, true); assert.equal(config.capabilities.swapsEnabled, false);
    assert.equal(config.capabilities.liveWalletsEnabled, false);
    const mutation = await fetch(origin + '/v1/execute', {method: 'POST', headers: {'content-type': 'application/json'}, body: '{}'});
    assert.equal(mutation.status, 503);
    record.quote = body; record.financialMutationStatus = mutation.status; record.passed = true;
  } catch {
    record.errorCode ??= 'MARKET_SMOKE_FAILED'; process.exitCode = 1;
  } finally {
    if (app) await app.close();
    const output = new URL('../../artifacts/verification/MARKET_ESTIMATE_SMOKE.json', import.meta.url);
    await mkdir(new URL('.', output), {recursive: true});
    await writeFile(output, JSON.stringify(record, null, 2) + '\n');
    console.log(JSON.stringify({passed: record.passed, httpStatus: record.httpStatus ?? null, errorCode: record.errorCode ?? null,
      record: fileURLToPath(output), transactionBroadcast: false}));
  }
}
