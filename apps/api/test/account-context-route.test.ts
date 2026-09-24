import assert from 'node:assert/strict';
import {inspect} from 'node:util';
import {test} from 'node:test';
import {buildApp} from '../src/app.js';
import {
  ACCOUNT_CONTEXT_ROUTE,
  readAccountContextResolver,
} from '../src/account-context-route.js';
import type {
  AccountContextAdapters,
  AccountContextIdentityResolver,
} from '../src/account-context-route.js';
import type {PracticeIdentity} from '../src/practice-identity.js';
import {
  createPracticeAccountContextAuthenticator,
  PracticeAuthenticationUnavailable,
} from '../src/practice-session-routes.js';
import {PrivyLinkedIdentityError} from '../src/privy-linked-identities.js';
import type {
  PrivyLinkedIdentityErrorCode,
  PrivyLinkedIdentityResolution,
  PrivyUserReaderFactory,
} from '../src/privy-linked-identities.js';

const appId = 'trimmy_test_app';
const appSecret = 'server_test_secret_123';
const subject = 'did:privy:accountcontextsubject';
const xSubject = '18446744073709551615';
const userId = '10000000-0000-4000-a000-000000000001';
const token = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const identity: PracticeIdentity = {provider: 'privy', appId, subject};
const walletAddress = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
const resolution: PrivyLinkedIdentityResolution = {
  provider: 'privy',
  subject,
  twitter: {
    status: 'verified',
    subject: xSubject,
    usernameSnapshot: 'trimmyhq',
    verifiedAtUnixSeconds: 1_757_845_200,
  },
  embeddedSolanaWallet: {
    status: 'candidate',
    address: walletAddress,
    verifiedAtUnixSeconds: 1_757_845_201,
  },
};

function options(linkedIdentities: AccountContextIdentityResolver = {
  resolve: async () => resolution,
}, authenticate: AccountContextAdapters['authenticate'] = async () => ({userId, identity})):
AccountContextAdapters {
  return {authenticate, linkedIdentities};
}

test('disabled route and partial server credentials remain safely unavailable', async () => {
  const instance = buildApp({logger: false});
  try {
    const response = await instance.inject(ACCOUNT_CONTEXT_ROUTE);
    assert.equal(response.statusCode, 503);
    assert.equal(response.json().error.code, 'ACCOUNT_CONTEXT_UNAVAILABLE');
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.equal((await instance.inject('/v1/config')).json().accountContextEnabled, false);
  } finally { await instance.close(); }

  let factories = 0;
  const clientFactory: PrivyUserReaderFactory = () => {
    factories += 1;
    return {getById: async () => ({id: subject, linked_accounts: []})};
  };
  for (const env of [
    {},
    {PRIVY_APP_ID: appId},
    {PRIVY_APP_SECRET: appSecret},
    {PRIVY_APP_ID: appId, PRIVY_APP_SECRET: ''},
    {PRIVY_APP_ID: '', PRIVY_APP_SECRET: appSecret},
  ]) assert.equal(readAccountContextResolver(env, {clientFactory}), undefined);
  assert.equal(factories, 0);
  assert.ok(readAccountContextResolver(
    {PRIVY_APP_ID: appId, PRIVY_APP_SECRET: appSecret}, {clientFactory}));
  assert.equal(factories, 1);
  assert.throws(() => readAccountContextResolver(
    {PRIVY_APP_ID: 'bad app id', PRIVY_APP_SECRET: appSecret}, {clientFactory}), error => {
    assert.ok(error instanceof Error);
    assert.ok(!inspect(error).includes(appSecret));
    return true;
  });
});

test('returns one strict sanitized account context from the same verified Privy subject', async () => {
  let resolvedIdentity: PracticeIdentity | undefined;
  const privateValue = 'private-provider-value';
  const injected = {
    ...resolution,
    email: 'never-return@example.invalid',
    oauthToken: privateValue,
    twitter: {...resolution.twitter, displayName: privateValue},
    embeddedSolanaWallet: {...resolution.embeddedSolanaWallet, delegated: true, privateKey: privateValue},
  } as unknown as PrivyLinkedIdentityResolution;
  const instance = buildApp({logger: false, accountContext: options({
    resolve: async value => { resolvedIdentity = value; return injected; },
  })});
  try {
    const response = await instance.inject({
      url: ACCOUNT_CONTEXT_ROUTE,
      headers: {authorization: `Bearer ${token}`},
    });
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(resolvedIdentity, identity);
    assert.deepEqual(response.json(), {
      schemaVersion: 1,
      userId,
      xIdentity: resolution.twitter,
      embeddedSolanaWallet: resolution.embeddedSolanaWallet,
    });
    assert.equal(response.headers['cache-control'], 'no-store');
    for (const forbidden of [subject, privateValue, 'never-return@example.invalid',
      'oauthToken', 'privateKey', 'delegated']) assert.ok(!response.body.includes(forbidden));
    assert.equal((await instance.inject('/v1/config')).json().accountContextEnabled, true);
  } finally { await instance.close(); }
});

test('keeps missing and ambiguous identity states explicit', async () => {
  for (const value of [
    {provider: 'privy', subject, twitter: {status: 'missing'}, embeddedSolanaWallet: {status: 'ambiguous'}},
    {provider: 'privy', subject, twitter: {status: 'ambiguous'}, embeddedSolanaWallet: {status: 'missing'}},
  ] as const) {
    const instance = buildApp({logger: false, accountContext: options({resolve: async () => value})});
    try {
      const response = await instance.inject(ACCOUNT_CONTEXT_ROUTE);
      assert.equal(response.statusCode, 200);
      assert.deepEqual(response.json().xIdentity, value.twitter);
      assert.deepEqual(response.json().embeddedSolanaWallet, value.embeddedSolanaWallet);
    } finally { await instance.close(); }
  }
});

test('exact no-cache context read sees a newly linked wallet despite the warm provider cache', async () => {
  let linked = false;
  let reads = 0;
  const resolver = readAccountContextResolver({PRIVY_APP_ID: appId, PRIVY_APP_SECRET: appSecret}, {
    now: () => 10_000,
    clientFactory: () => ({getById: async requestedSubject => {
      assert.equal(requestedSubject, subject);
      reads++;
      return {id: subject, linked_accounts: linked ? [{type: 'wallet', chain_type: 'solana',
        connector_type: 'embedded', wallet_client: 'privy', wallet_client_type: 'privy',
        address: walletAddress, id: 'server-only-wallet-id', verified_at: 1_757_845_201,
        delegated: false, imported: false, wallet_index: 0}] : []};
    }}),
  });
  assert.ok(resolver);
  const instance = buildApp({logger: false, accountContext: options(resolver)});
  try {
    assert.equal((await instance.inject(ACCOUNT_CONTEXT_ROUTE)).json().embeddedSolanaWallet.status, 'missing');
    linked = true;
    for (const headers of [{}, {'cache-control': 'no-store'}, {'cache-control': 'max-age=0'}]) {
      const cached = await instance.inject({url: ACCOUNT_CONTEXT_ROUTE, headers});
      assert.equal(cached.statusCode, 200);
      assert.equal(cached.json().embeddedSolanaWallet.status, 'missing');
    }
    assert.equal(reads, 1);
    const fresh = await instance.inject({url: ACCOUNT_CONTEXT_ROUTE, headers: {'cache-control': 'no-cache'}});
    assert.equal(fresh.statusCode, 200, fresh.body);
    assert.deepEqual(fresh.json().embeddedSolanaWallet, resolution.embeddedSolanaWallet);
    assert.equal(fresh.headers['cache-control'], 'no-store');
    assert.equal(fresh.body.includes('server-only-wallet-id'), false);
    const subsequent = await instance.inject(ACCOUNT_CONTEXT_ROUTE);
    assert.deepEqual(subsequent.json().embeddedSolanaWallet, resolution.embeddedSolanaWallet,
      'the next ordinary context or holdings lookup must retain the newly created wallet');
    assert.equal(reads, 2);
  } finally { await instance.close(); }
});

test('fresh context failures are sanitized and never fall back to an existing cached result', async () => {
  let cachedReads = 0, freshReads = 0;
  const instance = buildApp({logger: false, accountContext: options({
    resolve: async () => { cachedReads++; return resolution; },
    resolveFresh: async observed => {
      assert.deepEqual(observed, identity);
      freshReads++;
      throw new Error(`${appSecret} private fresh provider error`);
    },
  })});
  try {
    assert.equal((await instance.inject(ACCOUNT_CONTEXT_ROUTE)).statusCode, 200);
    const failed = await instance.inject({url: ACCOUNT_CONTEXT_ROUTE, headers: {'cache-control': 'no-cache'}});
    assert.equal(failed.statusCode, 502);
    assert.equal(failed.json().error.code, 'PRIVY_USER_UNAVAILABLE');
    assert.equal(failed.headers['cache-control'], 'no-store');
    assert.equal(failed.body.includes(appSecret), false);
    assert.equal(failed.body.includes('private fresh provider error'), false);
    assert.equal(cachedReads, 1);
    assert.equal(freshReads, 1);
  } finally { await instance.close(); }
});

test('fresh context requests require both an authenticated account and a fresh-capable resolver', async () => {
  let reads = 0;
  const resolver = {resolve: async () => { reads++; return resolution; }};
  for (const [authenticate, status, code] of [
    [async () => ({userId, identity}), 503, 'ACCOUNT_CONTEXT_UNAVAILABLE'],
    [async () => null, 401, 'ACCOUNT_CONTEXT_UNAUTHENTICATED'],
  ] as const) {
    const instance = buildApp({logger: false, accountContext: options(resolver, authenticate)});
    try {
      const response = await instance.inject({url: ACCOUNT_CONTEXT_ROUTE, headers: {'cache-control': 'no-cache'}});
      assert.equal(response.statusCode, status);
      assert.equal(response.json().error.code, code);
      assert.equal(reads, 0);
    } finally { await instance.close(); }
  }
});

test('existing-account authentication never provisions and unknown accounts cannot reach Privy', async () => {
  let verifies = 0, finds = 0, provisions = 0, providerCalls = 0;
  const authenticate = createPracticeAccountContextAuthenticator({
    verifier: {verify: async input => { verifies += 1; return input === token ? identity : null; }},
    accounts: {
      find: async value => { finds += 1; assert.deepEqual(value, identity); return null; },
      provision: async () => { provisions += 1; return {userId}; },
    },
  });
  const instance = buildApp({logger: false, accountContext: options({
    resolve: async () => { providerCalls += 1; return resolution; },
  }, authenticate)});
  try {
    assert.equal((await instance.inject(ACCOUNT_CONTEXT_ROUTE)).statusCode, 401);
    const response = await instance.inject({
      url: ACCOUNT_CONTEXT_ROUTE,
      headers: {authorization: `Bearer ${token}`},
    });
    assert.equal(response.statusCode, 401);
    assert.equal(response.json().error.code, 'ACCOUNT_CONTEXT_UNAUTHENTICATED');
    assert.equal(verifies, 1);
    assert.equal(finds, 1);
    assert.equal(provisions, 0);
    assert.equal(providerCalls, 0);
  } finally { await instance.close(); }
});

test('known account mapping carries its exact verified subject into the one provider read', async () => {
  let provisions = 0, providerCalls = 0;
  const authenticate = createPracticeAccountContextAuthenticator({
    verifier: {verify: async input => input === token ? identity : null},
    accounts: {
      find: async value => { assert.deepEqual(value, identity); return {userId}; },
      provision: async () => { provisions += 1; return {userId}; },
    },
  });
  const instance = buildApp({logger: false, accountContext: options({
    resolve: async value => {
      providerCalls += 1;
      assert.deepEqual(value, identity);
      return resolution;
    },
  }, authenticate)});
  try {
    const response = await instance.inject({
      url: ACCOUNT_CONTEXT_ROUTE,
      headers: {authorization: `Bearer ${token}`},
    });
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(response.json().userId, userId);
    assert.equal(providerCalls, 1);
    assert.equal(provisions, 0);
  } finally { await instance.close(); }
});

test('authentication outages and malformed adapter identities fail before provider access', async () => {
  let providerCalls = 0;
  const linkedIdentities = {resolve: async () => { providerCalls += 1; return resolution; }};
  for (const [authenticate, status] of [
    [async () => { throw new PracticeAuthenticationUnavailable(); }, 503],
    [async () => ({userId: 'caller-selected', identity}), 401],
    [async () => ({userId, identity: {...identity, subject: `${subject}\n`}}), 401],
    [async () => null, 401],
  ] as const) {
    const instance = buildApp({logger: false, accountContext: options(
      linkedIdentities, authenticate as AccountContextAdapters['authenticate'])});
    try { assert.equal((await instance.inject(ACCOUNT_CONTEXT_ROUTE)).statusCode, status); }
    finally { await instance.close(); }
  }
  assert.equal(providerCalls, 0);
});

test('mismatched or malformed provider projections fail closed without leaking fields', async () => {
  const privateValue = 'private-provider-diagnostic';
  for (const value of [
    {...resolution, subject: 'did:privy:anotheruser', oauthToken: privateValue},
    {...resolution, twitter: {...resolution.twitter, usernameSnapshot: 'TrimmyHQ'}},
    {...resolution, embeddedSolanaWallet: {...resolution.embeddedSolanaWallet, address: 'not-an-address'}},
    {...resolution, embeddedSolanaWallet: {...resolution.embeddedSolanaWallet,
      address: '11111111111111111111111111111111'}},
    {...resolution, twitter: {status: 'verified', subject: '0', usernameSnapshot: 'trimmyhq', verifiedAtUnixSeconds: 1}},
    null,
  ]) {
    const instance = buildApp({logger: false, accountContext: options({
      resolve: async () => value as PrivyLinkedIdentityResolution,
    })});
    try {
      const response = await instance.inject(ACCOUNT_CONTEXT_ROUTE);
      assert.equal(response.statusCode, 502);
      assert.equal(response.json().error.code, 'PRIVY_USER_RESPONSE_INVALID');
      assert.ok(!response.body.includes(privateValue));
    } finally { await instance.close(); }
  }
});

test('provider failures use reconstructed status and messages only', async () => {
  for (const [code, status] of [
    ['PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED', 503],
    ['PRIVY_VERIFIED_IDENTITY_INVALID', 503],
    ['PRIVY_USER_RESPONSE_INVALID', 502],
    ['PRIVY_USER_UNAVAILABLE', 502],
    ['PRIVY_USER_TIMEOUT', 504],
    ['PRIVY_USER_RATE_LIMITED', 429],
  ] as const satisfies readonly (readonly [PrivyLinkedIdentityErrorCode, number])[]) {
    const error = new PrivyLinkedIdentityError(code);
    error.message = `${appSecret} private provider diagnostic`;
    const instance = buildApp({logger: false, accountContext: options({
      resolve: async () => { throw error; },
    })});
    try {
      const response = await instance.inject(ACCOUNT_CONTEXT_ROUTE);
      assert.equal(response.statusCode, status);
      assert.equal(response.json().error.code, code);
      assert.ok(!response.body.includes(appSecret));
      assert.ok(!response.body.includes('private provider diagnostic'));
    } finally { await instance.close(); }
  }
  const unexpected = new Error(`${appSecret} unexpected provider error`);
  const instance = buildApp({logger: false, accountContext: options({
    resolve: async () => { throw unexpected; },
  })});
  try {
    const response = await instance.inject(ACCOUNT_CONTEXT_ROUTE);
    assert.equal(response.statusCode, 502);
    assert.equal(response.json().error.code, 'PRIVY_USER_UNAVAILABLE');
    assert.ok(!inspect(response.json()).includes(appSecret));
  } finally { await instance.close(); }
});

test('query, body, HEAD, and mutation attempts cannot authenticate or call the provider', async () => {
  let authCalls = 0, providerCalls = 0;
  const instance = buildApp({logger: false, accountContext: options({
    resolve: async () => { providerCalls += 1; return resolution; },
  }, async () => { authCalls += 1; return {userId, identity}; })});
  try {
    for (const url of [
      `${ACCOUNT_CONTEXT_ROUTE}?userId=${userId}`,
      `${ACCOUNT_CONTEXT_ROUTE}?token=private-token`,
      `${ACCOUNT_CONTEXT_ROUTE}?x=1&x=2`,
    ]) {
      const response = await instance.inject(url);
      assert.equal(response.statusCode, 400);
      assert.ok(!response.body.includes('private-token'));
    }
    assert.equal((await instance.inject({
      method: 'GET', url: ACCOUNT_CONTEXT_ROUTE,
      headers: {'content-type': 'application/json'}, payload: '{}',
    })).statusCode, 400);
    assert.equal((await instance.inject({method: 'HEAD', url: ACCOUNT_CONTEXT_ROUTE})).statusCode, 404);
    assert.equal((await instance.inject({method: 'POST', url: ACCOUNT_CONTEXT_ROUTE, payload: {}})).statusCode, 503);
    assert.equal(authCalls, 0);
    assert.equal(providerCalls, 0);
  } finally { await instance.close(); }
});

test('CORS permits only the exact read-only account-context preflight', async () => {
  let authCalls = 0, providerCalls = 0;
  const origin = 'https://app.trimmy.example';
  const instance = buildApp({logger: false, browserOrigins: [origin], accountContext: options({
    resolve: async () => { providerCalls += 1; return resolution; },
  }, async () => { authCalls += 1; return {userId, identity}; })});
  const headers = {
    origin,
    'access-control-request-method': 'GET',
    'access-control-request-headers': 'authorization',
  };
  try {
    const preflight = await instance.inject({method: 'OPTIONS', url: ACCOUNT_CONTEXT_ROUTE, headers});
    assert.equal(preflight.statusCode, 204);
    assert.equal(preflight.headers['access-control-allow-methods'], 'GET');
    assert.equal((await instance.inject({
      method: 'OPTIONS', url: `${ACCOUNT_CONTEXT_ROUTE}?x=1`, headers,
    })).statusCode, 403);
    assert.equal((await instance.inject({
      method: 'OPTIONS', url: ACCOUNT_CONTEXT_ROUTE,
      headers: {...headers, 'access-control-request-method': 'POST'},
    })).statusCode, 403);
    assert.equal(authCalls, 0);
    assert.equal(providerCalls, 0);
    const response = await instance.inject({url: ACCOUNT_CONTEXT_ROUTE, headers: {origin}});
    assert.equal(response.statusCode, 200);
    assert.equal(response.headers['access-control-allow-origin'], origin);
    assert.equal(authCalls, 1);
    assert.equal(providerCalls, 1);
  } finally { await instance.close(); }
});
