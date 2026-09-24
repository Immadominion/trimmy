import assert from 'node:assert/strict';
import {test} from 'node:test';
import Fastify from 'fastify';
import {buildApp} from '../src/app.js';
import {createPracticeAuthenticator, PracticeAuthenticationUnavailable} from '../src/practice-session-routes.js';
import {registerBrowserOrigins} from '../src/browser-origins.js';
import {XProfileLookupError, readXProfileLookup} from '../src/x-profile-lookup.js';
import {registerSocialXRoutes, X_PROFILE_ROUTE, XProfileRequestBudget, socialXEnabled} from '../src/x-profile-routes.js';
import type {SocialXAdapters} from '../src/x-profile-routes.js';

const user = '10000000-0000-4000-a000-000000000001';
const secondUser = '10000000-0000-4000-a000-000000000002';
const profile = {provider: 'x', id: '1234567890123456789', username: 'trimmyhq', name: 'Trimmy',
  lookedUpAt: '2026-09-14T18:00:00.000Z', ownershipVerified: false} as const;
const url = X_PROFILE_ROUTE + '?username=trimmyhq';
function adapters(lookup: SocialXAdapters['lookup'] = {lookup: async () => profile}): SocialXAdapters {
  return {lookup, authenticate: async () => ({userId: user})};
}
function app(options?: SocialXAdapters, budget = new XProfileRequestBudget(), origins: readonly string[] = []) {
  const instance = Fastify({logger: false, ajv: {customOptions: {removeAdditional: false, coerceTypes: false, useDefaults: false}}});
  instance.setErrorHandler((_error, request, reply) => reply.code(400).send({error: {code: 'INVALID_REQUEST', requestId: request.id}}));
  registerBrowserOrigins(instance, origins);
  registerSocialXRoutes(instance, options, budget);
  return instance;
}

test('explicit server environment enables only a valid X bearer token', () => {
  assert.equal(readXProfileLookup({}), undefined);
  assert.equal(readXProfileLookup({X_BEARER_TOKEN: '', TWITTER_BEARER_TOKEN: 'unused'}), undefined);
  assert.ok(readXProfileLookup({X_BEARER_TOKEN: 'test-only-token'}));
  assert.throws(() => readXProfileLookup({X_BEARER_TOKEN: 'unsafe\n'}), {code: 'X_LOOKUP_NOT_CONFIGURED'});
  assert.equal(socialXEnabled(undefined), false);
});
test('disabled and unauthenticated requests never spend provider calls', async () => {
  const disabled = app();
  try { assert.equal((await disabled.inject(url)).statusCode, 503); } finally { await disabled.close(); }
  let calls = 0;
  for (const authenticate of [async () => null, async () => ({userId: 'unverified'}),
    async () => { throw new Error('private auth diagnostic'); }]) {
    const instance = app({lookup: {lookup: async () => { calls++; return profile; }}, authenticate});
    try {
      const response = await instance.inject({url, headers: {'x-user-id': user, authorization: 'Bearer arbitrary'}});
      assert.equal(response.statusCode, 401); assert.ok(!response.body.includes('private auth diagnostic'));
    } finally { await instance.close(); }
  }
  assert.equal(calls, 0);
});
test('real existing-account authenticator never provisions and ignores caller-selected IDs', async () => {
  let lookups = 0, finds = 0, provisions = 0;
  const authenticate = createPracticeAuthenticator({
    verifier: {verify: async token => token === 'verified.test.jwt' ? {provider: 'privy', appId: 'testApp', subject: 'did:privy:test'} : null},
    accounts: {find: async () => { finds++; return null; }, provision: async () => { provisions++; return {userId: user}; }},
  });
  const instance = app({authenticate, lookup: {lookup: async () => { lookups++; return profile; }}});
  try {
    const response = await instance.inject({url, headers: {authorization: 'Bearer verified.test.jwt', 'x-user-id': user}});
    assert.equal(response.statusCode, 401); assert.equal(finds, 1);
    assert.equal(provisions, 0); assert.equal(lookups, 0);
  } finally { await instance.close(); }
});
test('authentication storage outages fail closed without X requests', async () => {
  let calls = 0;
  const instance = app({...adapters({lookup: async () => { calls++; return profile; }}),
    authenticate: async () => { throw new PracticeAuthenticationUnavailable(); }});
  try { assert.equal((await instance.inject(url)).statusCode, 503); assert.equal(calls, 0); }
  finally { await instance.close(); }
});
test('strict query/body checks run before lookup and no HEAD route exists', async () => {
  let calls = 0;
  const instance = app(adapters({lookup: async () => { calls++; return profile; }}));
  try {
    for (const requestUrl of [X_PROFILE_ROUTE, X_PROFILE_ROUTE + '?username=', X_PROFILE_ROUTE + '?username=%20trimmyhq',
      X_PROFILE_ROUTE + '?username=trimmyhq%0A', X_PROFILE_ROUTE + '?username=@trimmyhq',
      X_PROFILE_ROUTE + '?username=' + 'a'.repeat(16), X_PROFILE_ROUTE + '?username=trimmyhq&username=another',
      url + '&userId=' + user, url + '&token=private-token', X_PROFILE_ROUTE + '?username=../users']) {
      const response = await instance.inject(requestUrl);
      assert.equal(response.statusCode, 400, requestUrl); assert.ok(!response.body.includes('private-token'));
    }
    assert.equal((await instance.inject({url, method: 'GET', headers: {'content-type': 'application/json'}, payload: '{}'})).statusCode, 400);
    assert.equal((await instance.inject({url, method: 'HEAD'})).statusCode, 404);
    assert.equal((await instance.inject({url, method: 'POST'})).statusCode, 404);
    assert.equal(calls, 0);
  } finally { await instance.close(); }
});
test('public result is projected, never an invitation or proof of ownership', async () => {
  const instance = app(adapters({lookup: async () => ({...profile, apiToken: 'private-token'})}));
  try {
    const response = await instance.inject(url);
    assert.equal(response.statusCode, 200); assert.equal(response.headers['cache-control'], 'no-store');
    assert.deepEqual(response.json(), {schemaVersion: 1, profile, invitationCreated: false});
    assert.ok(!response.body.includes('private-token'));
  } finally { await instance.close(); }
  for (const bad of [{...profile, ownershipVerified: true}, {...profile, username: 'other'}, {...profile, id: 123},
    {...profile, lookedUpAt: 'not-a-date'}]) {
    const invalid = app(adapters({lookup: async () => bad as unknown as typeof profile}));
    try { assert.equal((await invalid.inject(url)).statusCode, 502); } finally { await invalid.close(); }
  }
});
test('mapped provider failures do not echo mutated error messages', async () => {
  for (const [code, status] of [['X_PROFILE_NOT_FOUND', 404], ['X_PROVIDER_AUTH_FAILED', 503],
    ['X_PROVIDER_ACCESS_DENIED', 503], ['X_PROVIDER_PAYMENT_REQUIRED', 503], ['X_PROVIDER_RATE_LIMITED', 429],
    ['X_LOOKUP_TIMEOUT', 504], ['X_RESPONSE_INVALID', 502], ['X_PROVIDER_UNAVAILABLE', 502]] as const) {
    const error = new XProfileLookupError(code); error.message = 'private provider diagnostic';
    const instance = app(adapters({lookup: async () => { throw error; }}));
    try {
      const response = await instance.inject(url);
      assert.equal(response.statusCode, status); assert.ok(!response.body.includes('private provider diagnostic'));
    } finally { await instance.close(); }
  }
  const error = new XProfileLookupError('X_PROVIDER_UNAVAILABLE');
  Object.defineProperty(error, 'code', {value: 'private-token'});
  const instance = app(adapters({lookup: async () => { throw error; }}));
  try {
    const response = await instance.inject(url);
    assert.equal(response.statusCode, 502); assert.ok(!response.body.includes('private-token'));
  } finally { await instance.close(); }
});
test('denied browser origins cannot spend X calls or authenticate', async () => {
  let calls = 0, auth = 0;
  const instance = app({...adapters({lookup: async () => { calls++; return profile; }}),
    authenticate: async () => { auth++; return {userId: user}; }}, undefined, ['https://trimmy.example']);
  try {
    assert.equal((await instance.inject({url, headers: {origin: 'https://unknown.example'}})).statusCode, 403);
    assert.equal(calls, 0); assert.equal(auth, 0);
  } finally { await instance.close(); }
});
test('concurrent and fast repeated requests reserve budget atomically across verified accounts', async () => {
  let now = 0, calls = 0, release: (() => void) | undefined;
  const budget = new XProfileRequestBudget({now: () => now});
  const first = budget.run(user, async () => { calls++; await new Promise<void>(resolve => { release = resolve; }); });
  now = 1000;
  await assert.rejects(budget.run(secondUser, async () => { calls++; }), {code: 'X_LOOKUP_RATE_LIMITED'});
  release?.(); await first;
  now = 500;
  await assert.rejects(budget.run(secondUser, async () => { calls++; }), {code: 'X_LOOKUP_BUDGET_UNAVAILABLE'});
  now = 1000; await budget.run(secondUser, async () => { calls++; });
  now = 2000;
  await assert.rejects(budget.run(user, async () => { calls++; }), {code: 'X_LOOKUP_RATE_LIMITED'});
  now = 15000; await budget.run(user, async () => { calls++; });
  assert.equal(calls, 3);
});
test('rolling per-account and shared hourly bounds survive account switching and charge failures', async () => {
  let now = 0, calls = 0;
  const budget = new XProfileRequestBudget({now: () => now});
  for (let index = 0; index < 5; index++) {
    now = index * 15000;
    await assert.rejects(budget.run(user, async () => { calls++; throw new XProfileLookupError('X_PROFILE_NOT_FOUND'); }));
  }
  now = 75000;
  await assert.rejects(budget.run(user, async () => { calls++; }), {code: 'X_LOOKUP_RATE_LIMITED'});
  for (let index = 0; index < 15; index++) {
    now += 1000;
    await budget.run(`20000000-0000-4000-a000-${String(index).padStart(12, '0')}`, async () => { calls++; });
  }
  now += 1000;
  await assert.rejects(budget.run(secondUser, async () => { calls++; }), {code: 'X_LOOKUP_RATE_LIMITED'});
  assert.equal(calls, 20);
  now = 3_600_000; await budget.run(user, async () => { calls++; }); assert.equal(calls, 21);
});
test('provider billing/auth failures latch the instance and throttling enforces a cooldown', async () => {
  for (const code of ['X_PROVIDER_AUTH_FAILED', 'X_PROVIDER_ACCESS_DENIED', 'X_PROVIDER_PAYMENT_REQUIRED'] as const) {
    let now = 0, calls = 0;
    const budget = new XProfileRequestBudget({now: () => now});
    await assert.rejects(budget.run(user, async () => { calls++; throw new XProfileLookupError(code); }));
    now = 10_000_000;
    await assert.rejects(budget.run(secondUser, async () => { calls++; }), {code: 'X_LOOKUP_BUDGET_UNAVAILABLE'});
    assert.equal(calls, 1);
  }
  let now = 0, calls = 0;
  const budget = new XProfileRequestBudget({now: () => now});
  await assert.rejects(budget.run(user, async () => { calls++; now = 100; throw new XProfileLookupError('X_PROVIDER_RATE_LIMITED'); }));
  now = 900099;
  await assert.rejects(budget.run(secondUser, async () => { calls++; }), {code: 'X_LOOKUP_RATE_LIMITED'});
  now = 900100; await budget.run(secondUser, async () => { calls++; }); assert.equal(calls, 2);
});
test('HTTP account identifiers cannot bypass a previously reserved provider budget', async () => {
  let calls = 0;
  const instance = app(adapters({lookup: async () => { calls++; return profile; }}), new XProfileRequestBudget({now: () => 0}));
  try {
    assert.equal((await instance.inject(url)).statusCode, 200);
    const response = await instance.inject({url, headers: {'x-user-id': secondUser}});
    assert.equal(response.statusCode, 429); assert.equal(calls, 1);
  } finally { await instance.close(); }
});
test('composed API permits exact authenticated browser GET while preflight and financial denial spend no quota', async () => {
  let calls = 0, auth = 0;
  const instance = buildApp({logger: false, browserOrigins: ['https://trimmy.example'], socialX: {
    authenticate: async () => { auth++; return {userId: user}; },
    lookup: {lookup: async () => { calls++; return profile; }},
  }});
  try {
    const preflight = {origin: 'https://trimmy.example', 'access-control-request-method': 'GET', 'access-control-request-headers': 'authorization'};
    assert.equal((await instance.inject({url, method: 'OPTIONS', headers: preflight})).statusCode, 204);
    assert.equal((await instance.inject({url, method: 'OPTIONS', headers: {...preflight, 'access-control-request-method': 'POST'}})).statusCode, 403);
    assert.equal((await instance.inject({url, method: 'HEAD'})).statusCode, 404);
    for (const path of [X_PROFILE_ROUTE, '/v1/gifts', '/v1/execute']) {
      assert.equal((await instance.inject({url: path, method: 'POST', payload: {username: 'trimmyhq'}})).statusCode, 503);
    }
    assert.equal(calls, 0); assert.equal(auth, 0);
    const response = await instance.inject({url, headers: {origin: 'https://trimmy.example'}});
    assert.equal(response.statusCode, 200); assert.equal(response.headers['access-control-allow-origin'], 'https://trimmy.example');
    assert.equal(calls, 1); assert.equal(auth, 1);
    assert.equal((await instance.inject('/v1/config')).json().socialXEnabled, true);
  } finally { await instance.close(); }
});
