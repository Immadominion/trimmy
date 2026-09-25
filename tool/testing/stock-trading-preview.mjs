/** A real unsigned review + simulation against public wallet state. Never signs or submits. */
import {mkdir, writeFile} from 'node:fs/promises';
import {setTimeout as pause} from 'node:timers/promises';
import {address} from '@solana/kit';
import {LiveStockOrders} from '../../apps/api/src/live-stock-orders.ts';
import {STOCK_TRADING_ASSETS} from '../../apps/api/src/stock-trading-catalog.ts';

const [flag, wallet, ...specs] = process.argv.slice(2);
if (flag !== '--read-only' || !wallet || !specs.length) throw Error('Use --read-only PUBLIC_WALLET SYMBOL:buy|sell:RAW_AMOUNT ...');
address(wallet);
const requests = specs.map(spec => {
  const [symbol, side, amountRaw] = spec.split(':');
  const asset = STOCK_TRADING_ASSETS.find(asset => asset.symbol === symbol);
  if (!asset || !['buy', 'sell'].includes(side) || !/^[1-9][0-9]{0,8}$/.test(amountRaw ?? '')) throw Error('INVALID_REQUEST');
  return {asset, side, amountRaw};
});
const store = {
  read: async () => null,
  create: async (user, id, selectedWallet, review) => ({id, user_id: user, wallet: selectedWallet, review,
    unsignedTransaction: '', expires_at: review.expiresAt, status: 'reviewed', signature: null}),
  begin: async () => {throw Error('SUBMISSION_FORBIDDEN');},
  resolve: async () => {throw Error('PERSISTENCE_FORBIDDEN');},
};
const allowedRpc = new Set(['getGenesisHash', 'getBlockHeight', 'getBalance', 'getMultipleAccounts',
  'getAccountInfo', 'isBlockhashValid', 'simulateTransaction']);
const readOnlyFetch = async (url, options) => {
  const selected = new URL(String(url));
  if (selected.origin === 'https://api.jup.ag') {
    if (selected.pathname !== '/swap/v2/order' || options.method !== 'GET') throw Error('SUBMISSION_FORBIDDEN');
  } else if (selected.origin === 'https://api.mainnet-beta.solana.com') {
    if (!allowedRpc.has(JSON.parse(options.body).method)) throw Error('RPC_WRITE_FORBIDDEN');
  } else throw Error('UNKNOWN_PROVIDER');
  return fetch(url, options);
};
const service = new LiveStockOrders({rpcUrl: 'https://api.mainnet-beta.solana.com', store, fetch: readOnlyFetch});
const evidence = {observedAt: new Date().toISOString(), signed: false, transactionBroadcast: false, persisted: false, results: []};
for (const {asset, side, amountRaw} of requests) {
  const start = Date.now();
  try {
    const order = await service.preview('12345678-1234-4567-8123-123456789abc', wallet,
      {assetId: asset.assetId, variantMint: asset.mint, side, amountRaw});
    const result = {symbol: asset.symbol, side, status: order.status, terms: order.review.terms,
      observationSlot: order.review.evidence.observationSlot, simulationSlot: order.review.evidence.simulationSlot, durationMs: Date.now() - start};
    evidence.results.push(result); console.log(JSON.stringify(result));
  } catch (error) {
    const result = {symbol: asset.symbol, side, status: 'failed', code: error.code ?? error.name, durationMs: Date.now() - start};
    evidence.results.push(result); console.log(JSON.stringify(result)); process.exitCode = 1;
  }
  await pause(2500);
}
await mkdir('artifacts/verification', {recursive: true});
await writeFile('artifacts/verification/stock-trading-preview-2026-09-25.json', JSON.stringify(evidence, null, 2) + '\n');
