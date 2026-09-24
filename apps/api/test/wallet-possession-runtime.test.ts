import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {test} from 'node:test';
import {getAddressDecoder} from '@solana/kit';
import {buildApp} from '../src/app.js';
import {createPracticeRuntime, readPracticeRuntimeConfig} from '../src/practice-runtime.js';
import type {PracticeRuntime} from '../src/practice-runtime.js';
import type {WalletPossessionIdentityResolver} from '../src/wallet-possession-route.js';
import {readAccountContextResolver} from '../src/account-context-route.js';
import {createWalletPossessionRuntime, readWalletPossessionRuntimeConfig} from '../src/wallet-possession-runtime.js';
import {WalletPossessionError} from '../src/wallet-possession.js';
import {PostgresWalletBindingStore} from '../src/postgres-wallet-bindings.js';

const {publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const verificationKey = publicKey.export({type: 'spki', format: 'pem'}).toString();
const env = {
  PRIVY_APP_ID: 'trimmy_runtime_test', PRIVY_APP_SECRET: 'test-runtime-secret',
  PRIVY_VERIFICATION_KEY: verificationKey,
  PRACTICE_DATABASE_URL: 'postgresql://practice:test-password@db.example.test/trimmy',
  TRIMMY_GUEST_SOURCE_MODE: 'direct',
  TRIMMY_GUEST_SOURCE_HMAC_KEY: Buffer.alloc(32, 4).toString('base64url'),
  TRIMMY_WALLET_POSSESSION: 'single_process', TRIMMY_WALLET_NETWORK: 'mainnet-beta',
};
const invalidConfig = (error: unknown) => error instanceof WalletPossessionError &&
  error.code === 'WALLET_POSSESSION_CONFIGURATION_INVALID';
const accountId = '10000000-0000-4000-a000-000000000001';
const walletKey = generateKeyPairSync('ed25519').publicKey.export({type: 'spki', format: 'der'});
const wallet = getAddressDecoder().decode(walletKey.subarray(walletKey.length - 32));
const subject = 'did:privy:runtimeWallet';
const resolveLinked: WalletPossessionIdentityResolver['resolve'] = async identity => ({
  provider: 'privy', subject: identity.subject, twitter: {status: 'missing'},
  embeddedSolanaWallet: {status: 'candidate', address: wallet, verifiedAtUnixSeconds: 1_757_845_201},
});
const resolver: WalletPossessionIdentityResolver = {resolve: resolveLinked, resolveFresh: resolveLinked};

test('wallet possession remains disabled by default even with all account credentials present', async () => {
  for (const mode of [undefined, '', 'disabled']) {
    assert.equal(readWalletPossessionRuntimeConfig({...env,
      TRIMMY_WALLET_POSSESSION: mode, TRIMMY_WALLET_NETWORK: undefined}), null);
  }
  assert.equal(readWalletPossessionRuntimeConfig({}), null);
  assert.equal(createWalletPossessionRuntime(null, {}, undefined), undefined);
  const app = buildApp({logger: false});
  try {
    assert.equal((await app.inject('/v1/config')).json().walletPossessionEnabled, false);
    assert.equal((await app.inject({method: 'POST', url: '/v1/account/wallet/challenge', payload: {}})).statusCode, 503);
  } finally { await app.close(); }
});

test('malformed, incomplete and ambiguous wallet opt-in fails without leaking configuration', () => {
  for (const field of Object.keys(env)) {
    if (['TRIMMY_WALLET_POSSESSION', 'TRIMMY_GUEST_SOURCE_MODE',
      'TRIMMY_GUEST_SOURCE_HMAC_KEY'].includes(field)) continue;
    assert.throws(() => readWalletPossessionRuntimeConfig({...env, [field]: ''}), invalidConfig);
  }
  for (const mode of ['true', 'privy', 'single_process ', 'SINGLE_PROCESS']) {
    assert.throws(() => readWalletPossessionRuntimeConfig({...env, TRIMMY_WALLET_POSSESSION: mode}), invalidConfig);
  }
  for (const network of ['devnet', 'localnet', 'mainnet', ' mainnet-beta']) {
    assert.throws(() => readWalletPossessionRuntimeConfig({...env, TRIMMY_WALLET_NETWORK: network}), invalidConfig);
  }
  assert.throws(() => readWalletPossessionRuntimeConfig({...env, PRIVY_APP_ID: 'wrong app'}), invalidConfig);
  assert.throws(() => readWalletPossessionRuntimeConfig({...env, TRIMMY_WALLET_POSSESSION: 'disabled'}), invalidConfig);
  assert.throws(() => readWalletPossessionRuntimeConfig({TRIMMY_WALLET_NETWORK: 'mainnet-beta'}), invalidConfig);
  try { readWalletPossessionRuntimeConfig({...env, TRIMMY_WALLET_NETWORK: env.PRIVY_APP_SECRET}); }
  catch (error) { assert.ok(error instanceof Error); assert.equal(error.message.includes(env.PRIVY_APP_SECRET), false); }
});

test('opt-in composes real verified-account and durable adapters without eagerly reaching providers', async () => {
  const practice = createPracticeRuntime(readPracticeRuntimeConfig(env));
  try {
    assert.equal(practice.appId, env.PRIVY_APP_ID);
    assert.ok(practice.walletBindings instanceof PostgresWalletBindingStore);
    const linked = readAccountContextResolver(env);
    assert.ok(linked);
    const configured = createWalletPossessionRuntime(readWalletPossessionRuntimeConfig(env), practice, linked);
    assert.ok(configured);
    assert.equal(configured.linkedIdentities, linked);
    const app = buildApp({logger: false, ...practice.options, walletPossession: configured});
    try {
      const config = (await app.inject('/v1/config')).json();
      assert.equal(config.walletPossessionEnabled, true);
      assert.equal(config.moneyMode, 'practice_only');
      for (const capability of ['financialOperationsEnabled', 'liveWalletsEnabled', 'fundedGiftsEnabled', 'swapsEnabled']) {
        assert.equal(config.capabilities[capability], false);
      }
      for (const url of ['/v1/account/wallet/challenge', '/v1/account/wallet/possession']) {
        const response = await app.inject({method: 'POST', url, payload: {}});
        assert.equal(response.statusCode, 401);
        assert.equal(response.json().error.code, 'ACCOUNT_WALLET_UNAUTHENTICATED');
      }
      assert.equal((await app.inject({method: 'POST', url: '/v1/orders', payload: {}})).statusCode, 503);
    } finally { await app.close(); }
  } finally { await practice.close(); }
});

test('composition refuses a missing verified runtime, durable store, resolver or different app', async () => {
  const practice = createPracticeRuntime(readPracticeRuntimeConfig(env));
  const config = readWalletPossessionRuntimeConfig(env);
  try {
    assert.throws(() => createWalletPossessionRuntime(config, {}, resolver), invalidConfig);
    assert.throws(() => createWalletPossessionRuntime(config, practice, undefined), invalidConfig);
    assert.throws(() => createWalletPossessionRuntime(config, practice,
      {resolve: resolver.resolve} as never), invalidConfig);
    assert.throws(() => createWalletPossessionRuntime(config, {...practice, appId: 'another_app'}, resolver), invalidConfig);
    const {walletBindings: _bindings, ...withoutBindings} = practice;
    const {authenticateContext: _authenticate, ...withoutAuthentication} = practice;
    assert.throws(() => createWalletPossessionRuntime(config, withoutBindings, resolver), invalidConfig);
    assert.throws(() => createWalletPossessionRuntime(config, withoutAuthentication, resolver), invalidConfig);
  } finally { await practice.close(); }
});

test('configured route scopes a challenge to the verified app, account and pinned network', async () => {
  let appId = env.PRIVY_APP_ID;
  let lookupCalls = 0;
  const practice: Pick<PracticeRuntime, 'appId' | 'authenticateContext' | 'walletBindings'> = {
    appId,
    authenticateContext: async () => ({userId: accountId, identity: {provider: 'privy', appId, subject}}),
    walletBindings: {record: async () => { throw new Error('Issuing a challenge must not record a binding.'); }},
  };
  const configured = createWalletPossessionRuntime(readWalletPossessionRuntimeConfig(env), practice,
    {resolveFresh: resolver.resolveFresh, resolve: async identity => { lookupCalls++; return resolver.resolve(identity); }});
  const app = buildApp({logger: false, walletPossession: configured!});
  try {
    const issued = await app.inject({method: 'POST', url: '/v1/account/wallet/challenge', payload: {}});
    assert.equal(issued.statusCode, 201, issued.body);
    const challenge = issued.json().challenge;
    assert.equal(challenge.network, 'mainnet-beta');
    assert.equal(challenge.walletAddress, wallet);
    assert.ok(challenge.message.includes(`account: ${accountId}\n`));
    assert.ok(challenge.message.includes('It authorizes no transfer, swap or payment.'));
    assert.equal(lookupCalls, 1);
    appId = 'a_different_app';
    const crossed = await app.inject({method: 'POST', url: '/v1/account/wallet/challenge', payload: {}});
    assert.equal(crossed.statusCode, 401);
    assert.equal(lookupCalls, 1);
  } finally { await app.close(); }
});

test('shared storage is accepted, and only when a durable challenge store exists', async () => {
  const shared = {...env, TRIMMY_WALLET_POSSESSION: 'shared_storage'};
  assert.equal(readWalletPossessionRuntimeConfig(shared)?.mode, 'shared_storage');
  const practice = createPracticeRuntime(readPracticeRuntimeConfig(shared));
  try {
    assert.ok(practice.walletChallenges, 'a configured runtime must expose the durable store');
    assert.ok(createWalletPossessionRuntime(readWalletPossessionRuntimeConfig(shared), practice, resolver));
    // Promising shared storage and quietly using process memory would restore
    // the single-instance limitation under a configuration that denies it.
    const {walletChallenges, ...withoutStore} = practice;
    assert.ok(walletChallenges);
    assert.throws(() => createWalletPossessionRuntime(
      readWalletPossessionRuntimeConfig(shared), withoutStore, resolver), invalidConfig);
  } finally { await practice.close(); }
});

test('single process still works, and its challenges stay out of the database', async () => {
  const practice = createPracticeRuntime(readPracticeRuntimeConfig(env));
  try {
    // The durable store is available but deliberately unused in this mode, so an
    // existing single-instance deployment keeps its exact behaviour.
    const runtime = createWalletPossessionRuntime(readWalletPossessionRuntimeConfig(env), practice, resolver);
    assert.ok(runtime);
    const challenge = await runtime.service.issue({
      userId: accountId, walletAddress: wallet, network: 'mainnet-beta', providerWalletId: null,
    });
    // No database is reachable in this test, so issuing at all proves memory was used.
    assert.equal(challenge.userId, accountId);
    assert.equal(challenge.network, 'mainnet-beta');
  } finally { await practice.close(); }
});
