import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PublicTokenHolders, HoldersError, registerPublicHolders} from '../src/public-token-holders.js';
import Fastify from 'fastify';
const mint = 'XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB';
const owner = 'FMmaHPDL47V1gXsfh9WjgAT7Er3dfDvarQubTU1Jxc1r';
const keys = ['So11111111111111111111111111111111111111112', 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'];
function mock(options: {snsFails?: boolean; wrongMint?: boolean; wrongSlot?: boolean} = {}) {
  const methods: string[] = [];
  const fetcher = (async (url, init) => {
    if (String(url).startsWith('https://sns-api.bonfida.com/')) return Response.json(options.snsFails ? {} : {[owner]: 'best-intern'}, {status: options.snsFails ? 503 : 200});
    const body = JSON.parse(String(init?.body)); methods.push(body.method);
    const result = body.method === 'getTokenLargestAccounts'
      ? {context: {slot: 100}, value: keys.map(address => ({address}))}
      : {context: {slot: options.wrongSlot ? 99 : 101}, value: keys.map((_, i) => ({owner: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA', data: {parsed: {type: 'account', info: {owner, mint: options.wrongMint ? keys[0] : mint, tokenAmount: {amount: i ? '500000' : '9007199254740993', decimals: 6}}}}}))};
    return Response.json({jsonrpc: '2.0', id: body.id, result});
  }) as typeof fetch;
  return {reader: new PublicTokenHolders('https://rpc.example', fetcher), methods};
}
test('resolves account owners, merges without float loss, names and caches snapshot', async () => {
  const {reader, methods} = mock();
  const result = await reader.holders(mint);
  assert.equal(result.complete, false); assert.equal(result.scope, 'largest-20-token-accounts');
  assert.equal(result.sampledAccounts, 2); assert.equal(result.holders.length, 1);
  assert.deepEqual(result.holders[0], {owner, primaryDomain: 'best-intern.sol', amount: '9007199255.240993', tokenAccounts: 2});
  assert.equal(result.slot, '101');
  await reader.holders(mint); assert.deepEqual(methods, ['getTokenLargestAccounts', 'getMultipleAccounts']);
});
test('SNS outage leaves public holder balances intact', async () => {
  const {reader} = mock({snsFails: true}); const result = await reader.holders(mint);
  assert.equal(result.holders[0]?.primaryDomain, null); assert.ok(result.holders[0]?.amount);
});
test('rejects token account mint mismatch and older slots', async () => {
  for (const options of [{wrongMint: true}, {wrongSlot: true}]) {
    await assert.rejects(mock(options).reader.holders(mint), HoldersError);
  }
});
test('public route validates input and safely reports missing infrastructure', async () => {
  const app = Fastify(); registerPublicHolders(app);
  assert.equal((await app.inject('/v1/markets/stocks/holders?mint=no')).statusCode, 400);
  assert.equal((await app.inject(`/v1/markets/stocks/holders?mint=${mint}`)).statusCode, 503);
  await app.close();
});
