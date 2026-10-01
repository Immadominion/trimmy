import assert from 'node:assert/strict';
import test from 'node:test';
import {bytesToBase64, parseTransaction} from '../src/product/money/solana-wire.js';
import {AccountWalletClient} from '../src/product/money/wallet-client.js';
import {coherentHoldings, MoneyWallet, WalletSignError} from '../src/product/money/wallet-controller.js';
import {createProductWalletSdk, embeddedSolanaWallets, type EmbeddedSolanaSnapshot} from '../src/product/money/wallet-sdk-loader.js';
import {ACCOUNT_ID, SUBJECT, contextJson, holdingsJson, message, signer, signSlot, unsigned} from './support/money-fixtures.js';

function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(done => {resolve = done;}); return {promise, resolve};}
interface Server {linked: string | null; holdingsWallet?: string; slot: number; fail?: 'network' | null; seen: {url: string; init: RequestInit}[]}

async function setup(options: {linked?: boolean; privyWallets?: number} = {}) {
  const user = await signer();
  const server: Server = {linked: options.linked === false ? null : user.address, slot: 400, fail: null, seen: []};
  const fetch = (async (url: string | URL | Request, init: RequestInit = {}) => {
    server.seen.push({url: String(url), init});
    if (server.fail === 'network') throw new TypeError('offline');
    if (String(url).endsWith('/context')) return Response.json(contextJson(server.linked));
    return Response.json(holdingsJson(server.holdingsWallet ?? server.linked!, {slot: server.slot}));
  }) as typeof globalThis.fetch;
  const identity = new AbortController();
  const privy = {subject: SUBJECT as string | null, ready: true, wallets: Array.from({length: options.privyWallets ?? 1}, (_, index) => index === 0 ? user.address : 'So11111111111111111111111111111111111111112'),
    creates: 0, refreshes: 0, signs: 0, sign: null as null | ((bytes: Uint8Array) => Promise<Uint8Array>)};
  const snapshot = (): EmbeddedSolanaSnapshot => ({ready: privy.ready, subject: privy.subject, wallets: privy.wallets.map(address => ({address})),
    signable: [...privy.wallets],
    refreshUser: async () => {privy.refreshes++; return {subject: privy.subject, wallets: privy.wallets.map(address => ({address}))};},
    createWallet: async () => {privy.creates++; privy.wallets = [user.address]; return user.address;},
    signTransaction: async (address, bytes) => {
      privy.signs++;
      if (privy.sign) return privy.sign(bytes);
      return signSlot(bytes, parseTransaction(bytes).signers.indexOf(address), user);
    }});
  const access = {subject: SUBJECT, accountId: ACCOUNT_ID, signal: identity.signal, freshAccessToken: async () => identity.signal.aborted ? null : 'aaa.bbb.ccc'};
  const client = new AccountWalletClient({baseUrl: '/api', accountId: ACCOUNT_ID, bearer: access.freshAccessToken, fetch});
  const wallet = new MoneyWallet({access, client, embedded: snapshot, signingTimeoutMs: 200});
  return {user, server, privy, identity, wallet};
}

test('refresh reads the linked wallet, then holdings v2 for that wallet, and keeps a confirmed trade’s slot floor', async () => {
  const {user, server, wallet} = await setup();
  await wallet.refresh();
  assert.equal(wallet.state.phase, 'ready'); assert.equal(wallet.fresh(), true);
  assert.equal(coherentHoldings(wallet.state)?.walletAddress, user.address);
  assert.equal(server.seen.filter(item => item.url.endsWith('/context')).length, 1);
  server.slot = 500;
  await wallet.refreshAfterTrade(900);
  assert.equal(new Headers(server.seen.at(-1)!.init.headers as Record<string, string>).get('x-trimmy-holdings-min-slot'), '900');
  assert.equal(wallet.state.phase, 'stale', 'a read older than the confirmed slot is never presented as current');
  server.slot = 901; await wallet.refresh();
  assert.equal(wallet.state.phase, 'ready');
  server.fail = 'network'; await wallet.refresh();
  assert.equal(wallet.state.phase, 'offline'); assert.ok(wallet.state.holdings, 'the last holdings stay visible, marked as not current');
  assert.equal(wallet.fresh(), false);
  server.fail = null; server.holdingsWallet = (await signer()).address; await wallet.refresh();
  assert.equal(wallet.state.issue, 'wallet-changed'); assert.equal(coherentHoldings(wallet.state), null);
});

test('a missing wallet is reported without inventing holdings, and a setup creates exactly one wallet that the server must link', async () => {
  const {user, server, privy, wallet} = await setup({linked: false, privyWallets: 0});
  await wallet.refresh();
  assert.equal(wallet.state.issue, 'wallet-missing'); assert.equal(wallet.state.holdings, null);
  assert.equal(server.seen.some(item => item.url.endsWith('/holdings')), false);
  // The server still reports the old "missing" read: Trimmy waits for it instead of trusting the SDK alone.
  assert.equal(await wallet.setUpWallet(), 'awaiting-server');
  assert.equal(privy.creates, 1);
  const fresh = server.seen.filter(item => item.url.endsWith('/context')).at(-1)!;
  assert.equal(fresh.init.cache, 'no-store', 'the linked-wallet read after setup bypasses the server cache');
  server.linked = user.address;
  assert.equal(await wallet.setUpWallet(), 'ready');
  assert.equal(privy.creates, 1, 'a wallet that already exists is never created twice');
  assert.equal(wallet.state.phase, 'ready');
});

test('setup refuses more than one embedded wallet and an account that changes mid-flight', async () => {
  const two = await setup({linked: false, privyWallets: 2});
  assert.equal(await two.wallet.setUpWallet(), 'unavailable'); assert.equal(two.privy.creates, 0);
  const switched = await setup({linked: false, privyWallets: 0});
  switched.privy.subject = 'did:privy:someoneElse';
  assert.equal(switched.wallet.canSetUpWallet, false); assert.equal(await switched.wallet.setUpWallet(), 'unavailable');
  const signedOut = await setup({linked: false, privyWallets: 0});
  signedOut.identity.abort();
  assert.equal(await signedOut.wallet.setUpWallet(), 'unavailable'); assert.equal(signedOut.privy.creates, 0);
});

test('signing fills only the user slot of the exact reviewed RFQ transaction and re-checks the account and wallet', async () => {
  const {user, privy, identity, wallet} = await setup();
  await wallet.refresh();
  const maker = await signer();
  const transaction = bytesToBase64(unsigned(message([maker.address, user.address], {version: 0}), 2));
  const expiresAt = new Date(Date.now() + 30_000).toISOString();
  const signed = await wallet.signReviewedTransaction({wallet: user.address, transaction, expiresAt, route: 'rfq'});
  assert.equal(parseTransaction(Uint8Array.from(atob(signed), char => char.charCodeAt(0))).signatures[0]!.every(byte => byte === 0), true);
  const code = (promise: Promise<unknown>) => promise.then(() => 'signed', (error: WalletSignError) => error.code);
  assert.equal(await code(wallet.signReviewedTransaction({wallet: user.address, transaction, expiresAt: new Date(Date.now() - 1).toISOString(), route: 'rfq'})), 'QUOTE_EXPIRED');
  assert.equal(await code(wallet.signReviewedTransaction({wallet: maker.address, transaction, expiresAt, route: 'rfq'})), 'WALLET_CHANGED');
  assert.equal(await code(wallet.signReviewedTransaction({wallet: user.address, transaction, expiresAt, route: 'aggregator'})), 'INVALID_TRANSACTION');
  privy.sign = async bytes => {const out = await signSlot(bytes, 1, user); out[out.length - 1] = out.at(-1)! ^ 1; return out;};
  assert.equal(await code(wallet.signReviewedTransaction({wallet: user.address, transaction, expiresAt, route: 'rfq'})), 'SIGNATURE_MISMATCH');
  privy.sign = async bytes => {const out = await signSlot(bytes, 1, user); return signSlot(out, 0, maker);};
  assert.equal(await code(wallet.signReviewedTransaction({wallet: user.address, transaction, expiresAt, route: 'rfq'})), 'SIGNATURE_MISMATCH',
    'a wallet that also fills the market maker slot is refused');
  privy.sign = async bytes => {privy.subject = 'did:privy:other'; return signSlot(bytes, 1, user);};
  assert.equal(await code(wallet.signReviewedTransaction({wallet: user.address, transaction, expiresAt, route: 'rfq'})), 'ACCOUNT_CHANGED');
  privy.subject = SUBJECT; privy.sign = null;
  identity.abort();
  assert.equal(await code(wallet.signReviewedTransaction({wallet: user.address, transaction, expiresAt, route: 'rfq'})), 'ACCOUNT_CHANGED');
});

test('a slow wallet times out without releasing the signing lock until the wallet itself settles', async () => {
  const {user, privy, wallet} = await setup();
  await wallet.refresh();
  const transaction = bytesToBase64(unsigned(message([user.address]), 1));
  const expiresAt = new Date(Date.now() + 30_000).toISOString();
  const slow = deferred<Uint8Array>();
  privy.sign = () => slow.promise;
  await assert.rejects(wallet.signReviewedTransaction({wallet: user.address, transaction, expiresAt, route: 'aggregator'}),
    (error: WalletSignError) => error.code === 'SIGNING_TIMEOUT');
  assert.equal(wallet.state.signing, true);
  await assert.rejects(wallet.signReviewedTransaction({wallet: user.address, transaction, expiresAt, route: 'aggregator'}),
    (error: WalletSignError) => error.code === 'WALLET_BUSY');
  slow.resolve(new Uint8Array(0)); await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal(wallet.state.signing, false); assert.equal(privy.signs, 1);
});

test('the Privy boundary counts only embedded Solana wallets and confirms direct sends', async () => {
  const user = await signer();
  assert.deepEqual(embeddedSolanaWallets({linkedAccounts: [{type: 'wallet', walletClientType: 'privy', chainType: 'solana', address: user.address},
    {type: 'wallet', walletClientType: 'phantom', chainType: 'solana', address: 'So11111111111111111111111111111111111111112'},
    {type: 'wallet', walletClientType: 'privy', chainType: 'ethereum', address: '0xabc'}, {type: 'email', address: 'a@b.c'}]}), [{address: user.address}]);
  assert.equal(embeddedSolanaWallets({linkedAccounts: [{type: 'wallet', walletClientType: 'privy', chainType: 'solana', address: 'bad'}]}), null);
  const calls: unknown[] = [];
  const connected = {address: user.address, standardWallet: {isPrivyWallet: true}};
  const external = {address: 'So11111111111111111111111111111111111111112', standardWallet: {isPrivyWallet: false}};
  const port = createProductWalletSdk({
    usePrivy: () => ({ready: true, authenticated: true, user: {id: SUBJECT, linkedAccounts: [{type: 'wallet', walletClientType: 'privy', chainType: 'solana', address: user.address}]}}),
    useUser: () => ({refreshUser: async () => ({id: SUBJECT, linkedAccounts: []})}),
  }, {
    useWallets: () => ({ready: true, wallets: [connected, external]}),
    useCreateWallet: () => ({createWallet: async () => ({wallet: {address: user.address}})}),
    useSignTransaction: () => ({signTransaction: async (input: {transaction: Uint8Array}) => {calls.push(input); return {signedTransaction: input.transaction};}}),
  });
  const snapshot = port.useEmbeddedSolana();
  assert.deepEqual(snapshot.signable, [user.address]); assert.equal(snapshot.subject, SUBJECT); assert.equal(snapshot.ready, true);
  await snapshot.signTransaction(user.address, new Uint8Array([1]));
  assert.deepEqual((calls[0] as {options: unknown}).options, {uiOptions: {showWalletUIs: false}});
  assert.equal((calls[0] as {wallet: unknown}).wallet, connected);
  await snapshot.signTransaction(user.address, new Uint8Array([1]), {confirm: true});
  assert.deepEqual((calls[1] as {options: unknown}).options, {uiOptions: {showWalletUIs: true}});
  await assert.rejects(snapshot.signTransaction(external.address, new Uint8Array([1])));
  assert.throws(() => createProductWalletSdk({}, {}));
});

test('wallet setup waits only for Privy’s session, while signing waits for the connected wallet', async () => {
  const user = await signer();
  let walletsReady = false;
  const port = createProductWalletSdk({
    usePrivy: () => ({ready: true, authenticated: true, user: {id: SUBJECT, linkedAccounts: []}}),
    useUser: () => ({refreshUser: async () => ({id: SUBJECT, linkedAccounts: []})}),
  }, {
    useWallets: () => ({ready: walletsReady, wallets: walletsReady ? [{address: user.address, standardWallet: {isPrivyWallet: true}}] : []}),
    useCreateWallet: () => ({createWallet: async () => ({wallet: {address: user.address}})}),
    useSignTransaction: () => ({signTransaction: async (input: {transaction: Uint8Array}) => ({signedTransaction: input.transaction})}),
  });
  const before = port.useEmbeddedSolana();
  assert.equal(before.ready, true, 'a user without a wallet can still create one'); assert.deepEqual(before.signable, []);
  walletsReady = true;
  assert.deepEqual(port.useEmbeddedSolana().signable, [user.address]);
});
