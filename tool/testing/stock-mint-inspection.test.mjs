import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { getMintEncoder, TOKEN_2022_PROGRAM_ADDRESS } from '@solana-program/token-2022';
import { getSysvarClockEncoder, SYSVAR_CLOCK_ADDRESS } from '@solana/sysvars';
import { ISSUER_URL, LEGACY_TOKEN_PROGRAM, MAINNET_GENESIS, MAINNET_RPC_URL,
  MintReadClient, inspectMintAccount, parseIssuerAsset, runMintInspection } from './stock-mint-inspection.mjs';

const mint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const authority = '7pt9tkctJPK7PPNQJ77GKg8ZffSF6QxoMiCFYHxrtaCj';
const otherMint = 'So11111111111111111111111111111111111111112';
const issuer = { id: '9e43a778-fdc8-44f1-87de-f2e7420bb7f7', symbol: 'AAPLx', name: 'Apple xStock',
  isin: 'CH1436219187', deployments: [{ network: 'Solana', address: mint }] };
const scaled = { __kind: 'ScaledUiAmountConfig', authority, multiplier: 1.25,
  newMultiplier: 2.5, newMultiplierEffectiveTimestamp: 1000n };
function account({ extensions = null, owner = TOKEN_2022_PROGRAM_ADDRESS, ...fields } = {}) {
  const bytes = getMintEncoder().encode({ mintAuthority: authority, supply: 18446744073709551615n,
    decimals: 8, isInitialized: true, freezeAuthority: null, extensions, ...fields });
  return { owner, executable: false, data: [Buffer.from(bytes).toString('base64'), 'base64'], space: bytes.length };
}
const inspect = (value, at = 999n) => inspectMintAccount({ mint, account: value, chainUnixTimestamp: at });
const json = value => new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json' } });
const rpcReply = (request, result) => json({ jsonrpc: '2.0', id: JSON.parse(request.body).id, result });
const clockAccount = (slot = 42n) => ({ owner: 'Sysvar1111111111111111111111111111111111111', executable: false,
  data: [Buffer.from(getSysvarClockEncoder().encode({ slot, epochStartTimestamp: 900n, epoch: 1n,
    leaderScheduleEpoch: 2n, unixTimestamp: 1000n })).toString('base64'), 'base64'], space: 40 });

test('publisher provenance uses one exact Solana deployment and never implies eligibility', () => {
  const result = parseIssuerAsset(issuer);
  assert.equal(result.mint, mint); assert.equal(result.sourceUrl, ISSUER_URL);
  assert.equal(result.provenance, 'publisher_listed'); assert.equal(result.eligibility, 'unverified');
  assert.throws(() => { result.mint = otherMint; }, TypeError);
  for (const value of [null, [], { ...issuer, symbol: 'AAPL' }, { ...issuer, deployments: [] },
    { ...issuer, deployments: [...issuer.deployments, ...issuer.deployments] },
    { ...issuer, deployments: [{ network: 'Solana', address: 'not-a-mint' }] }]) {
    assert.throws(() => parseIssuerAsset(value));
  }
});

test('legacy and Token2022 mints retain exact u64 supply and optional authorities', () => {
  for (const owner of [LEGACY_TOKEN_PROGRAM, TOKEN_2022_PROGRAM_ADDRESS]) {
    const result = inspect(account({ owner }));
    assert.equal(result.rawSupply, '18446744073709551615'); assert.equal(result.decimals, 8);
    assert.equal(result.mintAuthority, authority); assert.equal(result.freezeAuthority, null);
    assert.deepEqual(result.extensions, []); assert.equal(result.scaledUi, null);
    assert.equal(result.executionEnabled, false);
  }
  assert.throws(() => inspect(account({ owner: LEGACY_TOKEN_PROGRAM, extensions: [scaled] })), { code: 'INVALID_LEGACY_MINT' });
});

test('multiplier changes at the chain timestamp boundary without changing raw units', () => {
  const encoded = account({ extensions: [scaled] });
  const before = inspect(encoded, 999n), at = inspect(encoded, 1000n), after = inspect(encoded, 1001n);
  assert.equal(before.scaledUi.effectiveMultiplier, 1.25); assert.equal(before.scaledUi.activeField, 'multiplier');
  assert.equal(at.scaledUi.effectiveMultiplier, 2.5); assert.equal(at.scaledUi.activeField, 'newMultiplier');
  assert.deepEqual(at.rawSupply, before.rawSupply); assert.equal(after.scaledUi.effectiveMultiplier, 2.5);
  assert.equal(at.scaledUi.changesRawSupply, false);
  assert.throws(() => { at.extensions[0].newMultiplier = 99; }, TypeError);
  assert.throws(() => { at.scaledUi.effectiveMultiplier = 99; }, TypeError);
  const distant = inspect(account({ extensions: [{ ...scaled, newMultiplierEffectiveTimestamp: 9223372036854775807n }] }), 1000n);
  assert.equal(distant.scaledUi.nextEffectiveUnixTimestamp, '9223372036854775807');
  assert.equal(distant.scaledUi.effectiveMultiplier, 1.25);
});

test('nonfinite or nonpositive multipliers and incompatible interest-bearing config fail closed', () => {
  for (const value of [0, -1, Infinity, NaN]) {
    assert.throws(() => inspect(account({ extensions: [{ ...scaled, multiplier: value }] })), { code: 'INVALID_SCALED_MULTIPLIER' });
    assert.throws(() => inspect(account({ extensions: [{ ...scaled, newMultiplier: value }] })), { code: 'INVALID_SCALED_MULTIPLIER' });
  }
  const interest = { __kind: 'InterestBearingConfig', rateAuthority: authority, initializationTimestamp: 1n,
    preUpdateAverageRate: 0, lastUpdateTimestamp: 1n, currentRate: 100 };
  assert.throws(() => inspect(account({ extensions: [scaled, interest] })), { code: 'INCOMPATIBLE_MINT_EXTENSIONS' });
});

test('authority-bearing extensions remain review flags even when decoded successfully', () => {
  const result = inspect(account({ extensions: [scaled, { __kind: 'PermanentDelegate', delegate: authority },
    { __kind: 'PausableConfig', authority, paused: true }, { __kind: 'TransferHook', authority, programId: otherMint }] }));
  assert.deepEqual(result.extensionReviewRequired, ['PermanentDelegate', 'PausableConfig', 'TransferHook']);
  assert.equal(result.extensions[2].paused, true); assert.equal(result.extensions[3].programId, otherMint);
  assert.equal(result.eligibility, 'unverified'); assert.equal(result.executionEnabled, false);
});

test('mint rejects duplicated/account-only extensions and metadata for a different mint', () => {
  assert.throws(() => inspect(account({ extensions: [scaled, scaled] })), { code: 'DUPLICATE_MINT_EXTENSION' });
  assert.throws(() => inspect(account({ extensions: [{ __kind: 'ImmutableOwner' }] })), { code: 'UNSUPPORTED_MINT_EXTENSION' });
  const metadata = { __kind: 'TokenMetadata', updateAuthority: authority, mint: otherMint,
    name: 'Apple xStock', symbol: 'AAPLx', uri: 'https://example.com/public.json', additionalMetadata: new Map() };
  assert.throws(() => inspect(account({ extensions: [metadata] })), { code: 'METADATA_MINT_MISMATCH' });
});

test('wrong owners, executable accounts, uninitialized mints and corrupt binary layouts fail', () => {
  assert.throws(() => inspect(account({ owner: otherMint })), { code: 'UNSUPPORTED_TOKEN_PROGRAM' });
  assert.throws(() => inspect({ ...account(), executable: true }), { code: 'INVALID_ACCOUNT' });
  assert.throws(() => inspect(account({ isInitialized: false })), { code: 'UNINITIALIZED_MINT' });
  const base = account({ extensions: [scaled] });
  const raw = Buffer.from(base.data[0], 'base64');
  for (const bytes of [raw.subarray(0, raw.length - 1), Buffer.concat([raw, Buffer.from([255, 255, 0, 0])])]) {
    assert.throws(() => inspect({ ...base, data: [bytes.toString('base64'), 'base64'], space: bytes.length }));
  }
  assert.throws(() => inspect({ ...base, data: [base.data[0] + '\n', 'base64'] }), { code: 'INVALID_ACCOUNT' });
  assert.throws(() => inspect({ ...base, space: 1 }), { code: 'INVALID_ACCOUNT' });
  assert.throws(() => inspect(base, 1000), { code: 'INVALID_CHAIN_TIME' });
});

test('fixed read transport obtains issuer mint and same-context chain Clock without transaction methods', async () => {
  const methods = [];
  const client = new MintReadClient({ fetchImpl: async (url, request) => {
    assert.equal(request.redirect, 'error');
    if (url === ISSUER_URL) { assert.equal(request.method, 'GET'); return json(issuer); }
    assert.equal(url, MAINNET_RPC_URL);
    const body = JSON.parse(request.body); methods.push(body.method);
    if (body.method === 'getGenesisHash') return rpcReply(request, MAINNET_GENESIS);
    assert.deepEqual(body.params, [[mint, SYSVAR_CLOCK_ADDRESS], { encoding: 'base64', commitment: 'confirmed' }]);
    return rpcReply(request, { context: { slot: 42 }, value: [account({ extensions: [scaled] }), clockAccount()] });
  } });
  const result = await runMintInspection({ client });
  assert.equal(result.passed, true); assert.equal(result.inspection.scaledUi.effectiveMultiplier, 2.5);
  assert.deepEqual(methods, ['getGenesisHash', 'getMultipleAccounts']);
  for (const method of ['sendTransaction', 'simulateTransaction', 'requestAirdrop', 'sendBundle']) {
    await assert.rejects(client.call(method), { code: 'READ_METHOD_NOT_ALLOWED' });
  }
  assert.equal(methods.length, 2); assert.equal(result.transactionBuilt, false);
  assert.throws(() => { result.accounts[0].data[0] = ''; }, TypeError);
});

test('wrong chain stops before mint reads; inconsistent clock context cannot choose a multiplier', async () => {
  const calls = [];
  const wrongChain = { issuerAsset: async () => issuer, call: async method => { calls.push(method); return 'devnet'; } };
  assert.equal((await runMintInspection({ client: wrongChain })).errorCode, 'WRONG_CHAIN');
  assert.deepEqual(calls, ['getGenesisHash']);
  const wrongClock = { issuerAsset: async () => issuer, call: async method => method === 'getGenesisHash'
    ? MAINNET_GENESIS : { context: { slot: 42 }, value: [account(), clockAccount(41n)] } };
  assert.equal((await runMintInspection({ client: wrongClock })).errorCode, 'CHAIN_CLOCK_CONTEXT_MISMATCH');
});

test('read response bounds, redirects and mismatched RPC identities are rejected', async () => {
  for (const makeResponse of [() => new Response(' '.repeat(262_145), { headers: { 'content-type': 'application/json' } }),
    () => new Response('{}', { status: 302, headers: { location: 'https://example.com' } }),
    () => new Response('{}', { headers: { 'content-type': 'text/html' } })]) {
    await assert.rejects(new MintReadClient({ fetchImpl: async () => makeResponse() }).issuerAsset());
  }
  await assert.rejects(new MintReadClient({ fetchImpl: async () => json({ jsonrpc: '2.0', id: 99, result: MAINNET_GENESIS }) }).call('getGenesisHash'), { code: 'INVALID_RPC_RESPONSE' });
});

test('deadline handles ignored abort and stalled bodies, with sanitized errors', async () => {
  await assert.rejects(new MintReadClient({ timeoutMs: 5, fetchImpl: () => new Promise(() => {}) }).issuerAsset(), { code: 'READ_TIMEOUT' });
  let cancelled = false;
  const stream = new ReadableStream({ start(controller) { controller.enqueue(new TextEncoder().encode('{')); }, cancel() { cancelled = true; } });
  await assert.rejects(new MintReadClient({ timeoutMs: 5, fetchImpl: async () => new Response(stream, { headers: { 'content-type': 'application/json' } }) }).issuerAsset(), { code: 'READ_TIMEOUT' });
  assert.equal(cancelled, true);
  await assert.rejects(new MintReadClient({ fetchImpl: async () => { throw new Error('private provider diagnostic'); } }).issuerAsset(), { code: 'READ_FAILED', message: 'READ_FAILED' });
});

test('recorded real AAPLx bytes reproduce supply, eight extensions and chain-timed multiplier offline', async () => {
  const evidence = JSON.parse(await readFile(new URL('./fixtures/aaplx-mint-2026-09-14.json', import.meta.url), 'utf8'));
  assert.equal(evidence.passed, true); assert.equal(evidence.publisher.mint, mint);
  assert.equal(evidence.genesisHash, MAINNET_GENESIS);
  const result = inspectMintAccount({ mint, account: evidence.accounts[0], chainUnixTimestamp: BigInt(evidence.chainClock.unixTimestamp) });
  assert.deepEqual(result, evidence.inspection);
  assert.equal(result.rawSupply, '15376355897326'); assert.equal(result.decimals, 8);
  assert.deepEqual(result.extensions.map(item => item.__kind), ['MetadataPointer', 'PermanentDelegate', 'DefaultAccountState',
    'ScaledUiAmountConfig', 'PausableConfig', 'ConfidentialTransferMint', 'TransferHook', 'TokenMetadata']);
  assert.equal(result.scaledUi.activeField, 'newMultiplier');
  assert.equal(result.scaledUi.effectiveMultiplier, 1.0032690125398187);
  assert.equal(evidence.walletUsed, false); assert.equal(evidence.transactionBroadcast, false);
});
