import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { Pool } from 'pg';
import { PostgresPracticeAccounts } from '../../src/postgres-practice-accounts.js';
import { PostgresPracticeRepository } from '../../src/postgres-practice-repository.js';
import { buildApp } from '../../src/app.js';
import { createPracticeAuthenticator } from '../../src/practice-session-routes.js';
import type { PracticeIdentity } from '../../src/practice-identity.js';

const host = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.practice-runtime/socket'));
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const pool = new Pool({host, port: 65438, database: 'postgres', user: 'trimmy_practice_test_app', max: 5, connectionTimeoutMillis: 3000});
const owner = new Pool({host, port: 65438, database: 'postgres', user: 'trimmy_test_owner', max: 1, connectionTimeoutMillis: 3000});
const accounts = new PostgresPracticeAccounts(pool);
const identity: PracticeIdentity = {provider: 'privy', appId: 'practice-accounts-test', subject: 'did:privy:concurrentaccount'};
after(async () => {await pool.end(); await owner.end();});

test('finding an unknown identity creates no users or mappings', async () => {
  const before = (await owner.query('SELECT count(*)::int AS count FROM trimmy.users')).rows[0].count;
  assert.equal(await accounts.find(identity), null);
  assert.equal((await owner.query('SELECT count(*)::int AS count FROM trimmy.users')).rows[0].count, before);
});

test('simultaneous verified sign-ins converge on one account with no orphan users', async () => {
  const before = (await owner.query('SELECT count(*)::int AS count FROM trimmy.users')).rows[0].count;
  const created = await Promise.all(Array.from({length: 12}, () => accounts.provision(identity)));
  assert.equal(new Set(created.map(account => account.userId)).size, 1);
  assert.deepEqual(await accounts.find(identity), created[0]);
  assert.equal((await owner.query('SELECT count(*)::int AS count FROM trimmy.users')).rows[0].count, before + 1);
});

test('both verified app and subject bind the practice account', async () => {
  const original = await accounts.provision(identity);
  const otherApp = await accounts.provision({...identity, appId: 'practice-other-app'});
  const otherSubject = await accounts.provision({...identity, subject: 'did:privy:differentaccount'});
  assert.equal(new Set([original.userId, otherApp.userId, otherSubject.userId]).size, 3);
});

test('closed identity cannot receive a new UUID; restricted account keeps learning access', async () => {
  const restricted = {...identity, subject: 'did:privy:restrictedaccount'};
  const closed = {...identity, subject: 'did:privy:closedaccount'};
  const restrictedAccount = await accounts.provision(restricted);
  const closedAccount = await accounts.provision(closed);
  await owner.query("UPDATE trimmy.users SET status = 'restricted' WHERE id = $1", [restrictedAccount.userId]);
  await owner.query("UPDATE trimmy.users SET status = 'closed' WHERE id = $1", [closedAccount.userId]);
  assert.deepEqual(await accounts.provision(restricted), restrictedAccount);
  assert.equal(await accounts.find(closed), null);
  await assert.rejects(accounts.provision(closed), {code: 'PRACTICE_ACCOUNT_UNAVAILABLE'});
  assert.equal((await owner.query('SELECT user_id FROM trimmy.practice_auth_identities WHERE app_id=$1 AND subject=$2', [closed.appId, closed.subject])).rows[0].user_id, closedAccount.userId);
});

test('runtime has function-only mapping access and cannot modify or enumerate financial identities', async () => {
  for (const table of ['practice_auth_identities', 'provider_identities', 'users']) {
    await assert.rejects(pool.query(`SELECT * FROM trimmy.${table}`), {code: '42501'});
  }
  assert.equal((await owner.query("SELECT has_function_privilege('public', 'trimmy.practice_find_account(text,text)', 'EXECUTE') AS allowed")).rows[0].allowed, false);
  assert.equal((await owner.query("SELECT has_function_privilege('public', 'trimmy.practice_provision_account(text,text)', 'EXECUTE') AS allowed")).rows[0].allowed, false);
});

test('session POST provisions once and subsequent progress requests use its server account', async () => {
  const token = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJkaWQ6cHJpdnk6dGVzdCJ9.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
  const verified = {...identity, subject: 'did:privy:sessionaccount'};
  const adapters = {accounts, verifier: {verify: async (input: string) => input === token ? verified : null}};
  const app = buildApp({logger: false, practiceSessions: adapters, practice: {repository: new PostgresPracticeRepository(pool), authenticate: createPracticeAuthenticator(adapters)}});
  try {
    const headers = {authorization: `Bearer ${token}`};
    const first = await app.inject({method: 'POST', url: '/v1/practice/session', headers, payload: {}});
    assert.equal(first.statusCode, 200, first.body);
    const retry = await app.inject({method: 'POST', url: '/v1/practice/session', headers, payload: {}});
    assert.deepEqual(retry.json(), first.json());
    const progress = await app.inject({method: 'GET', url: '/v1/practice/progress', headers});
    assert.equal(progress.statusCode, 200, progress.body);
    assert.equal(progress.json().revision, 0);
    assert.equal((await accounts.find(verified))?.userId, first.json().userId);
  } finally {await app.close();}
});
