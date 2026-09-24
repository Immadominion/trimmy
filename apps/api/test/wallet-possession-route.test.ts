import assert from 'node:assert/strict';
import { createHash, createPrivateKey, createPublicKey, sign as signBytes } from 'node:crypto';
import { test } from 'node:test';
import { getAddressDecoder, getBase58Decoder } from '@solana/kit';
import { buildApp } from '../src/app.js';
import type { PracticeIdentity } from '../src/practice-identity.js';
import { createPracticeAccountContextAuthenticator, PracticeAuthenticationUnavailable } from '../src/practice-session-routes.js';
import { PrivyLinkedIdentityError, PrivyLinkedIdentityResolver } from '../src/privy-linked-identities.js';
import type { PrivyLinkedIdentityResolution } from '../src/privy-linked-identities.js';
import { InMemoryWalletBindingStore, InMemoryWalletPossessionChallengeStore, WalletPossessionError,
  WalletPossessionService } from '../src/wallet-possession.js';
import { WALLET_CHALLENGE_ROUTE, WALLET_POSSESSION_ROUTE } from '../src/wallet-possession-route.js';
import type { WalletPossessionAdapters, WalletPossessionIdentityResolver } from '../src/wallet-possession-route.js';
import { PRACTICE_SESSION_ROUTE } from '../src/practice-session-routes.js';

const appId = 'trimmy_test_app';
const subject = 'did:privy:walletsubject';
const userId = '10000000-0000-4000-a000-000000000001';
const token = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const identity: PracticeIdentity = {provider: 'privy', appId, subject};

function keypair(label: string) {
  const seed = createHash('sha256').update(`trimmy-route-${label}`).digest();
  const pkcs8 = Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]);
  const privateKey = createPrivateKey({key: pkcs8, format: 'der', type: 'pkcs8'});
  const spki = createPublicKey(privateKey).export({format: 'der', type: 'spki'});
  return {
    address: getAddressDecoder().decode(Uint8Array.from(spki.subarray(spki.length - 32))),
    sign: (message: string) => getBase58Decoder().decode(signBytes(null, Buffer.from(message, 'utf8'), privateKey)),
  };
}
const wallet = keypair('wallet');
const stranger = keypair('stranger');

function resolution(overrides: Partial<PrivyLinkedIdentityResolution['embeddedSolanaWallet']> = {}): PrivyLinkedIdentityResolution {
  return Object.freeze({
    provider: 'privy', subject, twitter: Object.freeze({status: 'missing'}),
    embeddedSolanaWallet: Object.freeze({
      status: 'candidate', address: wallet.address, verifiedAtUnixSeconds: 1_757_845_201, ...overrides,
    }) as PrivyLinkedIdentityResolution['embeddedSolanaWallet'],
  });
}

function adapters(overrides: Omit<Partial<WalletPossessionAdapters>, 'linkedIdentities'> & {
  linkedIdentities?: Pick<WalletPossessionIdentityResolver, 'resolve'> & Partial<Pick<WalletPossessionIdentityResolver, 'resolveFresh'>>;
  now?: () => number; perUserLimit?: number} = {}) {
  const clock = overrides.now ?? (() => Date.parse('2026-09-15T08:00:00.000Z'));
  const challenges = new InMemoryWalletPossessionChallengeStore({now: clock});
  const bindings = new InMemoryWalletBindingStore();
  const service = new WalletPossessionService({
    challenges, bindings, now: clock,
    ...(overrides.perUserLimit !== undefined ? {perUserLimit: overrides.perUserLimit} : {}),
  });
  const built: WalletPossessionAdapters = {
    authenticate: async () => ({userId, identity}),
    linkedIdentities: {resolve: async () => resolution(), resolveFresh: async () => resolution()},
    service, network: 'mainnet-beta',
    ...(overrides.authenticate ? {authenticate: overrides.authenticate} : {}),
    ...(overrides.linkedIdentities ? {linkedIdentities: {
      resolve: overrides.linkedIdentities.resolve.bind(overrides.linkedIdentities),
      resolveFresh: (overrides.linkedIdentities.resolveFresh ?? overrides.linkedIdentities.resolve)
        .bind(overrides.linkedIdentities),
    }} : {}),
    ...(overrides.service ? {service: overrides.service} : {}),
    ...(overrides.network ? {network: overrides.network} : {}),
  };
  return {adapters: built, challenges, bindings, service};
}

test('wallet checks are absent until configured and appear in the config flag', async () => {
  const bare = buildApp({logger: false});
  try {
    assert.equal(bare.inject === undefined, false);
    const challenge = await bare.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
    assert.equal(challenge.statusCode, 503);
    assert.equal(challenge.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
    const config = await bare.inject('/v1/config');
    assert.equal(config.json().walletPossessionEnabled, false);
  } finally { await bare.close(); }
  const {adapters: configured} = adapters();
  const instance = buildApp({logger: false, walletPossession: configured});
  try {
    const config = await instance.inject('/v1/config');
    assert.equal(config.json().walletPossessionEnabled, true);
  } finally { await instance.close(); }
});

test('the money gate admits exactly the two wallet writes', async () => {
  const {adapters: configured} = adapters();
  const instance = buildApp({logger: false, walletPossession: configured});
  try {
    const challenge = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
    assert.equal(challenge.statusCode, 201);
    // Another POST on a configured build still hits the financial gate.
    const order = await instance.inject({method: 'POST', url: '/v1/orders', payload: {}});
    assert.equal(order.statusCode, 503);
    assert.equal(order.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
    for (const method of ['PUT', 'DELETE', 'PATCH'] as const) {
      const response = await instance.inject({method, url: WALLET_POSSESSION_ROUTE, payload: {}});
      assert.equal(response.statusCode, 503);
      assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
    }
  } finally { await instance.close(); }
});

test('a real wallet signature over the issued message records a binding', async () => {
  const context = adapters();
  const instance = buildApp({logger: false, walletPossession: context.adapters});
  try {
    const issued = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
    assert.equal(issued.statusCode, 201);
    assert.equal(issued.headers['cache-control'], 'no-store');
    const challenge = issued.json().challenge as {challengeId: string; walletAddress: string; message: string;
      network: string; issuedAt: string; expiresAt: string};
    assert.equal(challenge.walletAddress, wallet.address);
    assert.equal(challenge.network, 'mainnet-beta');
    assert.ok(challenge.message.startsWith('Trimmy wallet possession\n'));
    assert.ok(challenge.message.includes('It authorizes no transfer, swap or payment.'));
    // The account and wallet are inside the signed text, so the proof cannot be
    // replayed for another account; the response adds no field of its own.
    assert.ok(challenge.message.includes(`account: ${userId}`));
    assert.ok(challenge.message.includes(`wallet: ${wallet.address}`));
    assert.deepEqual(Object.keys(issued.json()).sort(), ['challenge', 'schemaVersion']);
    assert.deepEqual(Object.keys(challenge).sort(),
      ['challengeId', 'expiresAt', 'issuedAt', 'message', 'network', 'walletAddress']);

    const verified = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
      payload: {challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)}});
    assert.equal(verified.statusCode, 200);
    assert.equal(verified.headers['cache-control'], 'no-store');
    const body = verified.json() as {kind: string; walletAddress: string; possessionSignatureVerified: boolean;
      network: string; binding: {id: string}};
    assert.equal(body.kind, 'wallet_possession');
    assert.equal(body.walletAddress, wallet.address);
    assert.equal(body.possessionSignatureVerified, true);
    assert.equal(body.network, 'mainnet-beta');
    assert.equal(context.bindings.list().length, 1);
    assert.equal(context.bindings.list()[0]?.address, wallet.address);
    assert.equal(context.bindings.list()[0]?.userId, userId);
  } finally { await instance.close(); }
});

test('a wrong signature, a reused challenge and an unknown challenge are conflicts', async () => {
  const context = adapters({perUserLimit: 10});
  const instance = buildApp({logger: false, walletPossession: context.adapters});
  try {
    const first = (await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).json().challenge;
    const wrong = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
      payload: {challengeId: first.challengeId, signature: stranger.sign(first.message)}});
    assert.equal(wrong.statusCode, 409);
    assert.equal(wrong.json().error.code, 'WALLET_POSSESSION_SIGNATURE_INVALID');
    assert.ok(!JSON.stringify(wrong.json()).includes(stranger.address));

    const second = (await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).json().challenge;
    const signature = wallet.sign(second.message);
    assert.equal((await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
      payload: {challengeId: second.challengeId, signature}})).statusCode, 200);
    const replay = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
      payload: {challengeId: second.challengeId, signature}});
    assert.equal(replay.statusCode, 409);
    assert.equal(replay.json().error.code, 'WALLET_POSSESSION_CHALLENGE_NOT_FOUND');
    const unknown = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
      payload: {challengeId: '33333333-4444-4555-8666-777777777777', signature}});
    assert.equal(unknown.statusCode, 409);
    assert.equal(unknown.json().error.code, 'WALLET_POSSESSION_CHALLENGE_NOT_FOUND');
    assert.equal(context.bindings.list().length, 1);
  } finally { await instance.close(); }
});

test('possession rechecks the same subject and refuses missing, ambiguous or malformed current links', async () => {
  const failures: readonly [PrivyLinkedIdentityResolution, number, string][] = [
    [resolution({status: 'missing'}), 409, 'ACCOUNT_WALLET_MISSING'],
    [resolution({status: 'ambiguous'}), 409, 'ACCOUNT_WALLET_AMBIGUOUS'],
    [{...resolution(), subject: 'did:privy:anotheraccount'}, 502, 'PRIVY_USER_RESPONSE_INVALID'],
    [resolution({walletId: ''}), 502, 'PRIVY_USER_RESPONSE_INVALID'],
  ];
  for (const [failure, status, code] of failures) {
    let current = failure;
    let freshReads = 0;
    const context = adapters({linkedIdentities: {
      resolve: async () => resolution(),
      resolveFresh: async observed => { assert.deepEqual(observed, identity); freshReads++; return current; },
    }});
    const instance = buildApp({logger: false, walletPossession: context.adapters});
    try {
      const issued = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
      assert.equal(issued.statusCode, 201);
      const challenge = issued.json().challenge;
      const payload = {challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)};
      const refused = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE, payload});
      assert.equal(refused.statusCode, status);
      assert.equal(refused.json().error.code, code);
      assert.equal(context.bindings.list().length, 0);
      assert.equal(context.challenges.size, 1);
      current = resolution();
      assert.equal((await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE, payload})).statusCode, 200);
      assert.equal(freshReads, 2);
    } finally { await instance.close(); }
  }
});

test('provider failures leave an unexpired proof retryable without accepting stale linkage', async () => {
  for (const [providerCode, status] of [['PRIVY_USER_UNAVAILABLE', 502], ['PRIVY_USER_TIMEOUT', 504],
    ['PRIVY_USER_RATE_LIMITED', 429]] as const) {
    let unavailable = true;
    const context = adapters({linkedIdentities: {
      resolve: async () => resolution(),
      resolveFresh: async () => { if (unavailable) throw new PrivyLinkedIdentityError(providerCode); return resolution(); },
    }});
    const instance = buildApp({logger: false, walletPossession: context.adapters});
    try {
      const challenge = (await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).json().challenge;
      const payload = {challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)};
      const refused = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE, payload});
      assert.equal(refused.statusCode, status);
      assert.equal(refused.json().error.code, providerCode);
      assert.equal(context.challenges.size, 1);
      assert.equal(context.bindings.list().length, 0);
      unavailable = false;
      assert.equal((await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE, payload})).statusCode, 200);
    } finally { await instance.close(); }
  }
});

test('a replaced address or provider wallet ID consumes the old challenge without recording a binding', async () => {
  for (const changed of [resolution({address: stranger.address, walletId: 'wallet-1'}),
    resolution({walletId: 'wallet-2'}), resolution()]) {
    let current = changed;
    const original = resolution({walletId: 'wallet-1'});
    const context = adapters({linkedIdentities: {
      resolve: async () => original,
      resolveFresh: async () => current,
    }});
    const instance = buildApp({logger: false, walletPossession: context.adapters});
    try {
      const challenge = (await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).json().challenge;
      assert.equal('providerWalletId' in challenge, false);
      const payload = {challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)};
      const refused = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE, payload});
      assert.equal(refused.statusCode, 409);
      assert.equal(refused.json().error.code, 'WALLET_POSSESSION_WALLET_CHANGED');
      assert.equal(context.bindings.list().length, 0);
      assert.equal(context.challenges.size, 0);
      current = original;
      const replay = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE, payload});
      assert.equal(replay.json().error.code, 'WALLET_POSSESSION_CHALLENGE_NOT_FOUND');
    } finally { await instance.close(); }
  }
});

test('real resolver bypasses a cached linked wallet after unlinking between challenge and proof', async () => {
  let linked = true;
  let reads = 0;
  const resolver = new PrivyLinkedIdentityResolver({appId, appSecret: 'test-only-secret', now: () => 10_000,
    clientFactory: () => ({getById: async () => {
      reads++;
      return {id: subject, linked_accounts: linked ? [{type: 'wallet', chain_type: 'solana',
        connector_type: 'embedded', wallet_client: 'privy', wallet_client_type: 'privy',
        address: wallet.address, id: 'wallet-1', verified_at: 1_757_845_201,
        delegated: false, imported: false, wallet_index: 0}] : []};
    }})});
  const context = adapters({linkedIdentities: resolver});
  const instance = buildApp({logger: false, walletPossession: context.adapters});
  try {
    const issued = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
    assert.equal(issued.statusCode, 201);
    const challenge = issued.json().challenge;
    linked = false;
    assert.equal((await resolver.resolve(identity)).embeddedSolanaWallet.status, 'candidate');
    const refused = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
      payload: {challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)}});
    assert.equal(refused.statusCode, 409);
    assert.equal(refused.json().error.code, 'ACCOUNT_WALLET_MISSING');
    assert.equal(reads, 2);
    assert.equal(context.bindings.list().length, 0);
  } finally { await instance.close(); }
});

test('concurrent submissions each recheck linkage but only one consumes the challenge', async () => {
  let reads = 0;
  const context = adapters({linkedIdentities: {
    resolve: async () => resolution(), resolveFresh: async () => { reads++; return resolution(); },
  }});
  const instance = buildApp({logger: false, walletPossession: context.adapters});
  try {
    const challenge = (await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).json().challenge;
    const payload = {challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)};
    const results = await Promise.all([1, 2].map(() => instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE, payload})));
    assert.deepEqual(results.map(result => result.statusCode).sort(), [200, 409]);
    assert.equal(results.find(result => result.statusCode === 409)!.json().error.code, 'WALLET_POSSESSION_CHALLENGE_NOT_FOUND');
    assert.equal(reads, 2);
    assert.equal(context.bindings.list().length, 1);
  } finally { await instance.close(); }
});

test('an expired challenge is a conflict and records nothing', async () => {
  let now = Date.parse('2026-09-15T08:00:00.000Z');
  const context = adapters({now: () => now});
  const instance = buildApp({logger: false, walletPossession: context.adapters});
  try {
    const challenge = (await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).json().challenge;
    now += 300_000;
    const expired = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
      payload: {challengeId: challenge.challengeId, signature: wallet.sign(challenge.message)}});
    assert.equal(expired.statusCode, 409);
    assert.equal(expired.json().error.code, 'WALLET_POSSESSION_CHALLENGE_EXPIRED');
    assert.equal(context.bindings.list().length, 0);
  } finally { await instance.close(); }
});

test('the body is strict and a malformed signature never reaches the service', async () => {
  let verifyCalls = 0;
  const base = adapters();
  const context = adapters({service: {
    issue: base.service.issue.bind(base.service),
    verify: async (input) => { verifyCalls += 1; return base.service.verify(input); },
  }});
  const instance = buildApp({logger: false, walletPossession: context.adapters});
  try {
    for (const payload of [
      {},
      {challengeId: 'not-a-uuid', signature: '1'.repeat(80)},
      {challengeId: '33333333-4444-4555-8666-777777777777'},
      {challengeId: '33333333-4444-4555-8666-777777777777', signature: 'short'},
      {challengeId: '33333333-4444-4555-8666-777777777777', signature: '0OIl'.repeat(20)},
      {challengeId: '33333333-4444-4555-8666-777777777777', signature: '1'.repeat(80), extra: true},
      {challengeId: '33333333-4444-4555-8666-777777777777', signature: '1'.repeat(80), walletAddress: stranger.address},
      {challengeId: '33333333-4444-4555-8666-777777777777', signature: '1'.repeat(80),
        expectedWallet: {address: stranger.address, network: 'mainnet-beta', providerWalletId: 'forged'}},
    ]) {
      const response = await instance.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE, payload});
      assert.equal(response.statusCode, 400, JSON.stringify(payload));
      assert.equal(response.json().error.code, 'INVALID_REQUEST');
    }
    assert.equal(verifyCalls, 0);
    const query = await instance.inject({method: 'POST', url: `${WALLET_CHALLENGE_ROUTE}?wallet=abc`, payload: {}});
    assert.equal(query.statusCode, 400);
  } finally { await instance.close(); }
});

test('an unauthenticated caller, an unavailable verifier and provisioning are all refused', async () => {
  let provisions = 0;
  const authenticate = createPracticeAccountContextAuthenticator({
    verifier: {verify: async input => (input === token ? identity : null)},
    accounts: {
      find: async () => ({userId}),
      provision: async () => { provisions += 1; return {userId: '20000000-0000-4000-a000-000000000002'}; },
    },
  });
  const context = adapters({authenticate});
  const instance = buildApp({logger: false, walletPossession: context.adapters});
  try {
    const anonymous = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
    assert.equal(anonymous.statusCode, 401);
    assert.equal(anonymous.json().error.code, 'ACCOUNT_WALLET_UNAUTHENTICATED');
    const authorized = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {},
      headers: {authorization: `Bearer ${token}`}});
    assert.equal(authorized.statusCode, 201);
    assert.equal(provisions, 0);
  } finally { await instance.close(); }

  const unavailable = adapters({authenticate: async () => { throw new PracticeAuthenticationUnavailable(); }});
  const second = buildApp({logger: false, walletPossession: unavailable.adapters});
  try {
    const response = await second.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
    assert.equal(response.statusCode, 503);
    assert.equal(response.json().error.code, 'ACCOUNT_WALLET_UNAVAILABLE');
  } finally { await second.close(); }
});

test('a missing or ambiguous linked wallet is a conflict and provider failures keep their codes', async () => {
  for (const [status, code] of [['missing', 'ACCOUNT_WALLET_MISSING'], ['ambiguous', 'ACCOUNT_WALLET_AMBIGUOUS']] as const) {
    const context = adapters({linkedIdentities: {resolve: async () => Object.freeze({
      provider: 'privy', subject, twitter: Object.freeze({status: 'missing'}),
      embeddedSolanaWallet: Object.freeze({status}),
    }) as PrivyLinkedIdentityResolution}});
    const instance = buildApp({logger: false, walletPossession: context.adapters});
    try {
      const response = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
      assert.equal(response.statusCode, 409);
      assert.equal(response.json().error.code, code);
    } finally { await instance.close(); }
  }
  for (const [providerCode, status] of [['PRIVY_USER_RATE_LIMITED', 429], ['PRIVY_USER_TIMEOUT', 504],
    ['PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED', 503]] as const) {
    const context = adapters({linkedIdentities: {resolve: async () => { throw new PrivyLinkedIdentityError(providerCode); }}});
    const instance = buildApp({logger: false, walletPossession: context.adapters});
    try {
      const response = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
      assert.equal(response.statusCode, status);
      assert.equal(response.json().error.code, providerCode);
    } finally { await instance.close(); }
  }
  // A resolution for a different subject is a provider response failure.
  const mismatched = adapters({linkedIdentities: {resolve: async () => Object.freeze({
    provider: 'privy', subject: 'did:privy:someoneelse', twitter: Object.freeze({status: 'missing'}),
    embeddedSolanaWallet: Object.freeze({status: 'candidate', address: wallet.address, verifiedAtUnixSeconds: 1}),
  }) as PrivyLinkedIdentityResolution}});
  const instance = buildApp({logger: false, walletPossession: mismatched.adapters});
  try {
    const response = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
    assert.equal(response.statusCode, 502);
    assert.equal(response.json().error.code, 'PRIVY_USER_RESPONSE_INVALID');
  } finally { await instance.close(); }
});

test('too many challenges and an unavailable store map to 429 and 503', async () => {
  const limited = adapters({perUserLimit: 1});
  const instance = buildApp({logger: false, walletPossession: limited.adapters});
  try {
    assert.equal((await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}})).statusCode, 201);
    const response = await instance.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
    assert.equal(response.statusCode, 429);
    assert.equal(response.json().error.code, 'WALLET_POSSESSION_RATE_LIMITED');
  } finally { await instance.close(); }

  const broken = adapters({service: {
    issue: async () => { throw new WalletPossessionError('WALLET_POSSESSION_STORE_UNAVAILABLE'); },
    verify: async () => { throw new Error('private detail'); },
  }});
  const second = buildApp({logger: false, walletPossession: broken.adapters});
  try {
    const issued = await second.inject({method: 'POST', url: WALLET_CHALLENGE_ROUTE, payload: {}});
    assert.equal(issued.statusCode, 503);
    assert.equal(issued.json().error.code, 'WALLET_POSSESSION_STORE_UNAVAILABLE');
    const verified = await second.inject({method: 'POST', url: WALLET_POSSESSION_ROUTE,
      payload: {challengeId: '33333333-4444-4555-8666-777777777777', signature: '1'.repeat(80)}});
    assert.equal(verified.statusCode, 503);
    assert.equal(verified.json().error.code, 'WALLET_POSSESSION_STORE_UNAVAILABLE');
    assert.ok(!JSON.stringify(verified.json()).includes('private detail'));
  } finally { await second.close(); }
});

test('the practice session route still works beside the wallet routes', async () => {
  const {adapters: configured} = adapters();
  const instance = buildApp({logger: false, walletPossession: configured});
  try {
    // Unconfigured practice sessions answer 503 from their own route, not the gate.
    const response = await instance.inject({method: 'POST', url: PRACTICE_SESSION_ROUTE, payload: {}});
    assert.notEqual(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
  } finally { await instance.close(); }
});
