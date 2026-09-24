import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { it } from 'node:test';
import { address, getAddressDecoder, getCompiledTransactionMessageEncoder, getTransactionEncoder } from '@solana/kit';
import { findAssociatedTokenPda } from '@solana-program/token-2022';
import { openStockResearchWallet, STOCK_WALLET_GENESIS } from './stock-order-wallet.mjs';
import { MainnetStockOrderInspection, MAINNET_STOCK_RPC, REQUIRED_USDC_RAW, SOL_RESERVE_LAMPORTS, USDC_MINT, StockInspectionError } from './mainnet-stock-order-inspection.mjs';
import { STOCK_ESTIMATE_ASSET } from '../../apps/api/src/stock-estimates.ts';
const TOKEN = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const now = Date.parse('2026-09-14T18:00:02.000Z');
const codeIs = code => error => error instanceof StockInspectionError && error.code === code;
async function isolated(fn) {
  const homeDirectory = await mkdtemp(join(tmpdir(), 'trimmy-stock-inspection-'));
  try { await fn(await openStockResearchWallet({mode: 'create', homeDirectory})); }
  finally { await rm(homeDirectory, {recursive: true, force: true}); }
}
function estimate() {
  return {schemaVersion: 1, kind: 'indicative', network: 'solana:mainnet-beta', provider: 'jupiter-swap-v2', executable: false, walletChecked: false, networkFees: null,
    input: {symbol: 'USDC', mint: USDC_MINT, decimals: 6, amountRaw: REQUIRED_USDC_RAW},
    output: {symbol: 'AAPLx', mint: STOCK_ESTIMATE_ASSET.variantMint, decimals: 8, estimatedAmountRaw: '2972350', quotedMinimumAmountRaw: '2972350'},
    slippageBps: 0, swapFee: {basisPoints: 10, mint: USDC_MINT}, router: 'metis', requestedAt: '2026-09-14T18:00:00.000Z', receivedAt: '2026-09-14T18:00:01.000Z',
    refreshAfter: '2026-09-14T18:00:10.000Z', providerExpiresAt: null, assetId: 'apple', variantMint: STOCK_ESTIMATE_ASSET.variantMint,
    side: 'buy', executionEnabled: false, eligibility: 'unverified', amountUnits: 'raw_token_units'};
}
const verified = wallet => async () => ({provider: 'privy', userId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', verifiedTaker: wallet.publicAddress, walletOwnershipVerified: true, expectedEstimate: estimate()});
async function mock(wallet, changes = {}) {
  const calls = []; const [ata] = await findAssociatedTokenPda({owner: address(wallet.publicAddress), mint: address(USDC_MINT), tokenProgram: address(TOKEN)});
  const fetchImpl = async (url, options) => {
    const uri = new URL(String(url)); assert.equal(options.redirect, 'error');
    if (uri.origin === 'https://api.jup.ag') {
      calls.push('order'); assert.equal(uri.pathname, '/swap/v2/order'); assert.equal(options.method, 'GET');
      assert.deepEqual(Object.fromEntries(uri.searchParams), {inputMint: USDC_MINT, outputMint: STOCK_ESTIMATE_ASSET.variantMint,
        amount: REQUIRED_USDC_RAW, taker: wallet.publicAddress, slippageBps: '0'});
      if (changes.orderStatus) return Response.json({error: 'private-provider-detail'}, {status: changes.orderStatus});
      const messageBytes = getCompiledTransactionMessageEncoder().encode({version: 0,
        header: {numSignerAccounts: 1, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 1}, staticAccounts: [address(wallet.publicAddress), address('11111111111111111111111111111111')],
        lifetimeToken: getAddressDecoder().decode(new Uint8Array(32).fill(9)), instructions: [{programAddressIndex: 1, accountIndices: [0], data: new Uint8Array([1])}], addressTableLookups: []});
      const bytes = getTransactionEncoder().encode({messageBytes, signatures: {[wallet.publicAddress]: null}});
      return Response.json({inputMint: USDC_MINT, outputMint: STOCK_ESTIMATE_ASSET.variantMint, inAmount: REQUIRED_USDC_RAW,
        outAmount: '3000000', otherAmountThreshold: '3000000', swapMode: 'ExactIn', slippageBps: 0, mode: 'manual', feeBps: 9,
        feeMint: STOCK_ESTIMATE_ASSET.variantMint, router: 'dflow', taker: wallet.publicAddress,
        transaction: Buffer.from(bytes).toString('base64'), requestId: 'fixture-order', lastValidBlockHeight: '1050'});
    }
    assert.equal(String(url), MAINNET_STOCK_RPC); assert.equal(options.method, 'POST');
    const request = JSON.parse(options.body); calls.push(request.method); let result;
    if (request.method === 'getGenesisHash') result = changes.genesis ?? STOCK_WALLET_GENESIS;
    else if (request.method === 'getBalance') {
      assert.equal(request.params[0], wallet.publicAddress); result = {context: {slot: 2000}, value: changes.sol ?? Number(SOL_RESERVE_LAMPORTS)};
    } else if (request.method === 'getTokenAccountsByOwner') {
      assert.equal(request.params[0], wallet.publicAddress); assert.deepEqual(request.params[1], {mint: USDC_MINT});
      const entry = {pubkey: ata, account: {owner: TOKEN, executable: false, data: {program: 'spl-token', parsed: {type: 'account', info: {
        mint: changes.mint ?? USDC_MINT, owner: changes.owner ?? wallet.publicAddress, state: changes.state ?? 'initialized', isNative: false,
        tokenAmount: {amount: changes.usdc ?? REQUIRED_USDC_RAW, decimals: changes.decimals ?? 6}}}}}};
      result = {context: {slot: changes.slot ?? 2001}, value: changes.entries ?? [entry]};
    } else if (request.method === 'getBlockHeight') result = 1000;
    else assert.fail('Only the expected read RPC methods are allowed.');
    return Response.json({jsonrpc: '2.0', id: request.id, result});
  };
  return {calls, fetchImpl};
}
it('unfunded wallet returns exact shortfalls before any account verification or Jupiter request', async () => isolated(async wallet => {
  const fake = await mock(wallet, {sol: 0, entries: []}); let authCalls = 0;
  const client = new MainnetStockOrderInspection({wallet, fetchImpl: fake.fetchImpl, now: () => now});
  const result = await client.inspectFunded({verifyAccount: async () => { authCalls++; return verified(wallet)(); }});
  assert.equal(result.status, 'funding_required'); assert.equal(result.funding.solShortfallLamports, SOL_RESERVE_LAMPORTS); assert.equal(result.funding.usdcShortfallRaw, REQUIRED_USDC_RAW);
  assert.equal(authCalls, 0); assert.equal(client.orderAttempted, false);
  assert.deepEqual(fake.calls, ['getGenesisHash', 'getBalance', 'getTokenAccountsByOwner']);
}));
it('one-unit shortfall in either reserve refuses before Jupiter', async () => isolated(async wallet => {
  for (const changes of [{sol: Number(SOL_RESERVE_LAMPORTS) - 1}, {usdc: (BigInt(REQUIRED_USDC_RAW) - 1n).toString()}]) {
    const fake = await mock(wallet, changes); const client = new MainnetStockOrderInspection({wallet, fetchImpl: fake.fetchImpl, now: () => now});
    assert.equal((await client.inspectFunded()).status, 'funding_required'); assert.equal(client.orderAttempted, false);
  }
}));
it('wrong network stops before any wallet balance request', async () => isolated(async wallet => {
  const fake = await mock(wallet, {genesis: 'devnet'}); const client = new MainnetStockOrderInspection({wallet, fetchImpl: fake.fetchImpl});
  await assert.rejects(client.readFunding(), codeIs('STOCK_WRONG_NETWORK')); assert.deepEqual(fake.calls, ['getGenesisHash']);
}));
it('funding cannot replace separately verified application identity or local wallet ownership', async () => isolated(async wallet => {
  const fake = await mock(wallet); const client = new MainnetStockOrderInspection({wallet, fetchImpl: fake.fetchImpl, now: () => now});
  const result = await client.inspectFunded(); assert.equal(result.status, 'verified_app_account_required'); assert.equal(result.applicationAuthenticationVerified, false);
  for (const change of [{userId: wallet.localResearchPrincipalId}, {provider: 'local'}, {verifiedTaker: USDC_MINT}, {walletOwnershipVerified: false}]) {
    await assert.rejects(client.inspectFunded({verifyAccount: async () => ({...await verified(wallet)(), ...change})}), codeIs('STOCK_APP_ACCOUNT_REQUIRED'));
  }
  assert.equal(fake.calls.includes('order'), false);
}));
it('rejects wrong-owner/mint/decimals/frozen/noncanonical or stale-context USDC records', async () => isolated(async wallet => {
  for (const changes of [{owner: USDC_MINT}, {mint: STOCK_ESTIMATE_ASSET.variantMint}, {decimals: 9}, {state: 'frozen'}, {usdc: '1\n'}, {slot: 1999}]) {
    const fake = await mock(wallet, changes); const client = new MainnetStockOrderInspection({wallet, fetchImpl: fake.fetchImpl});
    await assert.rejects(client.readFunding(), codeIs('STOCK_BALANCE_INVALID')); assert.equal(fake.calls.includes('order'), false);
  }
}));
it('requires explicit provider mode and a fresh exact accepted input before the sole order', async () => isolated(async wallet => {
  const fake = await mock(wallet); const client = new MainnetStockOrderInspection({wallet, fetchImpl: fake.fetchImpl, now: () => now});
  await assert.rejects(client.inspectFunded({verifyAccount: verified(wallet)}), codeIs('STOCK_ORDER_ACCESS_DISABLED'));
  await assert.rejects(client.inspectFunded({verifyAccount: async () => ({...await verified(wallet)(), expectedEstimate: {...estimate(), refreshAfter: '2026-09-14T18:00:01Z'}})}), codeIs('STOCK_ACCEPTED_ESTIMATE_REQUIRED'));
  assert.equal(fake.calls.includes('order'), false);
}));
it('with injected verified fixture context makes exactly one taker order and binds only an unreviewed draft', async () => isolated(async wallet => {
  const fake = await mock(wallet); const client = new MainnetStockOrderInspection({wallet, fetchImpl: fake.fetchImpl, now: () => now, jupiterAccess: {kind: 'keyless_research'}});
  const result = await client.inspectFunded({verifyAccount: verified(wallet)});
  assert.equal(result.status, 'draft_unreviewed'); assert.equal(result.orderRequested, true); assert.equal(result.draft.taker, wallet.publicAddress);
  assert.equal(result.draft.output.estimatedAmountRaw, '3000000'); assert.equal(result.draft.referenceEstimate.output.estimatedAmountRaw, '2972350');
  assert.equal(result.draft.userApproval.status, 'required'); assert.deepEqual(result.draft.termChanges.map(change => change.field),
    ['output.estimatedAmountRaw', 'output.quotedMinimumAmountRaw', 'swapFee.basisPoints', 'swapFee.mint', 'router']);
  assert.equal(result.draft.review.simulation, 'not_run'); assert.equal(result.draft.readyForSimulation, false); assert.equal(result.draft.executionEnabled, false);
  assert.ok(!Object.hasOwn(result, 'transaction')); assert.ok(!Object.hasOwn(result.draft, 'transaction'));
  await assert.rejects(client.inspectFunded({verifyAccount: verified(wallet)}), codeIs('STOCK_ORDER_ALREADY_ATTEMPTED'));
  assert.equal(fake.calls.filter(call => call === 'order').length, 1);
  assert.equal(fake.calls.some(call => /send|simulate|execute/i.test(call)), false);
}));
it('provider failure is not retried and cannot reveal raw provider details', async () => isolated(async wallet => {
  const fake = await mock(wallet, {orderStatus: 429}); const client = new MainnetStockOrderInspection({wallet, fetchImpl: fake.fetchImpl, now: () => now, jupiterAccess: {kind: 'keyless_research'}});
  await assert.rejects(client.inspectFunded({verifyAccount: verified(wallet)}), codeIs('STOCK_READ_RATE_LIMITED'));
  assert.equal(fake.calls.filter(call => call === 'order').length, 1); assert.equal(client.orderAttempted, true);
}));
it('noncooperative RPC fetch is deadline bounded and never falls through to an order', async () => isolated(async wallet => {
  let calls = 0;
  const client = new MainnetStockOrderInspection({wallet, timeoutMs: 10, fetchImpl: async () => { calls++; return new Promise(() => {}); }});
  await assert.rejects(client.readFunding(), codeIs('STOCK_READ_TIMEOUT')); assert.equal(calls, 1); assert.equal(client.orderAttempted, false);
}));
