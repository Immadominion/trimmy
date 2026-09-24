import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildApp } from '../src/app.js';
import { ACCOUNT_CLOSURE_CONFIRMATION, ACCOUNT_CLOSURE_ROUTE } from '../src/account-closure-route.js';
import { AccountClosureError } from '../src/account-closure.js';
import type { AccountClosureRepository, AccountClosureResult } from '../src/account-closure.js';
import type {PracticeIdentity} from '../src/practice-identity.js';
import type {PrivyLinkedIdentityResolution} from '../src/privy-linked-identities.js';

const USER = '7c000000-0000-4000-8000-000000000001';
const body = {schemaVersion: 1, confirm: ACCOUNT_CLOSURE_CONFIRMATION};

function repository(result: AccountClosureResult | Error = {closed: true, canceledInvitations: 2}) {
  const calls: string[] = [];
  const repo: AccountClosureRepository = {
    close: async userId => {
      calls.push(userId);
      if (result instanceof Error) throw result;
      return result;
    },
  };
  return {repo, calls};
}

function app(repo?: AccountClosureRepository, userId: string | null = USER) {
  return buildApp({
    logger: false,
    ...(repo ? {accountClosure: {repository: repo, authenticate: async () => (userId ? {userId} : null)}} : {}),
  });
}

const post = (instance: ReturnType<typeof buildApp>, payload: unknown) =>
  instance.inject({method: 'POST', url: ACCOUNT_CLOSURE_ROUTE, payload: payload as never});

test('closure is unavailable until configured, and no other verb is allowed', async () => {
  const instance = app();
  try {
    const response = await post(instance, body);
    assert.equal(response.statusCode, 503);
    assert.equal(response.json().error.code, 'ACCOUNT_CLOSURE_UNAVAILABLE');
    assert.equal((await instance.inject('/v1/config')).json().accountClosureEnabled, false);
    // Only POST is allowlisted; the money gate refuses the rest.
    for (const method of ['PUT', 'PATCH', 'DELETE'] as const) {
      const other = await instance.inject({method, url: ACCOUNT_CLOSURE_ROUTE, payload: body});
      assert.equal(other.statusCode, 503, method);
      assert.equal(other.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED', method);
    }
  } finally { await instance.close(); }
});

test('an unverified caller is refused before the body is acted on', async () => {
  const {repo, calls} = repository();
  const instance = app(repo, null);
  try {
    for (const payload of [body, {schemaVersion: 1, confirm: 'wrong'}]) {
      const response = await post(instance, payload);
      assert.equal(response.statusCode, 401);
      assert.equal(response.json().error.code, 'ACCOUNT_CLOSURE_UNAUTHENTICATED');
    }
    // The framework validates the schema before the handler, so a malformed
    // body is refused with 400 even without a verified account. That discloses
    // only the route's published shape, and storage is still never touched.
    for (const payload of [{}, {schemaVersion: 2, confirm: 'close my account'}, {confirm: 1}]) {
      const response = await post(instance, payload);
      assert.equal(response.statusCode, 400, JSON.stringify(payload));
    }
    assert.deepEqual(calls, [], 'no unverified request reaches storage, however it is shaped');
  } finally { await instance.close(); }
});

test('closing requires the exact written confirmation', async () => {
  const {repo, calls} = repository();
  const instance = app(repo);
  try {
    for (const confirm of ['', 'yes', 'Close My Account', 'close my account ', ACCOUNT_CLOSURE_CONFIRMATION.toUpperCase()]) {
      const response = await post(instance, {schemaVersion: 1, confirm});
      assert.equal(response.statusCode, 400, confirm);
      assert.equal(response.json().error.code, 'ACCOUNT_CLOSURE_INVALID_INPUT');
    }
    // The request schema itself rejects a missing or unexpected field.
    for (const payload of [{schemaVersion: 1}, {confirm: ACCOUNT_CLOSURE_CONFIRMATION},
      {schemaVersion: 2, confirm: ACCOUNT_CLOSURE_CONFIRMATION},
      {...body, extra: true}]) {
      const response = await post(instance, payload);
      assert.equal(response.statusCode, 400, JSON.stringify(payload));
    }
    assert.deepEqual(calls, [], 'nothing reaches storage without a valid confirmation');
  } finally { await instance.close(); }
});

test('a confirmed closure reports what happened in plain terms', async () => {
  const {repo, calls} = repository({closed: true, canceledInvitations: 2});
  const instance = app(repo);
  try {
    assert.equal((await instance.inject('/v1/config')).json().accountClosureEnabled, true);
    const response = await post(instance, body);
    assert.equal(response.statusCode, 200, response.body);
    const json = response.json();
    assert.equal(json.schemaVersion, 1);
    assert.equal(json.closed, true);
    assert.equal(json.canceledInvitations, 2);
    assert.match(json.note, /can no longer sign in/);
    // The account identifier is never echoed back.
    assert.equal(response.body.includes(USER), false);
    assert.deepEqual(calls, [USER]);
  } finally { await instance.close(); }
});

test('closing an already closed account is reported without an error', async () => {
  const {repo} = repository({closed: false, canceledInvitations: 0});
  const instance = app(repo);
  try {
    const response = await post(instance, body);
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(response.json().closed, false);
    assert.equal(response.json().canceledInvitations, 0);
  } finally { await instance.close(); }
});

test('storage failures stay opaque', async () => {
  for (const [error, status, code] of [
    [new AccountClosureError('ACCOUNT_CLOSURE_INVALID_INPUT', 'detail'), 400, 'ACCOUNT_CLOSURE_INVALID_INPUT'],
    [new AccountClosureError('ACCOUNT_CLOSURE_NOT_FOUND', 'detail'), 404, 'ACCOUNT_CLOSURE_NOT_FOUND'],
    [new AccountClosureError('ACCOUNT_CLOSURE_RUNTIME_ROLE_INVALID', 'detail'), 503, 'ACCOUNT_CLOSURE_UNAVAILABLE'],
    [new Error('connection string leaked'), 503, 'ACCOUNT_CLOSURE_UNAVAILABLE'],
  ] as const) {
    const {repo} = repository(error as Error);
    const instance = app(repo);
    try {
      const response = await post(instance, body);
      assert.equal(response.statusCode, status, code);
      assert.equal(response.json().error.code, code);
      assert.equal(response.body.includes('connection string leaked'), false);
      assert.equal(response.body.includes('detail'), false);
    } finally { await instance.close(); }
  }
});

test('there is no route that reopens a closed account', async () => {
  const {repo} = repository();
  const instance = app(repo);
  try {
    for (const url of ['/v1/account/reopen', '/v1/account/closure/undo', '/v1/account/status']) {
      const response = await instance.inject({method: 'POST', url, payload: body});
      // Either the money gate or a missing route; never a successful reopen.
      assert.ok([404, 503].includes(response.statusCode), `${url} ${response.statusCode}`);
    }
  } finally { await instance.close(); }
});

test('closure uses fresh X proof when available and provider failure never blocks closing', async () => {
  const identity: PracticeIdentity = {
    provider: 'privy', appId: 'trimmy_test', subject: 'did:privy:closuretest',
  };
  const verified: PrivyLinkedIdentityResolution = {
    provider: 'privy',
    subject: identity.subject,
    twitter: {status: 'verified', subject: '18446744073709551615',
      usernameSnapshot: 'ada_builds', verifiedAtUnixSeconds: 1_758_369_600},
    embeddedSolanaWallet: {status: 'missing'},
  };
  for (const [resolver, expectedSubject] of [
    [async () => verified, '18446744073709551615'],
    [async () => { throw new Error('provider detail'); }, null],
  ] as const) {
    const calls: Array<string | null | undefined> = [];
    const repo: AccountClosureRepository = {
      close: async (_userId, freshXSubject) => {
        calls.push(freshXSubject);
        return {closed: true, canceledInvitations: 1};
      },
    };
    const instance = buildApp({logger: false, accountClosure: {
      repository: repo,
      authenticate: async () => { throw new Error('legacy authentication must not run'); },
      authenticateContext: async () => ({userId: USER, identity}),
      linkedIdentities: {resolveFresh: resolver},
    }});
    try {
      const response = await post(instance, body);
      assert.equal(response.statusCode, 200, response.body);
      assert.deepEqual(calls, [expectedSubject]);
      assert.equal(response.body.includes(identity.subject), false);
      assert.equal(response.body.includes('provider detail'), false);
    } finally { await instance.close(); }
  }
});
