import {MemoryTransferStore} from './transfer-store-fixture.js';
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { generateKeyPairSync, sign, type KeyObject } from 'node:crypto';
import Fastify from 'fastify';
import { address, getAddressDecoder, getBase58Decoder, getTransactionDecoder, getTransactionEncoder } from '@solana/kit';
import { findAssociatedTokenPda, TOKEN_PROGRAM_ADDRESS } from '@solana-program/token';
import { WalletTransfers, USDC_MINT, registerWalletTransferRoutes, verifySignedTransfer } from '../src/wallet-transfers.js';

const SYSTEM = '11111111111111111111111111111111';
function keypair(): {wallet: string; key: KeyObject} {
  const {publicKey, privateKey} = generateKeyPairSync('ed25519');
  return {wallet: getAddressDecoder().decode(publicKey.export({format: 'der', type: 'spki'}).subarray(12)), key: privateKey};
}
function signWire(wire: string, wallet: string, key: KeyObject): string {
  const tx = getTransactionDecoder().decode(Buffer.from(wire, 'base64'));
  const signature = sign(null, Buffer.from(tx.messageBytes), key);
  return Buffer.from(getTransactionEncoder().encode({...tx, signatures: {...tx.signatures, [address(wallet)]: new Uint8Array(signature)}})).toString('base64');
}
const wallet = (lamports: number) => ({owner: SYSTEM, lamports, executable: false, data: ['', 'base64']});
const tokenAccount = (mint: string, owner: string, amount: string, program = TOKEN_PROGRAM_ADDRESS, state = 'initialized') =>
  ({owner: program, lamports: 2_039_280, executable: false, data: {program: 'spl-token', parsed: {type: 'account',
    info: {mint, owner, state, tokenAmount: {amount, decimals: 6}}}}});
const mintAccount = (extensions?: unknown[]) => ({owner: TOKEN_PROGRAM_ADDRESS, lamports: 1, executable: false,
  data: {program: 'spl-token', parsed: {type: 'mint', info: {decimals: 6, isInitialized: true, supply: '1', ...(extensions ? {extensions} : {})}}}});

/** A chain of accounts; simulation applies a transfer of `moved` between the watched accounts. */
function chain(accounts: Record<string, unknown>, options: {height?: number; simulate?: (addresses: string[]) => unknown[] | {err: unknown}} = {}) {
  const sent: string[] = [];
  const fetch = (async (_url: URL, init: {body: string}) => {
    const {id, method, params} = JSON.parse(init.body) as {id: string; method: string; params: any[]};
    const result = method === 'getMultipleAccounts' ? {context: {slot: 1}, value: (params[0] as string[]).map(a => accounts[a] ?? null)}
      : method === 'getLatestBlockhash' ? {context: {slot: 1}, value: {blockhash: '4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn', lastValidBlockHeight: 1000}}
      : method === 'simulateTransaction' ? (() => { const out = options.simulate!(params[1].accounts.addresses);
        return {context: {slot: 1}, value: Array.isArray(out) ? {err: null, accounts: out} : {err: out.err, accounts: null}}; })()
      : method === 'getBlockHeight' ? options.height ?? 900
      : method === 'sendTransaction' ? (() => { sent.push(params[0]); const tx = getTransactionDecoder().decode(Buffer.from(params[0], 'base64'));
        return getBase58Decoder().decode(Object.values(tx.signatures)[0]!); })()
      : method === 'getSignatureStatuses' ? {context: {slot: 1}, value: [{slot: 5, err: null, confirmationStatus: 'confirmed'}]} : null;
    return Response.json({jsonrpc: '2.0', id, result});
  }) as unknown as typeof globalThis.fetch;
  return {fetch, sent};
}

describe('wallet transfers', () => {
  const now = () => Date.parse('2026-09-28T18:00:00Z');

  it('sends exactly the reviewed SOL transfer, signed by the wallet, and nothing else', async () => {
    const me = keypair(), friend = keypair();
    let moved = 1_000_000;
    const rpc = chain({[me.wallet]: wallet(50_000_000)}, {simulate: () => [wallet(50_000_000 - moved), wallet(moved)]});
    const service = new WalletTransfers({store: new MemoryTransferStore(),rpcUrl: 'https://rpc.example', fetch: rpc.fetch, now});
    const preview = await service.preview({userId: 'u1', wallet: me.wallet, asset: 'SOL', destination: friend.wallet, amountRaw: '1000000'});
    assert.equal(preview.review.asset.symbol, 'SOL');
    assert.equal(preview.review.receivedRaw, '1000000');
    const signed = signWire(preview.unsignedTransaction, me.wallet, me.key);
    // Another account, another signer, or a changed message is refused.
    await assert.rejects(service.execute({userId: 'u2', wallet: me.wallet, reviewToken: preview.reviewToken, signedTransaction: signed}), {code: 'INVALID_REVIEW'});
    await assert.rejects(service.execute({userId: 'u1', wallet: me.wallet, reviewToken: `${preview.reviewToken.split('.')[0]}.AAAA`, signedTransaction: signed}), {code: 'INVALID_REVIEW'});
    const other = keypair();
    await assert.rejects(service.execute({userId: 'u1', wallet: me.wallet, reviewToken: preview.reviewToken,
      signedTransaction: signWire(preview.unsignedTransaction, me.wallet, other.key)}), {code: 'INVALID_SIGNATURE'});
    moved = 2_000_000;
    const second = await service.preview({userId: 'u1', wallet: me.wallet, asset: 'SOL', destination: friend.wallet, amountRaw: '2000000'});
    await assert.rejects(service.execute({userId: 'u1', wallet: me.wallet, reviewToken: preview.reviewToken,
      signedTransaction: signWire(second.unsignedTransaction, me.wallet, me.key)}), {code: 'INVALID_REVIEW'});
    assert.equal(rpc.sent.length, 0);
    const currentSigned=signWire(second.unsignedTransaction,me.wallet,me.key);
    const {signature} = await service.execute({userId: 'u1', wallet: me.wallet, reviewToken: second.reviewToken, signedTransaction: currentSigned});
    assert.deepEqual(rpc.sent, [currentSigned]);
    assert.equal(signature, verifySignedTransfer(currentSigned, me.wallet, JSON.parse(Buffer.from(second.reviewToken.split('.')[0]!, 'base64url').toString()).h));
    assert.deepEqual(await service.status(signature), {status: 'confirmed', slot: 5});
  });

  it('refuses a review past its time or its blockhash', async () => {
    const me = keypair(), friend = keypair();
    let clock = now();
    const rpc = chain({[me.wallet]: wallet(50_000_000)}, {height: 1001, simulate: () => [wallet(48_990_000), wallet(1_000_000)]});
    const service = new WalletTransfers({store: new MemoryTransferStore(),rpcUrl: 'https://rpc.example', fetch: rpc.fetch, now: () => clock});
    const preview = await service.preview({userId: 'u1', wallet: me.wallet, asset: 'SOL', destination: friend.wallet, amountRaw: '1000000'});
    const signed = signWire(preview.unsignedTransaction, me.wallet, me.key);
    await assert.rejects(service.execute({userId: 'u1', wallet: me.wallet, reviewToken: preview.reviewToken, signedTransaction: signed}), {code: 'REVIEW_EXPIRED'});
    clock += 91_000;
    await assert.rejects(service.execute({userId: 'u1', wallet: me.wallet, reviewToken: preview.reviewToken, signedTransaction: signed}), {code: 'REVIEW_EXPIRED'});
    assert.equal(rpc.sent.length, 0);
  });

  it('keeps SOL rules: enough left to exist, and enough to open a new wallet', async () => {
    const me = keypair(), friend = keypair();
    const service = new WalletTransfers({store: new MemoryTransferStore(),rpcUrl: 'https://rpc.example', now,
      fetch: chain({[me.wallet]: wallet(2_000_000)}, {simulate: () => [wallet(0), wallet(1)]}).fetch});
    const send = (amountRaw: string) => service.preview({userId: 'u1', wallet: me.wallet, asset: 'SOL', destination: friend.wallet, amountRaw});
    await assert.rejects(send('1500000'), {code: 'LEAVES_TOO_LITTLE_SOL'});
    await assert.rejects(send('5000'), {code: 'AMOUNT_TOO_SMALL'});
    await assert.rejects(send('3000000'), {code: 'INSUFFICIENT_BALANCE'});
    await assert.rejects(service.preview({userId: 'u1', wallet: me.wallet, asset: 'SOL', destination: me.wallet, amountRaw: '1000000'}), {code: 'DESTINATION_SELF'});
  });

  it('sends USDC to a new wallet, creating its account, and refuses token accounts and restricted tokens', async () => {
    const me = keypair(), friend = keypair();
    const [mine] = await findAssociatedTokenPda({owner: address(me.wallet), mint: address(USDC_MINT), tokenProgram: TOKEN_PROGRAM_ADDRESS});
    const [theirs] = await findAssociatedTokenPda({owner: address(friend.wallet), mint: address(USDC_MINT), tokenProgram: TOKEN_PROGRAM_ADDRESS});
    const accounts: Record<string, unknown> = {[USDC_MINT]: mintAccount(), [me.wallet]: wallet(10_000_000), [mine]: tokenAccount(USDC_MINT, me.wallet, '5000000')};
    let delivered = '2000000';
    const rpc = chain(accounts, {simulate: () => [wallet(7_900_000), tokenAccount(USDC_MINT, me.wallet, '3000000'), tokenAccount(USDC_MINT, friend.wallet, delivered)]});
    const service = new WalletTransfers({store: new MemoryTransferStore(),rpcUrl: 'https://rpc.example', fetch: rpc.fetch, now});
    const send = (destination: string, amountRaw = '2000000') => service.preview({userId: 'u1', wallet: me.wallet, asset: 'USDC', destination, amountRaw});
    const preview = await send(friend.wallet);
    assert.equal(preview.review.createsAccount, true);
    assert.equal(preview.review.accountRentLamports, '2039280');
    assert.equal(preview.review.receivedRaw, '2000000');
    // Three setup instructions and the transfer, from the user's own account, paid by the user.
    const tx = getTransactionDecoder().decode(Buffer.from(preview.unsignedTransaction, 'base64'));
    assert.deepEqual(Object.keys(tx.signatures), [me.wallet]);
    await assert.rejects(send(mine), {code: 'DESTINATION_NOT_WALLET'}, 'a token account is not a wallet');
    await assert.rejects(send(USDC_MINT), {code: 'DESTINATION_NOT_WALLET'});
    await assert.rejects(send(friend.wallet, '9000000'), {code: 'INSUFFICIENT_BALANCE'});
    delivered = '2500000';
    await assert.rejects(send(friend.wallet), {code: 'SIMULATION_MISMATCH'}, 'the destination cannot receive more than was sent');
    accounts[theirs] = tokenAccount(USDC_MINT, friend.wallet, '0', TOKEN_PROGRAM_ADDRESS, 'frozen');
    await assert.rejects(send(friend.wallet), {code: 'DESTINATION_FROZEN'});
    delete accounts[theirs];
    accounts[USDC_MINT] = mintAccount([{extension: 'transferHook', state: {programId: SYSTEM}}]);
    await assert.rejects(send(friend.wallet), {code: 'ASSET_NOT_TRANSFERABLE'});
    accounts[USDC_MINT] = mintAccount([{extension: 'pausableConfig', state: {paused: true}}]);
    await assert.rejects(send(friend.wallet), {code: 'ASSET_PAUSED'});
    await assert.rejects(service.preview({userId: 'u1', wallet: me.wallet, asset: friend.wallet, destination: friend.wallet, amountRaw: '1'}), {code: 'ASSET_UNSUPPORTED'});
  });
});

describe('wallet transfer routes', () => {
  it('require an account, respect the live switch and validate input', async () => {
    const me = keypair();
    const service = new WalletTransfers({store: new MemoryTransferStore(),rpcUrl: 'https://rpc.example', fetch: chain({}).fetch});
    const build = (account: boolean, enabled = true) => {
      // The app's own validation: unknown fields are refused, not dropped.
      const app = Fastify({ajv: {customOptions: {removeAdditional: false, coerceTypes: false, useDefaults: false}}});
      registerWalletTransferRoutes(app, {executionEnabled: enabled, service,
        authenticate: async () => account ? {userId: 'u1', identity: {subject: 'did:privy:x'}} as never : null,
        identities: {resolveFresh: async () => ({subject: 'did:privy:x', embeddedSolanaWallet: {status: 'candidate', address: me.wallet}}) as never}});
      return app;
    };
    const body = {asset: 'USDC', destination: keypair().wallet, amountRaw: '1000000'};
    assert.equal((await build(false).inject({method: 'POST', url: '/v1/wallet/transfers/preview', payload: body})).statusCode, 401);
    const off = await build(true, false).inject({method: 'POST', url: '/v1/wallet/transfers/preview', payload: body});
    assert.deepEqual([off.statusCode, off.json()], [503, {code: 'TRANSFER_UNAVAILABLE'}]);
    assert.equal((await build(true).inject({method: 'POST', url: '/v1/wallet/transfers/preview', payload: {...body, amountRaw: '0'}})).statusCode, 400);
    assert.equal((await build(true).inject({method: 'POST', url: '/v1/wallet/transfers/preview', payload: {...body, extra: 1}})).statusCode, 400);
    const self = await build(true).inject({method: 'POST', url: '/v1/wallet/transfers/preview', payload: {...body, destination: me.wallet}});
    assert.deepEqual([self.statusCode, self.json()], [409, {code: 'DESTINATION_SELF'}]);
  });
});

it('persists before broadcast; timeout and restart recover the same signature without rebroadcast',async()=>{
 const me=keypair(),friend=keypair(),store=new MemoryTransferStore();
 let broadcasts=0,confirmed=false;
 const rpc=chain({[me.wallet]:wallet(50_000_000)},{simulate:()=>[wallet(48_994_900),wallet(1_000_000)]});
 const fetch:typeof globalThis.fetch=async(url,init)=>{
  const {id,method}=JSON.parse(String(init?.body));
  if(method==='sendTransaction'){
   broadcasts++;
   assert.equal((await store.read('u1'))?.status,'pending');
   assert.ok((await store.read('u1'))?.signature);
   throw Error('lost network reply after submission');
  }
  if(method==='getSignatureStatuses')return Response.json({jsonrpc:'2.0',id,result:{context:{slot:10},value:[confirmed?{slot:10,err:null,confirmationStatus:'confirmed'}:null]}});
  return rpc.fetch(url,init);
 };
 const service=new WalletTransfers({rpcUrl:'https://rpc.example',store,fetch});
 const preview=await service.preview({userId:'u1',wallet:me.wallet,asset:'SOL',destination:friend.wallet,amountRaw:'1000000'});
 const input={userId:'u1',wallet:me.wallet,reviewToken:preview.reviewToken,signedTransaction:signWire(preview.unsignedTransaction,me.wallet,me.key)};
 const replies=await Promise.all([service.execute(input),service.execute(input)]);
 assert.equal(replies[0]!.signature,replies[1]!.signature);assert.equal(broadcasts,1);
 const restarted=new WalletTransfers({rpcUrl:'https://rpc.example',store,fetch});
 assert.deepEqual(await restarted.execute(input),replies[0]);assert.equal(broadcasts,1);
 await assert.rejects(restarted.preview({userId:'u1',wallet:me.wallet,asset:'SOL',destination:friend.wallet,amountRaw:'1000000'}),/TRANSFER_PENDING/);
 assert.equal((await restarted.recovery('u1',me.wallet,preview.id))?.status,'pending');
 assert.equal(await restarted.recovery('u2',me.wallet,preview.id),null);
 confirmed=true;
 assert.equal((await restarted.recovery('u1',me.wallet,preview.id))?.status,'confirmed');
 assert.equal(broadcasts,1);
});

it('a failed durable write never broadcasts, and malformed expiry evidence never unlocks a send',async()=>{
 const me=keypair(),friend=keypair(),store=new MemoryTransferStore();
 let height=900,valid:unknown=true,slot=20,historySlot=20,entry:unknown=null;
 const rpc=chain({[me.wallet]:wallet(50_000_000)},{simulate:()=>[wallet(48_994_900),wallet(1_000_000)]});
 const fetch:typeof globalThis.fetch=async(url,init)=>{
  const {id,method}=JSON.parse(String(init?.body));
  if(method==='getBlockHeight')return Response.json({jsonrpc:'2.0',id,result:height});
  if(method==='getSignatureStatuses')return Response.json({jsonrpc:'2.0',id,result:{context:{slot:historySlot},value:[entry]}});
  if(method==='isBlockhashValid')return Response.json({jsonrpc:'2.0',id,result:{context:{slot},value:valid}});
  return rpc.fetch(url,init);
 };
 const service=new WalletTransfers({rpcUrl:'https://rpc.example',store,fetch});
 const preview=await service.preview({userId:'u1',wallet:me.wallet,asset:'SOL',destination:friend.wallet,amountRaw:'1000000'});
 const input={userId:'u1',wallet:me.wallet,reviewToken:preview.reviewToken,signedTransaction:signWire(preview.unsignedTransaction,me.wallet,me.key)};
 const begin=store.begin.bind(store);store.begin=async()=>{throw Error('database down');};
 await assert.rejects(service.execute(input),/database down/);assert.equal(rpc.sent.length,0);
 store.begin=begin;await service.execute(input);height=1001;
 assert.equal((await service.recovery('u1',me.wallet,preview.id))?.status,'pending');
 valid='false';await assert.rejects(service.recovery('u1',me.wallet,preview.id),{code:'TRANSFER_UNAVAILABLE'});
 valid=false;slot=0;await assert.rejects(service.recovery('u1',me.wallet,preview.id),{code:'TRANSFER_UNAVAILABLE'});
 slot=20;historySlot=19;assert.equal((await service.recovery('u1',me.wallet,preview.id))?.status,'pending');
 historySlot=20;entry={slot:20,err:{InstructionError:[0,'InvalidArgument']},confirmationStatus:'processed'};
 assert.equal((await service.recovery('u1',me.wallet,preview.id))?.status,'pending');
 entry={slot:20};await assert.rejects(service.recovery('u1',me.wallet,preview.id),{code:'TRANSFER_UNAVAILABLE'});
 entry=null;assert.equal((await service.recovery('u1',me.wallet,preview.id))?.status,'expired');
 assert.equal((await service.statusFor('u1',me.wallet,(await store.read('u1'))!.signature!)).status,'expired');
});
