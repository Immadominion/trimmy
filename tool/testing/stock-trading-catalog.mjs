/** Read-only issuer / mainnet / quote verification. No wallet, taker, signer or execution endpoint. */
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {setTimeout as pause} from 'node:timers/promises';
import {STOCK_TRADING_ASSETS, STOCK_TOKEN_PROGRAM} from '../../apps/api/src/stock-trading-catalog.ts';
import {JUPITER_QUOTE_ASSETS} from '../../apps/api/src/jupiter-quote-reader.ts';

if (process.argv.length !== 3 || process.argv[2] !== '--read-only') throw Error('Use --read-only. This checks public identities and indicative quotes only.');
async function json(url, init) {
  const response = await fetch(url, {...init, redirect: 'error', signal: AbortSignal.timeout(15000)});
  if (!response.ok) throw Error(`READ_HTTP_${response.status}`);
  const bytes = await response.arrayBuffer();
  assert.ok(bytes.byteLength < 524288);
  return JSON.parse(new TextDecoder().decode(bytes));
}
async function rpc(method, params = []) {
  assert.ok(['getGenesisHash', 'getMultipleAccounts'].includes(method));
  const result = await json('https://api.mainnet-beta.solana.com', {method: 'POST', headers: {'content-type': 'application/json'},
    body: JSON.stringify({jsonrpc: '2.0', id: 1, method, params})});
  assert.equal(result.jsonrpc, '2.0'); assert.equal(result.id, 1); assert.equal(result.error, undefined);
  return result.result;
}
const evidence = {observedAt: new Date().toISOString(), walletUsed: false, transactionBroadcast: false, assets: []};
assert.equal(await rpc('getGenesisHash'), '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d');
const mints = await rpc('getMultipleAccounts', [STOCK_TRADING_ASSETS.map(asset => asset.mint), {encoding: 'jsonParsed', commitment: 'finalized'}]);
evidence.slot = mints.context.slot;
for (const [index, asset] of STOCK_TRADING_ASSETS.entries()) {
  const issuer = await json(asset.issuerUrl);
  assert.equal(issuer.symbol, asset.symbol);
  const deployments = issuer.deployments.filter(row => row.network === 'Solana');
  assert.equal(deployments.length, 1); assert.equal(deployments[0].address, asset.mint);
  const account = mints.value[index], info = account.data.parsed.info;
  assert.equal(account.owner, STOCK_TOKEN_PROGRAM); assert.equal(info.decimals, asset.decimals); assert.equal(info.isInitialized, true);
  const extensions = info.extensions;
  assert.equal(extensions.find(e => e.extension === 'defaultAccountState')?.state.accountState, 'initialized');
  assert.equal(extensions.find(e => e.extension === 'pausableConfig')?.state.paused, false);
  assert.equal(extensions.find(e => e.extension === 'transferHook')?.state.programId, null);
  const results = [];
  for (const side of ['buy', 'sell']) {
    const inputMint = side === 'buy' ? JUPITER_QUOTE_ASSETS.USDC.mint : asset.mint;
    const outputMint = side === 'buy' ? asset.mint : JUPITER_QUOTE_ASSETS.USDC.mint;
    const amount = side === 'buy' ? '2000000' : results[0].outAmount;
    const query = new URLSearchParams({inputMint, outputMint, amount, slippageBps: '50', excludeRouters: 'jupiterz,dflow,okx'});
    const quote = await json('https://api.jup.ag/swap/v2/order?' + query);
    assert.equal(quote.inputMint, inputMint); assert.equal(quote.outputMint, outputMint); assert.equal(quote.inAmount, amount);
    assert.equal(quote.router, 'metis'); assert.equal(quote.transaction, null); assert.equal(quote.taker, null);
    assert.ok(BigInt(quote.outAmount) > 0n); assert.ok(BigInt(quote.otherAmountThreshold) > 0n);
    results.push({side, inAmount: amount, outAmount: quote.outAmount, minimumOutput: quote.otherAmountThreshold, router: quote.router});
    await pause(2200);
  }
  evidence.assets.push({assetId: asset.assetId, symbol: asset.symbol, mint: asset.mint, issuerSource: asset.issuerUrl,
    decimals: info.decimals, tokenProgram: account.owner, extensions: extensions.map(e => e.extension), quotes: results});
  console.log(asset.symbol + ': issuer + mainnet identity + buy/sell quotes passed');
}
await mkdir('artifacts/verification', {recursive: true});
await writeFile('artifacts/verification/stock-trading-catalog-2026-09-25.json', JSON.stringify(evidence, null, 2) + '\n');
