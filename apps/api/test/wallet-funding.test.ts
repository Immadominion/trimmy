import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { generateKeyPairSync, sign, type KeyObject } from 'node:crypto';
import { address, getAddressDecoder, getBase58Decoder, getTransactionDecoder, getTransactionEncoder } from '@solana/kit';
import { findAssociatedTokenPda, TOKEN_PROGRAM_ADDRESS } from '@solana-program/token';
import { TOKEN_2022_PROGRAM_ADDRESS } from '@solana-program/token-2022';
import { buildApp } from '../src/app.js';
import { WalletTransfers, USDC_MINT, WALLET_FUNDING_ROUTES, type WalletTransferAdapters } from '../src/wallet-transfers.js';
import { readWalletFundingConfig } from '../src/wallet-funding-config.js';

const SYSTEM = '11111111111111111111111111111111';
const epoch = Date.parse('2026-10-11T18:00:00Z');
function keypair(): {wallet: string; key: KeyObject} {
  const {publicKey, privateKey} = generateKeyPairSync('ed25519');
  return {wallet: getAddressDecoder().decode(publicKey.export({format: 'der', type: 'spki'}).subarray(12)), key: privateKey};
}
function signed(wire: string, source: ReturnType<typeof keypair>) {
  const tx = getTransactionDecoder().decode(Buffer.from(wire, 'base64'));
  const signature = sign(null, Buffer.from(tx.messageBytes), source.key);
  return {wire: Buffer.from(getTransactionEncoder().encode({...tx, signatures: {...tx.signatures, [address(source.wallet)]: new Uint8Array(signature)}})).toString('base64'),
    signature: getBase58Decoder().decode(signature)};
}
const wallet = (lamports: number) => ({owner: SYSTEM, lamports, executable: false, data: ['', 'base64']});
const tokenAccount = (owner: string, amount: string) => ({owner: TOKEN_PROGRAM_ADDRESS, lamports: 2_039_280, executable: false,
  data: {program: 'spl-token', parsed: {type: 'account', info: {mint: USDC_MINT, owner, state: 'initialized', tokenAmount: {amount, decimals: 6}}}}});
const mintAccount = () => ({owner: TOKEN_PROGRAM_ADDRESS as string, lamports: 1, executable: false,
  data: {program: 'spl-token', parsed: {type: 'mint', info: {decimals: 6, isInitialized: true}}}});

function fixture() {
  const source = keypair(), recipient = keypair();
  const accounts: Record<string, unknown> = {[source.wallet]: wallet(50_000_000)};
  const calls: string[] = [];
  let clock = epoch, chainTransaction: unknown = null, amount = 1_000_000, height = 900, unavailable = false;
  let simulate: () => unknown[] = () => [wallet(50_000_000 - amount - 5100), wallet(amount)];
  const fetch = (async (_url: URL, init: {body: string}) => {
    const {id, method, params} = JSON.parse(init.body) as {id: string; method: string; params: any[]};
    calls.push(method);
    if (unavailable) return new Response('', {status: 503});
    const result = method === 'getMultipleAccounts' ? {context: {slot: 1}, value: (params[0] as string[]).map(a => accounts[a] ?? null)}
      : method === 'getLatestBlockhash' ? {context: {slot: 1}, value: {blockhash: '4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn', lastValidBlockHeight: 1000}}
      : method === 'simulateTransaction' ? {context: {slot: 1}, value: {err: null, accounts: simulate()}}
      : method === 'getBlockHeight' ? height
      : method === 'getTransaction' ? (() => {assert.deepEqual(params[1], {encoding: 'base64', commitment: 'confirmed', maxSupportedTransactionVersion: 0}); return chainTransaction;})()
      : assert.fail(`Unexpected RPC method ${method}`);
    return Response.json({jsonrpc: '2.0', id, result});
  }) as unknown as typeof globalThis.fetch;
  const key = Buffer.alloc(32, 7);
  const service = new WalletTransfers({rpcUrl: 'https://rpc.example', fetch, now: () => clock, key});
  const input = {userId: 'u1', wallet: recipient.wallet, from: source.wallet, asset: 'SOL' as const, amountRaw: '1000000'};
  return {source, recipient, accounts, calls, service, input, fetch, key,
    setClock: (value: number) => {clock = value;}, setHeight: (value: number) => {height = value;}, setAmount: (value: number) => {amount = value;},
    setTransaction: (value: unknown) => {chainTransaction = value;}, setSimulation: (value: () => unknown[]) => {simulate = value;},
    setUnavailable: (value: boolean) => {unavailable = value;}};
}

describe('incoming mobile-wallet funding', () => {
  it('reviews the exact recipient, source, amount and signer, never broadcasts, and reconciles late confirmation', async () => {
    const f = fixture();
    const preview = await f.service.previewFunding(f.input);
    assert.equal(preview.review.from, f.source.wallet);
    assert.equal(preview.review.destination, f.recipient.wallet);
    assert.equal(preview.review.amountRaw, '1000000');
    assert.equal(preview.review.expiresAt, new Date(epoch + 90_000).toISOString());
    const tx = signed(preview.unsignedTransaction, f.source);
    const request = {...f.input, reviewToken: preview.reviewToken, signature: tx.signature};
    assert.deepEqual(await f.service.fundingStatus(request), {status: 'pending', slot: null});
    f.setClock(epoch + 10 * 60_000);
    f.setHeight(5000); // The blockhash expired after the wallet submitted; confirmation remains valid.
    assert.deepEqual(await f.service.fundingStatus(request), {status: 'pending', slot: null});
    f.setTransaction({slot: 123, meta: {err: null}, transaction: [tx.wire, 'base64']});
    assert.deepEqual(await f.service.fundingStatus(request), {status: 'confirmed', slot: 123});
    f.setTransaction({slot: 123, meta: {err: {InstructionError: [2, 'InsufficientFunds']}}, transaction: [tx.wire, 'base64']});
    assert.deepEqual(await f.service.fundingStatus(request), {status: 'failed', slot: 123});
    // A funding token cannot call the existing outgoing broadcast endpoint.
    await assert.rejects(f.service.execute({userId: 'u1', wallet: f.source.wallet, reviewToken: preview.reviewToken, signedTransaction: tx.wire}), {code: 'INVALID_REVIEW'});
    assert.equal(f.calls.includes('sendTransaction'), false);
  });

  it('scopes receipts to the authenticated account, current embedded recipient, external account and exact signed message', async () => {
    const f = fixture(), other = keypair();
    const preview = await f.service.previewFunding(f.input), tx = signed(preview.unsignedTransaction, f.source);
    const request = {...f.input, reviewToken: preview.reviewToken, signature: tx.signature};
    const before = f.calls.length;
    for (const change of [{userId: 'other-user'}, {wallet: other.wallet}, {from: other.wallet},
      {reviewToken: `${preview.reviewToken}x`}, {reviewToken: `${preview.reviewToken}.extra`}]) {
      await assert.rejects(f.service.fundingStatus({...request, ...change}), {code: 'INVALID_REVIEW'});
    }
    assert.equal(f.calls.length, before, 'reject account/token mismatches before RPC');
    f.setAmount(2_000_000);
    const changed = await f.service.previewFunding({...f.input, amountRaw: '2000000'});
    const changedTx = signed(changed.unsignedTransaction, f.source);
    f.setTransaction({slot: 123, meta: {err: null}, transaction: [changedTx.wire, 'base64']});
    await assert.rejects(f.service.fundingStatus({...request, signature: changedTx.signature}), {code: 'INVALID_REVIEW'});
    f.setTransaction({slot: 123, meta: {err: null}, transaction: [tx.wire, 'base64']});
    await assert.rejects(f.service.fundingStatus({...request, signature: changedTx.signature}), {code: 'INVALID_SIGNATURE'});
    const forged = signed(preview.unsignedTransaction, {...f.source, key: other.key});
    f.setTransaction({slot: 123, meta: {err: null}, transaction: [forged.wire, 'base64']});
    await assert.rejects(f.service.fundingStatus({...request, signature: forged.signature}), {code: 'INVALID_SIGNATURE'});
  });

  it('does not turn RPC failures or malformed records into outcomes, and supports next-day recovery', async () => {
    const f = fixture(), preview = await f.service.previewFunding(f.input), tx = signed(preview.unsignedTransaction, f.source);
    const request = {...f.input, reviewToken: preview.reviewToken, signature: tx.signature};
    f.setUnavailable(true);
    await assert.rejects(f.service.fundingStatus(request), {code: 'TRANSFER_UNAVAILABLE'});
    f.setUnavailable(false);
    for (const result of [{}, {slot: 1, meta: {}, transaction: [tx.wire, 'base64']}, {slot: -1, meta: {err: null}, transaction: [tx.wire, 'base64']},
      {slot: 1, meta: {err: null}, transaction: [tx.wire, 'json']}]) {
      f.setTransaction(result);
      await assert.rejects(f.service.fundingStatus(request), {code: 'TRANSFER_UNAVAILABLE'});
    }
    f.setTransaction({slot: 123, meta: {err: null}, transaction: [tx.wire, 'base64']});
    // A supplied stable private key permits a restart during reconciliation.
    const restarted = new WalletTransfers({rpcUrl: 'https://rpc.example', fetch: f.fetch, now: () => epoch + 5 * 60_000, key: f.key});
    assert.deepEqual(await restarted.fundingStatus(request), {status: 'confirmed', slot: 123});
    f.setClock(epoch + 48 * 60 * 60_000);
    assert.deepEqual(await f.service.fundingStatus(request), {status: 'confirmed', slot: 123});
  });

  it('rejects non-wallet sources, self funding, unsupported assets, invalid raw amounts and a stale blockhash', async () => {
    const f = fixture();
    const [offCurve] = await findAssociatedTokenPda({owner: address(f.source.wallet), mint: address(USDC_MINT), tokenProgram: TOKEN_PROGRAM_ADDRESS});
    for (const from of ['bad', '1'.repeat(44), offCurve]) {
      await assert.rejects(f.service.previewFunding({...f.input, from}), {code: 'SOURCE_INVALID'});
    }
    await assert.rejects(f.service.previewFunding({...f.input, from: f.recipient.wallet}), {code: 'DESTINATION_SELF'});
    await assert.rejects(f.service.previewFunding({...f.input, asset: 'BTC' as 'SOL'}), {code: 'ASSET_UNSUPPORTED'});
    await assert.rejects(f.service.previewFunding({...f.input, amountRaw: '18446744073709551616'}), {code: 'TRANSFER_INPUT_INVALID'});
    for (const source of [{...wallet(50_000_000), executable: true}, {...wallet(50_000_000), owner: TOKEN_PROGRAM_ADDRESS}]) {
      f.accounts[f.source.wallet] = source;
      await assert.rejects(f.service.previewFunding(f.input), {code: 'SOURCE_INVALID'});
    }
    f.accounts[f.source.wallet] = wallet(50_000_000);
    f.setHeight(1001);
    await assert.rejects(f.service.previewFunding(f.input), {code: 'REVIEW_EXPIRED'});
    assert.equal(f.calls.includes('sendTransaction'), false);
  });

  it('uses the mainnet legacy USDC mint with its exact decimals and embedded recipient ATA', async () => {
    const f = fixture();
    const [mine] = await findAssociatedTokenPda({owner: address(f.source.wallet), mint: address(USDC_MINT), tokenProgram: TOKEN_PROGRAM_ADDRESS});
    f.accounts[USDC_MINT] = mintAccount();
    f.accounts[mine] = tokenAccount(f.source.wallet, '5000000');
    f.setSimulation(() => [wallet(47_952_720), tokenAccount(f.source.wallet, '4000000'), tokenAccount(f.recipient.wallet, '1000000')]);
    const preview = await f.service.previewFunding({...f.input, asset: 'USDC'});
    assert.deepEqual(preview.review.asset, {kind: 'token', mint: USDC_MINT, symbol: 'USDC', decimals: 6, uiMultiplier: '1'});
    assert.equal(preview.review.createsAccount, true);
    assert.equal(preview.review.accountRentLamports, '2039280');
    assert.equal(preview.review.destination, f.recipient.wallet);
    f.accounts[USDC_MINT] = {...mintAccount(), owner: TOKEN_2022_PROGRAM_ADDRESS};
    await assert.rejects(f.service.previewFunding({...f.input, asset: 'USDC'}), {code: 'ASSET_UNSUPPORTED'});
    const wrongDecimals = mintAccount(); wrongDecimals.data.parsed.info.decimals = 9;
    f.accounts[USDC_MINT] = wrongDecimals;
    await assert.rejects(f.service.previewFunding({...f.input, asset: 'USDC'}), {code: 'ASSET_UNSUPPORTED'});
  });
});

describe('funding HTTP boundaries', () => {
  function setup(enabled = true) {
    const f = fixture();
    let authenticated = true, embedded = f.recipient.wallet, subject = 'did:privy:funding';
    const adapters: WalletTransferAdapters = {service: f.service, executionEnabled: enabled, fundingEnabled: true,
      authenticate: async () => authenticated ? {userId: 'u1', identity: {subject: 'did:privy:funding'}} as never : null,
      identities: {resolveFresh: async () => ({subject, embeddedSolanaWallet: {status: 'candidate', address: embedded}}) as never}};
    const app = buildApp({logger: false, walletTransfers: adapters});
    return {...f, app, setAuthenticated: (value: boolean) => {authenticated = value;}, setEmbedded: (value: string) => {embedded = value;},
      setSubject: (value: string) => {subject = value;}};
  }
  const body = (f: ReturnType<typeof fixture>) => ({from: f.source.wallet, asset: 'SOL', amountRaw: '1000000'});

  it('advertises availability without authentication, identity or RPC calls', async () => {
    for (const enabled of [true, false]) {
      const f = setup(enabled); f.setAuthenticated(false);
      try {
        const response = await f.app.inject({method: 'GET', url: WALLET_FUNDING_ROUTES.capabilities});
        assert.deepEqual(response.json(), {enabled, chain: 'solana:mainnet', assets: ['SOL', 'USDC']});
        assert.equal(response.headers['cache-control'], 'no-store');
        assert.equal(f.calls.length, 0);
      } finally { await f.app.close(); }
    }
    const missing = buildApp({logger: false});
    try { assert.equal((await missing.inject({method: 'GET', url: WALLET_FUNDING_ROUTES.capabilities})).json().enabled, false); }
    finally { await missing.close(); }
  });

  it('keeps incoming funding off without its rollout flag or a persistent receipt key', async () => {
    for (const fundingEnabled of [undefined, false, true]) {
      const f = fixture();
      const service = new WalletTransfers({rpcUrl: 'https://rpc.example', fetch: f.fetch,
        ...(fundingEnabled !== true ? {key: f.key} : {})});
      const app = buildApp({logger: false, walletTransfers: {service, executionEnabled: true,
        ...(fundingEnabled !== undefined ? {fundingEnabled} : {}),
        authenticate: async () => assert.fail('disabled preview must not authenticate'),
        identities: {resolveFresh: async () => assert.fail('disabled preview must not resolve identity')}}});
      try {
        assert.equal((await app.inject({method: 'GET', url: WALLET_FUNDING_ROUTES.capabilities})).json().enabled, false);
        const response = await app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.preview, payload: body(f)});
        assert.deepEqual([response.statusCode, response.json()], [503, {code: 'TRANSFER_UNAVAILABLE'}]);
        assert.equal(f.calls.length, 0);
      } finally { await app.close(); }
    }
  });

  it('requires authentication, enforces the live gate, and refuses a client-chosen recipient or RPC method', async () => {
    const f = setup();
    try {
      f.setAuthenticated(false);
      assert.equal((await f.app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.preview, payload: body(f)})).statusCode, 401);
      f.setAuthenticated(true);
      for (const extra of [{destination: keypair().wallet}, {wallet: keypair().wallet}, {method: 'sendTransaction'}, {asset: 'BTC'}]) {
        assert.equal((await f.app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.preview, payload: {...body(f), ...extra}})).statusCode, 400);
      }
      assert.equal(f.calls.length, 0);
      f.setSubject('did:privy:someone-else');
      assert.equal((await f.app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.preview, payload: body(f)})).json().code, 'WALLET_REQUIRED');
    } finally { await f.app.close(); }
    const off = setup(false);
    try {
      const response = await off.app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.preview, payload: body(off)});
      assert.deepEqual([response.statusCode, response.json()], [503, {code: 'TRANSFER_UNAVAILABLE'}]);
      assert.equal(off.calls.length, 0);
    } finally { await off.app.close(); }
  });

  it('resolves the fresh embedded recipient on status, rejects account switches and continues reconciliation while disabled', async () => {
    const f = setup(false);
    try {
      const preview = await f.service.previewFunding(f.input), tx = signed(preview.unsignedTransaction, f.source);
      f.setTransaction({slot: 123, meta: {err: null}, transaction: [tx.wire, 'base64']});
      const payload = {from: f.source.wallet, reviewToken: preview.reviewToken, signature: tx.signature};
      const confirmed = await f.app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.status, payload});
      assert.deepEqual([confirmed.statusCode, confirmed.json()], [200, {status: 'confirmed', slot: 123}]);
      f.setEmbedded(keypair().wallet);
      const switched = await f.app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.status, payload});
      assert.deepEqual([switched.statusCode, switched.json()], [409, {code: 'INVALID_REVIEW'}]);
      f.setAuthenticated(false);
      assert.equal((await f.app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.status, payload})).statusCode, 401);
    } finally { await f.app.close(); }
  });

  it('bounds repeated authenticated preview requests before further RPC work', async () => {
    const f = setup();
    try {
      for (let i = 0; i < 6; i++) {
        assert.equal((await f.app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.preview,
          payload: {...body(f), from: f.recipient.wallet}})).json().code, 'DESTINATION_SELF');
      }
      const limited = await f.app.inject({method: 'POST', url: WALLET_FUNDING_ROUTES.preview, payload: body(f)});
      assert.deepEqual([limited.statusCode, limited.json()], [429, {code: 'TRANSFER_BUSY'}]);
      assert.equal(limited.headers['retry-after'], '3');
      assert.equal(f.calls.length, 0);
    } finally { await f.app.close(); }
  });
});

describe('incoming funding runtime configuration', () => {
  it('defaults off and requires a separate persistent 32-byte hex key for activation', () => {
    assert.deepEqual(readWalletFundingConfig({}), {enabled: false});
    assert.deepEqual(readWalletFundingConfig({TRIMMY_MWA_FUNDING: 'disabled'}), {enabled: false});
    const synthetic = 'ab'.repeat(32);
    const config = readWalletFundingConfig({TRIMMY_MWA_FUNDING: 'enabled', TRIMMY_WALLET_REVIEW_KEY: synthetic});
    assert.equal(config.enabled, true);
    assert.deepEqual(config.reviewKey, Buffer.from(synthetic, 'hex'));
    assert.throws(() => readWalletFundingConfig({TRIMMY_MWA_FUNDING: 'enabled'}), /requires TRIMMY_WALLET_REVIEW_KEY/);
    for (const value of ['bad', 'ab'.repeat(31), 'ab'.repeat(33), ` ${synthetic}`, 'zz'.repeat(32)]) {
      assert.throws(() => readWalletFundingConfig({TRIMMY_MWA_FUNDING: 'enabled', TRIMMY_WALLET_REVIEW_KEY: value}),
        error => error instanceof Error && error.message === 'TRIMMY_WALLET_REVIEW_KEY must encode exactly 32 bytes as hex.' && !error.message.includes(value));
    }
    assert.throws(() => readWalletFundingConfig({TRIMMY_MWA_FUNDING: 'true'}), /must be disabled or enabled/);
    assert.throws(() => new WalletTransfers({rpcUrl: 'https://rpc.example', key: Buffer.alloc(31)}), /exactly 32 bytes/);
  });
});
