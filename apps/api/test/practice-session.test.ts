import assert from 'node:assert/strict';
import { test } from 'node:test';
import { request as httpRequest } from 'node:http';
import { buildApp } from '../src/app.js';
import { PracticeIdentityError } from '../src/practice-identity.js';
import type { PracticeAccountRepository, PracticeIdentityVerifier } from '../src/practice-identity.js';
import { createPracticeAuthenticator } from '../src/practice-session-routes.js';

const userId = 'b9000000-0000-4000-8000-000000000001';
const token = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJkaWQ6cHJpdnk6dGVzdCJ9.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const headers = {authorization: `Bearer ${token}`};
const verifier: PracticeIdentityVerifier = {verify: async value => value === token ? {provider: 'privy', appId: 'test-app', subject: 'did:privy:testsubject'} : null};
const path = '/v1/practice/session';

test('duplicate physical Authorization headers are rejected before Node can normalize their identity', async () => {
  let provisions = 0;
  const app = buildApp({logger: false, practiceSessions: {verifier, accounts: {
    find: async () => null,
    provision: async () => {provisions++; return {userId};},
  }}});
  try {
    const address = await app.listen({host: '127.0.0.1', port: 0});
    const status = await new Promise<number | undefined>((resolve, reject) => {
      const request = httpRequest(`${address}${path}`, {method: 'POST', headers: [
        'Host', new URL(address).host,
        'Authorization', `Bearer ${token}`, 'authorization', `Bearer ${token}`,
        'Content-Type', 'application/json', 'Content-Length', '2',
      ]}, response => {response.resume(); response.on('end', () => resolve(response.statusCode));});
      request.on('error', reject);
      request.end('{}');
    });
    assert.equal(status, 401);
    assert.equal(provisions, 0);
  } finally {await app.close();}
});

test('practice session defaults unavailable and cannot be enabled by caller identity hints', async () => {
  const app = buildApp({logger: false});
  try {
    const result = await app.inject({method: 'POST', url: path, headers, payload: {userId}});
    assert.equal(result.statusCode, 503);
    assert.equal(result.json().error.code, 'PRACTICE_SYNC_UNAVAILABLE');
    assert.equal((await app.inject({method: 'GET', url: '/v1/config'})).json().practiceAccountsEnabled, false);
  } finally { await app.close(); }
});

test('session verifies before parsing and provisions only the verified identity after strict validation', async () => {
  const calls: unknown[] = [];
  const accounts: PracticeAccountRepository = {find: async () => null, provision: async identity => {calls.push(identity); return {userId};}};
  const app = buildApp({logger: false, practiceSessions: {verifier, accounts}});
  try {
    const unauthenticated = await app.inject({method: 'POST', url: path, headers: {'content-type': 'application/json'}, payload: '{invalid'});
    assert.equal(unauthenticated.statusCode, 401);
    for (const payload of [{userId}, {subject: 'did:privy:someoneelse'}, []]) {
      assert.equal((await app.inject({method: 'POST', url: path, headers, payload})).statusCode, 400);
    }
    assert.equal((await app.inject({method: 'POST', url: `${path}?userId=${userId}`, headers, payload: {}})).statusCode, 400);
    assert.equal(calls.length, 0);
    const created = await app.inject({method: 'POST', url: path, headers: {...headers, 'x-user-id': 'untrusted'}, payload: {}});
    assert.equal(created.statusCode, 200, created.body);
    assert.deepEqual(created.json(), {schemaVersion: 1, userId});
    assert.deepEqual(calls, [{provider: 'privy', appId: 'test-app', subject: 'did:privy:testsubject'}]);
  } finally { await app.close(); }
});

test('session failures stay opaque and closed accounts are not recreated', async () => {
  for (const [error, status] of [[new PracticeIdentityError('PRACTICE_ACCOUNT_UNAVAILABLE', 'secret-session-detail'), 403], [new Error('secret-db-password'), 503]] as const) {
    const app = buildApp({logger: false, practiceSessions: {verifier, accounts: {find: async () => null, provision: async () => {throw error;}}}});
    try {
      const response = await app.inject({method: 'POST', url: path, headers, payload: {}});
      assert.equal(response.statusCode, status);
      assert.equal(response.body.includes('secret'), false);
    } finally { await app.close(); }
  }
});

test('progress authentication only finds accounts and distinguishes unavailable storage from expired login', async () => {
  let provisions = 0;
  let storageFailed = false;
  const accounts: PracticeAccountRepository = {
    find: async () => {if (storageFailed) throw new Error('private-database-detail'); return {userId};},
    provision: async () => {provisions++; return {userId};},
  };
  const seen: string[] = [];
  const app = buildApp({logger: false, practice: {
    authenticate: createPracticeAuthenticator({verifier, accounts}),
    repository: {get: async id => {seen.push(id); return {revision: 0, progress: null, updatedAt: null};}, put: async () => {throw new Error();}},
  }});
  try {
    assert.equal((await app.inject({method: 'GET', url: '/v1/practice/progress', headers})).statusCode, 200);
    assert.deepEqual(seen, [userId]);
    assert.equal(provisions, 0);
    storageFailed = true;
    const failed = await app.inject({method: 'GET', url: '/v1/practice/progress', headers});
    assert.equal(failed.statusCode, 503);
    assert.equal(failed.body.includes('private'), false);
    assert.equal((await app.inject({method: 'GET', url: '/v1/practice/progress'})).statusCode, 401);
  } finally { await app.close(); }
});

test('session route exceptions do not open other mutations or aliases', async () => {
  const app = buildApp({logger: false, practiceSessions: {verifier, accounts: {find: async () => null, provision: async () => ({userId})}}});
  try {
    for (const url of ['/v1/practice/session/extra', '/v1/practice/session/', '/v1/wallets', '/v1/gifts']) {
      const response = await app.inject({method: 'POST', url, headers, payload: {}});
      assert.equal(response.statusCode, 503);
      assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
    }
  } finally { await app.close(); }
});
