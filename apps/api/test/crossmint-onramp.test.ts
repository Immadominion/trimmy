import assert from 'node:assert/strict';
import {test} from 'node:test';
import {generateKeyPairSync, sign} from 'node:crypto';
import {getBase58Decoder} from '@solana/kit';
import {buildApp} from '../src/app.js';
import {CrossmintOnramp, readCrossmintOnramp} from '../src/crossmint-onramp.js';

const user = '10000000-0000-4000-a000-000000000001';
const keys = generateKeyPairSync('ed25519');
const wallet = getBase58Decoder().decode(keys.publicKey.export({format: 'der', type: 'spki'}).subarray(-32));
const identity = {provider: 'privy', appId: 'trimmy_test_app', subject: 'did:privy:onramptest'} as const;
const configuration = {environment: 'staging', serverKey: 'sk_staging_server_secret', clientKey: 'ck_staging_public'} as const;
const challenge = `crossmint.com wants you to sign in with your blockchain account:\n${wallet}\n\nI am signing this message to prove ownership.\n\nURI: https://crossmint.com`;

function fixture() {
  const requests: Array<{url: string; body: any}> = [];
  let linked = false, delivered = false, phase = 'payment', statusWallet = wallet, userId = user;
  let providerFails = false;
  const service = new CrossmintOnramp(configuration, {fetch: async (url, init) => {
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    requests.push({url: String(url), body});
    if (providerFails) return new Response(JSON.stringify({secret: 'never return me'}), {status: 403});
    if (String(url).includes('linked-wallets')) {
      if (body.proof) linked = true;
      return Response.json({address: wallet, chain: 'solana', ownership: linked ? {verified: true} : {verified: false, verificationChallenge: challenge}});
    }
    if (init?.method === 'POST') return Response.json({order: {orderId: 'order_test'}, clientSecret: 'order_only_secret'});
    return Response.json({orderId: 'order_test', phase, lineItems: [{chain: 'solana', delivery: {
      status: delivered ? 'completed' : 'in-progress', recipient: {walletAddress: statusWallet},
    }}]});
  }});
  const app = buildApp({logger: false, onramp: {service,
    authenticate: async (req) => req.headers.authorization === 'Bearer verified' ? {userId, identity} : null,
    linkedIdentities: {resolve: async () => ({provider: 'privy', subject: identity.subject, twitter: {status: 'missing'},
      embeddedSolanaWallet: {status: 'candidate', address: wallet, verifiedAtUnixSeconds: 1}})},
  }});
  const post = (path: string, payload: Record<string, unknown>, auth = 'Bearer verified') => app.inject({method: 'POST', url: `/v1/funding/${path}`, headers: {authorization: auth}, payload});
  return {app, service, requests, post, setLinked: () => {linked = true;},
    complete: () => {delivered = true;}, phaseComplete: () => {phase = 'completed';},
    wrongRecipient: () => {statusWallet = 'different-wallet';},
    otherUser: () => {userId = '20000000-0000-4000-a000-000000000002';}, failProvider: () => {providerFails = true;}};
}

test('onramp is opt-in and rejects mixed staging/production keys', async () => {
  assert.equal(readCrossmintOnramp({}), undefined);
  assert.throws(() => readCrossmintOnramp({CROSSMINT_ENVIRONMENT: 'production',
    CROSSMINT_SERVER_SIDE_API_KEY: 'sk_staging_secret', CROSSMINT_CLIENT_SIDE_API_KEY: 'ck_production_public'}));
  const app = buildApp({logger: false});
  try { assert.deepEqual((await app.inject('/v1/funding/capabilities')).json(), {enabled: false}); }
  finally { await app.close(); }
});

test('guests cannot link wallets or create onramp orders; secrets never leak on provider failures', async () => {
  const f = fixture();
  try {
    assert.equal((await f.post('wallet', {email: 'buyer@example.com'}, 'Bearer guest')).statusCode, 401);
    assert.equal(f.requests.length, 0);
    f.failProvider();
    const response = await f.post('wallet', {email: 'buyer@example.com'});
    assert.deepEqual(response.json(), {code: 'ONRAMP_NOT_ENABLED'});
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.ok(!response.body.includes('never return me'));
  } finally { await f.app.close(); }
});

test('wallet proof is verified, recipient and mint are server-bound, repeats reuse an unpaid order', async () => {
  const f = fixture();
  try {
    const preparation = (await f.post('wallet', {email: 'buyer@example.com'})).json();
    assert.equal(preparation.wallet, wallet);
    const invalid = await f.post('verify', {challengeToken: preparation.challengeToken, proof: Buffer.alloc(64).toString('base64')});
    assert.equal(invalid.statusCode, 400);
    const proof = sign(null, Buffer.from(challenge), keys.privateKey).toString('base64');
    const verified = (await f.post('verify', {challengeToken: preparation.challengeToken, proof})).json();
    assert.equal(verified.verified, true);
    const input = {walletToken: verified.walletToken, amount: '50', requestId: '12345678-1234-4234-8234-123456789012'};
    const order = (await f.post('orders', input)).json();
    assert.equal(order.orderId, 'order_test');
    assert.equal(order.environment, 'staging');
    const creation = f.requests.find(r => r.body?.lineItems);
    assert.deepEqual(creation?.body.recipient, {walletAddress: wallet});
    assert.equal(creation?.body.lineItems[0].tokenLocator, 'solana:4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU');
    assert.equal(creation?.body.payment.currency, 'usd');
    assert.deepEqual((await f.post('orders', input)).json(), order);
    assert.equal(f.requests.filter(r => r.body?.lineItems).length, 1);
    assert.equal((await f.post('orders', {...input, amount: '100'})).statusCode, 409);
    // Payment/phase completion alone must never report that funds arrived.
    f.phaseComplete();
    assert.equal((await f.post('status', {orderToken: order.orderToken})).json().status, 'pending');
    f.complete();
    assert.equal((await f.post('status', {orderToken: order.orderToken})).json().status, 'completed');
    f.wrongRecipient();
    assert.equal((await f.post('status', {orderToken: order.orderToken})).json().status, 'pending');
    f.otherUser();
    assert.equal((await f.post('status', {orderToken: order.orderToken})).statusCode, 400);
  } finally { await f.app.close(); }
});

test('invalid amounts and tampered wallet grants cannot create orders', async () => {
  const f = fixture(); f.setLinked();
  try {
    const linked = (await f.post('wallet', {email: 'buyer@example.com'})).json();
    const input = {walletToken: linked.walletToken, requestId: '12345678-1234-4234-8234-123456789012'};
    for (const amount of ['-1', '0', '4.99', '10001', '1e3', '50.001']) {
      assert.equal((await f.post('orders', {...input, amount})).statusCode, 400);
    }
    const [body] = linked.walletToken.split('.');
    const tampered = `${body}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`;
    assert.equal((await f.post('orders', {...input, amount: '50', walletToken: tampered})).statusCode, 400);
    assert.equal(f.requests.filter(r => r.body?.lineItems).length, 0);
  } finally { await f.app.close(); }
});
