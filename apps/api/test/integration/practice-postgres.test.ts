import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { after, before, describe, test } from 'node:test';
import { Pool } from 'pg';
import { parsePracticeProgress } from '@trimmy/domain';
import type { PracticeProgress } from '@trimmy/domain';
import { buildApp } from '../../src/app.js';
import { PostgresPracticeRepository } from '../../src/postgres-practice-repository.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'), 'Use npm run test:practice-db; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const pool = new Pool({host: socket, port: 65438, database: 'postgres', user: 'trimmy_practice_test_app', max: 3, connectionTimeoutMillis: 3000});
const repository = new PostgresPracticeRepository(pool);
const users = ['00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000005'] as const;
// This adapter exists only in tests. Production receives no fixture identity.
const sessions = new Map(users.map((id, i) => [`Bearer fixture-session-${i}`, id]));
const app = buildApp({logger: false, practice: {repository, authenticate: async request => {
  const userId = sessions.get(request.headers.authorization ?? '');
  return userId ? {userId} : null;
}}});
const fixtures = JSON.parse(readFileSync(new URL('../../../../contracts/practice-progress-v3.json', import.meta.url), 'utf8')) as {cases: {name: string; progress: unknown}[]};
function fixture(name: string): PracticeProgress {
  const entry = fixtures.cases.find(item => item.name === name);
  assert.ok(entry, name);
  return parsePracticeProgress(entry.progress);
}
const firstProgress = fixture('check-the-date-completed');
const closedProgress = fixture('check-the-date-closed');
const firstMutation = '00000000-0000-4000-8000-000000001001';
const firstCommand = {schemaVersion: 1, mutationId: firstMutation, baseRevision: 0, progress: firstProgress};
function get(index: number) {
  return app.inject({method: 'GET', url: '/v1/practice/progress', headers: {authorization: `Bearer fixture-session-${index}`}});
}
function put(index: number, progress: PracticeProgress, baseRevision: number, mutationId = randomUUID()) {
  return app.inject({method: 'PUT', url: '/v1/practice/progress', headers: {authorization: `Bearer fixture-session-${index}`}, payload: {schemaVersion: 1, mutationId, baseRevision, progress}});
}
before(async () => { await app.ready(); });
after(async () => { await app.close(); await pool.end(); });

if (process.env['TRIMMY_PRACTICE_TEST_RECOVERY'] === '1') {
  test('a new API process recovers committed progress and original retry receipt after database restart', async () => {
    const current = await get(0);
    assert.equal(current.statusCode, 200);
    assert.equal(current.json().revision, 2);
    assert.deepEqual(current.json().progress, closedProgress);
    const retry = await put(0, firstProgress, 0, firstMutation);
    assert.equal(retry.statusCode, 200);
    assert.equal(retry.json().revision, 1);
    assert.deepEqual(retry.json().progress, firstProgress);
    assert.equal((await get(0)).json().revision, 2);
  });
} else {
  describe('HTTP and PostgreSQL practice recovery', () => {
    test('verified account starts empty; save/retry returns one durable snapshot', async () => {
      const initial = await get(0);
      assert.equal(initial.statusCode, 200);
      assert.deepEqual(initial.json(), {schemaVersion: 1, revision: 0, progress: null, updatedAt: null});
      const saved = await app.inject({method: 'PUT', url: '/v1/practice/progress', headers: {authorization: 'Bearer fixture-session-0'}, payload: firstCommand});
      assert.equal(saved.statusCode, 200, saved.body);
      assert.equal(saved.json().revision, 1);
      assert.deepEqual(saved.json().progress, firstProgress);
      assert.match(saved.json().updatedAt, /^\d{4}-\d{2}-\d{2}T.*Z$/);
      const retry = await put(0, firstProgress, 0, firstMutation);
      assert.deepEqual(retry.json(), saved.json());
      assert.deepEqual((await get(0)).json(), saved.json());
    });

    test('later progress keeps first answers and retrying the older mutation cannot roll it back', async () => {
      const saved = await put(0, closedProgress, 1);
      assert.equal(saved.statusCode, 200, saved.body);
      assert.equal(saved.json().revision, 2);
      const retry = await put(0, firstProgress, 0, firstMutation);
      assert.equal(retry.statusCode, 200, retry.body);
      assert.equal(retry.json().revision, 1);
      assert.deepEqual((await get(0)).json(), saved.json());
    });

    test('two simultaneous devices produce one winner and one explicit current-snapshot conflict', async () => {
      const responses = await Promise.all([
        put(1, fixture('check-the-date-brief'), 0),
        put(1, fixture('check-the-date-source'), 0),
      ]);
      assert.deepEqual(responses.map(response => response.statusCode).sort(), [200, 409]);
      const winner = responses.find(response => response.statusCode === 200)!;
      const conflict = responses.find(response => response.statusCode === 409)!;
      assert.equal(conflict.json().error.code, 'PRACTICE_REVISION_CONFLICT');
      assert.deepEqual(conflict.json().currentSnapshot, winner.json());
      assert.deepEqual((await get(1)).json(), winner.json());
    });

    test('parallel retries of one mutation commit once even before the first response arrives', async () => {
      const mutation = randomUUID();
      const responses = await Promise.all(Array.from({length: 5}, () => put(2, fixture('empty'), 0, mutation)));
      for (const response of responses) {
        assert.equal(response.statusCode, 200, response.body);
        assert.deepEqual(response.json(), responses[0]!.json());
      }
      assert.equal((await get(2)).json().revision, 1);
    });

    test('completed history cannot be erased or altered by one microsecond; failed saves do not advance', async () => {
      const erased = await put(0, fixture('empty'), 2);
      assert.equal(erased.statusCode, 409, erased.body);
      assert.equal(erased.json().error.code, 'PRACTICE_HISTORY_CONFLICT');
      const changed = JSON.parse(JSON.stringify(closedProgress));
      changed.completions['check-the-date'].completedAt = '2026-09-14T10:20:30.123457Z';
      const altered = await put(0, parsePracticeProgress(changed), 2);
      assert.equal(altered.statusCode, 409, altered.body);
      assert.equal(altered.json().error.code, 'PRACTICE_HISTORY_CONFLICT');
      assert.deepEqual((await get(0)).json().progress, closedProgress);
      assert.equal((await get(0)).json().revision, 2);
    });

    test('mutation identifiers bind to the original body including its base revision', async () => {
      for (const [progress, revision] of [[closedProgress, 0], [firstProgress, 2]] as const) {
        const response = await put(0, progress, revision, firstMutation);
        assert.equal(response.statusCode, 409, response.body);
        assert.equal(response.json().error.code, 'PRACTICE_IDEMPOTENCY_CONFLICT');
      }
      assert.equal((await get(0)).json().revision, 2);
    });

    test('untrusted identity fields and headers cannot select or disclose another account', async () => {
      const denied = await app.inject({method: 'GET', url: '/v1/practice/progress', headers: {'x-user-id': users[0]}});
      assert.equal(denied.statusCode, 401);
      const forged = await app.inject({method: 'PUT', url: '/v1/practice/progress', headers: {authorization: 'Bearer fixture-session-1'}, payload: {...firstCommand, userId: users[0]}});
      assert.equal(forged.statusCode, 400);
      const ignored = await app.inject({method: 'GET', url: '/v1/practice/progress', headers: {authorization: 'Bearer fixture-session-1', 'x-user-id': users[0]}});
      assert.equal(ignored.statusCode, 200);
      assert.equal(ignored.json().revision, 1);
      assert.deepEqual(ignored.json().progress.completions, {});
      assert.equal(ignored.body.includes('2026-09-14T10:20:30.123456Z'), false);
    });

    test('database account scope clears on pool reuse and never grants financial-table access', async () => {
      const client = await pool.connect();
      try {
        assert.equal((await client.query('SELECT * FROM trimmy.practice_progress')).rowCount, 0);
        await client.query('BEGIN');
        await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [users[0]]);
        const own = await client.query('SELECT user_id, revision FROM trimmy.practice_progress');
        assert.equal(own.rowCount, 1);
        assert.equal(own.rows[0].user_id, users[0]);
        assert.equal((await client.query('SELECT * FROM trimmy.practice_progress WHERE user_id = $1', [users[1]])).rowCount, 0);
        await client.query('ROLLBACK');
        assert.equal((await client.query('SELECT * FROM trimmy.practice_progress')).rowCount, 0);
        for (const table of ['users', 'assets', 'financial_intents']) {
          await assert.rejects(client.query(`SELECT * FROM trimmy.${table}`), {code: '42501'});
        }
      } finally { await client.query('ROLLBACK'); client.release(); }
    });

    test('closed and nonexistent accounts fail; a financial restriction does not block practice', async () => {
      assert.equal((await get(4)).statusCode, 404);
      await assert.rejects(repository.get('00000000-0000-4000-8000-000000000099'), {code: 'PRACTICE_ACCOUNT_NOT_FOUND'});
      const restricted = await get(3);
      assert.equal(restricted.statusCode, 200);
      assert.equal(restricted.json().revision, 0);
    });

    test('migration-owner and reachable RLS-bypass credentials are refused before reading account data', async () => {
      for (const user of ['trimmy_test_owner', 'trimmy_practice_test_unsafe']) {
        const unsafePool = new Pool({host: socket, port: 65438, database: 'postgres', user, max: 1, connectionTimeoutMillis: 3000});
        try {
          await assert.rejects(new PostgresPracticeRepository(unsafePool).get(users[0]), {code: 'PRACTICE_RUNTIME_ROLE_INVALID'});
        } finally { await unsafePool.end(); }
      }
    });

    test('live financial mutations remain disabled with working practice persistence', async () => {
      for (const url of ['/v1/gifts', '/v1/swaps', '/v1/wallets']) {
        const response = await app.inject({method: 'POST', url, headers: {authorization: 'Bearer fixture-session-0'}, payload: {amount: '1'}});
        assert.equal(response.statusCode, 503);
        assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
      }
      const config = (await app.inject({method: 'GET', url: '/v1/config'})).json();
      assert.equal(config.practiceSyncEnabled, true);
      assert.equal(config.capabilities.financialOperationsEnabled, false);
      assert.equal(config.capabilities.persistenceEnabled, false);
    });
  });
}
